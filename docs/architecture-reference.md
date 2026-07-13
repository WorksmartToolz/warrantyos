**Last updated:** 2dcdfbd 2026-07-12

# WarrantyOS — Architectural Reference (v2, Prototype Phase)

> **Status:** Canonical architecture reference (promoted 2026-07-12). This
> document supersedes the Phase 2 baseline, archived at
> `docs/archive/architecture-reference-v1-phase2-baseline-ARCHIVED.md`. It is
> the current source of truth for system architecture. Sections are marked with an
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

### View security convention (per Decision 24.5)

Views on tenant-scoped tables MUST be created with the `security_invoker = true`
attribute. This attribute is REQUIRED and non-optional for any view whose
underlying tables are subject to RLS policies.

The default behavior of Postgres views is SECURITY DEFINER semantics — the view
executes with the privileges of the view owner rather than the querying user.
When the view owner is a role with RLS bypass or when RLS policies are not
evaluated during view execution, this default silently bypasses tenant
isolation. A view without `security_invoker = true` on tenant-scoped tables
creates a cross-tenant data leak vector regardless of how the underlying
tables' RLS policies are defined.

The `security_invoker = true` attribute (Postgres 15+) causes the view to
execute with the querying user's privileges, respecting RLS policies on the
underlying tables. Tenant isolation is preserved end-to-end from the view
through to the base tables.

Requirements:

- Every migration creating a view on tenant-scoped tables MUST include
  `WITH (security_invoker = true)` in the CREATE VIEW statement
- Every migration altering an existing view MUST preserve the
  `security_invoker = true` attribute
- Views must have appropriate GRANTs for the application role that PostgREST
  uses, following the same pattern as base table GRANTs (missing GRANTs on
  a view produce the same failure mode as missing GRANTs on a table — the
  Phase 1 missing-GRANTs incident is the precedent)

The trigger case for this convention is Decision 24, which introduces the
first view (`warranty_coverages_effective`) exposing derived
effective_start_date and effective_end_date columns via a cross-table
COALESCE. Decision 24's Resolution 24.5 documents the specific application
of this convention to that view.

Future Decisions introducing views on tenant-scoped tables MUST reference
this convention and confirm compliance in their view definitions.

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

Six interaction surfaces use this pattern. All six are the same mechanism
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
- **Service report customer review (customer-facing).** When the warranty
  professional accepts a submitted Service Report, the customer is notified
  via a tokenized link to a focused review interface with three possible
  actions: accept the report, dispute the report, or take no action.
  Silence is structurally treated as acceptance ('the warrantor shall
  consider the silence acceptance' per SOP 1); a three-day customer review
  window backstops the no-action case.
- **Customer Work Authorization (customer-facing).** For each on-site event
  requiring physical presence at the customer's site (inspection, repair,
  site visit), the customer receives a tokenized link to the Work
  Authorization form. Approval requires a signature artifact (typed name +
  acknowledgment checkbox). Per Decision 11, universal blocking-gate
  behavior: no on-site activity proceeds without an approved Work
  Authorization for that specific event.
- **ALA signing (claimant-facing).** Per Decision 19, for claims with the
  Indistinct outcome, the claimant receives a tokenized link to the ALA
  document. The flow is two-step with atomic Accept-and-Signature: claimant
  chooses Accept or Decline; if Accept, the signature step captures the
  electronic signature in the same atomic Server Action write. Decline
  triggers a per-tenant configurable warning and opens a configurable
  recant window during which the warrantor can re-issue the ALA.
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
surface of one-off security decisions. One pattern, applied six-plus times,
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

Three flags ship in Phase 1:

- **`epc_workflow`** — gates the EPC trigger sources (`contractual_date_manual`,
  `wbs_integration`) and EPC-specific UI: WBS integration configuration,
  milestone date entry, EPC-flavored registration prep flows.
- **`supply_only_workflow`** — gates the supply-only trigger sources
  (`delivery_report_tokenized`, `delivery_report_api`) and supply-only-specific
  UI: delivery-reporting form configuration, overdue-trigger escalation surfaces,
  supply-only-flavored registration prep flows.
- **`service_report_acquiesce_window`** — gates the silence-acceptance path
  (Assumption of Acquiesce per SOP 1) on Service Report customer review.
  When enabled (default), the service_report_response_due clock event is
  created at Service Report issuance and silence-acceptance fires at window
  expiry. When disabled, the clock event is NOT created; the customer must
  explicitly accept or dispute via the tokenized review interface; the claim
  remains open until the customer acts. Added by Decision 21.5.

All three default to enabled at provisioning. Hybrid tenants leave the
workflow flags both on; pure-shape tenants disable the one they don't use.
Tenants who want explicit-only customer review on Service Reports (no
silence-acceptance) disable service_report_acquiesce_window.

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
- `om_provider`
- `om_provider_contact`
- `registration_assignee`
- `other`

Ten categories total. The `om_provider` and `om_provider_contact` values were
added by Decision 20, which recognized O&M Providers as a distinct operational
party (operators and maintainers of the warrantied system, typically engaged
as the customer's authorized agent for warranty matters).

This is a single-table approach for the prototype. The alternative — a separate
table per contact kind — is held in reserve: specialized tables are introduced
only if type-specific fields proliferate to the point that one shared shape
stops fitting. Until then, one table with a discriminator is simpler to query,
simpler to import into, and simpler to reference.

#### Matched-pair traversal: parent_contact_id

Four contact_type values appear in matched pairs — an organization-level
contact_type and an individual-contact variant: customer + customer_contact,
subcontractor + subcontractor_contact, vendor + vendor_contact, and om_provider
+ om_provider_contact. The individual-contact variants must reference their
parent organization to enable agency and authorization traversal. The contacts
table carries a `parent_contact_id` column for this purpose:

- `parent_contact_id` uuid nullable FK -> contacts (self-referential)
  -- references the parent organization contact when this row is an
  --   individual-contact variant
  -- null for organization-level rows (customer, subcontractor, vendor,
  --   om_provider)
  -- null for non-matched-pair rows (registration_assignee, other)

CHECK / application-layer invariant: when contact_type ends in `_contact`,
parent_contact_id MUST be non-null, and the referenced row's contact_type
MUST be the matching organization-level type (e.g., om_provider_contact's
parent must have contact_type = 'om_provider'). The mechanism was added by
Decision 20 to enable the authorized-agent agency check (per Decision 20.4)
but applies to all matched pairs.

#### Customer-O&M Provider relationship: linked_om_provider_id

Customer rows (contact_type = 'customer') carry an additional column capturing
their currently engaged O&M Provider, per Decision 20:

- `linked_om_provider_id` uuid nullable FK -> contacts
  -- references contacts where contact_type = 'om_provider'
  -- nullable; not all customers engage an O&M Provider

CHECK / application-layer invariant: when linked_om_provider_id is non-null,
the referenced contact row MUST have contact_type = 'om_provider'.

The column is updatable when the customer changes O&M Provider; historical
relationships are preserved through the transaction-time FK + Snapshot Pattern
on operational tables (claim records, parts orders, documents capture the O&M
Provider at the moment of action). The current linked_om_provider_id reflects
only the present state.

Customer-row-scope flexibility: tenants who need per-site O&M Provider
modeling (one O&M Provider for the inverter side, another for the panel side
of a single commercial customer) can model this via per-site customer rows.
Each customer-row-as-site has its own linked_om_provider_id. The single-FK
choice does not constrain multi-O&M-Provider scenarios; tenants choose their
customer-row granularity to match their commercial relationships.

#### contact_type immutability discipline

contact_type is effectively immutable per row. If a contact's operational
role changes (rare — e.g., a customer_contact who becomes a subcontractor_
contact at a different company), a new contact row is created rather than
UPDATE on the existing row. Server Action layer enforces this discipline;
the schema does not.

This discipline matters for derivable-not-stored patterns (Decision 20.4):
operational tables capture actors via contact_id, and downstream queries
derive role through contact_type lookup. The discipline ensures the actor's
contact_type at the moment of query equals the actor's contact_type at the
moment of action.

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
                      -- 'project' | 'claim' | 'warranty_coverage' |
                      -- 'work_authorization_document' |
                      -- 'service_report' | 'ala_document' |
                      -- 'warranty_registration' | (extensible)
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

### Event types

The event_type enum is extensible. The full set as of Decision 25:

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
- service_report_response_due — fires when a service report's customer review
  window expires. If customer_decision is still null at firing, the row is
  updated to customer_decision = 'accepted', accepted_by_acquiescence = true,
  and claim closure is initiated. Added by Service Report Submission.
- work_authorization_response_overdue — fires when a Work Authorization
  document's expected_response_date passes with customer_decision still null.
  Reminder-only; no state mutation. Added by Customer Work Authorization
  (Decision 11).
- ala_decline_window_expired — fires at decided_at +
  ala_decline_recant_window_days when claimant_decision = 'declined'; marks
  the decline permanently terminal and unblocks claim denial workflow. Added
  by Decision 19.
- ala_response_overdue — fires when an ALA's response window (tenant-
  configurable business days, default 7) expires with claimant_decision still
  null. Reminder-only; sets overdue_flagged_at without touching
  claimant_decision. Added by Decision 25.
- warranty_id_early_issuance — fires at trigger_date (kept in sync with
  actual_start_date confirmation). Issues warranty_id if not already set
  by Section 7 completion; no-ops otherwise. Added by Decision 27.

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

## Database Migration Tooling

**Status: Designed** (the six-step baseline procedure per Decision 22.2, the
six pre-procedure verification gates per Decision 22.3, the drift verification
gate per Decision 22.9, the six named failure modes per Decision 22.5, the
Mode C gating per Decision 22.10, and the four Phase 4 transition criteria per
Decision 22.8 are architecturally locked. Procedure execution against the
hosted database is Phase 4 work, gated by the CLAUDE-rev6.md stop-point until all
four transition criteria in Decision 22.8 are satisfied. This section is the
authoritative reference for the procedure and for ongoing migration tooling
mechanics across the platform lifecycle.)

This section is the authoritative reference for database migration tooling in
WarrantyOS — how schema migrations are applied to the hosted Supabase
database, the one-time baseline procedure required before Phase 4 work can
begin, the failure modes that could occur during baseline and their recovery
procedures, and the ongoing operational mechanics for migrations after
baseline completes. It is distinct from Data Migration Tooling (covered in
its own section elsewhere in v2), which handles customer data import at
tenant onboarding via CSV/Excel upload. Database Migration Tooling covers
schema mechanics; Data Migration Tooling covers customer data mechanics.
Both are load-bearing for the platform, and they are architecturally
independent.

Decision 22 (session-handoffs/5e-bridge-phase3-decisions-log-rev6.md) is the
architectural authority for the material in this section. This section
documents Decision 22's ten commitments in reference-usable form and adds
the ongoing operational mechanics that Decision 22 flagged as belonging in
this section.

### Historical context: why baseline is required

The hosted/remote Supabase database's migration_history table has no record
of 000_baseline.sql or migrations 001 through 004. The absence is not a bug;
it reflects the actual history of how the initial schema was applied.

Before the migrations directory existed in the repo, the initial tables —
tenants, users, invitations, and the tenant-scoping infrastructure that
supports Standard RLS Pattern — were created manually in the hosted
Supabase project's SQL Editor. Those tables were the operational schema
for what became the Session 5e-bridge branch's work. When the migrations
directory was later established, the existing tables on the hosted DB were
NOT recreated via migration; they already existed and were being used.
Migration 000_baseline.sql was constructed as the warrantor's best
reconstruction of what had been manually applied, so that the migration
chain could replay from an empty database (a local Supabase stack, for
instance) and produce the same schema state as the hosted DB.

The consequence is a divergence: locally, the migration chain applies from
000_baseline through 004_team_admin_management to build the schema; on the
hosted DB, the schema was constructed manually before migrations existed,
and the migration_history table records nothing about how it got there.
The hosted DB has the tables. It does not have the record of when or by
what migration each table was created.

This divergence is safe as long as no one runs supabase db push or
supabase migration up --linked against the hosted DB. If either is run,
the CLI will attempt to apply migrations 000 through the newest one,
detecting that migration 000 has not been applied per migration_history,
and attempting to CREATE TABLE tenants (which already exists) — producing
either an error or, worse, silent corruption depending on the specific
migration content. The CLAUDE-rev6.md stop-point (lines 71-83 as of this
writing) documents this hazard and instructs Claude Code to STOP before
running any command that could trigger this failure.

The baseline procedure resolves the divergence. It writes rows to the
hosted DB's migration_history table for migrations 000 through 004,
marking them as already-applied, WITHOUT running the migration SQL.
The CLI's `supabase migration repair` command is the tool for this: it
updates migration_history without touching the schema. After baseline
completes, subsequent supabase db push commands only attempt to apply
migrations 005 and later.

This is a one-time procedure. Once baseline is complete and Phase 4
transition criteria per Decision 22.8 are all satisfied, the CLAUDE-rev6.md
stop-point is updated to RESOLVED and Phase 4 work proceeds normally.
The hazard becomes historical context preserved in this section.

### The locked baseline procedure

Per Decision 22.2, the procedure is a six-step sequence. Each step has
explicit verification before proceeding to the next.

**Step 0 — Backup current migration_history table contents.**

Before any modification, capture the current state of the
supabase_migrations.schema_migrations table to a file. The table is
trivially small; the safety net matters.

Mechanism: query the table via psql or Supabase CLI, persist to disk under
a timestamped filename. Suggested naming convention:

    supabase_migrations_schema_migrations_backup_<YYYYMMDD-HHMMSS>.sql

The backup file is retained in the operator's local environment (not
committed to the repo, following the same convention as any operational
artifact containing potentially sensitive schema information). The backup
serves as the recovery baseline if Mode C (see failure modes below)
becomes necessary during or after the procedure.

**Step 1 — Pre-procedure verification gates.**

All six verification gates documented below (Pre-procedure verification
gates subsection) must pass before any repair command runs. If any gate
fails, STOP. Do not proceed to Step 2.

**Step 2 — Run five sequential repair commands.**

    supabase migration repair --linked --status applied 000
    supabase migration repair --linked --status applied 001
    supabase migration repair --linked --status applied 002
    supabase migration repair --linked --status applied 003
    supabase migration repair --linked --status applied 004

Each command marks one local migration as already-applied without
re-running the migration's SQL. The procedure is sequential (not a single
command with multiple version arguments) for explicit per-step verification
gates between commands. Single-command alternatives — for instance,
`supabase migration repair --linked --status applied 000 001 002 003 004` —
are deliberately not used because they defer all verification to the end
and lose per-step state visibility.

The procedure is idempotent at the migration level. Running
`supabase migration repair --linked --status applied <version>` on a
migration that is ALREADY marked applied is a no-op or
success-on-already-applied. This idempotency is what makes Mode B recovery
(partial completion across commands) safe: the operator can re-run the
procedure from the beginning without concern for double-marking migrations
that succeeded in an earlier partial run.

**Step 3 — Per-command post-verification.**

After each repair command succeeds, verify via
`supabase migration list --linked` that the just-repaired migration shows
as applied. If the list shows an unexpected state after any single repair,
STOP and investigate before proceeding to the next migration.

**Step 4 — Final post-procedure verification.**

After all five repair commands succeed, `supabase migration list --linked`
should show all five migrations as applied:

    000_baseline                | applied
    001_invitations             | applied
    002_security_hardening      | applied
    003_team_admin_role         | applied
    004_team_admin_management   | applied

If the final list differs from this expected state, STOP and investigate
before declaring baseline complete. Discrepancies at this point indicate
either partial success that Step 3's per-command verification should have
caught, or unexpected state (Mode C — see failure modes below) that
requires Mode C gating.

**Step 5 — Schema.sql regeneration smoke test.**

After baseline is verified per Step 4, run the schema.sql regeneration
mechanism established by Decision 10 (scripts/generate-schema-sql.mjs).
Confirm the output matches expected — the regeneration should produce
effectively no change from the current committed schema.sql, since
baseline established the same state that was already on disk.

If schema.sql regeneration produces unexpected output, STOP. The
regeneration mechanism is the Phase 4 development feedback loop for
schema changes; it must be working correctly before Phase 4 begins.
Unexpected output at this step is a signal that either the local schema
diverged from what was baselined, or the generator mechanism itself has
an issue. Both cases require investigation before Phase 4 unblocks.

### Pre-procedure verification gates

Per Decision 22.3, six gates must pass before Step 2 of the baseline
procedure runs. The gates are ordered by execution sequence; each is
independent, and a failure of any gate halts the procedure.

**Gate 1 — Local repo state.**

`git status` returns clean; the working tree is on the expected branch
(the current Phase 3 branch through Session B and Session C-prime; will
be the equivalent Phase 4 branch when baseline actually executes).

The rationale is defensive: an unclean working tree indicates in-flight
work that might interact with the baseline procedure in unexpected ways.
Better to clean the working tree first and re-verify than to attempt
baseline with local changes that might have been intended to accompany
it. If the operator explicitly wants uncommitted changes present during
baseline (unusual), the operator makes that call explicitly and documents
it in the session-handoff entry per Decision 22.8 condition 3.

**Gate 2 — Local migrations present.**

`ls supabase/migrations/` returns the expected five files:

    000_baseline.sql
    001_invitations.sql
    002_security_hardening.sql
    003_team_admin_role.sql
    004_team_admin_management.sql

If additional migrations exist (005+, added during Phase 3 development
after Decision 22 was drafted), the baseline procedure still applies to
migrations 000-004 only. Migrations 005+ are applied via subsequent
supabase db push after baseline completes. If migration files 000-004
are missing or renamed, STOP — the discrepancy indicates local repo
state does not match the baseline procedure's assumptions.

**Gate 3 — Supabase CLI authenticated and version pinned.**

`supabase projects list` returns the expected project without
authentication errors. The CLI version is verified to match the version
that was tested at Decision 22 documentation time.

The CLI version pin protects against the failure mode where a newer or
older CLI version handles `supabase migration repair` differently than
the version the procedure was documented against. `supabase migration
repair` behavior is version-dependent; the CLI's release notes are the
authoritative source for behavioral changes across versions. If the
locally installed CLI version differs from the pinned version, STOP —
this is failure mode F (CLI version mismatch, see below).

The pinned version is captured either in CLAUDE-rev6.md alongside the
stop-point or in a repo-committed config file. Visual inspection of
"looks like the current version" is not sufficient; the check is exact
version-string match.

**Gate 4 — Linked project verified against known-good project ID.**

`supabase status --linked` shows the correct project ID. The correct ID
is stored persistently — in CLAUDE-rev6.md or a committed config file — and
the verification compares the returned ID against the stored ID exactly.

Visual inspection of "this looks like our project" is NOT sufficient.
A single-character typo in project ID is unrecoverable surgery on the
wrong database — running the baseline procedure against a test project
or a different tenant's project would insert spurious migration_history
rows that would then need Mode C SQL surgery to reverse. Prevention at
Gate 4 is much cheaper than recovery via Mode C.

The stored project ID lives in a location that (a) is committed to the
repo (so it's version-controlled and auditable), and (b) is protected
by the same security posture as CLAUDE-rev6.md. A dedicated config file
under docs/operational/ is one appropriate location; embedding the ID
in CLAUDE-rev6.md alongside the stop-point is another. The specific location
is an operator preference; the architectural commitment is that the ID
is stored persistently rather than remembered.

**Gate 5 — Migration history pre-state strict commitment.**

`supabase migration list --linked` must return one of two acceptable
pre-states:

- (a) Empty migration_history table — the expected greenfield case for
  the documented hazard. Migration_history has never been written to.
- (b) One or more of 000-004 already marked applied — the idempotent
  partial-completion recovery case. A prior baseline attempt succeeded
  for some migrations but not others; the operator is resuming from
  where the prior attempt left off.

Any other pre-state — for example, 005+ entries present, or unknown
version strings, or partial state across migrations that shouldn't be
in the history yet — triggers STOP for human investigation. The
baseline procedure does NOT silently overwrite unexpected state.

If Gate 5 returns unexpected state, the operator documents what was
found in a session-handoff entry and determines the appropriate response
outside the baseline procedure's scope. Depending on what was found,
the response might be: correct project (Gate 4 was actually wrong,
different DB), Mode C intervention (see Mode C gating below), or
restore from point-in-time backup (out of scope for this Decision).

**Gate 6 — Drift verification between local files and actual remote
schema.**

Per Decision 22.9, this is the most critical of the six pre-verification
gates. Before any repair command runs, generate the actual remote schema
via `supabase db diff` and compare against the local supabase/schema.sql
(Decision 10's generated artifact).

The mechanism is documented in detail in the Drift verification
subsection below. The gate itself is: if local schema.sql matches actual
remote schema, proceed to Step 2. If they don't match, STOP and reconcile
before proceeding.

Drift verification prevents the most consequential silent failure mode
(Mode D — see failure modes below). Without this gate, the baseline
procedure runs against a state where the migration_history's claim
of what's applied ("000-004 are all applied") could be inconsistent
with what's actually in the schema — a divergence that manifests
months later when a downstream migration fails because it assumes
state that isn't present. The Drift verification subsection below
covers the mechanism, the two reconciliation paths, and why bypassing
this gate is architecturally rejected.

### Failure modes and recovery procedures

Per Decision 22.5, six failure modes are named and their recovery
procedures documented. Modes A through C are procedural failure modes
that manifest during or immediately after execution. Modes D through F
are the silent or upstream failure modes that pre-verification gates
prevent.

**Mode A — Repair command itself fails.**

The CLI returns an error before modifying migration_history. Typical
causes: authentication failure, network transient error, CLI version
mismatch producing unexpected behavior.

Recovery: address the underlying error, retry the failing command. No
state change occurred (the CLI returned an error before writing),
so no rollback is needed. The procedure resumes from the failed
command.

Detection: the CLI returns a non-zero exit status and an error message
identifying the specific failure.

**Mode B — Partial completion across commands.**

Some repair commands succeed, others fail partway through. Example:
000, 001, and 002 succeed; 003 fails due to Mode A; 004 has not yet
been attempted.

Recovery: identify which migrations are already marked applied via
`supabase migration list --linked`. Resume the procedure from the next
unrepaired migration. The procedure's per-migration idempotency
(commitment in Decision 22.2) makes re-running repair on
already-applied migrations safe — the CLI treats them as no-ops.

Detection: after any Mode A failure, `supabase migration list --linked`
shows a partial state. The operator identifies the state before
resuming.

**Mode C — All repairs succeed but migration history doesn't match
expectations.**

All five repair commands returned successfully. However, the resulting
migration_history state differs from what was expected — perhaps rows
appear that weren't marked, or expected rows are missing, or version
strings differ.

Recovery: direct SQL surgery on supabase_migrations.schema_migrations.
This is the most invasive recovery procedure and is gated by Decision
22.10's five named gates (documented in Mode C gating subsection
below).

Detection: after the procedure completes, Step 4's final post-procedure
verification catches the mismatch. If the mismatch is subtle enough
that Step 4 doesn't catch it, subsequent migration attempts eventually
surface it via failed migration application.

**Mode D — Drift between local migration files and actual remote
schema.**

This is the most consequential silent failure. Post-repair, the
migration_history claims a state (all migrations 000-004 applied) that
doesn't match what the database actually contains (some divergent
schema from what the migrations describe). Subsequent migrations 005+
may fail when they assume baseline state that isn't present, sometimes
months after the baseline itself succeeded.

The drift verification gate (Gate 6 of pre-procedure verification, full
mechanism in Drift verification subsection below) prevents this mode
from manifesting at baseline time.

Recovery if Mode D is detected post-baseline (drift discovered after
the procedure completed): the situation requires Mode C-style
intervention on the migration_history plus reconciliation of the
local schema.sql and/or 000_baseline.sql to align with actual remote
state. This is a Category 3 incident — surface via
session-handoff entry, evaluate against Mode C gating, execute
reconciliation with explicit warrantor approval and independent
verification.

Detection mechanism: `supabase db diff` shows differences between
local schema.sql and remote that should not exist post-baseline.
The `supabase migration list --linked` shows the migrations as
applied, but the actual schema differs from what those migrations
would produce.

**Mode E — Wrong linked project.**

The baseline procedure is run against a project that is NOT the
production project — typically a test project, a development project,
or another tenant's project. Spurious migration_history rows are
inserted on the wrong database.

Prevention: Gate 4 (linked project verified against known-good stored
project ID) catches this before Step 2 runs. If the gate fails, the
operator does not proceed to Step 2.

Recovery if Mode E is detected AFTER Step 2 has already run against
the wrong project: requires Mode C intervention on the wrong project
to remove the spurious baseline entries, then correction of the
project linkage via `supabase link --project-ref <correct-id>`, then
restart of the baseline procedure from Step 0 against the correct
project. The wrong-project intervention is Mode C-gated.

**Mode F — CLI version mismatch.**

The Supabase CLI locally installed at baseline time is a different
version than the one Decision 22 was documented against. Repair
behavior is version-dependent; a CLI version mismatch could produce
unexpected or subtly different behavior.

Prevention: Gate 3 (Supabase CLI version pinned) catches this before
Step 2 runs.

Recovery if Mode F is detected before Step 2: install the pinned CLI
version, re-run pre-verification. Recovery if Mode F is detected
after Step 2 has run with the wrong version: case-by-case
investigation based on actual observed behavior; may require Mode C
intervention depending on what the wrong CLI version actually did.

### Mode C gating: last-resort escape valve

Per Decision 22.10, direct SQL surgery on
supabase_migrations.schema_migrations is the recovery mechanism for
Mode C (and the intervention path for Modes D and E post-execution).
This is rare, high-risk, high-context work. Mode C gating enforces
five named gates before any SQL runs.

The gates apply to any Mode C intervention regardless of what triggered
it. The five gates are not procedural nicety; they are the safety net
that prevents Mode C — the last-resort recovery — from becoming itself
a failure vector.

**Gate 1 — Backup before modification.**

Capture the current contents of supabase_migrations.schema_migrations
to a file before running any UPDATE or DELETE. If Step 0 of the baseline
procedure already captured this backup, verify the file exists and is
current. If it does not exist or is stale (a fresh state has since
been established), capture it now.

The table is trivially small; the backup cost is negligible; the safety
net matters.

**Gate 2 — Explicit warrantor approval of the specific SQL.**

