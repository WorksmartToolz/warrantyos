-- 027_claim_intake.sql
--
-- The Claim Intake Data Model: what gets captured when a customer files a claim
-- through the tokenized intake link. This is the operational data model layered
-- onto the Claim shell that migration 016 deliberately left bare.
--
-- 016's header is explicit about the boundary it was holding: "SCOPE: SHELL
-- ONLY. The intake data model is a SEPARATE Tier 3 section and is deliberately
-- NOT built here. Do not add intake form fields (hard columns or JSONB),
-- tokenized intake link columns, gate-level state columns, or a claimant
-- FK/snapshot." Three of those four are added here, by design -- this is the
-- section 016 was deferring to. The fourth (gate-level state) is NOT added; see
-- the omissions list.
--
-- Locked sources:
--   architecture-reference.md "Claim Intake Data Model" -- THE locked
--     specification: the hybrid strategy, the hard column set, the
--     claim_type_data JSONB mechanism, and the Replacement Parts shape.
--   Decision 20 (Phase 3 decisions log) -- 20.4 actor capture and contact_type
--     immutability; the submitter FK + Snapshot revision; 20.6's INFORMATIONAL
--     vs BINDING-COMMITMENT carving, which submitter_contact_id makes derivable.
--   Decision 27 -- 27.5/27.6 emergency carve-out. Governs is_emergency, already
--     built in 016. See THE NAMING COLLAPSE below.
--   Decision 4  -- rich text storage: ProseMirror-compatible JSON, 10,000-char
--     default cap, tenants.settings.rich_text_max_chars, 50,000 ceiling.
--   Decision 3  -- custom fields; entity_type = 'claim' is one of three Phase 1
--     entities. Already built (015/017). No work needed here.
--   Decision 12 -- Acknowledgment Gate; gate_purpose = 'claim_submission'
--     guards this intake form. Already built (023). No work needed here.
--   Decision 9  -- Stateless Tokenized Interaction Pattern's storage rule.
--
-- THE HYBRID STRATEGY IS THE WHOLE SHAPE OF THIS MIGRATION. Three mechanisms,
-- each for a different kind of variation:
--   * Hard columns    -- universal across every claim_type and every tenant.
--   * claim_type_data -- varies by claim_type. PLATFORM-shaped variation: every
--                        warrantor's Parts claim captures Part Name; the field
--                        name is fixed by the platform, no tenant config.
--   * custom fields   -- varies by tenant. TENANT-shaped variation: whether the
--                        field exists, what it is called, and its options are
--                        all the tenant's. Already built; nothing to do here.
-- The arch ref names the tell: "a platform-architecture field has a fixed name;
-- a tenant-configured field is named in the tenant's operational language."
--
-- THE NAMING COLLAPSE -- priority_emergency IS is_emergency. RESOLVED, DO NOT
-- RE-ADD. The arch ref's hard-column list carries `priority_emergency boolean
-- NOT NULL DEFAULT false`. Migration 016 already built `is_emergency boolean
-- not null default false` from Decision 27.5. Same field, two names, written
-- months apart -- the arch ref's Claim Intake section pre-dates Decision 27,
-- which is the newer locked source and uses is_emergency throughout. This
-- migration adds NO priority_emergency column: a second emergency flag could
-- disagree with the first, which is exactly the sync surface the architecture
-- refuses everywhere else. Confirmed with Andre in Chat 19. The intake form
-- writes is_emergency. emergency_details (below) is the rich-text companion the
-- arch ref pairs with it, and IS new.
--
-- WHAT IS DELIBERATELY NOT SETTLED HERE, and must not be "helpfully" settled:
-- six of the seven claim_type_data shapes. The arch ref settles Replacement
-- Parts from Workbook 2 and states plainly that billable_service_request,
-- design, equipment, foundation, tracker, and workmanship "are not yet settled
-- at the architectural layer. Each will be defined when its specific
-- operational requirements surface." That is deliberate restraint, the same
-- pattern as Section 7's specific conditions -- the architecture commits to the
-- MECHANISM (claim_type_data JSONB), the per-type contents are downstream
-- operational work. Critically, settling them later needs NO migration: JSONB
-- shape is validated app-layer.
--
-- SEVEN NOT NULL COLUMNS, ADDED WITH NO DEFAULT AND NO BACKFILL -- deliberate.
-- claim_type, date_of_defect_incident, equipment_status, loto_requirement,
-- detailed_description, submitter_name, submitter_email are NOT NULL exactly as
-- the arch ref specifies. They are required intake-form inputs: a claim cannot
-- exist without a type, a defect date, or a description of the defect. None has
-- an honest default -- a defaulted date_of_defect_incident would be a
-- fabricated fact about the customer's site.
--
-- `add column ... not null` with no default fails on a table with existing
-- rows. That is correct and wanted here. There is no draft state for a claim:
-- 016 built status not null default 'intake_received', meaning a claim row
-- exists only once intake completes, fully populated. In production the
-- database is empty at onboarding and awaits first entries, so there is nothing
-- to backfill; any rows present in a local dev DB are test data. Do NOT weaken
-- these to nullable, and do NOT invent defaults to make the migration apply
-- over test rows -- drop the test rows instead. Confirmed with Andre in Chat 19.
--
-- ON DELETE resolved from precedent:
--   submitter_contact_id -> RESTRICT. Contacts soft-delete (005); hard-deletion
--     is not an ordinary path. Matches 020's subcontractor_contact_id, 026's
--     recipient_contact_id, 021's snapshot-bearing contact FKs.
--
-- DELIBERATE OMISSIONS (documented so a future chat does not add them back):
--
--   - No priority_emergency column. See THE NAMING COLLAPSE above. This is the
--     one omission most likely to be "corrected" by someone reading the arch
--     ref literally. It is not an oversight.
--
--   - No claim_intake_tokens table. The arch ref flags "whether the intake
--     token is one column on the claim row or a separate claim_intake_tokens
--     table is a Phase 3 implementation detail" and closes it neither way.
--     Precedent closes it: the Stateless Tokenized Interaction Pattern's "shape
--     to copy, not shared store" rule has been applied three times, three times
--     identically, always as a token pair ON THE ENTITY ROW --
--     work_authorization_documents.customer_token (022),
--     ala_documents.claimant_token (025), notices_of_defect.recipient_token
--     (026). A fourth answer would be a new convention, not a build decision.
--
--   - No gate-level state columns. Decision 12's gate for gate_purpose =
--     'claim_submission' is an INTERSTITIAL on intake_token -- there is no
--     second token and no gate state on this table. 023 owns the gate's own
--     rows via its polymorphic authorized_entity_type = 'claim' /
--     authorized_entity_id pointing back at the claim this intake creates.
--     Same rule 022 and 025 already follow. 016's header names "gate-level
--     state columns" as a deliberate omission and it STAYS one.
--
--   - No FK for the O&M Provider capture. This is the one place the arch ref
--     reads like it is announcing an answer when it is only proposing one. Its
--     open-questions block says the FK "is the architecturally consistent
--     answer: an om_provider_contact_id FK to contacts." But 022's committed
--     header states the governing position directly: "No O&M provider FK.
--     Direct field capture (om_provider_company through om_contact_email) is
--     Decision 11's locked schema, PARALLELING CLAIM INTAKE. Any future move to
--     FK + Snapshot warrants its own decision." No such decision exists.
--     Committed precedent that names this very section as its parallel beats an
--     unresolved flag in an open-questions list. Direct text, matching 022's
--     four columns exactly. If operational pressure surfaces for the FK, it is
--     its own decision -- for BOTH tables, together.
--
--   - No claim_attachments child table. supporting_documents is JSONB. The arch
--     ref flags this one honestly as "genuinely a JSONB-vs-child-table choice --
--     the data is a list of uniform items, exactly the case child tables handle
--     well," and no precedent in the repo resolves it (every other JSONB here is
--     rich text, config, or snapshot). Resolved on the locked SEMANTICS: the
--     column stores "the multi-select of document categories the claimant
--     DECLARES they are providing." It is a declaration checklist -- a set of
--     enum values -- not an attachment store. No file, no URL, no per-item
--     metadata, no join surface. The child-table argument imagines "each row is
--     one document with its category"; the locked semantics store no documents.
--     Actual file storage is unaddressed anywhere in v1. If v1 later stores
--     files, that is a new entity, not a widening of this column. Confirmed
--     with Andre in Chat 19.
--
--   - No change to the status CHECK. It stays at exactly one value,
--     'intake_received'. The Six Gates value set is the Tier 3 claim lifecycle
--     section, which is NOT drafted. 016's header calls the one-value CHECK
--     "the architecturally honest shell-scope read, not an oversight" -- filing
--     a claim IS intake_received, so this section needs no other value.
--
--   - No DB CHECK coupling emergency_details to is_emergency, or
--     offline_condition_explanation to equipment_status = 'offline'. The arch
--     ref marks both conditional in prose ("present only when..."). 17.A.6 caps
--     v1 DB enforcement; app-layer. Identical restraint to 016's own refusal to
--     CHECK emergency_stabilized_at against is_emergency (Decision 27.6), and
--     to 022's special_access_details / gate_code_details.
--
--   - No DB validation of claim_type_data against the row's claim_type. The
--     arch ref is explicit: "Validation of claim_type_data against the expected
--     shape for the row's claim_type happens application-layer at write time...
--     The database does not enforce per-claim_type JSONB shape -- that's the
--     same convention used for clock_events payload validation."
--
--   - No customer / project / WarrantyID / service-address columns. Workbook 1
--     lists five fields as auto-populated from the parent WarrantyID. NONE
--     become claim columns. Each is already reachable: WarrantyID via
--     warranty_registration_id -> warranty_registrations.warranty_id; Customer
--     and Project name via warranty_registrations.project_id -> projects;
--     Service Address via projects.site_address_*. The arch ref: "Duplicating
--     these on the claim would create sync surfaces where none is needed;
--     reading them is a join, not a column."
--
--   - No claim-time snapshot of registration or project state. The arch ref
--     flags it as a Phase 4 / downstream question "not raised by any locked
--     source." Auto-populated does not mean immutable -- reads reflect current
--     parent state by design.
--
--   - No UNIQUE on intake_token. 001's invitations.token is unique, but that is
--     a shared-store table where the token IS the lookup key. Under "shape to
--     copy, not shared store" the per-row tokens (022/025/026) carry no UNIQUE.
--     Follow the three, not the one.
--
--   - No clock_events enum extension. Nothing in this section schedules a
--     future-firing event. Unlike 026, no alter table is needed.
--
-- APP-LAYER INVARIANTS (deliberately not DB constraints):
--   - claim_type_data's shape matches the row's claim_type.
--   - emergency_details is present when is_emergency = true;
--     offline_condition_explanation is present when equipment_status =
--     'offline'.
--   - submitter_name / submitter_email are snapshots captured at submission and
--     never re-synced from submitter_contact_id, which may drift.
--   - contact_type immutability (Decision 20.4): a contact whose operational
--     role changes gets a NEW row, never an UPDATE. This discipline is what
--     makes "derivable, not stored" sound across time -- the actor's
--     contact_type at query time equals their contact_type at action time. It
--     is what lets 20.6's INFORMATIONAL vs BINDING-COMMITMENT carving be read
--     off submitter_contact_id instead of stored on the claim.
--   - Rich text char caps (Decision 4) apply to detailed_description,
--     emergency_details, and offline_condition_explanation.
--   - The Acknowledgment Gate, when a tenant has configured one for
--     gate_purpose = 'claim_submission', renders as the first screen of the
--     intake_token link before the form.

-- ---------------------------------------------------------------------------
-- Hard columns: universal across every claim_type and every tenant.
-- ---------------------------------------------------------------------------
alter table public.claims
  add column claim_type                    text not null,
  add column date_of_defect_incident       date not null,
  add column emergency_details             jsonb,
  add column equipment_status              text not null,
  add column offline_condition_explanation jsonb,
  add column loto_requirement              text not null,
  add column required_docs_provided        boolean not null default false,
  add column supporting_documents          jsonb,
  add column detailed_description          jsonb not null,
  add column submitter_contact_id          uuid
                                             references public.contacts(id)
                                             on delete restrict,
  add column submitter_name                text not null,
  add column submitter_email               text not null,
  add column om_provider_company           text,
  add column om_contact_name               text,
  add column om_contact_phone              text,
  add column om_contact_email              text,
  add column ship_to_street                text,
  add column ship_to_city                  text,
  add column ship_to_state                 text,
  add column ship_to_zip                   text,
  add column recipient_name                text,
  add column recipient_phone               text,
  add column claim_type_data               jsonb,
  add column intake_token                  text,
  add column intake_token_expires_at       timestamptz;

-- ---------------------------------------------------------------------------
-- CHECK constraints on the three closed enums.
-- ---------------------------------------------------------------------------
-- The arch ref marks claim_type, equipment_status, and loto_requirement as
-- CHECK-enforced. This is v1 DB enforcement of closed value sets -- squarely
-- inside what 17.A.6 permits, and the same treatment 016 gives status,
-- 022 gives customer_decision, and 026 gives response_status.

alter table public.claims
  add constraint claims_claim_type_check check (
    claim_type in (
      'billable_service_request',
      'design',
      'equipment',
      'foundation',
      'replacement_parts',
      'tracker',
      'workmanship'
    )
  );

alter table public.claims
  add constraint claims_equipment_status_check check (
    equipment_status in ('online', 'offline')
  );

alter table public.claims
  add constraint claims_loto_requirement_check check (
    loto_requirement in (
      'not_required',
      'required_claimant_responsible',
      'required_warrantor_responsible'
    )
  );

-- ---------------------------------------------------------------------------
-- Indexes.
-- ---------------------------------------------------------------------------
-- Partial, matching 026's convention for a nullable FK: only rows with a known
-- submitter populate it. The lookup this serves is Decision 20.6's carving --
-- "was this claim filed by an authorized agent or by the customer directly?"
create index claims_submitter_contact_id_idx
  on public.claims (submitter_contact_id)
  where submitter_contact_id is not null;

-- Token lookup on every tokenized intake link click.
create index claims_intake_token_idx
  on public.claims (intake_token)
  where intake_token is not null;

-- ---------------------------------------------------------------------------
-- Column comments.
-- ---------------------------------------------------------------------------
comment on column public.claims.claim_type is
  'The seven values come from Workbook 1''s dropdown directly. Extensible: '
  'adding a claim_type is a migration that updates this CHECK, the '
  'claim_type_data shape for the new type, and its UI affordances.';

comment on column public.claims.claim_type_data is
  'Per-claim_type structured fields -- the hybrid strategy''s PLATFORM-shaped '
  'variation (contrast custom_field_values, which is TENANT-shaped). JSONB is '
  'locked here, NOT flagged as a possible child table like supporting_documents '
  'is: variable-schema-by-discriminator is the case JSONB is designed for, the '
  'fields do not decompose into uniform child rows, and a polymorphic child '
  'table per claim_type would multiply the schema rather than encapsulate the '
  'variation. Only the replacement_parts shape is settled (Workbook 2): '
  'part_name, row_number, row_controller_asset_id, description_of_issue, '
  'customer_comments (rich text). The other six shapes are DELIBERATELY not '
  'settled at the architectural layer and need no migration when they are -- '
  'shape is validated app-layer at write time, same convention as '
  'clock_events.payload.';

comment on column public.claims.loto_requirement is
  'Three values covering the three real business shapes. Workbook 1 '
  '(supply-only) listed two; the platform-general schema extends to three to '
  'cover warrantors who self-perform LOTO. The industry default for '
  'system-owner-installed projects is required_claimant_responsible. Detail '
  'BEYOND this categorical answer -- who specifically performs LOTO, contact '
  'info, authorization details -- is tenant-shaped and lives in custom fields '
  '(Decision 3, entity_type = ''claim''), not here. Same subject, different '
  'mechanism, because the variation is at a different level.';

comment on column public.claims.emergency_details is
  'ProseMirror-compatible JSON (Decision 4). The rich-text companion to '
  'is_emergency, present only when it is true -- app-layer, NOT a DB CHECK '
  '(17.A.6). NOTE: the arch ref names the boolean priority_emergency; that is '
  'the older label for is_emergency, which 016 already built from Decision '
  '27.5. One flag, not two. No priority_emergency column exists or should.';

comment on column public.claims.supporting_documents is
  'The multi-select of document CATEGORIES the claimant declares they are '
  'providing -- a declaration checklist, not an attachment store. No file, no '
  'URL, no per-item metadata, no join surface. The arch ref flags '
  'JSONB-vs-child-table here honestly (unlike claim_type_data, where JSONB is '
  'locked outright); resolved as JSONB on the locked semantics, because the '
  'child-table argument imagines storing documents and this column stores '
  'declarations. Actual file storage is unaddressed anywhere in v1 -- if it '
  'lands, it is a new entity, not a widening of this column.';

comment on column public.claims.submitter_contact_id is
  'FK + Snapshot (Decision 20). Nullable: null when the submitter is a one-off '
  'third party not in the contacts directory, in which case the snapshot '
  'columns are the only record and agency role cannot be derived. When '
  'populated, downstream workflows traverse to the contact''s contact_type to '
  'derive whether the claim was filed by the customer, a customer_contact, an '
  'O&M Provider (subject to Decision 20.6''s INFORMATIONAL vs '
  'BINDING-COMMITMENT carving), or another party. This shape resolves the '
  'chat-4-identified traceability gap in Decision 20.4. Soundness across time '
  'depends on contact_type immutability (20.4): a role change creates a NEW '
  'contact row, never an UPDATE.';

comment on column public.claims.submitter_name is
  'Snapshot at submission, NOT re-synced from submitter_contact_id, which may '
  'drift. Populated regardless of whether the FK is set. Same '
  'never-re-sync convention as 026''s recipient_name_snapshot and 021''s.';

comment on column public.claims.om_provider_company is
  'Direct text capture, NOT an FK -- the four om_* columns mirror 022''s '
  'om_provider_company / om_contact_name / om_contact_phone / om_contact_email '
  'exactly. The arch ref''s open-questions block PROPOSES an '
  'om_provider_contact_id FK and does not lock it; 022''s committed header '
  'states the governing position and names Claim Intake as its parallel: '
  '"Direct field capture ... is Decision 11''s locked schema, paralleling Claim '
  'Intake. Any future move to FK + Snapshot warrants its own decision." No such '
  'decision exists. If it lands, it lands for BOTH tables together.';

comment on column public.claims.intake_token is
  'Stateless Tokenized Interaction Pattern. The customer receives a tokenized '
  'email link to a focused intake form -- no account, no session persistence '
  'beyond the link. Stored on this row per "shape to copy, not shared store", '
  'parallel to work_authorization_documents.customer_token (022), '
  'ala_documents.claimant_token (025), notices_of_defect.recipient_token (026). '
  'The arch ref leaves row-column-vs-claim_intake_tokens-table open; three '
  'identical precedents close it. No UNIQUE, matching those three -- '
  'invitations.token (001) is unique because it is a SHARED STORE where the '
  'token is the lookup key; that is the shape this pattern explicitly does not '
  'copy. When a tenant has configured an Acknowledgment Gate for gate_purpose '
  '= ''claim_submission'' (Decision 12), that gate is an INTERSTITIAL on THIS '
  'token -- there is no second token and no gate state on this table.';

comment on column public.claims.detailed_description is
  'ProseMirror-compatible JSON (Decision 4) -- one rich-text storage convention '
  'platform-wide, not two. Cap defaults: 10,000 effective characters, '
  'per-tenant configurable DOWNWARD via tenants.settings.rich_text_max_chars, '
  'hard platform ceiling 50,000.';

comment on column public.claims.ship_to_street is
  'Four scalars following projects.site_address_* for consistency. Whether '
  'this is the right level of structure -- or whether the project address '
  'pattern itself needs revision for geocoding or international formats -- is '
  'a future decision, not raised by any locked source.';
