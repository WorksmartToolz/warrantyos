-- 005_contacts.sql
-- Unified Contacts Directory (Phase 0 Item 16, locked by Decision 1; Decision 20
-- added om_provider types and the linked_om_provider_id / parent_contact_id
-- agency-traversal columns).
--
-- Per-tenant directory of non-user parties (customers, subcontractors, vendors,
-- O&M providers, and their individual contacts, plus registration assignees).
-- Tenant users (public.users) are deliberately NOT contacts.
--
-- Follows the Standard RLS Pattern's six steps: tenant_id FK, RLS enabled,
-- tenant-scoped SELECT policy, service-role-only writes, required grants.
--
-- DEFERRED FK (blocked on design, NOT deferred by choice):
--   imported_via_batch_id references import_batches(id). The import_batches
--   table belongs to the data-migration subsystem (Decision 8), whose MVP
--   scope is an OPEN architectural question (Phase 1 audit open item). The
--   column exists now so import provenance is accommodated from the start
--   (per the architecture's Import Tracking note); the FK CONSTRAINT is added
--   in a later migration once import_batches is designed and built.
--
-- APPLICATION-LAYER INVARIANTS (per architecture; NOT DB constraints because
-- they are cross-row and the architecture specifies them as app-layer):
--   * When contact_type ends in '_contact', parent_contact_id MUST be non-null
--     and the referenced row's contact_type MUST be the matching org-level type
--     (e.g. om_provider_contact -> parent contact_type = 'om_provider').
--   * When linked_om_provider_id is non-null, the referenced row's contact_type
--     MUST be 'om_provider'.
--   * contact_type is effectively immutable per row (role change => new row).
--   These are enforced in the Server Action layer, not the database.

create table public.contacts (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references public.tenants(id),

  contact_type          text not null,
  -- 10 locked categories (Decision 1 + Decision 20 added the om_provider pair):
  --   customer, customer_contact, subcontractor, subcontractor_contact,
  --   vendor, vendor_contact, om_provider, om_provider_contact,
  --   registration_assignee, other

  name                  text not null,
  email                 text,
  phone                 text,

  parent_contact_id     uuid references public.contacts(id),
  -- self-referential; non-null only for individual-contact ('_contact') rows,
  -- pointing to their parent organization row. App-layer invariant above.

  linked_om_provider_id uuid references public.contacts(id),
  -- self-referential; on customer rows, the currently-engaged O&M provider.
  -- App-layer invariant above. Current-state only; history via FK+Snapshot
  -- on operational tables.

  imported_via_batch_id uuid,
  -- FK to import_batches DEFERRED (see header). Column present for provenance.

  deleted_at            timestamptz,
  -- soft-delete discriminator; non-null means the contact is retired.

  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),

  constraint contacts_contact_type_check check (
    contact_type in (
      'customer',
      'customer_contact',
      'subcontractor',
      'subcontractor_contact',
      'vendor',
      'vendor_contact',
      'om_provider',
      'om_provider_contact',
      'registration_assignee',
      'other'
    )
  )
);

-- Standard RLS Pattern -------------------------------------------------------

-- Step 2: enable RLS
alter table public.contacts enable row level security;

-- Step 3: tenant-scoped SELECT policy
create policy "contacts: members can view their tenant's rows"
  on public.contacts
  for select
  using (tenant_id = public.get_user_tenant_id());

-- Step 4: writes are service-role only (no user-facing INSERT/UPDATE/DELETE
--         policies). All mutations go through Server Actions using the admin
--         client. No self-service exception applies to contacts.

-- Step 5: grants (required for PostgREST schema cache visibility)
grant all on public.contacts to anon, authenticated, service_role;

-- Helpful indexes for tenant-scoped reads and the self-referential traversals.
create index contacts_tenant_id_idx on public.contacts (tenant_id);
create index contacts_parent_contact_id_idx on public.contacts (parent_contact_id);
create index contacts_linked_om_provider_id_idx on public.contacts (linked_om_provider_id);
