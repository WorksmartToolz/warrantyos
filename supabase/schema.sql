-- ============================================================
-- WarrantyOS — Initial Database Schema
-- Run this in full in the Supabase SQL Editor.
-- ============================================================


-- ────────────────────────────────────────────────────────────
-- Helper: auto-update updated_at on row modification
-- ────────────────────────────────────────────────────────────
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;


-- ────────────────────────────────────────────────────────────
-- tenants
-- The architectural anchor. Every piece of data in the system
-- ultimately scopes back to a tenant_id. No cross-tenant
-- operations exist except via authorized platform administration
-- using the service role.
-- ────────────────────────────────────────────────────────────
create table public.tenants (
  id         uuid        primary key default gen_random_uuid(),
  name       text        not null,
  slug       text        not null unique,
  status     text        not null default 'active'
               check (status in ('active', 'suspended', 'terminated')),
  settings   jsonb       not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on column public.tenants.slug     is 'URL-safe identifier for the tenant, e.g. "acme-solar"';
comment on column public.tenants.settings is 'Per-org configuration: WarrantyID format, ClaimID format, feature flags, etc.';

create trigger tenants_set_updated_at
  before update on public.tenants
  for each row execute function public.set_updated_at();


-- ────────────────────────────────────────────────────────────
-- users
-- People who work for warrantor organizations.
-- id mirrors auth.users.id; the two are kept in sync via
-- cascade delete so removing an auth user removes the profile.
-- ────────────────────────────────────────────────────────────
create table public.users (
  id          uuid        primary key references auth.users(id) on delete cascade,
  tenant_id   uuid        not null references public.tenants(id) on delete restrict,
  email       text        not null,
  role        text        not null check (role in ('admin', 'reviewer', 'viewer')),
  full_name   text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on column public.users.role is 'admin: tenant configuration; reviewer: claim evaluation; viewer: read-only';

create index users_tenant_id_idx on public.users(tenant_id);

create trigger users_set_updated_at
  before update on public.users
  for each row execute function public.set_updated_at();


-- ────────────────────────────────────────────────────────────
-- Row-Level Security
-- Both tables are locked down. Default-deny; policies below
-- grant the minimum required access.
-- ────────────────────────────────────────────────────────────
alter table public.tenants enable row level security;
alter table public.users    enable row level security;


-- ────────────────────────────────────────────────────────────
-- RLS helper: resolves the calling user's tenant_id without
-- triggering circular policy evaluation on public.users.
-- SECURITY DEFINER runs as the function owner (bypasses RLS).
-- ────────────────────────────────────────────────────────────
create or replace function public.get_user_tenant_id()
returns uuid
language sql
security definer
stable
set search_path = public
as $$
  select tenant_id from public.users where id = auth.uid()
$$;


-- ────────────────────────────────────────────────────────────
-- RLS policies: tenants
-- ────────────────────────────────────────────────────────────

-- A user may read only the tenant they belong to.
create policy "tenants: members can view their own tenant"
  on public.tenants
  for select
  using (id = public.get_user_tenant_id());

-- INSERT / UPDATE / DELETE on tenants is service-role only.
-- Tenant lifecycle management never goes through user sessions.


-- ────────────────────────────────────────────────────────────
-- RLS policies: users
-- ────────────────────────────────────────────────────────────

-- A user may read other users only within their own tenant.
create policy "users: members can view users in their tenant"
  on public.users
  for select
  using (tenant_id = public.get_user_tenant_id());

-- A user may update only their own profile record.
create policy "users: members can update their own profile"
  on public.users
  for update
  using    (id = auth.uid())
  with check (id = auth.uid());

-- INSERT / DELETE on users is service-role only.
-- User provisioning and deprovisioning are admin server operations.


-- ────────────────────────────────────────────────────────────
-- Grants
-- PostgREST requires at least one role to have privileges on a
-- table before it will include that table in its schema cache.
-- RLS policies control actual row access; these grants are the
-- prerequisite for PostgREST to see the tables at all.
-- ────────────────────────────────────────────────────────────
grant all on public.tenants to anon, authenticated, service_role;
grant all on public.users   to anon, authenticated, service_role;
