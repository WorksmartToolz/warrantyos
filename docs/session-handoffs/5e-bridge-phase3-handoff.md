# WarrantyOS — Session 5e-bridge Phase 3 Handoff Document

Generated: 2026-05-22
Purpose: Opening context for a fresh Claude chat resuming Phase 3 (v2 architecture document drafting). Read this first, then read the referenced documents in the order listed in Section 5.

---

## I'M STARTING PHASE 3 OF THE 5e-BRIDGE SESSION ON WARRANTYOS

Phases 1 and 2 are complete. Phase 1 produced the architecture audit catalog; Phase 2 produced the decisions log with all 10 architectural decisions resolved. Phase 3 produces v2 of the architecture reference document.

---

## SECTION 1: PROJECT IDENTITY

WarrantyOS is a multi-tenant SaaS warranty governance platform for mid-sized EPC solar/renewables operations. The decision sequence in target accounts is Warranty Director (champion) → COO/President (money gate) → CIO/IT (hardest gate).

I'm Andre. Solo founder. Dyslexic but technically savvy — not a developer. I authored Terrasmart SOPs (TSW-GD-202/203/204/204b/205/211) and QCELLS SOP (EHSQ-SOP-201) in a prior role. I'm building the prototype solo with Claude Code and intend to recruit a technical co-founder after the prototype validates.

---

## SECTION 2: WORKING STYLE

- Plain language, no jargon
- Click-by-click instructions for technical setup
- Challenge weak assumptions — push back when I'm about to defer something that should be addressed now
- "1 or 2?" responses for Claude Code permission prompts
- Default to less, not more — don't add belt-and-suspenders verification on already-confirmed work
- Don't reinvent the wheel — Phase 1 audit findings and Phase 2 decisions count as evidence
- Tests are checkpoints, not investigations
- If I ask "fix now vs defer," take "fix it now" seriously (the Tailwind v3→v4 deferral is the cautionary precedent)
- 45–90 minute sessions work best
- Verify pushes succeeded
- Soft-remove for users (audit trail preservation)

---

## SECTION 3: TECHNICAL ENVIRONMENT

- Machine: Windows desktop running WSL/Ubuntu (NOT switching to native Windows)
- WSL username: andre
- Project path: /home/andre/Projects/warrantyos
- Editor: VS Code on Windows with WSL extension
- AI assistance: Claude Code v2.x (Sonnet 4.6) launched from WSL terminal
- Dev server port: 3000 (port 3001 does NOT work — 3000 is correct)
- Node v24.15.0 via nvm, npm v11.12.1, Git v2.53.0

CRITICAL FRONTEND NOTES (carried from Phase 2 handoff):
- shadcn base-nova uses Base UI primitives, not Radix. APIs differ (onClick not onSelect, native button requirements, ref forwarding patterns).
- Tailwind v4 conditional classes only apply when the attribute is present on the element.
- When Claude Code wants to run `npx next build` while the dev server is running, REFUSE. Use `npx tsc --noEmit` instead.

---

## SECTION 4: TECH STACK

- Frontend: Next.js 14.2 App Router, TypeScript strict
- Styling: Tailwind v4 (NOT v3 — migrated in Session 5c)
- UI Components: shadcn base-nova style with Base UI primitives (NOT Radix)
- Database: Supabase Pro tier (upgraded during Phase 2 for pg_cron)
- Auth: Supabase Auth
- Email: Resend (account created, not yet integrated)
- Hosting: Vercel Hobby (account exists, not yet deployed)
- Version Control: Git/GitHub (WorksmartToolz/warrantyos)

