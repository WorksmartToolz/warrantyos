-- 028_service_report_submission.sql
--
-- The Warranty Service Report: the structured record of completed repair work,
-- prepared by whoever performed the repair and submitted to the warranty
-- professional for review. It is the bridge between Work Plan execution and
-- claim closure -- the work is done, the report documents what was done, the
-- customer reviews the assertion of completion, and the claim closes when the
-- customer accepts (explicitly or by silence under the Assumption of
-- Acquiesce). SOP 5's framing: "ensures there is a clear and documented trail
-- of the repair work performed under the warranty claim, allowing for
-- transparency and accountability."
--
-- Locked sources:
--   architecture-reference.md, "Service Report Submission" section -- THE
--     locked schema. The full table shape, the submitter dual-FK, the customer
--     review mechanism, the three-day clock event, and the seven universal
--     content fields are all specified there. Built verbatim here.
--   Decision 21 (Phase 3 decisions log) -- customer review window
--     configurability. IMPORTANT: 21 adds ZERO columns to this table and ZERO
--     to clock_events. Its two additions are provisioning-layer only
--     (tenants.settings.service_report_response_days + the
--     service_report_acquiesce_window feature flag). Neither belongs in this
--     migration. 21.7 is explicit that NO snapshot column for the window
--     length belongs on this table -- the window is derivable from
--     fires_at minus issued_at.
--   Decision 1  -- dual-FK + Snapshot Pattern (submitter capture).
--   Decision 4  -- rich text storage: ProseMirror-compatible JSON.
--   Decision 9  -- Clock Event Infrastructure. NOTE: no alter table here --
--     migration 026 already landed service_report_response_due (event_type)
--     and service_report (entity_type). Verified in 026's committed bytes.
--   Decision 16 -- Parts Fulfillment out of scope at v1 (bears on parts_used).
--   Decision 28 -- Customer-O&M Authorization (029, downstream); the O&M-actor
--     review block referenced in the arch-ref is app-layer, not schema.
--
-- ONE SERVICE REPORT PER CLAIM, STRUCTURALLY (arch-ref). claim_id is UNIQUE.
-- Multiple repair attempts resolve through the dispute-resolution path, not
-- through multiple reports on one claim. The deliberate contrast against
-- work_plans (020), work_authorization_documents (022), and notices_of_defect
-- (026), which are one-to-many; service_reports joins ala_documents (025) as
-- UNIQUE per claim. If operational reality later surfaces a need for multiple
-- reports per claim, the UNIQUE relaxes -- but one-to-one is the locked
-- commitment.
--
-- SUBMITTER DUAL-FK WITH A CONDITIONAL XOR (arch-ref). The submitter is one of
-- two bounded operational roles: an external contact (a subcontractor performing
-- the repair, contact_type = subcontractor_contact) or a warrantor self-perform
-- tenant user. Never a one-off third party -- which is exactly why this uses the
-- dual-FK + Snapshot pattern rather than the free-text snapshot Claim Intake (027)
-- uses for its unbounded claim submitter. The audit-defensibility benefit of
-- contact-FK reuse (recognizing a recurring subcontractor across many reports)
-- earns the dual-FK shape here; the unbounded claim-submitter case does not.
--
--   The XOR IS CONDITIONAL, gated on submitted_at -- deliberately UNLIKE 026
--   (notices_of_defect), whose recipient XOR is unconditional. A service report
--   HAS a pre-submission draft state; a Notice of Defect does not. The arch-ref
--   states it flatly: "exactly one non-null WHEN SUBMITTED; both null when the
--   report is in pre-submission draft." This is 010's (warranty_registrations)
--   conditional shape -- both null in the edge state, XOR otherwise -- NOT 026's
--   flat "exactly one." 026's own header names this contrast and says "DO NOT
--   HARMONIZE"; it cuts both ways. The `<>` idiom transfers from 010; the
--   discriminator differs: 010 gates on a status enum (pre_activation), this
--   gates on submitted_at IS NULL (the draft state). Same structure, different
--   key -- because this entity has no status enum, it has a submission timestamp.
--
-- FK + SNAPSHOT (Decision 1): the submitter's identity is frozen at submission
-- in submitted_by_name_snapshot / _email_snapshot / _phone_snapshot. The FK
-- preserves the relationship for reporting; the snapshot preserves who actually
-- submitted, at that address, on that date. Snapshots are captured at submission
-- and never re-synced. Same convention as notices_of_defect (026), inspections
-- (021).
--
-- SEVEN UNIVERSAL SOP CONTENT ITEMS (arch-ref). SOP 5 enumerates seven things a
-- service report contains; each maps to a column or set:
--   1. corrective actions taken          -> corrective_actions
--   2. date and duration of repair work  -> repair_started_at + repair_completed_at
--   3. names and roles of personnel      -> personnel
--   4. parts or materials used           -> parts_used
--   5. photographs before/during/after   -> photos
--   6. challenges or issues encountered  -> challenges_encountered
--   7. fully resolved or further work     -> resolution_status + further_work_explanation
-- These seven are UNIVERSAL across all warrantors and all claim types -- the
-- opposite of claim_type_data on claims, where the schema varies by
-- discriminator. Here the schema is uniform: hard columns + JSONB, no
-- custom-field variation (service_report is not in Decision 3's Phase 1
-- custom-field entity scope).
--
-- CUSTOMER REVIEW: THREE OUTCOMES IN TWO COLUMNS (arch-ref). When the warranty
-- professional accepts the report, the customer is notified via a tokenized
-- review link and may accept, dispute, or take no action. SOP 1 treats silence
-- as acceptance, so customer_decision has only two values -- accepted | disputed
-- -- and silence-acceptance is recorded as accepted WITH provenance in
-- accepted_by_acquiescence = true, NOT as a third enum value. Both explicit and
-- silent acceptance close the claim and have the same legal effect; modeling
-- them as one enum value with a provenance boolean keeps every downstream
-- surface from having to handle two operationally-identical states, while the
-- boolean preserves the audit distinction (did the customer affirmatively
-- accept, or go silent).
--
-- STATELESS TOKENIZED INTERACTION PATTERN -- TWO TOKENS ON THIS TABLE.
--   customer_review_token  -- the customer's review link (locked in the
--     arch-ref schema block). Issued only after the report is reviewer-accepted.
--   submission_token       -- the SUBMITTER's link. The arch-ref schema block
--     lists only the customer token; the submitter's link storage is prose-
--     flagged as "a column or columns on this table, parallel to
--     customer_review_token ... exact shape is a Phase 3 implementation detail."
--     Resolved here by the Tier 1 pattern law (arch-ref line 262): the token
--     lives on the entity's own row per "shape to copy, not shared store," not
--     in invitations. Built as a column pair mirroring 026's recipient_token /
--     025's claimant_token / 022's customer_token -- nullable, NO UNIQUE. This
--     is pattern application, not a new decision.
--
-- DELIBERATE OMISSIONS (documented so they are not "helpfully" added later):
--
--   - No window-length snapshot column. Decision 21.7 is explicit: the window
--     applied to each report is derivable from the clock event's fires_at minus
--     issued_at. No snapshot column belongs on this table.
--   - No work_plan_id FK. arch-ref: the relationship is one-to-one THROUGH the
--     claim (a claim has one work plan and one service report); the work plan
--     is reachable via claim_id. An explicit FK adds no information. Same shape
--     as 026's no-work_plan_id omission.
--   - No subcontractor company columns. The subcontractor's identity and
--     company are reachable through submitted_by_contact_id's FK to contacts.
--     Duplicating company on the report would create a sync surface.
--   - No closure-notice fields. The Notice of Closure is generated from the
--     closed claim's state; notice generation is a separate concern. This table
--     carries the data that drives the notice, not the notice itself.
--   - No reviewer-authority columns. Whether a warranty professional may accept
--     or reject a report is a role-based permission check at the Server Action
--     layer (reviewer is a tenant user with role reviewer or team_admin), not a
--     column here.
--   - No third customer_decision enum value for acquiescence. Silence-acceptance
--     is accepted + accepted_by_acquiescence = true. See above.
--   - No clock_events row created here, and no alter table clock_events. 026
--     already added the enum values; the service_report_response_due row is
--     inserted by the Server Action that issues the customer link, per Decision
--     9's convention. Feature-flag gating of that insert (21.5) is app-layer.
--
-- APP-LAYER INVARIANTS (deliberately not DB constraints -- 17.A.6 caps v1 DB
-- enforcement; same restraint as 026):
--   - tenant_id matches the referenced claim's tenant_id.
--   - further_work_explanation is populated when resolution_status =
--     'further_work_needed'.
--   - The submitter snapshots are captured from the FK target at submission and
--     never re-synced.
--   - When submitted_at is set, exactly one submitter FK is non-null (the CHECK
--     enforces the structural XOR; the coupling to draft/submitted state is the
--     conditional CHECK below).
--   - parts_used / photos JSONB internal shape is a flagged Phase 3 detail; the
--     columns and their nullability are locked, the array shape is not. Same
--     treatment as 026's claim_summary_snapshot, 022's field_changes, 021's
--     inspection_report.

