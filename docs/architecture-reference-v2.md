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
