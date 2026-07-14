-- 010_warranty_registrations.sql
--
-- Warranty Registration: the parent record for one warranty agreement on one
-- project. Carries the WarrantyID once issued, tracks the assignee responsible
-- for completing activation, and is the immediate parent of warranty coverages
-- and claims.
--
-- Locked sources:
--   architecture-reference.md "Warranty Registration" section (schema block).
--   Decision 1  - dual-FK assignee model (contact OR tenant user).
--   Decision 5  - FK direction and 1:1 enforcement (UNIQUE project_id).
--   Decision 23 - actual_start_date (23.4), four-state status machine (23.7),
--                 no data backfill required.
--   Decision 2 / 27 - WarrantyID issuance via tenant_id_sequences (app-layer;
--                 warranty_id is nullable here, immutable once set).
--
-- App-layer invariants (documented, NOT DB-enforced, per project convention on
-- cross-row invariants):
--   * tenant_id must match the referenced project's tenant_id.
--   * warranty_id is immutable once set (enforced in the Server Action).
--   * status state-machine transitions (23.7) are enforced in the Server Action.
--
-- No data backfill: existing rows (none yet) would take NULL actual_start_date,
-- the correct initial state (Decision 23, "No data backfill required").

create table public.warranty_registrations (
  id                          uuid primary key default gen_random_uuid(),

  tenant_id                   uuid not null references public.tenants(id),
                              -- denormalized per Standard RLS Pattern.
                              -- App-layer invariant: must equal the referenced
                              --   project's tenant_id.

  project_id                  uuid not null unique
                                references public.projects(id) on delete restrict,
                              -- UNIQUE enforces the 1:1 with project (Decision 5).
                              -- ON DELETE RESTRICT: a project with a registration
                              --   cannot be hard-deleted; cleanup is soft-delete.

  warranty_id                 text,
                              -- issued no later than effective_start_date via
                              --   tenant_id_sequences (Decisions 2/27); null
                              --   until issued; immutable once set (app-layer).

  status                      text not null,
                              -- Four-value closed set (Decision 23.7):
                              --   'pre_activation', 'assigned', 'active',
                              --   'rejected'. CHECK below enforces the values;
                              --   transitions are enforced app-layer.

  assigned_to_contact_id      uuid references public.contacts(id),
  assigned_to_user_id         uuid references public.users(id),
                              -- Dual-FK assignee (Decision 1): exactly one
                              --   non-null when assigned; both null only in the
                              --   pre_activation edge state. CHECK below.

  assigned_to_name_snapshot   text,
  assigned_to_email_snapshot  text,
  assigned_to_phone_snapshot  text,
                              -- FK + Snapshot Pattern: assignee contact details
                              --   captured at assignment time.

  assigned_at                 timestamptz,
  activated_at                timestamptz,
                              -- set when status transitions to 'active'.

  actual_start_date           date,
                              -- warrantor-confirmed operational start (Decision
                              --   23.4). Null until confirmed; no default. May be
                              --   before, at, or after trigger_date (23.4a: no
                              --   temporal constraint).

  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now(),

  constraint warranty_registrations_status_check
    check (status in ('pre_activation', 'assigned', 'active', 'rejected')),

  -- Dual-FK assignee invariant (architecture-reference.md: "exactly one
  -- non-null when assigned; both null when unassigned"). Encoded conditional
  -- on status: pre_activation may be unassigned (both null); the other three
  -- states require exactly one assignee FK (XOR).
  constraint warranty_registrations_assignee_check check (
    (status = 'pre_activation'
       and assigned_to_contact_id is null
       and assigned_to_user_id is null)
    or
    (status in ('assigned', 'active', 'rejected')
       and (assigned_to_contact_id is not null) <> (assigned_to_user_id is not null))
  )
);

comment on table public.warranty_registrations is
  'Parent record for one warranty agreement on one project (1:1 with projects, '
  'enforced by UNIQUE project_id). Carries WarrantyID once issued, tracks the '
  'assignee, parents coverages and claims. Decisions 1/5/23; '
  'architecture-reference.md Warranty Registration section.';

comment on column public.warranty_registrations.warranty_id is
  'Business-visible WarrantyID. Issued via tenant_id_sequences no later than '
  'effective_start_date (Decisions 2/27). Null until issued; immutable once set '
  '(app-layer enforcement).';

comment on column public.warranty_registrations.status is
  'Four-state machine (Decision 23.7): pre_activation (edge fallback), assigned '
  '(prep), active (Section 7 passed, WarrantyID issued), rejected (Section 7 '
  'rejected, loops back to assigned). Transitions enforced app-layer.';

comment on column public.warranty_registrations.actual_start_date is
  'Warrantor-confirmed operational start date (Decision 23.4). Null until '
  'confirmed. Effective start is COALESCE(actual_start_date, coverage/trigger '
  'date) derived at query time (23.5/23.9) - never read this or trigger_date '
  'directly for effective-start purposes (23.5a application invariant).';

-- ---------------------------------------------------------------------------
-- Standard RLS Pattern (6-step)
-- ---------------------------------------------------------------------------
alter table public.warranty_registrations enable row level security;

create policy "warranty_registrations: members can view their tenant's rows"
  on public.warranty_registrations
  for select
  using (tenant_id = public.get_user_tenant_id());

-- Writes are service-role only: no user-facing INSERT/UPDATE/DELETE policy.
-- Registration creation (clock-event dispatcher), assignment, WarrantyID
-- issuance, and status transitions are all performed by Server Actions.

grant all on public.warranty_registrations to anon, authenticated, service_role;
