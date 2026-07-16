# Handoff → Chat 18

**Written:** 2026-07-16 at the close of Chat 17 (seventh Phase 3 build session).
**Built on:** verified git + direct disk reads. Every hash and claim below was
confirmed by terminal output Andre pasted — not narration, not memory.

> **Read `PROJECT-MAP.md` (repo root) first.** It is the durable orientation doc
> and it is **current** — updated twice this session, committed `f209b5a` and
> `201c6a8`. This handoff is the session-specific supplement.

---

## New standing order locked this session

### 5. Check the locked sources before asking Andre to decide anything.

> *"checking before asking me shall be law from this point on, had i agreed with
> you and selected B we would have overruled an already locked decision"*

This is now law, and the reason is sharper than "check first." **An unchecked
question is a live path to overruling locked architecture with Andre's authority
on it.** It manufactures consent for improvisation. The advisor asked four times
this session; **four times the answer was already locked:**

1. Asked Andre to rule on 12.6 / `is_default` / `template_id` ON DELETE. All
   three were answerable from precedent (11.b, 022, 017). `is_default` **wasn't
   even deferred** — the decisions log states the intent flatly; the *arch ref*
   had added a hedge the locked source never carried.
2. Asked whether to split `tenant_holidays` into its own migration. Not
   architecture at all — file packaging, already answered by the in-repo
   018/019-vs-022 convention.
3. Asked where to document 024. **Decision 25's own "Decision implications for
   already-committed sections" block names the target subsection — and the
   advisor had already read it.** Had Andre picked the other option, D25 would
   have been silently overruled.

**The failure mode, named:** reading the *architecture reference* and stopping,
when the *decisions log* carries the resolution. **The decisions log's "Decision
implications for already-committed sections" blocks are binding instructions,
not commentary.** Read them as law.

### The four from Chats 15–16, still in force

1. **Never hand off unfinished work.** The 85-message ceiling is advisory. Its
   corollary, applied this session: **don't *start* work that can't finish** —
   025 was deferred rather than begun at message 79.
2. **Never take the simplest route because it's easy.** Take the option that best
   supports the locked decision without altering it.
3. **Files-panel swap is the default action at every doc-control close.** Never
   ask. Do it, then verify with `diff -q`.
4. **Never assume, always verify.** Before drafting any migration, read the most
   recent comparable one from disk.

---

## Where the project stands (verified)

- **Branch:** `session-5e-bridge-phase3-schema-generator`
- **Git HEAD:** `201c6a8`, pushed, working tree clean, in sync with origin.
- **Phase 4 baseline:** COMPLETE. Hosted ref `uzjivnmwedfzcgqnnhos` in
  `supabase/PRODUCTION-REF.md`.
- **Phase 3 build:** IN PROGRESS — **22 tables + 1 view + 3 functions.**
- **Migrations on disk: 25.**

### Commits this session (all pushed, all verified via the origin ref line)
- `a985970` — feat(schema): Acknowledgment Gate ×2 (023) + Convention 9
- `f209b5a` — docs(project-map): 21 tables + view
- `5e9ccd2` — feat(schema): tenant_holidays + 3 functions (024)
- `4bcae5e` — docs(arch-ref): tenant_holidays recorded in ALA subsection
- `201c6a8` — docs(project-map): 22 tables + view + 3 functions

HEAD at Chat 17 open was `b535d4f` — the Chat 16 handoff *was* committed, unlike
the session before. This document will likely be the same.

### Open items
**None.** **Zero deferred FKs.** Nothing half-done. **No pending doc-control.**

**One recorded dependency (not an open item):** the `tenant_holidays` rolling
annual top-up needs pg_cron, which isn't built. Until it lands, the calendar
horizon is literally what 024's backfill wrote (2026–2036). Recorded in the
migration header, the arch ref, and PROJECT-MAP.

---

## What 023 settled — Acknowledgment Gate Pattern

