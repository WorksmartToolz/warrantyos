# WarrantyOS — Architectural Reference (v2, Prototype Phase)

> **Draft status:** v2 in progress. This document expands and completes v1
> (`architecture-reference.md`); it does not replace v1's decisions. v1 remains
> the anchor until v2 is complete and reviewed, at which point v2 is promoted to
> the canonical `architecture-reference.md`. Sections are marked with an
> implementation status: **Implemented** (exists in code today), **Designed**
> (architecturally locked, not yet built), or **Deferred** (planned, not yet
> designed in detail).
>
> **Section ordering note:** v1's identity sections — "What This Platform Is,"
> the Core Operational Philosophy principles, and Core Identifiers — precede
> this content in the final document. They are carried forward from v1 and
> integrated in a later drafting pass. v2 currently opens with foundational
> patterns (Tier 1) because those are drafted first per the Phase 3 dependency
> order; the anchor sections will be slotted ahead of them before the swap.

---

## Standard RLS Pattern

**Status: Implemented** (the core pattern across `tenants`, `users`,
`invitations`; the `tenant_id` denormalization convention is **Designed**,
locked by Decisions 3 and 5, applying to child tables not yet built).

WarrantyOS is multi-tenant: every row of tenant-owned data belongs to exactly
one tenant, and no user may read or write another tenant's data. This isolation
is enforced at the database layer through PostgreSQL Row-Level Security (RLS),
not left to application code alone. The pattern below is the single convention
every tenant-scoped table follows. It is documented here because the Phase 1
audit found it fully implemented but unwritten — future tables must follow it
rather than re-deriving it, and a prior incident (a table with missing grants
that PostgREST could not see at all) traces directly to the pattern being
undocumented.

### The tenant lookup helper

Isolation hinges on one `SECURITY DEFINER` helper function,
`public.get_user_tenant_id()`. It looks up the calling user's tenant from
`public.users`, matching `auth.uid()`, and returns NULL for any user who is not
active or has been removed. For a suspended or removed user the NULL return
causes every tenant-scoped policy that compares against it to evaluate false —
the user sees nothing. This is deliberate defense-in-depth: access falls closed,
not open, when a user's standing lapses.

```sql
create or replace function public.get_user_tenant_id()
returns uuid
language sql
security definer
stable
set search_path = public
as $$
  select tenant_id
  from public.users
  where id = auth.uid()
    and status = 'active'
    and removed_at is null
$$;
```

Two hardening details are load-bearing and must be preserved in any change to
this function. `set search_path = public` (added in migration 002) prevents
search-path injection — without it, a malicious schema earlier on the path
could shadow `public.users`. The `status = 'active' and removed_at is null`
filters (added in migration 004) are what make access fall closed for lapsed
users; dropping them would let a suspended user retain tenant visibility.

### The checklist every tenant-scoped table follows

Every new tenant-scoped table must do all six of the following. Omitting any one
of them is a defect; the missing-grants incident is the cautionary precedent.

1. **Include the tenant foreign key.** A
   `tenant_id uuid not null references public.tenants(id)` column. No
   tenant-scoped row exists without an owning tenant.
2. **Enable RLS.** `alter table ... enable row level security`. Without this,
   the policies below are never consulted and the table is wide open.
3. **Add the SELECT policy** scoping reads to the caller's tenant (shown below).
4. **Keep writes service-role only, with one narrow exception.** No user-facing
   INSERT or DELETE policies, and UPDATE only where a user must edit their own
   row. All other mutations go through `createAdminClient()` in a Server Action,
   where application-layer authorization decides what the user may do. The
   database does not grant general write access to authenticated users; the
   Server Action is the gate. The one live exception is on `users`: the policy
   "users: members can update their own profile" (`using (id = auth.uid())`)
   lets a user edit their own profile row directly. A new table should add a
   user-facing write policy only for a comparably narrow self-service case;
   otherwise writes stay service-role only.
5. **Add the grants.** `grant all on <table> to anon, authenticated,
   service_role`. PostgREST requires these for its schema cache; a table without
   them is invisible to the API layer even though it exists. This is the step
   the prior incident skipped.
6. **Decide on a self-read exception.** Most tables need none — see the `users`
   exception below for the one case that does.

The representative SELECT policy, applied to every tenant-scoped table (policy
named in the live convention, `<table>: <who> can <action>`):

```sql
alter table public.<table_name> enable row level security;

create policy "<table_name>: members can view their tenant's rows"
  on public.<table_name>
  for select
  using (tenant_id = public.get_user_tenant_id());

grant all on public.<table_name> to anon, authenticated, service_role;
```

For reference, the live policies following this pattern are
"tenants: members can view their own tenant" (scoped on `id`, since `tenants` is
the tenant itself), "users: members can view users in their tenant", and
"invitations: members can view their tenant's invitations".

### The `users` self-read exception

The `users` table carries an additional SELECT policy beyond the standard
tenant-scoped one, named "users: authenticated can read their own profile":

```sql
create policy "users: authenticated can read their own profile"
  on public.users
  for select
  using (id = auth.uid());
```

This exists so the middleware can read a user's own row — specifically their
status — even when that user is suspended or removed and `get_user_tenant_id()`
would return NULL for them. PostgreSQL ORs multiple SELECT policies together, so
the self-read widens access for that one row without affecting tenant scoping
elsewhere. A new table needs an exception like this only if something must read
its rows in a context where the normal tenant lookup is unavailable; this is
rare, and `users` is currently the only case.

### The `tenant_id` denormalization convention for child tables

A child table whose parent is itself tenant-scoped could derive its tenant by
joining through the parent on every policy evaluation. WarrantyOS does not do
this. Instead, tenant-scoped child tables **denormalize `tenant_id` directly**
onto the child row, so the SELECT policy compares a local column rather than
joining. The tradeoff is a redundant column carrying a stay-in-sync invariant —
any write that creates or updates the child's `tenant_id` must verify it matches
the parent's, enforced application-layer in the Server Action wrapper (a
cross-table CHECK constraint is awkward in PostgreSQL, so this invariant lives in
code, not the database). The benefit is simpler RLS policies and faster read
paths on high-read tables.

This convention was established by Decision 3 (`custom_field_values`) and
Decision 5 (`warranty_registrations`), and applies to every future child table
whose parent is also tenant-scoped. `custom_field_values` is the precedent
specifically called out for high-read child tables.

---

## Stateless Tokenized Interaction Pattern

**Status: Designed** (the tokenized-link mechanism is **Implemented** for team
invitations; its application to claim intake, registration assignees, and
delivery reporting is **Designed**, locked by Decision 1 and Item 17).

Some parties WarrantyOS must interact with are not platform users and never will
be: the customer filing a claim, the subcontractor PM a registration is assigned
to, the buyer-installer reporting a delivery date. They have no account, no
login, and no reason to acquire one for a single bounded interaction. The
Stateless Tokenized Interaction Pattern is how WarrantyOS gives such a party
time-bound access to one focused task without an account.

This generalizes v1's Stateless Customer Interaction principle. v1 framed it as
customer-only ("customers do not have platform accounts; all customer engagement
is via tokenized email links"). Decision 1 widened it: the same mechanism serves
any non-authenticated party, not just customers. The principle is unchanged in
spirit — it is now named as a reusable pattern rather than a customer-specific
rule.

### The mechanism

A tokenized email link carries a high-entropy, single-purpose token that grants
the recipient access to one focused interface — a claim intake form, an assignee
acceptance form, a delivery-date report — with no account and no session
persistence beyond the link itself. Each interaction is structurally
independent: the token identifies the one record and the one action, nothing
more. The token is time-bound (it expires) and consumable (it records when it
was used).

The implemented precedent is the team invitation flow. The `invitations` table
already carries the shape this pattern generalizes: a 64-character hex token
(32 random bytes), an `expires_at` timestamp, and a `consumed_at` timestamp that
records single use. New stateless interfaces follow this same shape — a
high-entropy token, an expiry, and a consumption record — rather than inventing
a parallel mechanism. The invitation token authenticates a future *user*; the
stateless interfaces here authenticate a *party who will never be a user*, but
the token mechanics are the same. The `invitations` table is the *shape* to
copy, not a shared store: each surface keeps its own token on its own record —
a claim intake token on the claim, an assignee token on the assignment, a
delivery-report token on the project — rather than routing through
`invitations`. Audit Topic 9 flagged this for claim intake specifically: the
intake token is "similar to invitation token but customer-facing," meaning same
shape, separate storage.

### Where the pattern applies

Four interaction surfaces use this pattern. All four are the same mechanism
applied to different parties and tasks:

- **Claim intake (customer-facing).** A customer files a claim through a
  tokenized link to an intake form. This is v1's original use.
- **Registration assignee submission (assignee-facing).** When a registration is
  assigned to a directory contact (rather than a tenant user), the contact
  receives a tokenized link to an acceptance/submission form. Decision 1's
  dual-FK assignee model routes by FK type: a contact assignee gets the
  tokenized link; a tenant-user assignee gets an in-app notification through
  their existing login. The pattern covers only the contact case — tenant users
  are authenticated and do not need it.
- **Supply-only delivery reporting (buyer-facing).** Under Item 17's
  `delivery_report_tokenized` trigger source, the buyer-installer reports the
  delivery date — which sets the warranty trigger — through a tokenized form.
  The form is sent when the project is created at sale time and remains open
  until the buyer reports the date. This is the warrantor's first and only
  channel for learning a delivery date it cannot otherwise observe; the pattern
  is the mechanism, and Item 17's overdue-escalation handling (the
  `trigger_confirmation_overdue` clock event) backstops a buyer who never
  responds.
- **Future stateless workflows.** The pattern is explicitly extensible. Any
  future interaction with a non-authenticated party — additional customer touch
  points, other third-party submissions — uses this same mechanism rather than a
  new one.

### Why a pattern and not per-feature plumbing

Naming this as one pattern, rather than building each tokenized surface
independently, means the token mechanics (entropy, expiry, single-use
consumption, the focused single-record interface) are decided once and reused.
The alternative — each feature rolling its own link mechanism — risks
inconsistent expiry handling, inconsistent consumption semantics, and a wider
surface of one-off security decisions. One pattern, applied four-plus times,
keeps the security-relevant mechanics uniform.

## Cache Invalidation Pattern

**Status: Implemented** (the path-based pattern is live for team mutations; the
tag-based evolution noted below is **Deferred**).

WarrantyOS renders most of its UI through Next.js Server Components, which Next
caches. When a mutation changes underlying data, the cached renders that display
that data go stale and must be explicitly revalidated, or the user sees old
state after their own action. This pattern is the convention for which paths a
mutation revalidates.

### The rule

When a Server Action mutates data, it revalidates two things on success: the
specific page that displays the mutated record, **and** any parent path that
aggregates or summarizes that data. The second half is the easy one to forget —
a mutation often changes both a detail view and a dashboard count, and
revalidating only the detail view leaves the dashboard stale.

### The implemented precedent

Team mutations are the live example, introduced in Session 5e. A local helper
revalidates two paths:

```ts
function revalidateTeamPages() {
  revalidatePath('/app/team')
  revalidatePath('/app')
}
```

It is called on the success of every team mutation — `changeRole`, `suspend`,
`reactivate`, `remove`, `cancelInvite` — and the same two paths are revalidated
on successful invitation creation. The reasoning maps directly to the rule:
`/app/team` renders the team roster (the detail view), and `/app` renders the
dashboard with aggregate member and seat-count stats (the parent that
summarizes). A team mutation changes both, so both are revalidated.

### Applying it to future mutations

Every new mutating Server Action must identify its own revalidation targets the
same way: the page that shows the record, plus any parent that aggregates it.
Claim creation, warranty registration, project creation, and role changes that
affect claim queues will each have their own pair (or set) of paths — the team
pattern is the template, not the literal target list. Identifying these targets
is part of writing each mutation, not an afterthought.

### Evolution point: path-based to tag-based

All invalidation today is path-based (`revalidatePath`); no tag-based
invalidation (`revalidateTag`) exists yet. Path-based is adequate while the set
of pages affected by any given mutation is small and obvious. As the app grows
and a single data type appears across many pages — claims on a queue, a detail
view, a dashboard, a report — listing every affected path per mutation becomes
brittle. At that point a tag-based approach (`revalidateTag('claims')`,
`revalidateTag('projects')`) is the more maintainable model: a mutation
invalidates a tag, and every page that reads that tag refreshes without the
mutation needing to know the page list. This is a noted future evolution, not a
current requirement — path-based is correct for now, and the switch happens when
the path lists start to hurt.

## Feature Flag System

**Status: Designed** (locked by Phase 0 Item 18; not yet built. The storage
mechanism is an open Phase 3 implementation choice, noted below.)

Tenants operate in different business shapes — pure EPC, pure supply-only, or
hybrid. If every tenant got every workflow by default, a pure-EPC firm's
reviewers would see supply-only surfaces (a "delivery report awaiting" view)
they will never act on: bad onboarding, weak sales positioning. The feature flag
system lets WarrantyOS enable or disable workflows per tenant. It is foundational
architecture, not a bolt-on — the same logic that justified multi-tenancy from
day one: cheap to bake in early, a painful retrofit later. It sits in Tier 1
alongside the RLS, tokenized-interaction, and cache patterns.

### The four parts

**1. Storage.** Per-tenant feature configuration lives either in a JSONB key,
`tenants.settings.enabled_features`, or in a dedicated `tenant_features` table.
This choice is an open Phase 3 implementation detail, not yet decided. JSONB is
the lighter starting point. A dedicated table is the natural upgrade if feature
config turns out to need independent operational characteristics — its own audit
trail of who toggled what and when. The rest of this section is written to hold
either way; where storage specifics matter, both options are noted.