Not generalized "warrantor approval" for Mode C in the abstract — the
specific SQL that will run must be stated in full and approved by the
warrantor by name. Approval covers the specific SQL statements. Any
change to the SQL — even minor — requires re-approval.

The SQL is stated in full because Mode C SQL frequently involves
subtle logic (checking specific version strings, updating specific
rows) that is hard to describe abstractly without introducing errors.
Full SQL removes that ambiguity.

**Gate 3 — Independent verification round on the specific SQL.**

The proposed SQL is presented to an independent verifier before
execution. In practice this is the chat 4 verification round pattern
used during architectural drafting: paste the proposed SQL into a
separate Claude context and request independent review for correctness,
side effects, and edge cases.

Mode C SQL is rare enough that the verification round overhead is
justified. The independent read may catch concerns about related rows,
related state (foreign key implications on other rows in the same
table, though supabase_migrations.schema_migrations is standalone),
or edge cases in the specific version strings being modified.

**Gate 4 — Session-handoff entry documenting the surgery.**

Before the SQL runs, a session-handoff entry is drafted capturing:
the SQL to be applied, the rationale, the verification steps run
(including Gates 1-3), the state before, and the expected state after.
This entry becomes part of the incident-handling record.

The session-handoff entry goes in the decisions log or, if a dedicated
incident-handling section is later added to v2, that section. The
architectural commitment is that Mode C surgery is documented at the
time of intervention, not reconstructed after the fact.

**Gate 5 — Post-modification verification.**

Immediately after the SQL runs, `supabase migration list --linked` is
re-run and the actual state is compared against the expected state
from Gate 4. If they match, the intervention is complete; the
session-handoff entry is updated with the confirmed post-state. If
they don't match, more surgery is required — return to Gate 1 with
new SQL. This is a loop, not a one-shot; each iteration is a full
Mode C invocation with its own five-gate cycle.

If any of the five gates cannot be satisfied, the intervention does
not proceed. If actual state is genuinely unrecoverable through CLI
commands AND Mode C is also unworkable — for instance, the
supabase_migrations table itself is in an unexpected state that Mode C
SQL cannot address — the recovery path becomes "restore from
point-in-time backup." That path is out of scope for this section
but is flagged for awareness. Backup restoration is a Supabase
platform capability that operates on the entire database rather than
targeting migration_history specifically.

### Drift verification: the critical pre-baseline gate

The most consequential failure mode is Mode D — drift between local
migration files and the actual remote schema. Post-baseline, the
migration_history claims a state that the database doesn't actually
have. Subsequent migrations 005+ assume baseline state that isn't
present, and they fail — sometimes months after the successful
baseline, in ways that appear unrelated to the baseline.

Drift verification prevents this mode from manifesting at baseline
time by comparing local schema.sql against actual remote schema
BEFORE marking any migration as applied.

**The mechanism.**

Before Step 2 of the baseline procedure runs:

1. Generate the actual remote schema via `supabase db diff`. This
   command compares the linked remote database against the local
   schema state and produces a description of any differences.
2. Compare against the local supabase/schema.sql (Decision 10's
   generated artifact). The local schema.sql is the authoritative
   representation of what the migration chain SHOULD produce; the
   remote is what actually exists.
3. If they match — no significant drift — proceed to Step 2.
4. If they don't match, STOP and reconcile before proceeding.

The mechanism is not automated. The comparison is human-verified,
with the diff output as the reference. The rationale is that
"significant drift" involves architectural judgment that automation
would either miss (subtle logic differences) or false-positive
(cosmetic differences like whitespace or column ordering that don't
affect semantics).

**The reconciliation paths.**

When drift is detected, two real paths are available:

- (a) Update 000_baseline.sql to match actual remote state. The
  remote is treated as the source of truth. Manual SQL Editor changes
  that constitute the difference are captured as architectural
  decisions that should persist. The local 000_baseline.sql is
  revised to reflect them. Subsequent commit of the updated
  000_baseline.sql aligns local files with remote reality.

- (b) Apply corrective SQL to the remote to bring it into alignment
  with the local file. The local file is treated as the source of
  truth. Manual SQL Editor changes that constitute the difference
  are treated as accidental drift that should be corrected. Corrective
  SQL is applied to the remote to restore the state that
  000_baseline.sql describes.

The choice depends on which state is architecturally correct. Path
(a) is appropriate when the remote state captures operational decisions
that were intentional but weren't propagated to local files. Path (b)
is appropriate when the remote state is accidental — someone made
a change directly against the remote that shouldn't have persisted.
The determination requires operational context and is not automatable.

Either path requires:

- Explicit warrantor approval of the specific change being made
- A session-handoff entry documenting the reconciliation
- Post-reconciliation re-verification (re-run the `supabase db diff`
  and confirm match)

Only after reconciliation is complete AND re-verification confirms
match does the baseline procedure proceed to Step 2.

**Why bypassing this gate is architecturally rejected.**

The drift verification gate is non-optional. Bypassing it — running
Step 2 without confirming local and remote schemas match — converts
the baseline procedure from a safe and idempotent operation into a
potential silent corruption of migration_history.

The failure mode is not that the procedure fails visibly; it's that
the procedure succeeds visibly while producing an inconsistent state.
Silent success on invalid input is the worst possible failure shape
for a foundational schema operation. Later migrations that depend on
the baseline being accurate fail in confusing ways that don't obviously
trace back to the baseline — increasing the diagnostic cost by orders
of magnitude.

The gate is fast to check (a few seconds), free to skip only in the
sense that skipping doesn't produce an immediate error, and expensive
to skip in the sense that skipping creates a class of failure that
manifests months later. The architectural commitment is that this
trade is not acceptable.

### Phase 4 transition criteria

Per Decision 22.8, Phase 4 work involving migrations can begin once
four conditions are ALL satisfied. The four conditions are ordered:
each is a prerequisite for the next.

**Condition 1 — Baseline procedure executed and verified.**

Steps 0 through 4 of the baseline procedure are complete. All
per-step verification gates passed. `supabase migration list --linked`
shows all five migrations 000-004 as applied. No unresolved failure
modes remain.

**Condition 2 — Schema.sql regeneration mechanism verified working
post-baseline.**

Step 5 of the baseline procedure is complete. The schema.sql
regeneration mechanism (scripts/generate-schema-sql.mjs per Decision
10) runs successfully post-baseline and produces expected output.
This confirms that the Phase 4 development feedback loop for schema
changes is functional; without this confirmation, subsequent Phase 4
migrations couldn't be reliably verified against schema.sql.

**Condition 3 — Session-handoff entry documenting successful
execution.**

A session-handoff entry records the execution date, the verifying
warrantor, the pre-state observed (per Gate 5 of pre-procedure
verification), the post-state confirmed (per Step 4's final
verification), and any anomalies encountered and resolved during
execution. This entry becomes the permanent audit record that
baseline was successfully completed. Future operators reviewing the
project's history can find this entry and understand what happened,
when, and by whom.

**Condition 4 — CLAUDE-rev6.md stop-point updated to RESOLVED.**

The stop-point text in CLAUDE-rev6.md (currently lines 71-83 as of this
writing) is updated to RESOLVED status with the execution date. This
is the LAST step in the Phase 4 transition. It signals that Phase 4
is unblocked.

Condition 4 is deliberately last. It is not parallel to verification;
it is the readiness signal that follows successful verification.
Sequence: complete baseline (Conditions 1-2) -> session-handoff entry
(Condition 3) -> CLAUDE-rev6.md update (Condition 4) -> Phase 4 unblocked.

Before all four conditions are met, Phase 4 work is BLOCKED. After
all four are met, Phase 4 work proceeds normally and the stop-point
becomes historical context preserved in this section.

Three additional considerations were surfaced during Decision 22
drafting but were not added to the locked conditions:

- Test migration smoke test — applying a no-op migration end-to-end
  through the migration pipeline post-baseline to confirm the entire
  path works. Useful operational hygiene worth doing alongside Step
  5's schema.sql regeneration, but not a locked Phase 4 gate.
- Backup verification before Phase 4 starts — confirming a recent
  point-in-time backup exists before declaring Phase 4 unblocked.
  Standard pre-major-work hygiene worth doing, but not a locked
  Phase 4 gate specifically for migration tracking.
- Drift re-verification post-baseline — running `supabase db diff`
  after Step 5 to confirm no drift emerged during the procedure.
  Made redundant by Gate 6 (drift verification as pre-verification
  gate); if Gate 6 was satisfied and Step 5's regeneration produces
  expected output, drift is architecturally impossible at Step 5's
  completion.

### Ongoing operational mechanics post-baseline

After Phase 4 transition is complete, migration tooling operates
normally for the remainder of the platform's lifecycle. The mechanics
below describe the post-baseline steady state.

**Applying new migrations to the hosted DB.**

Once baseline is complete, `supabase db push` applies new migrations
to the hosted DB. The command inspects migration_history and applies
any migrations not yet marked as applied. Migrations 005+ (added
during Phase 4 development or later) are applied through this
mechanism.

The pre-push verification pattern is:

1. `git status` — clean working tree, on the expected branch
2. `supabase migration list --linked` — confirm the current
   migration_history state matches expectation (all migrations
   up to the most-recent-applied are marked applied)
3. `supabase db push` — apply pending migrations
4. `supabase migration list --linked` — confirm all migrations
   including the just-pushed ones are marked applied
5. Regenerate schema.sql via scripts/generate-schema-sql.mjs
6. Verify schema.sql reflects the new migrations (diff against
   the pre-push schema.sql should match the new migrations)
7. Commit the updated schema.sql alongside the migration files
   in the same commit

This pattern is intentionally verbose. The verbosity encodes the
same defense-in-depth thinking that motivates the baseline procedure:
each step verifies the previous state before proceeding, so
inconsistencies are caught immediately rather than silently
propagating.

**Schema.sql regeneration.**

Per Decision 10, schema.sql is a generated artifact regenerated from
the canonical migrations by scripts/generate-schema-sql.mjs. The
generator shells out to `supabase db dump --local` against a local
Supabase stack built from the canonical migrations by `supabase
start`.

The regeneration is run:

- After any new migration is added to supabase/migrations/, before
  committing that migration
- After baseline execution as Step 5 verification
- On demand when verifying current schema state during architectural
  review

Regeneration is fast (seconds to a couple minutes depending on
schema size) and deterministic. Running it repeatedly against
unchanged migrations produces byte-identical output.

**Verifying migration_history matches expectation.**

The verification pattern for confirming migration_history is in a
known state is:

    supabase migration list --linked

The output lists each migration and its status (applied, pending,
etc.). During normal operation, all migrations up to the most recent
one should show as applied. Any pending migrations indicate that
`supabase db push` hasn't been run since new migrations were added.
Any unexpected entries (unknown version strings, entries for
migrations that don't exist locally) indicate the hosted DB has
seen migration activity from outside the standard workflow —
investigation is warranted.

**Handling migration failures during ongoing operation.**

If a `supabase db push` fails mid-migration (a migration errors
during application), the migration_history reflects the last
successfully-applied migration. The failed migration is not marked
applied. Recovery involves diagnosing the failure (typically a SQL
error in the migration itself), correcting the migration, and
re-running `supabase db push`. The CLI treats the correction as a
retry of the same migration since the migration file name and
version string are unchanged.

If a migration is applied but produces incorrect schema state
(the migration SQL was wrong but ran without error), correction
requires a NEW migration that fixes the previous one. Editing an
already-applied migration and re-running push is architecturally
rejected — it violates the migrations-are-immutable-once-applied
principle that makes the migration_history reliable as an audit
record.

**The stop-point becomes historical context.**

Post-Phase-4-transition, the CLAUDE-rev6.md stop-point at lines 71-83
(as of this writing; the specific lines will change with future
CLAUDE-rev6.md edits) is updated to RESOLVED status. The text is preserved
in CLAUDE-rev6.md as historical context rather than being deleted. Future
operators reading CLAUDE-rev6.md can find both the historical hazard and
the resolution reference.

### CLAUDE-rev6.md stop-point evolution

Per Decision 22.7, the CLAUDE-rev6.md stop-point evolves through three
distinct states across the platform lifecycle:

**State 1 — In force (current state as of this section).**

The stop-point text (currently lines 71-83) explicitly instructs
Claude Code to STOP before running any command that could apply
local migrations to the hosted DB. This state is in effect from
the stop-point's original commit through the Phase 4 transition
criteria being satisfied. The current cross-reference paragraph
points to Decision 22 and this section for the locked baseline
procedure.

**State 2 — During baseline execution (transient).**

While the baseline procedure is actively running — from Step 0
backup through Step 5 schema.sql regeneration — the stop-point
remains in force. Claude Code should not interpret the operator's
in-progress baseline work as authorization to bypass the stop-point.
Only after all four Phase 4 transition criteria are satisfied does
the stop-point update.

**State 3 — RESOLVED (post-Phase-4-transition).**

After Condition 4 of the Phase 4 transition is satisfied, the
stop-point text is updated to RESOLVED status with the execution
date. Suggested resolved-state text:

    **Hosted database migration hazard — RESOLVED [YYYY-MM-DD].**
    The hosted DB's migration_history was baselined via Decision
    22's procedure on [YYYY-MM-DD]. Migrations 000-004 are marked
    applied. Subsequent `supabase db push` commands apply
    migrations 005+ normally. See Decision 22 and the Database
    Migration Tooling section for the historical hazard context
    and the procedure that resolved it.

The RESOLVED state is preserved in CLAUDE-rev6.md indefinitely. It serves
audit defensibility — future contributors can find both the historical
hazard and its resolution without needing to reconstruct either from
git history.

### Password handling

Per Decision 22.7, the `supabase migration repair` command accepts
a `--password` flag for the remote Postgres database's password.
Password handling during baseline (and during any Mode C intervention
that also needs the password) follows four rules:

**Rule 1 — Use interactive prompt only.**

The Supabase CLI's default behavior when `--password` is not passed
inline is to prompt for the password interactively. Baseline procedure
uses this default. Do NOT pass `--password` inline on the command
line.

**Rule 2 — Never inline the password in shell commands.**

Passwords in shell commands persist in shell history (e.g., ~/.bash_history)
and are visible in the process listing (`ps aux`) while the command runs.
Both are real exposure surfaces. Interactive prompt avoids both.

**Rule 3 — Never commit any artifact containing the password.**

The password does not appear in any file that is committed to the repo.
No .env file with the password, no config file with the password, no
script that hardcodes the password. If a password is needed by tooling
that reads config, the tooling reads from environment variables set at
runtime, and those environment variables are set from a source that is
not committed.

**Rule 4 — The password should not appear in shell history, git history,
or any committed file.**

This is the combined implication of Rules 1-3, restated as a positive
verification: the operator can grep every committed file and every
shell history file for the password, and find nothing.

Password-in-shell-history is a real exposure surface. Interactive
prompt is the safer default and is the architectural commitment.

### Cross-references

- Decision 22 (docs/session-handoffs/5e-bridge-phase3-decisions-log-rev6.md)
  is the architectural authority for this section. Decision 22's ten
  commitments (22.1 through 22.10) are documented here in
  reference-usable form.
- Decision 10 (Schema Source-of-Truth, in the same decisions log and
  represented as the Schema Source-of-Truth section in v2) is the
  authority for the migrations-canonical, schema.sql-generated
  convention that Database Migration Tooling operates within. Step 5
  of the baseline procedure and the ongoing schema.sql regeneration
  mechanic both depend on Decision 10's mechanism.
- CLAUDE-rev6.md (lines 71-83 as of this writing) contains the stop-point
  that governs Claude Code's behavior during the pre-baseline period.
  The stop-point cross-references this section and Decision 22.
- Data Migration Tooling section (in v2, elsewhere) covers the
  distinct concept of customer data import at tenant onboarding. It
  is architecturally independent from Database Migration Tooling.
  Both are load-bearing for the platform but operate on different
  concerns (customer data vs. schema state) at different points in
  the platform lifecycle (tenant onboarding vs. platform-wide schema
  evolution).

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
                                    -- Semantics vary by trigger_source:
                                    -- For 'contractual_date_manual':
                                    --   populated at project creation
                                    --   with the contractually-agreed
                                    --   warranty active date. Non-null
                                    --   at creation via Server Action
                                    --   enforcement (exception via
                                    --   migration path per Decision
                                    --   23.11).
                                    -- For 'wbs_integration',
                                    --   'delivery_report_tokenized',
                                    --   'delivery_report_api':
                                    --   populated when trigger_status
                                    --   becomes 'confirmed' (trigger
                                    --   event actually happens). Null
                                    --   until then.
                                    -- Per Decision 23.1.
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

For `contractual_date_manual` specifically, Decision 23.1 clarifies the
semantics of `pending`. At project creation, `trigger_date` is already
populated with the contractually-agreed warranty active date — the tenant
user enters it directly. But `trigger_status` remains `pending` because the
warranty hasn't started yet: the calendar hasn't reached the recorded date.
The warranty starts operationally per the contract on the recorded date,
independent of platform state changes to `trigger_status` (this reflects
Decision 23.8's warranty-starts-per-contract principle: platform state
does not block customer rights that the contract grants). The transition
of `trigger_status` for `contractual_date_manual` is governed by other
events (deferred to a future architectural decision per Decision 23's open
questions), NOT by the calendar reaching `trigger_date`.

### Lifecycle: when projects are created and what fires

This revises Phase 0 item 9, which was originally written EPC-only ("Projects
exist in WarrantyOS once their contractual milestone date is known.
Registration prep is triggered registration_lead_time_days before the
milestone, default 21 days, per-tenant configurable.") The revised wording:

Projects exist in WarrantyOS at the point determined by their trigger source.

- For `contractual_date_manual` and `wbs_integration` when the trigger date
  is known in advance (EPC shape), the project is created when the trigger
  date is known. `trigger_status` starts `pending`. `trigger_date` is
  populated at project creation for `contractual_date_manual` (per Decision
  23.1); for `wbs_integration` in the known-in-advance case, `trigger_date`
  is populated at project creation if the integration poller has captured
  the milestone date. Registration prep is triggered
  `registration_lead_time_days` before the trigger date — a future-firing
  clock event of type `registration_prep_pre_trigger` inserted into
  `clock_events` at project creation (per Decision 23.2). Default lead time
  is 21 days, per-tenant configurable.
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

### Migration and import handling

Per Decision 23.11, projects imported via Decision 8's data migration
tooling may enter the system with `trigger_source =
'contractual_date_manual'` and `trigger_date = NULL` because the
customer's source data was incomplete at migration time. The architecture
handles this case with a permissive-with-surfacing model rather than
blocking the import.

**Migration handling:**

- The project row is created despite missing trigger_date
- The `registration_prep_pre_trigger` clock event is NOT created at
  migration time (no known trigger_date to schedule against)
- The row surfaces in a "projects missing trigger_date" operational
  queue for warrantor follow-up
- When the warrantor later enters `trigger_date` via post-migration
  editing, the Server Action creates the clock event at that point,
  scheduled to fire at `trigger_date - registration_lead_time_days`

Application-layer enforcement: a project row created through the
standard Server Action (not migration) MUST have `trigger_date` non-null
when `trigger_source = 'contractual_date_manual'`. Migration is the
exception path — Server Action bypass allows migration to insert rows
with missing trigger_date. The database CHECK constraint on projects
does NOT enforce trigger_date non-null for `contractual_date_manual`,
precisely because migration needs to create these rows.

**Three downstream guards (per Decision 23.11):**

**Guard 1 — Deferred clock event creation.** The Server Action that
populates trigger_date on a migrated project must handle the
"trigger_date was null, now being populated" case by creating the
`registration_prep_pre_trigger` clock event at that point, not at
original project creation. This is the retrospective scheduling path.

**Guard 2 — Cat 3 #1 handoff for in-flight state.** Between migration
completion and trigger_date population (whether by warrantor entry or
by never happening), the project exists but has no registration and no
clock event. Claims may be filed during this in-flight state. Claim
eligibility handling for "project exists, trigger_date populated
(past), but registration not yet created" is a Cat 3 #1 concern.
Decision 23 introduces the state; Cat 3 #1 will specify the eligibility
rules.

**Guard 3 — Past-dated trigger_date handling.** If a warrantor populates
trigger_date with a past date (e.g., migrating projects whose
contractual dates already occurred), the calculation
`trigger_date - lead_time_days` produces a past `fires_at`. Decision 9's
clock_events dispatcher fires already-past events on the next poll —
the clock event is created, and the dispatcher fires it on the next
hourly poll. Between the trigger_date population and the next
dispatcher poll, the project exists without a registration; this is an
in-flight state that Guard 2 covers via the Cat 3 #1 handoff.

These three guards are architectural commitments of Decision 23, not
downstream operational scope. Server Action implementations for
project creation, project editing (trigger_date update), and the
`registration_prep_pre_trigger` dispatcher must honor these guards.

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
                                  -- Four-value closed set per Decision
                                  --   23.7: 'pre_activation',
                                  --   'assigned', 'active', 'rejected'.
                                  -- See "Registration status state
                                  --   machine" subsection for state
                                  --   semantics and transitions.
                                  -- CHECK constraint enforces allowed
                                  --   values.
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
      actual_start_date           date nullable
                                  -- populated by the warrantor when
                                  --   they confirm the warranty actually
                                  --   started operationally; null until
                                  --   confirmed; no default value.
                                  -- May be before, at, or after
                                  --   trigger_date (per Decision 23.4a
                                  --   no temporal constraint).
                                  -- Per Decision 23.4.
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

Section 7 is the structural anchor in registration lifecycle: the review
gate that transitions the registration to active, with WarrantyID issuance
now decoupled from its completion per Decision 27. v1 and Audit Topic 6
both name it but do not specify its contents — what review artifacts it
requires, what conditions it checks, who has authority to clear it. v2
documents Section 7 as the named activation event with the state
consequences we know:

- Before Section 7 passes: status is `assigned` (the normal state during
  prep work per Decision 23.7's four-state machine; `pre_activation` is a
  fallback edge-case state, not the general pre-gate state). Coverages may
  exist as draft. warranty_id may already be non-null per Decision 27's
  early-issuance mechanism (see "WarrantyID issuance" subsection below) —
  Section 7 completion is no longer the sole trigger for the identifier.
- Section 7 passes: the Server Action handling activation checks whether
  warranty_id is already set. If not, it generates the WarrantyID from the
  tenant's warranty_id row in tenant_id_sequences (default format
  WID-{year}-{seq:06d}, per-tenant configurable) — the same fallback path
  Decision 27's early-issuance event uses. The WarrantyID is written to
  warranty_id and the column is treated as immutable from that point.
  status transitions from `assigned` to `active` per Decision 23.7.
  activated_at is captured.
- After Section 7 passes: the registration is live. Coverages are active,
  and the registration's operational prep is complete. Whether a claim can
  be filed is governed by Decision 27's claim eligibility rule
  (warranty_id IS NOT NULL), which may already be true before Section 7
  passes.

The specific conditions Section 7 evaluates — required fields, required
reviewer approvals, required documents — are not specified at the
architectural layer in any locked source. This is a Phase 4 or downstream
operational question. The architecture sets the gate's role (complete
review and activate); the gate's contents are a separate decision.

### WarrantyID issuance, not assignment at creation

The WarrantyID is issued no later than effective_start_date (Decision
23.9), not assigned at registration creation, and not necessarily tied to
Section 7 completion. Decision 27's warranty_id_early_issuance clock event
(fires_at = trigger_date, kept in sync with actual_start_date confirmation
per 23.4) issues the identifier as soon as the customer's contractual
warranty right begins, independent of whether the assignee has finished
prep work or Section 7 has been reviewed. If Section 7 happens to pass
first, its Server Action issues the WarrantyID directly and the early-
issuance event becomes a no-op when it later fires.

This matters: a registration's id (uuid PK) exists from creation; its
WarrantyID does not, until effective_start_date (or Section 7 completion,
whichever comes first). The WarrantyID is the business-visible identifier
that appears in customer-facing communications and is the mechanism by
which Decision 27 resolves claim eligibility — a claim is filable exactly
when warranty_id IS NOT NULL.

Generation goes through tenant_id_sequences in the same transaction as
whichever event issues it (early-issuance firing, or Section 7 activation
if it passes first), so the counter and the issuing event cannot drift
apart. See the ID Generation section for the transactional gap-free
mechanism. Once issued, warranty_id is immutable; this is the
Defensibility Principle applied to identifiers.

### Assignee: who's responsible for completing activation

A registration is assigned to one party — a directory contact (e.g., a
subcontractor PM who handles the activation paperwork) or a tenant user
(e.g., a Reviewer self-handling). The assignment is captured using the FK +
Snapshot Pattern's dual-FK shape: two nullable FKs with a CHECK enforcing
exactly one non-null when assigned, plus snapshot columns for name, email,
phone, and the assigned_at timestamp.

Initial assignment happens as part of the atomic Server Action at
`registration_prep_pre_trigger` clock event firing (per Decision 23.3;
see the Clock-event interactions subsection below). The dispatcher
creates the registration row, captures the assignee, sets
`status = 'assigned'`, and sends notification atomically. The mechanism
by which the Server Action determines the specific assignee — pre-
configured default per tenant, assignment task surfaced to team admins,
operator selection — is Phase 4 / operational drafting.

The FK type drives downstream behavior. A contact assignee is reached
through the Stateless Tokenized Interaction Pattern (a tokenized email link
to a focused activation form). A tenant-user assignee is reached through an
in-app notification on their existing login. The two paths are different
because the parties are different kinds of thing — contacts have no
account, tenant users do.

Reassignment mechanics — the specifics of replacing an existing assignee,
audit trail requirements, cross-type reassignment (contact to tenant user
or reverse), notification behavior on reassignment, and permissible states
for reassignment (whether reassignment is allowed in `active` state or
only in `assigned` / `rejected` / `pre_activation` states) — are deferred
to a downstream Decision per Decision 23.12. The atomic assignment model
in Decision 23.3 handles initial assignment; reassignment is a real
operational concern that requires its own architectural work.

### Registration status state machine

Per Decision 23.7, the registration status column carries a four-state
machine that governs the registration's progress across its lifecycle.
This resolves Cat 3 backlog item #6 as a byproduct of Decision 23's
registration lifecycle work, and supersedes the earlier v1-anchor
placeholder that deferred the closed set of values to a separate
decision.

The four states are flat sequential — no hierarchy, no sub-states,
no parallel state dimensions. Each state has explicit entry and exit
transitions.

**States:**

