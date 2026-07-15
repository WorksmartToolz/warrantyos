-- 014_internal_teams.sql
-- internal_teams: a tenant-defined registry of the internal teams a warrantor
-- uses for warranty work. Locked by Decision 13 (13.3, 13.4, 13.5).
--
-- The platform commits to the OPERATIONAL PATTERN (each tenant may define
-- multiple internal teams used for warranty work) without enshrining specific
-- team labels. Terrasmart uses "Warranty FOS" and "Construction Support";
-- other warrantors define their own naming. The two-team or n-team pattern
-- (primary internal team, one or more fallback teams) is universal across
-- warrantors industry-wide -- but the labels are tenant data, NOT platform
-- enum values (Decision 13.4).
--
-- Referenced by work_plans.internal_team_id when execution_path =
-- 'warrantor_self_performs' (Decision 13.1). work_plans is not yet built; that
-- FK lands with the work_plans migration, not here.
--
-- DELIBERATE OMISSIONS (per Decision 13 -- do not "helpfully" add these later):
--   - NO is_primary / default-team flag. Decision 13.5 is explicit: a
--     primary-vs-fallback distinction is NOT architecturally tracked at the
--     team level. UI default-selection behavior belongs in tenants.settings if
--     needed. Cost-per-team queries answer through the future Cost Tracking
--     section joining work_plans to internal_teams via internal_team_id.
--   - NO unique constraint on name. Decision 13 enumerates its deferred
--     questions explicitly (ON DELETE behavior on the work_plans FK; internal
--     team membership tracking) and name uniqueness is not among them. It was
--     never contemplated, so it is not imposed here. The warranty_types (011)
--     case-insensitive unique does NOT set a precedent for this table: that
--     constraint exists to protect Decision 6's anchor-type invariant, which
--     internal_teams has no equivalent of. Uniqueness, if ever wanted, is
--     app-layer.
--   - NO team membership columns. Whether internal_teams should reference
--     contacts or tenant users for membership tracking is explicitly outside
--     Decision 13's scope.
--
-- SOFT-DELETE IS REQUIRED (not optional): historical work_plans retain their
-- internal_team_id FK even when teams are retired. Retirement sets deleted_at;
-- rows are never hard-deleted on the ordinary path.
--
-- APP-LAYER INVARIANTS (documented, deliberately NOT DB constraints):
--   - updated_at is maintained by the writing Server Action (matches the
--     010/006 precedent: default now(), no trigger).
--   - Active-team queries filter on deleted_at is null.
create table public.internal_teams (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references public.tenants(id),
  name         text not null,
  -- tenant's own label (e.g., "Warranty FOS", "Construction Support",
  -- "Tier 1 Service", whatever fits the warrantor's organizational structure)
  description  text,
  -- optional explanatory note
  deleted_at   timestamptz,
  -- soft-delete required; historical work_plans retain internal_team_id
  -- even when teams are retired
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- Standard RLS Pattern -------------------------------------------------------
-- Step 2: enable RLS
alter table public.internal_teams enable row level security;
-- Step 3: tenant-scoped SELECT policy
create policy "internal_teams: members can view their tenant's rows"
  on public.internal_teams
  for select
  using (tenant_id = public.get_user_tenant_id());
-- Step 4: writes are service-role only. No user-facing INSERT/UPDATE/DELETE
--         policies; team creation, editing, and retirement all go through
--         Server Actions.
-- Step 5: grants (required for PostgREST schema cache visibility)
grant all on public.internal_teams to anon, authenticated, service_role;
-- Step 6: index
create index internal_teams_tenant_id_idx on public.internal_teams (tenant_id);
