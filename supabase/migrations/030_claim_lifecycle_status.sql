-- Migration 030: claim lifecycle status enum (Tier 3 Six Gates)
--
-- Source of truth: Decision 30 (Phase 3 decisions log) + SOP 1 (Accepted
--                  Warranty Claim Lifecycle) as the design-against source.
--
-- WHAT THIS DOES: extends claims.status from the shell-scope one-value CHECK
-- ('intake_received', locked in 016) to the full Tier 3 value set. Migration 016
-- explicitly anticipated this: "the CHECK is extended by migration when that
-- section lands." No table/column added; this is a CHECK swap + comment refresh.
--
-- THE VALUE SET (Decision 30). One text column, NO gate-level columns
-- (016 + arch-ref 3415: the Six Gates are a structure OVER status, not columns):
--
--   ENTRY / GATE STAGES (linear, SOP 1 order):
--     intake_received              -- entry; the only value 016 locked. Kept.
--     administrative_validation    -- Gate 1 (016 header: named, 3-outcome shape)
--     responsibility_notice        -- Gate 2 (SOP 1 Notice of Defect; Decision 14)
--     evidence_evaluation          -- Gate 3 (arch-ref 4356: named; inspection/ALA)
--     work_planning_authorization  -- Gate 4 (SOP 1; Decisions 11/15)
--     execution_service_report     -- Gate 5 (15.3/15.4 REQUIRE execution+scheduling
--                                  --   at claim level, not on work_plans)
--     customer_review              -- Gate 6 (arch-ref 5062; Decision 21; 3-day window)
--
--   OUTCOME / TERMINAL STATES:
--     resolved                     -- reviewer accepts Service Report (arch-ref 5066).
--                                  --   Non-terminal: precedes closure.
--     closed                       -- customer accept/acquiesce or post-dispute
--                                  --   resolution; Notice of Closure sent (arch-ref 5069)
--     denied                       -- claim rejected at review (SOP 1; workbooks 3/4)
--     escalated                    -- denied claim appealed (arch-ref 4298 "existing
--                                  --   Escalated/Denied pathway"; workbooks 3/4)
--     indistinct_ala_required      -- one of v1's Six Final Outcomes (025 / arch-ref
--                                  --   3801). Branch/flag at Gate 3, gated by an
--                                  --   unsigned ALA (19.7); resolves back into the
--                                  --   linear flow once the ALA is signed.
--
-- DELIBERATELY NOT ENCODED HERE (per Decision 30 + standing locks):
--   * No transition enforcement in the DB. Transitions are governed by Server
--     Actions (same rule 015 states for work_plans), not by CHECK/trigger. The
--     value set is the lock; the transition MAP + authorized actors live in the
--     C10 claim-progression Server Actions (roadmap), per Decision 30.
--   * is_emergency stays a separate boolean flag (Decision 27.5), NOT a status
--     value -- it governs filing TIMING, not lifecycle stage.
--   * No gate-level state columns (016 deliberate-omission list; arch-ref 3415).
--
-- VERIFICATION AFTER db reset: this is a CHECK swap with no computed output, so
-- `db reset` applied-clean DOES prove correctness here (unlike backfills). Still
-- confirm the constraint exists with the new array via \d public.claims.

alter table public.claims
  drop constraint claims_status_check;

alter table public.claims
  add constraint claims_status_check
  check (status = any (array[
    'intake_received'::text,
    'administrative_validation'::text,
    'responsibility_notice'::text,
    'evidence_evaluation'::text,
    'work_planning_authorization'::text,
    'execution_service_report'::text,
    'customer_review'::text,
    'resolved'::text,
    'closed'::text,
    'denied'::text,
    'escalated'::text,
    'indistinct_ala_required'::text
  ]));

comment on column public.claims.status is
  'Claim lifecycle status (Decision 30, Tier 3 Six Gates). Entry: '
  'intake_received. Gate stages: administrative_validation (G1), '
  'responsibility_notice (G2), evidence_evaluation (G3), '
  'work_planning_authorization (G4), execution_service_report (G5), '
  'customer_review (G6). Outcomes: resolved, closed, denied, escalated, '
  'indistinct_ala_required. Transitions + authorized actors are enforced in '
  'the claim-progression Server Actions (C10), NOT in the DB -- same discipline '
  'as work_plans (Decision 15). is_emergency stays a separate flag (27.5).';
