-- 015_custom_field_definitions.sql
-- custom_field_definitions: lets a Tenant Team Admin declare extra fields on
-- certain entities without a schema change. Locked by Decision 3 (Phase 2
-- decisions log); the rich_text field type's storage format is locked by
-- Decision 4 (TipTap / ProseMirror-compatible JSON).
--
-- A definition declares a field: which entity type it attaches to, its label,
-- its type, whether it is required, dropdown options if applicable, and display
-- order. Team Admins create and manage definitions; Reviewers and Viewers
-- consume them (filling values on entity records, reading them back).
--
-- SCOPE OF THIS MIGRATION: definitions only. Decision 3's companion table
-- custom_field_values is NOT built here -- it carries a required
-- claim_id FK -> claims, and claims does not yet exist. Its three-way
-- exactly-one-non-null CHECK cannot be built until all three FK targets exist
-- (projects/006 and warranty_registrations/010 do; claims does not). This is a
-- real dependency boundary, not a deferral by choice: no deferred FK is being
-- introduced. custom_field_values lands with or after the claims shell.
--
-- PHASE 1 ENTITY SCOPE: exactly three entities -- projects, warranty
-- registrations, claims. Each has a concrete MVP need: data migration requires
-- project-level custom fields for import column mapping; claim intake requires
-- them for the six-workbook variance; registrations need them for
-- tenant-specific Section 7 capture. Deliberate exclusions (Decision 3):
-- contacts (fixed shape), inspections (customize via inspection_report JSONB),
-- warranty type coverages (tightly scoped to start/end/term), ALA documents /
-- work plans / costs (no base schema yet), communications (template-driven),
-- audit trail entries (tenant customization would muddy the audit).
--
-- SOFT-DELETE ON DEFINITIONS: definitions are never hard-deleted through the
-- UI. When soft-deleted (deleted_at IS NOT NULL): existing values remain
-- queryable for historical display and reporting; the definition-list UI
-- filters it out; new entity edit forms stop rendering its input. Existing
-- values do not migrate or detach -- they stay attached to the now-hidden
-- definition. Aligns with the Defensibility principle (historical values stay
-- queryable) and the Soft Remove principle. Hard-delete would orphan
-- historical values or cascade-destroy auditable data; admin tooling only, if
-- ever genuinely needed.
--
-- APP-LAYER INVARIANTS (documented, deliberately NOT DB constraints):
--   - options is populated for field_type = 'dropdown' and null otherwise.
--     Decision 3 states this descriptively ("dropdown options, null
--     otherwise"); it is validated at write time, not by a CHECK.
--   - value type-safety per field_type is enforced when custom_field_values
--     rows are written (that table's concern, not this one's).
--   - updated_at is maintained by the writing Server Action (matches the
--     006/010/014 precedent: default now(), no trigger).
create table public.custom_field_definitions (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.tenants(id),
  entity_type    text not null,
  -- 'project' | 'warranty_registration' | 'claim'
  label          text not null,
  field_type     text not null,
  -- The 11 Phase 1 types. Signature, multi-select, and currency are Phase 2
  -- and are deliberately absent; extensible via migration when they land
  -- (the established pattern -- cf. Decision 13.2).
  required       boolean not null default false,
  options        jsonb,
  -- dropdown options; null otherwise (app-layer, see above)
  display_order  integer not null default 0,
  deleted_at     timestamptz,
  -- soft-delete discriminator; see SOFT-DELETE note above
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),

  constraint custom_field_definitions_entity_type_check check (entity_type in (
    'project',
    'warranty_registration',
    'claim'
  )),
  constraint custom_field_definitions_field_type_check check (field_type in (
    'address',
    'phone',
    'date',
    'number',
    'plain_text',
    'rich_text',
    'dropdown',
    'email',
    'url',
    'checkbox',
    'file_upload'
  ))
);

-- Standard RLS Pattern -------------------------------------------------------
-- Step 2: enable RLS
alter table public.custom_field_definitions enable row level security;
-- Step 3: tenant-scoped SELECT policy
create policy "custom_field_definitions: members can view their tenant's rows"
  on public.custom_field_definitions
  for select
  using (tenant_id = public.get_user_tenant_id());
-- Step 4: writes are service-role only. No user-facing INSERT/UPDATE/DELETE
--         policies; definition management is a Team Admin capability exercised
--         through Server Actions.
-- Step 5: grants (required for PostgREST schema cache visibility)
grant all on public.custom_field_definitions to anon, authenticated, service_role;
-- Step 6: index
create index custom_field_definitions_tenant_id_idx
  on public.custom_field_definitions (tenant_id);
