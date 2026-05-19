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
set search_path = public
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
  status          text        not null default 'active'
                    check (status in ('active', 'suspended', 'terminated')),
  settings        jsonb       not null default '{}',
  max_team_admins integer     not null default 3,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

comment on column public.tenants.slug            is 'URL-safe identifier for the tenant, e.g. "acme-solar"';
comment on column public.tenants.settings        is 'Per-org configuration: WarrantyID format, ClaimID format, feature flags, etc.';
comment on column public.tenants.max_team_admins is 'Contracted Team Admin seat count. Enforced at invite and role-promotion time.';

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
  role        text        not null check (role in ('team_admin', 'reviewer', 'viewer')),
  full_name   text,
  status      text        not null default 'active'
                check (status in ('active', 'suspended')),
  removed_at  timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on column public.users.role       is 'team_admin: tenant configuration and team management; reviewer: claim evaluation; viewer: read-only';
comment on column public.users.status     is 'active: normal access; suspended: temporarily blocked (reversible)';
comment on column public.users.removed_at is 'Set when a team admin removes a user. Non-null means permanently blocked. Auth account is NOT deleted — historical attribution is preserved.';

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
  select tenant_id
  from public.users
  where id = auth.uid()
    and status = 'active'
    and removed_at is null
$$;

-- anon has no business calling this function; authenticated must retain access
-- because all RLS policies on tenants, users, and invitations invoke it.
-- Suspended and removed users receive NULL from this function, which causes all
-- tenant-scoped RLS policies to evaluate false for them (defense-in-depth).
revoke execute on function public.get_user_tenant_id() from anon;
grant  execute on function public.get_user_tenant_id() to authenticated;


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

-- A user may always read their own profile row.
-- Required so that suspended/removed users can be identified by the middleware
-- (get_user_tenant_id() returns NULL for them, which would otherwise block
-- even a self-read). PostgreSQL ORs multiple SELECT policies together.
create policy "users: authenticated can read their own profile"
  on public.users
  for select
  using (id = auth.uid());

-- A user may update only their own profile record.
create policy "users: members can update their own profile"
  on public.users
  for update
  using    (id = auth.uid())
  with check (id = auth.uid());

-- INSERT / DELETE on users is service-role only.
-- User provisioning and deprovisioning are admin server operations.
-- Team management (role change, suspend, reactivate, remove) also uses
-- service-role via Server Actions; permissions are enforced at the
-- application layer in lib/core/manage-team-member.ts.


-- ────────────────────────────────────────────────────────────
-- Grants
-- PostgREST requires at least one role to have privileges on a
-- table before it will include that table in its schema cache.
-- RLS policies control actual row access; these grants are the
-- prerequisite for PostgREST to see the tables at all.
-- ────────────────────────────────────────────────────────────
grant all on public.tenants      to anon, authenticated, service_role;
grant all on public.users        to anon, authenticated, service_role;
grant all on public.invitations  to anon, authenticated, service_role;


-- ────────────────────────────────────────────────────────────
-- invitations
-- Holds pending invitations. The invited party visits
-- /signup?token=<token> to complete account setup. The
-- auth.users row is NOT created at provisioning time.
-- ────────────────────────────────────────────────────────────
create table public.invitations (
  id          uuid        primary key default gen_random_uuid(),
  tenant_id   uuid        not null references public.tenants(id) on delete cascade,
  email       text        not null,
  role        text        not null check (role in ('team_admin', 'reviewer', 'viewer')),
  full_name   text,
  token       text        not null unique,
  expires_at  timestamptz not null,
  consumed_at timestamptz,
  invited_by  uuid        references auth.users(id) on delete set null,
  created_at  timestamptz not null default now()
);

comment on table  public.invitations             is 'Pending invitations. Token validated at signup; auth user created then, not at provisioning time.';
comment on column public.invitations.token       is '64-char hex string (32 random bytes). Sent in the signup URL, never stored hashed.';
comment on column public.invitations.consumed_at is 'Set when the invited user completes signup. Non-null means the token is spent.';
comment on column public.invitations.invited_by  is 'User who created this invitation. NULL for platform-admin-issued invitations.';

create index invitations_tenant_id_idx on public.invitations(tenant_id);
create index invitations_token_idx     on public.invitations(token);

alter table public.invitations enable row level security;

create policy "invitations: members can view their tenant's invitations"
  on public.invitations
  for select
  using (tenant_id = public.get_user_tenant_id());
