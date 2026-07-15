-- Migration 016: claims (shell)
--
-- Source of truth: architecture-reference.md "Claim (Shell)" section
--                  (Tier 2 shell scope) + Decision 27 (Phase 3 decisions log).
--
-- SCOPE: SHELL ONLY. The intake data model is a SEPARATE Tier 3 section and is
-- deliberately NOT built here. Do not add intake form fields (hard columns or
-- JSONB), tokenized intake link columns, gate-level state columns, or a
-- claimant FK/snapshot. All four are named in the arch ref's "What is NOT in
-- the shell" list as deliberate omissions.
--
-- DELIBERATE OMISSIONS (documented so a future chat does not "helpfully" add
-- them back):
--
--   * No UNIQUE on claim_id. The gap-free guarantee lives in the ID Generation
--     system (Decision 2): tenant_id_sequences is row-locked in the same
--     transaction as the insert, so the mechanism IS the uniqueness. The
--     parallel column warranty_registrations.warranty_id (migration 010) is a
--     bare text column with no unique constraint; that is the governing
--     precedent and it is not overridden here.
--
--   * No CHECK requiring emergency_stabilized_at when is_emergency = true.
--     Decision 27.6 is explicit: the customer is reporting a past event they
--     experienced before ever touching the platform, and the platform must not
--     block filing on their own self-report. emergency_window_exceeded is
--     DERIVED (now() - emergency_stabilized_at > 24 hours), never stored, and
--     is surfaced to the Gate 1 reviewer as judgment input under
--     Administrative Validation's three-outcome shape — "reviewer judgment,
--     not a hard platform gate." A DB CHECK would be exactly the hard platform
--     gate 27.6 forbids. The "required when is_emergency = true" requirement is
--     an intake-form / app-layer rule.
--
--   * No UNIQUE on warranty_registration_id. A registration accumulates many
--     claims over the warranty horizon; the relationship is one-to-many by
--     design (arch ref, "Parent: warranty_registrations").
--
-- IMPLEMENTATION DETAIL RESOLVED IN THIS MIGRATION:
--
--   * ON DELETE RESTRICT on warranty_registration_id. The arch ref states this
--     clause "is not yet locked ... a Phase 3 implementation detail" and points
--     at the projects-to-registrations parallel (RESTRICT, with soft-delete as
--     the operational cleanup path) as the suggested restraint. Confirmed with
--     Andre in Chat 14 and resolved as RESTRICT, matching migration 010.
--
-- APP-LAYER INVARIANTS (not DB constraints, per the architecture):
--   * tenant_id must match the referenced registration's tenant_id.
--   * claim_id is immutable once set (enforced in the Server Action, same as
--     warranty_id in 010).
--   * Claim eligibility: filable exactly when the parent registration's
--     warranty_id IS NOT NULL (Decision 27.4). Emergency claims are subject to
--     the same rule — the carve-out governs filing TIMING, not eligibility
--     (Decision 27.7).
--
-- STATUS: the CHECK enforces the only value the architecture locks at the shell
-- level: 'intake_received'. The richer value set reflects v1's Six Gates plus
-- outcome states and is Tier 3 / downstream operational work; it is added by a
-- later migration when that section is drafted. A one-value CHECK is the
-- architecturally honest shell-scope read, not an oversight.

create table if not exists public.claims (
  id                        uuid primary key default gen_random_uuid(),
  tenant_id                 uuid not null references public.tenants(id),
  warranty_registration_id  uuid not null
                              references public.warranty_registrations(id)
                              on delete restrict,
  claim_id                  text not null,
  status                    text not null default 'intake_received',
  is_emergency              boolean not null default false,
  emergency_stabilized_at   timestamptz,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),

  constraint claims_status_check
    check (status = any (array['intake_received'::text]))
);

-- Standard RLS Pattern: tenant index
create index if not exists claims_tenant_id_idx
  on public.claims (tenant_id);

-- Parent lookup: claims for a registration.
create index if not exists claims_warranty_registration_id_idx
  on public.claims (warranty_registration_id);

-- Standard RLS Pattern: enable RLS
alter table public.claims enable row level security;

-- Standard RLS Pattern: tenant-scoped SELECT for members.
-- Writes are service-role only (no INSERT/UPDATE/DELETE policies).
create policy "claims: members can view their tenant's rows"
  on public.claims
  for select
  using (tenant_id = public.get_user_tenant_id());

-- Standard RLS Pattern: grants
grant all on table public.claims to anon;
grant all on table public.claims to authenticated;
grant all on table public.claims to service_role;

comment on table public.claims is
  'Claim shell (Tier 2). A customer''s report against a live warranty '
  'registration. Intake data model, tokenized intake link, and the Six Gates '
  'status value set are Tier 3 and deliberately absent.';

comment on column public.claims.claim_id is
  'Business-visible ClaimID, generated from tenant_id_sequences (id_type = '
  '''claim_id'', default format CLM-{year}-{seq:07d}) in the same transaction '
  'as the insert. Independent per-tenant sequence — NOT derived from the '
  'parent WarrantyID (v1''s [WarrantyID]-C[NNNN] form is retired). Immutable '
  'once set; immutability is enforced in the Server Action.';

comment on column public.claims.status is
  'Minimum locked value: intake_received. Richer values (v1 Six Gates plus '
  'outcome states) are Tier 3; the CHECK is extended by migration when that '
  'section lands.';

comment on column public.claims.is_emergency is
  'Decision 27.5. Customer-reported emergency stabilization carve-out.';

comment on column public.claims.emergency_stabilized_at is
  'Decision 27.5. Customer-reported stabilization moment; starts the 24-hour '
  'formal-filing window. Self-reported at intake, not independently verified '
  'by the platform. Required when is_emergency = true — enforced at the '
  'intake form / app layer, NOT as a DB CHECK (Decision 27.6: the 24-hour '
  'window is not a submission-blocking validation).';
