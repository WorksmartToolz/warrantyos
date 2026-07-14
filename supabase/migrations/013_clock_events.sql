-- 013_clock_events.sql
-- Clock Event Infrastructure: the record of every scheduled, future-firing
-- event in the platform. Locked by Decision 9; event-type enum extended by
-- Phase 0 Item 17 and Decisions 11, 19, 21, 25, and 27.
--
-- This table backs the System-Managed Clock principle: the platform manages
-- all deadlines, not reviewers. The table is inspectable (a pending-events
-- query shows what is coming), auditable (every firing leaves a permanent row
-- with its fired_at timestamp), and decoupled from entity state (cancelling an
-- event is a status update here, not a mutation on the underlying entity).
--
-- SCOPE OF THIS MIGRATION: the table, its CHECK constraints, its three indexes,
-- and the Standard RLS Pattern. pg_cron enablement and the cron handler
-- function are separate Phase 3 build-time work (per the section's Status).
--
-- NOT EVERY TRANSITION IS A CLOCK EVENT. This table is reserved for
-- future-firing events. Synchronous transitions -- things that happen now in
-- response to a Server Action -- do not go through clock_events. Example:
-- registration prep on supply-only confirmation creates the warranty
-- registration immediately, with no clock event scheduled.
--
-- APP-LAYER INVARIANTS (documented, deliberately NOT DB constraints):
--   - payload is validated at write time per event type.
--   - fired_at is set by the cron handler when status becomes 'fired';
--     failure_reason when status becomes 'failed'. The handler owns these
--     transitions.
--   - Server Actions that create/update/delete an entity with scheduled events
--     MUST update the corresponding clock_events rows in the SAME transaction:
--       * project creation with a known trigger date -> insert a pending
--         registration_prep_pre_trigger row
--       * project trigger date update -> update fires_at on the pending row
--       * project soft-delete -> set status = 'cancelled' on pending rows
--       * comparable patterns apply for other event types
--   - tenant_id must match the parent entity's tenant_id (denormalized here
--     for RLS scoping; the matches-parent invariant is app-layer).
--
-- No FK on entity_id: it is a polymorphic reference resolved by entity_type.
create table public.clock_events (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references public.tenants(id),
  event_type      text not null,
  -- 'registration_prep_pre_trigger' -- fires registration_lead_time_days
  --     before a known trigger date. EPC trigger sources only
  --     (contractual_date_manual, wbs_integration). Item 17's renaming and
  --     specialization of Decision 9's original registration_prep.
  -- 'info_request_due'              -- information request response window
  --     expires. Hour-precision. Decision 9 Phase 1 enum.
  -- 'warranty_expiry_warning'       -- fires before a warranty coverage's end
  --     date. Decision 9 Phase 1 enum.
  -- 'trigger_confirmation_overdue'  -- project's expected trigger window
  --     passed without confirmation. Primarily delivery_report_tokenized;
  --     escalates to platform admins and team admins. Added by Item 17.
  -- 'service_report_response_due'   -- service report customer review window
  --     expires. If customer_decision is still null at firing, the row is
  --     updated to 'accepted' with accepted_by_acquiescence = true and claim
  --     closure is initiated. Added by Service Report Submission.
  -- 'work_authorization_response_overdue' -- Work Authorization document's
  --     expected_response_date passes with customer_decision still null.
  --     Reminder-only; no state mutation. Added by Decision 11.
  -- 'ala_decline_window_expired'    -- fires at decided_at +
  --     ala_decline_recant_window_days when claimant_decision = 'declined';
  --     marks the decline permanently terminal and unblocks claim denial
  --     workflow. Added by Decision 19.
  -- 'ala_response_overdue'          -- ALA response window (tenant-
  --     configurable business days, default 7) expires with claimant_decision
  --     still null. Reminder-only; sets overdue_flagged_at without touching
  --     claimant_decision. Added by Decision 25.
  -- 'warranty_id_early_issuance'    -- fires at trigger_date (kept in sync
  --     with actual_start_date confirmation). Issues warranty_id if not
  --     already set by Section 7 completion; no-ops otherwise. Added by
  --     Decision 27.
  entity_type     text not null,
  -- 'project' | 'claim' | 'warranty_coverage'
  --   | 'work_authorization_document' | 'service_report' | 'ala_document'
  --   | 'warranty_registration' | (extensible)
  entity_id       uuid not null,
  fires_at        timestamptz not null,
  status          text not null default 'pending',
  -- 'pending' | 'fired' | 'cancelled' | 'failed'
  fired_at        timestamptz,
  failure_reason  text,
  payload         jsonb,
  -- event-type-specific context, validated at write time per event type
  -- (app-layer; see APP-LAYER INVARIANTS above)
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint clock_events_event_type_check check (event_type in (
    'registration_prep_pre_trigger',
    'info_request_due',
    'warranty_expiry_warning',
    'trigger_confirmation_overdue',
    'service_report_response_due',
    'work_authorization_response_overdue',
    'ala_decline_window_expired',
    'ala_response_overdue',
    'warranty_id_early_issuance'
  )),
  constraint clock_events_entity_type_check check (entity_type in (
    'project',
    'claim',
    'warranty_coverage',
    'work_authorization_document',
    'service_report',
    'ala_document',
    'warranty_registration'
  )),
  constraint clock_events_status_check check (status in (
    'pending',
    'fired',
    'cancelled',
    'failed'
  ))
);

-- Standard RLS Pattern -------------------------------------------------------
-- Step 2: enable RLS
alter table public.clock_events enable row level security;
-- Step 3: tenant-scoped SELECT policy
create policy "clock_events: members can view their tenant's rows"
  on public.clock_events
  for select
  using (tenant_id = public.get_user_tenant_id());
-- Step 4: writes are service-role only. No user-facing INSERT/UPDATE/DELETE
--         policies; clock event scheduling, cancellation, and firing all go
--         through Server Actions and the cron handler.
-- Step 5: grants (required for PostgREST schema cache visibility)
grant all on public.clock_events to anon, authenticated, service_role;

-- Step 6: indexes. Names are Decision 9's verbatim (clock_events_tenant_idx,
-- not the pattern's usual <table>_tenant_id_idx) -- the locked decision names
-- them explicitly and the locked decision wins.
--
-- The partial index on pending fires_at is the load-bearing one: the cron
-- handler queries it hourly to find what to dispatch, and the partial filter
-- keeps the index small as fired and cancelled events accumulate.
create index clock_events_pending_fires_at_idx
  on public.clock_events (fires_at)
  where status = 'pending';
create index clock_events_tenant_idx on public.clock_events (tenant_id);
create index clock_events_entity_idx
  on public.clock_events (entity_type, entity_id);
