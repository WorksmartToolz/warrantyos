-- 025_ala_system.sql
--
-- The ALA System: the Owner's Consent and Assumption of Liability Agreement.
-- The document a claimant signs when a claim's causation or ownership is
-- unclear, accepting financial responsibility for the investigation if the
-- defect is ultimately found to be outside warranty scope.
--
-- The SOPs name this the "Indistinct Claims" workflow; v1's Six Final Outcomes
-- lists "Indistinct Claim -- ALA Required" as one of the six review outcomes.
-- An ALA document exists only when a claim's outcome is Indistinct; most claims
-- never have one.
--
-- Three tables, parent-child-revisions:
--   ala_templates           -- tenant-defined reusable agreement configuration
--   ala_documents           -- one claim's instantiation, frozen content
--                              snapshot + the claimant's decision + signature
--   ala_document_revisions  -- full history of warrantor content changes
--
-- Locked sources:
--   architecture-reference.md "ALA System" -> both schema sketches, the
--     three-state model, the signature mechanism columns, the token columns,
--     the deliberate-omissions list.
--   Decision 7  - markup default 10% (decimal 0.10), stored at
--     tenants.settings.ala_markup_percent, app-layer bounds 0 to 0.50.
--   Decision 19 - signature capture mechanism; ten architectural commitments.
--   Decision 25 - response window, overdue flag, re-issue. Adds
--     overdue_flagged_at to this table.
--   Decision 26 - revise-and-resend; ala_document_revisions.
--   Decision 4  - rich text storage: ProseMirror-compatible JSON.
--
-- ONE-TO-ONE WITH CLAIMS -- UNIQUE on claim_id, and Decision 26.2 explicitly
-- REFUSES TO REOPEN IT. A claim either is Indistinct and has exactly one ALA,
-- or is not Indistinct and has none. This is the deliberate contrast against
-- work_authorization_documents (022) and work_plans (020), which are
-- one-to-many: the scope differs. ALA authorizes financial liability for the
-- claim's investigation -- once per Indistinct outcome. Work Authorization
-- authorizes physical site presence for a bounded event, which recurs.
-- Revise-and-resend (Decision 26) is how content changes without a second row.
--
-- NO status COLUMN -- deliberate, per Decision 19.7. The three-state machine is
-- DERIVED from (claimant_decision, signed_at):
--   unsigned  -> claimant_decision IS NULL AND signed_at IS NULL
--   signed    -> claimant_decision = 'accepted' AND signed_at IS NOT NULL
--   declined  -> claimant_decision = 'declined' AND signed_at IS NULL
-- unsigned / signed / declined remain the complete state set. Do not add a
-- status column; the locked sketch carries none and the states are computable.
--
-- overdue_flagged_at (Decision 25.4) is a FOURTH ORTHOGONAL SIGNAL layered on
-- top of the unsigned state -- NOT a fourth state. It is a pure marker: it does
-- not change claimant_decision or signed_at, and it does not unblock the
-- Indistinct blocking gate (19.7). Note: this column is named in Decision 25.4
-- in PROSE ONLY -- the arch ref's ala_documents sketch (19 columns) predates it
-- and does not carry it. This table has 20 columns.
--
-- ON DELETE resolved at build time, all from precedent:
--   documents.claim_id            -> RESTRICT. The arch ref defers only the
--     clause, calling it "parallel to other claim-child FK flags". Those
--     parallels are 010/016/020/021/022 -- all RESTRICT. Every parent
--     soft-deletes; hard-deletion is not an ordinary path.
--   documents.template_id         -> RESTRICT. Templates soft-delete and their
--     documents must stay readable; the arch ref says so explicitly ("template
--     may be soft-deleted later but the FK remains valid because of
--     soft-delete"). Parallel to 022's template_id, 023's template_id, and
--     017's definition_id.
--   revisions.ala_document_id     -> CASCADE. A revision is a dependent
--     attribute of its document, not an independent record -- 017's entity-FK
--     reasoning. Identical shape to 022's work_authorization_document_id.
--     Deliberately differs from the RESTRICTs above: different relationship,
--     different answer.
--   revisions.revised_by_user_id  -> RESTRICT. Tenant users soft-remove
--     (removed_at); matches 022's and 020's user FKs.
--
-- DELIBERATE OMISSIONS (documented so they are not "helpfully" added later):
--
--   - No status column. See above -- Decision 19.7's three states are derived.
--   - No counter-signature column. The arch ref is explicit that the ALA is
--     one-sided consent: the claimant assumes liability; the warrantor does not
--     counter-sign. Adding a warrantor signature would change the instrument.
--   - No partial UNIQUE index on (tenant_id) WHERE is_default. The arch ref
--     offers partial-UNIQUE or app-layer and picks neither ("a Phase 3
--     implementation detail"); 17.A.6 caps v1 DB enforcement. This is the THIRD
--     parallel is_default flag -- 022's and 023's face the identical question
--     and were both answered app-layer. Three parallel flags, one answer.
--   - No DB CHECK for "claimant_decision = 'accepted' implies signed_at IS NOT
--     NULL". The arch ref names it an application invariant enforced through
--     the Server Actions (Decision 19.1's atomic accept-and-signature write);
--     17.A.6 caps v1 DB enforcement. Same restraint as 022's
--     denial_explanation and 016's emergency_stabilized_at.
--   - No DB CHECK coupling signature_image_url to signature_method =
--     'in_platform_widget', or esignature_envelope_id to 'esignature_service'.
--     Conditional per the arch ref's prose; app-layer, same reasoning.
--   - No created_at/updated_at on revisions. The locked 26.1 sketch carries
--     revised_at only. Built verbatim -- an applying table does not vary the
--     locked column set. Same as 022's revisions.
--   - No deleted_at on ala_documents. The locked sketch carries none: an ALA is
--     an audit-bearing legal artifact for the warranty horizon, and Decision 26
--     makes revise-in-place the content-change path. Templates soft-delete;
--     documents do not.
--   - No deleted_at on revisions. Frozen audit artifacts. Same as 022's.
--   - No custom field involvement. Templates are tenant-defined documents, not
--     custom field definitions on the claim (arch ref, "What is NOT in the ALA
--     system").
--   - No DB enforcement of the markup bounds (0 to 0.50). Decision 7 places
--     that validation in the application layer; the Server Action that updates
--     tenants.settings.ala_markup_percent is the gate. The numeric(4,3) type
--     constrains precision, not the architectural bounds.
--   - No clock_events row created here. The ala_response_overdue event is
--     inserted by the Server Action at ALA creation/routing time (Decision
--     25.1), per Decision 9's convention that clock_events is for
--     future-firing events scheduled by the action that causes them.
--     clock_events (013) ALREADY carries entity_type 'ala_document' and
--     event_types 'ala_response_overdue' and 'ala_decline_window_expired'.
--     No alter table migration is needed.
--   - No second token for an Acknowledgment Gate. Same rule as 022: a gate is
--     an interstitial on claimant_token, not its own tokenized interaction.
--   - No holiday FK. Business-day math (Decision 25.2's tenant-configurable
--     window, default 7) reads tenant_holidays (024) application-layer at the
--     moment fires_at is computed, producing a concrete stored timestamp. No
--     operational table references a holiday by FK -- which is exactly why 025
--     and 024 are separate migrations.
--
-- APP-LAYER INVARIANTS (deliberately not DB constraints):
--   - tenant_id matches the referenced claim's tenant_id (documents) and the
--     parent document's tenant_id (revisions).
--   - claimant_decision = 'accepted' implies signed_at IS NOT NULL (19.1).
--   - At most one is_default = true template per tenant.
--   - decided_at is non-null when claimant_decision is non-null.
--   - decline_reason is populated only when claimant_decision = 'declined'.
--   - markup_percent_snapshot falls within Decision 7's 0 to 0.50 bounds.
--   - Revising a signed ALA is blocked (26.4).
--   - The Indistinct blocking gate: an unsigned ALA blocks the claim's
--     progression, and overdue_flagged_at does not unblock it (19.7, 25.4).

-- ---------------------------------------------------------------------------
-- ala_templates
-- ---------------------------------------------------------------------------
create table public.ala_templates (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.tenants(id),
              -- denormalized per Standard RLS Pattern.
  name        text not null,
  content     jsonb not null,
              -- the template's body, ProseMirror-compatible JSON per
              --   Decision 4; the same rich-text convention as
              --   detailed_description on claims and rich-text custom fields.
              --   The stored JSON outlives any specific editor library.
  is_default  boolean not null default false,
              -- at most one default per tenant; app-layer.
  deleted_at  timestamptz,
              -- soft-delete REQUIRED, not optional: a template retired today
              --   may have generated a document last year, and that document
              --   must remain readable for audit defensibility over the
              --   warranty horizon.
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index ala_templates_tenant_id_idx
  on public.ala_templates (tenant_id);
comment on table public.ala_templates is
  'Tenant-defined reusable configuration for the Owner''s Consent and '
  'Assumption of Liability Agreement (Decision 19). A tenant has one or more '
  'templates; Phase 1 likely has one default per tenant, with multiple '
  'templates supporting warrantors who use different agreement variants for '
  'different claim types or jurisdictions. Same templates-and-documents shape '
  'as Customer Work Authorization (022) and the Acknowledgment Gate Pattern '
  '(023). The platform stores template content and any tenant-supplied '
  'document-number identifier, but does not reserve or assign document numbers '
  'itself -- numbering is data, not architecture. This section does NOT specify '
  'the legal form of the agreement: that content is warrantor-specific.';
comment on column public.ala_templates.is_default is
  'At most one is_default = true per tenant is the architectural intent. '
  'Enforcement is app-layer: the arch ref offers partial-UNIQUE or app-layer '
  'and picks neither, and Decision 17.A.6 caps v1 DB enforcement. The third '
  'parallel flag, after work_authorization_templates (022) and '
  'acknowledgment_gate_templates (023) -- identical question, identical answer.';

-- ---------------------------------------------------------------------------
-- ala_documents
-- ---------------------------------------------------------------------------
create table public.ala_documents (
  id                         uuid primary key default gen_random_uuid(),
  tenant_id                  uuid not null references public.tenants(id),
                             -- denormalized per Standard RLS Pattern.
  claim_id                   uuid not null unique
                               references public.claims(id) on delete restrict,
                             -- UNIQUE enforces 1:1. Decision 26.2 explicitly
                             --   refuses to reopen this: one row per claim,
                             --   always; content changes are child revisions.
  template_id                uuid not null
                               references public.ala_templates(id)
                               on delete restrict,
                             -- the template this document was generated from.
                             --   Templates soft-delete, so the FK stays valid.
  content_snapshot           jsonb not null,
                             -- the template content frozen at generation. The
                             --   document the claimant signed must read
                             --   identically in twenty years even if the
                             --   template was updated, retired, or
                             --   restructured. template_id preserves the
                             --   relationship for reporting; content_snapshot
                             --   preserves the historical truth.
  markup_percent_snapshot    numeric(4,3) not null,
                             -- the tenant's ala_markup_percent (Decision 7:
                             --   default 0.10) frozen at generation. What the
                             --   claimant agreed to, not current config.
                             --   Bounds 0 to 0.50 are app-layer per Decision 7.

  -- Signer identity. Free-text snapshot, not FK + Snapshot -- the same question
  -- Claim Intake settled for the submitter, with the same answer: a signer may
  -- be a customer contact or a one-off third party, the FK is too heavy for the
  -- operational shape. Revisitable if reporting needs argue otherwise.
  signer_name                text,
  signer_email               text,
  signed_at                  timestamptz,
                             -- null until signed. Non-null is the
                             --   architectural marker of "ALA in force",
                             --   refined by Decision 19.7's three-state model.

  -- Decision capture (Decision 19.2). The signer columns capture WHO signed and
  -- WHEN; these capture WHAT they decided. Complementary, not redundant.
  claimant_decision          text,
                             -- null until the claimant responds.
  decided_at                 timestamptz,
                             -- the Accept/Decline click moment. In the happy
                             --   path near-identical to signed_at, because
                             --   19.1's atomic commitment requires both within
                             --   a single Server Action write. Kept
                             --   semantically distinct so downstream code can
                             --   read whichever it needs.
  decline_reason             text,
                             -- optional free-text context; populated only when
                             --   claimant_decision = 'declined'. App-layer.

  -- Signature mechanism (Decisions 19.3 / 19.4 / 19.5).
  signature_method           text not null default 'in_platform_widget',
                             -- captured at row creation from the tenant's
                             --   ala_signature_method setting and FROZEN for
                             --   the document's lifetime, so historical
                             --   documents retain their mechanism even if the
                             --   tenant changes the setting later.
  signature_image_url        text,
                             -- URL reference to Supabase Storage under a
                             --   tenant-scoped path; populated only when the
                             --   in_platform_widget canvas sub-path was used
                             --   AND signed_at is non-null. URL-reference
                             --   rather than bytea: aligns with platform
                             --   patterns for other binary data and keeps
                             --   backups, replication, and TOAST overhead
                             --   sane. App-layer conditional.
  esignature_envelope_id     text,
                             -- e-signature service envelope/document ID;
                             --   populated only when signature_method =
                             --   'esignature_service' AND signed_at non-null.

  overdue_flagged_at         timestamptz,
                             -- Decision 25.4. Set when ala_response_overdue
                             --   fires and claimant_decision is still null.
                             --   A PURE MARKER: does not change
                             --   claimant_decision or signed_at, and does NOT
                             --   unblock the Indistinct blocking gate (19.7).
                             --   Cleared by re-issue (25.7) or revise (26.3).
                             --   NOT in the arch ref's schema sketch -- named
                             --   in Decision 25.4's prose. This is the column
                             --   that makes 20, not 19.

  -- Stateless Tokenized Interaction Pattern: token on this row, not in
  -- invitations ("shape to copy, not shared store"). Parallel to 022.
  claimant_token             text,
  claimant_token_expires_at  timestamptz,

  created_at                 timestamptz not null default now(),
  updated_at                 timestamptz not null default now(),
  constraint ala_documents_claimant_decision_check check (
    claimant_decision in ('accepted', 'declined')
  ),
  constraint ala_documents_signature_method_check check (
    signature_method in ('in_platform_widget', 'esignature_service')
  )
);
create index ala_documents_tenant_id_idx
  on public.ala_documents (tenant_id);
create index ala_documents_template_id_idx
  on public.ala_documents (template_id);
-- No separate claim_id index: the UNIQUE constraint's backing index serves it.
comment on table public.ala_documents is
  'One claimant''s Owner''s Consent and Assumption of Liability Agreement for '
  'one Indistinct claim (Decision 19). Exists ONLY when a claim''s outcome is '
  'Indistinct -- most claims never have one. UNIQUE on claim_id enforces 1:1 '
  'and Decision 26.2 explicitly refuses to reopen it: a claim either is '
  'Indistinct and has exactly one ALA, or is not Indistinct and has none. The '
  'deliberate contrast against work_authorization_documents (022), which is '
  'one-to-many because it authorizes a bounded, recurring on-site event; an ALA '
  'authorizes financial liability for the claim''s investigation, once. '
  'Content changes go through revise-and-resend (026), never a second row.';
comment on column public.ala_documents.claimant_decision is
  'Half of the DERIVED three-state machine (Decision 19.7). There is '
  'deliberately NO status column: unsigned = claimant_decision IS NULL AND '
  'signed_at IS NULL; signed = ''accepted'' AND signed_at IS NOT NULL; '
  'declined = ''declined'' AND signed_at IS NULL. These three are the complete '
  'state set. The app-layer invariant that ''accepted'' implies signed_at '
  'non-null follows from Decision 19.1''s atomic accept-and-signature write; '
  'it is enforced in the Server Action, not by a DB CHECK (17.A.6).';
comment on column public.ala_documents.overdue_flagged_at is
  'Decision 25.4: a FOURTH ORTHOGONAL SIGNAL layered on top of the unsigned '
  'state -- NOT a fourth state. Set by the clock dispatcher when '
  'ala_response_overdue fires with claimant_decision still null (25.5); the '
  'claimant is emailed that the window closed with no decision made, and no '
  'decision is recorded. Silence never becomes a decision (25.8): there is no '
  'auto-terminal state. It persists until the warrantor re-issues (25.7) or '
  'escalates manually. Does not unblock the Indistinct gate.';
comment on column public.ala_documents.signature_method is
  'Decision 19.3. Platform-locked CHECK enum WITH a default, captured at row '
  'creation from the tenant''s ala_signature_method setting and frozen for the '
  'document''s lifetime. in_platform_widget is the accessibility-compliant '
  'default path; esignature_service routes to an external provider. The '
  'mechanism-specific artifact lands in signature_image_url or '
  'esignature_envelope_id respectively -- both conditional, both app-layer.';
comment on column public.ala_documents.claimant_token is
  'Stateless Tokenized Interaction Pattern (Decision 19.8), stored on this row '
  'per the pattern''s "shape to copy, not shared store" rule -- parallel to '
  'work_authorization_documents.customer_token (022). Per-row token '
  'regeneration handles expiry recovery: the warrantor updates both token '
  'columns on the existing row, and the document''s state combination '
  '(claimant_decision, signed_at) is preserved across regeneration.';
comment on column public.ala_documents.markup_percent_snapshot is
  'Decision 7: the tenant''s ala_markup_percent (default 0.10, stored at '
  'tenants.settings.ala_markup_percent) frozen at document generation. A '
  'tenant who changes their markup later does not retroactively change '
  'documents already generated. The 0 to 0.50 validation bounds are app-layer: '
  'the numeric(4,3) type constrains precision, not the architectural bounds. '
  'v1''s 15% figure was checked against all six claim intake workbooks during '
  'drafting and confirmed unsourced; Decision 7''s 10% stands.';

-- ---------------------------------------------------------------------------
-- ala_document_revisions
-- ---------------------------------------------------------------------------
create table public.ala_document_revisions (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references public.tenants(id),
                      -- denormalized per Standard RLS Pattern.
  ala_document_id     uuid not null
                        references public.ala_documents(id) on delete cascade,
                      -- a revision is a dependent attribute of its document,
                      --   not an independent record.
  revised_by_user_id  uuid not null
                        references public.users(id) on delete restrict,
                      -- the warrantor user who made the revision.
  revision_reason     jsonb not null,
                      -- ProseMirror-compatible JSON; why the content changed
                      --   (new findings, revised scope).
  field_changes       jsonb not null,
                      -- structured before/after record. The exact JSONB shape
                      --   is a flagged Phase 3 implementation detail; the
                      --   column and its NOT NULL are locked.
  revised_at          timestamptz not null default now()
);
create index ala_document_revisions_tenant_id_idx
  on public.ala_document_revisions (tenant_id);
create index ala_document_revisions_document_id_idx
  on public.ala_document_revisions (ala_document_id);
comment on table public.ala_document_revisions is
  'Full history of warrantor content changes to one ALA document (Decision '
  '26), resolving the revise-and-resend question Decision 19 deferred: '
  'operational pressure surfaced a need to update an ALA''s content (new '
  'findings, revised scope) without creating a second ala_documents row, which '
  'UNIQUE(claim_id) forbids and continues to forbid (26.2). Distinct from '
  'Decision 25''s re-issue: re-issue resends the SAME content after '
  'non-response; revise-and-resend changes the content because circumstances '
  'changed. The revise action (26.3) updates the row in place, logs prior state '
  'here, clears overdue_flagged_at, regenerates the token, and resends. '
  'Revising a SIGNED ALA is blocked at v1 (26.4) -- the gate is already cleared '
  'on the strength of that signature, and revising accepted terms is a '
  'materially different problem; mirrors the O&M provider blocking convention '
  '(20.6/20.7). Structurally identical to work_authorization_revisions (022) '
  'and built verbatim to the locked 26.1 sketch: revised_at only, no '
  'created_at/updated_at, no soft-delete.';

-- ---------------------------------------------------------------------------
-- Standard RLS Pattern (6-step) -- all three tables
-- ---------------------------------------------------------------------------
alter table public.ala_templates enable row level security;

create policy "ala_templates: tenant read"
  on public.ala_templates
  for select
  using (tenant_id = public.get_user_tenant_id());

alter table public.ala_documents enable row level security;

create policy "ala_documents: tenant read"
  on public.ala_documents
  for select
  using (tenant_id = public.get_user_tenant_id());

alter table public.ala_document_revisions enable row level security;

create policy "ala_document_revisions: tenant read"
  on public.ala_document_revisions
  for select
  using (tenant_id = public.get_user_tenant_id());

-- Writes are service-role only: document generation at the Indistinct outcome,
-- the claimant's tokenized Accept/Decline + atomic signature write, the
-- dispatcher's overdue flagging, re-issue, and revision capture all run through
-- Server Actions.

grant all on public.ala_templates to anon, authenticated, service_role;
grant all on public.ala_documents to anon, authenticated, service_role;
grant all on public.ala_document_revisions to anon, authenticated, service_role;
