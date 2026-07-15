# Handoff → Chat 15

**Written:** 2026-07-14 at the close of Chat 14 (fourth Phase 3 build session).
**Built on:** verified git + direct disk reads. Every hash and claim below was
confirmed by terminal output Andre pasted — not narration, not memory.

> **Read `PROJECT-MAP.md` (repo root) first.** It is the durable orientation doc
> and it is **current** — updated twice this session, committed `ec0e85f` and
> `6d48b86`. This handoff is the session-specific supplement.

---

## The one thing to internalize

**The design phase is done. Build accordingly.** ~95%+ of decisions are locked
(Decisions 1–28, Phase 0 Items, architecture-reference.md). Before treating
anything as an "open question," a "gap," or something you get to decide —
**check the locked sources first.** Andre made this a **standing order** this
session:

> *"Checking shall be a standing order for all forward chats, because what's
> been decided and locked wins unless it's necessary to make changes."*

This session proved it three times, and the advisor was wrong all three times:

1. **The emergency CHECK.** Claude recommended a DB CHECK requiring
   `emergency_stabilized_at` when `is_emergency = true`. Decision **27.6**
   forbids exactly that: the platform cannot block filing on the customer's own
   self-report. `emergency_window_exceeded` is **derived, never stored**, and is
   Gate 1 reviewer judgment input. Andre's push — *"check the locked decision"* —
   caught it before it shipped.
2. **`claim_id` uniqueness.** Claude framed it as an open question. The parallel
   column `warranty_registrations.warranty_id` (010) is a **bare text column with
   no unique**, and ID Generation's gap-free guarantee **is** the mechanism. Not
   a question — already answered by precedent.
3. **`tenant_id NOT NULL`.** Claude called Decision 3's sketch omission "a
   genuine gap I resolve." Andre: *"I doubt the gap is real — widen your check."*
   It wasn't real. The Standard RLS Pattern's six-step checklist (arch ref line
   ~108) states `tenant_id uuid not null references public.tenants(id)` as
   **step 1**, and says outright: **"Omitting any one of them is a defect."**

**The pattern:** when a table sketch omits something, check whether a *pattern*
or *precedent* already governs it before calling it undecided. Widen the search
beyond the one decision you're reading.

**Where a locked decision is silent, its silence is often deliberate.**
(Chat 12's `internal_teams` lesson still holds: no unique on `name`, because
Decision 13 never contemplated one.)

**Decisions live in TWO logs.** `custom_field_definitions` and
`custom_field_values` are **Decision 3 — a PHASE 2 decision**
(`docs/session-handoffs/5e-bridge-phase2-decisions-log.md`). Grepping only the
Phase 3 log returns nothing and looks like a gap. It isn't.

---

## Where the project stands (verified)

- **Branch:** `session-5e-bridge-phase3-schema-generator`
- **Git HEAD:** `6d48b86`, pushed, working tree clean, in sync with origin.
- **Phase 4 baseline:** COMPLETE. Hosted ref `uzjivnmwedfzcgqnnhos` in
  `supabase/PRODUCTION-REF.md`.
- **Phase 3 build:** IN PROGRESS — **12 of ~20 tables built, plus 1 view.**

### Migrations on disk (18 total)
- `000_baseline` → `004_team_admin_management` — auth/provisioning (pre-existing).
- `005`–`008` (Chat 10), `009`–`012` + `warranty_coverages_effective` view
  (Chat 11), `013`–`015` (Chat 12).
- **`016_claims.sql`** — the claim shell (Tier 2). **Shell scope only.**
- **`017_custom_field_values.sql`** — closes the Custom Field System section.

### Commits this session (all pushed, all verified via the origin ref line)
- `01be4d2` — feat(schema): claims shell (016) + Convention 9 Status line
- `ec0e85f` — docs(project-map): 11 tables + view
- `77ed146` — feat(schema): custom_field_values (017) + Convention 9 Status line
- `6d48b86` — docs(project-map): 12 tables + view

### Open items
**None.** **Zero deferred FKs.** Nothing half-done. **No pending doc-control.**
Nothing carried into Chat 15.

---

## What 016 and 017 settled

### `claims` (016) — shell only
- **ON DELETE RESTRICT** on `warranty_registration_id`. The arch ref explicitly
  called this "not yet locked… a Phase 3 implementation detail" and pointed at
  the projects→registrations parallel. **Resolved at build time, confirmed with
  Andre.** This was the *one* genuinely open question in the whole section.
- **`status` CHECK admits only `intake_received`** — the sole value locked at the
  shell level. A one-value CHECK looks odd but is the architecturally honest
  read; the Six Gates value set is Tier 3 and extends it by migration.
- **`claim_id` is an independent per-tenant sequence** (`CLM-{year}-{seq:07d}`),
  **not** derived from the parent WarrantyID. v1's `[WarrantyID]-C[NNNN]` is
  retired.
- **Deliberately absent:** intake form fields, tokenized link columns,
  gate-level state columns, claimant FK/snapshot. **Claim Intake is a separate
  Tier 3 section** — do not pull its hard columns into the shell.