-- ---------------------------------------------------------------------------
-- service_reports
-- ---------------------------------------------------------------------------
create table public.service_reports (
  id                                uuid primary key default gen_random_uuid(),
  tenant_id                         uuid not null references public.tenants(id),
                                    -- denormalized per Standard RLS Pattern.
  claim_id                          uuid not null unique
                                      references public.claims(id) on delete restrict,
                                    -- UNIQUE: 1:1 with claim (arch-ref). RESTRICT
                                    --   parallels every claim-child FK
                                    --   (010/016/020/021/022/025/026); the lone
                                    --   CASCADE is custom_field_values (017), a
                                    --   deliberate exception because values are
                                    --   attributes, not records.

  -- Submitter capture: Decision 1's dual-FK + Snapshot Pattern.
  submitted_by_contact_id           uuid
                                      references public.contacts(id) on delete restrict,
                                    -- when the submitter is a subcontractor
                                    --   (contact_type = subcontractor_contact).
  submitted_by_user_id              uuid
                                      references public.users(id) on delete restrict,
                                    -- when the submitter is a warrantor
                                    --   self-perform tenant user.
  submitted_by_name_snapshot        text,
  submitted_by_email_snapshot       text,
  submitted_by_phone_snapshot       text,
                                    -- frozen at submission; nullable because
                                    --   they are unset while the report is in
                                    --   pre-submission draft.
  submitted_at                      timestamptz,
                                    -- set when the report transitions from
                                    --   draft to submitted. Null in draft.

  -- Submitter's tokenized link (Stateless Tokenized Interaction Pattern).
  -- Column pair on this row per "shape to copy, not shared store", parallel to
  -- customer_review_token below and to 026's recipient_token. NO unique.
  submission_token                  text,
  submission_token_expires_at       timestamptz,

  -- The seven universal SOP content items.
  corrective_actions                jsonb not null,
                                    -- what was done; ProseMirror-compatible
                                    --   JSON per Decision 4.
  repair_started_at                 timestamptz not null,
  repair_completed_at               timestamptz not null,
                                    -- duration is derived from the two
                                    --   timestamps; display unit is a
                                    --   presentation choice, not storage.
  personnel                         jsonb not null,
                                    -- array of {name, role}; JSONB (not child
                                    --   table) because no downstream join
                                    --   surface. Locked by the arch-ref.
  parts_used                        jsonb,
                                    -- array of {part, quantity, ...}; JSONB.
                                    --   The arch-ref flags child-table only on
                                    --   cost-tracking-join grounds; Parts
                                    --   Fulfillment is out of scope at v1
                                    --   (Decision 16), so no join surface
                                    --   exists. Resolved as JSONB by precedent.
  photos                            jsonb,
                                    -- array of {url, caption?, category?} with
                                    --   before/during/after categorization;
                                    --   JSONB, same reasoning as parts_used and
                                    --   supporting_documents on Claim Intake.
  challenges_encountered            jsonb,
                                    -- rich text (Decision 4); nullable because
                                    --   some repairs have none to note.
  resolution_status                 text not null,
                                    -- 'fully_resolved' | 'further_work_needed'.
  further_work_explanation          jsonb,
                                    -- rich text (Decision 4); required
                                    --   app-layer when resolution_status =
                                    --   'further_work_needed'.

  -- Reviewer step (the warranty professional).
  reviewer_user_id                  uuid
                                      references public.users(id) on delete restrict,
                                    -- nullable until reviewed.
  reviewer_decision                 text,
                                    -- 'accepted' | 'rejected'.
  reviewed_at                       timestamptz,

  -- Customer review: tokenized link, three outcomes in two columns.
  customer_review_token             text,
                                    -- single-use; null until the report is
                                    --   reviewer-accepted and the link issues.
  customer_review_token_expires_at  timestamptz,
  customer_decision                 text,
                                    -- 'accepted' | 'disputed'. Silence-
                                    --   acceptance is 'accepted' with
                                    --   accepted_by_acquiescence = true, NOT a
                                    --   third value.
  accepted_by_acquiescence          boolean,
                                    -- true only when the clock event fires the
                                    --   silence-acceptance path; null in all
                                    --   other cases (including explicit accepts
                                    --   and disputes).
  customer_decided_at               timestamptz,
  customer_dispute_details          jsonb,
                                    -- rich text (Decision 4); populated when
                                    --   customer_decision = 'disputed'.

  created_at                        timestamptz not null default now(),
  updated_at                        timestamptz not null default now(),

  -- Submitter dual-FK XOR, CONDITIONAL on submitted_at (arch-ref). Both null in
  -- pre-submission draft; exactly one non-null when submitted. 010's shape, not
  -- 026's. DO NOT HARMONIZE to the unconditional form.
  constraint service_reports_submitter_check check (
    (submitted_at is null
       and submitted_by_contact_id is null
       and submitted_by_user_id is null)
    or
    (submitted_at is not null
       and (submitted_by_contact_id is not null) <> (submitted_by_user_id is not null))
  ),
  constraint service_reports_resolution_status_check check (
    resolution_status in ('fully_resolved', 'further_work_needed')
  ),
  constraint service_reports_reviewer_decision_check check (
    reviewer_decision in ('accepted', 'rejected')
  ),
  constraint service_reports_customer_decision_check check (
    customer_decision in ('accepted', 'disputed')
  )
);
create index service_reports_tenant_id_idx
  on public.service_reports (tenant_id);
