-- ============================================================
-- WarrantyOS — Migration 004: team admin management
-- Run once in the Supabase SQL Editor after 003_team_admin_role.sql.
-- ============================================================


-- ────────────────────────────────────────────────────────────
-- Step 1: users — add status and removed_at columns
--
-- status tracks whether an account is usable. 'suspended' is a
-- temporary state; removal (removed_at set) is intended as
-- permanent, though recoverable at the database level.
--
-- removed_at implements soft removal: the auth account and
-- public.users row are preserved for audit trail attribution,
-- but the user is blocked from all access.
-- ────────────────────────────────────────────────────────────
alter table public.users
  add column status     text        not null default 'active'
    check (status in ('active', 'suspended')),
  add column removed_at timestamptz;

comment on column public.users.status     is 'active: normal access; suspended: temporarily blocked (reversible)';
comment on column public.users.removed_at is 'Set when a team admin removes a user. Non-null means permanently blocked. Auth account is NOT deleted — historical attribution is preserved.';


-- ────────────────────────────────────────────────────────────
-- Step 2: invitations — add invited_by column
--
-- Records which user issued the invitation. Null for invitations
-- created by platform admins via the CLI or admin panel.
-- ────────────────────────────────────────────────────────────
alter table public.invitations
  add column invited_by uuid references auth.users(id) on delete set null;

comment on column public.invitations.invited_by is 'User who created this invitation. NULL for platform-admin-issued invitations.';


-- ────────────────────────────────────────────────────────────
-- Step 3: update get_user_tenant_id() to enforce active status
--
-- By adding the status and removed_at filters here, every RLS
-- policy that calls this function automatically blocks suspended
-- and removed users from all tenant-scoped data. Defense-in-depth
-- on top of the middleware status check.
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

-- Preserve existing grants — anon still excluded, authenticated still allowed.
revoke execute on function public.get_user_tenant_id() from anon;
grant  execute on function public.get_user_tenant_id() to authenticated;


-- ────────────────────────────────────────────────────────────
-- Step 4: new RLS SELECT policy — users can read their own row
--
-- After the get_user_tenant_id() change, suspended and removed
-- users receive NULL from that function, which makes the existing
-- tenant-scoped SELECT policy ("tenant_id = get_user_tenant_id()")
-- evaluate to false for them. That is correct for listing other
-- users, but the middleware needs to read the user's own status
-- to issue the account_inactive redirect. This policy restores
-- self-read without opening any cross-user access.
--
-- PostgreSQL ORs multiple SELECT policies together, so this does
-- not override the tenant-scoped policy — both apply.
-- ────────────────────────────────────────────────────────────
create policy "users: authenticated can read their own profile"
  on public.users
  for select
  using (id = auth.uid());


-- ────────────────────────────────────────────────────────────
-- No new UPDATE RLS policies are required.
--
-- All team management operations (role change, suspend, reactivate,
-- remove) execute via the service-role admin client in Server
-- Actions, which bypasses RLS entirely. Permissions are enforced
-- at the application layer in lib/core/manage-team-member.ts
-- before the service-role client is called.
-- ────────────────────────────────────────────────────────────