`acknowledgment_gate_templates` (11 col, 1 CHECK, 2 idx, 1 FK) and
`acknowledgment_gate_records` (10 col, 1 CHECK, 3 idx, 2 FKs). Verbatim to both
locked sketches. Zero deferred FKs.

**Three "Phase 3 implementation details" resolved — none were open questions:**

| Item | Answer | Precedent |
|---|---|---|
| 12.6 polymorphic FK | single polymorphic col, NO FK, app-layer dispatch | 11.b (022), `clock_events.entity_id` (013) |
| `is_default` | app-layer, no partial UNIQUE | 022 — and the decisions log never deferred it |
| `records.template_id` ON DELETE | RESTRICT | 022's `template_id`, 017's `definition_id` |

**The 12.6 test, reusable:** *does the locked text name the column?* It does —
twice, in both schema sketches. Junction table and typed-FK columns both **delete
the locked columns**; the single polymorphic column preserves them. 017's typed-FK
precedent does not transfer because Decision 3 chose typed FKs **where no locked
column name was at stake.**

**Third consecutive polymorphic reference answered the same way (013, 022, 023).
That is a pattern, not a coincidence.**

**One deliberate difference from 022:** `authorized_entity_id` is **NOT NULL**
where `event_reference_id` is nullable. Each built verbatim to its own sketch —
an acknowledgment is by definition an acknowledgment *of* something. **Do not
harmonize.**

**No seed, no backfill — deliberately inverting 018/019.** Their backfill was
mandatory because `inspections.inspection_type_id` is NOT NULL and a tenant with
zero rows couldn't create an inspection. The inverse holds here: 12.3 makes gates
optional, **zero rows is a valid steady state**, and seeding gate content would
be the platform imposing legal language on tenants — exactly what 12.3 forbids.

**Two enum-coupling CHECKs deliberately absent** — `acknowledger_name` ↔
`requires_typed_name`, and `authorized_entity_type` ↔ `gate_purpose`. Both pairs
straddle the template/record FK, so a DB CHECK physically cannot see both sides.

---

## What 024 settled — tenant_holidays

`tenant_holidays` (6 col, 2 idx, 1 FK) + **three functions**. This one had real
design work in it, driven entirely by Andre's pushback.

**Its own migration, not bundled with ALA** — no FK to any ALA table and none
references it. The 018/019 independent-siblings case, not the 022
one-section-with-intra-section-FKs case. ALA is the calendar's first *consumer*,
not its owner.

**25.3 extends Decision 17's *philosophy*, not its *mechanics*** — platform seeds
at provisioning, tenant owns forever after, no propagation (17.A.3) — but no
operational table references a holiday by FK, so: **no `lock_tier`, no
`is_system`, no protection trigger, no value/label pair, no `sort_order`.** A
tenant may delete every row.

### The three things Andre's pushback changed

1. **"why do we need a cap end year?"** — killed the literal-date-list plan. A
   bounded list **fails silently**: business-day math would stop skipping
   holidays past the cliff with no error, no alert, wrong `fires_at`. Answer:
   `federal_holidays_for_year(integer)`, no cap.
2. **"the number of holidays recognized should be tenant owned"** — already what
   25.3 says. Confirmed the schema resists nothing: plain rows, no lock tier.
   **The seed is a starting default, not a model of what warrantors observe.**
3. **"the seed should carry the shifts"** — Andre's call, overriding the
   advisor's unshifted proposal. Federal observed-shift rule (Sat → preceding
   Fri, Sun → following Mon) on the **five** fixed-date holidays. It's what OPM
   publishes and what most U.S. warrantors follow, so **most tenants edit
   nothing**; unshifted would hand everyone the same correction.

**Tenant policy variance needs zero schema support.** `holiday_date` stores a
concrete *observed* date. Taking the Monday instead of the Friday = edit a row.
Both = add a row. Neither = delete. **Storing observed dates rather than holiday
rules is exactly what makes that work.**

