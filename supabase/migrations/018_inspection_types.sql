-- 018_inspection_types.sql
--
-- Tenant-editable defaults lookup table: inspection types. First canonical
-- application of the Tenant-Editable Defaults Pattern (Decision 17 Part A),
-- applied to Inspections per Decision 17 Part B.
--
-- Locked sources:
--   architecture-reference.md "Tenant-Editable Defaults Pattern" ->
--     canonical lookup table schema; three-category lock_tier model;
--     disable/soft-delete semantics; six-step convention.
--   Decision 17.A.1 - per-enum lookup tables, not polymorphic-with-discriminator.
--   Decision 17.A.4 - two columns: platform-canonical value + tenant-editable label.
--   Decision 17.A.5 - three-category model via lock_tier discriminator.
--   Decision 17.A.7 - disable applies to ALL lock_tiers; soft-delete ONLY to tenant_added.
--   Decision 17.A.9 - canonical-text-value constraint for platform-locked defaults.
--   Decision 17.B.1 - the four platform_locked default values seeded below.
--
-- The column set and types are the pattern's canonical shape. Per the six-step
-- convention, an applying entity substitutes the enum name and does NOT vary
-- the column set or types. This table is that shape verbatim.
--
-- DELIBERATE OMISSIONS (documented so they are not "helpfully" added later):
--
--   * No unique index on (tenant_id, value). The architecture states it
--     explicitly: "Uniqueness of value within (tenant_id, table) is an
--     application-layer invariant enforced at row creation." This is stated,
--     not omitted. The warranty_types (011) case-insensitive unique exists to
--     protect Decision 6's anchor-type invariant and does NOT transfer here.
--
--   * No DB trigger protecting platform_locked rows from rename or delete.
--     Decision 17.A.6 is explicit: "No PostgreSQL triggers at v1." Enforcement
--     is application-layer validation plus minimal DB CHECK constraints
--     (lock_tier value set, NOT NULL columns, FK referential integrity).
--     This deliberately differs from warranty_types (011), which DOES carry a
--     protection trigger, because Decision 6 mandates defense-in-depth for
--     anchor types while Decision 17.A.6 explicitly defers triggers here.
--     Migration-readiness to trigger enforcement is preserved by the five
--     commitments in 17.A.6; the schema is in its final shape from v1, so the
--     future trigger introduction is a pure DB-layer change with no schema
--     migration.
--
--   * No DB CHECK enforcing "deleted_at only when lock_tier = 'tenant_added'"
--     (17.A.7). Same reason: 17.A.6 caps v1 DB enforcement at the lock_tier
--     value set, NOT NULLs, and FK integrity. The rule is app-layer, carried by
--     the canonical validation helper.
--
-- APP-LAYER COMPANIONS (not in this migration):
--   * Tenant provisioning Server Action seeds these four rows for every NEW
--     tenant (six-step convention, step 3). The backfill below covers tenants
--     that predate this migration only.
--   * The canonical validation helper (17.A.6, commitment 1) validates every
--     operational FK reference: row exists AND tenant_id matches AND
--     disabled_at IS NULL AND deleted_at IS NULL AND lock_tier permits.
--   * Slugification of label -> value for tenant_added rows (17.A.4), applied
--     once at row creation, never re-derived.

create table public.inspection_types (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenants(id),
                -- denormalized per Standard RLS Pattern.
  value         text not null,
                -- platform-canonical identifier; snake_case, lowercase.
                --   Tenants cannot edit for non-tenant_added rows.
                --   Identical across all tenants for platform_locked rows
                --   (Decision 17.A.9) so platform-wide analytics filter by
                --   value, not by id.
  label         text not null,
                -- tenant-displayed name; editable subject to lock_tier.
  lock_tier     text not null,
                -- three-category discriminator (Decision 17.A.5).
  sort_order    integer not null default 0,
  disabled_at   timestamptz,
                -- tenant-disabled; applies to ALL lock_tiers (17.A.7).
  deleted_at    timestamptz,
                -- soft-delete; applies ONLY to lock_tier = 'tenant_added'
                --   (17.A.7). Enforced app-layer, not by CHECK, per 17.A.6.
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  constraint inspection_types_lock_tier_check check (
    lock_tier in ('platform_locked', 'platform_seeded', 'tenant_added')
  )
);

create index inspection_types_tenant_id_idx
  on public.inspection_types (tenant_id);

comment on table public.inspection_types is
  'Tenant-editable defaults lookup table for inspection types. First canonical '
  'application of the Tenant-Editable Defaults Pattern (Decision 17 Part A). '
  'Four platform_locked defaults seeded per tenant (Decision 17.B.1); tenants '
  'may add tenant_added rows, and may disable but not rename or soft-delete the '
  'platform_locked defaults. The inspections table references this via '
  'inspection_type_id (FK) + inspection_type_value (snapshot) per 17.A.2.';