create index service_reports_submitted_by_contact_id_idx
  on public.service_reports (submitted_by_contact_id)
  where submitted_by_contact_id is not null;
create index service_reports_submitted_by_user_id_idx
  on public.service_reports (submitted_by_user_id)
  where submitted_by_user_id is not null;
  -- partial: the submitter XOR means at most one leg is populated. Same
  -- convention as 026's two partial recipient indexes and 017's three.
  -- claim_id needs no separate index: its UNIQUE constraint already builds one.
comment on table public.service_reports is
  'The structured record of completed repair work, prepared by whoever '
  'performed the repair and submitted to the warranty professional for review '
  '(SOP 5, arch-ref "Service Report Submission"). The bridge between Work Plan '
  'execution and claim closure. One service report per claim, structurally '
  '(claim_id UNIQUE) -- multiple repair attempts resolve through the '
  'dispute-resolution path, not through multiple reports; joins ala_documents '
  '(025) as UNIQUE per claim, the deliberate contrast against work_plans (020), '
  'work_authorization_documents (022), and notices_of_defect (026). The seven '
  'SOP content items are universal across all warrantors -- uniform hard-column '
  '+ JSONB shape, no custom-field variation. NO work_plan_id FK: the '
  'relationship is one-to-one through the claim.';
comment on column public.service_reports.submitted_by_contact_id is
  'Dual-FK submitter with a CONDITIONAL XOR (arch-ref), gated on submitted_at: '
  'both null in pre-submission draft, exactly one non-null when submitted. This '
  'is 010''s conditional shape (both null in the pre_activation edge state, XOR '
  'otherwise), NOT 026''s unconditional "exactly one" -- a service report has a '
  'draft state, a Notice of Defect does not. The `<>` idiom transfers from 010; '
  'the discriminator differs (010 gates on a status enum, this gates on '
  'submitted_at IS NULL). 026''s header says DO NOT HARMONIZE about exactly '
  'this contrast; it cuts both ways. The dual-FK + Snapshot pattern is used '
  'here rather than 027''s free-text snapshot because the submitter is a '
  'bounded role (subcontractor or self-perform tenant user), never a one-off '
  'third party -- so contact-FK reuse earns its audit-defensibility benefit.';