### The functions
- `federal_holidays_for_year(integer)` → 11 holidays, any year, shift applied
- `nth_weekday_of_month(y, m, dow, n)` — helper
- `last_weekday_of_month(y, m, dow)` — helper. **Memorial Day is the *last*
  Monday of May, which the Nth helper cannot express.**

All three IMMUTABLE, read no tables. **Callables, not triggers — 17.A.6's
no-triggers-at-v1 restraint does not bar them.** Conventions per 011: plpgsql,
`set search_path = public`, **no security definer**.

**Year-boundary case is CORRECT, not a bug.** When Jan 1 falls on a Saturday the
observed date shifts *backward into the prior year*:
`federal_holidays_for_year(2028)` returns `2027-12-31`. OPM publishes it that
way and the tenant really is closed that Friday. **Callers must not assume year
N's holidays fall within year N.** Documented in the function header — it would
look like a bug to anyone reading it cold.

### NEW — verification went beyond any prior migration
`db reset` proves a migration *executes*, not that it's *correct*. 024's output
was checked against reality:
```
docker exec supabase_db_warrantyos psql -U postgres -d postgres -c "<sql>"
```
- All 11 dates match OPM for 2026 (July 4 Sat → `2026-07-03 Fri` ✓)
- Backfill produces **exactly 121 rows** (11 × 11 years)
- **Re-running inserts 0** — idempotency proven, not assumed

**Do this for any migration with computed output.** `psql` is not installed in
WSL and `supabase db shell` does not exist in this CLI version — go through the
container.

---

## The build loop (proven across 12 migrations now)

1. Pull the **exact locked schema** from architecture-reference.md / **both**
   decisions logs. **Read the decision's "Decision implications" block — it is
   binding.** Widen the check to patterns and precedents before declaring a gap
   or asking Andre anything.
2. **Read the most recent comparable migration from disk before drafting.**
3. Advisor generates the full `.sql` in chat → Andre downloads →
   `cp "/mnt/c/Users/andre/Downloads/FILE" supabase/migrations/NNN_name.sql`.
4. `git status --short` — confirm it landed (raw bytes, not narration).
5. `supabase db reset` — **replays ALL migrations. Read the NOTICE lines.**
6. **If the migration computes anything, query it in the container and check the
   values against reality.** (NEW this session.)
7. `node scripts/generate-schema-sql.mjs` — **NOT an npm script.**
8. `grep -n "<table>" supabase/schema.sql | cat` — verify CHECKs, PK, indexes,
   FKs (**and their ON DELETE clauses**), RLS, policy, grants. Then
   `git diff supabase/schema.sql | grep "^[-+]" | grep -v "<table>"` — what
   remains should be *only* the new table's own columns.
9. **Draft the Convention 9 doc-control edit BEFORE committing** — see the miss
   below.
10. Pre-commit audit: `git add -N` untracked migrations first. `git diff --stat`
    on `schema.sql` must be **additive only (0 deletions)**.
11. Commit all files together. Push. **Verify the `origin` ref line.**
12. Update PROJECT-MAP + swap the Files panel **immediately**. `diff -q` verify.

### Convention 9 miss this session — don't repeat
024's migration was committed (`5e9ccd2`) **before** its arch-ref doc-control was
drafted, so the Status edit landed in a separate commit (`4bcae5e`) rather than
alongside. Convention 9 wants them together. Content unaffected; noted rather
than papered over. **Draft doc-control before committing the migration.**

---

## Traps (corrected, confirmed, and new)

1. **CONFIRMED AGAIN (3rd + 4th time) — the `architecture-reference.md`
   relocation is a handler error.** Fired **both** times this session.
   - Correct home: **`docs/architecture-reference.md`**
   - Fix: `mv docs/session-handoffs/architecture-reference.md docs/architecture-reference.md`
   - Then `git status --short` must be empty. Both times it was — the misplaced
     file is byte-identical, so the move leaves no trace.
   - **This is now predictable. Expect it on every arch-ref swap.**

