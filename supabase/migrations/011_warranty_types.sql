-- 011_warranty_types.sql
--
-- Per-tenant configurable warranty type list (Foundation, Racking, Workmanship,
-- etc.). Coverages draw down from this list. Two anchor types are seeded per
-- tenant and are permanent (is_system).
--
-- Locked sources:
--   architecture-reference.md "Warranty Type Coverages" -> warranty_types schema.
--   Decision 6 - defense-in-depth anchor protection (app layer + DB trigger).
--
-- App-layer companion (not in this migration): the Server Action for
-- warranty_types CRUD rejects delete of is_system rows and is_system->false
-- flips, for a clean early error. The DB trigger below is the structural-
-- guarantee layer that backstops it.

create table public.warranty_types (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.tenants(id),
                -- denormalized per Standard RLS Pattern.
  name          text not null,
  is_system     boolean not null default false,
                -- true on anchor types seeded at tenant provisioning;
                --   protected from delete and from is_system->false (Decision 6).
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- Case-insensitive uniqueness on (tenant_id, name): "Foundation" and
-- "foundation" collide within a tenant (architecture-reference.md).
create unique index warranty_types_tenant_name_lower_unique
  on public.warranty_types (tenant_id, lower(name));

comment on table public.warranty_types is
  'Per-tenant configurable warranty type list. Coverages instantiate these on '
  'registrations. Two anchor types (Standard Warranty, Workmanship Warranty) are '
  'seeded per tenant with is_system=true and are permanent. Decision 6; '
  'architecture-reference.md Warranty Type Coverages section.';

comment on column public.warranty_types.is_system is
  'True on anchor types seeded at provisioning. Protected from DELETE and from '
  'is_system->false by defense-in-depth (Server Action + DB trigger, Decision 6). '
  'Renameable, not deleteable.';

-- ---------------------------------------------------------------------------
-- Defense-in-depth anchor protection: DB-layer trigger (Decision 6).
-- Backstops the app-layer Server Action check. Hardened with
-- SET search_path = public per the migration 002 precedent.
-- Raises on: DELETE of an is_system row, or UPDATE flipping is_system true->false.
-- ---------------------------------------------------------------------------
create or replace function public.protect_system_warranty_types()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    if old.is_system then
      raise exception 'Cannot delete a system warranty type (is_system = true).';
    end if;
    return old;
  elsif tg_op = 'UPDATE' then
    if old.is_system and not new.is_system then
      raise exception 'Cannot clear is_system on a system warranty type.';
    end if;
    return new;
  end if;
  return null;
end;
$$;

create trigger warranty_types_protect_system
  before delete or update on public.warranty_types
  for each row
  execute function public.protect_system_warranty_types();

-- ---------------------------------------------------------------------------
-- Standard RLS Pattern (6-step)
-- ---------------------------------------------------------------------------
alter table public.warranty_types enable row level security;

create policy "warranty_types: members can view their tenant's rows"
  on public.warranty_types
  for select
  using (tenant_id = public.get_user_tenant_id());

-- Writes are service-role only: Team Admins manage the list via Server Actions;
-- Reviewers and Viewers consume it.

grant all on public.warranty_types to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Backfill: seed the two anchor types for every existing tenant, matching what
-- provisioning seeds for new tenants (architecture-reference.md: "Tenant
-- provisioning seeds two warranty_types rows per new tenant"). Idempotent via
-- the case-insensitive unique index + ON CONFLICT DO NOTHING.
--
-- Ongoing seeding for tenants created after this migration is an app-layer
-- provisioning concern (Server Action), consistent with tenant_id_sequences.
-- ---------------------------------------------------------------------------
insert into public.warranty_types (tenant_id, name, is_system)
select id, 'Standard Warranty', true
from public.tenants
on conflict (tenant_id, lower(name)) do nothing;

insert into public.warranty_types (tenant_id, name, is_system)
select id, 'Workmanship Warranty', true
from public.tenants
on conflict (tenant_id, lower(name)) do nothing;
