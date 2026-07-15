# Handoff → Chat 14

**Written:** 2026-07-14 at the close of Chat 12 (third Phase 3 build session).
**Built on:** verified git + direct disk reads. Every hash and claim below was
confirmed this session by terminal output Andre pasted — not narration, not
memory.

> **Read `PROJECT-MAP.md` (repo root) first.** It is the durable orientation doc
> and it is **current** — updated twice this session, committed `c8e6fca` and
> `c6c2a54`. This handoff is the session-specific supplement.

---

## The one thing to internalize

**The design phase is done. Build accordingly.** ~95%+ of decisions are locked
(Decisions 1–28, Phase 0 Items, architecture-reference.md). Before treating
anything as an "open question" or deferring it as "undesigned," **check the
decisions log / arch ref first** — it is almost always already specified, often
down to the exact DDL.

**Where a locked decision is silent, its silence is often deliberate.** This
session's clearest lesson: `internal_teams` looked like it "obviously" wanted a
unique constraint on `name` — the `warranty_types` precedent (011) has one.
Checking Decision 13 first showed the authors had enumerated their omissions
carefully: 13.5 explicitly kills `is_primary`, and the deferred-questions list
names exactly two items, neither of them name uniqueness. It was never
contemplated, so it was not imposed. **Read the decision before importing a
precedent from a neighbouring table.** The `warranty_types` unique exists to
protect Decision 6's anchor-type invariant; `internal_teams` has no equivalent,
so the precedent does not transfer.

Decisions also live in **two logs**. `custom_field_definitions` is Decision 3 —
a **Phase 2** decision (`docs/session-handoffs/5e-bridge-phase2-decisions-log.md`),
not Phase 3. Grepping only the Phase 3 log returns nothing and looks like a gap.
It isn't.

---

## Where the project stands (verified)

- **Branch:** `session-5e-bridge-phase3-schema-generator`
- **Git HEAD:** `c6c2a54`, pushed, working tree clean, in sync with origin.
- **Phase 4 baseline:** COMPLETE. Hosted ref `uzjivnmwedfzcgqnnhos` in
  `supabase/PRODUCTION-REF.md`.
- **Phase 3 build:** IN PROGRESS — **10 of ~20 tables built, plus 1 view.**

### Migrations on disk (16 total)
- `000_baseline` → `004_team_admin_management` — auth/provisioning (pre-existing).
- `005_contacts`, `006_projects`, `007_import_batches`, `008_import_batch_fks` —
  Chat 10.
- `009_tenant_id_sequences`, `010_warranty_registrations`, `011_warranty_types`,
  `012_warranty_coverages` (+ `warranty_coverages_effective` view) — Chat 11.
- **`013_clock_events.sql`** — Clock Event Infrastructure (Decision 9; event-type
  enum extended by Item 17 and Decisions 11/19/21/25/27). Three CHECKs
  (`event_type` ×9, `entity_type` ×7, `status` ×4); three indexes with
  **Decision 9's verbatim names** — `clock_events_pending_fires_at_idx` (the
  load-bearing partial index on `fires_at WHERE status = 'pending'`, queried
  hourly by the cron handler), `clock_events_tenant_idx`,
  `clock_events_entity_idx`. No FK on `entity_id`: polymorphic, resolved by
  `entity_type`. **Table only** — pg_cron and the cron handler are separate work.
- **`014_internal_teams.sql`** — tenant-defined internal team registry
  (Decision 13). Soft-delete required. **No unique constraint, no `is_primary`,
  no membership columns** — all deliberate, all documented in the migration
  header so a future chat doesn't "helpfully" add them back.
- **`015_custom_field_definitions.sql`** — tenant-defined extra fields
  (Decision 3, **Phase 2** decisions log; `rich_text` storage locked by
  Decision 4). Two CHECKs: `entity_type` (project | warranty_registration |
  claim) and `field_type` (11 Phase 1 types, snake_case).
  Signature/multi-select/currency are Phase 2 and deliberately absent.

