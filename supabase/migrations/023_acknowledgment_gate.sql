-- 023_acknowledgment_gate.sql
--
-- The Acknowledgment Gate Pattern: a Tier 1 platform-wide pattern (Decision 12).
-- Certain tokenized customer interactions must put tenant-defined content in
-- front of the customer BEFORE the customer sees the actual interaction form --
-- a Site Readiness & Safety Requirements acknowledgment before a Customer Work
-- Authorization is accepted; a Warranty Claim Submission Requirements
-- acknowledgment before a claim is filed.
--
-- The content is tenant-defined (the warrantor's legal, safety, or operational
-- language); the gate is platform architecture (the same pre-form acknowledgment
-- mechanism reused across multiple interactions). The pattern exists so that
-- interactions opting into it do not each invent their own gate mechanism.
--
-- Two tables, parent-child -- the same shape as the ALA System and Customer Work
-- Authorization (022):
--   acknowledgment_gate_templates  -- tenant-defined, reusable, soft-delete
--                                     required
--   acknowledgment_gate_records    -- per-acknowledgment-event instantiations,
--                                     frozen content snapshot for defensibility
--
-- Locked sources:
--   architecture-reference.md "Acknowledgment Gate Pattern" -> both schema
--     sketches, the gate mechanics, the optional-per-tenant framing, the
--     one-gate-per-entity commitment, the deliberate-omissions list.
--   Decision 12 - the locked architectural specification: seven locked
--     commitments (12.1 through 12.7) and both schema sketches.
--   Decision 4 - ProseMirror-compatible JSON storage format for rich text
--     (content, template_content_snapshot).
--   Decision 9 - the extensibility convention the gate_purpose CHECK follows
--     (same as clock_events event_type).
--   Decision 11 / 022 - Customer Work Authorization; gate_purpose =
--     'work_authorization' guards that document's tokenized form. The gate is an
--     interstitial on THAT document's customer_token -- there is no second
--     token.
--
-- OPTIONAL PER TENANT PER PURPOSE (12.3). The platform supports gates natively
-- but does not mandate them. A tenant configures a template for a gate_purpose
-- only if their operational practice requires one; a tenant whose external
-- compliance processes already handle the equivalent acknowledgment leaves the
-- purpose unconfigured, and their customers proceed straight to the interaction
-- form. The pattern's presence is platform-level SUPPORT for warrantors who use
-- gates, not an assertion that warrantors should. Nothing in this migration
-- requires a tenant to hold any rows at all -- which is why, unlike 018/019,
-- there is deliberately NO seed and NO backfill here.
--
-- ONE GATE PER PROTECTED ENTITY IN PHASE 1 (12.4). A protected entity carries at
-- most one acknowledgment_gate_records row; once the record exists the gate is
-- not shown again for that entity on subsequent link clicks. Multi-gate-per-
-- entity is deferred as speculative: a tenant needing several acknowledgments
-- composes them into one longer template's content rather than chaining records.
-- The "at most one" is enforced app-layer by the Server Action's existence check
-- (12.7 step 3), NOT by a DB unique -- see the omissions list.
--
-- authorized_entity_id: SINGLE POLYMORPHIC COLUMN, NO FK -- resolved at build
-- time.
--
--   Decision 12.6 left the polymorphic shape open, naming three candidates:
--   separate per-entity-type FK columns with a CHECK; a single polymorphic
--   authorized_entity_id with app-layer dispatch; or a junction table.
--
--   Resolved as the single polymorphic column, because it is the only candidate
--   that honors the two-column shape Decision 12 commits to BY NAME
--   (authorized_entity_type + authorized_entity_id, named in both the decisions
--   log sketch and the arch ref sketch):
--     - The junction table is doubly excluded: it eliminates both locked
--       columns, and it supports many-to-many in principle, which 12.4's
--       one-gate-per-entity commitment forbids.
--     - Separate typed FK columns (claim_id, work_authorization_document_id, +
--       CHECK exactly-one-non-null) would give real referential integrity -- and
--       017 (custom_field_values) is a real precedent for preferring typed FKs
--       over a polymorphic key per Decision 3. But that shape DELETES both
--       columns Decision 12 locks. 017's precedent does not transfer: Decision 3
--       chose typed FKs where no locked column name was at stake. Here two are.
--     - The single polymorphic column preserves the locked text verbatim.
--
--   This is the SAME reasoning, and the same answer, as Decision 11.b on 022's
--   event_reference_id -- the structurally identical question. The deciding test
--   in both cases: does the locked text name the column? It does. In-repo
--   precedent for exactly this shape: clock_events.entity_id (013) carries NO FK
--   and is resolved by entity_type. Third consecutive polymorphic reference
--   answered the same way; it is a pattern, not a coincidence.
--
--   ONE DELIBERATE DIFFERENCE FROM 022: authorized_entity_id is NOT NULL here,
--   where 022's event_reference_id is nullable. Both are built verbatim to their
--   own locked sketches, and the sketches differ because the semantics differ: a
--   Work Authorization may exist before its event entity is identified, but an
--   acknowledgment is BY DEFINITION an acknowledgment OF something -- there is
--   always a protected entity. Do not harmonize.
--
--   Consequence, accepted: without a database-enforced FK this is an
--   application-layer integrity concern. Dispatch by authorized_entity_type, and
--   the check for acknowledgment records before allowing a protected entity to
--   be deleted, are app-layer.
--
-- ON DELETE resolved at build time:
--   records.template_id -> RESTRICT. The arch ref flags the clause as a Phase 3
--     implementation detail while naming the restraint plainly: templates
--     soft-delete, so "hard-deleting a template would break the relationship"
--     and records "must remain readable... the template_id FK must remain valid
--     for reporting and historical query." CASCADE would be exactly the
--     cascade-destruction of auditable data -- the record of what a customer
--     agreed to -- that the architecture names as the outcome to avoid.
--     Directly parallel to 022's template_id and 017's definition_id: same
--     shape, same reasoning, same answer.
--   records.authorized_entity_id -> no clause. There is no FK to carry one (see
--     above). App-layer integrity.
--
-- DELIBERATE OMISSIONS (documented so they are not "helpfully" added later):
--
--   - No FK on authorized_entity_id. Locked-shape-preserving; see above. Both
--     candidate targets (claims 016, work_authorization_documents 022) now
--     exist, so this is a deliberate architectural choice, not a deferral for
--     want of a target.
--   - No partial UNIQUE index on (tenant_id, gate_purpose) WHERE is_default. The
--     arch ref offers partial-UNIQUE or app-layer and picks neither, and the
--     decisions log sketch states the intent flatly ("at most one default per
--     (tenant_id, gate_purpose)") without deferring the mechanism at all.
--     Decision 17.A.6 caps v1 DB enforcement, and every prior table places this
--     class of invariant app-layer. 022 answered the identical question
--     app-layer; the arch ref calls this flag "parallel to ALA's is_default
--     flag", and ALA (Decision 19) resolves the same way when it lands. Three
--     parallel flags, one answer.
--   - No UNIQUE on (authorized_entity_type, authorized_entity_id). 12.4's "at
--     most one record per protected entity" is real architectural intent, but it
--     is enforced by 12.7 step 3's Server Action existence check -- the mechanic
--     the locked text specifies. A DB unique would additionally have to be
--     tenant-scoped to be correct, and 17.A.6 caps v1 DB enforcement at value
--     sets, NOT NULLs, and FK integrity. Same restraint as 016's claim_id and
--     020's/022's claim_id.
--   - No second token, no expires_at, no consumed_at. The gate is an
--     interstitial on the protected entity's EXISTING tokenized link, not its
--     own tokenized interaction. Token validation runs once per click, in the
--     protected entity's tokenized interaction layer (022's customer_token).
--     Explicit in 12.7 and the arch ref's omissions list.
--   - No expires_at / stale-out on records. An acknowledgment is valid for the
--     protected entity's lifetime. The arch ref's omissions list is explicit; if
--     compliance language changes warrant re-prompting, the architecture
--     revisits.
--   - No updated_at on records. The locked sketch carries created_at only -- a
--     record is frozen at acknowledgment and never edited. Built verbatim; an
--     applying table does not vary the locked column set. (Templates DO carry
--     updated_at: they are edited.)
--   - No deleted_at on records. Soft-delete is required on templates only. The
--     locked sketch carries none for records: an acknowledgment is the audit
--     artifact and is never retired.
--   - No custom field involvement. The arch ref is explicit: gates are
--     tenant-defined documents with a structured shape, not custom fields. The
--     Custom Field System (Decision 3) is for fields varying by tenant on the
--     ENTITIES; not for legal/safety language attached to interaction surfaces.
--   - No seed, no backfill. Deliberately differs from 018/019, whose backfill was
--     mandatory because inspections.inspection_type_id is NOT NULL and existing
--     tenants would hold zero rows and be unable to create an inspection at all.
--     The inverse is true here: 12.3 makes gates optional, zero rows is a valid
--     and expected steady state, and platform-seeded gate content would be the
--     platform imposing legal/safety language on tenants -- precisely what 12.3
--     forbids.
--   - No CHECK coupling acknowledger_name to the template's requires_typed_name.
--     The requirement lives on the template and the value on the record, across
--     a FK; a DB CHECK cannot see it. App-layer, per 17.A.6.
--   - No CHECK coupling authorized_entity_type to gate_purpose. The pairs
--     correspond in Phase 1 ('claim_submission'/'claim',
--     'work_authorization'/'work_authorization_document') but gate_purpose lives
--     on the template and authorized_entity_type on the record -- again across a
--     FK. Both enums are independently extensible, and the arch ref never
--     couples them. App-layer.
--   - No clock_events row created here. A gate acknowledgment is a synchronous
--     event within the Server Action that renders the form; nothing fires later.
--     Decision 9's convention reserves clock_events for future-firing events.
--
-- APP-LAYER INVARIANTS (deliberately not DB constraints):
--   - tenant_id matches the referenced template's tenant_id (records), and the
--     protected entity's tenant_id.
--   - authorized_entity_id resolves to the right table per
--     authorized_entity_type, and the referenced row exists.
--   - At most one is_default = true template per (tenant_id, gate_purpose).
--   - At most one record per protected entity (12.4), enforced by 12.7 step 3's
--     existence check.
--   - acknowledger_name is populated exactly when the template's
--     requires_typed_name = true.
--   - template_content_snapshot is captured at acknowledgment, never read live
--     through template_id.
--   - The gate is rendered or skipped by the same Server Action that renders the
--     interaction form (12.7).

