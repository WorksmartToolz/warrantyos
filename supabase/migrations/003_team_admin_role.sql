-- ============================================================
-- WarrantyOS — Migration 003: team_admin role + seat count
-- Run once in the Supabase SQL Editor after 002_security_hardening.sql.
-- ============================================================


-- ────────────────────────────────────────────────────────────
-- Step 1: users — rename 'admin' role to 'team_admin'
--
-- The original check constraint was defined inline and received
-- the auto-generated name users_role_check. We drop it, migrate
-- existing data, then add the updated constraint.
-- ────────────────────────────────────────────────────────────
alter table public.users drop constraint if exists users_role_check;

update public.users set role = 'team_admin' where role = 'admin';

alter table public.users
  add constraint users_role_check
  check (role in ('team_admin', 'reviewer', 'viewer'));

comment on column public.users.role is 'team_admin: tenant configuration and team management; reviewer: claim evaluation; viewer: read-only';


-- ────────────────────────────────────────────────────────────
-- Step 2: invitations — same rename on the invitations table
--
-- invitations.role carries the intended role for the invited
-- user. It must accept 'team_admin' before provisioning code
-- can issue team_admin invitations.
-- ────────────────────────────────────────────────────────────
alter table public.invitations drop constraint if exists invitations_role_check;

update public.invitations set role = 'team_admin' where role = 'admin';

alter table public.invitations
  add constraint invitations_role_check
  check (role in ('team_admin', 'reviewer', 'viewer'));


-- ────────────────────────────────────────────────────────────
-- Step 3: tenants — add max_team_admins seat count column
--
-- Tracks how many Team Admin seats a tenant is contracted for.
-- Set at provisioning time; enforcement logic is in Session 5b.
-- Default 3 applies to all existing and future tenants unless
-- overridden at provisioning.
-- ────────────────────────────────────────────────────────────
alter table public.tenants
  add column max_team_admins integer not null default 3;

comment on column public.tenants.max_team_admins is 'Contracted Team Admin seat count. Enforcement added in Session 5b.';

-- Explicit set for pre-existing tenants (they already get the
-- default; this documents the intentional contract value).
update public.tenants
  set max_team_admins = 3
  where slug in ('acme-solar', 'bright-energy');
