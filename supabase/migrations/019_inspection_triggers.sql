-- 019_inspection_triggers.sql
--
-- Tenant-editable defaults lookup table: inspection triggers. Second canonical
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
--   Decision 17.B.2 - the eight platform_locked default values seeded below.
--   Decision 18.2   - requires the third_party value.
--
-- Structurally identical to inspection_types (018) by design: the six-step
-- convention says an applying entity substitutes the enum name and does NOT
-- vary the column set or types. The per-enum-table shape (17.A.1) means this
-- repetition is the pattern working as specified, not duplication to factor out.
--
-- DELIBERATE OMISSIONS (documented so they are not "helpfully" added later):
--
--   * No unique index on (tenant_id, value). The architecture states it
--     explicitly: "Uniqueness of value within (tenant_id, table) is an
--     application-layer invariant enforced at row creation." Stated, not omitted.
--
--   * No DB trigger protecting platform_locked rows. Decision 17.A.6: "No
--     PostgreSQL triggers at v1." Deliberately differs from warranty_types
--     (011), whose trigger is mandated by Decision 6's defense-in-depth
--     requirement for anchor types. Different decision, different answer.
--
--   * No DB CHECK enforcing "deleted_at only when lock_tier = 'tenant_added'"
--     (17.A.7). 17.A.6 caps v1 DB enforcement at the lock_tier value set,
--     NOT NULLs, and FK integrity. The rule is app-layer.
--
-- APP-LAYER COMPANIONS (not in this migration):
--   * Tenant provisioning Server Action seeds these eight rows for every NEW
--     tenant (six-step convention, step 3). The backfill below covers tenants
--     that predate this migration only.
--   * The canonical validation helper (17.A.6, commitment 1) validates every
--     operational FK reference: row exists AND tenant_id matches AND
--     disabled_at IS NULL AND deleted_at IS NULL AND lock_tier permits.
--   * Slugification of label -> value for tenant_added rows (17.A.4).

create table public.inspection_triggers (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenants(id),
                -- denormalized per Standard RLS Pattern.
  value         text not null,
                -- platform-canonical identifier; snake_case, lowercase.
                --   Identical across all tenants for platform_locked rows
                --   (Decision 17.A.9).
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

  constraint inspection_triggers_lock_tier_check check (
    lock_tier in ('platform_locked', 'platform_seeded', 'tenant_added')
  )
);

create index inspection_triggers_tenant_id_idx
  on public.inspection_triggers (tenant_id);

comment on table public.inspection_triggers is
  'Tenant-editable defaults lookup table for inspection triggers: what caused an '
  'inspection to be performed. Second canonical application of the '
  'Tenant-Editable Defaults Pattern (Decision 17 Part A). Eight platform_locked '
  'defaults seeded per tenant (Decision 17.B.2); tenants may add tenant_added '
  'rows, and may disable but not rename or soft-delete the platform_locked '
  'defaults. The inspections table references this via inspection_trigger_id '
  '(FK) + inspection_trigger_value (snapshot) per 17.A.2.';

comment on column public.inspection_triggers.value is
  'Platform-canonical identifier: snake_case, lowercase, stable. Identical '
  'across all tenants for platform_locked rows (Decision 17.A.9) so cross-tenant '
  'analytics filter by value rather than id. Locked for platform_locked and '
  'platform_seeded rows; auto-slugified from label at creation for tenant_added '
  'rows. Uniqueness within (tenant_id) is an application-layer invariant.';

comment on column public.inspection_triggers.label is
  'Tenant-displayed name shown in dropdowns, reports, and operational UI. '
  'Editable for platform_seeded and tenant_added rows; locked for '
  'platform_locked rows. Label edits never re-derive value.';

comment on column public.inspection_triggers.lock_tier is
  'Three-category discriminator (Decision 17.A.5). platform_locked: platform '
  'commits to the value as canonical; tenants cannot rename or soft-delete, but '
  'CAN disable. platform_seeded: starting point; tenants can rename and disable, '
  'cannot soft-delete. tenant_added: full tenant control. Edit permissions are '
  'enforced app-layer per 17.A.6; the CHECK constrains the value set only.';

comment on column public.inspection_triggers.disabled_at is
  'Tenant-disabled. Hides the row from new-entry dropdowns and the active admin '
  'list view; historical operational records referencing the value continue to '
  'display normally (the FK + Snapshot integration preserves the value at row '
  'creation). Applies to ALL lock_tiers including platform_locked (17.A.7).';