-- ---------------------------------------------------------------------------
-- acknowledgment_gate_templates
-- ---------------------------------------------------------------------------
create table public.acknowledgment_gate_templates (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references public.tenants(id),
                        -- denormalized per Standard RLS Pattern.
  gate_purpose          text not null,
                        -- which tokenized interaction this gate guards.
                        --   Extensible exactly like clock_events.event_type
                        --   (Decision 9): a new tokenized interaction adds a
                        --   value and updates the CHECK via migration, without
                        --   restructuring the tables.
  name                  text not null,
                        -- tenant-friendly identifier.
  content               jsonb not null,
                        -- ProseMirror-compatible JSON per Decision 4; the
                        --   gate's body content. Decision 4's character cap
                        --   defaults apply.
  acknowledgment_label  text not null,
                        -- the text shown next to the checkbox (e.g., "By
                        --   checking this box, I confirm...").
  requires_typed_name   boolean not null default false,
                        -- whether the gate requires the customer to type their
                        --   name in addition to checking the box.
  is_default            boolean not null default false,
                        -- at most one default per (tenant_id, gate_purpose);
                        --   app-layer.
  deleted_at            timestamptz,
                        -- soft-delete REQUIRED, not optional: a template
                        --   retired today may have records pointing to it from
                        --   acknowledgments captured last year. Those records
                        --   must stay readable and template_id must still
                        --   resolve for reporting and historical query.
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  constraint acknowledgment_gate_templates_gate_purpose_check check (
    gate_purpose in ('claim_submission', 'work_authorization')
  )
);
create index acknowledgment_gate_templates_tenant_id_idx
  on public.acknowledgment_gate_templates (tenant_id);
create index acknowledgment_gate_templates_purpose_idx
  on public.acknowledgment_gate_templates (tenant_id, gate_purpose);
  -- the gate-mechanics lookup path (12.7 step 2): "does this tenant have a
  -- template configured for this interaction's purpose?" -- run on every
  -- tokenized link click.
comment on table public.acknowledgment_gate_templates is
  'Tenant-defined gate definitions (Decision 12): which interaction purpose the '
  'gate guards, the gate''s content, the acknowledgment text beside the '
  'checkbox, whether a typed name is required, and which template is the '
  'tenant''s default for the purpose. Same templates-and-records shape as the '
  'ALA System and Customer Work Authorization (022). Gates are OPTIONAL per '
  'tenant per purpose (12.3): a tenant whose external compliance processes '
  'already handle the equivalent acknowledgment leaves the purpose '
  'unconfigured, and their customers proceed directly to the interaction form. '
  'Zero rows is a valid steady state -- which is why this migration '
  'deliberately seeds nothing.';
comment on column public.acknowledgment_gate_templates.gate_purpose is
  'Which tokenized customer interaction this gate guards. Phase 1 values: '
  'claim_submission (guards a Claim Intake tokenized intake form), '
  'work_authorization (guards a Customer Work Authorization tokenized '
  'acceptance form, 022). Extensible the same way Decision 9''s '
  'clock_events.event_type is: a future tokenized interaction that benefits '
  'from a pre-form gate adds a value and updates this CHECK via migration, '
  'without restructuring the tables. Other candidates named but NOT locked by '
  'Decision 12: registration assignee submission, supply-only delivery '
  'reporting, service report customer review -- each a per-interaction decision '
  'when those sections are drafted.';
comment on column public.acknowledgment_gate_templates.is_default is
  'At most one is_default = true per (tenant_id, gate_purpose) is the '
  'architectural intent. Enforcement is app-layer: the arch ref offers '
  'partial-UNIQUE or app-layer and picks neither, and Decision 17.A.6 caps v1 '
  'DB enforcement. Parallel to Work Authorization''s (022) and ALA''s '
  'is_default flags -- three parallel flags, one answer.';
comment on column public.acknowledgment_gate_templates.deleted_at is
  'Soft-delete is required, not optional. Records captured against a retired '
  'template must remain readable: the frozen template_content_snapshot '
  'preserves what the customer actually agreed to, but the template_id FK must '
  'remain valid for reporting and historical query. Hard-deleting a template '
  'would break that relationship -- hence RESTRICT on records.template_id.';

-- ---------------------------------------------------------------------------
-- acknowledgment_gate_records
-- ---------------------------------------------------------------------------
create table public.acknowledgment_gate_records (
  id                         uuid primary key default gen_random_uuid(),
  tenant_id                  uuid not null references public.tenants(id),
                             -- denormalized per Standard RLS Pattern.
  template_id                uuid not null
                               references public.acknowledgment_gate_templates(id)
                               on delete restrict,
                             -- templates soft-delete; the FK must stay valid for
                             --   reporting. RESTRICT, never CASCADE -- see the
                             --   header.
  template_content_snapshot  jsonb not null,
                             -- content frozen at acknowledgment time. The
                             --   customer agreed to exactly this, not to
                             --   whatever the current template says. Captured at
                             --   acknowledgment, never read live through
                             --   template_id -- same defensibility logic as
                             --   ALA's content_snapshot and 022's
                             --   template_snapshot (FK + Snapshot Pattern).
  acknowledger_name          text,
                             -- populated only when the template's
                             --   requires_typed_name = true; app-layer.
  acknowledged_at            timestamptz not null,
                             -- no default: set explicitly by the Server Action
                             --   at the moment of acknowledgment, per the locked
                             --   sketch.
  acknowledger_ip            text,
                             -- captured for audit trail.
  authorized_entity_type     text not null,
                             -- which kind of entity this acknowledgment
                             --   authorizes.
  authorized_entity_id       uuid not null,
                             -- polymorphic reference to the specific protected
                             --   row, resolved app-layer by
                             --   authorized_entity_type. NO FK -- see the header
                             --   for why this preserves Decision 12's locked
                             --   two-column shape. Precedent:
                             --   clock_events.entity_id (013),
                             --   work_authorization_documents.event_reference_id
                             --   (022). NOT NULL because an acknowledgment is by
                             --   definition an acknowledgment OF something.
  created_at                 timestamptz not null default now(),
  constraint acknowledgment_gate_records_authorized_entity_type_check check (
    authorized_entity_type in ('claim', 'work_authorization_document')
  )
);
create index acknowledgment_gate_records_tenant_id_idx
  on public.acknowledgment_gate_records (tenant_id);
create index acknowledgment_gate_records_template_id_idx
  on public.acknowledgment_gate_records (template_id);
create index acknowledgment_gate_records_authorized_entity_idx
  on public.acknowledgment_gate_records (authorized_entity_type, authorized_entity_id);
  -- the load-bearing lookup path (12.7 step 3): "does a record already exist for
  -- this specific protected entity?" -- run on every tokenized link click to
  -- decide gate-or-form. Mirrors clock_events_entity_idx (013) and
  -- work_authorization_documents_event_reference_idx (022).
comment on table public.acknowledgment_gate_records is
  'Per-acknowledgment-event instantiations (Decision 12): for one specific '
  'protected entity, the customer''s acknowledgment with the template content '
  'frozen at the moment they agreed, the acknowledger''s identity capture, the '
  'timestamp, the IP for audit trail, and a polymorphic reference to the '
  'protected entity the acknowledgment authorizes. One gate per protected '
  'entity in Phase 1 (12.4): once this row exists, the gate is not shown again '
  'for that entity on subsequent link clicks. That "at most one" is enforced by '
  'the Server Action''s existence check (12.7 step 3), not by a DB unique. '
  'Multi-gate-per-entity is deferred as speculative -- a tenant needing several '
  'acknowledgments composes them into one longer template''s content.';
comment on column public.acknowledgment_gate_records.authorized_entity_id is
  'Polymorphic reference to the protected entity: claims.id when '
  'authorized_entity_type = ''claim'', work_authorization_documents.id when '
  '''work_authorization_document''. NO database FK -- Decision 12 locks the '
  'two-column (authorized_entity_type + authorized_entity_id) shape by name, '
  'and typed per-entity FK columns would delete both locked columns. Same '
  'reasoning and same answer as Decision 11.b on 022''s event_reference_id, the '
  'structurally identical question; precedent also clock_events.entity_id '
  '(013). Deliberately NOT NULL where 022''s event_reference_id is nullable: '
  'both are built verbatim to their own locked sketches, and an acknowledgment '
  'is by definition an acknowledgment OF something. Do not harmonize. Dispatch '
  'and referential integrity are app-layer; the application must check for '
  'acknowledgment records before allowing a protected entity to be deleted.';
comment on column public.acknowledgment_gate_records.template_content_snapshot is
  'The frozen content the customer actually agreed to, captured at '
  'acknowledgment rather than referenced live through template_id. Same '
  'defensibility logic as ALA''s content_snapshot and the FK + Snapshot '
  'Pattern: a later template revision must not retroactively alter what the '
  'customer agreed to. The template_id FK preserves the relationship for '
  'reporting; this column preserves the historical truth.';

-- ---------------------------------------------------------------------------
-- Standard RLS Pattern (6-step) -- both tables
-- ---------------------------------------------------------------------------
alter table public.acknowledgment_gate_templates enable row level security;

create policy "acknowledgment_gate_templates: tenant read"
  on public.acknowledgment_gate_templates
  for select
  using (tenant_id = public.get_user_tenant_id());

alter table public.acknowledgment_gate_records enable row level security;

create policy "acknowledgment_gate_records: tenant read"
  on public.acknowledgment_gate_records
  for select
  using (tenant_id = public.get_user_tenant_id());

-- Writes are service-role only: template authoring, and the record insert the
-- Server Action performs on gate submission (12.7 step 5), both run through
-- Server Actions. The customer's acknowledgment arrives through the protected
-- entity's existing tokenized link -- there is no second token.

grant all on public.acknowledgment_gate_templates to anon, authenticated, service_role;
grant all on public.acknowledgment_gate_records to anon, authenticated, service_role;