2. **NEW — "done" is not verification.** Andre replied "done" to a verification
   command; the advisor asked again for the actual bytes. **The output is the
   point.** Applies to Andre's confirmations exactly as it applies to Claude
   Code's narration.

3. **NEW — the advisor's own draft needs auditing before Andre touches it.**
   Three defects were caught in the 024 draft *by re-reading it*, before it ever
   reached disk: an ambiguous `label` variable that plpgsql would have rejected,
   a four/five miscount, and the year-boundary case. **Re-read your own draft.**

4. **NEW — no `psql` in WSL; no `supabase db shell` in this CLI.** Use
   `docker exec supabase_db_warrantyos psql -U postgres -d postgres -c "..."`.

5. **NEW — `db reset` on a fresh DB has zero tenants, so backfills insert
   nothing.** A clean reset proves the SQL parses, **not** that the backfill
   works. Insert a scratch tenant, run the backfill by hand, count, re-run for
   idempotency, then clean up. Deleting the scratch tenant requires deleting its
   child rows first — every `tenant_id` FK is RESTRICT by default.

6. **Pattern-memory of conventions is unreliable. Read the prior migration.**

7. **`supabase db reset` can fail transiently on the container.** Re-run before
   diagnosing your SQL.

8. **The anchor abort is the system working.** It has never fired on a bad file —
   only on the advisor's wrong assumption. Scripts verify all anchors *before*
   any write, so a successful write is positive proof.

9. **`sed` output does not show blank lines distinctly. Use `cat -A`.** Note
   em-dashes render as `M-bM-^@M-^T` under `cat -A` — that's correct UTF-8, not
   corruption.

10. **Verify the Files-panel swap with `diff -q`, not by eyeball.**

11. **Don't assert a command will fail — run it.**

12. **`git diff` opens a pager that swallows subsequent commands.** Always `| cat`.

13. **Untracked files don't show in `git diff --stat`.** `git add -N` first.

14. **The `/mnt/project/` mount and the Files panel BOTH lag disk.** Always read
    canonical docs from disk.

15. **Migration file mode is `100755`, and that's correct.** Not a bug.

16. **Decision 3 is in the PHASE 2 log.** Both logs are live.

---

## Doc-control state at close — ALL CLOSED

- `docs/architecture-reference.md` — Acknowledgment Gate Status block
  (Designed → Implemented (schema)) + three outstanding questions marked
  **RESOLVED** (`a985970`); ALA "Response window" subsection expanded to record
  024 (`4bcae5e`). Files panel refreshed and **`diff -q`-verified**.
- `PROJECT-MAP.md` — updated twice (`f209b5a`, `201c6a8`): counts, migration list
  (25), phase table row, two new per-table detail bullets, Acknowledgment Gate
  removed from DESIGNED-NOT-BUILT. Files panel refreshed and **`diff -q`-verified**.
- `CLAUDE-rev6.md` — untouched. Panel copy accurate.
- Decisions logs (Phase 2 + Phase 3) — untouched. Panel copies accurate.

### Known cosmetic lag (expected, not a bug)
PROJECT-MAP's "Last built" cites `4bcae5e` — the HEAD it describes — not
`201c6a8`, its own commit hash. A doc cannot cite its own not-yet-created hash.
**The hash is the load-bearing part.**

---

## What to build next — 025_ala_system.sql

**Deferred from Chat 17 at message 79** under standing order #1's corollary: don't
start what can't finish. **All research is done** — sources read, precedents
mapped, conflict checked. Chat 18 can draft almost immediately.

### Three tables, one migration
`ala_templates`, `ala_documents`, `ala_document_revisions` — one section with
intra-section FKs, the 022 case. **`tenant_holidays` is already built (024).**

