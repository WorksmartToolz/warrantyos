-- 026_notices_of_defect.sql
--
-- The Notice of Defect: the warrantor's formal, on-the-record notification to a
-- believed-responsible party -- "this defect is yours; respond with acceptance
-- or rejection."
--
-- Its purpose, in Andre's words during Decision 14's drafting: "the party
-- believed to be responsible has been officially notified and that is a matter
-- of record." It is an AUDIT ARTIFACT OF OFFICIAL NOTIFICATION, separate from
-- any downstream execution work. That framing is the whole shape of this table.
--
-- Locked sources:
--   Decision 14 (Phase 3 decisions log) -- THE locked architectural
--     specification: ten commitments plus the schema sketch, built verbatim
--     here. The architecture reference has NO Notice of Defect section; its
--     Work Plan cross-reference says so explicitly and points here. The
--     decisions log is the authority for this entity.
--   Decision 1  -- dual-FK + Snapshot Pattern, broadened by 14.2.
--   Decision 4  -- rich text storage: ProseMirror-compatible JSON.
--   Decision 9  -- Clock Event Infrastructure; 14.9 adds
--     notice_of_defect_response_overdue.
--   Decision 16.5 -- Parts Claims do not get a Notice of Defect (app-layer).
--
-- V1 GOT THIS STRUCTURALLY WRONG, and the correction is the point of the
-- entity. v1 modeled Notice of Defect as fields on the Work Plan
-- (notice_of_defect_sent boolean, notice_of_defect_response text). The Phase 1
-- audit flagged it: a Notice of Defect is a document sent to a party, with its
-- own lifecycle, its own response, and its own audit trail. It is not an
-- attribute of a Work Plan.
--
-- NO FK TO WORK PLANS IN EITHER DIRECTION (14.4). notices_of_defect has no
-- work_plan_id; work_plans has no notice_of_defect_id (confirmed: 020's header
-- documents that omission). The Notice's architectural responsibility ENDS at
-- response capture. Whether a Work Plan, downstream tracking, dispute, or other
-- activity follows from an accepted Notice is operational and
-- contract-dependent -- not encoded in the schema. Some Notices lead to Work
-- Plans; some never do, because the subcontractor remediates independently, or
-- the matter is contractually outside warrantor coordination, or the claim
-- resolves without warrantor-coordinated execution. "Which Notice of Defect led
-- to this Work Plan" is an application-layer question answered by reading the
-- claim's history. Do not add the FK later "for convenience" -- its absence is
-- the locked decision.
--
-- ONE-TO-MANY WITH CLAIMS (14.1) -- no UNIQUE on claim_id. Zero, one, or many
-- per claim: zero when the defect is the warrantor's own responsibility, many
-- when multiple parties share responsibility or when the responsibility picture
-- evolves and a new party is put on notice. Same shape as work_plans (020) and
-- work_authorization_documents (022); the deliberate contrast against
-- ala_documents (025) and service_reports, which are UNIQUE per claim.
--
-- ACCEPTANCE IS NOT CLOSURE (14.3). A recipient may accept at the notice stage,
-- get to site, and shift position ("not on me, it's the other guy"). Such
-- post-acceptance position changes are NOT captured as revisions to this row's
-- response_status. They become NEW events -- a new Notice of Defect to another
-- party, a claim status transition, an escalation -- each in its own section.
-- The historical record of the original response is preserved intact. This is
-- why there is NO revisions child table here, deliberately unlike
-- work_authorization_revisions (022) and ala_document_revisions (025): those
-- entities revise their content in place and log the prior state; a Notice of
-- Defect's response is frozen testimony about a moment.
--
-- CREATABLE AT ANY POINT IN THE CLAIM LIFECYCLE (14.6). At claim review time
-- during initial responsibility determination, or later -- after inspection
-- findings, after scope investigation reveals a different responsible party.
-- The architecture does not constrain when rows can be created; that is a
-- Server Action authority rule, not a schema constraint.
--
-- DUAL-FK RECIPIENT WITH XOR (14.2), Decision 1's pattern broadened: the
-- recipient is either an external contact (subcontractor, vendor, original
-- installer, or other contact_type) or an internal user (Path 1 self-perform).
-- Exactly one is non-null.
--
--   The XOR IS UNCONDITIONAL here, deliberately differing from 010
--   (warranty_registrations), whose dual-FK assignee CHECK gates on status:
--   both null when status = 'pre_activation', exactly one otherwise. That
--   conditionality is Decision 23.7's four-state registration machine, which
--   the Notice of Defect has no analogue to -- a Notice without a recipient is
--   not a thing that exists. 14.2 states the rule flatly: "exactly one
--   non-null." The `<>` idiom transfers from 010; the status gate does not.
--   DO NOT HARMONIZE.
--
-- FK + SNAPSHOT (14.2): recipient identity is frozen at notification time in
-- recipient_name_snapshot / recipient_email_snapshot /
-- recipient_company_snapshot. The FK preserves the relationship for reporting;
-- the snapshot preserves who was actually notified, at that address, on that
-- date -- which is the entire audit-defensibility point of a matter-of-record
-- notification. Snapshots are captured at row creation and never re-synced: the
-- FK may drift if a contact is later edited; the snapshot cannot. Same
-- convention as inspections (021).
--
-- contact_type NEEDS NO EXTENSION. 14.10 flags adding vendor_contact and
-- original_installer_contact "or equivalent" as a routine Phase 3 detail "when
-- Notice of Defect functionality is built" -- i.e. now. Checked against the
-- built enum (005): vendor and vendor_contact ALREADY EXIST. No
-- original_installer_contact, but 14.10's "or equivalent" and the sketch's own
-- scoping ("subcontractor, vendor, original installer, or other contact_type")
-- are satisfied by the existing 'other' value. 14.10 is discharged with no
-- migration. If operational pressure later surfaces a real need to distinguish
-- original installers in reporting, that is a one-line CHECK extension.
--
-- ON DELETE resolved at build time, all four from precedent:
--   claim_id             -> RESTRICT. The log defers only the clause, calling
--     it "parallel to other claim-child FK flags". Those parallels are
--     010/016/020/021/022/025 -- all RESTRICT. Every parent soft-deletes;
--     hard-deletion is not an ordinary path, and cascade-deleting the record
--     that a party was officially notified would destroy exactly the audit
--     artifact this entity exists to be.
--   recipient_contact_id -> RESTRICT. The log names the reasoning itself:
--     "soft-delete on contacts and tenant users means hard-deletion isn't
--     ordinary". Matches 020's subcontractor_contact_id.
--   recipient_user_id    -> RESTRICT. Same, for tenant users (removed_at
--     soft-remove). Matches 020's warranty_professional_user_id and 025's
--     revised_by_user_id.
--   notified_by_user_id  -> RESTRICT. Not separately flagged in the log, but
--     the same clause for the same reason: it records WHO sent the
--     notification, and that is not erasable by removing a user.
--
-- DELIBERATE OMISSIONS (documented so they are not "helpfully" added later):
--
--   - No work_plan_id FK. 14.4, in either direction. See above.
--   - No revisions child table. 14.3: position changes become new events, not
--     revisions. Deliberately unlike 022 and 025.
--   - No UNIQUE on claim_id. 14.1: one-to-many. See above.
--   - No 'withdrawn' status. The locked enum is exactly three values --
--     pending | accepted | rejected. A four-value machine with 'withdrawn'
--     appears nowhere in Decision 14; do not add it by analogy to 022's
--     seven-value work-authorization machine. Different entity, different
--     lifecycle: a Notice of Defect is a matter of record, and un-sending one
--     is not a thing.
--   - No templates table. Unlike Customer Work Authorization (022), the ALA
--     System (025), and the Acknowledgment Gate (023), a Notice of Defect has
--     no tenant-defined reusable template: 14.8 puts the warrantor's custom
--     message in notification_message per-Notice, and the claim content is a
--     snapshot, not a template instantiation. The templates-and-documents shape
--     does NOT transfer here.
--   - No status column separate from response_status. The locked sketch carries
--     one response column set; the Notice's own lifecycle IS its response
--     status. Sent-ness is recorded by notified_at, which is NOT NULL.
--   - No DB CHECK coupling response_at / response_explanation to
--     response_status != 'pending'. App-layer; 17.A.6 caps v1 DB enforcement.
--     Same restraint as 022's denial_explanation and 025's accepted-implies-
--     signed invariant.
--   - No DB CHECK coupling the snapshot columns to their FK. A snapshot that
--     matched the FK's current values would defeat the point of a snapshot.
--   - No clock_events row created here. The
--     notice_of_defect_response_overdue event is inserted by the Server Action
--     that sends the notification, per Decision 9's convention that
--     clock_events is for future-firing events scheduled by the action that
--     causes them. This migration adds the enum values it will use.
--   - No Acknowledgment Gate wiring. Decision 12's gate_purpose Phase 1 values
--     are claim_submission and work_authorization only; a Notice of Defect
--     recipient is not gated. Extensible later exactly like clock_events.
--   - No Parts Claim exclusion CHECK. Decision 16.5 excludes Parts Claims from
--     Notice of Defect, but that is app-layer -- a DB CHECK would couple this
--     table to the parent claim's claim_type. Same treatment as 020's identical
--     Decision 16.3 exclusion.
--
-- APP-LAYER INVARIANTS (deliberately not DB constraints):
--   - tenant_id matches the referenced claim's tenant_id.
--   - response_at and response_explanation are populated when response_status
--     leaves 'pending'.
--   - The recipient snapshots are captured from the FK target at row creation
--     and never re-synced.
--   - Parts Claims do not get a Notice of Defect (16.5).
--   - Whether re-notifying a previously-noticed party on the same claim creates
--     a new row or updates the existing one is a flagged Phase 3 OPERATIONAL
--     question (deferred in Decision 14, not resolved here). The schema
--     permits either: one-to-many is locked, so a new row is always legal.
--   - claim_summary_snapshot's internal shape (which claim fields are frozen)
--     is a flagged Phase 3 implementation detail. The column and its NOT NULL
--     are locked; the JSONB shape is not. Same treatment as 021's
--     inspection_report and 022's field_changes.

