-- 029_customer_om_authorization.sql
--
-- The Customer-O&M Authorization: the customer's signed authorization for an
-- O&M Provider to act as their agent on ONE specific binding-commitment event
-- (an ALA acceptance, a Work Authorization approval, or a Service Report
-- review). Per-event, not standing: authorization is sign-once-per-event and
-- closes when that event closes. It does NOT persist across subsequent events,
-- even for the same customer and the same O&M relationship on the same day.
--
-- Locked source:
--   Decision 28 (Phase 3 decisions log) -- THE locked architectural
--     specification: ten commitments (28.1-28.10) plus the two schema
--     sketches, built verbatim here. The architecture reference has NO
--     Customer-O&M Authorization section; per Chat 18's Notice-of-Defect
--     precedent, none is written -- the decisions log holds the locked spec,
--     this migration header carries the rationale, PROJECT-MAP records the gap.
--     Writing an arch-ref section would be design-era work.
--   Decision 1  -- Stateless Tokenized Interaction Pattern (28.9's token pair).
--   Decision 4  -- rich text storage: ProseMirror-compatible JSON.
--   Decision 11 -- the polymorphic event_type + event_reference_id shape this
--     reuses (28.1); 022's committed bytes are the build precedent.
--   Decision 19 -- signature-capture mechanism reused (28.8): in_platform_widget
--     with typed-name fallback. signer_name_typed is that fallback artifact.
--   Decisions 20.3 / 20.7 / 20.8 -- 20.8's standing-document scope is SUPERSEDED
--     by Decision 28's per-event model. 20.3's single-FK linked_om_provider_id
--     on the customer row is what 28.6's handoff rule reads from.
--
-- SUPERSESSION NOTE (28 context). Decision 20.8 originally scoped this as a
-- STANDING per-customer authorization with a four-state machine
-- (unsigned/signed/voided/superseded), a separate voiding mechanic, and a
-- separate audit-trail table. Decision 28 is a substantive scope DEPARTURE, not
-- a refinement: per-event authorization, a different four-value enum
-- (unsigned/signed/closed/stale), no voiding, and the per-event FK capture
-- serving as its own audit trail. The net scope is SMALLER than 20.8
-- anticipated. Do not reintroduce voided/superseded or a standing-document
-- shape by analogy to 20.8 -- Decision 28 eliminated both deliberately.
--
-- POLYMORPHIC event_reference_id: NOT NULL uuid, NO DATABASE FK -- deliberate,
-- reusing 022's exact shape (28.1).
--
--   event_type ('ala' | 'work_authorization' | 'service_report') +
--   event_reference_id together identify exactly one parent row in
--   ala_documents (025) / work_authorization_documents (022) / service_reports
--   (028). There is NO database FK on event_reference_id: it is polymorphic,
--   resolved app-layer by event_type -- the same shape 022 built for its own
--   event_type + event_reference_id, and clock_events (013) built for
--   entity_type + entity_id. A composite index carries the lookup path.
--
--   THE INTEGRITY PROPERTY, STATED PLAINLY: because event_reference_id has no
--   DB FK, this migration applies cleanly even though it can reference a
--   service_reports row that did not exist until migration 028 -- and would
--   still apply cleanly if 028 had never been written. "Applied clean" proves
--   this migration EXECUTES, not that the reference is CORRECT. Referential
--   integrity across the three parents is an app-layer concern: the Server
--   Action must resolve event_reference_id against the table named by
--   event_type, and must check for signed authorizations before allowing a
--   referenced parent row to be deleted. This is 022's locked position, reused.
--
-- ONE AUTHORIZATION PER EVENT (28.2) -- NO UNIQUE on claim_id. event_type +
-- event_reference_id identify one parent row; a customer with three open claims
-- needing binding-commitment action gets three separate signed rows -- same
-- customer, same O&M Provider, same day, no sharing. Even within a single
-- claim, distinct events (an ALA and a Work Authorization) each get their own
-- row. This is one-to-many with claims -- the same shape as
-- work_authorization_documents (022), the deliberate contrast against
-- ala_documents (025) and service_reports (028), which are UNIQUE per claim.
--   A UNIQUE on (event_type, event_reference_id) would structurally enforce
--   28.2's "one per event" -- BUT 28.3 requires that a reopened event (denied
--   claim reopening, ALA revise-and-resend, Work Authorization
--   revision-and-resend) generates a BRAND-NEW row for the SAME
--   event_reference_id, preserving the prior row's history unmodified. A DB
--   UNIQUE on (event_type, event_reference_id) would forbid exactly that
--   second row. So "one per event" is an app-layer invariant (one NON-TERMINAL
--   row per event), not a DB UNIQUE -- the same restraint 022 applies to its
--   own one-per-event intent, and consistent with 17.A.6's cap on v1 DB
--   enforcement.
--
-- linked_om_provider_id CAPTURED AT ROW CREATION, NOT DERIVED LIVE (28.4). This
-- single field carries the entire mid-claim-handoff and audit-defensibility
-- burden. A signed row remains permanent proof of who was authorized for that
-- specific event (satisfying 20.7c with no separate snapshot mechanism). An
-- unsigned row, if the customer's O&M Provider changes before signature, goes
-- stale and a new row is created for the new provider (28.6). The handoff rule
-- (28.6) and the no-audit-table decision (28.10) are both app-layer / Server
-- Action logic -- nothing in them is a DB constraint here.
--
-- FOUR-VALUE STATUS ENUM (28.5): unsigned | signed | closed | stale.
--   unsigned -- created, tokenized link sent, awaiting signature.
--   signed   -- customer signed; permanent audit record authorizing the O&M
--               Provider named in linked_om_provider_id for this event.
--   closed   -- mirrors the parent event's own terminal state. Does not track
--               an independent lifecycle past its parent's.
--   stale    -- was unsigned when the linked O&M Provider changed; token
--               invalidated; a new row was created for the new provider (28.6).
--               Terminal, audit-only.
--   NO 'voided' value (a provider switch reroutes an unsigned row or leaves a
--   signed one untouched -- there is nothing to void). NO 'superseded' value
--   (reopening always produces a new row under 28.3 -- nothing to supersede in
--   place). 28.5 is explicit about both omissions. Do not add them.
--
-- SIGNATURE MECHANISM REUSED (28.8), not reinvented: Decision 19's
-- in_platform_widget with typed-name fallback. signer_name_typed is the typed
-- fallback; signed_at is when signature completed. Both nullable -- populated
-- only in the signed (and onward) states.
--
-- TOKENIZED SIGNING FLOW (28.9) -- SEVENTH canonical use of the Stateless
-- Tokenized Interaction Pattern. customer_token / customer_token_expires_at on
-- this row per "shape to copy, not shared store," matching 025's claimant_token,
-- 022's customer_token, 026's recipient_token, 028's submission_token. The
-- "seventh" ordinal collides with 026's "sixth" and others -- a numbering
-- artifact from decisions drafted in different sessions, not a conflict; each
-- entity's token columns are independently locked.
--
-- ON DELETE resolved at build time, from 022's committed precedent:
--   claim_id               -> RESTRICT. Every claim-child FK is RESTRICT
--     (010/016/020/021/022/025/026/028); claims soft-delete, hard-deletion is
--     not an ordinary path.
--   customer_id            -> RESTRICT. Contacts soft-delete; matches 026's
--     recipient_contact_id and 022's contact references.
--   linked_om_provider_id  -> RESTRICT. Same -- a contact FK; and the whole
--     point of capturing it once is that it remains readable as audit proof.
--   template_id            -> RESTRICT. Retired templates must stay readable
--     because signed documents reference them for reporting. Directly parallel
--     to 022's documents.template_id RESTRICT.
--   event_reference_id     -> no clause. There is no FK to carry one (see
--     above). App-layer integrity.
--
-- DELIBERATE OMISSIONS (documented so they are not "helpfully" added later):
--
--   - No UNIQUE on claim_id. One-to-many (28.2). See above.
--   - No UNIQUE on (event_type, event_reference_id). 28.3 requires a new row
--     for a reopened event; a DB UNIQUE would forbid it. App-layer. See above.
--   - No FK on event_reference_id. Polymorphic, locked-shape-preserving; 022's
--     position reused. See above.
--   - No 'voided' or 'superseded' status value. 28.5 eliminates both.
--   - No separate voiding mechanic and no linked_om_provider_id audit-trail
--     table. 28.10: the per-event FK capture IS the audit trail.
--   - No updated_at on om_authorization_templates. The locked sketch (28) lists
--     only created_at on the template. Built verbatim -- an applying table does
--     not vary the locked column set (022's rule for its revisions table).
--     (om_authorization_documents DOES carry updated_at; its sketch lists it.)
--   - No partial UNIQUE index on (tenant_id) WHERE is_default. App-layer, per
--     17.A.6; parallel to 022's / 025's / 023's is_default flags.
--   - No CHECK coupling status to signer_name_typed / signed_at. Transitions
--     run through Server Actions; 17.A.6 caps v1 DB enforcement. Same restraint
--     as 022's status/customer_decision decoupling.
--   - No contact_type CHECK on customer_id / linked_om_provider_id. A CHECK
--     cannot reach a column on another table; that customer_id is a
--     contact_type='customer' row and linked_om_provider_id an O&M-provider row
--     are app-layer invariants. Same treatment as every cross-table invariant.
--   - No clock_events row and no clock_events alter. This entity schedules no
--     future-firing event of its own; the token expiry is a plain timestamp.
--
-- APP-LAYER INVARIANTS (deliberately not DB constraints):
--   - tenant_id matches the referenced claim's tenant_id.
--   - event_reference_id resolves to the row in the table named by event_type,
--     and that row exists.
--   - customer_id is a contact_type='customer' row; linked_om_provider_id is an
--     O&M-provider contact row.
--   - At most one NON-TERMINAL authorization per (event_type,
--     event_reference_id) (28.2); reopened events create new rows (28.3).
--   - At most one is_default = true template per tenant.
--   - The 28.6 mid-claim handoff rule: on provider switch, unsigned rows go
--     stale + reissue; signed rows are never touched.
--   - The 28.7 permission swap: an O&M-provider actor may act on an ALA / Work
--     Authorization / Service Report event only when a 'signed' row exists here
--     matching that event_type/event_reference_id.

-- ---------------------------------------------------------------------------
-- om_authorization_templates
-- ---------------------------------------------------------------------------
-- Created first: om_authorization_documents.template_id is a real FK to it.
create table public.om_authorization_templates (
  id                   uuid primary key default gen_random_uuid(),
  tenant_id            uuid not null references public.tenants(id),
                       -- denormalized per Standard RLS Pattern.
  name                 text not null,
  acknowledgment_text  jsonb not null,
                       -- ProseMirror-compatible JSON per Decision 4; captures
                       --   20.7a-d's four commitments: agent authorization,
                       --   no-notification acknowledgment, binding-on-customer
                       --   acknowledgment, ultimate-responsibility
                       --   acknowledgment.
  is_default           boolean not null default false,
                       -- at most one default per tenant; app-layer.
  created_at           timestamptz not null default now()
                       -- NOTE: no updated_at. The locked sketch (Decision 28)
                       --   lists only created_at on the template; built
                       --   verbatim. Contrast om_authorization_documents below,
                       --   whose sketch does carry updated_at.
);
create index om_authorization_templates_tenant_id_idx
  on public.om_authorization_templates (tenant_id);
comment on table public.om_authorization_templates is
  'Tenant-defined reusable configuration for Customer-O&M Authorization '
  '(Decision 28). acknowledgment_text captures Decision 20.7a-d''s four '
  'commitments (agent authorization; no-notification, binding-on-customer, and '
  'ultimate-responsibility acknowledgments). Built verbatim to the locked '
  'sketch: created_at only, no updated_at.';
comment on column public.om_authorization_templates.is_default is
  'At most one is_default = true per tenant is the architectural intent. '
  'Enforcement is app-layer per Decision 17.A.6''s cap on v1 DB enforcement, '
  'parallel to the is_default flags on work_authorization_templates (022), '
  'ala_templates (025), and the Acknowledgment Gate (023). No partial-UNIQUE '
  'index.';

-- ---------------------------------------------------------------------------
-- om_authorization_documents
-- ---------------------------------------------------------------------------
create table public.om_authorization_documents (
  id                          uuid primary key default gen_random_uuid(),
  tenant_id                   uuid not null references public.tenants(id),
                              -- denormalized per Standard RLS Pattern.
  claim_id                    uuid not null
                                references public.claims(id) on delete restrict,
                              -- NO unique: one-to-many with claim (28.2). Each
                              --   row authorizes one binding-commitment event.
  customer_id                 uuid not null
                                references public.contacts(id) on delete restrict,
                              -- the contact_type = 'customer' row (app-layer).
  linked_om_provider_id       uuid not null
                                references public.contacts(id) on delete restrict,
                              -- the O&M Provider authorized to act, captured at
                              --   row creation and never derived live (28.4).
                              --   This single field carries the entire
                              --   mid-claim-handoff + audit-defensibility
                              --   burden; a signed row is permanent proof of
                              --   who was authorized for this specific event.
  event_type                  text not null,
                              -- 'ala' | 'work_authorization' | 'service_report'.
  event_reference_id          uuid not null,
                              -- polymorphic reference to the parent row in
                              --   ala_documents / work_authorization_documents /
                              --   service_reports, resolved app-layer by
                              --   event_type. NO database FK -- 022's locked
                              --   shape, precedent clock_events.entity_id (013).
  template_id                 uuid not null
                                references public.om_authorization_templates(id)
                                on delete restrict,
  content_snapshot            jsonb not null,
                              -- the template's acknowledgment_text frozen at
                              --   document generation; the customer signed
                              --   exactly this, not whatever the template says
                              --   today. Same freeze convention as 022's
                              --   template_snapshot.
  status                      text not null default 'unsigned',
                              -- four-value machine (28.5); transitions run
                              --   through Server Actions, never direct UPDATE.
  signer_name_typed           text,
                              -- typed-name fallback of Decision 19's signature
                              --   widget (28.8); null until signed.
  signed_at                   timestamptz,
                              -- when signature completed; null until signed.

  -- Stateless Tokenized Interaction Pattern: token on this row, not in
  -- invitations ("shape to copy, not shared store"). Seventh canonical use.
  customer_token              text,
  customer_token_expires_at   timestamptz,

  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now(),
  constraint om_authorization_documents_event_type_check check (
    event_type in ('ala', 'work_authorization', 'service_report')
  ),
  constraint om_authorization_documents_status_check check (
    status in ('unsigned', 'signed', 'closed', 'stale')
  )
);
create index om_authorization_documents_tenant_id_idx
  on public.om_authorization_documents (tenant_id);
create index om_authorization_documents_claim_id_idx
  on public.om_authorization_documents (claim_id);
create index om_authorization_documents_customer_id_idx
  on public.om_authorization_documents (customer_id);
create index om_authorization_documents_linked_om_provider_id_idx
  on public.om_authorization_documents (linked_om_provider_id);
create index om_authorization_documents_template_id_idx
  on public.om_authorization_documents (template_id);
create index om_authorization_documents_event_reference_idx
  on public.om_authorization_documents (event_type, event_reference_id);
  -- the polymorphic lookup path: "which authorization signs off this event?"
  -- Mirrors 022's work_authorization_documents_event_reference_idx and
  -- clock_events_entity_idx (013).
comment on table public.om_authorization_documents is
  'The customer''s signed authorization for an O&M Provider to act as their '
  'agent on ONE specific binding-commitment event -- an ALA acceptance, a Work '
  'Authorization approval, or a Service Report review (Decision 28). '
  'PER-EVENT, not standing: sign-once-per-event, closing when the event closes; '
  'it does not persist across subsequent events even for the same customer and '
  'O&M relationship on the same day. This supersedes Decision 20.8''s standing '
  'per-customer model. One-to-many with claims (28.2): event_type + '
  'event_reference_id identify one parent row, and reopened events create new '
  'rows (28.3) rather than resetting prior ones. NO database FK on '
  'event_reference_id: it is polymorphic across three parent tables, resolved '
  'app-layer -- so this migration applies cleanly regardless of whether a '
  'referenced row exists, which proves execution, not correctness.';
comment on column public.om_authorization_documents.event_reference_id is
  'Polymorphic reference to the authorized event: ala_documents.id when '
  'event_type = ''ala'', work_authorization_documents.id when '
  '''work_authorization'', service_reports.id when ''service_report''. NO '
  'database FK -- Decision 28.1 reuses Decision 11''s two-column (event_type + '
  'event_reference_id) shape exactly as 022 built it; precedent '
  'clock_events.entity_id (013). Dispatch and referential integrity are '
  'app-layer: the Server Action resolves this against the table named by '
  'event_type and must check for signed authorizations before a referenced '
  'parent row is deleted.';
comment on column public.om_authorization_documents.linked_om_provider_id is
  'The O&M Provider authorized to act on this event, captured at row creation '
  'and never derived live (Decision 28.4). This single field carries the entire '
  'mid-claim-handoff and audit-defensibility burden: a signed row is permanent '
  'proof of who was authorized for this specific event (satisfying 20.7c with '
  'no separate snapshot mechanism), and across every event a customer ever has, '
  'these fields collectively ARE the audit trail (28.10) -- no dedicated '
  'change-log table. On a mid-claim provider switch (28.6): unsigned rows go '
  'stale and a new row is created for the incoming provider; signed rows are '
  'never touched.';
comment on column public.om_authorization_documents.status is
  'Four values, exactly: unsigned | signed | closed | stale (Decision 28.5). '
  'unsigned (tokenized link sent, awaiting signature) -> signed (permanent '
  'audit record) -> closed (mirrors the parent event''s terminal state; no '
  'independent lifecycle). stale is the provider-switch terminal for a row that '
  'was still unsigned (token invalidated, new row issued per 28.6), audit-only. '
  'There is NO ''voided'' value (a switch reroutes unsigned or leaves signed '
  'untouched -- nothing to void) and NO ''superseded'' value (28.3 always '
  'creates a new row -- nothing to supersede in place). Both omissions are '
  'explicit in 28.5. This is a different four-value set from Decision 20.8''s '
  'superseded unsigned/signed/voided/superseded model.';
comment on column public.om_authorization_documents.customer_token is
  'Seventh canonical use of the Stateless Tokenized Interaction Pattern '
  '(Decision 28.9), stored on this row per "shape to copy, not shared store," '
  'matching ala_documents.claimant_token (025), '
  'work_authorization_documents.customer_token (022), '
  'notices_of_defect.recipient_token (026), and service_reports.submission_token '
  '(028). The "seventh" ordinal collides with other decisions'' counts -- a '
  'numbering artifact from different drafting sessions, not a conflict.';

-- ---------------------------------------------------------------------------
-- Standard RLS Pattern (6-step) -- both tables
-- ---------------------------------------------------------------------------
alter table public.om_authorization_templates enable row level security;

create policy "om_authorization_templates: tenant read"
  on public.om_authorization_templates
  for select
  using (tenant_id = public.get_user_tenant_id());

alter table public.om_authorization_documents enable row level security;

create policy "om_authorization_documents: tenant read"
  on public.om_authorization_documents
  for select
  using (tenant_id = public.get_user_tenant_id());

-- Writes are service-role only: document creation, the customer's tokenized
-- signing, status transitions, the 28.6 handoff (stale + reissue), and the
-- 28.7 permission checks all run through Server Actions.

grant all on public.om_authorization_templates to anon, authenticated, service_role;
grant all on public.om_authorization_documents to anon, authenticated, service_role;