### `custom_field_values` (017) — ON DELETE runs in two directions
Both from locked text, neither improvised:
- **CASCADE on the three entity FKs.** Decision 3's rationale for choosing typed
  FKs over a polymorphic key states it: the approach *"lets ON DELETE CASCADE
  work per entity."* A value is a **dependent attribute**, not an independent
  record.
- **RESTRICT on `definition_id`.** Definitions soft-delete and their values must
  **remain queryable**; the arch ref names *"cascade-destroy auditable data"* as
  the outcome to avoid. CASCADE there would be exactly that.
- **No conflict with the RESTRICT on 010/016** — those protect *parent rows
  carrying independent meaning*. Different situation, different clause. If a
  future table raises this again, that's the distinction.

---

## Convention 9 — held 2/2 this session

Migration + its arch-ref `**Status:**` line land in the **same commit**.

| Section | Status now |
|---|---|
| Claim (Shell) | `Designed at the shell level` → **`Implemented (schema)`** |
| Custom Field System | `Partially implemented (schema)` → **`Implemented (schema)`** |

**The progression is one-way:** `Designed` → `Partially implemented (schema)` →
`Implemented (schema)` → (later, with Server Actions + UI) fully implemented.
**Never revert to `Designed`.** Custom Field System also **left the
DESIGNED-NOT-BUILT list entirely** — both its tables are built.

Note: Claim (Shell) went straight to `Implemented (schema)`, not `Partially` —
because Claim Intake is a **separate section**, not an unbuilt sibling table
within this one.

---

## What to build next (dependency-ordered)

- **Tenant-Editable Defaults lookup tables** (Decision 17 Part A/B) — canonical
  lookup shape (value/label/lock_tier/sort_order/disabled_at/deleted_at),
  six-step convention; `inspection_types` (4 platform_locked defaults) and
  `inspection_triggers` (8 platform_locked defaults) are the canonical uses.
  `warranty_types` (011) is the working precedent for the seeded pattern.
- **`work_plans`** (Decisions 13/15/16) — `internal_teams` (014) is built and
  waiting. **Note:** Decision 13 explicitly defers *"ON DELETE behavior on
  internal_team_id"* to "Phase 3 implementation detail" — that question comes due
  when you build this table, exactly like 016's did. Soft-delete on
  `internal_teams` means hard-deletion isn't an ordinary path.
- **Customer Work Authorization** (Decision 11, 3 tables), **ALA System**
  (Decision 19, ext. 25/26, + `ala_document_revisions` and `tenant_holidays`),
  **Inspections** (Decisions 17/18), **Service Reports** (Decision 21),
  **Acknowledgment Gate** (Decision 12, 2 tables), **Notice of Defect**
  (Decision 14), **Customer-O&M Authorization** (Decision 28).
- **Claim Intake Data Model** (Tier 3) — the hybrid hard-columns + JSONB schema,
  settled against the six intake workbooks. Now that the shell exists, this is
  unblocked but it is **real Tier 3 design work**, not a migration you can pull
  from a locked sketch.
- **pg_cron enablement + the cron handler function** — `clock_events` (013) is
  the table only. Every scheduled job must be defined in a version-controlled
  migration alongside its supporting function; cron schedule is hourly,
  `'0 * * * *'`.

---

## The build loop (proven across 5 migrations now; unchanged)

1. Pull the **exact locked schema** from architecture-reference.md / **both**
   decisions logs. Check the decision's deferred-questions list. **Widen the
   check to patterns and precedents before declaring a gap.** Confirm any
   behavioral CHECK semantics with Andre first.
2. Advisor generates the full `.sql` in chat → Andre downloads →
   `cp "/mnt/c/Users/andre/Downloads/FILE" supabase/migrations/NNN_name.sql`.
3. `git status --short` — confirm it landed (raw bytes, not narration).
4. `supabase db reset` — **the real validation.** Replays ALL migrations.
5. `node scripts/generate-schema-sql.mjs` — **NOT an npm script.** There is no
   `schema:generate`; `grep schema package.json` returns nothing. It is
   documented in `scripts/README.md`.
6. `grep -n "<table>" supabase/schema.sql | cat` — verify table, CHECKs, PK,
   indexes, FKs (**and their ON DELETE clauses**), RLS, policy, 3 grants.
7. Convention 9 Status-line edit via a downloaded **anchored Python script**.
8. Pre-commit audit: `git diff | cat` on every file. `git diff --stat` on
   `schema.sql` should be **additive only** (0 deletions) — that's the property
   that proves no drift in existing objects.
9. Commit all files together. Push. **Verify the `origin` ref line.**
10. Update PROJECT-MAP + swap the Files panel **immediately** — see below.

---

## Working conventions (in force)

- **Doc-control is NEVER deferred.** Andre, verbatim: *"This should always be the
  default action, never delay or defer anything like this EVER!"* When a doc
  change is due, it lands in the same session — no "we'll batch it next chat."
  The advisor proposed batching once this session and was corrected.
- **Command hygiene (critical — Andre is dyslexic):** ONE command per code block,
  ONLY the command in the block, labeled `▶ RUN IN WSL` or `▶ RUN IN CLAUDE
  CODE`. One at a time, confirm before the next.