-- ---------------------------------------------------------------------------
-- clock_events enum extension (Decision 14.9)
-- ---------------------------------------------------------------------------
-- 14.9 calls notice_of_defect_response_overdue the "seventh" event type. That
-- ordinal is STALE: Decisions 25 and 27 landed after Decision 14 and added
-- ala_response_overdue and warranty_id_early_issuance, so the built enum (013)
-- already carries nine. The VALUE is locked; only the count was written before
-- the later decisions existed. This adds the tenth -- and the seventh
-- entity_type, notice_of_defect.
--
-- Unlike migration 025 (ALA), which needed no alter table because 013 already
-- carried its enum values, this entity's values were never added. Extension via
-- migration is the convention Decision 9 establishes for exactly this.

alter table public.clock_events
  drop constraint clock_events_event_type_check;

alter table public.clock_events
  add constraint clock_events_event_type_check check (
    event_type in (
      'registration_prep_pre_trigger',
      'info_request_due',
      'warranty_expiry_warning',
      'trigger_confirmation_overdue',
      'service_report_response_due',
      'work_authorization_response_overdue',
      'ala_decline_window_expired',
      'ala_response_overdue',
      'warranty_id_early_issuance',
      'notice_of_defect_response_overdue'
    )
  );

alter table public.clock_events
  drop constraint clock_events_entity_type_check;