### Commits this session (all pushed, all verified via the origin ref line)
- `a41128e` — feat(schema): clock_events (013) + Convention 9 Status line
- `23143a2` — feat(schema): internal_teams (014) + Convention 9 Status line
- `034eba6` — feat(schema): custom_field_definitions (015) + Convention 9 Status
- `c8e6fca` — docs(project-map): 10 tables + view
- `c6c2a54` — docs(project-map): per-table detail bullets for 013/014/015

### Open items
**None** from the Phase 3 build. **Zero deferred FKs.** Nothing half-done.
**No pending doc-control.** Nothing carried into Chat 14.

---

## Convention 9 in practice — three sections, three different Status shapes

Convention 9 (migrations and their arch-ref `**Status:**` line land in the SAME
commit) held 3/3. What this session added is the vocabulary for **multi-table
sections**:

| Section | Tables | Status now |
|---|---|---|
| Clock Event Infrastructure | 1 (built) | `Implemented (schema)` |
| Work Plan Workflow | 2 (`internal_teams` ✅ / `work_plans` ✗) | header unchanged (`Designed at the architectural level`), one sentence corrected |
| Custom Field System | 2 (`custom_field_definitions` ✅ / `custom_field_values` ✗) | `Partially implemented (schema)` |

**The progression is one-way and was explicitly confirmed with Andre:**

`Designed` → `Partially implemented (schema)` → `Implemented (schema)` →
(later, when Server Actions + UI exist) fully implemented.

**Never revert to `Designed`** once anything is built — "Designed" means
*nothing exists*, which is permanently false after the first table lands.
`Partially implemented (schema)` retires when the section's last table lands,
going **forward** to `Implemented (schema)`.

Why Work Plan Workflow kept its header while Custom Field System changed: in Work
Plan Workflow the *main* table (`work_plans`) is unbuilt, so the section really
is still architectural; in Custom Field System the parent is built and only the
child waits. Judgement call, confirmed with Andre, worth preserving.

---

## The blocker that shaped this session: `claims` does not exist

