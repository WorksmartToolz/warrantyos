-- 009_tenant_id_sequences.sql
--
-- Per-tenant, gap-free business identifier generation (WarrantyIDs, ClaimIDs).
--
-- Locked by Decision 2 (Phase 2 decisions log). Table shape per
-- architecture-reference.md "ID Generation" section (One table, one row per
-- (tenant, id_type)). Unamended by Decisions 11-28: Decision 27 changes WHEN
-- and by WHOM the sequence is consumed (WarrantyID early-issuance clock event),
-- not the table shape defined here.
--
-- Generation is transactional and gap-free: a Server Action that inserts a
-- warranty registration or claim locks the relevant row in the SAME
-- transaction, increments current_value, formats via format_string, and writes
-- the id onto the inserting record. Rollback rolls back the counter -> no gaps.
-- Year-rollover is UTC and atomic with the increment (CASE on current_year).
--
-- Writes are service-role only (all generation and format edits go through
-- Server Actions). Tenant members may READ their own tenant's rows so the
-- settings UI can display the configured format_string.

create table public.tenant_id_sequences (
  tenant_id      uuid not null references public.tenants(id) on delete cascade,
  id_type        text not null,
  format_string  text not null,
  current_year   integer not null,
  current_value  integer not null default 0,
  updated_at     timestamptz not null default now(),
  primary key (tenant_id, id_type),
  constraint tenant_id_sequences_id_type_check
    check (id_type in ('warranty_id', 'claim_id'))
);

comment on table public.tenant_id_sequences is
  'Per-(tenant, id_type) gap-free identifier counters. One row per id_type per '
  'tenant. Read/updated in the same transaction as the record that consumes the '
  'id, giving the gap-free guarantee. Decision 2; architecture-reference.md ID '
  'Generation section.';

comment on column public.tenant_id_sequences.format_string is
  'Python format-string syntax: {year} and {seq:NNd}. Validated at '
  'settings-save time, not generation time.';

comment on column public.tenant_id_sequences.current_year is
  'UTC year the counter is currently advancing in. On first generation of a new '
  'UTC year, the increment UPDATE resets current_value to 1 and updates this.';

-- ---------------------------------------------------------------------------
-- Standard RLS Pattern (6-step)
-- ---------------------------------------------------------------------------
alter table public.tenant_id_sequences enable row level security;

create policy "tenant_id_sequences: members can view their tenant's rows"
  on public.tenant_id_sequences
  for select
  using (tenant_id = public.get_user_tenant_id());

-- Writes are service-role only: no user-facing INSERT/UPDATE/DELETE policy.
-- Generation and format changes are performed by Server Actions.

grant all on public.tenant_id_sequences to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Backfill: existing tenants must already have their two sequence rows, because
-- generation LOCKS an existing row (the spec assumes the row exists; there is
-- no lazy-create path). Idempotent via ON CONFLICT DO NOTHING.
--
-- Ongoing seeding for tenants created AFTER this migration is an application-
-- layer concern: tenant provisioning is an admin server operation (Server
-- Action), not a DB function (see 000_baseline.sql line ~129). The provisioning
-- Server Action must insert these two rows at tenant-creation time. That hook
-- is intentionally NOT a DB trigger here, to avoid contradicting the locked
-- "provisioning is an admin server operation" design.
-- ---------------------------------------------------------------------------
insert into public.tenant_id_sequences
  (tenant_id, id_type, format_string, current_year, current_value)
select
  id,
  'warranty_id',
  'WID-{year}-{seq:06d}',
  extract(year from now() at time zone 'utc')::int,
  0
from public.tenants
on conflict (tenant_id, id_type) do nothing;

insert into public.tenant_id_sequences
  (tenant_id, id_type, format_string, current_year, current_value)
select
  id,
  'claim_id',
  'CLM-{year}-{seq:07d}',
  extract(year from now() at time zone 'utc')::int,
  0
from public.tenants
on conflict (tenant_id, id_type) do nothing;