**Locked sketches, verified from disk:**
- `ala_templates` — **8 columns.** arch ref 3884–3924.
- `ala_documents` — **20 columns.** arch ref 3925–4005 gives 19; **Decision 25.4
  adds `overdue_flagged_at timestamptz nullable`**, which the arch ref sketch
  does NOT carry (it's named in prose only). **Don't miss it.**
- `ala_document_revisions` — **7 columns.** Decision 26.1, decisions log
  ~4750–4762. **Structurally identical to `work_authorization_revisions` (022).**

### Everything is already decided — apply, don't ask
| Item | Answer | Precedent |
|---|---|---|
| `documents.claim_id` **UNIQUE** | **present** | locked; **26.2 explicitly refuses to reopen** |
| `documents.claim_id` ON DELETE | RESTRICT | 010/016/020/021/022 |
| `documents.template_id` ON DELETE | RESTRICT | 022, 023, 017 |
| `revisions.ala_document_id` ON DELETE | **CASCADE** | 022's revisions — identical shape |
| `revisions.revised_by_user_id` ON DELETE | RESTRICT | 022 |
| `templates.is_default` | app-layer | 022, 023 — **the third parallel flag, and the arch ref names it as such** |

### Conflict already checked — none
D25 says `clock_events` needs `ala_document` (entity_type) and
`ala_response_overdue` (event_type). **013 already carries both**, plus
`ala_decline_window_expired`. Verified in `schema.sql`. **No `alter table`
migration needed.**

### Things that will bite
- **`markup_percent_snapshot numeric(4,3)`** — the first non-uuid/text/jsonb/
  bool/timestamptz/date type in Phase 3.
- **`signature_method text NOT NULL DEFAULT 'in_platform_widget'`** — a
  platform-locked CHECK enum **with a default**. Only 022's `status` precedes it.
- **No `status` column.** The three-state machine (unsigned / signed / declined)
  is **derived** from `claimant_decision` + `signed_at`. Deliberate — 19.7.
  Don't add one.
- **`overdue_flagged_at` is a 4th orthogonal signal, NOT a 4th state** (25.4).
- **Policy name byte-check:** `"ala_document_revisions: tenant read"` = 35 bytes.
  Fine.
- **Deliberate omissions to document:** no counter-signature column (the arch ref
  is explicit — one-sided consent); no `is_default` partial UNIQUE; no DB CHECK
  for "accepted ⇒ signed_at non-null" (app-layer, 19.1); no `created_at`/
  `updated_at` on revisions (locked sketch has `revised_at` only); no
  `deleted_at` on documents.

### Then, dependency-ordered
- **Notice of Defect** (Decision 14) — no FK to work_plans in either direction.
- **Service Reports** (Decision 21) — UNIQUE(claim_id); parts/photos
  JSONB-vs-child-table explicitly flagged as Phase 3.
- **Customer-O&M Authorization** (Decision 28) — `om_authorization_documents`.
  **Four** built sections now reference it for the O&M blocking check.
- **Claim Intake Data Model** (Tier 3) — hybrid hard-columns + JSONB, settled
  against the two real intake workbooks. **Real Tier 3 design work.**
- **pg_cron enablement + cron handler** — `clock_events` (013) is the table only.
  **Also unblocks `tenant_holidays`' rolling top-up.** Hourly, `'0 * * * *'`.

---

## First moves in Chat 18

1. `cd ~/Projects/warrantyos && git status && git log --oneline -5` — expect
   clean, HEAD `201c6a8` (or the commit carrying this handoff).
2. Read `PROJECT-MAP.md` **from disk**.
3. Build **025_ala_system.sql**. Pull the locked sketches from arch ref
   3884–4005 + decisions log Decision 26.1. **Add `overdue_flagged_at` from
   25.4 — it's not in the arch ref sketch.** **Read 022's bytes from disk before
   drafting** (standing order #4) — `work_authorization_revisions` is the
   template for `ala_document_revisions`.
4. **Draft the Convention 9 doc-control BEFORE committing the migration.**

**No pending doc-control. No open items. Nothing carried forward but 025, which
is fully researched and ready to draft.**