`custom_field_values` (Decision 3's companion table) **could not be built**, and
this is **not a deferral by choice**:

- It carries `claim_id uuid nullable FK → claims`, and `claims` is not among
  migrations 000–015.
- Its `CHECK: exactly one of the three entity FKs is non-null` needs **all three**
  FK targets to exist. `projects` (006) ✅ and `warranty_registrations` (010) ✅
  exist; `claims` ✗ does not.
- Building it now would introduce a deferred FK. **This project has zero and
  should keep it that way.**

Recorded in the migration 015 header, the arch-ref Status block, and PROJECT-MAP.

**This makes the claims shell the highest-leverage next target** — it unblocks
`custom_field_values` and is a dependency for much of the remaining ALA /
service report / work plan surface.

---

## The build loop (proven across 3 more migrations tonight; unchanged)

1. Pull the **exact locked schema** from architecture-reference.md / the decisions
   logs (do not improvise). **Check the decision's own deferred-questions list** —
   it tells you what was deliberately left out. Confirm any behavioral CHECK
   semantics with Andre first.
2. Advisor generates the full `.sql` in chat → Andre downloads →
   `cp "/mnt/c/Users/andre/Downloads/FILE" supabase/migrations/NNN_name.sql`.
3. `git status --short` — confirm it landed (raw bytes, not narration).
4. `supabase db reset` — **the real validation.** Replays ALL migrations against
   local Postgres; any SQL error, bad FK, constraint or trigger problem fails
   here, locally, harmlessly. Nothing touches the hosted DB.
5. `node scripts/generate-schema-sql.mjs` — regenerates `supabase/schema.sql`.
6. `grep -n "<table>" supabase/schema.sql` — confirm table, constraints, indexes,
   triggers, RLS policy, and grants were all captured.
7. **Update the section's Status line (Convention 9)** — via a downloaded Python
   script with **anchor asserts** (verify ALL anchors before writing anything;
   abort untouched on mismatch).
8. Pre-commit audit: `git diff --stat supabase/schema.sql | cat`. **Additive-only
   is the clean result** for schema.sql. (Prose docs legitimately show deletions —
   that's a rewrite, not a red flag.)
9. Stage, `git status --short`, commit (multi-`-m`, citing the Decision), push,
   verify the `origin` ref line, confirm clean tree.

### Locked patterns every table follows
- **Standard RLS Pattern (6 steps):** `tenant_id` FK (bare `references
  public.tenants(id)`, no ON DELETE — matches the 006 precedent); `enable row
  level security`; SELECT policy `"<table>: members can view their tenant's
  rows"` using `tenant_id = public.get_user_tenant_id()`; writes service-role
  only (no user-facing INSERT/UPDATE/DELETE); `grant all on public.<table> to
  anon, authenticated, service_role`; tenant index.
- **Index naming:** the pattern default is `<table>_tenant_id_idx`. **Where a
  locked decision names its indexes explicitly, the decision wins** —
  `clock_events` uses Decision 9's `clock_events_tenant_idx`. Flag it as a
  deliberate choice in the migration header so it doesn't read as drift.
- **Views on tenant-scoped tables MUST use `WITH (security_invoker = true)`**
  (Decision 24.5) and need their own GRANTs.
- **Hardened functions:** `language plpgsql` + `SET search_path = public`, **no
  `security definer`** (migration 002 precedent).
- **PK convention:** `id uuid primary key default gen_random_uuid()`.
- **`created_at` / `updated_at`:** `timestamptz not null default now()`, **no
  trigger** — the writing Server Action maintains `updated_at`
  (006/010/014/015 precedent).
- **tenant_id denormalized** onto child tables; matches-parent invariant is
  **app-layer**, a comment, not a DB constraint.
- **Cross-row invariants are app-layer**, documented as comments, NOT DB
  constraints.
- **Backfill pattern:** where provisioning seeds rows for new tenants, the
  migration backfills existing tenants idempotently (`ON CONFLICT DO NOTHING`).

---

## Carry-forward: app-layer provisioning seeds (NOT a gap — already specified)

Two tables need rows seeded per **new** tenant at provisioning. Both stated in
the arch ref; neither deferred nor ambiguous. They land with the provisioning
Server Action work (roadmap step 3):

- **`tenant_id_sequences`** — two rows (`warranty_id`, `claim_id`) with default
  formats. Arch ref ID Generation section.
- **`warranty_types`** — two anchor rows (Standard Warranty, Workmanship
  Warranty, `is_system = true`). Arch ref "Anchor types and the is_system flag".

Provisioning is an **admin server operation** (Server Action), not a DB function
(`000_baseline.sql` ~line 129) — app-layer hooks, deliberately not DB triggers.

---

## What to build next (dependency-ordered)

**Recommended: the claims shell.** It unblocks `custom_field_values` and gates
much of what remains. The arch ref's "Claim (Shell)" section is
**Designed at the shell level** and explicit about scope: the shell columns are
locked (including Decision 27's `is_emergency` / `emergency_stabilized_at`, and
claim eligibility locked to `warranty_id IS NOT NULL`), while the intake data
model is a **separate section** and Tier 3. **Build the shell only; do not pull
in Claim Intake's hard columns.** Read both sections' status framing first.

Then, roughly in order of how much they unblock:
- **`custom_field_values`** (Decision 3) — immediately after claims.
- **Tenant-Editable Defaults lookup tables** (Decision 17 Part A/B) — canonical
  lookup shape (value/label/lock_tier/sort_order/disabled_at/deleted_at), six-step
  convention; `inspection_types` (4 platform_locked defaults) and
  `inspection_triggers` (8 platform_locked defaults) are the canonical uses.
  `warranty_types` (011) is the working precedent for the seeded pattern.
- **`work_plans`** (Decisions 13/15/16) — `internal_teams` (014) is built and
  waiting. **Note:** Decision 13 explicitly defers *"ON DELETE behavior on
  internal_team_id"* to "Phase 3 implementation detail" — that question comes due
  when you build this table. Soft-delete on `internal_teams` means hard-deletion
  isn't an ordinary path.
- **Customer Work Authorization** (Decision 11, 3 tables), **ALA System**
  (Decision 19, ext. 25/26, + `ala_document_revisions` and `tenant_holidays`),
  **Inspections** (Decisions 17/18), **Service Reports** (Decision 21),
  **Acknowledgment Gate** (Decision 12, 2 tables), **Notice of Defect**
  (Decision 14), **Customer-O&M Authorization** (Decision 28).
- **pg_cron enablement + the cron handler function** — `clock_events` (013) is
  the table only. The thing that *runs* the clock is separate Phase 3 build-time
  work, explicitly scoped out of 013 and recorded in its Status line. Every
  scheduled job must be defined in a version-controlled migration alongside its
  supporting function (the arch ref's stated convention); cron schedule is hourly,
  `'0 * * * *'`.

---

## Working conventions (unchanged, still in force)

- **Command hygiene (critical — Andre is dyslexic):** ONE command per code block,
  ONLY the command in the block, labeled `▶ RUN IN WSL` or `▶ RUN IN CLAUDE
  CODE`. One at a time, confirm before the next. Never mix prose and commands
  ambiguously.
- **Don't improvise architecture.** Where the arch ref or a decision leaves a line
  item to "implementation," **ask** rather than assume. Three such calls were
  confirmed with Andre this session (clock_events `payload` nullability and the
  absent status/fired_at CHECK; the `field_type` CHECK and its snake_case strings;
  `tenant_id NOT NULL` where Decision 3's sketch omitted it).
- **Prefer clean solutions over shallow fixes.** Err toward quality that won't
  need rework. Don't duplicate state across docs. Don't leave stale-able entries.
- **Environment:** WSL/Ubuntu, `/home/andre/Projects/warrantyos`, Docker + local
  Supabase stack. Dev server port 3000 only. `npx tsc --noEmit`, never
  `npx next build` while the dev server runs.
- **File writes:** advisor generates in chat → Andre downloads → `cp` → verify
  with `git diff` before committing. For in-place doc edits, a downloaded Python
  script with anchor asserts. Do NOT rely on Claude Code for load-bearing
  writes/reads.
- **Read from DISK, not the claude.ai Files panel or the `/mnt/project/` mount or
  memory.** See Traps below.
- **Pre-commit audit** before every substantive commit. Non-negotiable.
- **Verify pushes** succeeded (check the `origin` ref line).
- **Session rhythm:** 45–90 min; soft ceiling 85 messages, warn ~65. (This session
  ran to ~120 at Andre's explicit direction — his call to make, not a default.)

---

## Traps hit this session (don't repeat)

1. **`docs/architecture-reference.md` got dragged into `docs/session-handoffs/`
   AGAIN — third occurrence** (twice in Chat 11, once here), while fetching it for
   a Files-panel upload. Git caught it every time; the signature is `D
   docs/architecture-reference.md` + `?? docs/session-handoffs/architecture-
   reference.md`. Fix: `mv docs/session-handoffs/architecture-reference.md
   docs/architecture-reference.md`, then confirm `git status --short` is empty.
   **Three-for-three means this is a reliable failure mode, not bad luck.**
   Prevention: `cp` to Downloads in the terminal, then upload **from the
   Downloads folder** — never drag from VS Code's explorer.
2. **The `/mnt/project/` mount and the Files panel BOTH lag disk.** At session
   start the panel's `PROJECT-MAP.md` was the **Chat 9** version ("Phase 4 NOT
   STARTED — the gate") while disk was at Chat 11. Claude flagged it as stale
   *disk* state and was wrong — **disk was fine, the panel was stale.** A `wc -l`
   then showed disk's `architecture-reference.md` at 7111 vs the mount's 7104 —
   exactly the 7-line `c195b81` gap. **Always read canonical docs from disk via
   `sed`/`cat` + paste.**
3. **A superseded handoff looks like a git contradiction.** The Chat 12 handoff
   named HEAD `3f34c84`; a revised one named `fb46962`. Both were right at
   different times. **Reconcile against `git log`, not against assumptions.**
4. **Anchor asserts fire on *your* wrong assumptions, not just bad files.** The
   first Status-line script aborted because Claude assumed no blank line between
   the `##` heading and the Status block. The file was fine. `cat -A` settled it.
   **The abort is the system working — but verify the anchor from disk first and
   the abort never happens.**
5. **`git diff` opens a pager that swallows subsequent commands.** Two commands
   were eaten before this was spotted. **Always `| cat`.**
6. **A grep pattern that dodges shell escaping produces false negatives.**
   `grep 'Infrastructure..n.n'` returned nothing and briefly "proved" a
   re-download had failed. It hadn't. **Grep for a plain literal.**
7. **Browsers overwrite same-named downloads** rather than adding `(1)` — so a
   re-download of a corrected script lands at the same path. Convenient, but
   verify the content (grep a distinctive line), not the filename.
8. **Decision 3 is in the PHASE 2 log.** Grepping only
   `5e-bridge-phase3-decisions-log-rev6.md` returns nothing and looks like a gap.
   Both logs are live: `5e-bridge-phase2-decisions-log.md` and
   `5e-bridge-phase3-decisions-log-rev6.md`.

---

## Doc-control state at close — ALL CLOSED

- `docs/architecture-reference.md` — three Status blocks updated, each in the same
  commit as its migration (Convention 9). **Files panel swapped and verified**
  (Andre pasted the full text; all three edits confirmed present).
- `PROJECT-MAP.md` — updated twice: counts/lists/HEAD anchor (`c8e6fca`), then
  per-table detail bullets for 013/014/015 (`c6c2a54`). **Files panel swapped.**
  The detail-bullet gap flagged in `c8e6fca` is **closed** — it is not a
  Chat 14 task.
- `CLAUDE-rev6.md` — untouched this session; panel copy swapped at session start
  and is accurate (includes Convention 9).
- Decisions logs (Phase 2 + Phase 3) — untouched; panel copies accurate.

### Known cosmetic lag (expected, not a bug)
PROJECT-MAP's "Last built" line cites the HEAD it describes (`034eba6`), not its
own commit hash — a doc cannot cite its own not-yet-created hash. It is also now
one commit behind (`c6c2a54` added the bullets). Update on the next substantive
change, not as standalone churn.

---

## First moves in Chat 14

1. `cd ~/Projects/warrantyos && git status` — expect clean, HEAD `c6c2a54`.
2. `git log --oneline -6` — expect `c6c2a54` at top.
3. Read `PROJECT-MAP.md` **from disk**.
4. **Optional re-verify** (Andre asked for a double-check of this session's three
   tables; cheap, and a fresh chat is the right place):
   `grep -n "clock_events\|internal_teams\|custom_field_definitions" supabase/schema.sql | cat`
   — expect table, CHECKs, indexes, FK, RLS policy, and 3 grants for each. All of
   this was verified live in Chat 12, so this is confirmation, not a known issue.
5. Build the **claims shell** — pull its locked schema from the arch ref's
   "Claim (Shell)" section (shell scope only; Claim Intake is a separate Tier 3
   section) plus Decision 27 in the Phase 3 log. Then run the proven loop
   **including Convention 9's Status-line update in the same commit.**

**No pending doc-control. No open items. Nothing carried forward.**
