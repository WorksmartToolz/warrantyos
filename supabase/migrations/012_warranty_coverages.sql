-- 012_warranty_coverages.sql
--
-- A coverage is one warranty type's instantiation on one registration. A
-- registration has one coverages row per warranty type it covers (Standard,
-- Workmanship, Racking, ...), each with its own start_date snapshot and term.
--
-- Locked sources:
--   architecture-reference.md "Warranty Type Coverages" -> warranty_coverages.
--   Decision 23.5  - start_date is an immutable snapshot of trigger_date at
--                    coverage creation; effective start derived via COALESCE.
--   Decision 24    - end_date is derived (not stored) via the
--                    warranty_coverages_effective VIEW; security_invoker = true
--                    is REQUIRED (24.5); view GRANTs required.
--
-- App-layer invariants (documented, NOT DB-enforced):
--   * tenant_id must match the referenced registration's tenant_id.
--   * start_date is set from projects.trigger_date at creation and is an
--     immutable snapshot thereafter (Server Action never updates it - 23.5).
--   * All effective start/end reads MUST go through warranty_coverages_effective
--     (24.3); reading start_date + term_years directly for effective values is
--     architecturally prohibited (reproduces the 23.5a corruption mode).

create table public.warranty_coverages (
  id                          uuid primary key default gen_random_uuid(),

  tenant_id                   uuid not null references public.tenants(id),
                              -- denormalized per Standard RLS Pattern.
                              -- App-layer invariant: equals the referenced
                              --   registration's tenant_id.

  warranty_registration_id    uuid not null
                                references public.warranty_registrations(id),
  warranty_type_id            uuid not null
                                references public.warranty_types(id),

  start_date                  date not null,
                              -- immutable snapshot of the parent project's
                              --   trigger_date at coverage creation (Decision
                              --   23.5). Effective start is derived via COALESCE
                              --   with the registration's actual_start_date - use
                              --   the warranty_coverages_effective view, never
                              --   this column directly for effective values.

  term_years                  integer not null,

  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now(),

  -- Defensive constraint (arch ref: "a CHECK > 0 is the obvious defensive
  -- constraint"). Confirmed for inclusion.
  constraint warranty_coverages_term_years_check check (term_years > 0),

  -- One coverage per (registration, type) pair - the locked architectural
  -- intent (arch ref); enforced here at the DB layer.
  constraint warranty_coverages_registration_type_unique
    unique (warranty_registration_id, warranty_type_id)
);

comment on table public.warranty_coverages is
  'One warranty type instantiated on one registration. start_date is an '
  'immutable trigger_date snapshot (Decision 23.5); end_date is NOT stored - '
  'read effective start/end from warranty_coverages_effective (Decision 24). '
  'One row per (registration, type).';

comment on column public.warranty_coverages.start_date is
  'Immutable snapshot of projects.trigger_date at coverage creation (Decision '
  '23.5). Never read directly for effective-start purposes - use '
  'warranty_coverages_effective.effective_start_date (Decisions 23.5a/24.3).';

-- ---------------------------------------------------------------------------
-- Standard RLS Pattern (6-step) on the base table
-- ---------------------------------------------------------------------------
alter table public.warranty_coverages enable row level security;

create policy "warranty_coverages: members can view their tenant's rows"
  on public.warranty_coverages
  for select
  using (tenant_id = public.get_user_tenant_id());

-- Writes are service-role only: the assignee configures coverages during the
-- prep window via Server Actions (Decision 23.6).

grant all on public.warranty_coverages to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Effective-timing view (Decision 24.2). The single canonical read surface for
-- effective_start_date and effective_end_date. Base table exposes start_date +
-- term_years only for snapshot/inspection; all effective reads use this view.
--
-- security_invoker = true (Decision 24.5) is REQUIRED and non-optional: it makes
-- the view execute with the querying user's privileges so RLS on the underlying
-- warranty_coverages and warranty_registrations tables is respected. Without it,
-- the view would bypass RLS and leak across tenants.
-- ---------------------------------------------------------------------------
create view public.warranty_coverages_effective
  with (security_invoker = true)
  as
  select
    c.id,
    c.tenant_id,
    c.warranty_registration_id,
    c.warranty_type_id,
    c.start_date,
    c.term_years,
    coalesce(r.actual_start_date, c.start_date)
      as effective_start_date,
    (coalesce(r.actual_start_date, c.start_date)
      + (c.term_years || ' years')::interval)::date
      as effective_end_date
  from public.warranty_coverages c
  join public.warranty_registrations r
    on r.id = c.warranty_registration_id;

comment on view public.warranty_coverages_effective is
  'Canonical read surface for coverage effective_start_date and '
  'effective_end_date (Decision 24). COALESCE(registration.actual_start_date, '
  'coverage.start_date) for start; start + term_years for end. '
  'security_invoker=true so underlying-table RLS is enforced (24.5). All '
  'effective start/end reads MUST use this view (24.3).';

-- View GRANTs (Decision 24.5): missing grants on the view produce the same
-- PostgREST-invisibility failure mode as missing grants on a table.
grant all on public.warranty_coverages_effective to anon, authenticated, service_role;