comment on column public.inspection_triggers.deleted_at is
  'Soft-delete. Applies ONLY to lock_tier = tenant_added rows (17.A.7); the '
  'platform commits to structural persistence of platform_locked and '
  'platform_seeded rows. disabled_at is the operational analog for those. '
  'Enforced app-layer, not by DB CHECK, per 17.A.6.';

-- ---------------------------------------------------------------------------
-- Standard RLS Pattern (6-step)
-- ---------------------------------------------------------------------------
alter table public.inspection_triggers enable row level security;

create policy "inspection_triggers: members can view their tenant's rows"
  on public.inspection_triggers
  for select
  using (tenant_id = public.get_user_tenant_id());

-- Writes are service-role only: Team Admins manage the lookup list via Server
-- Actions; Reviewers and Viewers consume it.

grant all on public.inspection_triggers to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Backfill: seed the eight platform_locked defaults (Decision 17.B.2) for every
-- tenant that exists today, matching what provisioning will seed for new
-- tenants. Precedent: tenant_id_sequences (009), warranty_types (011),
-- inspection_types (018).
--
-- One-time bootstrap for tenants that predate the table, NOT the propagation
-- mechanism 17.A.3 forbids. 17.A.3 bars ongoing platform-to-tenant data flow
-- AFTER provisioning -- e.g. pushing a future ninth canonical default into
-- existing tenants. That remains forbidden. Without this bootstrap, existing
-- tenants would hold zero rows and could not create an inspection at all, since
-- inspections.inspection_trigger_id is NOT NULL.
--
-- Idempotent via WHERE NOT EXISTS rather than ON CONFLICT: there is no unique
-- index on (tenant_id, value) to serve as a conflict arbiter, and adding one
-- would contradict the architecture's explicit assignment of value-uniqueness
-- to the application layer.
--
-- sort_order follows Decision 17.B.2's listed order.
-- ---------------------------------------------------------------------------
insert into public.inspection_triggers (tenant_id, value, label, lock_tier, sort_order)
select t.id, 'warranty_claim', 'Warranty Claim', 'platform_locked', 1
from public.tenants t
where not exists (
  select 1 from public.inspection_triggers x
  where x.tenant_id = t.id and x.value = 'warranty_claim'
);

insert into public.inspection_triggers (tenant_id, value, label, lock_tier, sort_order)
select t.id, 'customer_request', 'Customer Request', 'platform_locked', 2
from public.tenants t
where not exists (
  select 1 from public.inspection_triggers x
  where x.tenant_id = t.id and x.value = 'customer_request'
);

insert into public.inspection_triggers (tenant_id, value, label, lock_tier, sort_order)
select t.id, 'repeat_condition_verification', 'Repeat Condition Verification', 'platform_locked', 3
from public.tenants t
where not exists (
  select 1 from public.inspection_triggers x
  where x.tenant_id = t.id and x.value = 'repeat_condition_verification'
);

insert into public.inspection_triggers (tenant_id, value, label, lock_tier, sort_order)
select t.id, 'post_remediation_verification', 'Post-Remediation Verification', 'platform_locked', 4
from public.tenants t
where not exists (
  select 1 from public.inspection_triggers x
  where x.tenant_id = t.id and x.value = 'post_remediation_verification'
);

insert into public.inspection_triggers (tenant_id, value, label, lock_tier, sort_order)
select t.id, 'failure_investigation', 'Failure Investigation', 'platform_locked', 5
from public.tenants t
where not exists (
  select 1 from public.inspection_triggers x
  where x.tenant_id = t.id and x.value = 'failure_investigation'
);

insert into public.inspection_triggers (tenant_id, value, label, lock_tier, sort_order)
select t.id, 'preventative_condition_assessment', 'Preventative / Condition Assessment', 'platform_locked', 6
from public.tenants t
where not exists (
  select 1 from public.inspection_triggers x
  where x.tenant_id = t.id and x.value = 'preventative_condition_assessment'
);

insert into public.inspection_triggers (tenant_id, value, label, lock_tier, sort_order)
select t.id, 'internal_review', 'Internal Review', 'platform_locked', 7
from public.tenants t
where not exists (
  select 1 from public.inspection_triggers x
  where x.tenant_id = t.id and x.value = 'internal_review'
);

-- The third_party value is required by Decision 18.2.
insert into public.inspection_triggers (tenant_id, value, label, lock_tier, sort_order)
select t.id, 'third_party', 'Third Party', 'platform_locked', 8
from public.tenants t
where not exists (
  select 1 from public.inspection_triggers x
  where x.tenant_id = t.id and x.value = 'third_party'
);