comment on column public.service_reports.submission_token is
  'The submitter''s tokenized link (Stateless Tokenized Interaction Pattern). '
  'The arch-ref schema block lists only the customer''s token; the submitter '
  'link storage was prose-flagged as "a column or columns on this table, '
  'parallel to customer_review_token." Resolved by the Tier 1 pattern law: '
  'the token lives on this row per "shape to copy, not shared store," not in '
  'invitations. Column pair mirroring 026''s recipient_token, 025''s '
  'claimant_token, 022''s customer_token -- nullable, NO unique. Distinct from '
  'customer_review_token on this same table: submission_token gates the '
  'subcontractor submitting the report; customer_review_token gates the '
  'customer reviewing it after reviewer acceptance.';
comment on column public.service_reports.customer_decision is
  'Two values, exactly: accepted | disputed. Silence-acceptance (SOP 1''s '
  'Assumption of Acquiesce) is NOT a third value -- it is recorded as accepted '
  'with accepted_by_acquiescence = true and customer_decided_at = the moment '
  'the service_report_response_due clock event processed. Both explicit and '
  'silent acceptance close the claim and have the same legal effect; modeling '
  'them as one enum value with a provenance boolean keeps downstream surfaces '
  'from handling two operationally-identical states, while the boolean '
  'preserves the audit distinction.';