comment on column public.inspection_types.value is
  'Platform-canonical identifier: snake_case, lowercase, stable. Identical '
  'across all tenants for platform_locked rows (Decision 17.A.9) so cross-tenant '
  'analytics filter by value rather than id. Locked for platform_locked and '
  'platform_seeded rows; auto-slugified from label at creation for tenant_added '
  'rows. Uniqueness within (tenant_id) is an application-layer invariant.';

comment on column public.inspection_types.label is
  'Tenant-displayed name shown in dropdowns, reports, and operational UI. '
  'Editable for platform_seeded and tenant_added rows; locked for '
  'platform_locked rows. Label edits never re-derive value.';

comment on column public.inspection_types.lock_tier is
  'Three-category discriminator (Decision 17.A.5). platform_locked: platform '
  'commits to the value as canonical; tenants cannot rename or soft-delete, but '
  'CAN disable. platform_seeded: starting point; tenants can rename and disable, '
  'cannot soft-delete. tenant_added: full tenant control. Edit permissions are '
  'enforced app-layer per 17.A.6; the CHECK constrains the value set only.';

comment on column public.inspection_types.disabled_at is
  'Tenant-disabled. Hides the row from new-entry dropdowns and the active admin '
  'list view; historical operational records referencing the value continue to '
  'display normally (the FK + Snapshot integration preserves the value at row '
  'creation). Applies to ALL lock_tiers including platform_locked (17.A.7).';

comment on column public.inspection_types.deleted_at is
  'Soft-delete. Applies ONLY to lock_tier = tenant_added rows (17.A.7); the '
  'platform commits to structural persistence of platform_locked and '
  'platform_seeded rows. disabled_at is the operational analog for those. '
  'Enforced app-layer, not by DB CHECK, per 17.A.6.';

-- ---------------------------------------------------------------------------
-- Standard RLS Pattern (6-step)
-- ---------------------------------------------------------------------------
alter table public.inspection_types enable row level security;

create policy "inspection_types: members can view their tenant's rows"
  on public.inspection_types
  for select
  using (tenant_id = public.get_user_tenant_id());

-- Writes are service-role only: Team Admins manage the lookup list via Server
-- Actions; Reviewers and Viewers consume it.

grant all on public.inspection_types to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Backfill: seed the four platform_locked defaults (Decision 17.B.1) for every
-- tenant that exists today, matching what provisioning will seed for new
-- tenants. Precedent: tenant_id_sequences (009) and warranty_types (011) both
-- backfill existing tenants in-migration and leave new-tenant seeding to the
-- app-layer provisioning Server Action.
--
-- This is a one-time bootstrap for tenants that predate the table, NOT the
-- propagation mechanism 17.A.3 forbids. 17.A.3 bars ongoing platform-to-tenant
-- data flow AFTER provisioning -- e.g. pushing a future fifth canonical default
-- into existing tenants. That remains forbidden. Without this bootstrap,
-- existing tenants would hold zero rows and could not create an inspection at
-- all, since inspections.inspection_type_id is NOT NULL.
--
-- Idempotent via WHERE NOT EXISTS rather than ON CONFLICT: there is no unique
-- index on (tenant_id, value) to serve as a conflict arbiter, and adding one
-- would contradict the architecture's explicit assignment of value-uniqueness
-- to the application layer. The guard achieves 011's idempotency without
-- altering the locked decision.
-- ---------------------------------------------------------------------------
insert into public.inspection_types (tenant_id, value, label, lock_tier, sort_order)
select t.id, 'warranty', 'Warranty', 'platform_locked', 1
from public.tenants t
where not exists (
  select 1 from public.inspection_types x
  where x.tenant_id = t.id and x.value = 'warranty'
);

insert into public.inspection_types (tenant_id, value, label, lock_tier, sort_order)
select t.id, 'condition_assessment', 'Condition Assessment', 'platform_locked', 2
from public.tenants t
where not exists (
  select 1 from public.inspection_types x
  where x.tenant_id = t.id and x.value = 'condition_assessment'
);

insert into public.inspection_types (tenant_id, value, label, lock_tier, sort_order)
select t.id, 'remediation_verification', 'Remediation Verification', 'platform_locked', 3
from public.tenants t
where not exists (
  select 1 from public.inspection_types x
  where x.tenant_id = t.id and x.value = 'remediation_verification'
);

insert into public.inspection_types (tenant_id, value, label, lock_tier, sort_order)
select t.id, 'failure_investigation', 'Failure Investigation', 'platform_locked', 4
from public.tenants t
where not exists (
  select 1 from public.inspection_types x
  where x.tenant_id = t.id and x.value = 'failure_investigation'
);
