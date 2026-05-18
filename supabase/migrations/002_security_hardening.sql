-- ============================================================
-- WarrantyOS — Migration 002: Security hardening
-- Addresses warnings from the Supabase database linter.
-- Run once in the Supabase SQL Editor after 001_invitations.sql.
-- ============================================================


-- ────────────────────────────────────────────────────────────
-- Fix 1: set_updated_at — mutable search_path
--
-- WARN: function_search_path_mutable
-- A function without a fixed search_path is vulnerable to
-- search_path injection if an attacker can prepend a schema.
-- Adding SET search_path = public pins the resolution context.
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
-- Fix 2: get_user_tenant_id — anon role access
--
-- WARN: anon_security_definer_function_executable
-- WARN: authenticated_security_definer_function_executable
--
-- By default PostgreSQL grants EXECUTE on new functions to PUBLIC,
-- which includes the anon role. Unauthenticated callers have no
-- business calling this function (auth.uid() returns null for them).
--
-- The function MUST stay SECURITY DEFINER and MUST remain callable
-- by authenticated — RLS policies on tenants, users, and invitations
-- all invoke it. We only revoke from anon.
-- ────────────────────────────────────────────────────────────
revoke execute on function public.get_user_tenant_id() from anon;
grant  execute on function public.get_user_tenant_id() to authenticated;


-- ────────────────────────────────────────────────────────────
-- Acknowledged: rls_auto_enable warnings
--
-- WARN: anon_security_definer_function_executable — public.rls_auto_enable()
-- WARN: authenticated_security_definer_function_executable — same
--
-- public.rls_auto_enable() is a Supabase-managed function created
-- automatically when "Enable automatic RLS" was selected during
-- project setup. It is not defined in our schema files and its
-- grants cannot be altered from the application layer without
-- risking breakage of Supabase's internal infrastructure.
--
-- These two warnings are acknowledged and intentionally not
-- addressed here. No code change is possible or appropriate.
-- ────────────────────────────────────────────────────────────


-- ────────────────────────────────────────────────────────────
-- Not applicable: auth_leaked_password_protection
--
-- WARN: auth_leaked_password_protection — Leaked password protection disabled
--
-- This is a Supabase Auth configuration setting, not a database
-- object. It must be enabled in the Supabase Dashboard:
--   Authentication → Settings → Security → Leaked password protection → Enable
--
-- No SQL action is possible or needed here.
-- ────────────────────────────────────────────────────────────