comment on column public.service_reports.accepted_by_acquiescence is
  'True only when the service_report_response_due clock event fires the '
  'silence-acceptance path; null in all other cases (including explicit accepts '
  'and disputes). The clock event (event_type service_report_response_due, '
  'entity_type service_report -- both landed in 026, no alter table here) is '
  'inserted by the Server Action that issues the customer link, per Decision 9. '
  'Its firing is gated by the service_report_acquiesce_window feature flag '
  '(Decision 21.5, app-layer): when disabled, the event is not created and the '
  'customer must act explicitly.';
comment on column public.service_reports.resolution_status is
  'fully_resolved | further_work_needed (SOP item 7). further_work_explanation '
  'is required app-layer when this is further_work_needed -- not a DB CHECK, '
  'per 17.A.6''s cap on v1 DB enforcement, the same restraint as 026.';

-- ---------------------------------------------------------------------------
-- Standard RLS Pattern (6-step)
-- ---------------------------------------------------------------------------
alter table public.service_reports enable row level security;

create policy "service_reports: tenant read"
  on public.service_reports
  for select
  using (tenant_id = public.get_user_tenant_id());

-- Writes are service-role only: submission, reviewer decision, the customer's
-- tokenized review, and the clock-event-driven silence-acceptance all run
-- through Server Actions.

grant all on public.service_reports to anon, authenticated, service_role;