Supabase Pro tier note: the upgrade was made independent of Phase 2 decisions — it was a business decision recognizing that Supabase is the right home for WarrantyOS regardless. It unlocks pg_cron (used by Decision 9's clock event infrastructure), automated backups, and leaked password protection.

---

## SECTION 5: REFERENCE DOCUMENTS (PHASE 3 READING ORDER)

Before any v2 drafting, read these in order:

1. **docs/architecture-reference.md** — v1 anchor. Treat any decision documented here as anchor architecture unless we explicitly agreed to change it in Phase 2. v2's job is to expand and complete, not to re-litigate.

2. **docs/session-handoffs/5e-bridge-phase1-audit.md** — 565-line audit catalog. All 15 topics with A/B/C structure (what the doc says / what the code does / known gaps) plus summary (5 contradictions, 10 decisions, 6 risks). This is the working reference for what v2 must address.

3. **docs/session-handoffs/5e-bridge-phase2-decisions-log.md** — 575-line decisions log. All 10 architectural decisions resolved, four new conventions established (Standard RLS Pattern, Defense-in-Depth Pattern, Stateless Tokenized Interaction Pattern, FK + Snapshot Pattern), new Phase 0 alignment item 16 (Unified Contacts Directory) added. Every decision includes schema sketches, rationale, and downstream impacts.

4. **The 7 operational SOPs** (held back from Phase 2; they are Phase 3 source material). Andre will upload these at session start. They cover: warranty management system capabilities, accepted warranty claim lifecycle, denied warranty claim lifecycle, escalated denied claim lifecycle, claim submission requirements and instructions, warranty service report submission, and key components of a work plan.

   The SOPs provide operational detail that expands v1's named structures. v1's named structures (Six Gates, Six Outcomes, Three Escalation Pathways, Four Work Plan Execution Paths) are **anchor architecture**. The 7 SOPs provide operational detail that expands these structures — they do not replace them. v2 drafting integrates SOP content into the v1 anchors, not the other way around.

5. **The 6 claim intake workbooks** (also held back from Phase 2; Phase 3 source material). Andre will upload these alongside the SOPs at session start. They cover: Claim Intake Form, Claim Denial Escalation Intake, Reviewer Data, Parts Claim Datapoints, Work Authorizations, and Work Plan Data Inputs.

   These workbooks are the field-level source material whose existence the Phase 1 audit flagged (Audit Topic 9 references the 6 claim intake workbooks). They feed specifically into Tier 3 drafting of the Claim Intake Data Model section (Audit Topic 9), where the schema design strategy is worked out against actual workbook content. The audit's Topic 9 analysis suggests a hybrid approach (hard columns for universal/queryable fields plus JSONB for warrantor-configurable fields) is likely, but the specific division is a Tier 3 drafting question, not a locked Phase 2 decision. Audit risk #2 ("specification-incomplete topics") applies here: drafting Topic 9 before reconciling these workbooks risks writing a doc that needs immediate revision.

6. **This handoff document.**

---

## SECTION 6: GIT STATE

Most recent commits (newest first), with what each represents:

- `bc7b285` Session 5e-bridge Phase 2 complete: Decisions 1-10 finalized
- `1676e20` Session 5e-bridge Phase 2: Decisions 1-7 checkpoint
- `122dabb` Session 5e-bridge Phase 1: Architecture audit catalog
- `dbe4e31` Session 5e-bridge Phase 2: Handoff document for fresh chat resume
- `3310bb8` Document Session 5e deferred items
- `5690e05` Fix stale page cache after team mutations
- `1022d16` Fix dashboard stat queries to filter removed and suspended users
- `ad2c887` Session 5d: Fix DropdownMenu clicks, suspension loop, AlertDialog warning

Verify on resume:
- `cd ~/Projects/warrantyos`
- `git status` — expect clean working tree, up to date with origin/main
- `git log --oneline -8` — expect `bc7b285` at top

---

## SECTION 7: PHASE 3 PURPOSE

Phase 3 produces v2 of `docs/architecture-reference.md`. v1 is ~250 lines; v2 will be 600–900+ lines (per Phase 1 audit risk #1). Scope the effort accordingly.

v2 must:

- **Preserve all v1 decisions** as anchor architecture. The Core Operational Philosophy principles, the Six Evaluation Gates, the Six Final Outcomes, the Three Escalation Pathways, the Four Work Plan Execution Paths, the Six Lifecycle Stages, the role tier model (Platform Admin + Team Admin + Reviewer + Viewer) — these are anchors. v2 expands them with detail; v2 does not replace them.

- **Integrate all 10 Phase 2 decisions** verbatim with their rationale, schema sketches, and downstream impacts. The decisions log is the authoritative source; v2 quotes from it for the architectural sections it informs.

- **Add new sections** for entities and systems v1 hand-waved past:
  - Project (Audit Topic 7) — sacred root entity
  - Warranty Registration (Audit Topic 6) — 1:1 with Project, expanded from v1's brief mentions
  - Warranty Type Coverages (Audit Topic 8) — replacing v1's "Equipment and Workmanship sub-tables" language with the per-tenant configurable model
  - Claim Intake Data Model (Audit Topic 9) — drafted from claim submission SOPs and the 6 claim intake workbooks
  - ALA System (Audit Topic 10) — drafted from SOPs and the locked Decision 7 markup default
  - Inspections Foundation (Audit Topic 11)
  - Custom Field System (Audit Topic 12) — architecturally locked by Decision 3
  - Unified Contacts Directory (new Phase 0 item 16)
  - Clock Event Infrastructure (Audit Topic 14, Decision 9)
  - Data Migration Tooling (Decision 8, Audit Topic 13)
  - Standard RLS Pattern (Audit Topic 2, new convention from Decisions 3 & 5)
  - Cache Invalidation Pattern (Audit Topic 4)
  - ID Generation (Decision 2's `tenant_id_sequences`)
  - Schema source-of-truth convention (Decision 10)

- **Mark each major section with implementation status**: Implemented / Designed / Deferred (per audit risk #4). This communicates clearly which parts of the architecture exist in code today, which parts are designed but not built, and which parts are planned for later.

- **Replace v1's binary In Scope / Out of Scope** with a three-column structure: MVP / Post-MVP / Explicitly Out of Scope (per audit risk #5). The binary structure no longer captures reality.

- **Retire the "Session N Deferred Items" structure** in favor of one living "Outstanding Items" section organized by category — UX Polish, Architectural Debt, Feature Deferrals, Scope Additions (per audit risk #3). Session-numbered sections accumulate rot; a category-based living section does not.

- **Surface middleware.ts:77** (the auth lookup JWT-claim TODO) as a named Architectural Debt item with a proposed resolution path (per audit risk #6). This is real performance debt for production.

- **Generalize v1's Stateless Customer Interaction Principle** into a "Stateless Tokenized Interaction Pattern" covering both customer claim intake AND assignee registration submission (per Decision 1).

---

## SECTION 8: PHASE 3 HARD CONSTRAINTS

### 8a. SCHEMA.SQL GENERATOR FIRST (FROM DECISION 10)

The very first Phase 3 task — before ANY new schema migration is written, before any v2 section is drafted that depends on new schema — is building the `schema.sql` generator script. Hard ordering. This prevents drift during Phase 3's schema-heavy work (9+ new tables plus modifications).

Specifically:

1. Build the `schema.sql` generator script (estimated 30 min – 2 hours)
2. Verify it produces a `schema.sql` identical to the current hand-maintained one (sanity check that the generator is correct before relying on it)
3. THEN proceed with any v2 drafting that involves schema design

The generator approach (Supabase CLI command, custom pg_dump script, or other) is a Phase 3 implementation decision. Any approach that produces deterministic `schema.sql` from the applied migrations is acceptable.

### 8b. SOP AND WORKBOOK REVIEW BEFORE DEPENDENT SECTIONS

The 7 operational SOPs and 6 claim intake workbooks are source material for Audit Topics 6 (Warranty Registration), 9 (Claim Intake), 10 (ALA), 12 (Custom Fields — only where SOP/workbook-specific field types or required fields surface), and for the claim lifecycle / work plan / service report / escalation pathway sections.

Division of labor between SOPs and workbooks:
- **SOPs** describe operational *processes* — lifecycle stages, decision flows, escalation paths, work plan execution. They feed the narrative sections.
- **Workbooks** describe *data fields* — what gets captured at intake, what reviewers see, what the parts claim datapoints are, what work authorizations contain. They feed the schema-design sections, particularly the hybrid hard-columns-plus-JSONB strategy for claim intake.

Read both BEFORE drafting any dependent section, not after. The audit explicitly flagged this in Phase 1 risk #2: "Writing Topic 9 before the 6 workbooks are reconciled into a hybrid schema strategy risks writing a doc that needs immediate revision."

### 8c. DEPENDENCY ORDER FOR V2 SECTIONS

Some v2 sections depend on others being drafted first. Suggested order:

**Tier 1 — foundational (draft first; not SOP-dependent):**

- Standard RLS Pattern (referenced by every tenant-scoped section)
- Stateless Tokenized Interaction Pattern (referenced by claim intake, registration assignee, ALA, possibly other future stateless workflows)
- Cache Invalidation Pattern (referenced by all mutation sections)
- Unified Contacts Directory (referenced by Project, Decision 8 import, Topic 6, Topic 9)
- Custom Field System — architecturally locked by Decision 3; draft as documentation of the locked design. SOPs may surface field-type *examples* but do not modify the system's architecture.
- Clock Event Infrastructure (referenced by Project registration prep trigger, Information Request windows, warranty expiry, future scheduled events)
- ID Generation — `tenant_id_sequences`, referenced by every entity with a generated identifier
- Schema source-of-truth convention (Decision 10)

**Tier 2 — entity sections (draft after Tier 1):**

- Project (sacred root)
- Warranty Registration (1:1 with Project)
- Warranty Type Coverages (child of Registration)
- Claims (child of Registration — but Claim Intake Data Model is in Tier 3)

**Tier 3 — claim-downstream and SOP/workbook-dependent (draft after Tier 2 AND after SOP and workbook review):**

- Claim Intake Data Model (Audit Topic 9, **workbook-anchored** — hybrid schema design driven by Claim Intake Form, Reviewer Data, Parts Claim Datapoints workbooks)
- ALA System (Audit Topic 10, SOP-dependent)
- Inspections Foundation (Audit Topic 11)
- Work Plan Workflow (SOP- and workbook-dependent, derived from Key Components of a Work Plan SOP + Work Plan Data Inputs and Work Authorizations workbooks + claim lifecycle SOPs; expands v1's Four Work Plan Execution Paths)
- Service Report Submission (SOP-dependent, from the Service Report SOP)
- Escalation Pathways (SOP- and workbook-dependent, from the Denied and Escalated Denied Claim Lifecycle SOPs + Claim Denial Escalation Intake workbook; expands v1's Three Escalation Pathways)
- Customer-Facing Communications (v1 already lists 14 notice types; SOPs may surface additional detail)

**Tier 4 — cross-cutting (draft after all entities exist):**

- Data Migration Tooling (Decision 8)
- Outstanding Items (consolidated deferred items by category, per audit risk #3)
- Session History Summary (Sessions 1 through 5e-bridge — keeps historical context without the "Session N Deferred" rot)
- Implementation Status markers reviewed and applied to each section

---

## SECTION 9: WHAT PHASE 3 IS NOT

Phase 3 is primarily documentation with one code task: the `schema.sql` generator script (Decision 10's first-task constraint). No new migrations, no application code, no UI work in Phase 3.

Phase 3 is **not new architectural decisions**. The 10 Phase 2 decisions are the architectural foundation. If Phase 3 surfaces a question that was not answered in Phase 2, capture it as a Phase 4 or Session 5f open item — do not improvise an answer mid-drafting. The temptation will come; the discipline is to flag and defer.

Phase 3 is **not implementation work**. No new migrations beyond what the generator produces deterministically from the existing migrations. New schema migrations for the v2 entities (contacts, projects, warranty_registrations, etc.) come in Phase 4 or Session 5f, after v2 is drafted and reviewed.

---

## SECTION 10: COMMUNICATION STYLE FOR ANDRE

When responding to Andre:

1. Acknowledge state clearly before acting
2. Walk through plans before any commit
3. Push back if Andre is about to defer something that should be addressed now
4. Use plain language
5. Give "1 or 2?" responses for Claude Code permission prompts in Andre's terminal
6. Verify thoroughly before declaring success
7. Be honest about tradeoffs
8. Acknowledge mistakes when made rather than deflecting
9. Don't reinvent the wheel — Phase 2 decisions and audit findings count as evidence
10. Default to less, not more

---

## SECTION 11: ENVIRONMENT VERIFICATION COMMANDS

When ready to start Phase 3:

1. Open WSL terminal
2. `cd ~/Projects/warrantyos`
3. `git status` (expects clean, up to date with origin/main)
4. `git log --oneline -8` (expects `bc7b285` at top)
5. NO dev server needed (Phase 3 is documentation + the generator script only)
6. Claude Code needed: for the `schema.sql` generator script and for committing v2 drafts

---

## SECTION 12: CONFIRM YOU UNDERSTAND

Before starting Phase 3 work, the new Claude must:

1. Read `docs/architecture-reference.md` (v1)
2. Read `docs/session-handoffs/5e-bridge-phase1-audit.md` (565-line audit catalog, all 15 topics, full summary)
3. Read `docs/session-handoffs/5e-bridge-phase2-decisions-log.md` (575-line decisions log, all 10 decisions, all conventions)
4. Read the 7 operational SOPs (uploaded by Andre at session start)
5. Read the 6 claim intake workbooks (uploaded by Andre at session start)
6. Read this handoff document
7. Confirm understanding of:
   - Project state and Phase 0 alignment (including the new item 16, Unified Contacts Directory)
   - All 10 Phase 2 decisions and the four new conventions
   - Phase 3 hard constraints (schema.sql generator first; SOP and workbook review before SOP/workbook-dependent sections; dependency order for v2 sections)
   - What Phase 3 is NOT (no new architectural decisions, no new application code, no new migrations beyond what the generator produces)
8. Begin Phase 3 with the `schema.sql` generator script per Decision 10's hard ordering. Walk Andre through the plan before any code is written.

---

End of Phase 3 handoff document.