alter table public.clock_events
  add constraint clock_events_entity_type_check check (
    entity_type in (
      'project',
      'claim',
      'warranty_coverage',
      'work_authorization_document',
      'service_report',
      'ala_document',
      'warranty_registration',
      'notice_of_defect'
    )
  );

-- ---------------------------------------------------------------------------
-- notices_of_defect
-- ---------------------------------------------------------------------------
create table public.notices_of_defect (
  id                          uuid primary key default gen_random_uuid(),
  tenant_id                   uuid not null references public.tenants(id),
                              -- denormalized per Standard RLS Pattern.
  claim_id                    uuid not null
                                references public.claims(id) on delete restrict,
                              -- NO unique: one-to-many with claim (14.1).

  -- Recipient capture (the party put on notice).
  -- Decision 1's dual-FK + Snapshot Pattern, broadened by 14.2.
  recipient_contact_id        uuid
                                references public.contacts(id)
                                on delete restrict,
                              -- when the recipient is a subcontractor, vendor,
                              --   original installer, or other contact_type.
  recipient_user_id           uuid
                                references public.users(id) on delete restrict,
                              -- when the recipient is an internal team
                              --   assignee (Path 1 self-perform).
  recipient_name_snapshot     text not null,
                              -- frozen at notification time. The FK may drift
                              --   if the contact is later edited; the snapshot
                              --   cannot. This is who was actually notified.
  recipient_email_snapshot    text not null,
                              -- frozen: the address the notice actually went
                              --   to, which is the matter of record.
  recipient_company_snapshot  text,
                              -- frozen; nullable per the locked sketch (an
                              --   internal user has no company to snapshot).

  -- The notification event.
  notified_at                 timestamptz not null default now(),
                              -- THE MATTER-OF-RECORD MOMENT. This is the
                              --   column the entity exists for.
  notified_by_user_id         uuid not null
                                references public.users(id) on delete restrict,
                              -- the warranty professional who sent it.

  -- What was sent.
  claim_summary_snapshot      jsonb not null,
                              -- frozen snapshot of the claim information shared
                              --   with the recipient at notification (defect
                              --   description, relevant claim_type_data, etc.).
                              --   The internal shape is a flagged Phase 3
                              --   implementation detail; the column and its
                              --   NOT NULL are locked.
  notification_message        jsonb,
                              -- ProseMirror-compatible JSON per Decision 4;
                              --   the warrantor's custom message body
                              --   accompanying the claim summary (14.8).
                              --   Per-Notice, not per-tenant: there is no
                              --   template table here.

  -- Binding response capture (14.3).
  response_status             text not null default 'pending',
                              -- three values, exactly. Binding at the moment of
                              --   response -- but NOT closure-binding.
  response_at                 timestamptz,
  response_explanation        jsonb,
                              -- ProseMirror-compatible JSON; the recipient's
                              --   reasoning, particularly important for
                              --   rejections.

  -- Stateless Tokenized Interaction Pattern (14.5), sixth canonical use.
  -- Token on this row, not in invitations ("shape to copy, not shared store").
  recipient_token             text,
                              -- single-use; null after consumption.
  recipient_token_expires_at  timestamptz,

  -- Response deadline (14.7) -- drives clock event firing.
  expected_response_date      date not null,
                              -- NOT NULL: every Notice of Defect has a
                              --   warrantor-set deadline. 14.7 is explicit.

  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now(),
  constraint notices_of_defect_recipient_check check (
    (recipient_contact_id is not null) <> (recipient_user_id is not null)
  ),
  constraint notices_of_defect_response_status_check check (
    response_status in ('pending', 'accepted', 'rejected')
  )
);
create index notices_of_defect_tenant_id_idx
  on public.notices_of_defect (tenant_id);