**2. Application-layer helper.** A single function —
`lib/core/features/is-feature-enabled.ts` or equivalent — takes a `tenantId` and
a feature identifier and returns a boolean. Server Actions call it before
allowing a feature-gated operation; Server Components call it before rendering
feature-gated UI. It is the single source of truth for "is this feature on for
this tenant." No Server Action or component reads the flag storage directly —
they all go through the helper, so the storage choice above stays encapsulated
behind one function.

**3. Platform admin toggle surface.** Platform admins toggle features per tenant
through the existing `/admin/tenants/<id>/` surface (a new sub-page or section,
drafted now / built in Phase 4). Toggling is **platform-admin-only**. Tenant
Team Admins cannot configure feature flags — feature availability is a
platform-business decision (what is sold to which tenant), not tenant
self-service. Team Admins see only the features enabled for their tenant; they
can neither enable disabled ones nor disable enabled ones.

The outcome — only a platform admin can toggle — is the same under either
storage choice, but the enforcement *mechanism* follows the storage decision:

- **Dedicated `tenant_features` table:** a genuine RLS UPDATE policy on that
  table restricts UPDATE to the platform admin role. This is the clean fit Item
  18 describes.
- **JSONB on `tenants` (`settings.enabled_features`):** there is no user-facing
  UPDATE policy to scope, because `tenants` already follows the Standard RLS
  Pattern's writes-are-service-role-only rule (see the RLS section above — the
  one live user-facing UPDATE exception is on `users`, not `tenants`). So in the
  JSONB case, platform-admin toggling goes through a service-role write in a
  Server Action, gated by an application-layer platform-admin check — not
  through an RLS UPDATE policy scoped to a platform-admin role. Restricting a
  user-UPDATE that doesn't exist would be meaningless.

Item 18 states the RLS-UPDATE restriction generically; v2 is more precise here
because the generic statement collides with the Standard RLS Pattern in the
JSONB case. The enforcement is matched to the storage, the outcome is identical
either way.

**4. Defaults at provisioning.** Tenant provisioning
(`lib/core/provision-tenant.ts`) seeds the default feature set. The model is
**opt-out**: at provisioning, both `epc_workflow` and `supply_only_workflow` are
enabled. A platform admin disables one selectively if the tenant is pure-shape.
This favors discoverability — a new tenant sees all workflows and scopes down —
over minimalism, where each tenant would have to opt into each workflow at
provisioning.

### Phase 1 features

Two flags ship in Phase 1:

- **`epc_workflow`** — gates the EPC trigger sources (`contractual_date_manual`,
  `wbs_integration`) and EPC-specific UI: WBS integration configuration,
  milestone date entry, EPC-flavored registration prep flows.
- **`supply_only_workflow`** — gates the supply-only trigger sources
  (`delivery_report_tokenized`, `delivery_report_api`) and supply-only-specific
  UI: delivery-reporting form configuration, overdue-trigger escalation surfaces,
  supply-only-flavored registration prep flows.

Both default to enabled. Hybrid tenants leave both on; pure-shape tenants disable
the one they don't use.

### How flags gate the trigger model (defense-in-depth)

The feature flags gate Item 17's multi-source trigger model through the
**Defense-in-Depth Pattern** — the same convention Decision 6 used for anchor
warranty type protection. Three layers, with the database deliberately the most
permissive:

- **Schema layer (permissive).** The `trigger_source` column accepts all four
  Phase 1 enum values regardless of any tenant's feature configuration. The
  database does not enforce feature gating.
- **Application layer (the gate).** Before creating a project with an EPC
  trigger source (`contractual_date_manual`, `wbs_integration`), the Server
  Action checks `isFeatureEnabled(tenantId, 'epc_workflow')`; likewise
  `supply_only_workflow` for the supply-only sources. This is where a disabled
  feature actually blocks an operation.
- **UI layer (the filter).** Project creation forms render only the trigger
  sources whose flag is enabled. A pure-EPC tenant never sees delivery-report
  options; a pure-supply-only tenant never sees milestone date entry.

Schema permissive, application and UI enforcing, is the same shape Decision 6
used for anchor types (the schema allows the `is_system` values; the application
and a trigger enforce permanence). Both are instances of the Defense-in-Depth
Pattern — the database guarantees nothing about feature gating, so the
guarantee lives where it can be reasoned about and changed without a migration.

### Audit logging