- `pre_activation` — the registration row exists but no assignee has
  been captured. This state is reserved for edge cases where the
  clock event dispatcher's atomic operation partially failed
  (assignment failure, notification service down, contact FK invalid
  at dispatch time, etc.). The row exists in the database, but the
  atomic operation did not fully complete. Not entered during normal
  operation.

- `assigned` — an assignee has been captured on the registration.
  Assignee is working on prep (configuring coverages, gathering
  Section 7 documentation, etc.). This is the state most registrations
  spend their prep window in.

- `active` — Section 7 activation has passed, WarrantyID has been
  issued, `activated_at` is populated. Registration is live.
  Downstream claims, coverages billing time toward expiry, and
  customer-facing communications reference the WarrantyID.

- `rejected` — Section 7 activation attempt was rejected by the
  reviewer. The registration is not active; the assignee must revise
  and resubmit. This is a transient state (see transitions below).

**Transitions:**

- doesn't-exist -> `assigned` (normal path, per Decision 23.3's atomic
  Server Action; the row is created and assigned in the same operation)
- doesn't-exist -> `pre_activation` (edge case, when assignment fails
  during the clock event dispatcher; see the Pre-activation
  operational queue subsection below)
- `pre_activation` -> `assigned` (when assignment completes after
  edge-case entry, via manual intervention or retry mechanism)
- `assigned` -> `active` (when Section 7 activation gate passes)
- `assigned` -> `rejected` (when Section 7 activation attempt is
  rejected)
- `rejected` -> `assigned` (when the assignee revises and resubmits;
  Section 7 rejection loops back to prep state for revision)

No transition from `active` to any earlier state. Retirement or
cancellation of an active registration is a separate concern not
covered here.

No transition from `rejected` to `active` directly; rejection always
routes back through `assigned` for revision before another activation
attempt.

The CHECK constraint on `warranty_registrations.status` enforces the
four allowed values: `pre_activation`, `assigned`, `active`,
`rejected`.

### Pre-activation operational queue

Per Decision 23.7a, because `pre_activation` is an edge-case fallback
state where the atomic Server Action at clock event firing partially
failed, rows in this state require active operational attention. A
registration sitting in `pre_activation` means the clock event fired,
the row was created, but assignment did not complete. Something needs
to happen to advance the row to `assigned`.

Without an operational surface, `pre_activation` rows would silently
accumulate as an unnoticed operational failure mode. This is the
architectural concern Decision 23.7a addresses.

The platform surfaces an operational queue for warrantor team admins
showing registrations in `pre_activation` state. The queue is a
straightforward derived filter over `warranty_registrations`
(`WHERE status = 'pre_activation'`), scoped by tenant per the
Standard RLS Pattern. Team admins review the queue and take action to
resolve the failed assignment.

Resolution paths from `pre_activation`:

- **Manual assignment through an operational UI.** The team admin
  selects an assignee (contact or tenant user) and completes the
  assignment step that the atomic Server Action failed to complete.
  The registration transitions to `assigned` per the state machine.

- **Diagnose and retry the failed dispatcher path.** If the failure
  was transient (notification service down, transient FK constraint
  timing), the team admin can trigger a retry of the assignment step.

The queue's specific UI/UX and the mechanism for resolving
`pre_activation` rows (manual assignment vs retry, retry mechanics,
audit trail for resolution actions) are Phase 4 / operational
drafting. Decision 23.7a locks the operational queue as an
architectural commitment; the operational specifics are downstream.

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
depending on the project's trigger_source. Decision 23 locks the specific
mechanics for each source category. Decision 27 adds a parallel event,
warranty_id_early_issuance, scheduled alongside registration_prep_pre_trigger
in the same atomic Server Action (23.3) — see the WarrantyID issuance
subsection above for its firing and sync mechanics.

**Contractual_date_manual and wbs_integration when trigger_date is known
at creation (per Decision 23.2):**

At project creation, the platform calculates
`trigger_date - registration_lead_time_days` (per-tenant configurable
setting, default 21) and inserts a `clock_events` row of type
`registration_prep_pre_trigger` with that value as `fires_at`. The
entity_type = 'project', entity_id = the project's id.

The clock event is a scheduled reminder — Decision 9's Clock Event
Infrastructure holds the row until the hourly pg_cron poll detects
`fires_at` is in the past AND `status = 'pending'`. On that poll, the
dispatcher runs.

When the dispatcher runs the `registration_prep_pre_trigger` event, its
Server Action performs an atomic write (per Decision 23.3):

1. Creates the `warranty_registrations` row associated with the project
   (project_id populated, tenant_id denormalized per Standard RLS Pattern)
2. Assigns the registration to an assignee. Assignment populates one of
   `assigned_to_contact_id` or `assigned_to_user_id` per the dual-FK model.
   Captures assignee snapshots per the FK + Snapshot Pattern
3. Sets `warranty_registrations.status = 'assigned'`
4. Sends notification to the assignee

"Atomic" here means the Server Action commits row+state in a single
database write, NOT transactional all-or-nothing across all four effects.
The distinction matters: if the row creation succeeds but assignment
fails (contact FK invalid, assignee soft-deleted between dispatcher
scheduling and firing, notification service down), the row exists with
`status = 'pre_activation'` per the state machine's edge-case
disposition. The atomic commit succeeds to whichever state is achievable
given the partial-failure conditions.

The normal path (all four effects succeed) produces a row directly in
`assigned` state. The `pre_activation` state exists as a fallback for
the partial-failure edge case; see the Pre-activation operational queue
subsection above.

Between project creation and the clock event firing, the registration
row does NOT exist. The project exists (with trigger_date recorded), but
no registration exists yet.

**Delivery_report_tokenized and delivery_report_api (supply-only shape):**

The mechanism is different and preserved from Phase 0 Item 17. The
warranty_registrations row is created synchronously when the trigger
event occurs (buyer report, carrier API confirmation) via a Server
Action, not via a clock event. No `clock_events` row is created for the
registration creation itself; the Server Action handles it directly on
`trigger_status`'s transition from `pending` to `confirmed`.

Decision 23's clock-event-driven creation mechanism (above) applies only
to trigger sources where trigger_date is known at project creation. For
supply-only sources, trigger_date isn't known until the sale/delivery is
reported.

**Wbs_integration when trigger_date is NOT known at creation:**

If the WBS integration poller has not yet captured the milestone date at
project creation, the mechanism follows the supply-only pattern above:
the Server Action creates the registration synchronously when the poller
detects the milestone and transitions `trigger_status` to `confirmed`.

**Warranty expiry warnings:**

Warranty expiry warnings are a separate clock-event interaction,
operating at the coverage level (not the registration level). A
`warranty_expiry_warning` event fires before each coverage's derived
`end_date`, surfacing the upcoming expiry to warrantors and customers.
See the Warranty Type Coverages section for the mechanism.

Registration status remains `active` regardless of coverage expiry;
expiration is a coverage-level concern, not a registration status
transition. This is consistent with Decision 23.7's closed four-value
state machine (`pre_activation`, `assigned`, `active`, `rejected`)
which does not include an `expired` state.

### What is NOT on the registration

A short list of deliberate omissions, parallel to the Project section:

- No coverage start_date or end_date. Those live on the warranty_coverages
  child table, one per warranty type, with end_date derived from
  start_date + term_years. See the Warranty Type Coverages section.
- No customer FK. The customer is on the project (FK + Snapshot single-FK
  shape); the registration inherits its customer through project_id.
  Duplicating the customer on registration would create a sync surface
  where there's no need for one.
- No business-status enum beyond the four states in the Registration
  status state machine subsection above (`pre_activation`, `assigned`,
  `active`, `rejected` per Decision 23.7). Anything more granular about
  activation progress (which Section 7 fields are complete, which
  reviewer approvals are in) is downstream operational state, not
  registration-level state.

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
                                  -- immutable snapshot of the parent
                                  --   project's trigger_date at coverage
                                  --   creation. See "Coverage start_date
                                  --   derivation" subsection for
                                  --   snapshot semantics and COALESCE
                                  --   derivation of effective start.
                                  -- Per Decision 23.5.
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

### Coverage start_date derivation

Per Decision 23.5, coverage `start_date` is populated at coverage
creation with the current value of `projects.trigger_date`. This is a
snapshot at coverage creation — the moment-in-time capture of what the
contractually-agreed warranty active date is when the coverage row is
inserted.

Later, if `warranty_registrations.actual_start_date` is confirmed by
the warrantor and differs from trigger_date, coverage rows are NOT
updated. Coverage `start_date` remains as the trigger_date snapshot
captured at coverage creation. Coverage rows are immutable snapshots.

The effective start date for warranty calculations is derived at query
time via COALESCE:

    effective_start_date = COALESCE(
        warranty_registrations.actual_start_date,
        warranty_coverages.start_date
    )

Where `actual_start_date` is on the parent warranty_registrations row.
When actual_start_date is null (not yet confirmed by the warrantor),
the coverage's snapshotted start_date is used. When actual_start_date
is confirmed, it overrides.

This preserves audit-defensibility: coverage rows are historical
records of what was known at creation time. Effective start is
derived, not stored on the coverage row. Historical accuracy is
preserved even when actual_start_date is confirmed after coverages
were created and after claims were filed.

**Schema-level enforcement via database view (per Decisions 23.5a and 24):**

Decision 23.5a originally flagged schema-level enforcement (via generated
column or view) as a Phase 4 implementation option. Decision 24 exercises
the view option, superseding the application-layer default. The
`effective_start_date` derivation is enforced by the
`warranty_coverages_effective` database view, which joins
`warranty_coverages` with its parent `warranty_registrations` and computes
the COALESCE at the schema level.

Application code MUST query `warranty_coverages_effective` for
`effective_start_date` in ALL of the following contexts:

- Claim eligibility calculations
- Coverage window calculations
- Warranty period displays to warrantors and customers
- Expiry warning firing calculations

Application code MUST NEVER read `warranty_coverages.start_date`
directly for effective start date purposes. Reading the snapshot
directly bypasses the derivation and produces incorrect effective
start dates whenever actual_start_date has been populated — the silent
data corruption failure mode that this enforcement mechanism exists to
prevent.

The view uses `WITH (security_invoker = true)` for RLS pass-through per
Decision 24.5 and the Standard RLS Pattern's View security convention.
Tenant isolation is preserved end-to-end. See the "end_date is derived,
not stored" subsection below for the view definition, and Decision 24's
Resolution 24.2 through 24.5 for full commitments.

The generated-column alternative mentioned in the original 23.5a
framing is architecturally unavailable: Postgres generated columns
cannot reference columns on other tables, and the COALESCE requires
reading `actual_start_date` from `warranty_registrations`. Only the
view mechanism satisfies both the cross-table COALESCE requirement
and the schema-level enforcement objective.

**Application to Decision 23.8's warranty-starts-per-contract principle:**

The COALESCE derivation with `start_date` (the trigger_date snapshot)
as fallback is the mechanism by which Decision 23.8's
warranty-starts-per-contract principle is enforced at the coverage
level. When `actual_start_date` is null (warrantor has not confirmed
operational activation yet), the effective start date falls back to
`start_date` — the contractually-agreed warranty active date. This
ensures customer warranty rights are never blocked by internal platform
state: coverage calculations proceed based on the contractual date even
when operational confirmation is pending.

Any future Decision that touches coverage window calculations or claim
eligibility MUST reference Decision 23.8 explicitly to preserve this
principle. This enforcement invariant is architecturally comparable to
Decision 19's atomic Accept-and-Signature invariant — it applies
uniformly across all code paths that touch effective start date
semantics, with the enforcement mechanism sitting at the schema layer
(the view) rather than requiring distributed application-layer
discipline.

### end_date is derived, not stored

end_date is not an independent column. It is the value of
start_date + term_years, computed where it is needed. Two reasons.
Storing it as an independent column would create a sync surface: an
update to either start_date or term_years would have to remember to
update end_date too, or the stored value drifts. Audit defensibility
also prefers a single source of truth — start_date and term_years are
what the warranty agreement records; end_date is a calculation.

Per Decision 24, the derivation mechanism is a database view named
`warranty_coverages_effective` that joins `warranty_coverages` with its
parent `warranty_registrations`. The view exposes both
`effective_start_date` (per Decision 23.5a) and `effective_end_date` as
computed columns, alongside the base coverage columns needed for
downstream reads.

The `effective_end_date` computation extends 23.5a's COALESCE invariant
to end_date derivation:

    effective_end_date = (
        COALESCE(
            warranty_registrations.actual_start_date,
            warranty_coverages.start_date
        ) + (warranty_coverages.term_years || ' years')::interval
    )::date

This computation lives in the view definition, not at the application
layer. All read paths that need `effective_end_date` MUST query
`warranty_coverages_effective`, not compute `start_date + term_years`
against `warranty_coverages` directly. Bypassing the view reproduces
the silent data corruption failure mode that 23.5a exists to prevent —
if `actual_start_date` is populated but the read site uses
`start_date + term_years` alone, the effective_end_date will be wrong
by the offset between `actual_start_date` and `start_date`.

The view uses `WITH (security_invoker = true)` for RLS pass-through
per Decision 24.5 and the Standard RLS Pattern's view security
convention. Tenant isolation is preserved end-to-end.

Decision 24 supersedes the earlier "Phase 3 implementation choice"
framing. The generated-column option is architecturally unavailable —
Postgres generated columns cannot reference columns on other tables,
and the COALESCE requires reading `actual_start_date` from
`warranty_registrations`. Application-layer computation is
architecturally prohibited (per 24.3) because it reintroduces the
silent-data-corruption failure mode. The view is the sole mechanism.

Contexts where the view MUST be used (per 24.3):

- Claim eligibility calculations
- Coverage window calculations
- Warranty period displays to warrantors and customers
- Expiry warning firing calculations
- Reports and dashboards showing coverage timing
- Any operational tooling that filters, sorts, or displays coverage
  end dates

The architectural commitment (derived, not stored as an independent
column on `warranty_coverages`) holds — the base table remains
unchanged. The view is a schema-level derivation, not a stored value
on the base table.

### Coverages and the registration's status

Per Decision 23.6, coverages are created during the prep window by the
assignee. Under Decision 23.3's registration lifecycle timing, the
warranty_registrations row is created when the `registration_prep_pre_trigger`
clock event fires (approximately 21 days before trigger_date for
`contractual_date_manual` projects). Coverages come into existence during
the prep window that follows.

The assignee, during their prep work, configures coverages by drawing
down warranty types from the tenant's warranty_types list, setting
term_years for each, and populating coverage rows. Coverage creation
is part of the prep work that must complete before Section 7 activation.

At coverage creation, each coverage row's `start_date` is populated
with the current `projects.trigger_date` value (per Decision 23.5's
snapshot semantics documented in the Coverage start_date derivation
subsection above). Each coverage row's `end_date` is derived via the
`warranty_coverages_effective` database view per Decision 24 (see the
"end_date is derived, not stored" subsection below for the full
mechanism).

A coverage does not "count time" until the registration is active.
While the registration is in `assigned` state, coverage rows exist but
no warranty term is running. Once Section 7 passes and the registration
transitions to `active`, coverages are live and count toward expiry.

The expiry warning is a clock event, not a column update. A
`warranty_expiry_warning` event in `clock_events` fires before each
coverage's derived end_date, surfacing the upcoming expiry to warrantors
and customers.

Coverage expiration is a coverage-level concern, not a registration
status transition. When all coverages on a registration have passed
their end_date, the registration status remains `active` — Decision
23.7's four-value state machine (`pre_activation`, `assigned`, `active`,
`rejected`) does not include an `expired` state for registrations.
Expiration handling at the coverage level (whether it's a derived
condition from end_date, or gets a coverage-level status column, or
both) is deferred to future architectural work per Decision 23's open
questions.

### What is NOT on the coverage

A parallel deliberate-omissions list:

- No end_date column. Covered above; derived, not stored.
- No business-visible identifier. Coverages are referenced internally
  by uuid; the customer sees warranties (WarrantyID) and claims
  (ClaimID), not individual coverage rows.
- No coverage-level status enum. A coverage's operational state is
  derived from its registration's status and its own derived end_date
  — the coverage is counting time when registration is `active` and
  now < end_date, and past-expiry when now > end_date. Whether
  coverage-level expiration warrants an explicit status column, remains
  purely derived, or something else, is deferred to future architectural
  work per Decision 23's open questions.

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
      is_emergency          boolean NOT NULL DEFAULT false
                            -- per Decision 27.5
      emergency_stabilized_at  timestamptz nullable
                            -- customer-reported; required when
                            --   is_emergency = true
                            -- self-reported at intake, not
                            --   independently verified by the platform
                            -- per Decision 27.5
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

Claim eligibility is resolved by Decision 27: a claim is filable exactly
when warranty_id IS NOT NULL on the parent registration. Decision 27
decouples WarrantyID issuance from full Section 7 completion (see the
WarrantyID issuance subsection in the Warranty Registration section) so
that a customer's contractual right to file, established by
effective_start_date (23.9), is never blocked by unfinished warrantor-side
prep. Emergency claims (v1's Accepted/Denied Claim Lifecycle SOPs carve
out emergency stabilization with a 24-hour formal-filing window) are
subject to the same warranty_id IS NOT NULL rule — the emergency carve-out
governs filing timing, not eligibility. See is_emergency and
emergency_stabilized_at in the shell schema above, and Decision 27.5-27.7.

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
- Claim eligibility rules — resolved by Decision 27, not Tier 3 deferred.
  See "Parent: warranty_registrations" above for the filing rule
  (warranty_id IS NOT NULL) and the emergency carve-out's role as a
  filing-timing rule layered on top of it.
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
      submitter_contact_id          uuid nullable FK -> contacts
                                    -- per Decision 20: FK + Snapshot when
                                    --   submitter is a known contact;
                                    --   null when submitter is a one-off
                                    --   third party not in the directory
      submitter_name                text NOT NULL
                                    -- snapshot captured at submission;
                                    --   populated regardless of whether
                                    --   submitter_contact_id is set
      submitter_email               text NOT NULL
                                    -- snapshot captured at submission;
                                    --   populated regardless of whether
                                    --   submitter_contact_id is set
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

When a tenant has configured an Acknowledgment Gate template for
gate_purpose = 'claim_submission' (per Decision 12's Acknowledgment
Gate Pattern, documented as its own Tier 1 section), the customer
encounters that gate as the first screen of the tokenized link before
reaching the intake form. The canonical example is a Warranty Claim
Submission Requirements gate where the tenant lists evidence
expectations, submission standards, or operational language the
customer must acknowledge before filing. The customer reads the gate
content, checks the acknowledgment box, and (if the gate template
requires) types their name; only then does the Server Action render
the intake form. The gate is optional per tenant — tenants without a
configured gate for gate_purpose = 'claim_submission' see customers
proceed directly to the intake form. The Acknowledgment Gate Pattern
section documents the mechanism, schema, optional-per-tenant framing,
and the polymorphic protected-entity reference (authorized_entity_type
= 'claim', authorized_entity_id = the resulting claim row's id).

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
  contacts with name/email/phone snapshots captured at intake. Per Decision
  20.1, the contact_type for the FK is `om_provider_contact` (the
  individual at the O&M Provider organization who provided the contact
  info), with parent_contact_id traversing to the parent `om_provider`
  organization contact (per Decision 20.10's matched-pair traversal
  mechanism). The dedicated om_provider value is the cleaner answer this
  flag identified.
- Ship-to address structure. The hard columns above use four scalars
  (street/city/state/zip) following the project's site_address pattern for
  consistency. Whether this is the right level of structure or whether the
  project's address pattern itself needs revision (geocoding, international
  formats) is a future decision, not raised by any locked source.