create index notices_of_defect_claim_id_idx
  on public.notices_of_defect (claim_id);
create index notices_of_defect_recipient_contact_id_idx
  on public.notices_of_defect (recipient_contact_id)
  where recipient_contact_id is not null;
create index notices_of_defect_recipient_user_id_idx
  on public.notices_of_defect (recipient_user_id)
  where recipient_user_id is not null;
  -- partial: the XOR means each row populates exactly one. Same convention as
  -- 017's three partial entity-FK indexes.
comment on table public.notices_of_defect is
  'The warrantor''s formal notification to a believed-responsible party: "this '
  'defect is yours; respond with acceptance/rejection" (Decision 14). An AUDIT '
  'ARTIFACT OF OFFICIAL NOTIFICATION -- the purpose is that the party believed '
  'responsible has been officially notified and that is a matter of record, '
  'separate from any downstream execution work. v1 modeled this as two fields '
  'on the Work Plan; the Phase 1 audit flagged that as structurally wrong -- a '
  'Notice of Defect is a document sent to a party, with its own lifecycle, '
  'response, and audit trail. One-to-many with claims (14.1): zero when the '
  'defect is the warrantor''s own responsibility, many as the responsibility '
  'picture evolves. NO FK to work_plans in either direction (14.4): the '
  'Notice''s architectural responsibility ends at response capture, and some '
  'Notices never lead to a Work Plan at all.';