Feature flag changes are audit-quality events under the Defensibility principle.
The audit trail captures `tenant_id`, `feature`, `old_value`, `new_value`,
`changed_by` (the platform admin's user id), and `changed_at`.

### Extensibility

The system is designed to take new flags without restructuring. Candidates noted
for later — none of them Phase 1 — include `claim_intake_advanced_workflows`
(extended intake forms beyond the Phase 1 minimum), `ala_signature_capture` (an
ALA signature workflow if introduced), and `customer_portal` (a future
customer-facing portal beyond tokenized links). They are listed only to fix the
naming convention early and confirm the system anticipates growth; each becomes
real when its own architectural decision is made.

## Unified Contacts Directory

**Status: Designed** (Phase 0 Item 16, added during Decision 1; not yet built.
`contacts` is one of the Phase 3 tables to be migrated.)

WarrantyOS interacts with many parties who are not platform users: customers and
their contacts, subcontractors and theirs, vendors and theirs, and the people a
registration gets assigned to. Rather than scatter these across parallel
type-specific tables, Item 16 consolidates them into one per-tenant `contacts`
table with a `contact_type` discriminator. Catching this consolidation now —
before any of the entity tables that reference contacts are built — avoids a
later migration to unify parallel tables.

### Shape

A per-tenant `contacts` table, following the Standard RLS Pattern (tenant-scoped,
`tenant_id` FK, RLS-enabled, service-role writes). A `contact_type` column
discriminates the kind of contact. The Phase 1 categories are:

- `customer`
- `customer_contact`
- `subcontractor`
- `subcontractor_contact`
- `vendor`
- `vendor_contact`
- `registration_assignee`
- `other`

This is a single-table approach for the prototype. The alternative — a separate
table per contact kind — is held in reserve: specialized tables are introduced
only if type-specific fields proliferate to the point that one shared shape
stops fitting. Until then, one table with a discriminator is simpler to query,
simpler to import into, and simpler to reference.

### Tenant users are not contacts

Tenant users (`public.users`) stay separate from the contacts directory. They
are not a `contact_type`. The reason is that auth and RLS implications differ: a
`public.users` row is backed by a Supabase Auth account, participates in the
login and session machinery, and is the subject of `get_user_tenant_id()`; a
contact is a directory record with no account and no login. Conflating them
would entangle the auth model with what is really just an address book. This
separation is what makes the dual-FK assignee model (Decision 1) necessary: an
assignee can be *either* a directory contact *or* a tenant user, and the two are
referenced by different foreign keys precisely because they are different kinds
of thing.

### How other entities reference contacts

Contacts is a foundational table that several entity sections reference, using
the FK + Snapshot Pattern. The mechanics of that pattern — the CHECK constraint
on dual-FK, the snapshot-at-association-time-never-updated-on-read behavior, and
why both exist — are defined once in the FK + Snapshot Pattern section, not
restated here. What matters for the contacts directory is which entities point
at it and in which of the two shapes:

- **Single-FK** — the referenced party is always a directory contact. Example:
  `projects.customer_id` references `contacts(id)`.
- **Dual-FK** — the referenced party can be a directory contact *or* a tenant
  user, so two FKs appear. Example:
  `warranty_registrations.assigned_to_contact_id` alongside `assigned_to_user_id`.

See the FK + Snapshot Pattern section for how the snapshot columns and
constraints work in each shape.

### Import tracking

The data migration tooling (Decision 8) populates contacts during onboarding.
The `contacts` table therefore carries an `imported_via_batch_id` column
(nullable FK to `import_batches`) so an imported contact can be traced to the
batch that created it. Phase 1 import covers `customer` and `customer_contact`
records specifically; the other contact types are added during normal tenant
operation rather than at import. The data migration section covers the import
mechanics; the relevant point here is that the contacts schema accommodates
import provenance from the start.

## Custom Field System

**Status: Designed** (locked by Decision 3; not yet built.
custom_field_definitions and custom_field_values are Phase 3 tables to be
migrated. The rich-text field type depends on Decision 4, also locked.)

Tenants need to capture data the base schema doesn't anticipate — fields that
vary by warrantor, by workbook, by import source. The custom field system lets a
Team Admin define extra fields on certain entities without a schema change, and
lets Reviewers and Viewers fill and read them. The design is locked by Decision
3; this section documents it.

### Two tables: definitions and values

A custom_field_definitions row declares a field: which entity type it attaches
to, its label, its type, whether it is required, dropdown options if applicable,
and display order. A custom_field_values row holds one filled-in value for one
entity instance, linked to its definition. The two table sketches:

    custom_field_definitions
      id              uuid PK
      tenant_id       uuid FK to tenants
      entity_type     text  (project | warranty_registration | claim)
                            (CHECK constraint enforcing allowed values)
      label           text NOT NULL
      field_type      text  (one of 11 Phase 1 types)
      required        boolean NOT NULL DEFAULT false
      options         jsonb  (dropdown options, null otherwise)
      display_order   integer NOT NULL DEFAULT 0
      deleted_at      timestamptz nullable  (soft-delete discriminator)
      created_at      timestamptz
      updated_at      timestamptz

    custom_field_values
      id                          uuid PK
      tenant_id                   uuid FK to tenants  (denormalized for RLS)
      definition_id               uuid FK to custom_field_definitions
      project_id                  uuid nullable FK to projects
      warranty_registration_id    uuid nullable FK to warranty_registrations
      claim_id                    uuid nullable FK to claims
      value                       jsonb  (type-safe per definition.field_type)
      created_at                  timestamptz
      updated_at                  timestamptz
      (CHECK: exactly one of the three entity FKs is non-null)
      (CHECK / app-layer: tenant_id matches definition's tenant_id)

### Phase 1 entity scope: three entities

Custom fields attach to exactly three entities in Phase 1: projects, warranty
registrations, and claims. The entity_type column on a definition, and a CHECK
constraint, enforce that set. The three were chosen because each has a concrete
MVP need: data migration requires project-level custom fields for import column
mapping; claim intake requires them for the variance the six intake workbooks
introduce; registrations need them for tenant-specific Section 7 capture.
Entities that do not yet exist, or whose customization happens by another
mechanism, are deliberately excluded — inspections customize through their
inspection_report JSONB, warranty type coverages are tightly scoped to
start/end/term, contacts are mostly fixed shape, and ALA documents / work plans /
costs have no base schema yet. Audit trail entries are excluded on principle:
tenant customization would muddy the audit.

### Typed FK columns, not a polymorphic key

A value links to its entity through one of three typed, nullable foreign key
columns — project_id, warranty_registration_id, claim_id — with a CHECK
constraint enforcing that exactly one is non-null. This is the same typed-FK plus
CHECK approach Decision 1 used for assignees, chosen over a polymorphic
(entity_type, entity_id) key because it gives real referential integrity and
lets ON DELETE CASCADE work per entity, and it keeps the codebase consistent with
the pattern already in use.

### Denormalized tenant_id

custom_field_values carries its own tenant_id rather than deriving it by joining
through custom_field_definitions on every read. This is the tenant_id
denormalization convention from the Standard RLS Pattern section —
custom_field_values is the named precedent for it. The cost is a redundant column
with a stay-in-sync invariant: a value's tenant_id must match its definition's,
enforced application-layer at insert time.

### Soft-delete on definitions

Definitions soft-delete via a deleted_at discriminator; they are never
hard-deleted through the UI. When a definition is soft-deleted: its existing
values remain queryable for historical display and reporting; the definition-list
UI filters it out; new entity edit forms stop rendering its input. Existing values
do not migrate or detach — they stay attached to the now-hidden definition. This
aligns with both the Defensibility principle (historical values stay queryable)
and the Soft Remove principle already used for tenant users. Hard-delete would
orphan historical values or cascade-destroy auditable data; it is available only
through admin tooling if ever genuinely needed, never through the Phase 1 UI.

### The 11 Phase 1 field types

Address, phone, date, number, plain text, rich text, dropdown, email, URL,
checkbox, file upload. Three more — signature, multi-select, currency — are
deferred to Phase 2.

One of these, rich text, depends on Decision 4: its stored format is
ProseMirror-compatible JSON (the TipTap editor's storage), with the format chosen
deliberately so the stored data outlives any specific editor library. The Custom
Field System defines that rich text is a field type; the Rich Text Storage
section (Decision 4) defines how its value is stored and bounded. A custom field
UI renders a different input per field_type — a single-line box for plain text,
the TipTap editor for rich text, a picker for dropdown, and so on.

### Who creates and who consumes

Team Admins create and manage definitions; Reviewers and Viewers consume them —
filling values on entity records, reading them back. Definition management is a
tenant-admin capability; value entry is part of ordinary operational work.
## FK + Snapshot Pattern
**Status: Designed** (convention established by Decisions 1 and 8; applies to
tables not yet built — projects, warranty_registrations).
WarrantyOS warranties run on long horizons — up to 25 years. Over that span the
people and organizations a record refers to change: a subcontractor's contact
person leaves, a customer's phone number changes, a directory record is edited.
Two needs collide. Audit defensibility demands that a record show who it referred
to at the moment it was created or assigned, frozen, even if the directory entry
later changes. Operational reuse demands a live link to the current directory
record, so the same subcontractor can be reused across many registrations and
reporting can roll up by contact. The FK + Snapshot Pattern satisfies both: a
foreign key to the canonical directory record gives the live link, and snapshot
columns captured at association time give the frozen historical attribution.
This is a named Phase 2 convention. It is referenced today by the Unified
Contacts Directory section, and will be referenced by the forthcoming Project,
Warranty Registration, and Claim Intake sections (Tier 2 and Tier 3). The
mechanics are defined here once.
### The core rule
A row that references a party stores both a foreign key to the canonical record
and snapshot columns holding that party's identifying details. The snapshot is
written by the system at assignment or association time, never updated on read,
and never re-synced when the underlying directory record changes. The FK can
drift as the directory is edited; the snapshot cannot. Reading the FK gives the
current truth; reading the snapshot gives the truth as of association.
### Two shapes
The pattern appears in two shapes, depending on whether the referenced party is
always a directory contact or could also be a tenant user.
Single-FK (Decision 8) — the referenced party is always a directory contact.
One FK, plus snapshot columns. The example is a project's customer:
    projects
      ...
      customer_id              uuid nullable FK -> contacts(id)
      customer_name_snapshot   text
      customer_email_snapshot  text
      customer_phone_snapshot  text
      -- snapshots captured at project creation
Dual-FK (Decision 1) — the referenced party can be either a directory contact
OR a tenant user, because the two are different kinds of thing (the Unified
Contacts Directory section explains why tenant users are not contacts). Two
nullable FKs, a CHECK enforcing exactly one non-null, plus snapshot columns.
The example is a registration's assignee:
    warranty_registrations
      ...
      assigned_to_contact_id      uuid nullable FK -> contacts(id)
      assigned_to_user_id         uuid nullable FK -> public.users(id)
      -- CHECK: exactly one non-null when assigned; both null when unassigned
      assigned_to_name_snapshot   text nullable
      assigned_to_email_snapshot  text nullable
      assigned_to_phone_snapshot  text nullable
      assigned_at                 timestamptz nullable
In the dual-FK shape the FK type drives downstream behavior: a contact assignee
is reached through the Stateless Tokenized Interaction Pattern (a tokenized email
link), while a tenant-user assignee is reached through an in-app notification on
their existing login. Reassignment can cross types — a contact PM can be
reassigned to a Reviewer for self-handling, or the reverse.
### Why not FK-only or snapshot-only
FK-only fails audit defensibility: once the directory record is edited, the
historical truth of who a 20-year-old registration was assigned to is gone.
Snapshot-only fails operational reuse and reporting: there is no live link, so
the same recurring subcontractor cannot be recognized across registrations and
contacts cannot be rolled up. The pattern keeps both because warranty operations
genuinely need both over the long horizon.

## Clock Event Infrastructure

**Status: Designed** (locked by Decision 9; not yet built. clock_events is a
Phase 3 table to be migrated; pg_cron enablement and the cron handler function
are Phase 3 build-time work. Item 17's event-type additions apply.)

WarrantyOS has time-bound state transitions: registration prep fires a known
lead time before a project's trigger date, an information request expires after
a response window, a warranty coverage approaches its end date and someone needs
to know. v1 named this the System-Managed Clock principle and asserted the
platform manages all deadlines, not reviewers. Decision 9 chose the mechanism
that backs that principle. This section documents it.

### What runs the clock: pg_cron

pg_cron is the trigger mechanism. It is a PostgreSQL extension that runs
scheduled jobs from inside the database, not from the hosting layer. Supabase
Pro tier enables it. The choice is principle-aligned three ways: it lives where
the System-Managed Clock principle says it should (in the database, structurally
inseparable from the data), it survives hosting changes (Vercel today, anything
tomorrow — pg_cron stays), and it puts scheduling on the same audit footing as
data changes.

One concern with database-resident jobs is code visibility — a job scheduled
through a hidden interface is hard to find later. The mitigation is convention:
every scheduled job is defined in a version-controlled migration alongside its
supporting function. New contributors find schedules by reading the migrations
directory, not by inspecting the running database.

The cron runs hourly, on the schedule '0 * * * *'. This captures hour-precision
deadlines (information request response windows) with at most one hour of slack,
and day-precision events (registration prep, warranty expiry warnings) fire
reliably. Tighter precision is revisited if real usage shows the need.

### The record: clock_events

A clock_events table records every scheduled event — what fires, when, against
which entity, with what status. The table is inspectable (a pending-events query
shows what is coming), auditable (every firing leaves a permanent row with its
fired_at timestamp), and decoupled from entity state (cancelling an event is a
status update on this table, not a mutation on the underlying entity).

    clock_events
      id              uuid PK
      tenant_id       uuid NOT NULL FK -> tenants
      event_type      text NOT NULL
                      -- see event-type enum below
                      -- CHECK constraint enforces allowed values
      entity_type     text NOT NULL
                      -- 'project' | 'claim' | 'warranty_coverage'
                      -- | (extensible)
                      -- CHECK constraint enforces allowed values
      entity_id       uuid NOT NULL
      fires_at        timestamptz NOT NULL
      status          text NOT NULL DEFAULT 'pending'
                      -- 'pending' | 'fired' | 'cancelled' | 'failed'
      fired_at        timestamptz nullable
      failure_reason  text nullable
      payload         jsonb  -- event-type-specific context, validated
                             -- at write time per event type
      created_at      timestamptz
      updated_at      timestamptz

Three indexes support the access patterns:

    CREATE INDEX clock_events_pending_fires_at_idx
      ON clock_events (fires_at)
      WHERE status = 'pending';
    CREATE INDEX clock_events_tenant_idx ON clock_events (tenant_id);
    CREATE INDEX clock_events_entity_idx
      ON clock_events (entity_type, entity_id);

The partial index on pending fires_at is the load-bearing one — the cron
handler queries it every hour to find what to dispatch, and the partial filter
keeps the index small as fired and cancelled events accumulate.

### Phase 1 event types

The event_type enum is extensible. Phase 1 includes:

- registration_prep_pre_trigger — fires registration_lead_time_days before a
  known trigger date. Used for EPC trigger sources (contractual_date_manual and
  wbs_integration), where the trigger date is known in advance and prep can be
  scheduled. This is Item 17's renaming and specialization of Decision 9's
  original registration_prep.
- info_request_due — fires when an information request's response window
  expires. Hour-precision. From Decision 9's Phase 1 enum.
- warranty_expiry_warning — fires before a warranty coverage's end date, so
  someone is notified in time to act. From Decision 9's Phase 1 enum.
- trigger_confirmation_overdue — fires when a project's expected trigger window
  has passed without confirmation. Used primarily for the
  delivery_report_tokenized trigger source, escalating to platform admins and
  team admins when a buyer has not reported delivery. The overdue threshold
  defaults to (delivery window + grace period), both tenant-configurable, with
  sensible Phase 3 defaults to be set during supply-only-flow drafting. Added
  by Item 17.

### Not every transition is a clock event

A clock event represents something that will fire in the future. Synchronous
transitions — things that happen now, in response to a Server Action — do not
go through clock_events. The clearest example is registration prep on supply-
only confirmation: when trigger_status advances to confirmed (because the buyer
reported delivery, or the WBS poller detected the milestone), the Server Action
handling that transition creates the warranty registration immediately, without
scheduling a clock event. The clock_events table is reserved for future-firing
events; synchronous effects belong in the Server Action that caused them.

This applies to both supply-only flows (where confirmation is the trigger
event itself) and to wbs_integration flows (where the poller's detection of a
state change is itself a synchronous transition once detected). The EPC-specific
registration_prep_pre_trigger handles the pre-trigger arithmetic case;
confirmation handling does not.

### How Server Actions keep clock_events in sync

Entities with scheduled events are not free to mutate without telling
clock_events about it. The Server Action that creates, updates, or deletes such
an entity must update the corresponding clock_events rows in the same
transaction:

- Project creation with a known trigger date: insert a pending clock_events row
  for registration_prep_pre_trigger.
- Project trigger date update: update fires_at on the existing pending row.
- Project soft-delete: set status to cancelled on pending rows.
- Comparable patterns apply for other event types.

The payload JSONB is validated application-layer at insert time, in the Server
Action — each event_type has its own expected payload schema, and the database
does not enforce payload shape. Each event_type also has its own dispatcher
function called by the cron handler when fires_at is reached.

### Failure handling: best-effort with manual retry

When a dispatcher errors, the event flips to status failed with the
failure_reason captured. A platform admin surface shows failed events with
their diagnosis context and a retry button. There is no auto-retry. Adding
automatic retry without evidence of a real recurring failure mode would mask
the failure modes that do exist; if a class of failure recurs and warrants
retry logic, that is its own decision when the evidence arrives.

### The canonical mechanism for any future scheduled event

This is now the one mechanism for scheduled events in WarrantyOS. Future
contributors do not invent a parallel scheduler — they add a new event_type to
the enum, write its dispatcher, and let the existing infrastructure run it.
This is what the System-Managed Clock principle looks like when it has
implementation backing.

## ID Generation

**Status: Designed** (locked by Decision 2; not yet built. tenant_id_sequences
is a Phase 3 table to be migrated. The hardcoded WID-YYYY-NNNNNN label in the
settings page today is a placeholder, replaced by the real generated format
when the settings UI becomes live.)

WarrantyOS generates two kinds of business-visible identifier: WarrantyIDs on
every warranty registration and ClaimIDs on every claim. Both appear in
customer-facing communications and in internal operational work, both are
expected to follow per-tenant formats (one warrantor's "WID-2026-000001" is
another's "WCRT-26-1"), and both must be gap-free for audit defensibility — a
gap in the sequence is not just untidy, it raises legitimate questions about
what was deleted or hidden. This section documents the mechanism.

### One table, one row per (tenant, id_type)

Each tenant has one row per id_type it uses. The row carries the format string
the tenant has configured, the year that format string is currently counting
in, and the latest counter value used in that year. Generation reads and
updates this row in the same transaction as the row that consumes the
identifier, which gives the gap-free guarantee.

    tenant_id_sequences
      tenant_id      uuid FK -> tenants
      id_type        text  -- 'warranty_id' | 'claim_id'
      format_string  text  -- e.g., 'WID-{year}-{seq:06d}'
      current_year   integer
      current_value  integer NOT NULL DEFAULT 0
      updated_at     timestamptz
      PRIMARY KEY (tenant_id, id_type)

The composite primary key on (tenant_id, id_type) is the natural shape: a
tenant has one warranty-id sequence and one claim-id sequence, and they
advance independently.

### Phase 1 id_types and their default formats

Two id_types ship in Phase 1, with per-tenant configurable default formats:

- warranty_id, default WID-{year}-{seq:06d}
- claim_id, default CLM-{year}-{seq:07d}

A tenant can change either format string. The default formats are starting
points, not enforced shapes. The id_type column is the extension point — future
id types (project ids, work order ids, anything else that needs per-tenant
gap-free generation) follow the same row-per-(tenant, id_type) pattern without
restructuring. Each new id_type becomes a new enum value and a new row per
tenant; the table, the generation logic, and the format-string syntax are
unchanged.

### The format string syntax is Python's

The format strings use real Python format-string syntax — {year} for the
current year and {seq:NNd} for the zero-padded sequence number with width N.
This is a real standardized syntax, not an invented {NNNNNN} convention. The
explicit width specifier ({seq:06d} for six-digit zero-padding) is more
honest than a count-the-Ns convention, and the syntax integrates naturally
with template engines if formats ever need to compose with other variables.
Other Python format specifiers — alignment, fill characters, alternate forms
— work without inventing additional conventions.

Format strings must be validated against the supported placeholders ({year}
and {seq:NNd}) at the moment a tenant saves a new format in settings. An
invalid format string in tenant_id_sequences would cause every subsequent
generation to fail; the validation belongs at settings-save time, not at
generation time.

### Per-tenant, not global

Each tenant has its own row and its own counter. There is no global
warranty-id counter that all tenants share. The deciding reason is structural:
per-tenant configurable formats are incompatible with a shared counter,
because different format strings cannot share counter state — one tenant's
"WID-2026-000001" and another's "WCRT-26-1" cannot count in the same sequence.
Avoiding cross-tenant inference via sequence values (a tenant could otherwise
estimate a competitor's warranty volume from id deltas) is a secondary
benefit, not the deciding factor.

### Why a dedicated table, not PostgreSQL SEQUENCE objects or JSONB counters

Two alternatives were considered and rejected. PostgreSQL SEQUENCE objects
are non-transactional — they advance whether or not the surrounding
transaction commits, so a rolled-back insert leaves a gap. SEQUENCE objects
also require runtime DDL per tenant to create new sequences, which is awkward
in a multi-tenant context. JSONB counters on the tenants row work
transactionally but serialize every write to the tenant's settings, which
creates contention as the tenant grows. A dedicated table with row-level
locking gives transactional gap-free behavior without contention or runtime
DDL — the right shape for the actual requirements.

### Generation is transactional and gap-free

The defining behavior. When a Server Action inserts a new warranty
registration or claim, the same transaction also locks the relevant
tenant_id_sequences row, increments current_value, formats the resulting id
through the row's format_string, and writes the formatted id onto the
inserting record. If the surrounding insert rolls back — for any reason —
the counter rolls back with it. There is no committed counter advance for an
uncommitted insert, and therefore no gap.

### Year-rollover is UTC and atomic with the increment

On the first generation of a new calendar year, current_year is stale and
current_value should reset. This happens in the same UPDATE that increments
the counter, using CASE on current_year vs EXTRACT(YEAR FROM NOW() AT TIME ZONE
'UTC'): if the current UTC year matches current_year, current_value is
incremented; if it does not, current_year is updated to the new year and
current_value is reset to 1. Single statement, no race, no separate "is it a
new year?" check that could interleave with another transaction.

UTC, not per-tenant timezone. The platform-wide consistency is worth more
than calendar alignment for any one tenant — a per-tenant timezone column
would be an ongoing maintenance burden (DST, jurisdictional drift, tenant
relocation) without proportional benefit.

### Format changes affect generation only

A tenant can update its format string in settings, and the change takes
effect on the next generated id. It does not retroactively rewrite ids
already generated. Historical WarrantyIDs and ClaimIDs are immutable strings,
stored as-is on the records they identify. This is the only behavior
compatible with the Defensibility principle — an id that appeared in a
notice to a customer last year must still appear, unchanged, on the
internal record today. Retroactive rewrite would corrupt the audit trail.

A side effect: if a tenant changes format mid-year, the resulting id stream
is a mix — old format for ids generated before the change, new format for
ids generated after. This is the intended behavior. The system does not
attempt to preserve cosmetic uniformity at the cost of historical truth.

## Schema Source-of-Truth

**Status: Implemented** (the canonical-migrations convention, the generator
script, and the regenerated schema.sql are live; commits 628efd0
(000_baseline.sql), 44d61dc (generator + README + regenerated schema.sql), and
the supporting Supabase CLI install and supabase init are all on the
session-5e-bridge-phase3-schema-generator branch). **Designed** (the
new-migrations-follow-existing-pattern convention going forward, which applies
to every Phase 3 schema migration not yet written).

Two artifacts describe WarrantyOS's schema: the numbered migration files in
supabase/migrations and a supabase/schema.sql snapshot. Decision 10 settled
which is the source of truth and how the other is kept honest. The short answer
is that migrations are canonical and schema.sql is generated from them, never
hand-edited.

### Migrations are canonical

The numbered migration files in supabase/migrations are the authoritative
description of the schema. They are what is applied to a database — local or
hosted — to bring it from empty to current. Any change to the schema is a new
numbered migration; nothing else.

This is the only choice compatible with production deploys. A schema-canonical
model would require inventing conventions for what has already been applied to
an existing database versus what is still pending — which is exactly what
migrations already track. Reading schema.sql as the truth would mean the file
disagrees with reality the moment the first migration is applied.

### schema.sql is generated

supabase/schema.sql is a snapshot artifact, regenerated from the migrations
by a script. It is never hand-edited. Its purpose is current-state inspection
and code review ergonomics — a single readable file that shows the whole
schema as it stands, without requiring a reader to mentally compose four (now
five) numbered migrations. The file exists for human convenience; the
migrations are the source of truth.

The generator is scripts/generate-schema-sql.mjs. It shells out to
supabase db dump --local against a local Supabase stack — which is itself
built from the canonical migrations by supabase start — and writes the dump
to supabase/schema.sql. The generator approach was an open implementation
detail in Decision 10; Supabase's own CLI was chosen because it inherits
Supabase's maintenance over a 25-year horizon, requires no custom pg_dump
post-processing, and uses the tool already in the development environment.

### The new-migrations-follow-existing-pattern convention

Going forward, every new migration follows the existing pattern set by
000_baseline through 004_team_admin_management: numbered sequentially, with
SET search_path = public hardening on any function (the migration 002 fix is
the precedent), comments explaining design decisions inline, and RLS policies
applied alongside the table creation they belong to. New migrations do not
defer the RLS policy to a later file. New tables do not ship without the
Standard RLS Pattern's six steps all present.

### Why a pre-commit hook was rejected

A pre-commit hook that re-runs the generator would catch a developer who
forgets to regenerate schema.sql after adding a migration. It was considered
and rejected. The reasoning is short: a pre-commit hook is a convention
dressed up in code — the same person who forgets to regenerate schema.sql
will also forget to install the hook. The generator itself is the check
that matters. Once the generator exists, running it is fast and easy, and
schema.sql is verified against it during review. A hook adds machinery
without adding a guarantee.

### Build history

The convention was put into place in commits 628efd0 and 44d61dc, alongside
the schema generator work:

- 628efd0 added supabase/migrations/000_baseline.sql, extracted from commit
  594b206. This closed a real gap: migrations 001 through 004 referenced
  public.tenants and public.users as if they existed, but no migration created
  them — they had been built directly in the hosted Supabase SQL Editor before
  the migrations directory existed. Without 000_baseline, the migration chain
  could not replay from empty, and supabase db dump --local would fail at the
  first migration. With it, the full chain replays cleanly and the generator
  has a real local schema to dump.
- 44d61dc added scripts/generate-schema-sql.mjs and scripts/README.md, and
  regenerated supabase/schema.sql to be the script's output. The regenerated
  schema.sql was verified semantically equivalent to the prior hand-maintained
  version — every table, index, RLS policy, function (with search_path
  hardening), trigger, grant, and migration-applied mutation present and
  correct.
- Earlier supporting commits installed the Supabase CLI in WSL, installed
  Docker Desktop with WSL integration, ran supabase init, and consolidated the
  Supabase-related gitignore patterns under supabase/.gitignore.

The 000_baseline discovery is worth remembering as a small lesson, separate
from the convention itself: a missing baseline migration can hide behind a
hand-maintained schema.sql, because the snapshot file fills in the gap that the
migrations leave. The generator was what surfaced the gap — its first run
could not produce schema.sql because the migrations would not apply cleanly
from empty. The convention forces the migrations directory to be honest about
the full schema, not just the changes since some implicit prior state.

### How the convention works going forward

Adding a new migration is three steps: write the numbered migration file
following the existing pattern, apply it locally (supabase db reset or
equivalent), and run node scripts/generate-schema-sql.mjs to regenerate
schema.sql. The regenerated schema.sql is committed alongside the migration.
Code review checks that the schema.sql diff matches what the migration says
it does. No hand-edits to schema.sql — if the diff looks wrong, the
migration is what gets fixed, and schema.sql is regenerated.

## Project

**Status: Designed** (the sacred root entity; not yet built. projects is a
Phase 3 table to be migrated. Multi-source trigger model from Item 17 is
integrated; soft-delete discriminator specified per Decision 5's downstream
requirement.)

Project is the root entity of the WarrantyOS data model. Every warranty
registration belongs to exactly one project. Every claim is filed against a
warranty that belongs to a project. Every work plan executes against a claim
that traces back to a project. v1 names Project a sacred root in passing but
does not define the entity; this section is the full definition.

A project represents the unit of warranted work or product delivery — a solar
installation site under an EPC contract, a racking order to a buyer-installer,
or any equivalent unit. It is created before its warranty registration exists,
and the moment of its creation is determined by its trigger source (see
lifecycle below).

### Schema

    projects
      id                            uuid PK
      tenant_id                     uuid NOT NULL FK -> tenants
      name                          text NOT NULL
      trigger_source                text NOT NULL
                                    -- 'contractual_date_manual' |
                                    --   'wbs_integration' |
                                    --   'delivery_report_tokenized' |
                                    --   'delivery_report_api'
                                    -- CHECK constraint enforces allowed values
      trigger_status                text NOT NULL DEFAULT 'pending'
                                    -- 'pending' | 'confirmed' | 'overdue'
                                    -- CHECK constraint enforces allowed values
      trigger_date                  date nullable
                                    -- set when trigger_status becomes
                                    -- 'confirmed'; null until then
      integration_config            jsonb nullable
                                    -- WBS / API integration identity and
                                    -- project reference; null for non-
                                    -- integrated trigger sources
      customer_id                   uuid nullable FK -> contacts
      customer_name_snapshot        text
      customer_email_snapshot       text
      customer_phone_snapshot       text
      site_address_street           text
      site_address_city             text
      site_address_state            text
      site_address_zip              text
      imported_via_batch_id         uuid nullable FK -> import_batches
      deleted_at                    timestamptz nullable
                                    -- soft-delete discriminator;
                                    -- non-null means project is retired
      created_at                    timestamptz NOT NULL DEFAULT now()
      updated_at                    timestamptz NOT NULL DEFAULT now()

The table follows the Standard RLS Pattern's six steps: tenant_id FK, RLS
enabled, the standard tenant-scoped SELECT policy, service-role-only writes,
the required grants. There is no project-level user-facing UPDATE policy —
project mutations all go through Server Actions.

### No business-visible identifier in Phase 1

Projects have no business-visible identifier — no "PRJ-" prefix, no formatted
project number, just the uuid primary key. This is deliberate. WarrantyIDs
appear on warranty registrations and ClaimIDs appear on claims because both
identifiers serve customer-facing communications. Projects today are internal —
the customer sees warranties and claims, not projects. If a project number
becomes operationally necessary later, the ID Generation system's
tenant_id_sequences pattern accommodates it as a new id_type without
restructuring; until then, the uuid is enough.

### Multi-source trigger model

Two columns — trigger_source and trigger_status — make the warranty trigger a
first-class concept on the project. They exist because WarrantyOS serves two
distinct business shapes that imply different trigger mechanics, and the
architecture has to accommodate both without making one a special case of the
other.

**EPC shape.** The warrantor is part of the construction process. The trigger
date — substantial completion, commercial operation date, commissioning date,
a contract-defined variance — is known in advance, memorialized in the project
contract or in a construction-management system. Two trigger_source values
serve this shape:

- contractual_date_manual — A tenant user enters the trigger date directly at
  project creation. The default EPC trigger for tenants without WBS-integration
  tooling.
- wbs_integration — The trigger date is sourced from a construction-management
  system (Procore is the canonical example) via API. integration_config holds
  the external system identity and the project's reference within that system.
  A poller (driven by Clock Event Infrastructure) reads the external milestone
  state on a tenant-configurable schedule. When the milestone hits its
  configured state, the poller captures the timestamp, sets trigger_status to
  confirmed, and invokes the registration-creation Server Action directly.
  Concrete vendor integrations are Phase 4+ work; v2 documents the pattern,
  not the specific integrations.

**Supply-only shape.** The warrantor sells and ships a product but has no site
presence. The trigger date is the delivery date, and the buyer-installer is the
sole source of truth for it. This is an asymmetric-information structural
problem, not a missing feature: the buyer's incentive to volunteer the delivery
date promptly is not naturally aligned with the warrantor's interest. Two
trigger_source values serve this shape:

- delivery_report_tokenized — The buyer-installer reports the delivery date
  through a tokenized email form, using the Stateless Tokenized Interaction
  Pattern. The form is sent at project creation (sale time), not at expected
  delivery time, and remains open until the buyer reports. The
  trigger_confirmation_overdue clock event surfaces silence; what to do about
  it is operational policy (contractual default-trigger language is the
  warrantor's backstop, supported by the platform but not enforced
  automatically).
- delivery_report_api — A logistics or freight-carrier API confirms delivery.
  Reserved as a Phase 1 enum value so the future integration path is explicit;
  concrete carrier integrations are not Phase 3 scope.

The trigger_source enum is extensible. Future sources — customs_release_api,
inspection_signoff, warrantor_self_report — can be added by later decisions
without restructuring.

### trigger_status state machine

A project's trigger_status moves through three states:

- pending — the default at project creation. Trigger event has not yet
  occurred (or, for supply-only, has not been reported).
- confirmed — trigger event has occurred. trigger_date is captured. Warranty
  start date is established. This is the state at which registration prep can
  fire (for trigger sources where prep is post-confirmation) or has fired (for
  trigger sources where prep is pre-trigger).
- overdue — the expected trigger window has passed without confirmation.
  Applies primarily to delivery_report_tokenized (buyer has not responded
  within the expected delivery window) and to wbs_integration (the integrated
  milestone has not flipped within its expected timeframe). Surfaces to
  platform admins and tenant team admins for follow-up.

The transitions are governed by trigger_source. The mechanism by which a
state change becomes either a future-firing clock event or a synchronous
Server Action effect is in the lifecycle section below.

### Lifecycle: when projects are created and what fires

This revises Phase 0 item 9, which was originally written EPC-only ("Projects
exist in WarrantyOS once their contractual milestone date is known.
Registration prep is triggered registration_lead_time_days before the
milestone, default 21 days, per-tenant configurable.") The revised wording:

Projects exist in WarrantyOS at the point determined by their trigger source.

- For contractual_date_manual and wbs_integration (EPC shape), the project
  is created when the trigger date is known in advance. trigger_status starts
  pending. Registration prep is triggered registration_lead_time_days before
  the trigger date — a future-firing clock event of type
  registration_prep_pre_trigger inserted into clock_events at project creation.
  Default lead time is 21 days, per-tenant configurable.
- For delivery_report_tokenized and delivery_report_api (supply-only shape),
  the project is created when the sale occurs. trigger_status starts pending.
  Registration prep does NOT fire on creation — there is no known trigger date
  to schedule from. Registration is generated as a synchronous Server Action
  effect when trigger_status advances from pending to confirmed (because the
  buyer reported delivery, or the carrier API confirmed it). No clock_events
  row is created for this; synchronous transitions are not future-firing
  events.

The same synchronous-versus-scheduled distinction applies to wbs_integration
once the poller detects the milestone — the registration creation is
synchronous from the poller's perspective, even though the poller itself runs
on a clock_events schedule.

### Feature flag gating

Project creation gates on the Feature Flag System's two Phase 1 flags through
the Defense-in-Depth Pattern's three-layer model. At the schema layer the
trigger_source column accepts all four values; the database does not enforce
gating. At the application layer the Server Action creating a project checks
isFeatureEnabled(tenantId, 'epc_workflow') before allowing
contractual_date_manual or wbs_integration, and
isFeatureEnabled(tenantId, 'supply_only_workflow') before allowing
delivery_report_tokenized or delivery_report_api. At the UI layer the project
creation form renders only the trigger sources whose flag is enabled, so a
pure-EPC tenant never sees delivery-report options and a pure-supply-only
tenant never sees milestone-date entry.

### Customer attribution via FK + Snapshot

A project's customer is recorded using the FK + Snapshot Pattern's single-FK
shape: customer_id references contacts, with customer_name_snapshot,
customer_email_snapshot, and customer_phone_snapshot captured at project
creation. The snapshots preserve audit-defensible historical attribution over
the long warranty horizon; the FK supports reuse and reporting. See the FK +
Snapshot Pattern section for the mechanics.

The customer relationship is required for projects to be operationally useful
— claim intake auto-population, notice generation, and warranty activation
all depend on it. Decision 8 covers customer data during import; ongoing
customer creation happens through standard tenant operation.

### Site address

site_address_street, site_address_city, site_address_state, and
site_address_zip hold the physical location of the warranted work. These are
project columns, not customer columns, because the customer (the company) and
the site (the location of the installation) can differ — a customer with
many sites has many projects at different addresses. Phase 1 keeps the
address as four scalar columns; structured address handling (geocoding,
international format support) is deferred.

### Soft-delete via deleted_at

Decision 5 made the project-to-registration FK ON DELETE RESTRICT, which
blocks hard-deletion of a project that has an associated registration. This
section delivers the soft-delete discriminator Decision 5 said the Project
section must specify: a deleted_at timestamptz column, null when the project
is active, non-null when the project has been retired.

The semantics match the spirit of the users table's removed_at, with one
difference: users carries both a status column ('active'/'suspended') and
removed_at, because a user has a meaningful intermediate state. A project
does not — a project is either active or retired; there is no "suspended
project" state. So projects use a single discriminator, deleted_at, not the
two-column users pattern. Naming the column deleted_at rather than removed_at
also reads more naturally for an inanimate entity.

Operational rules:

- A non-null deleted_at means the project is retired. The row remains in the
  database — Defensibility requires the historical record to persist — but
  it is filtered out of normal queries.
- All standard SELECT queries on projects must include
  "deleted_at IS NULL" to exclude retired projects, matching the convention
  already used for removed users.
- Hard-deletion through the UI is not available. RESTRICT prevents accidental
  hard-delete of a project that still has a registration — a plain
  DELETE FROM projects will be refused by the database. Intentional
  admin-level destruction of the full project + registration + downstream
  chain is constrained by the absence of an admin UI for it, not by the
  database constraint alone.
- A retired project's associated warranty registration is not automatically
  retired. Cascading the retirement decision is a Phase 4 concern; in Phase 1
  the operational expectation is that retirement happens before a registration
  is active.

### Import-tracking

imported_via_batch_id (nullable FK to import_batches) records the data
migration batch that created the project, if any. Projects created through
normal tenant operation leave this null. Decision 8 covers the import
mechanics.

### Multiple projects per tenant; the portfolio view

A tenant has many projects, all scoped through Standard RLS. The "Project
Portfolio" view that warranty operations teams use is an application-layer
join over projects, warranty_registrations, claims, and cost-tracking tables
— not a database view today. Adding a database view is straightforward if
performance demands it; the portfolio concept does not require one.

### What is NOT on the project

Three things that might be expected but are not project columns, with the
reason for each:

- No assigned PM column. The Audit Topic 7 gap note floated "Created by PM
  role" as a possibility, but Decision 1 retired the PM role from the tenant
  role model. The dual-FK assignee model on warranty_registrations (contact
  assignee or tenant user assignee) handles "who's running this" at the
  registration level, not at the project level. If a project needs a "primary
  contact within the tenant" later, that's a future decision.
- No business-visible ID. Covered above; the uuid is sufficient for Phase 1.
- No business-status column beyond deleted_at and trigger_status. A project's
  business state is derived from its trigger_status, its registration's state,
  its claims, and its costs — not from a project-level status enum.

## Warranty Registration

**Status: Designed** (Phase 3 table to be migrated. The assignee model is
locked by Decision 1, the FK direction and 1:1 enforcement by Decision 5, the
WarrantyID issuance by Decision 2 and Item 17. The Section 7 activation gate's
specific conditions are not specified at the architectural layer and are
flagged as a Phase 4 / downstream-operational question.)

A warranty registration is the parent record for one warranty agreement on
one project. It carries the WarrantyID once issued, tracks the assignee
responsible for completing activation, and is the immediate parent of the
warranty coverages and claims that follow. v1 describes registration as a
lifecycle stage; this section is the entity behind it.

A registration begins life associated with its project but inactive — no
WarrantyID yet, no coverages billing time toward expiry. It moves through
preparation and review, passes the Section 7 activation gate, receives its
WarrantyID, and is then live. Everything downstream — coverages, claims,
work plans, costs — depends on a live registration.

### Schema

    warranty_registrations
      id                          uuid PK
      tenant_id                   uuid NOT NULL FK -> tenants
                                  -- denormalized per Standard RLS Pattern
      project_id                  uuid NOT NULL UNIQUE FK -> projects
                                  -- UNIQUE enforces 1:1; ON DELETE RESTRICT
      warranty_id                 text nullable
                                  -- issued at Section 7 activation;
                                  -- null until then; immutable once set
      status                      text NOT NULL
                                  -- minimum values: 'pre_activation',
                                  -- 'active'. Richer values are a
                                  -- downstream operational question.
                                  -- CHECK constraint enforces allowed values
      assigned_to_contact_id      uuid nullable FK -> contacts(id)
      assigned_to_user_id         uuid nullable FK -> public.users(id)
                                  -- CHECK: exactly one non-null when
                                  -- assigned; both null when unassigned
      assigned_to_name_snapshot   text nullable
      assigned_to_email_snapshot  text nullable
      assigned_to_phone_snapshot  text nullable
      assigned_at                 timestamptz nullable
      activated_at                timestamptz nullable
                                  -- set when status transitions to active
      created_at                  timestamptz NOT NULL DEFAULT now()
      updated_at                  timestamptz NOT NULL DEFAULT now()
      -- CHECK / app-layer invariant: tenant_id matches the referenced
      -- project's tenant_id

The table follows the Standard RLS Pattern's six steps. tenant_id is
denormalized onto the registration directly (rather than joined through
project) per the convention established by Decisions 3 and 5 — the same
convention the Standard RLS Pattern section documents formally.

### One-to-one with Project, enforced by the database

Phase 0 item 2 says a project and its warranty registration are 1:1
architecturally. Decision 5 enforces that architecturally-named property at
the database layer with a UNIQUE constraint on project_id: no second
registration can be inserted for a project that already has one. The
relationship's direction — registration carries the FK, project does not —
matches creation order: project exists first, registration is created
afterward (the timing depends on trigger_source; see the Project section's
lifecycle).

The FK is ON DELETE RESTRICT. A plain DELETE FROM projects against a
project that has a registration will be refused by the database. The
operational cleanup path for both is soft-delete (deleted_at on projects;
status transitions on registrations), not hard delete.

### Section 7 activation gate

Section 7 is the structural anchor in registration lifecycle: the gate that
issues the WarrantyID and transitions the registration to active. v1 and
Audit Topic 6 both name it but do not specify its contents — what review
artifacts it requires, what conditions it checks, who has authority to
clear it. v2 documents Section 7 as the named activation event with the
state consequences we know:

- Before Section 7 passes: warranty_id is null. status is pre-activation.
  Coverages may exist as draft, but no claim can be filed and no warranty
  term is counting.
- Section 7 passes: the Server Action handling activation generates the
  WarrantyID from the tenant's warranty_id row in tenant_id_sequences
  (default format WID-{year}-{seq:06d}, per-tenant configurable). The
  WarrantyID is written to warranty_id and the column is treated as
  immutable from that point. status transitions to active. activated_at
  is captured.
- After Section 7 passes: the registration is live. Coverages are active,
  claims can be filed against the registration, customer-facing
  communications reference the WarrantyID.

The specific conditions Section 7 evaluates — required fields, required
reviewer approvals, required documents — are not specified at the
architectural layer in any locked source. This is a Phase 4 or downstream
operational question. The architecture sets the gate's role (issue the
WarrantyID and activate); the gate's contents are a separate decision.

### WarrantyID issuance, not assignment at creation

The WarrantyID is issued at Section 7 activation, not assigned at
registration creation. This matters: a registration's id (uuid PK) exists
from creation; its WarrantyID does not. The WarrantyID is the business-
visible identifier that appears in customer-facing communications, and
issuing it only at activation reflects the operational reality — there is
no warranty agreement to identify until activation has happened.

Generation goes through tenant_id_sequences in the same transaction as the
status update to active, so the counter and the activation cannot drift
apart. See the ID Generation section for the transactional gap-free
mechanism. Once issued, warranty_id is immutable; this is the Defensibility
Principle applied to identifiers.

### Assignee: who's responsible for completing activation

A registration is assigned to one party — a directory contact (e.g., a
subcontractor PM who handles the activation paperwork) or a tenant user
(e.g., a Reviewer self-handling). The assignment is captured using the FK +
Snapshot Pattern's dual-FK shape: two nullable FKs with a CHECK enforcing
exactly one non-null when assigned, plus snapshot columns for name, email,
phone, and the assigned_at timestamp.

The FK type drives downstream behavior. A contact assignee is reached
through the Stateless Tokenized Interaction Pattern (a tokenized email link
to a focused activation form). A tenant-user assignee is reached through an
in-app notification on their existing login. The two paths are different
because the parties are different kinds of thing — contacts have no
account, tenant users do.

Reassignment can cross types. A registration assigned to a contact PM can
be reassigned to a Reviewer for self-handling, or the reverse. The snapshot
columns capture the assignment at the moment it was made and are never
updated on read; reassignment writes a new snapshot. See the FK + Snapshot
Pattern section for the mechanics.

### Status

A registration carries a status column. Two states are determined by the
architecture:

- pre-activation — warranty_id is null. activated_at is null. The
  registration exists but has no business-visible identifier and counts no
  warranty time. Section 7 has not passed.
- active — Section 7 has passed. warranty_id is set (immutable from this
  point), activated_at is set, coverages count time.

Whether the pre-activation state needs to subdivide further (e.g., separate
pending vs in-review states), and whether richer activation-progress states
are useful at the architecture layer versus derived from operational fields,
is a Phase 3 / downstream operational question — same flag as Section 7's
specific conditions. The architecture establishes that a status column
exists and carries at minimum the two states above; the closed set of values
is settled by a separate decision.

A third state — expired — is mentioned operationally (all coverages past
their end_date), but whether expiry is a status value, a derived condition
from coverage end_dates, or both, is also part of that downstream
question.

The column exists rather than being purely derived because queue filters,
dashboards, and reporting are cleaner against a status column than against
a multi-field derivation. Adding the column without locking its values is
the architecturally restrained move.

### Coverages are children of registration

A registration is the parent of one or more warranty coverages (one row per
warranty type per registration). The Warranty Type Coverages section
documents the coverages table and the per-tenant configurable warranty
types they reference. The 1:1 relationship between project and registration
does not extend to coverages — a registration can have many coverages, one
per warranty type the tenant offers and the agreement covers.

### Document attachments

Registrations carry document attachments — the artifacts captured during
activation, customer-signed terms, supporting documents, and so on. Audit
Topic 6 names a "document categories structure" as a known gap but does
not specify a categorization schema; no locked source defines what the
categories are. v2 names the relationship (registrations have associated
documents) and leaves the categorization schema to downstream operational
drafting or a future decision. Phase 4 territory.

### Clock-event interactions

A registration's lifecycle touches Clock Event Infrastructure differently
depending on the project's trigger_source. What Item 17 specifies, what is
synchronous, and what is open:

- For contractual_date_manual (EPC, known date), the project's creation
  inserts a registration_prep_pre_trigger event into clock_events, scheduled
  registration_lead_time_days before the trigger date. When the event fires,
  registration prep work begins — what specifically happens at firing time,
  including whether the registration record is created at project creation
  or at prep-event firing, is not specified by any locked source. v2 names
  the prep event without resolving the creation-timing question; it's a
  Phase 4 / downstream operational drafting decision.
- For wbs_integration (EPC, polled), Item 17 specifies that when the poller
  detects the milestone in its configured state, it sets trigger_status to
  confirmed and synchronously invokes the Server Action that creates the
  warranty registration. No clock_events row is created for the creation
  itself; the transition is synchronous from the poller's perspective.
- For delivery_report_tokenized and delivery_report_api (supply-only), Item
  17 specifies that registration creation is synchronous on trigger_status's
  transition from pending to confirmed. The Server Action handling the
  buyer's report (or carrier API confirmation) creates the registration
  directly. No clock_events row.

Warranty expiry warnings are a separate clock-event interaction. A
warranty_expiry_warning event fires before each coverage's end_date,
surfacing the upcoming expiry. The mechanism for transitioning to the
expired state (whether it's a column update, a derivation, or both) is part
of the same downstream operational question flagged in the Status section
above.

### What is NOT on the registration

A short list of deliberate omissions, parallel to the Project section:

- No coverage start_date or end_date. Those live on the warranty_coverages
  child table, one per warranty type, with end_date derived from
  start_date + term_years. See the Warranty Type Coverages section.
- No customer FK. The customer is on the project (FK + Snapshot single-FK
  shape); the registration inherits its customer through project_id.
  Duplicating the customer on registration would create a sync surface
  where there's no need for one.
- No business-status enum beyond the minimum two states above. Anything
  more granular about activation progress (which Section 7 fields are
  complete, which reviewer approvals are in) is downstream operational
  state, not registration-level state.

## Warranty Type Coverages

**Status: Designed** (Phase 3 tables to be migrated. warranty_types is locked
by Decision 6 with defense-in-depth anchor protection; warranty_coverages
follows the shape Audit Topic 8 specifies. The mechanism for end_date
derivation — application layer vs Postgres generated column — is a Phase 3
implementation choice flagged below.)

A warranty registration covers one or more warranty types over their own
terms. Foundation might run 5 years; racking, 25; workmanship, 10. The
warranty type list is per-tenant configurable so warrantors can name and
scope coverages to their own product lines, but a small set of types is
seeded at tenant provisioning so every tenant starts with a working
baseline. This section documents both tables — warranty_types (the
configurable list) and warranty_coverages (the per-registration
instantiations).

### v1's "Equipment and Workmanship sub-tables" is retired

v1 describes the coverage matrix as "Equipment and Workmanship sub-tables" —
a fixed two-sub-table model where the categorization is baked into the
schema. v2 retires that model. The per-tenant configurable warranty_types
table replaces it, with two seeded anchor types — Standard Warranty and
Workmanship Warranty — that preserve the spirit of v1's two categories as
defaults without forcing every tenant into them or limiting tenants to two.
A future reader of v1 alongside v2 should treat the sub-tables language as
historical; the configurable type list is the current model.

### warranty_types schema

The configurable per-tenant type list:

    warranty_types
      id            uuid PRIMARY KEY DEFAULT gen_random_uuid()
      tenant_id     uuid NOT NULL FK -> tenants
      name          text NOT NULL
      is_system     boolean NOT NULL DEFAULT false
                    -- true on anchor types seeded at tenant provisioning;
                    -- protected from delete and from is_system->false
      created_at    timestamptz NOT NULL DEFAULT now()
      updated_at    timestamptz NOT NULL DEFAULT now()

A case-insensitive uniqueness constraint on (tenant_id, name) is enforced by
a functional index:

    CREATE UNIQUE INDEX warranty_types_tenant_name_lower_unique
      ON warranty_types (tenant_id, LOWER(name));

"Foundation" and "foundation" within the same tenant would be
workflow-ambiguous; the LOWER index makes them collide as expected. The cost
is one composite index; the benefit is clean naming.

The table follows the Standard RLS Pattern's six steps: tenant_id FK, RLS
enabled, the standard tenant-scoped SELECT policy, service-role-only writes,
the required grants. Tenant Team Admins manage the type list through Server
Actions; Reviewers and Viewers consume it.

### Anchor types and the is_system flag

Tenant provisioning seeds two warranty_types rows per new tenant:

- Standard Warranty (is_system = true)
- Workmanship Warranty (is_system = true)

These are renameable — a tenant can update the name column on either row
through the standard CRUD path. They are not deleteable, and is_system
cannot be flipped to false on either. A tenant can add as many additional
types as it needs (Foundation, Component, Racking, whatever the product
lines call for); those are added with is_system = false and have no
special protection.

The architectural commitment behind is_system is that anchor types are
permanent. A tenant's downstream data — registrations, coverages, claims
— may reference Standard Warranty for years; orphaning those references
by deleting the row would corrupt the audit trail. is_system enforces
permanence.

### Defense-in-depth anchor protection

Decision 6 protects the anchor types through the Defense-in-Depth Pattern,
the same convention applied to last-admin protection. Two layers:

- Application layer: the Server Action for warranty_types CRUD rejects
  delete of any row where is_system = true, and rejects UPDATE attempts
  that flip is_system to false. The user gets a clean, early error
  before any database exception. This is the UX layer.
- Database layer: a BEFORE DELETE OR UPDATE trigger function on
  warranty_types raises an exception for the same conditions —
  OLD.is_system = true on DELETE, or OLD.is_system = true AND
  NEW.is_system = false on UPDATE. The trigger is hardened with SET
  search_path = public per the migration 002 precedent. This is the
  structural-guarantee layer.

The protection extends to UPDATE of is_system specifically to close the
two-step exploit: a delete-prevented anchor could otherwise be cleared
by first flipping is_system to false (no protection check) and then
deleting (now allowed because is_system is false). Extending the
protection to the flag itself, not just the row, prevents that path.

The architectural commitment applies to the flag, not just the row —
this is the same shape Decision 6 names. See the Standard RLS Pattern
section for the defense-in-depth convention; Decision 6 is one of its
two named precedents alongside last-admin protection.

### warranty_coverages schema

A coverage is one warranty type's instantiation on one registration. A
registration has one coverages row per warranty type it covers — a
Standard Warranty might run alongside a Workmanship Warranty and a
Racking warranty on the same registration, each with its own start date
and term.

    warranty_coverages
      id                          uuid PK
      tenant_id                   uuid NOT NULL FK -> tenants
                                  -- denormalized per Standard RLS Pattern
      warranty_registration_id    uuid NOT NULL FK -> warranty_registrations
      warranty_type_id            uuid NOT NULL FK -> warranty_types
      start_date                  date NOT NULL
      term_years                  integer NOT NULL
                                  -- a CHECK > 0 is the obvious defensive
                                  -- constraint; not architecturally locked
      created_at                  timestamptz NOT NULL DEFAULT now()
      updated_at                  timestamptz NOT NULL DEFAULT now()
      -- end_date is derived, not stored — see below
      -- CHECK / app-layer invariant: tenant_id matches the referenced
      -- registration's tenant_id

The table follows the Standard RLS Pattern. tenant_id is denormalized
directly onto the coverage (rather than joined through registration or
through warranty_type) per the same convention as warranty_registrations
and custom_field_values.

A natural uniqueness constraint applies: a registration should not have
two coverages of the same warranty type. Whether this is enforced by a
UNIQUE (warranty_registration_id, warranty_type_id) index is a Phase 3
implementation detail; the architectural intent is one row per
(registration, type) pair.

### end_date is derived, not stored

end_date is not an independent column. It is the value of
start_date + term_years, computed where it is needed. Two reasons.
Storing it as an independent column would create a sync surface: an
update to either start_date or term_years would have to remember to
update end_date too, or the stored value drifts. Audit defensibility
also prefers a single source of truth — start_date and term_years are
what the warranty agreement records; end_date is a calculation.

The mechanism for the derivation is a Phase 3 implementation choice:
either a Postgres generated column (GENERATED ALWAYS AS (start_date +
(term_years || ' years')::interval) STORED, which makes end_date
queryable like a regular column without the sync risk) or
application-layer computation (every read site computes end_date from
the two source columns). The generated-column approach is the more
ergonomic choice — queries can filter and sort on end_date directly —
but Postgres generated columns have constraints on what expressions
they accept, and the term_years-to-interval conversion specifically
should be verified against the production Postgres version. Application
layer is the always-available fallback. The choice is settled when
warranty_coverages is migrated; the architectural commitment (derived,
not stored as an independent column) holds either way.

### Coverages and the registration's status

A coverage's start_date and term_years are recorded at registration time,
but the coverage does not "count time" until the registration is active.
Pre-activation, the coverage row may exist as draft. Once Section 7
passes and the registration becomes active, the coverages are live.

The expiry warning is a clock event, not a column update. A
warranty_expiry_warning event in clock_events fires before each
coverage's computed end_date, surfacing the upcoming expiry. The
mechanism for the registration's transition to expired (whether driven
by all-coverages-past-end-date as a derived state or as an explicit
status update) is part of the Warranty Registration section's
status-enum open question.

### What is NOT on the coverage

A parallel deliberate-omissions list:

- No end_date column. Covered above; derived, not stored.
- No business-visible identifier. Coverages are referenced internally
  by uuid; the customer sees warranties (WarrantyID) and claims
  (ClaimID), not individual coverage rows.
- No coverage-level status enum. A coverage's state is derived from
  its registration's status and its own end_date — active when
  registration is active and now < end_date, expired when now >
  end_date.

## Claim (Shell)

**Status: Designed at the shell level.** This section documents the claim
entity's existence, its FK relationships, and its identifier mechanism. The
intake data model — what fields the intake form captures, how the schema
accommodates per-tenant variation across the six claim intake workbooks, the
tokenized intake link mechanics, and the operational status state machine —
is Tier 3 work, deferred to a later v2 section that depends on the workbooks
as source material. Phase 3 table to be migrated; the schema below is the
shell scope only.

A claim is the record of a customer's report against a live warranty
registration. It is the lifecycle stage where warranty operations work
moves from anticipation (registration, coverage) to response (intake, review,
work plans, costs, outcome). Every claim belongs to one warranty registration;
every registration may have zero, one, or many claims over the warranty
horizon.

### Shell schema

The shell-level columns — the ones the architecture locks at Tier 2,
independent of intake form contents:

    claims
      id                    uuid PK
      tenant_id             uuid NOT NULL FK -> tenants
                            -- denormalized per Standard RLS Pattern
      warranty_registration_id  uuid NOT NULL FK -> warranty_registrations
      claim_id              text NOT NULL
                            -- generated at claim creation; immutable
                            -- once set; default format CLM-{year}-{seq:07d}
      status                text NOT NULL
                            -- minimum value: 'intake_received'. Richer
                            -- values reflect v1's Six Gates and are a
                            -- Tier 3 / downstream operational question.
                            -- CHECK constraint enforces allowed values
      created_at            timestamptz NOT NULL DEFAULT now()
      updated_at            timestamptz NOT NULL DEFAULT now()
      -- intake form fields (hard columns + JSONB) are Tier 3 work
      -- and are NOT in this shell schema
      -- CHECK / app-layer invariant: tenant_id matches the referenced
      -- registration's tenant_id

The table follows the Standard RLS Pattern's six steps: tenant_id FK, RLS
enabled, the standard tenant-scoped SELECT policy, service-role-only writes,
the required grants. tenant_id is denormalized onto the claim directly per
the convention.

### ClaimID is an independent sequence, not derived from WarrantyID

v1 specifies the ClaimID format as [WarrantyID]-C[NNNN] — a derivative
form where the ClaimID inherits the WarrantyID and appends a per-warranty
counter. v2 retires that model. ClaimIDs are now an independent per-tenant
sequence, generated from tenant_id_sequences with the id_type claim_id and
the default format CLM-{year}-{seq:07d}, per-tenant configurable through the
ID Generation system.

A future reader of v1 alongside v2 should treat the inheriting format as
historical; the independent CLM- format is the current model. The change is
deliberate. The independent sequence is cleaner operationally (claim
counters do not interact with warranty issuance), aligns with how ClaimIDs
appear in customer communications (ClaimIDs are referenced on their own
terms, not as suffixes on a WarrantyID), and uses the same id_type
infrastructure as WarrantyIDs without inventing a parallel inheritance
mechanism.

Generation goes through tenant_id_sequences in the same transaction as the
claim insert. If the insert rolls back, the counter rolls back — no gaps.
See the ID Generation section for the transactional gap-free mechanism.
Once issued, claim_id is immutable; this is the Defensibility Principle
applied to identifiers, the same as WarrantyID.

### Parent: warranty_registrations

A claim's parent is its warranty registration, via warranty_registration_id.
A registration may have many claims over the warranty horizon; the
relationship is one-to-many. There is no UNIQUE constraint on the FK — a
registration can accumulate claims throughout its active period.

The FK direction matches creation order: a registration exists before a
claim can be filed against it.

Claim eligibility rules — whether a claim can be filed against a
pre-activation registration, how emergency claims are handled (v1's
Acknowledged Warranty Claim Lifecycle SOP carves out emergency
stabilization with a 24-hour formal-filing window), the relationship
between Section 7 and claim filing — are Tier 3 work, deferred to the
claim lifecycle section.

ON DELETE behavior on this FK is not yet locked. The architectural
parallel to projects-to-registrations (RESTRICT, with soft-delete the
operational cleanup path) suggests the same restraint here, but the
specific clause is a Phase 3 implementation detail.

### Status

Following the same architecturally-restrained pattern as Warranty
Registration's status:

- intake_received is the minimum starting state — a claim row exists, the
  initial intake has been captured. Beyond this, the operational state
  machine reflects v1's Six Gates structure (Gate 1 through Gate 6) plus
  outcome states, but the closed set of values, the transitions between
  them, and the rules governing each transition are Tier 3 / downstream
  operational work.

The status column exists at the shell level for the same reason
Warranty Registration's does: queue filters, dashboards, and reporting
are cleaner against a column than against a derivation. The
architectural commitment is the column itself; the values are settled
when the Tier 3 claim lifecycle section is drafted against v1's Six
Gates structure and the six claim intake workbooks.

### Custom field support

Claim is one of the three Phase 1 entities that support custom fields,
per Decision 3 — the others are project and warranty_registration. A
tenant Team Admin can define custom fields on claims through the Custom
Field System; values for those fields are stored in custom_field_values
with the claim_id FK set. The shell schema above does not list custom
fields because they live in a separate table; the Custom Field System
section documents the mechanism.

### What Tier 3 will add to this entity

Tier 3 work picks up from this shell and adds the operational data model.
Named explicitly so a future reader knows where to look:

- The intake form's field schema — the hybrid approach of hard columns
  for universal queryable fields (claim date, claimant identity, claim
  type, current gate) plus JSONB for warrantor-configurable fields
  varying across the six claim intake workbooks. Audit Topic 9 sketches
  the hybrid approach; the workbooks settle which fields are hard versus
  JSONB.
- The tokenized intake link mechanism — the customer-facing application
  of the Stateless Tokenized Interaction Pattern, with the token stored
  on its own record per the "shape to copy, not shared store" rule from
  the pattern section.
- The claim status state machine — the closed set of status values
  including Gate 1 through Gate 6 and outcome states, the transitions
  between them, the actors authorized for each transition, and the
  effects of each.
- Claim eligibility rules — pre-activation handling, emergency claim
  carve-outs, the relationship between Section 7 and claim filing.
- The relationships to downstream entities — work plans, service
  reports, ALA documents, escalation pathways, and cost tracking are
  all claim-level concerns drafted in their own Tier 3 sections, with
  the claim as their parent.

### What is NOT in the shell

A short list of deliberate omissions, parallel to the Project and
Warranty Registration sections:

- No intake form fields. Hybrid schema is Tier 3.
- No tokenized link columns. Tokenized intake is Tier 3.
- No gate-level state columns. The Six Gates lifecycle is operational
  structure, modeled in the status column's value set at Tier 3.
- No claimant FK or snapshot. Whether the claimant is captured as a
  contact (FK + Snapshot single-FK shape, parallel to projects.customer_id)
  or differently is a Tier 3 decision.

## Claim Intake Data Model

**Status: Designed at the architectural level.** The hybrid hard-columns-plus-
JSONB strategy is locked here; the hard column set and the Replacement Parts
JSONB shape are settled; the JSONB shapes for the other six claim_types are
deferred to downstream operational drafting when each type's workbook or SOP
surfaces. Several specific architectural questions are flagged in the
Outstanding architectural questions subsection below.

This section is the operational data model on top of the Claim shell drafted
in Tier 2. The shell established the entity, its FK to warranty_registrations,
its ClaimID issuance, its status column at minimum scope, and its custom field
support. This section adds the intake form's field schema — what gets captured
when a customer files a claim through the tokenized intake link.

A note on the workbook corpus. Audit Topic 9 framed "the six claim intake
workbooks" as source material for this section. On reading them, only two are
actually intake workbooks: Claim Intake Form Datapoint and Parts Claim
Datapoints. The other four — Claim Denial Escalations Intake, Claim Denial
Escalations Reviewer Data, Work Authorizations Customer Inputs, Work Plan Data
Inputs — belong to downstream Tier 3 sections (Escalation Pathways for the
first two, Work Plan Workflow for the latter two). The audit's "six workbooks"
framing was inherited loosely; the actual intake corpus is two.

### The hybrid strategy

The intake schema uses three mechanisms, each addressing a different kind of
variation:

- Hard columns on the claims table for fields that are universal across all
  claim types and all warrantors. Every claim has a claim_type, a date of
  defect, a priority flag, a description.
- JSONB on the claims table for fields whose schema varies by claim_type
  across the platform. Every warrantor's Replacement Parts claim has a Part
  Name; every Foundation claim has a Foundation Issue Type. The variation is
  by claim_type, not by tenant — the platform architecture defines the shape.
- Custom field values (per Decision 3, with entity_type = 'claim') for fields
  whose presence and shape varies by tenant. Some warrantors need to capture
  additional detail about LOTO responsibility beyond the categorical
  loto_requirement value — who specifically performs LOTO, contact info for
  the responsible party, authorization details. These vary by warrantor
  business model and are not pre-defined by the platform. A warrantor whose
  business model doesn't include electrical work may need no LOTO custom
  fields at all. A warrantor who sometimes self-performs may define multiple.
  The variation is by tenant — the tenant's Team Admin defines whatever
  fields fit their operational language.

The boundary between the second and third mechanisms is worth stating
explicitly, because they overlap conceptually. The contrast is between
platform-shaped variation and tenant-shaped variation. Part Name on a
Replacement Parts claim is platform-shaped: every warrantor's Parts claim
captures it, the field is part of how the platform models a Parts claim, no
tenant configuration is involved, the field name is fixed. LOTO-responsibility
detail beyond the universal loto_requirement is tenant-shaped: whether any
such fields appear, what they are called, and what their options are all
vary by tenant. Same general subject area (LOTO); different mechanism,
because the variation is at a different level. That even the field *names*
are tenant-configured is the strongest signal: a platform-architecture field
has a fixed name; a tenant-configured field is named in the tenant's
operational language.

### Hard columns

These are the universal fields. Every claim has them regardless of claim_type
or tenant.

    claims (hard columns added to the Tier 2 shell)
      -- shell columns from Tier 2 (id, tenant_id,
      --   warranty_registration_id, claim_id, status,
      --   created_at, updated_at) are still present
      claim_type                    text NOT NULL
                                    -- 'billable_service_request' |
                                    --   'design' | 'equipment' |
                                    --   'foundation' | 'replacement_parts' |
                                    --   'tracker' | 'workmanship'
                                    -- CHECK constraint enforces allowed values
      date_of_defect_incident       date NOT NULL
      priority_emergency            boolean NOT NULL DEFAULT false
      emergency_details             jsonb nullable
                                    -- rich text, ProseMirror-compatible JSON;
                                    -- present only when priority_emergency
                                    -- is true
      equipment_status              text NOT NULL
                                    -- 'online' | 'offline'
      offline_condition_explanation jsonb nullable
                                    -- rich text, ProseMirror-compatible JSON;
                                    -- present only when equipment_status
                                    -- is 'offline'
      loto_requirement              text NOT NULL
                                    -- 'not_required' |
                                    --   'required_claimant_responsible' |
                                    --   'required_warrantor_responsible'
                                    -- CHECK constraint enforces allowed values.
                                    -- The workbook (supply-only) listed two
                                    -- values; the platform-general schema
                                    -- extends to three to cover warrantors
                                    -- who self-perform LOTO.
      required_docs_provided        boolean NOT NULL DEFAULT false
      supporting_documents          jsonb nullable
                                    -- the multi-select of document
                                    -- categories the claimant declares they
                                    -- are providing; shape flagged below
      detailed_description          jsonb NOT NULL
                                    -- rich text, ProseMirror-compatible JSON
      submitter_name                text NOT NULL
      submitter_email               text NOT NULL
      ship_to_street                text
      ship_to_city                  text
      ship_to_state                 text
      ship_to_zip                   text
      recipient_name                text
      recipient_phone               text
      claim_type_data               jsonb nullable
                                    -- per-claim_type structured fields;
                                    -- shape varies by claim_type, defined
                                    -- below

The seven claim_type values come from Workbook 1's dropdown directly. The
enum is extensible — adding a new claim_type is a migration that updates the
CHECK constraint, the claim_type_data JSONB schema for the new type, and any
UI affordances for it.

The loto_requirement enum's three values cover the three real business
shapes. Warrantors who do no electrical work and never self-perform LOTO see
only the first two values in their operational flow (the warrantor-
responsible value never applies). Warrantors who sometimes self-perform
LOTO for electrical work in their scope may see any of the three. The
industry-default case for system-owner-installed projects is
required_claimant_responsible.

### Rich text fields use Decision 4's ProseMirror storage

Three columns store rich text: detailed_description, emergency_details, and
offline_condition_explanation. All three use the same ProseMirror-compatible
JSON storage format as Decision 4's rich-text custom field values, so the
platform has one rich-text storage convention rather than two. The character
cap defaults from Decision 4 apply (10,000 characters of effective text by
default, per-tenant configurable downward via
tenants.settings.rich_text_max_chars, hard platform ceiling 50,000). See the
Custom Field System section's Rich Text Storage subsection for the format
details.

### claim_type_data JSONB by claim_type

The claim_type_data column holds claim-type-specific structured fields. Its
schema varies by claim_type. JSONB is the locked shape here (not flagged as
a possible-child-table alternative the way supporting_documents is), because
variable-schema-by-discriminator data is the case JSONB is genuinely designed
for: the schema differs by claim_type, the fields don't decompose into
uniform child rows the way a list of attachments does, and a polymorphic
child table per claim_type would multiply the schema rather than encapsulate
the variation. JSONB is the only sensible shape.

The Replacement Parts shape is settled from Workbook 2:

    -- claim_type = 'replacement_parts'
    claim_type_data = {
      "part_name":                   text,
      "row_number":                  text,
      "row_controller_asset_id":     text,
      "description_of_issue":        text,
      "customer_comments":           prosemirror-json   -- rich text
    }

Workbook 2 also lists Customer/Job Name/Ship To/Recipient on the Parts intake
form, but those are either auto-populated from the parent registration
(Customer, Job Name) or already in the hard columns above (Ship To,
Recipient) — they do not appear in claim_type_data.

The JSONB shapes for the other six claim_types — billable_service_request,
design, equipment, foundation, tracker, workmanship — are not yet settled at
the architectural layer. Each will be defined when its specific operational
requirements surface (a per-type workbook, an SOP carving out the type's
fields, or production usage). The Foundation Issue Type sub-dropdown from
Workbook 1 is one piece of the foundation shape, but the values themselves
are operational content not yet enumerated. This is the same restraint
pattern as Section 7's specific conditions and document categorization in
Warranty Registration: the architecture commits to the mechanism
(claim_type_data JSONB), the per-type contents are downstream operational
work.

Validation of claim_type_data against the expected shape for the row's
claim_type happens application-layer at write time, in the Server Action
that creates or updates the claim. The database does not enforce
per-claim_type JSONB shape — that's the same convention used for
clock_events payload validation.

### Auto-populated context from the parent registration

Workbook 1 lists five fields as "auto-populated from parent WarrantyID, not
visible in the intake form, only visible in the claim database and PDF
generations": WarrantyID, Claim ID, Customer, Project name, Service Address.
None of these become claim columns. The architecture handles each through
existing relationships:

- WarrantyID is reachable through the warranty_registration_id FK to
  warranty_registrations.warranty_id.
- Claim ID is the claim_id hard column (already in the Tier 2 shell,
  generated at insert time).
- Customer is reachable through warranty_registrations.project_id ->
  projects.customer_id and the customer snapshots on projects.
- Project name is on projects via the same path.
- Service Address is the project's site_address_street/city/state/zip on
  projects.

Duplicating these on the claim would create sync surfaces where none is
needed; reading them is a join, not a column.

### Auto-populated does not mean immutable

A note for downstream drafting: "auto-populated" in the workbook's framing
means "filled in by the system, not by the customer at intake." It does not
imply the value is frozen at intake. The relationships through
warranty_registrations and projects reflect the current state of those
parent records. If a tenant edits the project's customer information,
claims under that project show the updated information when read. The FK +
Snapshot Pattern applies on projects.customer_id (the project's snapshot of
the customer at project-creation time is frozen); whether claim-time
snapshots of registration or project state are needed is a Phase 4 /
downstream question, not raised by any locked source.

### Custom field values for tenant-configurable intake fields

Per Decision 3, claim is one of three Phase 1 entities that support custom
fields. Tenant Team Admins define custom_field_definitions with
entity_type = 'claim'; values fill in via custom_field_values with the
claim_id FK set.

The LOTO example illustrates how this works in practice across different
business models. The hard-column loto_requirement captures the categorical
answer every claim has — is LOTO required, and if so who is structurally
responsible. Some warrantors need to capture additional detail about LOTO
responsibility beyond that categorical value — who specifically performs
LOTO, contact info for the responsible party, authorization details. These
vary by warrantor business model and are not pre-defined by the platform.
A warrantor whose business model doesn't include electrical work may need
no LOTO custom fields at all (the categorical loto_requirement field
captures everything relevant). A warrantor who sometimes self-performs may
define multiple custom fields capturing the operational detail they track.
The Custom Field System's 11 Phase 1 field types support whatever shape
fits each tenant's operational language.

The platform makes no architectural distinction between custom fields that
appear on the intake form and custom fields that appear on the claim
elsewhere in its lifecycle — both go through the same custom_field_values
mechanism. Whether a definition surfaces at intake versus during review is
an operational UI question, not a schema-level one.

### Stateless tokenized intake link

Claim intake uses the Stateless Tokenized Interaction Pattern. A customer
receives a tokenized email link to a focused intake form; no account, no
session persistence beyond the link. The token storage follows the pattern's
"shape to copy, not shared store" rule: the intake token lives on its own
record (or on the claim record itself, as an implementation detail to be
settled), not in the invitations table. The invitations precedent gives the
shape — a 64-character hex token, an expires_at timestamp, a consumed_at
timestamp — and Audit Topic 9 calls out specifically that the intake token
is "similar to invitation token but customer-facing" — same shape, separate
storage.

Whether the intake token is one column on the claim row or a separate
claim_intake_tokens table is a Phase 3 implementation detail, parallel to
the other implementation flags in this section. The architectural commitment
is that the pattern applies and the token has its own storage.

### Outstanding architectural questions

The workbooks surfaced architectural questions that this section does not
fully resolve. Each is flagged with the proposed resolution direction and
what's still open:

- Supporting documents shape. The supporting_documents column is JSONB
  above, but the architecturally cleaner answer may be a child table
  (claim_attachments) where each row is one document with its category.
  Phase 3 implementation detail; the choice between JSONB array and child
  table is settled at migration time. The user-facing semantics (multi-
  select of document categories the claimant declares they are providing)
  is locked either way. Unlike claim_type_data, this is genuinely a JSONB-
  vs-child-table choice — the data is a list of uniform items, exactly the
  case child tables handle well.
- O&M Provider as a contact. The intake form captures O&M Provider Company
  Name, Contact Name, Email, and Phone — the exact shape of a Unified
  Contacts Directory contact. The architecturally consistent answer is the
  FK + Snapshot Pattern's single-FK shape: an om_provider_contact_id FK to
  contacts with name/email/phone snapshots captured at intake. The
  contact_type for the FK is the open question — Item 16's eight Phase 1
  values include subcontractor_contact, which could fit, but a dedicated
  om_provider value may be cleaner. Resolving the contact_type is a
  downstream decision.
- Ship-to address structure. The hard columns above use four scalars
  (street/city/state/zip) following the project's site_address pattern for
  consistency. Whether this is the right level of structure or whether the
  project's address pattern itself needs revision (geocoding, international
  formats) is a future decision, not raised by any locked source.
- Claimant identity (the submitter). The Tier 2 shell flagged this; the
  workbook gives narrow data (name + email only). The hard columns above
  capture submitter_name and submitter_email directly, treating the
  submitter as a free-text capture per claim rather than a contact
  reference. The proposal is to keep it that way: a submitter is sometimes
  a customer contact and sometimes a one-off third party, FK + Snapshot
  may be too heavy for the operational shape, and free-text snapshots may
  be enough. If reporting or reuse needs surface that argue for FK +
  Snapshot, this is revisitable.
- Foundation Issue Type sub-dropdown values. Workbook 1 lists the field
  but not its values. The values themselves are operational content (which
  Foundation issues a warrantor distinguishes), not architecture. Flagged
  for downstream drafting when Foundation claim_type_data is settled.
- claim_type_data JSONB shapes for the six non-Parts claim types. Flagged
  above; each settles when its specific operational requirements surface.

### What is NOT in the intake data model

Parallel to the deliberate-omissions lists in Tier 2:

- Escalation fields. Workbooks 3 and 4 (Claim Denial Escalations Intake,
  Claim Denial Escalations Reviewer Data) are escalation entities, not
  intake. They belong to the Tier 3 Escalation Pathways section.
- Work plan and work authorization fields. Workbooks 5 and 6 are downstream
  of claim intake and belong to the Tier 3 Work Plan Workflow section.
- Review and gate state. v1's Six Gates are the operational structure of
  claim review; the values in the status column come from that structure
  but are settled when the Tier 3 claim lifecycle section is drafted.
- Outcomes, costs, ALA documents. Each is its own Tier 3 section, claim is
  the parent.

## ALA System

**Status: Designed at the architectural level.** ALA markup default and
storage locked by Decision 7. ala_templates and ala_documents schemas
follow Audit Topic 10's shape with the operational behavior the SOPs
specify. Signature capture mechanism is flagged as an open architectural
question — no locked source resolves it, and the choice has legal
implications.

ALA stands for the Owner's Consent and Assumption of Liability Agreement.
It is the document a claimant signs when a claim's causation or ownership
is unclear, accepting financial responsibility for the investigation if
the defect is ultimately found to be outside warranty scope. The agreement
exists because some claims need specialized investigation before a
warranty determination can be made, and the warrantor cannot reasonably
bear those investigation costs for non-warranty conditions on the
claimant's site. The SOPs name this the "Indistinct Claims" workflow.
v1's Six Final Outcomes lists "Indistinct Claim — ALA Required" as one of
the six possible review outcomes.

This section documents the data model and the operational behavior. It
does not specify the legal form of the agreement itself — that content is
warrantor-specific and is captured in tenant-defined templates.

### Two tables: templates and documents

The architecture is two tables in a parent-child relationship. A template
is tenant-defined and reusable; a document is per-claim and one-shot.

ala_templates holds tenant-defined template definitions — the agreement's
general shape, content, and terms as a particular warrantor configures it.
A tenant has one or more templates. Phase 1 likely has one default
template per tenant; multiple templates support warrantors who use
different agreement variants for different claim types or jurisdictions.

ala_documents holds per-claim instantiations — for one specific claim, the
specific agreement the claimant signs (or has been asked to sign), with
that claim's amounts and terms filled in, with the signer's identity
captured, with the signed-at timestamp recorded. An ALA document exists
only when a claim's outcome is Indistinct; most claims never have one.

Warrantors typically have their own internal document numbering for legal
forms like this — a tenant's template would carry whatever document
number identifier their compliance or legal practice uses. The platform
stores the template content and any tenant-supplied identifier; the
platform doesn't reserve or assign document numbers itself. Numbering is
data, not architecture.

### ala_templates schema

    ala_templates
      id              uuid PK
      tenant_id       uuid NOT NULL FK -> tenants
      name            text NOT NULL
      content         jsonb NOT NULL
                      -- the template's body, ProseMirror-compatible JSON
                      -- per Decision 4; supports the same rich-text
                      -- format as detailed_description on claims and
                      -- rich-text custom fields
      is_default      boolean NOT NULL DEFAULT false
                      -- whether this is the tenant's default template;
                      -- at most one default per tenant
      deleted_at      timestamptz nullable
                      -- soft-delete; retired templates remain queryable
                      -- because documents generated from them must
                      -- still be readable
      created_at      timestamptz NOT NULL DEFAULT now()
      updated_at      timestamptz NOT NULL DEFAULT now()

The table follows the Standard RLS Pattern's six steps. tenant_id FK,
RLS-enabled, standard SELECT policy, service-role-only writes, grants.

Content is rich text in ProseMirror-compatible JSON — the same convention
as detailed_description on claims and rich-text custom field values. A
tenant defines the template through a rich-text editor; the stored JSON
outlives any specific editor library. See Decision 4's Rich Text Storage
for the format details.

Soft-delete on templates (deleted_at) is required, not optional. A template
retired today may have generated a document last year, and that document
must remain readable for audit defensibility over the warranty horizon.
Hard-deleting a template would break the historical record. The convention
matches the Custom Field System's soft-delete pattern.

The is_default boolean identifies the tenant's primary template. At most
one is_default = true per tenant is the architectural intent; whether
this is enforced by a partial UNIQUE index or by an application-layer
invariant is a Phase 3 implementation detail.

### ala_documents schema

    ala_documents
      id                          uuid PK
      tenant_id                   uuid NOT NULL FK -> tenants
                                  -- denormalized per Standard RLS Pattern
      claim_id                    uuid NOT NULL UNIQUE FK -> claims
                                  -- UNIQUE enforces 1:1; ON DELETE
                                  -- behavior is a Phase 3 implementation
                                  -- detail parallel to other claim-child
                                  -- FK flags
      template_id                 uuid NOT NULL FK -> ala_templates
                                  -- which template this document was
                                  -- generated from; template may be
                                  -- soft-deleted later but the FK
                                  -- remains valid because of soft-delete
      content_snapshot            jsonb NOT NULL
                                  -- the template content captured at
                                  -- document generation time, frozen;
                                  -- changes to the template later do
                                  -- not affect already-generated
                                  -- documents
      markup_percent_snapshot     numeric(4,3) NOT NULL
                                  -- the tenant's ala_markup_percent value
                                  -- captured at document generation time;
                                  -- frozen
      signer_name                 text nullable
      signer_email                text nullable
      signed_at                   timestamptz nullable
                                  -- null until the document is signed;
                                  -- non-null is the architectural marker
                                  -- of "ALA in place"
      created_at                  timestamptz NOT NULL DEFAULT now()
      updated_at                  timestamptz NOT NULL DEFAULT now()
      -- CHECK / app-layer invariant: tenant_id matches the referenced
      -- claim's tenant_id

The table follows the Standard RLS Pattern. tenant_id is denormalized
directly per the convention.

UNIQUE on claim_id enforces that a claim has at most one ALA document. A
claim either is Indistinct and has one ALA, or is not Indistinct and has
none.

content_snapshot is captured at document generation, not referenced live
through template_id. This is the same defensibility logic as the FK +
Snapshot Pattern: the document the claimant signed must read identically
in twenty years even if the template was updated, retired, or
restructured. The template_id FK preserves the relationship for
reporting; the content_snapshot preserves the historical truth.

markup_percent_snapshot is also captured at document generation, frozen.
The current tenant ala_markup_percent reflects current configuration; the
percent that applied to this specific document at the moment it was
generated is what the claimant agreed to and what the audit trail must
preserve. Same defensibility logic.

The signer fields (signer_name, signer_email, signed_at) are nullable
because a document may exist as unsigned (sent to the claimant, awaiting
response) before becoming signed. signed_at being non-null is the
architectural marker that the agreement is in force.

Whether to capture the signer as a free-text snapshot (name/email pair,
as above) or as an FK + Snapshot reference to a contacts row is the same
question Claim Intake settled for the submitter, with the same answer
for the same reasons: a signer may be a customer contact or a one-off
third party, the FK is too heavy for the operational shape, free-text
snapshots are sufficient. If reporting needs surface that argue for FK +
Snapshot, this is revisitable.

### ALA markup: 10%, stored at tenants.settings.ala_markup_percent

Decision 7 locked the markup default at 10% (decimal 0.10), stored at
tenants.settings.ala_markup_percent, with application-layer validation
bounds of 0 to 0.50. The display layer converts at the edge for human
display (0.10 -> "10%" in form labels and document text).

A v1 mention referenced 15%. Decision 7 flagged this as possibly
unsourced and asked v2 drafting to verify against the six claim intake
workbooks. The workbooks were checked during this section's drafting: no
markup figure of any kind appears in any of the six workbooks. The v1 15%
is confirmed as an unsourced figure with no real-world source. Decision
7's 10% stands as the default. Tenants can configure to any value within
the 0 to 0.50 bounds.

The markup is captured at document generation through
markup_percent_snapshot on ala_documents. A tenant who changes their
ala_markup_percent later does not retroactively change documents already
generated.

### Indistinct outcome is the trigger

ALA documents exist only for claims whose review outcome is "Indistinct
Claim — ALA Required" (v1's Outcome 4 from the Six Final Claim Review
Outcomes). The Server Action handling that outcome creates the ALA
document from the tenant's default template (or a tenant-selected
template if more than one exists), populates content_snapshot and
markup_percent_snapshot, and routes the document to the claimant for
signature. The Server Action that creates the document is the trigger,
not a clock event — same convention as registration creation on
trigger_status confirmation.

Whether the routing-for-signature uses the Stateless Tokenized
Interaction Pattern, an in-app interface for a known claimant, or some
other channel depends on the signature mechanism question (see below).

### Signature capture: an open architectural question

Audit Topic 10 flagged the signature mechanism as TBD between tokenized
form acceptance and wet (physical) signature. None of the locked sources
— Decision 7, Audit Topic 10, the SOPs that name the Indistinct workflow
— resolves this. The SOPs say "signed" repeatedly without defining HOW;
they reference the agreement without specifying how it gets signed.

The question is real because the choice has legal implications. A
tokenized form-acceptance — claimant clicks a link, reviews the agreement
text, types their name or clicks "I Agree" — is operationally clean,
audit-friendly through Stateless Tokenized Interaction Pattern, and
preserves the entire interaction in the audit trail. Whether that
constitutes legally enforceable signature for the Owner's Consent's
purpose varies by jurisdiction and by the warrantor's contractual
preferences. A wet signature path — claimant prints, signs, scans/uploads
or mails back — is legally well-established but adds operational
friction and a document-handling surface.

A third path is also possible: an electronic signature service (DocuSign,
HelloSign, Adobe Sign) with established legal standing. None of the
locked sources mention this, but it bridges the two extremes.

The architectural commitment v2 makes: the ala_documents schema supports
any of these mechanisms — signer_name, signer_email, and signed_at are
generic enough to capture the outcome of any signing process. The
question of WHICH mechanism is settled by a future decision, and that
decision may need to be per-tenant (warrantors operating under different
contracts or in different jurisdictions may need different mechanisms).
Flagged as outstanding architectural question; no improvised resolution.

### Blocking-gate behavior

The SOPs are clear and stronger than Audit Topic 10's summary on this
point. Audit Topic 10 described the ALA as blocking Work Plan workflow.
The SOPs say the ALA blocks the *claim* from proceeding to investigation,
not just Work Plan downstream. SOP 1 (Accepted Warranty Claim Lifecycle):
the ALA "must be signed before the processing and investigation of the
claim can begin." SOP 0 (Warranty Management System Capabilities): the
Indistinct Claims "process will only commence following the receipt and
acceptance of the signed agreement." SOP 4 (Claim Submission
Requirements): "before [Company Name Here] will proceed."

The blocking relationship is locked architecture: a claim whose outcome
is Indistinct cannot move forward — neither to investigation nor to work
plan nor to anything downstream — until its ala_documents row exists and
has signed_at non-null. The Server Actions that would otherwise advance
the claim must check for this and refuse the advance if the gate is not
cleared.

The specific claim-status values that interact with this gate — what
status the claim is in while awaiting signature, what status it moves to
on signing, how this composes with the rest of the Six Gates flow — are
operational state-machine details that the Tier 3 claim lifecycle section
settles. The architectural commitment is the blocking relationship
itself; the state-machine particulars are downstream.

### What is NOT in the ALA system

Parallel to the deliberate-omissions lists elsewhere:

- No custom field involvement. Templates are tenant-defined documents,
  not custom field definitions on the claim. The Custom Field System is
  for fields that vary by tenant on claim entities; ALA templates are
  documents.
- No clock events. ALA generation is a synchronous Server Action effect
  on the Indistinct outcome, not a future-firing event. Reminder
  notifications to a claimant who has not signed within some window
  might use clock events in a future iteration, but no locked source
  specifies this yet.
- No automatic enforcement of the markup-bounds at the database level.
  Decision 7 places that validation in the application layer; the
  tenants.settings JSONB does not enforce numeric bounds in PostgreSQL
  by default. The Server Action that updates the setting is the gate.