- Claimant identity (the submitter). Per Decision 20, the submitter
  capture uses FK + Snapshot when the submitter is a known contact, with
  free-text fallback for one-off third parties. The hard columns capture
  submitter_contact_id (nullable FK to contacts), plus submitter_name and
  submitter_email (NOT NULL, snapshot at submission). When
  submitter_contact_id is populated, downstream workflows can traverse to
  the contact's contact_type to derive whether the submission was by the
  customer directly, by a customer_contact, by an O&M Provider (subject
  to Decision 20.6's INFORMATIONAL vs BINDING-COMMITMENT carving), or by
  another party type. When submitter_contact_id is null, the snapshot is
  the only record; agency role cannot be derived because there is no
  contact reference. This shape resolves the chat-4-identified
  traceability gap in Decision 20.4 (downstream workflows that need to
  know "was this claim filed by an authorized agent or by the customer
  directly?" can answer reliably when the submitter is a known contact).
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

**Status: Designed.** ALA markup default and storage locked by
Decision 7. ala_templates and ala_documents schemas follow Audit Topic
10's shape with the operational behavior the SOPs specify. Signature
capture mechanism locked by Decision 19 — ten architectural commitments
covering claimant decision capture, signature mechanism configurability,
accessibility-compliant signing path, decline handling with recant
window, and operational state machine.

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
                                  -- of "ALA in force" (refined by
                                  -- Decision 19's three-state model)
      claimant_decision           text nullable
                                  -- 'accepted' | 'declined'
                                  -- CHECK constraint enforces values
                                  -- application invariant: when
                                  --   'accepted', signed_at must be
                                  --   non-null (atomic per Decision 19.1)
      decided_at                  timestamptz nullable
                                  -- moment of Accept/Decline click;
                                  -- non-null when claimant_decision is
                                  -- non-null
      decline_reason              text nullable
                                  -- optional free-text context from
                                  -- the claimant; only populated when
                                  -- claimant_decision = 'declined'
      signature_method            text NOT NULL
                                    DEFAULT 'in_platform_widget'
                                  -- 'in_platform_widget' |
                                  --   'esignature_service'
                                  -- CHECK constraint enforces values;
                                  -- captured at row creation from the
                                  -- tenant's ala_signature_method
                                  -- setting and frozen for the
                                  -- document's lifetime
      signature_image_url         text nullable
                                  -- URL reference to Supabase Storage
                                  -- (tenant-scoped path); only
                                  -- populated when signature_method =
                                  -- 'in_platform_widget' AND canvas
                                  -- sub-path used AND signed_at
                                  -- non-null
      esignature_envelope_id      text nullable
                                  -- reference to e-signature service
                                  -- envelope/document ID; only
                                  -- populated when signature_method =
                                  -- 'esignature_service' AND signed_at
                                  -- non-null
      claimant_token              text nullable
                                  -- single-use token for the
                                  -- tokenized signing link; per
                                  -- Stateless Tokenized Interaction
                                  -- Pattern's "shape to copy" rule,
                                  -- stored on the document row rather
                                  -- than in the invitations table
      claimant_token_expires_at   timestamptz nullable
      created_at                  timestamptz NOT NULL DEFAULT now()
      updated_at                  timestamptz NOT NULL DEFAULT now()
      -- CHECK / app-layer invariant: tenant_id matches the referenced
      -- claim's tenant_id

The table follows the Standard RLS Pattern. tenant_id is denormalized
directly per the convention.

UNIQUE on claim_id enforces that a claim has at most one ALA document.
A claim either is Indistinct and has one ALA, or is not Indistinct and
has none.

content_snapshot is captured at document generation, not referenced
live through template_id. This is the same defensibility logic as the
FK + Snapshot Pattern: the document the claimant signed must read
identically in twenty years even if the template was updated, retired,
or restructured. The template_id FK preserves the relationship for
reporting; the content_snapshot preserves the historical truth.

markup_percent_snapshot is also captured at document generation, frozen.
The current tenant ala_markup_percent reflects current configuration;
the percent that applied to this specific document at the moment it
was generated is what the claimant agreed to and what the audit trail
must preserve. Same defensibility logic.

The signer fields (signer_name, signer_email, signed_at) are nullable
because a document may exist as unsigned (sent to the claimant,
awaiting response) before becoming signed. signed_at being non-null
remains the architectural marker that the agreement is in force —
this commitment carries over from prior v2 and is refined by Decision
19's three-state model: the in-force marker corresponds to the signed
state (signed_at IS NOT NULL AND claimant_decision = 'accepted'); the
unsigned state has both signed_at and claimant_decision null; the
declined state has claimant_decision = 'declined' AND signed_at IS
NULL. The signer columns capture WHO signed and WHEN; the decision
columns capture WHAT they decided. The two sets of columns are
complementary, not redundant.

Whether to capture the signer as a free-text snapshot (name/email
pair, as above) or as an FK + Snapshot reference to a contacts row is
the same question Claim Intake settled for the submitter, with the
same answer for the same reasons: a signer may be a customer contact
or a one-off third party, the FK is too heavy for the operational
shape, free-text snapshots are sufficient. If reporting needs surface
that argue for FK + Snapshot, this is revisitable.

The decision capture columns (claimant_decision, decided_at,
decline_reason) capture the claimant's Accept or Decline choice and
its context per Decision 19.2. decided_at captures the click moment;
signed_at captures the completed signature moment; in the happy path
the two timestamps are near-identical because the atomic Accept-and-
Signature commitment (Decision 19.1) requires both within a single
Server Action write. The columns remain semantically distinct so
downstream code can read whichever it needs.

The signature mechanism columns (signature_method, signature_image_url,
esignature_envelope_id) capture which signing mechanism produced the
signature and any mechanism-specific artifact per Decision 19.3, 19.4,
and 19.5. signature_method is captured at row creation from the
tenant's ala_signature_method setting and frozen for the document's
lifetime, so historical documents retain their mechanism even if the
tenant changes the setting later. signature_image_url is populated
only when the in_platform_widget canvas sub-path was used;
esignature_envelope_id is populated only when signature_method =
'esignature_service'.

The token columns (claimant_token, claimant_token_expires_at) store
the tokenized signing link per Decision 19.8 and the Stateless
Tokenized Interaction Pattern's "shape to copy, not shared store"
rule. The tokens live on the ala_documents row rather than in a
shared invitations table, parallel to the token storage on
work_authorization_documents (Decision 11). Per-row token
regeneration handles expiry recovery — the warrantor can update both
token columns on the existing row when a token expires; the
document's state column combination (claimant_decision, signed_at) is
preserved across regeneration.

Application invariant: when claimant_decision = 'accepted', signed_at
MUST be non-null. The atomic accept-and-signature commitment
(Decision 19.1) means the Server Action commits Accept and Signature
together as a single write; there is no valid row state where the
claimant has accepted but not signed. The invariant is enforced at
the application layer through the Server Actions that write these
columns.

signature_image_url storage convention: when the in_platform_widget
canvas sub-path is used, the Server Action writes the canvas image
data to Supabase Storage under a tenant-scoped path (typically
something like tenant-{tenant_id}/ala-signatures/{document_id}.png;
the exact path convention is a Phase 3 implementation detail). The
resulting URL is stored in signature_image_url. The URL-reference
convention aligns with platform patterns for other binary data
(claim photos, service report photos, work authorization documents)
and keeps backup, replication, and metadata-query performance
efficient — bytea storage at this scale would inflate database
backups, replication bandwidth, and TOAST overhead unnecessarily.

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

The routing-for-signature uses the Stateless Tokenized Interaction
Pattern per Decision 19 (ALA is the pattern's sixth canonical use).
The claimant receives a tokenized email link to the ALA document,
opens it, completes the Accept/Decline decision and (on Accept) the
signature step within the same tokenized session. See the Signature
capture mechanism subsection below for the locked architecture.

### Signature capture mechanism

The signature capture mechanism is locked per Decision 19 (Phase 3
decisions log) with ten architectural commitments. The previously
open architectural question — tokenized form acceptance vs wet
signature vs e-signature service — is resolved through a per-tenant
configurable architecture with a sensible default and architectural
support for future expansion. The existing schema columns
(signer_name, signer_email, signed_at) retain their original
semantics; eight new columns and three tenants.settings keys layer
the locked mechanism on top.

The signing flow is two-step with atomic Accept-and-Signature. Step
one captures the claimant's Accept or Decline decision. Step two, on
Accept only, captures the electronic signature. The two steps are
atomic: a claimant who clicks Accept MUST complete the signature in
the same flow before the decision is recorded. The Server Action
commits Accept and Signature together as a single atomic write or
commits neither. A claimant who abandons during signature (browser
closes, network fails, distraction) leaves no captured state.
Decline is the only single-step terminal action; no signature follows.

Decision capture lives in three columns: claimant_decision (the
'accepted' or 'declined' value), decided_at (timestamp of the
Accept/Decline click), and decline_reason (optional free-text context,
populated only when claimant_decision = 'declined'). decided_at
captures the click moment; signed_at captures the completed signature
moment. In the happy path the two timestamps are near-identical
because the steps are atomic; the columns remain semantically distinct
so downstream code can read whichever it needs.

The operational state machine is three states derived from the
combination of claimant_decision and signed_at. unsigned: signed_at
IS NULL AND claimant_decision IS NULL — document sent, awaiting
response. signed: claimant_decision = 'accepted' AND signed_at IS
NOT NULL — ALA in force, blocking-gate cleared, claim can advance
from Indistinct. declined: claimant_decision = 'declined' AND
signed_at IS NULL — claimant explicitly declined; pending the
decline-recant window (below), becomes permanently terminal after
window expiry. There is no accepted_unsigned intermediate state;
the atomic-accept-and-signature commitment eliminates that
possibility.

Signature mechanism is per-tenant configurable. Configuration lives
at tenants.settings.ala_signature_method with two valid values:
'in_platform_widget' (the v1 default) and 'esignature_service'.
Configuration storage shape parallels Decision 7's
tenants.settings.ala_markup_percent — single per-tenant scalar
value with application-layer validation. The Server Action handling
document creation reads the tenant's current setting and applies it
as the document's signature_method column at row creation; the
column preserves the mechanism for the lifetime of each document
even if the tenant changes the setting later.

The in_platform_widget mechanism has TWO sub-paths within the same
signature_method enum value, both producing valid signed ALAs. The
canvas-based sub-path presents a draw-your-signature interface,
captures the result as image data, and stores it in Supabase Storage
under a tenant-scoped path with the URL reference recorded in
signature_image_url. The typed-name-plus-checkbox fallback sub-path
mirrors Customer Work Authorization's signature mechanism (Decision
11): the claimant types their name and checks an "I sign" or
equivalent acknowledgment box. The acknowledgment checkbox replaces
the canvas image as the binding artifact; signature_image_url stays
null on this sub-path. Both sub-paths populate signer_name,
signer_email, and signed_at identically. The Server Action layer is
responsible for ensuring the in_platform_widget UI surface offers
both sub-paths; the dual-path commitment is not optional —
accessibility compliance (ADA and equivalent regulations) requires
the typed-name fallback within the default path for claimants using
assistive technology, motor impairments, or other accessibility
needs the canvas sub-path cannot accommodate.

Signature image storage uses a URL reference to Supabase Storage,
not bytea on the database row. The convention aligns with platform
patterns for other binary data (claim photos, service report photos,
work authorization documents) and decouples large-blob storage from
document metadata queries — TOAST overhead, backup inflation, and
replication bandwidth all stay efficient. The Server Action writes
canvas data to Supabase Storage and records the resulting URL on
the document.

The esignature_service mechanism is architecturally supported at v1
but no actual service integration is built. The signature_method
enum includes 'esignature_service' as a valid value, and the
esignature_envelope_id column captures the service-specific
reference when populated. A tenant who configures
tenants.settings.ala_signature_method = 'esignature_service' will
encounter a "not yet supported" error from the Server Action layer
when attempting to send an ALA for signing. Which specific service(s)
the platform integrates with (DocuSign, HelloSign, Adobe Sign, etc.)
is deferred to a future Decision when operational pressure surfaces.
The architectural commitment is the configurability; the integration
work is downstream. signer_name and signer_email semantics by
signature_method: in_platform_widget captures signer_name from the
canvas widget's name input (canvas sub-path) or the typed-name input
(fallback sub-path), with signer_email from the tokenized session;
esignature_service captures both fields from the service's response
callback.

Decline triggers a warning to the claimant AFTER commit, not as a
pre-commit confirmation. The Server Action records the decision
immediately (claimant_decision = 'declined', decided_at = now()) and
the outcome screen displays a warning explaining the consequence: the
warrantor cannot proceed with the claim, and the claim is subject to
denial. Warning text is per-tenant configurable at
tenants.settings.ala_decline_warning_text, with platform default
seeded at provisioning and application-layer validation enforcing
NOT NULL plus 50-500 character bounds. Storage shape parallels
Decision 7's ala_markup_percent. The Tenant-Editable Defaults Pattern
is deliberately NOT used for the warning text — that pattern fits
enum-like data with multiple values, and a single per-tenant
configurable string fits the tenants.settings convention.

Decline is NOT immediately permanently terminal. A configurable
window opens from decided_at during which the claimant can recant
their decline (typically by emailing the warrantor) and the warrantor
can re-issue the same ALA for another acceptance attempt. Window
duration lives at tenants.settings.ala_decline_recant_window_days
with platform default of 3 days and application-layer validation
bounds of 1-30 days. Storage shape parallels Decision 7's
ala_markup_percent. During the window, a warrantor-invoked re-issue
Server Action verifies the document is in declined state and the
current time is within the window, writes an audit trail entry
capturing the decline event (who declined, when, decline_reason),
resets claimant_decision and decided_at and decline_reason to NULL,
regenerates claimant_token and claimant_token_expires_at, and
re-sends the tokenized link. The document state returns to unsigned
and the claimant has full Accept/Decline path available again. After
window expiry the re-issue Server Action is blocked; if the claimant
later recants outside the window they must resubmit the claim
entirely. A new clock_event type ala_decline_window_expired fires
at decided_at + ala_decline_recant_window_days days when
claimant_decision = 'declined'; the event marks the decline as
permanently terminal and unblocks downstream claim denial workflow.
This is the seventh clock_event type after Decision 9's six. ALA's
recant-window mechanic handles the most common case (hasty decline
reconsidered within days) without committing to a fuller
revise-and-resend mechanic parallel to Customer Work Authorization
(Decision 11); the broader revise-and-resend question is flagged as
deferred for future Decision if operational pressure surfaces.

ALA is the sixth canonical use of the Stateless Tokenized Interaction
Pattern, after claim intake, registration assignee submission,
supply-only delivery reporting, service report customer review, and
Customer Work Authorization. The claimant is a non-authenticated
party receiving a tokenized email link to the ALA document; they
open it, complete the Accept/Decline decision and (on Accept) the
signature step within the same tokenized session. Per the pattern's
"shape to copy, not shared store" rule, two columns on ala_documents
store the token: claimant_token (the token value) and
claimant_token_expires_at (the expiry timestamp). Per-row token
regeneration is the mechanic for expiry recovery — the warrantor can
update both columns on the existing ala_documents row when the token
expires; document state is preserved across regeneration. Token
regeneration is distinct from the decline-recant re-issue: token
expiry on an unsigned document is a transient-availability concern;
decline-recant re-issue is the state-reset path post-decline. Both
mechanics co-exist.

Counter-signature is deliberately absent. The ALA is authored by the
warrantor and the operative event is claimant acceptance; the
warrantor's role is implicit in the Server Action that creates the
document. This is architecturally correct for an Owner's Consent and
Assumption of Liability Agreement — the document captures one-sided
consent from the claimant; no counter-signing column is needed and
none is added.

O&M Provider acceptance of an ALA is BLOCKED at v1 per Decision 20.6
and 20.7. The signing party must be the customer (claimant) directly.
Even when the customer has engaged an O&M Provider as their authorized
agent for warranty matters, the binding-commitment nature of an ALA
(the customer accepting financial responsibility for investigation if
the defect falls outside warranty scope) requires the Customer-O&M
Authorization document as a precondition. That document is deferred
to Cat 3 #9 (Customer-O&M Authorization document architecture). Per
Decision 28, the ALA Server Action checks for a signed
om_authorization_documents row (event_type = 'ala') before allowing an
actor with contact_type IN ('om_provider', 'om_provider_contact') to
accept. If no signed row exists, the action is blocked with an
"authorization required" error and a link to initiate signing.

### Response window, overdue flag, and re-issue

Per Decision 25, an unsigned ALA does not stay open indefinitely. A
tenant-configurable business-day window (tenants.settings.
ala_response_overdue_business_days, default 7, bounds 3-30) opens at
document creation. Business-day math skips weekends and any date in the
tenant's tenant_holidays table — a new per-tenant list, platform-seeded
with U.S. federal holidays at provisioning, tenant-owned thereafter, same
provisioning philosophy as the Tenant-Editable Defaults Pattern.

If the window expires with claimant_decision still null, the
ala_response_overdue clock event fires: overdue_flagged_at is set on the
row, and the claimant receives an email explaining the window closed with
no decision recorded. claimant_decision and signed_at are untouched — no
decision is made on the claimant's behalf. The Indistinct blocking gate
remains closed per Decision 19.7; overdue_flagged_at is a marker layered
on the existing unsigned state, not a fourth state in the state machine.

The warrantor is notified when the claimant explicitly Accepts or
Declines (new commitment, Decision 25.6) — synchronous Server Action
side effect at the moment claimant_decision commits. This makes the
absence of that notification a meaningful signal: no notification means
no response, without requiring a separate overdue push to the warrantor.

Re-issue is warrantor-invoked, mirroring the decline-recant re-issue
mechanic (Decision 19.9): writes an audit entry, clears
overdue_flagged_at, regenerates claimant_token and
claimant_token_expires_at, resends the link, and schedules a fresh
ala_response_overdue event. There is no forced auto-terminal state —
overdue-and-flagged persists until the warrantor re-issues or manually
escalates through the existing Escalated/Denied claim pathway.

### Revise-and-resend

Per Decision 26, resolving the revise-and-resend question this section
previously deferred: a new child table, ala_document_revisions, captures
content changes to an ALA without violating the UNIQUE(claim_id)
constraint on ala_documents, which stays exactly as locked. A revise
action updates content_snapshot and markup_percent_snapshot on the
existing row, logs the prior state (who, why, what changed) in the child
table, clears overdue_flagged_at if set, and resends the link. Revising a
signed ALA (signed_at IS NOT NULL) is blocked at v1 — the gate is already
cleared on the strength of that signature — mirroring the O&M provider
blocking convention above.

### What is NOT in the ALA system

Parallel to the deliberate-omissions lists elsewhere:

- No custom field involvement. Templates are tenant-defined documents,
  not custom field definitions on the claim. The Custom Field System is
  for fields that vary by tenant on claim entities; ALA templates are
  documents.
- ALA generation itself is not a clock event. The document is created
  synchronously by the Server Action handling the Indistinct outcome, not
  a future-firing event. Response-overdue reminders ARE a clock event
  (ala_response_overdue, Decision 25) — see the "Response window,
  overdue flag, and re-issue" subsection above.
- No automatic enforcement of the markup-bounds at the database level.
  Decision 7 places that validation in the application layer; the
  tenants.settings JSONB does not enforce numeric bounds in PostgreSQL
  by default. The Server Action that updates the setting is the gate.

## Inspections Foundation

**Status: Designed.** This section locks the inspections table foundation,
with the architecture having evolved through several Phase 3 decisions.
The schema (the five enum-like columns plus inspection_report JSONB),
each column's pattern assignment, and the cross-entity dependencies are
settled. Audit Topic 11 proposed a single type enum that conflated three
orthogonal axes; initial Phase 3 drafting split it into separate
performed_by and paid_by columns. Decision 17 Part B then added
inspection_type and inspection_trigger as tenant-editable defaults (per
the Tenant-Editable Defaults Pattern's Tier 1 specification) and
replaced the original 4-value status enum with a new 4-value enum
aligned with enterprise-level operational workflow. The inspections
table is the first v2 entity with mixed enum-handling patterns and
serves as the reference example for the role-based decision tree the
Tenant-Editable Defaults Pattern specifies. Operational workflow
specifics (when inspections are operationally triggered, how findings
feed back into claim status, what authority each role has at each
transition) are not in this section; later Tier 3 sections (claim
lifecycle, work plan workflow) settle the workflow.

Inspections are claim-level investigations into a defect's cause, scope,
or fix. The warranty professional uses them when the information in a
claim is insufficient to determine corrective actions, or when an
Indistinct claim needs investigation before warranty determination.
v1's Six Gates also reference inspection at Gate 3 (Evidence Evaluation)
and downstream. SOP-level terminology such as Joint Inspection (a
courtesy posture some warrantors offer to invite claimants to attend
the inspection as a transparency measure) is per-tenant operational
practice, not architecturally modeled; claimant attendance is not
captured as a structured schema column per Decision 18.1, and tenants
who track it operationally do so in inspection_report JSONB.

### Schema

    inspections
      id                            uuid PK
      tenant_id                     uuid NOT NULL FK -> tenants
                                    -- denormalized per Standard RLS Pattern
      claim_id                      uuid NOT NULL FK -> claims
      performed_by                  text NOT NULL
                                    -- 'warrantor' | 'third_party'
                                    -- CHECK constraint enforces allowed values
      paid_by                       text NOT NULL
                                    -- 'warrantor' | 'claimant' | 'third_party'
                                    -- CHECK constraint enforces allowed values
      inspection_type_id            uuid NOT NULL FK -> inspection_types(id)
      inspection_type_value         text NOT NULL
                                    -- snapshot of inspection_types.value
                                    -- captured at row creation per the
                                    -- FK + Snapshot Pattern's convention
      inspection_trigger_id         uuid NOT NULL FK -> inspection_triggers(id)
      inspection_trigger_value      text NOT NULL
                                    -- snapshot of inspection_triggers.value
                                    -- captured at row creation per the
                                    -- FK + Snapshot Pattern's convention
      status                        text NOT NULL DEFAULT 'open'
                                    -- 'open' | 'in_progress' |
                                    --   'under_review' | 'issued'
                                    -- CHECK constraint enforces allowed values
      inspection_report             jsonb nullable
                                    -- per-inspection findings, structured per
                                    -- inspection shape; null until findings
                                    -- are captured
      created_at                    timestamptz NOT NULL DEFAULT now()
      updated_at                    timestamptz NOT NULL DEFAULT now()
      -- CHECK / app-layer invariant: tenant_id matches the referenced
      -- claim's tenant_id

The table follows the Standard RLS Pattern's six steps: tenant_id FK,
RLS enabled, the standard tenant-scoped SELECT policy, service-role-only
writes, the required grants. tenant_id is denormalized onto the
inspection directly per the convention.

A claim may have zero, one, or many inspections over its lifecycle.
There is no UNIQUE constraint on claim_id — a single claim might involve
multiple inspections (an initial internal inspection, then a third-party
expert inspection if the first is inconclusive, for example).

ON DELETE behavior on the claim_id FK is not yet locked. The
architectural parallel to other claim-child entities (RESTRICT, with
soft-delete as the operational cleanup path) suggests the same restraint
here, but the specific clause is a Phase 3 implementation detail.

inspection_types and inspection_triggers are sibling lookup tables
created per the Tenant-Editable Defaults Pattern's canonical lookup
table schema. Each tenant has their own copy of each table, seeded at
provisioning with the platform-locked defaults specified in Decision 17
Part B (four default inspection_types: Warranty, Condition Assessment,
Remediation Verification, Failure Investigation; eight default
inspection_triggers including the Third Party value required by
Decision 18.2). The inspections table references each lookup table via
the FK + Snapshot integration the pattern documents: inspection_type_id
and inspection_trigger_id provide database-enforced referential
integrity to the lookup table; inspection_type_value and
inspection_trigger_value snapshot the lookup row's value column at
inspection row creation for cross-tenant analytics and
audit-defensibility. ON DELETE behavior on the two FKs to the lookup
tables is governed by the lookup tables' soft-delete semantics per the
Tenant-Editable Defaults Pattern; hard-deletion is not an ordinary
path.

### performed_by and paid_by: two orthogonal axes

Audit Topic 11 proposed a single type enum with three values: internal,
third_party, customer_paid. The values try to express both who runs the
inspection and who pays for it through one column, but the two questions
are orthogonal. internal means "warrantor performs AND warrantor pays."
third_party means "third party performs AND warrantor pays the third
party." customer_paid means "claimant pays" without saying who performs.
The collapse breaks down on real operational cases — for example, a
customer-requested inspection where the warrantor performs the work and
the warrantor is paid by the customer for the time. That case has no
home in the conflated enum.

The revised shape splits the question into two explicit columns:

- performed_by captures WHO PERFORMS the inspection. Two values:
  warrantor (the warrantor's own personnel conduct the inspection) or
  third_party (an external expert, subcontractor, structural engineer,
  manufacturer's representative, or independent investigator conducts
  it).
- paid_by captures WHO PAYS for the inspection. Three values: warrantor,
  claimant, or third_party (vendor reimbursement, insurer-funded
  inspection, or similar cases where the cost is borne by a party
  external to the warrantor-claimant relationship).

The two columns are independent. Any performer-payer combination is
valid:

- performed_by = warrantor, paid_by = warrantor — the warrantor's own
  investigation, on the warrantor's dime. The classic internal
  inspection.
- performed_by = third_party, paid_by = warrantor — the warrantor
  contracts an external expert. The classic third-party expert
  inspection.
- performed_by = third_party, paid_by = claimant — the claimant funds
  an external investigation, typically to demonstrate the basis of
  their claim under the Burden of Proof principle, or as part of an
  Indistinct Claims investigation governed by an ALA.
- performed_by = warrantor, paid_by = claimant — the claimant funds a
  warrantor-performed investigation. The case Audit Topic 11's conflated
  enum couldn't express. Common shape: the claimant requests the
  warrantor's expertise and pays for the warrantor's time.
- performed_by = warrantor, paid_by = third_party — vendor reimbursement
  or insurer-funded inspection where the warrantor's team performs but
  the cost is recovered from a vendor under their warranty or from an
  insurance carrier. The conflated enum couldn't express this either.
- performed_by = third_party, paid_by = third_party — a vendor's own
  inspection of their product, or an insurer's inspection, with the
  vendor or insurer bearing the cost.

The combinations are not all equally common, but each is operationally
real, and the schema supports each natively. The cost-tracking and
authority paths follow from the columns: the cost-tracking section
reads paid_by to determine the cost recovery path; the authority
checks read performed_by to determine which credentials apply.

Adding a new performer or payer value (a fourth performer category, or
a fifth payer category) is a future decision, not anticipated by the
locked sources. The two enums are extensible without restructuring the
shape.

### status: the inspection state machine

The four status values are platform-locked per the role-based decision
tree (status is a workflow-driver enum that platform code branches on;
tenant additions would create unknown states the platform's state
machine doesn't know how to handle).

- open — inspection created, awaiting activity. The default at row
  creation. Captures the warranty professional's decision (or response
  to a customer/third-party trigger) that an inspection is needed but
  field work has not yet begun. open subsumes what the original enum
  captured as 'requested' (record exists) and 'scheduled' (date set);
  the new enum collapses the request-vs-schedule distinction because
  operational state is the same — no field work has happened yet.
- in_progress — observations being captured. Field work is actively
  underway. Some inspections span multiple days or sessions; this
  state captures the active-execution period regardless of session
  count.
- under_review — inspection results being reviewed. Field observations
  have been captured and the warranty team is conducting internal
  review. Documentation drafting and validation happen in this state.
- issued — documentation completed and released to customer. Terminal
  state for the happy path; the inspection's resulting documentation
  has been finalized and delivered to the customer. Some tenant
  vocabularies call this documentation a Non-Conformance Report (NCR);
  the platform-level semantic is "inspection results have been
  finalized and the resulting documentation has been released to the
  customer" regardless of what the tenant calls the document.
  Consistent with the platform's discipline of treating
  tenant-specific terminology as per-tenant naming rather than
  platform vocabulary (parallel to Decision 13.4's
  Warranty FOS / Construction Support framing and Decision 18.1's
  Joint Inspection framing).

State transitions: open -> in_progress when field work begins;
in_progress -> under_review when observations are captured and ready
for review; under_review -> issued when documentation is finalized and
released. Backward transitions are not part of the architectural
commitment at this layer; whether under_review can transition back to
in_progress (e.g., review finds gaps requiring re-inspection), or
whether issued can transition back to under_review (e.g., post-release
dispute), is operational and downstream.

Migration mapping from the original enum to the new enum (for any
test data; no production tenants exist at v1):

- requested -> open
- scheduled -> open
- in_progress -> in_progress
- completed -> under_review

The new value 'issued' represents an operational state that did not
exist in the original enum. The original enum's 'completed' captured
what is now 'under_review' (field work done, ready for review);
'issued' captures the additional step of documentation finalization
and customer release that the original enum did not model.

This is a platform-locked CHECK enum, not a tenant-editable defaults
lookup table. See the Mixed-pattern columns subsection below for the
role-based reasoning behind this pattern choice.

### Mixed-pattern columns: role-based reasoning

The inspections table is the first v2 entity with multiple enum-like
columns using different architectural patterns. Five enum-like columns
span three patterns, each chosen per the role-based decision tree the
Tenant-Editable Defaults Pattern specifies:

- performed_by — platform-locked CHECK enum. Structural axis: values
  (warrantor, third_party) are universal across all warrantor business
  models and drive authority checks (which credentials apply to the
  inspection).
- paid_by — platform-locked CHECK enum. Structural axis: values
  (warrantor, claimant, third_party) are universal and drive cost
  recovery routing.
- inspection_type — Tenant-Editable Defaults. Categorization: values
  legitimately vary by tenant business and operational vocabulary.
  Platform-locked defaults (Warranty, Condition Assessment,
  Remediation Verification, Failure Investigation) cover canonical
  types; tenants extend with their own categories as needed.
- inspection_trigger — Tenant-Editable Defaults. Categorization:
  values legitimately vary by tenant business. Platform-locked
  defaults (eight values per Decision 17 Part B, including the Third
  Party value required by Decision 18.2) cover canonical triggers;
  tenants extend with their own.
- inspection_status — platform-locked CHECK enum. Workflow-driver:
  platform code branches on the value to drive the state machine,
  gate transitions, and trigger conditional logic. Tenant additions
  would create unknown states the platform doesn't know how to
  handle.

The pattern assignment per column is the role-based decision tree
applied uniformly. The Tenant-Editable Defaults Pattern's
"Mixed-pattern entities: role-based decision tree" subsection
documents the mechanics; this section is the first canonical reference
example. Future v2 entities with multiple enum-like columns follow the
same per-column role-based reasoning rather than picking a uniform
pattern across the entity.

### inspection_report: JSONB for per-shape variation

inspection_report is JSONB rather than a set of hard columns because
different inspection shapes capture different findings. A warrantor-
performed inspection on a foundation issue might capture pile depths,
soil conditions, and corrective recommendations; a third-party
engineer's report on a racking failure might capture load calculations
and failure mode analysis; a vendor-paid inspection might capture a
contracted investigator's narrative report. Forcing all of these into a
uniform hard-column shape would either constrain what can be captured or
proliferate columns most inspections leave null.

JSONB matches the same convention used for claim_type_data on claims:
variable-schema-by-discriminator data goes in JSONB, validated
application-layer against the expected shape per inspection shape. The
expected JSONB shapes for each performer/payer combination are not
specified at the architectural level — that's downstream operational
drafting, when each inspection shape's report structure is worked out.

### Cross-entity dependencies (deferred)

Real cross-entity dependencies this shell participates in, deferred to
downstream sections:

- Customer Work Authorization before a site inspection commences. SOP 1
  (Accepted Warranty Claim Lifecycle) is explicit on this for the case
  where the warrantor's team will be on-site: the warranty professional
  must request a customer Work Authorization before the on-site
  inspection can commence. The relationship between inspections and the
  Work Authorization entity is operational workflow, not this section's
  scope. Flagged for the Tier 3 Work Plan Workflow section.
- ALA gate for inspections on Indistinct claims. An inspection on an
  Indistinct claim presumably cannot commence until the ALA is signed
  (the SOPs' blocking-gate language about claim processing applies).
  The specific interaction — whether an inspection record exists in
  open state pre-ALA and advances to in_progress post-ALA, or whether
  it cannot be created at all pre-ALA — is operational and is settled
  by the Tier 3 claim lifecycle section in concert with the ALA System
  section.
- Custom field involvement. Inspections are not in Decision 3's Phase 1
  custom-field entity scope (projects, warranty_registrations, claims).
  Audit Topic 11 explicitly framed inspection_report JSONB as the
  flexibility mechanism in lieu of custom fields. A tenant wanting to
  capture inspection-specific tenant-shaped data does so through
  inspection_report JSONB; the platform does not extend custom field
  support to inspections in Phase 1.
- Claimant attendance (Joint Inspection posture). Resolved by
  Decision 18.1 as a non-feature at the schema level. Tenants who
  operationally care can capture claimant attendance in
  inspection_report JSONB per inspection. The architecture commits
  to performed_by and paid_by; claimant-attendance is not modeled
  as a structured column.
- Inspection requester (who asked for the inspection). Resolved by
  Decision 18.2: the requester axis is captured by inspection_trigger
  (Decision 17), not by a separate requested_by column. The WHO
  question is answered by reading the trigger value (Customer Request
  implies claimant-initiated; Third Party implies external-party-
  initiated; the remaining trigger values imply warrantor-initiated).

### Clock event interactions (open)

Inspections may have associated future dates (planned start of field
work, scheduled completion, follow-up reminders), which suggests
clock_events could fire reminders or notify of upcoming activity.
Whether this is actually wired — whether inspections insert
clock_events rows for reminder firing, or whether reminders are
derived at read time from date fields elsewhere — is not specified
at this section's architectural level. Flagged for downstream
operational drafting. The Clock Event Infrastructure supports the
addition of inspection-related event types without restructuring.

### What is NOT in the inspections foundation

Parallel to the deliberate-omissions lists elsewhere:

- No granular scheduling, findings, or recommendation columns
  (planned start date, scheduled party, findings detail, etc.). All
  of this is operational detail that lives inside inspection_report
  JSONB per shape, or in downstream entity tables (Work
  Authorization, work plans) where the dependencies surface. Audit
  Topic 11's framing was "the foundation costs little; the workflow
  comes later" — this section honors that.
- No claimant-attendance columns. Resolved as non-feature by Decision
  18.1; operational tracking via inspection_report JSONB if needed.
- No separate requester columns. Per Decision 18.2, the requester
  signal is captured by Decision 17's inspection_trigger enum.
- No inspection_statuses lookup table. inspection_status is a
  platform-locked CHECK enum per the role-based decision tree
  (Workflow-driver). It is not a tenant-editable defaults lookup
  table. See the Mixed-pattern columns subsection for the reasoning.
- No UI mechanics. Whether inspection requests originate from a Six
  Gates review interface, a dedicated inspections queue, or somewhere
  else is UI design, not architecture.
- No cost-tracking columns. Cost tracking has its own Tier 3 section
  per v1's Cost Tracking lifecycle stage; inspection costs feed that
  section's schema (which reads paid_by to determine the cost
  recovery path), they don't live here.

## Service Report Submission

**Status: Designed at the architectural level.** This section is sourced
primarily from SOP 5 (Submitting a Warranty Service Report), with
cross-references to SOP 1 (Accepted Warranty Claim Lifecycle) for the
tenant-configurable customer review window (three-day default per
Decision 21) and Assumption of Acquiesce, and SOP 0
(Warranty Management System Capabilities) for the platform capability
framing. The schema, the submitter dual-FK shape, the customer review
mechanism, the three-day clock event, and the universal content fields
are settled. List-shaped content items (parts, photos) face the same
JSONB-vs-child-table question as supporting_documents on Claim Intake;
that choice is flagged as Phase 3 implementation detail. The downstream
operational state machine (which specific claim status values transition
on submission, review, acceptance, dispute) belongs to the Tier 3 claim
lifecycle section.

A Warranty Service Report is the structured record of completed repair
work, prepared by whoever performed the repair and submitted to the
warranty professional for review. It is the bridge between Work Plan
execution and claim closure: the work is done, the report documents what
was done, the customer reviews the assertion of completion, and the
claim closes when the customer accepts (explicitly or by silence under
the Assumption of Acquiesce). SOP 5's framing is that this process
"ensures there is a clear and documented trail of the repair work
performed under the warranty claim, allowing for transparency and
accountability."

### One service report per claim, structurally

A claim has at most one Warranty Service Report. Multiple repair attempts
on the same claim — if the first work was inadequate and a follow-up is
needed — are operational details that resolve through the dispute
resolution path, not through multiple service reports on one claim. If
operational reality surfaces a need for multiple reports per claim, the
UNIQUE constraint below relaxes; the architectural commitment as of this
section is one-to-one.

### Schema

    service_reports
      id                            uuid PK
      tenant_id                     uuid NOT NULL FK -> tenants
                                    -- denormalized per Standard RLS Pattern
      claim_id                      uuid NOT NULL UNIQUE FK -> claims
                                    -- UNIQUE enforces 1:1 with claim;
                                    -- ON DELETE behavior is a Phase 3
                                    -- implementation detail parallel to
                                    -- other claim-child FK flags
      submitted_by_contact_id       uuid nullable FK -> contacts(id)
      submitted_by_user_id          uuid nullable FK -> public.users(id)
                                    -- CHECK: exactly one non-null when
                                    -- submitted; both null when the
                                    -- report is in pre-submission draft
      submitted_by_name_snapshot    text nullable
      submitted_by_email_snapshot   text nullable
      submitted_by_phone_snapshot   text nullable
      submitted_at                  timestamptz nullable
                                    -- set when the report is submitted
                                    -- (transitions from draft to
                                    -- submitted)
      corrective_actions            jsonb NOT NULL
                                    -- description of what was done,
                                    -- ProseMirror-compatible JSON per
                                    -- Decision 4 (rich text)
      repair_started_at             timestamptz NOT NULL
      repair_completed_at           timestamptz NOT NULL
                                    -- duration is derived from the two
                                    -- timestamps; unit (hours, days,
                                    -- business days) is a display
                                    -- decision, not a storage decision
      personnel                     jsonb NOT NULL
                                    -- array of {name, role} objects;
                                    -- locked as JSONB (not child table)
                                    -- because no downstream join surface
      parts_used                    jsonb nullable
                                    -- array of {part, quantity, ...}
                                    -- entries; JSONB-vs-child-table is
                                    -- a Phase 3 implementation detail
                                    -- (cost-tracking joins may pull
                                    -- this toward a child table)
      photos                        jsonb nullable
                                    -- array of {url, caption?, category?}
                                    -- entries with before/during/after
                                    -- categorization; JSONB-vs-child-
                                    -- table is a Phase 3 implementation
                                    -- detail (same as supporting_
                                    -- documents on Claim Intake)
      challenges_encountered        jsonb nullable
                                    -- rich text, ProseMirror-compatible
                                    -- JSON; nullable because some repairs
                                    -- have no challenges to note
      resolution_status             text NOT NULL
                                    -- 'fully_resolved' |
                                    --   'further_work_needed'
                                    -- CHECK constraint enforces allowed
                                    -- values
      further_work_explanation      jsonb nullable
                                    -- rich text, ProseMirror-compatible
                                    -- JSON; required when
                                    -- resolution_status =
                                    -- 'further_work_needed' (enforced
                                    -- application-layer)
      reviewer_user_id              uuid nullable FK -> public.users(id)
                                    -- the warranty professional who
                                    -- reviewed; nullable until reviewed
      reviewer_decision             text nullable
                                    -- 'accepted' | 'rejected'
                                    -- CHECK constraint enforces allowed
                                    -- values
      reviewed_at                   timestamptz nullable
      customer_review_token         text nullable
                                    -- single-use token for the customer's
                                    -- tokenized review link; null until
                                    -- the report is reviewer-accepted
                                    -- and the customer link is issued
      customer_review_token_expires_at  timestamptz nullable
      customer_decision             text nullable
                                    -- 'accepted' | 'disputed'
                                    -- CHECK constraint enforces allowed
                                    -- values; silence-acceptance is
                                    -- captured as customer_decision =
                                    -- 'accepted' with
                                    -- accepted_by_acquiescence = true,
                                    -- not as a distinct enum value
      accepted_by_acquiescence      boolean nullable
                                    -- set to true only when the clock
                                    -- event fires the silence-acceptance
                                    -- path; null in all other cases
                                    -- (including explicit accepts and
                                    -- disputes)
      customer_decided_at           timestamptz nullable
      customer_dispute_details      jsonb nullable
                                    -- rich text, ProseMirror-compatible
                                    -- JSON; populated when
                                    -- customer_decision = 'disputed'
      created_at                    timestamptz NOT NULL DEFAULT now()
      updated_at                    timestamptz NOT NULL DEFAULT now()
      -- CHECK / app-layer invariant: tenant_id matches the referenced
      -- claim's tenant_id

The table follows the Standard RLS Pattern's six steps: tenant_id FK, RLS
enabled, the standard tenant-scoped SELECT policy, service-role-only
writes, the required grants. tenant_id is denormalized onto the report
directly per the convention.

Rich text fields (corrective_actions, challenges_encountered,
further_work_explanation, customer_dispute_details) use the
ProseMirror-compatible JSON format from Decision 4, the same convention
as detailed_description on claims, ALA template content, and rich-text
custom field values. The character cap defaults from Decision 4 apply.

### The seven SOP content items, mapped

SOP 5 enumerates seven specific things a Warranty Service Report
contains. Each maps to a column or set of columns above:

1. "A description of the corrective actions taken" -> corrective_actions
2. "The date and duration of the repair work" -> repair_started_at plus
   repair_completed_at (duration is derived from the two timestamps;
   display unit — hours, days, business days — is a presentation choice)
3. "The names and roles of the personnel involved" -> personnel
4. "Any parts or materials used during the repair" -> parts_used
5. "Photographs or other visual evidence of the work before, during, and
   after completion" -> photos
6. "Any challenges or issues encountered during the repair process"
   -> challenges_encountered
7. "Confirmation of whether the issue has been fully resolved or if
   further work is necessary" -> resolution_status plus
   further_work_explanation

The seven items are universal across all warrantors and all claim types
— SOP 5 describes them as the standard report content, with no
warrantor-configurable variation. This is the opposite of claim_type_data
on claims, where the schema varies by discriminator. Here the schema is
uniform.

### Submitter capture: Decision 1's dual-FK pattern

The submitter columns (submitted_by_contact_id, submitted_by_user_id,
the three snapshot columns, submitted_at) apply Decision 1's dual-FK +
Snapshot Pattern. The mechanics are defined in the FK + Snapshot Pattern
section; no new commitment is being made — same pattern, different
context.

The structural reason for dual-FK here, rather than free-text capture as
Claim Intake uses for its submitter: a service report submitter is
always one of two known operational roles — a subcontractor (directory
contact, contact_type = subcontractor_contact) or a warrantor self-perform
tenant user. Never a one-off third party, unlike claim submitters who
might be a customer's facilities manager, a one-time installer, or some
other party. Free-text snapshots are appropriate for the unbounded
claim-submitter case; the dual-FK + Snapshot pattern is appropriate for
the bounded service-report-submitter case where the audit-defensibility
benefit of contact-FK reuse (recognizing a recurring subcontractor across
many service reports) outweighs the cost of the dual-FK shape.

This contrast — Claim Intake submitter = free-text snapshot; Service
Report submitter = dual-FK + Snapshot — is intentional and reflects the
different operational shapes. A future reader looking at "why one way
here and the other way there" finds the answer in this paragraph.

### Submission routing follows the FK type

Routing the service report submission to its submitter mirrors Decision
1's assignee routing exactly: a contact submitter receives a tokenized
email link via the Stateless Tokenized Interaction Pattern, opening a
focused submission form with no account required; a tenant-user
submitter uses the in-app submission form on their existing login. Same
two channels for the same operational reason — contacts have no account,
tenant users do. The pattern's "shape to copy, not shared store" rule
applies: the submitter's tokenized link has its own storage (likely a
column or columns on this table, parallel to customer_review_token
below; the exact shape is a Phase 3 implementation detail), not the
invitations table.

SOP 1 corroborates that the subcontractor is "prompted via electronic
notice to submit a Warranty Service Report through the WMS upon reaching
the projected completion date specified in the approved work plan."
This is the contact-submitter path; the tenant-user path is the
self-perform variant.

### Reviewer step

After submission, the warranty professional (a tenant user, captured in
reviewer_user_id) reviews the report. SOP 5 and SOP 1 both describe this
step: "The warranty professional reviews the Warranty Service Report to
ensure that the work has been completed according to the Work Plan and
meets the required standards." The reviewer_decision column captures
the outcome ('accepted' or 'rejected'), and reviewed_at captures when.

A rejected report goes back to the submitter for revision; the
operational mechanics of revision (whether a new report row is created,
or the existing row is reopened) are downstream operational drafting,
not locked here. The architectural commitment is that the reviewer step
exists and is captured.

An accepted report triggers the customer notification step.

### Customer review: tokenized link, three outcomes captured in two columns

When the warranty professional accepts the report, the customer is
notified per SOP 5: "The customer is then notified of the completion and
provided with a copy of the Warranty Service Report for their review.
This notification may also include a Notice of Resolution, which allows
the customer to review and either accept or reject the assertion of
completion."

The customer is a non-authenticated party — by definition the Stateless
Tokenized Interaction Pattern's customer case. The customer receives a
tokenized link (customer_review_token, with customer_review_token_expires_at
governing the three-day window) opening a focused interface with three
possible actions: accept the report, dispute the report, or take no
action. This is the fourth canonical use of the Stateless Tokenized
Interaction Pattern, after claim intake, registration assignee
submission, and supply-only delivery reporting.

The three outcomes are captured in two columns. SOP 1 is explicit that
silence is structurally treated as acceptance ("the warrantor shall
consider the silence acceptance"), so the customer_decision enum has
only two values — accepted and disputed — and the silence-acceptance
case is recorded as accepted with provenance preserved in
accepted_by_acquiescence:

- Explicit acceptance: customer_decision = 'accepted',
  accepted_by_acquiescence = null, customer_decided_at = the moment
  the customer clicked through.
- Dispute: customer_decision = 'disputed', accepted_by_acquiescence =
  null, customer_decided_at = the moment the customer submitted their
  dispute, customer_dispute_details populated. SOP 5: "If the customer
  disputes the completion, before the dispute window closes the
  warranty professional will work with the customer to address their
  concerns and take any necessary corrective actions." The dispute
  resolution path is operational and is settled by the Tier 3 claim
  lifecycle section.
- Silence-acceptance: customer_decision = 'accepted',
  accepted_by_acquiescence = true, customer_decided_at = the moment
  the clock event processed. SOP 1 names this the Assumption of
  Acquiesce: "If the customer fails to respond inside of the three-day
  confirmation/rejection period the warrantor shall consider the
  silence acceptance and close the claim for further activity."

The choice to model silence-acceptance as accepted-with-provenance
rather than as a third enum value is deliberate. Both explicit and
silent acceptance close the claim, both trigger Notice of Closure, both
have the same legal effect — operationally they are the same outcome.
Treating them as different enum values would force every downstream
surface (Server Actions, UI filters, queue queries, reporting) to
explicitly handle two states that are operationally identical. The
boolean captures the audit-trail-defensibility distinction (which
matters for "did the customer affirmatively accept or did they go
silent") without committing the rest of the system to a structural
distinction.

O&M Provider customer-side review (explicit acceptance or dispute) of
a Service Report is BLOCKED at v1 per Decision 20.6 and 20.7. The
reviewing party must be the customer directly. Even when the customer
has engaged an O&M Provider as their authorized agent for warranty
matters, the binding-commitment nature of customer-side review (the
customer accepting or disputing the warrantor's assertion that the
repair is complete, which closes or contests the claim) requires the
Customer-O&M Authorization document as a precondition. That document
is deferred to Cat 3 #9 (Customer-O&M Authorization document
architecture). Per Decision 28, the Service Report Server Action
checks for a signed om_authorization_documents row (event_type =
'service_report') before allowing an actor with contact_type IN
('om_provider', 'om_provider_contact') to submit an explicit acceptance
or dispute. If no signed row exists, the action is blocked with an
"authorization required" error and a link to initiate signing. The
silence-acceptance path (Assumption of Acquiesce) operates
independently of actor identity — it fires on the clock event
regardless of who could have responded.

### The customer review window: a new clock event type

The customer review window is a future-firing deadline. The canonical
mechanism is the Clock Event Infrastructure from Decision 9 —
clock_events, pg_cron-driven hourly. This section adds a new event type
to the enum, leveraging the extensibility property the Tier 1 section
locked. The Phase 1 event types from the Clock Event Infrastructure
section (registration_prep_pre_trigger, info_request_due,
warranty_expiry_warning, trigger_confirmation_overdue) are now joined
by a fifth:

- service_report_response_due — fires when the customer review window
  expires. The dispatcher checks the service_reports row: if
  customer_decision is still null at firing time, the row is updated
  with customer_decision = 'accepted' AND accepted_by_acquiescence =
  true AND customer_decided_at = the firing moment, then the claim
  closure flow is initiated. If customer_decision is non-null (the
  customer already accepted explicitly or disputed), the event has no
  effect — a synchronous customer action resolved the window before
  the deadline.

The event is inserted into clock_events at the moment the customer
notification is sent (when the reviewer accepts the report and the
customer link is issued). entity_type = 'service_report', entity_id =
the report's id, fires_at = now() + interval '[N] days' where N is the
tenant's configured window length. The payload JSONB carries the
report id and any context the dispatcher needs.

The window length is per-tenant configurable per Decision 21. Storage
at tenants.settings.service_report_response_days (JSONB key), DEFAULT
3 days at provisioning, application-layer validation bounds of 3-30
days. The three-day default matches SOP 1's "a minimum of three days"
baseline and the canonical platform convention established by Decision
21.6 (three days is the canonical default for any claimant response
window on the platform). Storage shape parallels Decision 7's
ala_markup_percent and Decision 19's ala_decline_recant_window_days.

Tenant setting changes are future-effective only (Decision 21.7).
When a tenant updates service_report_response_days, in-flight Service
Reports retain their original window — fires_at is locked at row
creation; setting changes do not retroactively recalculate fires_at
for pending clock events. New Service Reports issued after the
setting change use the new window. The clock_events.fires_at value is
the structural record of which window applied to each Service Report;
the window length is derivable from fires_at minus issued_at if
needed for analysis.

The silence-acceptance path (Assumption of Acquiesce) is gated by a
Feature Flag per Decision 21.5. The service_report_acquiesce_window
feature flag (default enabled at provisioning) controls whether the
service_report_response_due clock event is created at Service Report
issuance. When the flag is enabled (default), the event is created
and silence-acceptance fires at window expiry. When the flag is
disabled, the event is NOT created; the customer must explicitly
accept or dispute via the tokenized review interface; the claim
remains open until the customer acts. The feature flag joins the
Phase 1 features list in the Feature Flag System section.

### Claim status interactions (deferred to claim lifecycle)

The service report flow drives several claim status transitions:

- On reviewer acceptance: claim moves to a "Resolved" state (SOP 5 and
  SOP 1 both name this).
- On customer acceptance (explicit or by acquiescence), or post-dispute
  resolution: claim moves to a "Closed" state, and a Notice of Closure
  is sent (SOP 5: "the warrantyOS system closes the claim and
  subsequently sends a Notice of Closure to the customer").

The Tier 2 Claim Shell deliberately left the claim status enum's specific
values under-specified at the architectural level (only pre-activation
and active were locked, with richer states flagged). The Tier 3 claim
lifecycle section settles the closed set of claim status values and the
transitions between them, drawing on this section's evidence that
"Resolved" and "Closed" are meaningful states. The Service Report section
documents the trigger relationships; it does not lock the claim status
enum values.

### Custom Field System: not in Phase 1 scope

service_report is not in Decision 3's Phase 1 custom-field entity scope
(projects, warranty_registrations, claims). Whether the pattern of
tenant-configurable variation surfaces for service reports — and whether
Decision 3 needs revision to add service_report as a fourth entity_type
— is a downstream architectural question. The SOP's seven content items
are universal across warrantors and do not surface a tenant-configurable
need; if one surfaces operationally, Decision 3 gets revised and this
section gets a follow-up. The architecture as of this section commits to
the universal hard-column + JSONB shape only.

### Outstanding architectural questions

Flagged for downstream / Phase 3 implementation:

- parts_used shape: JSONB array (as drafted) or a child table
  (service_report_parts). Cost-tracking joins on parts may pull this
  toward a child table; the per-report query pattern alone is fine with
  JSONB. Same flag as supporting_documents on Claim Intake.
- photos shape: JSONB array (as drafted) or a child table
  (service_report_photos). Attachments-style querying and downstream
  asset management may pull this toward a child table. Same flag.
- Submitter's tokenized link storage: whether the link's token lives on
  the service_reports row directly or in a separate
  service_report_submission_tokens table is a Phase 3 implementation
  detail, parallel to the customer review token shape and to the claim
  intake token shape from Claim Intake's outstanding questions. The
  pattern's "shape to copy, not shared store" rule applies either way.
- Customer review window length configurability: resolved by Decision
  21. Window length is per-tenant configurable at
  tenants.settings.service_report_response_days (JSONB key), DEFAULT
  3 days, application-layer validation bounds of 3-30 days. Setting
  changes are future-effective only (Path A on in-flight Service
  Reports). Silence-acceptance behavior is gated by feature flag
  service_report_acquiesce_window (default enabled). See the customer
  review window subsection above for the full mechanic.
- service_report_response_due dispatcher payload shape: each clock event
  type has an expected payload schema validated at insert time. The
  shape for this new event type is a Phase 3 implementation detail.
- Multiple reports per claim: the UNIQUE constraint on claim_id locks
  one-to-one as the architectural commitment. If operational reality
  surfaces a need for multiple reports per claim (multiple repair
  attempts each generating their own report), the constraint relaxes.
  Flagged for downstream verification.

### What is NOT in the service report

Parallel to the deliberate-omissions lists elsewhere:

- No subcontractor company columns. The subcontractor's identity is
  reachable through submitted_by_contact_id's FK to contacts, and that
  contact's tenant-directory record carries the company information.
  Duplicating it on the report would create a sync surface.
- No work plan FK. The relationship between service reports and work
  plans is one-to-one through the claim — a claim has one work plan
  and one service report. The work plan can be reached through the
  claim_id; an explicit work_plan_id FK adds no information.
- No closure notice fields. The Notice of Closure is a customer-facing
  communication, generated from the closed claim's state. Notice
  generation is a separate concern (the v1 Customer-Facing
  Communications inventory); the service report carries the data that
  drives the notice, not the notice itself.
- No reviewer authority columns. Whether a warranty professional has
  the authority to accept or reject a specific report is a role-based
  permission check at the Server Action layer (the reviewer is a tenant
  user with role = 'reviewer' or 'team_admin'), not a column on this
  table.

## Acknowledgment Gate Pattern

**Status: Designed.** This is a Tier 1 platform-wide pattern locked by
Decision 12 (Phase 3 decisions log). The two tables
(acknowledgment_gate_templates and acknowledgment_gate_records) are Phase
3 tables to be migrated. The pattern's logical placement is alongside the
other Tier 1 conventions (Stateless Tokenized Interaction, FK + Snapshot,
Standard RLS, Custom Field System, Clock Event Infrastructure, ID
Generation, Schema Source-of-Truth); appending it at the end of v2 here is
a drafting-order convenience. Final section ordering is settled at the
Tier 4 reorganization before swap to canonical.

Some tokenized customer interactions need to put content in front of the
customer before the customer sees the actual interaction form — a Site
Readiness and Safety Requirements acknowledgment before a Customer Work
Authorization is accepted, a Warranty Claim Submission Requirements
acknowledgment before a claim is filed. The content is tenant-defined
(the warrantor's legal, safety, or operational language); the gate is
platform architecture (the same pre-form acknowledgment mechanism reused
across multiple interactions). The pattern is documented here so that
interactions opting into it do not each invent their own gate mechanism.

### Two tables: templates and records

Same parent-child shape as the ALA System: a template is tenant-defined
and reusable, a record is per-acknowledgment-event and frozen.

acknowledgment_gate_templates holds tenant-defined gate definitions —
which interaction purpose the gate guards, the gate's content, the
acknowledgment text shown beside the checkbox, whether typed name is
required, and which template is the tenant's default for the purpose.

acknowledgment_gate_records holds per-acknowledgment-event instantiations
— for one specific protected entity (one claim being submitted, one work
authorization being accepted), the customer's acknowledgment with the
template content frozen at the moment they agreed, the acknowledger's
identity capture, the timestamp, the IP for audit trail, and a
polymorphic reference to the protected entity the acknowledgment
authorizes.

### Schemas

    acknowledgment_gate_templates
      id                          uuid PK
      tenant_id                   uuid NOT NULL FK -> tenants
      gate_purpose                text NOT NULL
                                  -- 'claim_submission' |
                                  --   'work_authorization' | other
                                  --   future tokenized interaction
                                  --   types
                                  -- CHECK constraint enforces allowed
                                  -- values; extensible like clock_events
                                  -- event_type
      name                        text NOT NULL
                                  -- tenant-friendly identifier
      content                     jsonb NOT NULL
                                  -- ProseMirror-compatible JSON;
                                  -- the gate's body content
      acknowledgment_label        text NOT NULL
                                  -- the text shown next to the checkbox
                                  -- (e.g., "By checking this box, I
                                  -- confirm...")
      requires_typed_name         boolean NOT NULL DEFAULT false
                                  -- whether the gate config requires
                                  -- the customer to type their name in
                                  -- addition to checking the box
      is_default                  boolean NOT NULL DEFAULT false
                                  -- at most one default per
                                  -- (tenant_id, gate_purpose); whether
                                  -- enforced by partial UNIQUE index or
                                  -- app-layer is a Phase 3
                                  -- implementation detail
      deleted_at                  timestamptz nullable
                                  -- soft-delete required; retired gates
                                  -- must remain queryable for records
                                  -- that captured acknowledgment
                                  -- against them
      created_at                  timestamptz NOT NULL DEFAULT now()
      updated_at                  timestamptz NOT NULL DEFAULT now()

    acknowledgment_gate_records
      id                          uuid PK
      tenant_id                   uuid NOT NULL FK -> tenants
                                  -- denormalized per Standard RLS
                                  -- Pattern
      template_id                 uuid NOT NULL FK ->
                                    acknowledgment_gate_templates
      template_content_snapshot   jsonb NOT NULL
                                  -- frozen content at acknowledgment
                                  -- time; the customer agreed to
                                  -- exactly this content, not whatever
                                  -- the current template says
      acknowledger_name           text nullable
                                  -- populated only when the gate
                                  -- requires a typed name
      acknowledged_at             timestamptz NOT NULL
      acknowledger_ip             text nullable
                                  -- captured for audit trail
      authorized_entity_type      text NOT NULL
                                  -- 'claim' |
                                  --   'work_authorization_document' |
                                  --   future types
                                  -- CHECK constraint enforces allowed
                                  -- values
      authorized_entity_id        uuid NOT NULL
                                  -- FK target depends on
                                  -- authorized_entity_type; shape is a
                                  -- Phase 3 implementation detail (see
                                  -- below)
      created_at                  timestamptz NOT NULL DEFAULT now()

Both tables follow the Standard RLS Pattern's six steps: tenant_id FK,
RLS enabled, the standard tenant-scoped SELECT policy, service-role-only
writes, the required grants. tenant_id is denormalized onto both rows
directly per the convention.

Soft-delete on templates (deleted_at) is required, not optional. A
template retired today may have records pointing to it from acknowledgments
captured last year, and those records must remain readable — the frozen
content_snapshot preserves what the customer actually agreed to, but the
template_id FK must remain valid for reporting and historical query.
Hard-deleting a template would break the relationship.

The is_default boolean identifies the tenant's primary template for a
gate_purpose. At most one is_default = true per (tenant_id, gate_purpose)
is the architectural intent; whether this is enforced by a partial UNIQUE
index or by an application-layer invariant is a Phase 3 implementation
detail, parallel to ALA's is_default flag.

### gate_purpose: per-purpose configuration

A gate_purpose enum identifies what interaction the gate guards. Phase 1
values:

- claim_submission — guards a Claim Intake tokenized intake form
- work_authorization — guards a Customer Work Authorization tokenized
  acceptance form

The enum is extensible the same way Decision 9's clock_events event_type
is extensible. A future tokenized customer interaction that benefits from
a pre-form gate adds a new gate_purpose value (and updates the CHECK
constraint via migration) without restructuring the tables.

### Optional per tenant per purpose

The platform supports gates natively, but they are not mandatory. A
tenant configures a gate template for a given gate_purpose only if their
operational practice requires one. A tenant whose external compliance
processes already handle the equivalent acknowledgment — or whose
warrantor agreements don't include such gates — leaves the gate_purpose
unconfigured. Customers under that tenant proceed directly to the
interaction form without ever seeing a gate.

This framing matters. The pattern's presence in v2 is not an assertion
that warrantors should require gates; it is platform-level support for
warrantors who do. The platform doesn't impose safety or legal language
on tenants who already have external processes for it.

### One gate per protected entity in Phase 1

A protected entity (a claim being submitted, a work authorization being
accepted) carries at most one acknowledgment_gate_records row. The
acknowledgment is a one-time event per entity: once the customer
acknowledges and the record exists, the gate is not shown again for that
entity on subsequent link clicks.

Multi-gate-per-entity is deferred as speculative architecture. A tenant
who needs to capture multiple distinct acknowledgments for a single
protected entity composes them into one longer gate template's content
rather than chaining multiple gate records. If real operational
requirements surface that warrant multi-gate-per-entity (different
acknowledgments authorized at different points in an entity's lifecycle,
for example), the architecture revisits.

### Rich-text content via ProseMirror JSON

The gate's content column is ProseMirror-compatible JSON per Decision 4,
the same convention as ALA template content, detailed_description on
claims, claim emergency and offline-condition fields, the service report
rich-text fields, and rich-text custom field values. Tenants get
formatting flexibility (headers, lists, emphasis, links) without the
platform pre-deciding the document shape. The character cap defaults
from Decision 4 apply.

### Polymorphic protected-entity reference

The acknowledgment_gate_records row references the entity it authorizes
through two columns: authorized_entity_type and authorized_entity_id.
The type column captures which kind of entity is protected (claim,
work_authorization_document, future types); the id column carries the
uuid of the specific row.

Decision 12 locks the two-column shape but defers the implementation of
the polymorphic FK to Phase 3. The choice is between:

- A single nullable column per supported entity type (separate claim_id
  and work_authorization_document_id columns, with a CHECK enforcing
  exactly one non-null), giving real referential integrity but adding
  one column per supported entity type.
- A single polymorphic authorized_entity_id column without
  database-enforced FK integrity, with application-layer dispatch by
  authorized_entity_type, keeping the column count small but losing the
  database-enforced FK guarantee.
- A junction table per (entity_type, entity_id) pair, supporting many-to-
  many in principle but contradicting the one-gate-per-entity commitment
  above.

The right answer depends on how many authorized entity types the
platform actually ends up with and on operational ergonomics that
surface during build. Decision 12 commits to the two-column shape; the
mechanics are downstream. Same restraint pattern as ON DELETE behaviors
across other entities.

### Gate mechanics

The customer flow:

1. Customer clicks a tokenized link for an interaction (claim intake,
   work authorization, etc.). The Stateless Tokenized Interaction
   Pattern's existing token validation runs first.
2. The Server Action handling the tokenized link checks whether the
   tenant has a configured gate template for the interaction's
   gate_purpose. If no template is configured, the Server Action skips
   the gate and renders the interaction form directly.
3. If a template is configured, the Server Action checks whether an
   acknowledgment_gate_records row exists for this specific protected
   entity (by authorized_entity_type and authorized_entity_id). If a
   record exists, the Server Action skips the gate and renders the
   interaction form. If no record exists, the Server Action renders the
   gate screen.
4. The customer reads the gate content, checks the acknowledgment box,
   and (if requires_typed_name on the template is true) types their
   name.
5. On submission, the Server Action creates an acknowledgment_gate_records
   row capturing template_id, the frozen template_content_snapshot,
   acknowledger_name (if required), acknowledged_at, acknowledger_ip,
   and the polymorphic reference to the protected entity.
6. The Server Action then renders the interaction form. Subsequent
   tokenized link clicks for the same protected entity skip the gate
   because the record exists.

The frozen content_snapshot is captured at acknowledgment, not
referenced live through template_id. Same defensibility logic as ALA's
content_snapshot and the FK + Snapshot Pattern: the customer agreed to
exactly the content at acknowledgment time, and a later template
revision must not retroactively alter what they agreed to. The
template_id FK preserves the relationship for reporting; the
content_snapshot preserves the historical truth.

The gate is an interstitial on the existing tokenized link, not a
separate tokenized interaction. There is no second token, no second
expires_at, no second consumed_at. The Stateless Tokenized Interaction
Pattern's token (on the protected entity's record or in its own table
per that pattern's "shape to copy, not shared store" rule) is the
authentication surface; the gate is rendered or skipped by the same
Server Action that ultimately renders the interaction form.

### Cross-entity dependencies

The pattern is referenced by tokenized customer interaction sections
that may have gate configurations:

- Claim Intake Data Model uses gate_purpose = 'claim_submission'. A
  tenant who has configured a claim submission gate template requires
  the customer to acknowledge it before the intake form renders. The
  existing Claim Intake section's Stateless tokenized intake link
  subsection needs revision to cross-reference this pattern (the
  Decision 12 follow-up work item).
- Customer Work Authorization (drafted in a parallel session) uses
  gate_purpose = 'work_authorization'. The Work Authorization section
  cross-references this pattern when discussing its tokenized customer
  acceptance form.

Other tokenized customer interactions — registration assignee
submission, supply-only delivery reporting, service report customer
review — could opt into the pattern by adding their gate_purpose value
and configuring tenant templates. Whether they do is a per-interaction
decision when those sections are drafted, revised, or extended;
Decision 12 does not lock the answer.

### Outstanding architectural questions

Flagged for downstream / Phase 3 implementation:

- Polymorphic FK shape (Decision 12.6). The choice between separate
  per-entity-type FK columns, a single polymorphic authorized_entity_id
  with app-layer dispatch, or a junction table is a Phase 3
  implementation detail. Decision 12 locks the column-level shape;
  the mechanics are downstream.
- is_default enforcement. Partial UNIQUE index on (tenant_id,
  gate_purpose) where is_default = true vs application-layer invariant
  is a Phase 3 implementation detail, parallel to ALA's is_default
  flag.
- ON DELETE behavior on acknowledgment_gate_records.template_id. The
  soft-delete-on-templates convention means hard-deletion isn't an
  ordinary path, but the FK clause itself is a Phase 3 implementation
  detail.
- gate_purpose enum CHECK constraint extension mechanism. Adding a new
  gate_purpose value is a migration that updates the CHECK constraint,
  same as the clock_events event_type and the claim claim_type enums.

### What is NOT in the acknowledgment gate pattern

Parallel to the deliberate-omissions lists elsewhere:

- No second token. The gate is an interstitial on the existing tokenized
  link, not its own tokenized interaction. Token validation runs once
  per click, in the protected entity's tokenized interaction layer.
- No multi-gate-per-entity. One gate per protected entity in Phase 1.
  Multiple acknowledgments are composed into one longer gate template's
  content. If a tenant operationally needs more than one gate per entity,
  the architecture revisits.
- No tenant enforcement of "must have a gate configured." Whether a
  warrantor configures gates is up to the warrantor's compliance
  practice. Tenants without configured gates proceed without them.
- No expiration on acknowledgments. An acknowledgment_gate_records row
  is valid for the protected entity's lifetime. If operational requirements
  surface that an acknowledgment should "stale out" and re-prompt the
  customer (compliance language updated, contract renegotiated), the
  architecture revisits.
- No Custom Field System involvement. Gates are tenant-defined documents
  with a structured shape; they are not custom fields on claims or other
  entities. The Custom Field System is for fields that vary by tenant on
  the entities themselves, not for legal/safety language attached to
  interaction surfaces.

## Customer Work Authorization

**Status: Designed at the architectural level.** Decision 11 (Phase 3
decisions log) is the locked architectural specification for this entity,
including the three-table parent-child-revisions shape, the seven-value
status state machine, the five locked commitments, and the cross-entity
dependencies. Decision 12 (Acknowledgment Gate Pattern, Tier 1) is the
locked source for the gate cross-reference noted below. The three tables
(work_authorization_templates, work_authorization_documents,
work_authorization_revisions) are Phase 3 tables to be migrated. One open
architectural question — the polymorphic event_reference_id FK shape
(11b) — is deferred to Phase 3 implementation and flagged below. The
operational state machine specifics (which Server Actions transition
which status values under which conditions, the precise authority model
for who can revise versus withdraw) belong to downstream operational
drafting; this section locks the architecture, not the workflow.

A Customer Work Authorization is the document a warrantor sends to a
customer to obtain explicit approval before warranty personnel — or
contracted third parties under the warrantor's coordination — perform any
on-site activity at the customer's site. SOP 1's framing names this in
the inspection context: "the warranty professional must request a
customer Work Authorization before the joint/exploratory inspection can
commence." The platform's commitment is broader. Every event requiring
physical presence at the customer's site — inspections, repair work,
follow-up site visits, anything else operationally analogous — is gated
by an approved Work Authorization specific to that event. The
architecture intentionally extends beyond SOP 1's literal language to
capture the universal pattern.

### Schemas

Three tables. The template holds tenant-defined reusable configuration;
the document captures one specific authorization event with frozen
template snapshot and the customer's response; the revisions child table
captures the full history of warrantor edits to a single document.

    work_authorization_templates
      id                          uuid PK
      tenant_id                   uuid NOT NULL FK -> tenants
      name                        text NOT NULL
      warrantor_field_config      jsonb NOT NULL
                                  -- the configuration of warrantor-
                                  -- completed fields shown to the
                                  -- customer as read-only context
                                  -- (requestor info, planned dates,
                                  -- crew size, SOW activity)
      customer_field_config       jsonb NOT NULL
                                  -- the configuration of customer-
                                  -- entered fields (O&M contact info,
                                  -- site access, gate codes, special
                                  -- access requirements)
      legal_language              jsonb NOT NULL
                                  -- ProseMirror-compatible JSON; the
                                  -- tenant-defined legal/operational
                                  -- language that accompanies the form
      is_default                  boolean NOT NULL DEFAULT false
                                  -- at most one default per tenant
      deleted_at                  timestamptz nullable
                                  -- soft-delete required; retired
                                  -- templates must remain queryable
                                  -- for documents generated from them
      created_at                  timestamptz NOT NULL DEFAULT now()
      updated_at                  timestamptz NOT NULL DEFAULT now()

    work_authorization_documents
      id                          uuid PK
      tenant_id                   uuid NOT NULL FK -> tenants
                                  -- denormalized per Standard RLS
      claim_id                    uuid NOT NULL FK -> claims
                                  -- NO UNIQUE constraint;
                                  -- one-to-many with claim
      template_id                 uuid NOT NULL FK ->
                                    work_authorization_templates
      template_snapshot           jsonb NOT NULL
                                  -- template content captured at
                                  -- document generation time, frozen
      event_type                  text NOT NULL
                                  -- 'inspection' | 'repair_work' |
                                  --   'site_visit' | future types
                                  -- CHECK constraint enforces values;
                                  -- identifies what on-site activity
                                  -- this authorizes
      event_reference_id          uuid nullable
                                  -- FK to the specific event entity
                                  -- (inspections.id when event_type =
                                  -- 'inspection', etc.); shape resolved
                                  -- at implementation time per
                                  -- event_type (see open question 11b)
      status                      text NOT NULL DEFAULT 'draft'
                                  -- 'draft' | 'sent' | 'approved' |
                                  --   'denied' | 'revised' | 'resent' |
                                  --   'withdrawn'
                                  -- CHECK constraint enforces values
      expected_response_date      date nullable
                                  -- warrantor-set date by which
                                  -- customer response is expected;
                                  -- drives reminder event firing
      requestor_name              text NOT NULL
      requestor_company           text NOT NULL
      requestor_phone             text nullable
      requestor_email             text NOT NULL
      planned_start_at            timestamptz NOT NULL
      planned_end_at              timestamptz NOT NULL
      crew_size                   integer NOT NULL
      sow_activities              jsonb NOT NULL
                                  -- ProseMirror-compatible JSON;
                                  -- the planned Scope of Work
      om_provider_company         text nullable
      om_contact_name             text nullable
      om_contact_phone            text nullable
      om_contact_email            text nullable
      site_emergency_address      jsonb nullable
                                  -- structured address; shape
                                  -- consistent with project's
                                  -- site_address pattern
      site_accessibility_date     date nullable
      operating_hours             text nullable
      special_access_required     boolean nullable
      special_access_details      jsonb nullable
                                  -- ProseMirror-compatible JSON;
                                  -- conditional on
                                  -- special_access_required = true
      gate_code_needed            boolean nullable
      gate_code_details           jsonb nullable
                                  -- conditional on gate_code_needed
                                  -- = true
      customer_comments           jsonb nullable
                                  -- optional response, ProseMirror-
                                  -- compatible JSON; safety
                                  -- orientations, check-in/check-out,
                                  -- observations
      customer_decision           text nullable
                                  -- 'approved' | 'denied'
                                  -- nullable until customer responds
      denial_explanation          jsonb nullable
                                  -- ProseMirror-compatible JSON;
                                  -- required when customer_decision
                                  -- = 'denied' (enforced app-layer)
      signer_name_typed           text nullable
                                  -- the customer's typed-name signature
      authorization_acknowledged  boolean nullable
                                  -- the "I authorize" checkbox; must
                                  -- be true for an approval submission
      request_completed_by_name   text nullable
                                  -- the customer's representative name
      customer_token              text nullable
                                  -- single-use token for the tokenized
                                  -- access link; null after consumption
      customer_token_expires_at   timestamptz nullable
      requested_at                timestamptz NOT NULL DEFAULT now()
                                  -- when warrantor created and sent
                                  -- the request
      responded_at                timestamptz nullable
                                  -- when customer submitted response
      created_at                  timestamptz NOT NULL DEFAULT now()
      updated_at                  timestamptz NOT NULL DEFAULT now()
      -- CHECK / app-layer invariant: tenant_id matches the referenced
      -- claim's tenant_id

    work_authorization_revisions
      id                              uuid PK
      tenant_id                       uuid NOT NULL FK -> tenants
      work_authorization_document_id  uuid NOT NULL FK ->
                                        work_authorization_documents
      revised_by_user_id              uuid NOT NULL FK ->
                                        public.users(id)
                                      -- the warrantor user who made
                                      -- the revision
      revision_reason                 jsonb NOT NULL
                                      -- ProseMirror-compatible JSON;
                                      -- typically captures the denial
                                      -- reason that triggered this
                                      -- revision
      field_changes                   jsonb NOT NULL
                                      -- structured record of what
                                      -- fields changed (before/after
                                      -- pairs); shape is a Phase 3
                                      -- implementation detail
      revised_at                      timestamptz NOT NULL DEFAULT now()

All three tables follow the Standard RLS Pattern's six steps: tenant_id
FK, RLS enabled, the standard tenant-scoped SELECT policy,
service-role-only writes, the required grants. tenant_id is denormalized
onto all three directly per the convention. The application-layer
invariant that revisions.tenant_id matches the parent document's
tenant_id is parallel to other denormalization invariants in v2.

### Event-specific: one-to-many with claims

A claim has zero, one, or many Customer Work Authorizations across its
lifecycle. There is no UNIQUE constraint on claim_id. Each Work
Authorization authorizes one specific on-site event — an inspection at
one date and time, a repair-work execution at another, a follow-up site
visit later — and each event needs its own authorization. A claim with
an inspection followed by repair work followed by a follow-up visit has
three Work Authorization documents, one per event.

This is the architectural shape that distinguishes Customer Work
Authorization from ALA System and Service Report Submission. ALA's
relationship to claims is one-to-one (UNIQUE on claim_id): a claim that
needs an Indistinct ALA has exactly one. Service Report's relationship
is one-to-one (UNIQUE on claim_id): a claim has one service report
documenting the completed repair work. Work Authorization's
relationship is one-to-many because each authorization grants the
warrantor permission for one specific bounded event, not for the claim
as a whole. The same claim can have multiple events authorized
separately; each authorization is bounded by its event_type and
event_reference_id.

The contrast is operationally important. A reader looking at "why does
ALA UNIQUE-on-claim, why does Work Authorization not" finds the answer
in scope: ALA authorizes financial liability for the claim's
investigation, which happens once per Indistinct outcome per claim;
Work Authorization authorizes physical site presence for a bounded
event, which can recur multiple times per claim across its lifecycle.

### Universal blocking-gate behavior

The architectural commitment: no on-site activity of any kind — anyone
in the warrantor's coordination chain physically arriving at the
customer's site — proceeds without an approved Work Authorization for
that specific event. The Server Action layer enforces this as a
precondition check before any operation that creates on-site presence.

This is broader than SOP 1's literal language. SOP 1 names inspections
specifically (the warranty professional must request a customer Work
Authorization before the joint/exploratory inspection can commence).
The platform extends the gate to all on-site activity intentionally,
because the operational pattern — get explicit customer approval before
showing up — applies whether the on-site purpose is investigation,
repair, follow-up, or anything else. SOP 1 captured the canonical case;
the architecture commits to the pattern.

A reader looking at the audit-vs-decision relationship: SOP 1's
inspection-specific framing is preserved as an instance, not as the
limit. The platform supports broader gating, and tenants whose
operational practice already gates all site presence find the
architecture natively supports them.

### Template-vs-document parallel to ALA

The two-table shape — work_authorization_templates as tenant-defined
reusable configuration, work_authorization_documents as per-event
instantiations with frozen template_snapshot — mirrors ALA System's
templates-and-documents pattern.

Templates are tenant-defined. A tenant has one or more templates with
different warrantor and customer field configurations and different
legal language. A tenant with one operational style has one template,
defaulted. A tenant with multiple operational variants (different
templates for different on-site event types, different jurisdictions,
different SOW formalities) has multiple templates with one defaulted
per the is_default boolean.

Soft-delete on templates is required for the same reason as ALA's: a
template retired today may have generated documents last year, and
those documents' template_snapshot must remain readable while
template_id still resolves for reporting purposes. Hard-deleting a
template would break the relationship; the convention follows the same
shape as ALA, Custom Field System definitions, and Acknowledgment Gate
Pattern templates.

The frozen template_snapshot on the document is the same defensibility
mechanism as everywhere else: the customer agreed to exactly the
content captured at the moment they responded, not whatever the
template says today.

### Warrantor-completed fields

The warranty team fills the warrantor-side fields when creating the
document. These are direct text columns on the document, not FK +
Snapshot to contacts:

- requestor_name, requestor_company, requestor_phone, requestor_email
  identify the warranty professional or warrantor representative who
  is requesting the authorization. Direct field capture rather than
  FK + Snapshot to a tenant user reflects that this is a captured
  identity for the customer's reference, not a relationship the
  platform tracks for reporting reuse.
- planned_start_at, planned_end_at bracket the event window the
  warrantor intends to be on-site.
- crew_size is the number of personnel the warrantor plans to have
  on-site.
- sow_activities is the planned Scope of Work in ProseMirror-compatible
  JSON — what the warrantor intends to do during the on-site event.

This is "warrantor-completed" because the warranty team enters these
fields when constructing the request, before the customer sees the
document. They appear to the customer as read-only context.

### Customer-entered fields

The customer fills the customer-side fields when responding to the
document. These capture the operational information the warrantor needs
to coordinate the on-site event safely:

- om_provider_company, om_contact_name, om_contact_phone,
  om_contact_email identify the O&M provider or facility contact who
  will be on-site during the event (or reachable if needed).
- site_emergency_address holds a structured address for emergency
  reference, parallel to projects.site_address.
- site_accessibility_date, operating_hours, special_access_required
  (with conditional special_access_details), gate_code_needed (with
  conditional gate_code_details) capture practical access information.
- customer_comments holds optional notes from the customer — safety
  orientations, check-in/check-out procedures, observations about the
  site relevant to the planned event.

The customer_field_config on the template determines which of these
fields are required, which are optional, and any tenant-specific
labeling or instructions. The customer's response submission must
satisfy the template's required-field set.

### Tokenized form-acceptance with signature artifact

The Customer Work Authorization is the fifth canonical use of the
Stateless Tokenized Interaction Pattern, after claim intake,
registration assignee submission, supply-only delivery reporting, and
service report customer review. The customer receives a tokenized email
link to the authorization form, opens it, completes the customer-side
fields, and submits with approval or denial.

The signature artifact — captured on approval — is two columns:

- signer_name_typed: the customer's representative types their name
- authorization_acknowledged: an "I authorize" checkbox, must be true
  for an approval submission

The two-column signature artifact constitutes legal approval for the
on-site event. Form submission with both columns populated (signer
name + acknowledgment checkbox = true) plus customer_decision =
'approved' is the platform's record of authorization. The customer's
identity capture, the timestamp on responded_at, and the audit trail
through tokenized link consumption together preserve the
authorization's defensibility.

This signature mechanism is locked for Work Authorization specifically.
The ALA signature mechanism is locked separately by Decision 19
(Accept/Decline decision + atomic signature capture at Accept +
Decline-Recant Window per tenant setting). The two mechanisms are
architecturally distinct because ALA's assumption of financial
liability warrants tokenized-interaction ceremony with explicit
Accept/Decline framing and a recant window, while Work
Authorization's approval-of-on-site-activity fits typed-name-plus-
checkbox atomicity. Neither pre-decides the other; both are locked
at their respective architectural layers.

The customer_token and customer_token_expires_at columns store the
tokenized link per the Stateless Tokenized Interaction Pattern's
"shape to copy, not shared store" rule: each authorization's token
lives on its own document row rather than in the invitations table.

O&M Provider approval of a Customer Work Authorization is BLOCKED at
v1 per Decision 20.6 and 20.7. The approving party must be the
customer directly. Even when the customer has engaged an O&M Provider
as their authorized agent for warranty matters, the binding-commitment
nature of Work Authorization approval (the customer authorizing
specific on-site activity at their site) requires the Customer-O&M
Authorization document as a precondition. That document is deferred
to Cat 3 #9 (Customer-O&M Authorization document architecture). Per
Decision 28, the Work Authorization Server Action checks for a signed
om_authorization_documents row (event_type = 'work_authorization')
before allowing an actor with contact_type IN ('om_provider',
'om_provider_contact') to approve. If no signed row exists, the action
is blocked with an "authorization required" error and a link to
initiate signing.

### State machine on status

The status column transitions through seven values enforcing the
operational lifecycle:

- draft — warrantor has created the document but has not yet sent it
  to the customer. The customer cannot see a draft. Editable freely
  by the warrantor.
- sent — warrantor has sent the document to the customer (the
  tokenized link has been emailed). Awaiting customer response.
- approved — customer responded with customer_decision = 'approved'
  and submitted the signature artifact (signer_name_typed populated,
  authorization_acknowledged = true). This is the terminal state for
  the happy path; downstream on-site activity is authorized.
- denied — customer responded with customer_decision = 'denied' and
  populated denial_explanation. Triggers the revise-and-resend path
  (see below) or, as fallback, the withdrawal path.
- revised — warrantor has edited the denied document. The document is
  back to draft-like state pending resend.
- resent — warrantor has re-sent the revised document. The customer
  sees the full revision history transparently and decides again.
- withdrawn — warrantor has scrapped the request entirely (fallback
  for denials that aren't recoverable through revision). The
  authorization is permanently abandoned; the warrantor would issue a
  new document if they want to try again.

Transitions are governed by Server Actions, not by direct UPDATE on
the column. The specific authority rules — which roles can move which
documents through which transitions — are operational concerns
deferred to downstream drafting. The architectural commitment is the
seven values and the directed transitions among them.

### Revise-and-resend mechanic

The primary recovery path for a denied authorization is revise-and-
resend, not withdraw-and-recreate. When a customer denies a document,
the warrantor reviews the denial_explanation, edits the document's
fields (planned dates, scope of work, crew size, whatever the customer
objected to), and resubmits. The document's id, claim_id, and
event_reference_id stay the same — the same authorization request
evolves through one or more revisions until the customer approves (or
the warrantor withdraws as fallback).

The work_authorization_revisions child table captures each revision:

- revised_by_user_id identifies the warrantor user who made the
  revision.
- revision_reason captures why the revision happened, typically the
  customer's denial_explanation text or a paraphrase of it.
- field_changes records what fields changed and what their before/
  after values were. The shape of this JSONB record (structured diff,
  flat key-value map of changed fields, full-document snapshot before
  and after) is a Phase 3 implementation detail flagged below.
- revised_at is the timestamp.

The customer sees the full revision history transparently on resend.
A document on its third revision shows the customer all three prior
states and the warrantor's reasoning for each revision. This was
Option A from the Decision 11 resolution discussion — full
transparency for trust-building, operational clarity, and
audit-defensibility. The alternative (showing only the current
revision and burying the history) was rejected.

Withdrawal-and-new-document is the fallback for the edge case where
a denial isn't recoverable through revision (e.g., the customer's
denial reflects a fundamental scope rethink and the warrantor decides
to start over entirely). A withdrawn document is permanently
abandoned; the warrantor creates a new document with a new id if they
want to try again.

### Acknowledgment Gate Pattern cross-reference

Work Authorization uses the Acknowledgment Gate Pattern (Decision 12,
documented as its own Tier 1 section) via gate_purpose =
'work_authorization'. When a tenant has configured an acknowledgment
gate template for this purpose — the canonical example is a Site
Readiness and Safety Requirements gate — the customer encounters that
gate as the first screen of the tokenized link before reaching the
Work Authorization form. The customer must read the gate content, check
the acknowledgment box, and (if the gate template requires) type their
name. Only then does the Server Action render the actual Work
Authorization form.

The gate is per-tenant per-purpose optional. A tenant without a
configured gate for gate_purpose = 'work_authorization' sees customers
proceed directly to the Work Authorization form without a gate. The
Acknowledgment Gate Pattern section documents the mechanism, the
schema, the optional-per-tenant framing, and the polymorphic protected-
entity reference (authorized_entity_type = 'work_authorization_document',
authorized_entity_id = the document's id).

### Clock event reminder mechanism

The work_authorization_response_overdue clock event type fires when a
sent or resent document's expected_response_date passes with
customer_decision still null. This is the sixth event type added to
Decision 9's enum, after registration_prep_pre_trigger,
info_request_due, warranty_expiry_warning, trigger_confirmation_overdue,
and service_report_response_due (the latter added by Service Report
Submission).

When the warrantor sends or resends the document, the Server Action
inserts a clock_events row with event_type =
'work_authorization_response_overdue', entity_type =
'work_authorization_document', entity_id = the document's id, and
fires_at = the document's expected_response_date. When the event
fires, the dispatcher checks customer_decision: if still null, it
sends a reminder notification to the customer's tokenized link
contact email. If non-null (the customer already responded), the
event has no effect — a synchronous customer action resolved the
overdue window before firing.

The reminder cadence (one reminder, multiple reminders, escalating
cadence) is a Phase 3 implementation detail. The architectural
commitment is the event-fires-on-expected-date mechanism through
Decision 9's infrastructure.

### Cross-entity dependencies

Real cross-entity dependencies, deferred or resolved:

- Claims (FK parent). ON DELETE behavior on claim_id is a Phase 3
  implementation detail parallel to other claim-child FK flags. The
  architectural commitment is that Work Authorization documents are
  always child entities of a claim.
- Inspections (event reference). When event_type = 'inspection', the
  event_reference_id points to the inspections row. Work
  Authorization with customer_decision = 'approved' is required
  before the inspection's field work can commence — operationally,
  before the inspection's status advances from 'open' to
  'in_progress'. This resolves the cross-entity dependency the
  Inspections Foundation section flagged operationally ("Customer
  Work Authorization before a site inspection commences"); the
  resolution is here, locked at the architectural layer.
- Work Plan Workflow (event reference). When event_type =
  'repair_work', the event_reference_id points to the work plan
  entity. Work Authorization with customer_decision = 'approved' is
  required before work plan execution can commence. The Work Plan
  Workflow section is drafted later; the cross-entity flag is
  documented in advance here.
- Clock Event Infrastructure. The work_authorization_response_overdue
  event type fires reminders per the mechanism above.
- Custom Field System (Decision 3). Work Authorization is NOT in
  Phase 1 custom-field entity scope. Tenant-configurable variation
  in field labels, requiredness, and content is handled through the
  template's warrantor_field_config and customer_field_config JSONB
  rather than through custom_field_definitions on Work Authorization
  as an entity. If operational pressure surfaces a need for custom
  fields on Work Authorization specifically, Decision 3's three-entity
  scope (projects, warranty_registrations, claims) gets revisited;
  for now, the template's JSONB configuration is the mechanism.
- ALA System. ALA blocking-gate behavior and Work Authorization
  blocking-gate behavior are locked as separate but parallel
  mechanisms. ALA gates investigation (whether the warranty
  determination can proceed); Work Authorization gates on-site
  presence. The two operate independently and can both apply to the
  same claim — an Indistinct claim requiring on-site investigation
  needs both an approved ALA (financial liability accepted) and an
  approved Work Authorization (site presence approved).
- Acknowledgment Gate Pattern (Decision 12). gate_purpose =
  'work_authorization' covers the Site Readiness and Safety
  Requirements gate (or equivalent) configurable by tenants.

### Outstanding architectural questions

Flagged for downstream / Phase 3 implementation:

- Polymorphic event_reference_id FK shape (Decision 11.b). The
  event_reference_id column references different target tables per
  event_type (inspections.id when event_type = 'inspection', the
  work plan entity's id when 'repair_work', future types' rows for
  future event_type values). Whether this is implemented as a single
  nullable column with application-layer dispatch by event_type,
  separate event-type-specific FK columns (e.g., inspection_id,
  work_plan_id, with a CHECK enforcing alignment with event_type),
  or a junction table is a Phase 3 implementation detail. Decision
  11 locks the two-column shape (event_type + event_reference_id);
  the mechanics are downstream. Same restraint as the polymorphic
  FK question in the Acknowledgment Gate Pattern section.
- ON DELETE behavior on claim_id. Parallel to other claim-child FK
  flags across v2; the architectural restraint suggests RESTRICT
  with soft-delete as the cleanup path, but the specific clause is
  Phase 3.
- ON DELETE behavior on template_id. Soft-delete on templates means
  hard-deletion isn't an ordinary path, but the FK clause itself is
  Phase 3.
- ON DELETE behavior on event_reference_id. Without a database-
  enforced FK (per the polymorphic shape question), this becomes an
  application-layer integrity concern. The application must check
  for active Work Authorizations before allowing the referenced
  event entity to be deleted. The mechanics are Phase 3.
- is_default enforcement on templates. Partial UNIQUE index on
  (tenant_id) where is_default = true vs application-layer
  invariant, parallel to ALA's and Acknowledgment Gate's is_default
  flags.
- field_changes JSONB shape on revisions. Structured diff, flat
  key-value map, full-document before/after snapshot, or another
  shape is a Phase 3 implementation detail.
- Reminder cadence configuration. Whether the
  work_authorization_response_overdue event fires once or multiple
  times, and where the cadence configuration lives
  (tenants.settings, template configuration, hardcoded default), is
  a Phase 3 implementation detail.
- Authority rules for status transitions. Which roles can move
  documents through which transitions (e.g., can any Reviewer
  withdraw, or only Team Admin; can a different reviewer revise a
  document originally created by another reviewer) are operational
  authorization concerns, not schema-level.

### What is NOT in customer work authorization

Parallel to the deliberate-omissions lists elsewhere:

- No customer FK to the Unified Contacts Directory. The customer-
  facing identity capture is the typed signature (signer_name_typed)
  plus the customer's representative name (request_completed_by_name)
  as direct text fields, not as FK + Snapshot to a contacts row. The
  customer in this context is the entity associated with the claim's
  parent project, reachable through warranty_registration_id ->
  projects.customer_id; the Work Authorization document captures the
  on-site representative who responds, which is often different from
  the project's customer-of-record and varies per event.
- No O&M provider FK. The O&M provider information captured in
  om_provider_company through om_contact_email is direct field
  capture in Decision 11's locked schema, not FK + Snapshot to a
  contacts row. This parallels how Claim Intake captures O&M Provider
  information (also direct field capture in its current state).
  Whether either section should resolve toward FK + Snapshot remains
  an open architectural question on the Claim Intake side; Work
  Authorization's current shape reflects Decision 11's specification,
  and any future revision toward FK + Snapshot would warrant its own
  architectural decision rather than tracking another section's
  resolution implicitly.
- No work plan FK separate from event_reference_id. When event_type
  = 'repair_work', event_reference_id IS the work plan FK. Adding a
  separate work_plan_id would duplicate the relationship.
- No multi-event-per-document. A single Work Authorization document
  covers exactly one event (one event_type + one event_reference_id
  pair). A claim with multiple events has multiple documents. The
  one-document-per-event architectural choice is what makes
  one-to-many with claims operationally clean.
- No custom field involvement at the entity level. Tenant-
  configurable variation lives in the template's
  warrantor_field_config and customer_field_config JSONB, not
  through Decision 3's custom_field_definitions mechanism.
- No second token for the Acknowledgment Gate. The gate is an
  interstitial on the existing tokenized link (customer_token
  above), not a separate tokenized interaction. The Acknowledgment
  Gate Pattern section documents this mechanism.

## Work Plan Workflow

**Status: Designed at the architectural level.** This is the largest Tier 3
section, depending on substantial pre-triage work resolved in Decisions 13,
14, 15, and 16 (Phase 3 decisions log). Decision 13 locks the execution_path
enum, the internal_team_id FK, and the new internal_teams table. Decision
14 locks the Notice of Defect entity as a separate claim-child entity with
no FK relationship to Work Plan (cross-referenced here; its own section
documents its schema). Decision 15 locks the work_plans status state
machine at five values. Decision 16 explicitly excludes Parts Claims from
the Work Plan Workflow scope. The two tables documented here
(work_plans and internal_teams) are Phase 3 tables to be migrated. The
operational state machine specifics (authority rules per transition,
backward-transition handling on customer-disputed completion, etc.) belong
to downstream operational drafting.

A Work Plan is the document detailing the corrective actions the warrantor
or executing subcontractor intends to perform to address a claim. SOP 6
frames its purpose as ensuring "transparency, alignment, and agreement
among all parties involved before the repair work commences." It is the
warrantor's INTENT (the planned execution); Customer Work Authorization
(Decision 11) is the customer-facing COMMITMENT generated from that intent.
The two entities are intentionally separate: a Work Plan captures what
the warrantor plans, a Work Authorization captures what the customer
agreed to permit.

### Schemas

Two tables. internal_teams is a tenant-defined registry of internal teams
the warrantor uses for warranty work; work_plans is the per-claim
operational record of planned execution.

    internal_teams
      id              uuid PK
      tenant_id       uuid NOT NULL FK -> tenants
                      -- denormalized per Standard RLS Pattern
      name            text NOT NULL
                      -- tenant's own label (e.g., "Warranty FOS",
                      -- "Construction Support", "Tier 1 Service",
                      -- whatever fits the warrantor's organizational
                      -- structure)
      description     text nullable
                      -- optional explanatory note
      deleted_at      timestamptz nullable
                      -- soft-delete required; historical work_plans
                      -- retain internal_team_id FK even when teams
                      -- are retired
      created_at      timestamptz NOT NULL DEFAULT now()
      updated_at      timestamptz NOT NULL DEFAULT now()

    work_plans
      id                            uuid PK
      tenant_id                     uuid NOT NULL FK -> tenants
                                    -- denormalized per Standard RLS
      claim_id                      uuid NOT NULL FK -> claims
                                    -- NO UNIQUE constraint;
                                    -- one-to-many with claim
      execution_path                text NOT NULL
                                    -- 'warrantor_self_performs' |
                                    --   'scope_owned_subcontractor' |
                                    --   'outsourced_subcontractor' |
                                    --   'customer_self_services'
                                    -- CHECK constraint enforces values
      internal_team_id              uuid nullable FK -> internal_teams
                                    -- CHECK: NOT NULL when
                                    -- execution_path =
                                    -- 'warrantor_self_performs',
                                    -- NULL otherwise
      subcontractor_contact_id      uuid nullable FK -> contacts(id)
                                    -- CHECK: NOT NULL when
                                    -- execution_path IN
                                    -- ('scope_owned_subcontractor',
                                    -- 'outsourced_subcontractor'),
                                    -- NULL otherwise
      subcontractor_name_snapshot   text nullable
      subcontractor_email_snapshot  text nullable
      subcontractor_phone_snapshot  text nullable
      warranty_professional_user_id uuid NOT NULL FK -> public.users(id)
                                    -- the tenant user managing this
                                    -- Work Plan (the workbook's
                                    -- "Warrantor Contact"); always
                                    -- populated regardless of
                                    -- execution_path
      work_plan_type                text NOT NULL
                                    -- 'repair' | 'inspection' | 'both'
                                    -- CHECK constraint enforces values
      status                        text NOT NULL DEFAULT 'draft'
                                    -- 'draft' | 'sent_for_authorization'
                                    -- | 'authorized' | 'completed' |
                                    --   'cancelled'
                                    -- CHECK constraint enforces values
      planned_start_at              timestamptz NOT NULL
                                    -- SOP 6 component 1: Planned
                                    -- Arrival Date and Time
      planned_end_at                timestamptz NOT NULL
                                    -- SOP 6 component 6: Estimated
                                    -- Duration, captured as start+end
                                    -- pair matching Customer Work
                                    -- Authorization Decision 11
      crew_size                     integer NOT NULL
                                    -- SOP 6 component 2: Crew Size
      corrective_actions            jsonb NOT NULL
                                    -- SOP 6 component 3: Corrective
                                    -- Actions; ProseMirror-compatible
                                    -- JSON per Decision 4
      required_materials_equipment  jsonb nullable
                                    -- SOP 6 component 4: Required
                                    -- Materials and Equipment;
                                    -- ProseMirror-compatible JSON;
                                    -- workbook's "Special Equipment
                                    -- Needed" maps here; nullable
                                    -- because not every Work Plan
                                    -- requires special materials
      repair_scope_approach         jsonb NOT NULL
                                    -- SOP 6 component 5: Repair Scope
                                    -- and Approach; ProseMirror-
                                    -- compatible JSON; workbook's
                                    -- "Service Scope of Work" maps here
      safety_considerations         jsonb nullable
                                    -- SOP 6 component 7: Safety
                                    -- Considerations; ProseMirror-
                                    -- compatible JSON; nullable
                                    -- because tenants may rely on the
                                    -- Acknowledgment Gate Pattern's
                                    -- Site Readiness & Safety
                                    -- Requirements gate for much of
                                    -- this content
      site_access_coordination      jsonb nullable
                                    -- SOP 6 component 8: Site Access
                                    -- and Coordination; ProseMirror-
                                    -- compatible JSON; nullable
                                    -- because the Customer Work
                                    -- Authorization captures most
                                    -- site access fields directly
      created_at                    timestamptz NOT NULL DEFAULT now()
      updated_at                    timestamptz NOT NULL DEFAULT now()
      -- CHECK / app-layer invariant: tenant_id matches the referenced
      -- claim's tenant_id

Both tables follow the Standard RLS Pattern's six steps: tenant_id FK,
RLS enabled, the standard tenant-scoped SELECT policy, service-role-only
writes, the required grants. tenant_id is denormalized onto both directly
per the convention.

### Event-specific: one-to-many with claims

A claim has zero, one, or many Work Plans across its lifecycle. There is
no UNIQUE constraint on claim_id. Each Work Plan addresses one specific
execution effort — initial repair work, follow-up after dispute, an
inspection that turned into remediation. A claim with multiple distinct
repair events has multiple Work Plans, one per event.

This is the same architectural shape as Customer Work Authorization and
Notice of Defect, and the same contrast against ALA (UNIQUE on claim_id,
one-per-Indistinct-outcome) and Service Report (UNIQUE on claim_id,
one-per-claim-completion). The one-to-many pattern applies because Work
Plans bound specific execution events, not claims as a whole; multiple
events per claim is operationally expected.

### Execution path and internal teams

Decision 13 establishes a two-column shape for capturing who executes the
repair work. The columns are orthogonal axes — what kind of party
executes (execution_path) and which specific party (internal_team_id or
subcontractor_contact_id, conditional on execution_path).

The execution_path enum has four locked values, mapping to v1's Four
Work Plan Execution Paths:

- warrantor_self_performs — an internal team executes the repair (v1's
  Path 1).
- scope_owned_subcontractor — the original installer with an active
  warranty obligation executes the repair (v1's Path 2A).
- outsourced_subcontractor — a third party procured via RFQ executes the
  repair (v1's Path 2B).
- customer_self_services — the customer executes the repair with
  warrantor reimbursement (v1's Path 3).

This enum is extensible. A fifth execution path that surfaces
operationally adds a new value via migration without restructuring.

The internal_team_id FK captures the specific internal team executing
the repair when execution_path = 'warrantor_self_performs'. A CHECK
constraint enforces that internal_team_id is non-null exactly when
execution_path equals that value, null otherwise. The internal_teams
table is tenant-defined: each warrantor populates it with their own
team labels (Terrasmart uses "Warranty FOS" and "Construction Support";
other warrantors define their own naming) and the platform does not
enshrine any specific team labels at the enum level.

Decision 13 explicitly does not add an is_primary boolean to
internal_teams. The primary-vs-fallback distinction between, e.g.,
warranty FOS as the primary internal team and construction support as
the fallback, is not architecturally tracked at the team level. Cost
analysis answers through the future Cost Tracking section joining
work_plans to internal_teams via internal_team_id; UI default-selection
behavior (pre-selecting a default team when creating a work_plan) lives
in tenants.settings if needed.

The subcontractor_contact_id FK captures the specific subcontractor
when execution_path is either scope_owned_subcontractor or
outsourced_subcontractor. The capture follows the FK + Snapshot
Pattern's single-FK shape: contact_id plus name/email/phone snapshots
captured at Work Plan creation time. A CHECK constraint enforces that
subcontractor_contact_id is non-null exactly when execution_path is one
of the two subcontractor values, null otherwise.

For execution_path = 'customer_self_services', both internal_team_id
and subcontractor_contact_id are null. The customer-as-executor is
captured through the claim's parent project's customer_id; no
additional Work-Plan-level FK is needed.

### The eight SOP 6 components as operational fields

SOP 6 enumerates eight components a Work Plan contains. Each maps to a
column or pair of columns on the work_plans schema:

1. Planned Arrival Date and Time — planned_start_at (timestamptz)
2. Crew Size — crew_size (integer)
3. Corrective Actions — corrective_actions (ProseMirror JSONB)
4. Required Materials and Equipment — required_materials_equipment
   (ProseMirror JSONB, nullable); the workbook's "Special Equipment
   Needed" maps here as the warrantor's representation
5. Repair Scope and Approach — repair_scope_approach (ProseMirror JSONB);
   the workbook's "Service Scope of Work" maps here
6. Estimated Duration — captured as the pair planned_start_at and
   planned_end_at (both timestamptz). The workbook's "Number of Days to
   Complete" is derivable from the difference. The two-timestamp shape
   mirrors Customer Work Authorization (Decision 11) for clean field
   replication when generating a Work Authorization from a Work Plan.
7. Safety Considerations — safety_considerations (ProseMirror JSONB,
   nullable). Tenants who configure the Acknowledgment Gate Pattern's
   Site Readiness and Safety Requirements gate may capture most safety
   content there rather than in this field; the field stays nullable
   to support both patterns.
8. Site Access and Coordination — site_access_coordination (ProseMirror
   JSONB, nullable). Customer Work Authorization captures structured
   site access fields directly (site_emergency_address,
   site_accessibility_date, operating_hours, special_access_required,
   gate_code_needed, gate_code_details); this Work Plan field is the
   warrantor's planning notes preceding that customer-facing structured
   capture.

All eight components are uniform across warrantors (SOP 6 frames them as
the standard Work Plan content). No claim-type-driven JSONB shape
variation parallel to claims.claim_type_data — the eight components apply
regardless of which claim_type a Work Plan addresses.

### Work Plan type

The work_plan_type column captures whether a Work Plan covers repair
work, inspection work, or both. Values: 'repair', 'inspection', 'both'.
CHECK constraint enforces. This comes from the Work Plan Data Inputs
workbook's "Work Plan Type" dropdown directly.

The relationship between work_plan_type and Customer Work Authorization's
event_type (which has values 'inspection', 'repair_work', 'site_visit',
and future types) is operational and not yet locked at the architectural
level. A Work Plan with work_plan_type = 'both' might generate a single
Customer Work Authorization document with event_type = 'repair_work' (if
the bundled approach is operationally preferred), or two separate
Customer Work Authorization documents (one with event_type = 'inspection'
and one with event_type = 'repair_work'), each referencing the same
work_plans row via event_reference_id. Which pattern applies is flagged
as a downstream operational question.

### Status state machine

Decision 15 locks the work_plans.status column at five values, capturing
only the lifecycle moments that are uniquely Work Plan moments. Several
operational states that might be expected (submitted, in_execution,
scheduled, revised, resent) are deliberately NOT on the Work Plan because
they belong to other entities' lifecycles or to the claim status level.

- draft — Work Plan is being authored. Editable freely by the authoring
  party (the subcontractor in Path 2A, the warranty professional in Path
  1 or post-rejection scenarios). The customer cannot see a draft.
- sent_for_authorization — Work Plan has been bundled into a Customer
  Work Authorization request and sent to the customer. The Customer Work
  Authorization's own state machine (Decision 11) governs the
  approval/denial/revision lifecycle; the Work Plan stays in
  sent_for_authorization while that runs, including across revision
  cycles on the Work Authorization.
- authorized — A Customer Work Authorization for this Work Plan has been
  approved by the customer (customer_decision = 'approved' on the
  corresponding work_authorization_documents row). Work Plan is ready
  for execution per the warrantor's coordination.
- completed — Repair work is complete and a Service Report has been
  submitted per the Service Report Submission section's lifecycle.
  Claim-level transitions and customer review of the Service Report
  continue from here.
- cancelled — Work Plan was created but will not be executed. Terminal
  state for Work Plans that are abandoned (situation changed, customer
  rejected Work Authorization and warrantor opted not to revise, a
  different Work Plan superseded this one).

Per Decision 15.5, the Work Plan does NOT replicate the
revised/resent states from Customer Work Authorization. When a customer
rejects a Work Authorization and the warrantor revises and re-sends, the
Work Plan stays in sent_for_authorization while the underlying Work
Authorization document goes through its own revision cycle. The Work
Plan only transitions to authorized when a Work Authorization for it is
finally approved.

Transitions are governed by Server Actions, not direct UPDATE on the
column. Authority rules for transitions (which roles can move which
documents through which transitions) are operational concerns deferred
to downstream drafting.

### Cross-reference: Notice of Defect (Decision 14)

Decision 14 establishes notices_of_defect as a separate claim-child
entity capturing the warrantor's official notification that "this defect
is yours; respond with acceptance/rejection." A Notice of Defect can be
sent to any party type — subcontractors (Path 2A or 2B contacts),
internal teams (Path 1 users via public.users dual-FK), vendors,
original installers, future types.

There is no FK relationship between Notice of Defect and Work Plan in
either direction. The notices_of_defect table has no work_plan_id
column; the work_plans table has no notice_of_defect_id column. The
operational sequence — "a subcontractor accepted a Notice of Defect and
then drafted a Work Plan" or "the warrantor rejected a Notice of Defect
and sourced an alternate" — is captured at the application layer
through the claim's history, not at the schema level.

This decoupling is deliberate. Per Decision 14.4, the Notice of Defect's
architectural responsibility ends at response capture. Whether a Work
Plan, downstream tracking, dispute, or other activity follows from an
accepted Notice is operational and contract-dependent. The application
reads the claim's history to answer "which Notice of Defect led to this
Work Plan" if that analysis is needed; the schema does not enforce the
relationship.

The notices_of_defect entity has its own schema and is documented in
its own section (drafted in a future session). Decision 14 in the Phase
3 decisions log holds the locked architectural specification.

### Cross-reference: Customer Work Authorization (Decision 11)

The Work Plan is bundled INTO a Customer Work Authorization request when
the warrantor sends it for customer authorization. The FK direction is
from Work Authorization to Work Plan, not the reverse:
work_authorization_documents.event_type = 'repair_work' (or 'inspection'
or 'site_visit' as applicable), with event_reference_id pointing to the
work_plans row.

The work_plans table has no work_authorization_id column. The
relationship is captured on the Work Authorization side via the
polymorphic event_reference_id, per Decision 11's locked schema.

The Work Plan transitions to authorized when a Customer Work
Authorization for it has customer_decision = 'approved'. The Server
Action handling the Work Authorization approval triggers this Work Plan
status update.

Several fields appear on both work_plans and work_authorization_documents
— planned_start_at, planned_end_at, crew_size, and the substance of
sow_activities (composed at Work Authorization generation time from the
Work Plan's corrective_actions and repair_scope_approach). This
duplication is intentional. Work Plan is the warrantor's INTENT;
Customer Work Authorization snapshots that intent for the customer's
review and approval. A Work Plan revision after a customer denial may
update the Work Plan's fields and then trigger Work Authorization
revision separately; the duplication isolates the warrantor's planning
state from the customer-facing commitment state.

### Cross-reference: Service Report Submission

The Work Plan transitions to completed when a service_reports row
exists for the parent claim documenting completion. Service Report
Submission section documents the service_reports table and its
lifecycle; the Work Plan does not replicate any of that schema or
state. Service Report's own customer review lifecycle
(accept/dispute/acquiesce) continues independently of the Work Plan's
status.

The Server Action handling service report submission triggers the Work
Plan status update to completed. The Work Plan's transition is one of
several effects of service report submission; the claim status also
transitions per the Service Report Submission section's specification.

### Subcontractor and internal team assignee capture

Decision 13 establishes the two-column shape for execution path and
team capture. The subcontractor capture (when execution_path is
scope_owned_subcontractor or outsourced_subcontractor) uses the FK +
Snapshot Pattern's single-FK shape (subcontractor_contact_id plus
name/email/phone snapshots), parallel to how projects.customer_id
captures the customer.

The structural reason for single-FK + Snapshot here, rather than the
dual-FK pattern Service Report Submission uses for its submitter: in
Service Report's case, the submitter could be either a contact
(subcontractor) or a tenant user (warrantor self-perform team) and the
dual-FK accommodates either. In Work Plan's case, the question of
"who executes" is already captured by execution_path; the assignee
capture splits cleanly by path — internal_team_id for self-performs,
subcontractor_contact_id for subcontractor paths, neither for customer
self-services. There's no need for a single column accepting either
contact or user reference because the paths are pre-disambiguated.

The warranty_professional_user_id FK captures the warranty professional
managing this Work Plan from the warrantor's side, regardless of
execution_path. The workbook's "Warrantor Contact" fields (Name, Phone,
Email) map to this FK plus its joined user record — they are not
captured as redundant columns on work_plans.

### Cross-entity dependencies

Real cross-entity dependencies, deferred or resolved:

- Claims (FK parent). ON DELETE behavior on claim_id is a Phase 3
  implementation detail parallel to other claim-child FK flags. The
  architectural commitment is that Work Plan documents are always
  child entities of a claim.
- internal_teams (FK). The work_plans.internal_team_id FK points to
  this section's internal_teams table when execution_path =
  'warrantor_self_performs'.
- contacts (FK). The work_plans.subcontractor_contact_id FK points to
  the Unified Contacts Directory's contacts table for subcontractor
  execution paths. The contact_type values used (subcontractor,
  subcontractor_contact, or future variations) are governed by the
  contacts directory's enum.
- public.users (FK). The work_plans.warranty_professional_user_id FK
  points to the tenant user managing the Work Plan.
- Inspections Foundation. Inspections is a separate entity with no
  direct FK relationship to work_plans in either direction. Both Work
  Plan and Inspections can be referenced by Customer Work Authorization
  documents via Decision 11's polymorphic event_reference_id mechanism
  (event_type = 'inspection' pointing to inspections rows; event_type
  = 'repair_work' pointing to work_plans rows). The operational
  sequence where a Work Plan with work_plan_type = 'inspection' or
  'both' relates to one or more inspections rows is captured via the
  claim's history at the application layer, not via direct FK between
  work_plans and inspections.
- ALA System. ALA is a parallel claim-level entity for financial
  liability on Indistinct claims. ALA's blocking-gate (investigation
  cannot proceed without ALA approval on Indistinct claims) operates
  independently of Customer Work Authorization's blocking-gate
  (on-site activity cannot proceed without Work Authorization approval
  per Decision 11.2). Work Plan is the warrantor's intent that flows
  through the Work Authorization gate; Work Plan itself does not gate
  anything at the architectural level. An Indistinct claim requiring
  on-site investigation may have an approved ALA, one or more Work
  Plans, and corresponding Customer Work Authorizations, with each
  entity contributing its own architectural commitment to the claim
  lifecycle.
- Notice of Defect (Decision 14). No FK either direction. Operational
  sequence captured via claim history.
- Customer Work Authorization (Decision 11). FK is on the Work
  Authorization side via event_reference_id when event_type =
  'repair_work'. Work Plan transitions to authorized on Work
  Authorization approval.
- Service Report Submission. No FK from Work Plan to Service Report.
  Service Report references claim_id; the Work Plan status updates to
  completed when a service_reports row exists for the claim.
- Clock Event Infrastructure (Decision 9). No direct clock_events
  interaction at the work_plans level. The cross-referenced entities
  (notices_of_defect, work_authorization_documents, service_reports)
  use clock events for their own reminder firing.
- Custom Field System (Decision 3). Work Plan is NOT in Phase 1
  custom-field entity scope. Tenant-configurable variation in Work
  Plan fields is not supported through custom_field_definitions in
  Phase 1. If operational pressure surfaces a need, Decision 3's
  three-entity scope (projects, warranty_registrations, claims) gets
  revisited; until then, the Work Plan schema is fixed at the
  architectural level.

### Outstanding architectural questions

Flagged for downstream / Phase 3 implementation:

- ON DELETE behavior on claim_id. Parallel to other claim-child FK
  flags across v2; the architectural restraint suggests RESTRICT with
  soft-delete as the cleanup path, but the specific clause is Phase 3.
- ON DELETE behavior on internal_team_id. Soft-delete on internal_teams
  means hard-deletion isn't an ordinary path, but the FK clause is
  Phase 3.
- ON DELETE behavior on subcontractor_contact_id. Soft-delete on
  contacts means hard-deletion isn't an ordinary path; FK clause is
  Phase 3.
- ON DELETE behavior on warranty_professional_user_id. Soft-remove on
  tenant users (removed_at semantics) means hard-deletion isn't an
  ordinary path; FK clause is Phase 3.
- Authority rules for status transitions. Which roles can move Work
  Plans through which transitions (can any Reviewer cancel a Work
  Plan, or only Team Admin; can a different reviewer send a Work Plan
  for authorization that another reviewer drafted) are operational
  authorization concerns, not schema-level.
- The transition from completed back to a non-terminal state.
  Whether a completed Work Plan can ever transition backward (Service
  Report disputed by customer leads to repair re-execution) is
  operational and depends on whether the dispute resolution path
  creates a new Work Plan or reopens an existing one.
- The work_plan_type = 'both' relationship to Customer Work
  Authorization documents. A Work Plan covering both repair and
  inspection may generate one bundled Work Authorization document or
  two separate documents (one per event_type). Which pattern applies
  is a downstream operational decision.
- sow_activities composition at Customer Work Authorization
  generation. Whether work_authorization_documents.sow_activities is
  generated by composing the Work Plan's corrective_actions and
  repair_scope_approach automatically, or is independently captured at
  Work Authorization creation time, is a Phase 3 implementation detail.

### What is NOT in the work plan workflow

Parallel to the deliberate-omissions lists elsewhere:

- **Parts Claims explicit exclusion.** Per Decision 16.3, Parts Claims
  (claim_type = 'replacement_parts') are NOT handled through the Work
  Plan Workflow. Their fulfillment lifecycle (sourcing, shipping,
  tracking, receiving, defective-part-return) is architected
  separately in a future Parts Fulfillment section. The Work Plan
  schema and supporting entities are designed for field-repair
  execution at customer sites, not shipping/receiving logistics. A
  Parts Claim's intake remains captured per the existing Claim Intake
  Data Model section's claim_type = 'replacement_parts' shape; what
  happens after intake is governed by a separate architecture not in
  this section's scope.
- No notice_of_defect_id FK. Per Decision 14.4, Notice of Defect and
  Work Plan have no FK relationship in either direction. Operational
  sequence captured via claim history.
- No work_authorization_id FK on work_plans. Per Decision 11, the FK
  is on the Work Authorization side via event_reference_id. Adding a
  reverse FK on work_plans would duplicate the relationship.
- No service_report_id FK on work_plans. Per the Service Report
  Submission section, the Service Report references claim_id; the
  Work Plan transitions to completed based on service_report
  existence for the claim, not on a direct FK.
- No submitted state on status. Per Decision 15.2, the
  previously-considered submitted state collapses into the draft ->
  sent_for_authorization transition. Draft is editable up to the
  point of sending; the act of sending IS the transition.
- No in_execution state on status. Per Decision 15.3, the
  previously-considered in_execution state is NOT modeled on the
  Work Plan. That lifecycle moment is tracked at the claim status
  level rather than the Work Plan status level. Modeling it on both
  would duplicate state.
- No scheduling state between authorized and completed. Per
  Decision 15.4, this is a claim-level concern, not a Work Plan
  status.
- No revised or resent states on status. Per Decision 15.5, the
  Customer Work Authorization (Decision 11) has these states
  governing the customer-rejection-and-revision lifecycle. The Work
  Plan does NOT replicate them. The Work Plan stays in
  sent_for_authorization while the underlying Work Authorization
  document goes through its own revision cycle.
- No customer FK directly on work_plans. The customer is the parent
  project's customer, reachable through claim_id ->
  warranty_registration_id -> projects.customer_id with project's
  customer snapshots. Duplicating on Work Plan would create a sync
  surface.
- No Custom Field System involvement at the entity level. Work Plan
  is not in Decision 3's Phase 1 custom-field entity scope. Tenant-
  configurable variation in Work Plan fields beyond what the eight
  SOP 6 components capture is not supported through
  custom_field_definitions in Phase 1.
- No is_primary or default-team flag on internal_teams. Per Decision
  13.5, the primary-vs-fallback distinction between internal teams
  is not architecturally tracked at the team level. UI default-
  selection behavior lives in tenants.settings if needed; cost
  analysis answers through future Cost Tracking joining work_plans
  to internal_teams.


---

## Tenant-Editable Defaults Pattern

**Status: Designed.** This is a Tier 1 platform-wide pattern locked by
Decision 17 Part A (Phase 3 decisions log). The pattern is greenfield
architecture; no tables exist at v1 launch beyond what canonical
applications introduce (inspection_types and inspection_triggers per
Decision 17 Part B). Logical placement is alongside the other Tier 1
patterns (Standard RLS, FK + Snapshot, Custom Field System, Acknowledgment
Gate, Stateless Tokenized Interaction, Clock Event Infrastructure, ID
Generation, Schema Source-of-Truth, Feature Flag System). Final section
ordering is settled at the Tier 4 reorganization before swap to canonical.

Some platform-level enum-like data needs a third configuration shape
beyond v2's existing two. Platform-locked CHECK enums (claim_type,
execution_path, work_plan_type, etc.) carry values the platform commits to
and tenants cannot extend. Tenant-defined JSONB and template tables
(Custom Field System, ALA templates, Acknowledgment Gate templates) carry
values the platform provides no defaults for and tenants define from
empty. Tenant-Editable Defaults sits between these: the platform provides
a starting set of canonical values, and each tenant takes ownership of
their own copy of that set, with the ability to extend, disable, and (for
their own additions) remove values. The platform's canonical defaults
remain consistent across all tenants for cross-tenant analytics; tenant-
added values vary per tenant business.

Two canonical uses identified during pattern formalization: the three
Inspections lookup tables (inspection_types, inspection_triggers per
Decision 17 Part B), and the future Reserve Forecasting capability's
calculation parameters (per scope note in the decisions log). The
two-canonical-uses signal is what justified formalizing the pattern as
Tier 1 rather than treating it as an Inspections-specific configuration
mechanism. v2's prior precedents for Tier 1 promotion (Custom Field
System, FK + Snapshot Pattern, Standard RLS Pattern) all crystallized
when multiple uses appeared; this section follows that discipline.

### Canonical lookup table schema

Every tenant-editable defaults lookup table follows the same shape. The
schema below uses <enum_name>s as a placeholder; an applying entity
substitutes the specific enum name (inspection_types, inspection_triggers,
etc.):

    <enum_name>s
      id            uuid PK
      tenant_id     uuid NOT NULL FK -> tenants
                    -- denormalized per Standard RLS Pattern
      value         text NOT NULL
                    -- platform-canonical identifier; snake_case,
                    -- lowercase; tenants cannot edit for non-
                    -- tenant_added rows
      label         text NOT NULL
                    -- tenant-displayed name; editable subject to
                    -- lock_tier restrictions
      lock_tier     text NOT NULL
                    -- 'platform_locked' | 'platform_seeded' |
                    --   'tenant_added'
                    -- CHECK constraint enforces values
      sort_order    integer NOT NULL DEFAULT 0
      disabled_at   timestamptz nullable
                    -- tenant-disabled; applies to ALL lock_tiers
      deleted_at    timestamptz nullable
                    -- soft-delete; applies ONLY to lock_tier =
                    -- 'tenant_added'
      created_at    timestamptz NOT NULL DEFAULT now()
      updated_at    timestamptz NOT NULL DEFAULT now()

The table follows the Standard RLS Pattern's six steps: tenant_id FK,
RLS enabled, the standard tenant-scoped SELECT policy, service-role-only
writes, the required grants. tenant_id is denormalized onto every row
per the convention.

### Two columns: value (canonical) and label (tenant-displayed)

Each row carries both a value and a label. The value is the platform-
canonical identifier used in code, analytics, and inter-tenant
consistency: snake_case, lowercase, stable. The label is the tenant-
displayed name shown in dropdowns, reports, and operational UI:
human-readable, free-form within tenant control.

The two columns serve different concerns. Operational tables denormalize
the value (not the label) per the FK + Snapshot integration below, so
cross-tenant queries can filter by value reliably. Tenants who customize
their UI vocabulary change the label while the value stays stable.

For tenant-added rows (lock_tier = 'tenant_added'), the value is
auto-generated by slugifying the label at row creation: "Site Inspection"
becomes "site_inspection". The slugification is deterministic, applied
once at row creation, and never re-derived; subsequent label edits do not
change the value. Uniqueness of value within (tenant_id, table) is an
application-layer invariant enforced at row creation.

### Three categories via lock_tier

The lock_tier column discriminates three categories of row, each with
different tenant edit permissions:

- platform_locked — the platform commits to this value as canonical
  across all tenants. The value is identical across every tenant's
  lookup table (per the canonical-text-value constraint below). Tenants
  cannot rename (label is locked), cannot soft-delete, but CAN disable.
  Used for platform-canonical defaults the platform's analytics and
  cross-tenant reporting rely on.
- platform_seeded — the platform provides a starting value, but the
  tenant is free to customize. The value column is locked (preserves
  cross-tenant reporting on the platform's canonical identifier), but
  the label is freely editable. Tenants can disable; soft-delete is
  not permitted. Used for platform-provided starting categories that
  tenants commonly relabel for their operational vocabulary.
- tenant_added — tenant-defined entirely. Both value (auto-slugified
  from the label at creation) and label are tenant-controlled. Tenants
  can rename, disable, and soft-delete. Used for tenant-specific
  categories the platform did not anticipate.

The three-category model captures the operational reality that some
platform defaults are canonical commitments (don't touch the label,
don't remove the row) while others are merely starting points (relabel
freely, just leave the value alone for reporting).

### Disable and soft-delete semantics

disabled_at hides a row from new-entry dropdowns and from the active
admin list view. Historical operational records that already reference
the disabled value continue to display the value normally (the FK +
Snapshot integration preserves the value at row creation time, so
historical reads do not depend on the lookup row's disabled state).
Applies to all three lock_tiers. Admin UI provides a "view disabled"
surface for tenants to re-enable disabled values.

deleted_at applies ONLY to lock_tier = 'tenant_added' rows. The
platform's commitment to platform_locked and platform_seeded rows
includes structural persistence; tenants cannot remove them from their
lookup table. The pattern uses disabled_at as the operational analog
for platform-defined rows the tenant no longer wants visible.

### Six-step convention for applying the pattern

A new tenant-editable defaults enum is introduced by following six steps,
parallel to the Standard RLS Pattern's six-step convention. Omitting any
of these is a defect.

1. **Create the lookup table** with the canonical schema shape above.
   Substitute the enum name; do not vary the column set or types.
2. **Apply the Standard RLS Pattern's six steps** to the lookup table.
   Every tenant-editable defaults lookup table is tenant-scoped and
   follows the platform's standard isolation conventions.
3. **Seed platform default values at tenant provisioning.** The tenant
   provisioning Server Action populates the new lookup table with the
   platform's canonical default values for the enum, assigning each
   row the appropriate lock_tier (platform_locked or platform_seeded
   per the platform's intent). No retrospective propagation to
   existing tenants is performed.
4. **Add operational table's FK + Snapshot columns.** The operational
   table (the entity that references this enum) gains both a FK
   column to the lookup table and a denormalized value snapshot
   column, following the FK + Snapshot integration convention below.
5. **Wire all operational writes through the canonical validation
   helper.** Server Actions that insert or update the operational
   table validate the FK reference through a single canonical helper
   (validateTenantEditableDefaultsReference or equivalent named
   convention), not through ad-hoc per-Server-Action checks. The
   helper's existence is the load-bearing condition for future
   migration to trigger-based enforcement (below).
6. **Document the pattern application in the operational entity's
   section.** Name the lookup table, its lock_tier defaults, and
   any application-specific notes in the entity's section that uses
   it. Cross-reference this pattern section for the mechanics.

### Operational table integration via FK + Snapshot

Operational tables that reference a tenant-editable defaults enum
follow a specific shape combining two Tier 1 patterns: FK to the
lookup table plus a denormalized value snapshot. The canonical example
is inspections (Decision 17 Part B):

    inspections
      ...
      inspection_type_id      uuid NOT NULL FK -> inspection_types(id)
      inspection_type_value   text NOT NULL
                              -- snapshot of inspection_types.value
                              -- captured at row creation per the
                              -- FK + Snapshot Pattern's convention
      ...

The FK provides database-enforced referential integrity to the
lookup table. The snapshot column preserves the value at row creation,
the same defensibility logic as the FK + Snapshot Pattern's existing
applications (project's customer, registration's assignee,
notice_of_defect's recipient).

The sync invariant — inspection_type_value matches the referenced
inspection_types.value at row creation — is enforced at the
application layer through the canonical validation helper. The
snapshot is never updated on read and never re-synced when the
underlying lookup row changes; the FK can drift if the label is
later edited, but the snapshot cannot.

The pair (id + value) means cross-tenant analytics queries filter on
the value column directly without joining to the per-tenant lookup
table; per-tenant operational queries reading the current label join
through the FK; historical operational queries reading the value as
it was at row creation use the snapshot.

### Platform seeds at provisioning; tenants own forever after

The platform's relationship to a tenant's lookup table is bounded.
At tenant provisioning, the platform's seeding logic populates the
lookup table with canonical default values and lock_tier assignments.
After provisioning, the tenant owns their lookup tables completely.

The platform has no propagation mechanism for default value changes.
If the platform later decides to add a fifth canonical
inspection_type value, existing tenants do not automatically receive
it. Tenants who want to adopt the new platform default add it as a
tenant_added row themselves, or operations performs a one-off bulk
update with explicit per-tenant consent. There is no automatic
platform-to-tenant data flow after provisioning.

This bounded relationship is deliberate. Multi-tenant SaaS
architectures that propagate platform changes into tenant data create
ongoing reconciliation surface (tenant edits versus platform updates,
conflict resolution rules, migration semantics) that scale poorly
with the number of tenants and the rate of platform changes. The
pattern's seeded-and-owned model avoids this entirely: the platform
ships defaults; tenants take it from there.

### Defense-in-Depth and migration-readiness to triggers

At v1 launch the pattern uses application-layer validation in Server
Actions plus minimal DB CHECK constraints (lock_tier value set,
NOT NULL columns, FK referential integrity). PostgreSQL triggers
enforcing the canonical validation rule are NOT introduced at v1.

The decision to defer trigger enforcement is balanced against five
architectural commitments that keep the future migration mechanical:

1. **Single canonical validation function.** All tenant-editable
   defaults FK validation lives in one application-layer helper,
   not duplicated across Server Actions.
2. **Single canonical validation rule.** The rule is uniform: the
   referenced row exists, its tenant_id matches the operational
   row's tenant, disabled_at IS NULL, deleted_at IS NULL, and the
   lock_tier permits the operation being performed.
3. **Schema design supports trigger mode natively.** The lookup
   table's column shape and the operational table's FK + snapshot
   shape are their final shapes from v1. No schema migrations
   accompany the future trigger introduction.
4. **Test infrastructure tests the validation rule consistently.**
   Every application of the pattern exercises the same validation
   helper through the same test patterns.
5. **Operational logging surfaces validation failures consistently.**
   Failures emit a uniform log shape that operators recognize across
   all pattern applications.

The future migration from application-layer to trigger enforcement is
a pure DB-layer change: a trigger function is added whose logic
mirrors the canonical validation helper. No application code changes,
no schema changes, no data migration. The five commitments above are
what make this true; violating any of them turns the future migration
into a multi-system project.

### Feature flag interaction

Lookup tables are always present in the schema across all tenants,
regardless of any feature flag state. Admin UI visibility for a
feature-gated capability's lookup tables is gated by the feature
flag; the data is always present, only the UI surface is conditionally
visible. Feature flag enable and disable are pure flag operations
with no schema migrations.

This convention applies to feature-gated capabilities like Reserve
Forecasting, whose calculation parameter lookup tables exist for all
tenants but are only visible in admin UI to tenants entitled to the
capability. The pattern decouples data presence from UI gating; the
Feature Flag System (Phase 0 Item 18) governs UI gating without
touching the underlying lookup tables.

### Mixed-pattern entities: role-based decision tree

When an entity has multiple enum-like columns, each column's pattern
assignment is determined by the column's operational role, not by a
uniform-across-the-entity choice. The first canonical example is the
inspections table (per Decision 17 Part B), which has five enum-like
columns spanning three patterns:

- performed_by — platform-locked CHECK enum (Structural axis)
- paid_by — platform-locked CHECK enum (Structural axis)
- inspection_type — Tenant-Editable Defaults (Categorization)
- inspection_trigger — Tenant-Editable Defaults (Categorization)
- inspection_status — platform-locked CHECK enum (Workflow-driver)

The role-based decision tree, applied per column:

1. **Workflow-driver** — platform code branches on the value to
   drive state machine behavior, gate transitions, or trigger
   conditional logic. Use platform-locked CHECK enum. Tenant
   additions would create unknown states code does not handle.
2. **Structural axis** — values are universal across all warrantor
   business models and drive cost recovery routing, authority
   checks, or other architectural behavior. Use platform-locked
   CHECK enum.
3. **Categorization** — values legitimately vary by tenant business
   and operational vocabulary. Use Tenant-Editable Defaults
   Pattern.
4. **Ambiguous** — when a column's role is not clearly one of the
   above three, default to platform-locked CHECK enum. Document
   the intent to promote to Tenant-Editable Defaults if operational
   pressure surfaces.

Rule 4 is driven by asymmetric migration cost. Platform-locked to
tenant-editable is a forward migration: add the lookup table,
populate canonical defaults per tenant, swap the operational
column's type to the FK + Snapshot shape, port code. Feasible if
done carefully. Tenant-editable to platform-locked is a breaking
change: remove tenant-added values, reconcile with operational
data referencing them, possibly migrate tenants away from custom
categories. Lean conservative; promote later as need is
demonstrated.

### Three documented constraints

Three constraints apply to the pattern's operational reality:

**Canonical-text-value design constraint for platform-locked
defaults.** Platform-locked default values seeded into per-tenant
lookup tables MUST use the same canonical value string across all
tenants. Per-tenant rows for the same platform-locked default have
identical value column content; only id and tenant_id differ.
Platform-wide analytics queries filter by value, not by id. Tenant-
added rows have tenant-specific value strings and naturally fall
outside cross-tenant analytics queries by design. Violating the
canonical-text-value constraint breaks cross-tenant reporting on
the platform's own canonical categories.

**Schema introspection overhead for mixed-pattern entities is
real.** Operators using generic database tooling face an ergonomic
cost on mixed-pattern entities: inspection_status reads
immediately as 'open' but inspection_type_id reads as a UUID that
requires joining inspection_types to interpret. The denormalized
value snapshot (inspection_type_value) mitigates this for the
common case but does not eliminate it for ad-hoc queries that
read only the FK column. Future engineers adding tenant-editable
columns to existing or new entities should weigh this cost
deliberately; the mixed pattern is operationally fine but each
addition incurs incremental introspection overhead.

**TypeScript exhaustiveness asymmetry reinforces role separation.**
Platform-locked CHECK enums give application code a TypeScript
union type ('open' | 'in_progress' | 'under_review' | 'issued')
that enables exhaustive switch checking and narrow inference.
Tenant-editable defaults expose a UUID at the application layer;
the value string is data, not part of the type system. Code that
branches on tenant-editable defaults values is by construction
non-exhaustive — and is also, by the role-based decision tree,
the wrong shape of code to write. Workflow logic branches on
platform-locked enums; categorization data flows through
application logic without branching. The asymmetry reinforces the
intended separation: platform-locked values are code-relevant,
tenant-editable values are data-relevant.

### Canonical uses

The pattern's canonical uses establish reference examples for
future applications:

- **Inspections (Decision 17 Part B).** Two lookup tables —
  inspection_types (four platform_locked defaults: Warranty,
  Condition Assessment, Remediation Verification, Failure
  Investigation) and inspection_triggers (eight platform_locked
  defaults: Warranty Claim, Customer Request, Repeat Condition
  Verification, Post-Remediation Verification, Failure
  Investigation, Preventative / Condition Assessment, Internal
  Review, Third Party). The inspections table is the first v2
  entity with mixed enum-handling patterns and is the reference
  example for the role-based decision tree.
- **Reserve Forecasting calculation parameters (future
  capability, scope note in decisions log).** Calculation tunables
  (statistical buffer multiplier, admin/overhead loading factor
  percentage, aggregation rules) use the pattern. The lookup
  tables are always present per the feature flag interaction
  above; admin UI visibility is gated by the Reserve Forecasting
  entitlement.

The Inspections application is being drafted in this session
following this pattern's commit. The Reserve Forecasting
application is deferred to a future Decision session when that
capability is taken up.

### Outstanding architectural questions

Flagged for downstream / Phase 3 implementation:

- **Performance characteristics of canonical validation helper at
  scale.** The helper performs a SELECT per validated reference
  on every operational write. At anticipated warranty inspection
  volume this is negligible; at higher volumes it may warrant
  caching or other optimization. Profile and optimize if
  performance becomes a concern. Not anticipated as a v1 concern.
- **Bulk operations on tenant-editable defaults.** A tenant
  reconfiguring lookup tables (mass-disabling categories,
  bulk-adding rows from an external source) may need batch
  Server Action support. Phase 3 implementation detail.
- **Sub-flavors of platform-locked defaults.** Tenants can add
  related-but-distinct tenant_added rows alongside platform_locked
  defaults (e.g., a tenant_added "Warranty - Manufacturer-Specific"
  alongside the platform_locked "Warranty" inspection_type). UI
  design for surfacing this relationship in admin and operational
  dropdowns is a Phase 3 UI design question.

### What is NOT in the pattern

Parallel to the deliberate-omissions lists elsewhere in v2:

- **No platform-to-tenant propagation after provisioning.** Per
  the seeded-and-owned model, platform updates to canonical
  defaults do not flow into existing tenants' lookup tables.
  Tenants adopt new platform defaults on their own terms or
  operations performs explicit per-tenant updates.
- **No polymorphic single lookup table with enum_kind
  discriminator.** The pattern uses per-enum lookup tables, not a
  single table with a discriminator column. Per-enum tables match
  v2's type discipline and parallel the internal_teams convention
  (Decision 13).
- **No PostgreSQL trigger enforcement at v1.** Defense-in-Depth
  uses application-layer validation through the canonical helper.
  Migration to trigger enforcement is preserved as mechanical
  through the five commitments above.
- **No automatic value generation for non-tenant-added rows.**
  Platform-locked and platform-seeded rows have their value
  column content authored by the platform; only tenant_added
  rows get auto-slugified values.
- **No cross-tenant lookup data sharing.** Each tenant's lookup
  rows are scoped to that tenant via tenant_id and RLS. The
  platform-locked rows share canonical value strings across
  tenants (per the canonical-text-value constraint), but the
  rows themselves are independent per tenant.
- **No participation in the Custom Field System.** Tenant-Editable
  Defaults and Custom Field System solve different problems:
  Custom Field System lets tenants add arbitrary tenant-defined
  fields to entities; Tenant-Editable Defaults lets tenants
  customize the values of platform-defined enum-like columns.
  The two patterns are independent.