- **Don't improvise architecture.** Where the arch ref leaves a line item to
  "implementation," **ask**. Where it doesn't, **don't ask — look it up.**
- **Environment:** WSL/Ubuntu, `/home/andre/Projects/warrantyos`, Docker + local
  Supabase stack. Dev server port 3000 only. `npx tsc --noEmit`, never
  `npx next build` while the dev server runs.
- **File writes:** advisor generates in chat → Andre downloads → `cp` → verify
  with `git diff` before committing. In-place doc edits use a downloaded Python
  script with anchor asserts. Do NOT rely on Claude Code for load-bearing writes.
- **Read from DISK**, not the Files panel, the `/mnt/project/` mount, or memory.
- **Pre-commit audit** before every substantive commit. Non-negotiable.
- **Session rhythm:** 45–90 min; soft ceiling 85 messages, warn ~65. (This
  session ran to ~100 at Andre's explicit direction, to finish 017 rather than
  hand off a staged-but-uncommitted table. His call to make, not a default.)

---

## Traps (corrected and new)

1. **CORRECTED — the `architecture-reference.md` relocation.** The Chat 12
   handoff blamed **VS Code drag-and-drop** and prescribed "never drag from VS
   Code's explorer." **Andre says that diagnosis is wrong, and it's his call:**

   > *"architecture-reference.md HAS TO BE MOVED to the correct location — this
   > is a handler error, meaning me placing the file, not a fault of VS or git."*
   >
   > *"The next chat must have the right explanation: that it is me misplacing
   > the file during upload, not VS Code."*

   **Root cause: handler error at file-placement time during the Files-panel
   upload.** Not a tooling defect. The tool isn't the culprit; the drop target
   is. It happened a **fourth time** this session and Andre's `mv` fixed it.
   - Correct home: **`docs/architecture-reference.md`**
   - Wrong: `docs/session-handoffs/architecture-reference.md`
   - Fix: `mv docs/session-handoffs/architecture-reference.md docs/architecture-reference.md`
   - Then confirm `git status --short` is empty.

   *(Chat 12's handoff text is frozen per Convention 7 — not edited in place.
   This entry supersedes it.)*

2. **Don't assert a command will fail — run it.** Claude told Andre the `mv`
   would fail because "there's nothing to move." It succeeded; the file **was**
   misplaced. `git status --short` had been empty and Claude reasoned from that
   instead of checking with `ls`. **Verify with a command, don't predict.**

3. **`sed` output does not show blank lines distinctly.** Claude read `sed`
   output, concluded three blank lines were missing, and wrote a repair script
   for a file that was **completely fine**. The anchor assert aborted and saved
   it. **Use `cat -A` to check whitespace** — `$` marks line ends. (This is Chat
   12's trap #4 restated; it was hit again despite being written down.)

4. **The anchor abort is the system working.** Twice now it has fired on
   Claude's wrong assumptions rather than a bad file. Trust it; investigate the
   assumption first.

5. **`git diff` opens a pager that swallows subsequent commands.** Always `| cat`.

6. **The `/mnt/project/` mount and the Files panel BOTH lag disk.** Always read
   canonical docs from disk via `sed`/`cat` + paste.

7. **Migration file mode is `100755`, and that's correct.** Every Phase 3
   migration (005–017) is 755 because of the download→`cp` workflow; only the
   pre-existing 000–004 are 644. Claude flagged this as a defect and withdrew it
   after checking `git ls-files -s`. **Not a bug — don't "fix" it.**

8. **Decision 3 is in the PHASE 2 log.** Both logs are live.

---

## Doc-control state at close — ALL CLOSED

- `docs/architecture-reference.md` — two Status blocks updated (Claim Shell,
  Custom Field System), each in the same commit as its migration (Convention 9).
  Files panel refreshed at close.
- `PROJECT-MAP.md` — updated twice (`ec0e85f`, `6d48b86`): counts, migration
  list, two new per-table detail bullets, Custom Field System removed from
  DESIGNED-NOT-BUILT. Files panel refreshed at close.
- `CLAUDE-rev6.md` — untouched. Panel copy accurate.
- Decisions logs (Phase 2 + Phase 3) — untouched. Panel copies accurate.

### Known cosmetic lag (expected, not a bug)
PROJECT-MAP's "Last built" line cites the HEAD it describes (`77ed146`), not its
own commit hash — a doc cannot cite its own not-yet-created hash. Its date reads
`2026-07-15` because the commits landed after 00:00 UTC while Andre's local date
was still the 14th. The **hash is the load-bearing part**. Update on the next
substantive change, not as standalone churn.

---

## First moves in Chat 15

1. `cd ~/Projects/warrantyos && git status` — expect clean, HEAD `6d48b86`.
2. `git log --oneline -5` — expect `6d48b86` at top.
3. Read `PROJECT-MAP.md` **from disk**.
4. Pick the next table (Tenant-Editable Defaults lookups or `work_plans`), pull
   its locked schema from the arch ref + the right decisions log, and run the
   proven loop **including Convention 9's Status-line update in the same commit**.

**No pending doc-control. No open items. Nothing carried forward.**