comment on column public.notices_of_defect.response_status is
  'Three values, exactly: pending | accepted | rejected (14.3). Binding at the '
  'moment of response, but NOT closure-binding -- a recipient may accept, get '
  'to site, and shift position. Such changes are NOT revisions to this column: '
  'they become NEW events (a new Notice to another party, a claim status '
  'transition, an escalation), each in its own section, and the historical '
  'record of the original response is preserved intact. That is why this entity '
  'has no revisions child table, deliberately unlike work_authorization_'
  'revisions (022) and ala_document_revisions (025). There is no ''withdrawn'' '
  'value: a matter of record is not un-sent.';
comment on column public.notices_of_defect.notified_at is
  'The matter-of-record moment -- the column this entity exists for. NOT NULL '
  'with a default: a row''s existence IS the notification having happened. '
  'Note there is no separate status column tracking sent-ness; the Notice''s '
  'own lifecycle is its response_status.';
comment on column public.notices_of_defect.recipient_contact_id is
  'Dual-FK recipient with an UNCONDITIONAL XOR (14.2): exactly one of '
  'recipient_contact_id / recipient_user_id is non-null. Deliberately differs '
  'from 010''s dual-FK assignee CHECK, which gates on status (both null when '
  'pre_activation) -- that conditionality is Decision 23.7''s four-state '
  'registration machine, which this entity has no analogue to. A Notice '
  'without a recipient is not a thing that exists. The `<>` idiom transfers '
  'from 010; the status gate does not. DO NOT HARMONIZE.';
comment on column public.notices_of_defect.recipient_name_snapshot is
  'FK + Snapshot (14.2, Decision 1 broadened). Frozen at notification time and '
  'never re-synced: the FK preserves the relationship for reporting, the '
  'snapshot preserves who was actually notified, at that address, on that date '
  '-- the entire audit-defensibility point of a matter-of-record '
  'notification. Same convention as inspections (021).';
comment on column public.notices_of_defect.expected_response_date is
  'NOT NULL per 14.7: every Notice of Defect has a warrantor-set response '
  'deadline. Drives notice_of_defect_response_overdue firing, which the Server '
  'Action that sends the notification schedules into clock_events.';
comment on column public.notices_of_defect.recipient_token is
  'Stateless Tokenized Interaction Pattern (14.5) -- the recipient receives a '
  'tokenized email link to respond, and needs no account. Stored on this row '
  'per the pattern''s "shape to copy, not shared store" rule, parallel to '
  'work_authorization_documents.customer_token (022) and '
  'ala_documents.claimant_token (025). Decision 14 calls this the sixth '
  'canonical use, as do Decisions 19 (ALA) and 28 (seventh, O&M): the ordinals '
  'collide because the decisions were drafted in different sessions. The '
  'collision is a numbering artifact, not a conflict -- each entity''s token '
  'columns are independently locked.';
comment on column public.notices_of_defect.claim_summary_snapshot is
  'Frozen snapshot of the claim information shared with the recipient at '
  'notification. The column and its NOT NULL are locked; the internal JSONB '
  'shape (which claim fields are captured) is a flagged Phase 3 implementation '
  'detail, same treatment as inspections.inspection_report (021) and '
  'work_authorization_revisions.field_changes (022).';

-- ---------------------------------------------------------------------------
-- Standard RLS Pattern (6-step)
-- ---------------------------------------------------------------------------
alter table public.notices_of_defect enable row level security;

create policy "notices_of_defect: tenant read"
  on public.notices_of_defect
  for select
  using (tenant_id = public.get_user_tenant_id());

-- Writes are service-role only: notification send, the recipient's tokenized
-- response, and response capture all run through Server Actions.

grant all on public.notices_of_defect to anon, authenticated, service_role;
