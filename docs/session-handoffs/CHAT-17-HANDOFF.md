# Handoff → Chat 17

**Written:** 2026-07-16 at the close of Chat 16 (sixth Phase 3 build session).
**Built on:** verified git + direct disk reads. Every hash and claim below was
confirmed by terminal output Andre pasted — not narration, not memory.

> **Read `PROJECT-MAP.md` (repo root) first.** It is the durable orientation doc
> and it is **current** — updated twice this session, committed `b8326e9` and
> `f0cab01`. This handoff is the session-specific supplement.

---

## New standing order locked this session

### 4. Never assume, always verify.

> *"never assume, always verify, make that law.."*

This is now law, and it earned the promotion within minutes of being spoken.
Drafting 021 from pattern-memory of the previous handoff, the advisor wrote
`public.current_tenant_id()` — a helper **that does not exist**. The real one is
`public.get_user_tenant_id()`. That alone fails `supabase db reset` outright.

Reading 020's actual bytes before drafting caught **four more** silent
divergences in the same draft: uppercase DDL (precedent is lowercase), missing
`public.` schema prefix, three separate `grant` statements (precedent is one
combined line), a quoted descriptive policy name written bare, and a phantom
`on delete cascade` on `tenant_id` (precedent carries no clause).

Six defects in one file, all from pattern-memory, all caught by reading real
bytes. **Before drafting any migration, read the most recent comparable one from
disk.** Do not reconstruct conventions from a handoff's description of them.

### The three from Chat 15, still in force

1. **Never hand off unfinished work.** The 85-message ceiling is advisory. This
   session ran to ~120 under this order and closed clean.
2. **Never take the simplest route because it's easy.** Take the option that
   best supports the locked decision without altering it. This produced 022's
   `event_reference_id` answer (below).
3. **Files-panel swap is the default action at every doc-control close.** Never
   ask. Do it, then verify.

---

## Where the project stands (verified)

- **Branch:** `session-5e-bridge-phase3-schema-generator`
- **Git HEAD:** `f0cab01`, pushed, working tree clean, in sync with origin.
- **Phase 4 baseline:** COMPLETE. Hosted ref `uzjivnmwedfzcgqnnhos` in
  `supabase/PRODUCTION-REF.md`.
- **Phase 3 build:** IN PROGRESS — **19 of ~20 tables built, plus 1 view.**
- **Migrations on disk: 23** (confirmed via `ls | wc -l`).

### Commits this session (all pushed, all verified via the origin ref line)
- `56dc7fe` — feat(schema): inspections (021) + Convention 9 Status lines
- `b8326e9` — docs(project-map): 16 tables + view
- `1cada01` — feat(schema): Customer Work Authorization ×3 (022) + Convention 9
- `f0cab01` — docs(project-map): 19 tables + view

Note: HEAD at Chat 16 open was `327e6a3`, exactly as the Chat 15 handoff
predicted — because that handoff was never committed. This document will be the
same: a handoff cannot cite the commit that carries it.

### Open items
**None.** **Zero deferred FKs.** Nothing half-done. **No pending doc-control.**
Nothing carried into Chat 17.

---

## What 021 settled — `inspections`

Built verbatim to the locked sketch: **13 columns, 3 CHECKs, 2 indexes, 4 FKs.**
Column block matched the arch ref exactly — zero drift.

This table is the arch ref's **canonical reference example for the role-based
decision tree**. Five enum-like columns span three patterns:

| Column | Pattern | Role |
|---|---|---|
| `performed_by` | platform-locked CHECK | structural axis |
| `paid_by` | platform-locked CHECK | structural axis |
| `inspection_type` | Tenant-Editable Defaults | categorization |
| `inspection_trigger` | Tenant-Editable Defaults | categorization |
| `status` | platform-locked CHECK | workflow-driver |

**Do not harmonize these.** Future v2 entities with multiple enum-like columns
follow the same per-column reasoning rather than picking one uniform pattern.

**Completed step 4** of the Tenant-Editable Defaults six-step convention (the
operational table's FK + value snapshot column pairs). **Step 5 — the app-layer
canonical validation helper — remains**, so that pattern's Status stays
`Partially implemented (schema)`. Andre's call, verbatim: *"it stays Partially
implemented (schema) until it has change"*. It moves only when step 5 lands.

### `performed_by` and `paid_by` are two orthogonal axes

Deliberately **not** one conflated enum, and there is **no CHECK coupling them**.
Audit Topic 11's three-value enum (`internal | third_party | customer_paid`)
cannot express a claimant-funded warrantor-performed inspection, or a
warrantor-performed inspection reimbursed by a vendor. All six combinations are
operationally real. A coupling CHECK would re-introduce exactly the conflation
the enum was rejected for.

### ON DELETE — one deferred, two not

- **`claim_id` → RESTRICT.** The one genuinely deferred clause ("not yet
  locked... a Phase 3 implementation detail"). Resolved per the arch ref's own
  named parallel, matching 010/016/020.
- **The two lookup FKs → RESTRICT, and this was NOT a deferred question.** The
  arch ref states outright that ON DELETE on them "is governed by the lookup
  tables' soft-delete semantics... hard-deletion is not an ordinary path."
  RESTRICT is also the *only architecturally available* clause: both columns are
  NOT NULL, so SET NULL is illegal, and CASCADE would destroy inspection history.

**017's CASCADE does not transfer.** Decision 3's rationale there is that a
custom field value is a *dependent attribute*. An inspection is an *independent
record* with its own state machine and findings. Same distinction resolved 022's
revisions table the other way — see below.

---

## What 022 settled — Customer Work Authorization (3 tables)

`work_authorization_templates`, `work_authorization_documents`,
`work_authorization_revisions`. Built as **one migration** because they are one
section with intra-section FKs. (018/019 were separate files only because they
were independent siblings.)

The customer-facing **COMMITMENT** generated from a Work Plan's **INTENT** (020).
**Universal blocking gate:** no on-site activity proceeds without an approved
document for that event. SOP 1 names only the inspection case; the architecture
extends the gate to all on-site activity intentionally — SOP 1 captured the
canonical instance, **not the limit**. Enforcement is a Server Action
precondition, not a DB constraint.

**One-to-many with claims** (no UNIQUE on `claim_id`). The contrast worth
internalizing: `ala_documents` and `service_reports` DO carry UNIQUE(claim_id)
because they bound **the claim as a whole**; Work Authorization and `work_plans`
do not, because they bound **one event**, which recurs.

### Decision 11.b RESOLVED — the standing-order-#2 case study

`event_reference_id` → **single nullable column, app-layer dispatch, NO FK.**

The arch ref named three candidates. The reasoning pattern to reuse:

- **Junction table** — doubly excluded. It eliminates the locked
  `event_reference_id` column, *and* supports many-to-many, which this section's
  own "No multi-event-per-document" omission forbids.
- **Separate typed FK columns** (`inspection_id`, `work_plan_id` + CHECK) — would
  give real referential integrity, and 017 is a genuine precedent for preferring
  typed FKs per Decision 3. **But it deletes `event_reference_id`, the column
  Decision 11 locks by name.** 017's precedent does not transfer: Decision 3
  chose typed FKs where *no locked column name was at stake*. Here one is.
- **Single nullable column** — preserves the locked two-column shape verbatim.

**In-repo precedent:** `clock_events.entity_id` (013) carries no FK and is
resolved by `entity_type`. Same problem, same answer, already built. The arch ref
also anticipates the consequence and accepts it: *"Without a database-enforced
FK... this becomes an application-layer integrity concern."*

### ON DELETE on all five FKs

| FK | Clause | Why |
|---|---|---|
| `claim_id` | RESTRICT | matches 010/016/020/021 |
| `template_id` | RESTRICT | templates soft-delete; parallel to 017's `definition_id` |
| `revised_by_user_id` | RESTRICT | users soft-remove; matches 020 |
| `work_authorization_document_id` | **CASCADE** | a revision is a dependent attribute, not an independent record — 017's entity-FK reasoning |
| `event_reference_id` | none | no FK exists |

The CASCADE/RESTRICT split inside one migration is the point: **different
relationship, different answer.** Do not harmonize.

### Deliberate omissions on 022
- **No partial UNIQUE on `is_default`.** App-layer. ALA's and Acknowledgment
  Gate's `is_default` flags carry the *identical* open question — resolve them
  the same way when those sections land.
- **No customer FK, no O&M provider FK.** Direct field capture is Decision 11's
  locked schema. Any move to FK + Snapshot warrants its own decision.
- **No `work_plan_id` FK** — `event_reference_id` IS that reference.
- **No DB CHECKs** for the denial/signature/conditional-field invariants (17.A.6
  caps v1 DB enforcement).
- **No `created_at`/`updated_at` on revisions.** The locked sketch carries only
  `revised_at`. Built verbatim — an applying table does not vary the locked
  column set.
- **No clock_events row created in the migration.** The Server Action that sends
  or resends inserts `work_authorization_response_overdue`. 013 already carries
  the event_type value.

### One CHECK added beyond the locked text — flagged and accepted
`customer_decision` carries a CHECK. The sketch comments `-- 'approved' |
'denied'` but, unlike `event_type` and `status`, never says *"CHECK constraint
enforces values"*. Flagged to Andre before drafting; kept, because 17.A.6's cap
explicitly admits closed value sets and omitting it would let
`customer_decision = 'maybe'` into an audit-bearing legal artifact.

---

## NEW: the 63-byte identifier cap is now live

`supabase db reset` emitted:

```
NOTICE (42622): identifier "work_authorization_documents: members can view
their tenant's rows" will be truncated to
"work_authorization_documents: members can view their tenant's r"
```

**All three 022 policy names exceeded PostgreSQL's 63-byte identifier limit and
were being silently truncated mid-word.** They functioned, but stored mangled.

**Resolution (Andre's call): shorten to `"<table>: tenant read"`.** The arch ref
documents the convention as a *shape* — `<table>: <who> can <action>` — not a
fixed string. Shortening honors the shape; accepting truncation stores names the
convention never intended.

**This will recur.** Any table whose name approaches ~30 characters will overflow
the usual wording. `om_authorization_documents` and
`acknowledgment_gate_templates` are both close. Check the byte length before
writing the policy name; longest 022 name is now 44 bytes.

---

## The build loop (proven across 10 migrations now)

1. Pull the **exact locked schema** from architecture-reference.md / **both**
   decisions logs. Check the decision's deferred-questions list. **Widen the
   check to patterns and precedents before declaring a gap.**
2. **NEW — read the most recent comparable migration from disk before drafting.**
   `grep -in "create table\|create policy\|grant\|enable row level" <prior>.sql`
   then read the header and column block. Six defects in one draft came from
   skipping this.
3. Advisor generates the full `.sql` in chat → Andre downloads →
   `cp "/mnt/c/Users/andre/Downloads/FILE" supabase/migrations/NNN_name.sql`.
4. `git status --short` — confirm it landed (raw bytes, not narration).
5. `supabase db reset` — **the real validation.** Replays ALL migrations.
   **Read the NOTICE lines**, not just the pass/fail.
6. `node scripts/generate-schema-sql.mjs` — **NOT an npm script.**
7. `grep -n "<table>" supabase/schema.sql | cat` — verify CHECKs, PK, indexes,
   FKs (**and their ON DELETE clauses**), RLS, policy, grants. Then
   `git diff supabase/schema.sql | grep "^[-+]" | grep -v "<table>"` — what
   remains should be *only* the new table's own columns.
8. Convention 9 Status-line edit via a downloaded **anchored Python script**.
9. Pre-commit audit: `git add -N` untracked migrations first. `git diff --stat`
   on `schema.sql` must be **additive only (0 deletions)** — the property that
   proves no drift.
10. Commit all files together. Push. **Verify the `origin` ref line.**
11. Update PROJECT-MAP + swap the Files panel **immediately**.

---

## Traps (corrected, confirmed, and new)

1. **NEW — pattern-memory of conventions is unreliable. Read the prior
   migration.** Six defects in the 021 draft, including a nonexistent helper
   function name that would have failed `db reset`. See standing order #4.

2. **NEW — `supabase db reset` can fail transiently on the container.** One run
   died at "Initialising schema... error running container: exit 1" *before any
   migration applied*. Re-running with `--debug` succeeded completely. **Don't
   diagnose your SQL from a container failure** — re-run first. (Corollary of
   trap #6: don't assert, run it.)

3. **NEW — chat-paste corruption can make a clean file look corrupted.** A
   `git diff` paste rendered `two-column shape` as `two-château shape`. The file
   was fine; git's object store confirmed five clean occurrences. **The proof is
   mechanical: the anchor script asserts before writing, so a successful write is
   positive proof the anchor matched.** If a paste looks corrupted, check
   `git show HEAD:<file> | grep` before believing it.

4. **The anchor abort is the system working.** It has now fired on the advisor's
   wrong assumption every single time, never on a bad file. The scripts verify
   all anchors *before* any write, so a failed anchor leaves the file untouched.

5. **`sed` output does not show blank lines distinctly. Use `cat -A`.** Hit
   *again* this session — the advisor raised a false alarm about a missing blank
   line from `sed` output; `cat -A` showed the `$` right there. **`cat -A` before
   you trust whitespace or line breaks**, in both directions.

6. **CONFIRMED — the `architecture-reference.md` relocation is a handler error.**
   Happened **both** times this session (Andre's own diagnosis: misplacing the
   file at the drop target during upload; not a VS Code or git defect).
   - Correct home: **`docs/architecture-reference.md`**
   - Fix: `mv docs/session-handoffs/architecture-reference.md docs/architecture-reference.md`
   - Then confirm `git status --short` is empty. Both times it was — the
     misplaced file is byte-identical to the committed one, so the move leaves no
     trace.

7. **NEW — verify the Files-panel swap with `diff -q`, not by eyeball.** Andre
   asked directly whether a command could confirm it. The panel itself is not
   reachable from WSL — but this is strictly better than reading a Status line,
   because it proves *every* byte:
   ```
   diff -q /mnt/c/Users/andre/Downloads/PROJECT-MAP.md PROJECT-MAP.md && \
   diff -q /mnt/c/Users/andre/Downloads/architecture-reference.md docs/architecture-reference.md && \
   echo "BOTH DOWNLOADS MATCH DISK"
   ```
   Trap #5's old content-check (reading the `**Last built:**` header / the
   Status line) is now the **fallback** for when the Downloads copy is gone.

8. **Don't assert a command will fail — run it.**

9. **`git diff` opens a pager that swallows subsequent commands.** Always `| cat`.

10. **Untracked files don't show in `git diff --stat`.** `git add -N` first.

11. **The `/mnt/project/` mount and the Files panel BOTH lag disk.** Always read
    canonical docs from disk via `sed`/`cat` + paste.

12. **Migration file mode is `100755`, and that's correct.** Every Phase 3
    migration (005–022) is 755 because of the download→`cp` workflow; only the
    pre-existing 000–004 are 644. **Not a bug — don't "fix" it.**

13. **Decision 3 is in the PHASE 2 log.** Both logs are live.

14. **Terminal paste collisions.** A leftover echo fused with a pasted command
    into `resetnode`, producing a confusing CLI error. Nothing ran, nothing
    broke. Re-run on a clean prompt.

15. **Advisor-side tool noise.** The advisor's `end_conversation` tool misfired
    roughly eight times this session when a command block was intended. It was
    never confirmed and has **zero effect on the repo**. Ignore it.

---

## Doc-control state at close — ALL CLOSED

- `docs/architecture-reference.md` — three Status blocks updated across two
  commits (Inspections Foundation → Implemented (schema); Tenant-Editable
  Defaults → prose only, value unchanged; Customer Work Authorization →
  Implemented (schema)), plus Decision 11.b's outstanding-question entry marked
  **RESOLVED** with the full reasoning. Each landed in the same commit as its
  migration (Convention 9). Files panel refreshed and **`diff -q`-verified**.
- `PROJECT-MAP.md` — updated twice (`b8326e9`, `f0cab01`): counts, migration list
  (23), phase table row, roadmap step 2, two new per-table detail bullets,
  Inspections Foundation and Customer Work Authorization both removed from
  DESIGNED-NOT-BUILT, Tenant-Editable Defaults still PARTIAL. Files panel
  refreshed and **`diff -q`-verified**.
- `CLAUDE-rev6.md` — untouched. Panel copy accurate.
- Decisions logs (Phase 2 + Phase 3) — untouched. Panel copies accurate.

### Known cosmetic lag (expected, not a bug)
PROJECT-MAP's "Last built" line cites `1cada01` — the HEAD it describes — not
`f0cab01`, its own commit hash. A doc cannot cite its own not-yet-created hash.
**The hash is the load-bearing part.** Update on the next substantive change, not
as standalone churn.

---

## What to build next (dependency-ordered)

- **Acknowledgment Gate Pattern** (Decision 12, 2 tables) — **the natural next
  one.** It carries its own polymorphic FK question (12.6) that is *structurally
  identical* to 11.b, and 11.b now sets the precedent: the locked text commits to
  a two-column shape (`authorized_entity_type` + `authorized_entity_id`), so the
  single-nullable-column-with-app-layer-dispatch answer should follow the same
  reasoning. **Check whether Decision 12 locks the column by name** — that was
  the deciding factor in 11.b. It also carries the same `is_default` question,
  answered app-layer on 022. Both FK targets (`claims` 016,
  `work_authorization_documents` 022) now exist.
- **ALA System** (Decision 19, ext. 25/26) — `ala_templates`, `ala_documents`,
  plus **`ala_document_revisions`** (Decision 26) and **`tenant_holidays`**
  (Decision 25, business-day math). Largest remaining section. Carries
  UNIQUE(claim_id) — the deliberate contrast against 022.
- **Notice of Defect** (Decision 14) — no FK to work_plans in either direction.
- **Service Reports** (Decision 21) — carries UNIQUE(claim_id); the parts/photos
  JSONB-vs-child-table question is explicitly flagged as Phase 3.
- **Customer-O&M Authorization** (Decision 28) — `om_authorization_documents`.
  Three built sections (ALA, Service Report, Work Authorization) already
  reference it for the O&M blocking check.
- **Claim Intake Data Model** (Tier 3) — the hybrid hard-columns + JSONB schema,
  settled against the two real intake workbooks. **Real Tier 3 design work**, not
  a migration you can pull from a locked sketch.
- **pg_cron enablement + the cron handler function** — `clock_events` (013) is the
  table only. Every scheduled job must be defined in a version-controlled
  migration alongside its supporting function; cron schedule is hourly,
  `'0 * * * *'`.

---

## First moves in Chat 17

1. `cd ~/Projects/warrantyos && git status` — expect clean, HEAD `f0cab01` (or
   the commit carrying this handoff, if it was committed).
2. `git log --oneline -5` — expect `f0cab01` at or near top.
3. Read `PROJECT-MAP.md` **from disk**.
4. Build **Acknowledgment Gate Pattern** (Decision 12). Pull its locked schema
   from the arch ref + the Phase 3 decisions log. **Read `022`'s bytes from disk
   before drafting** (standing order #4). Surface the 12.6 polymorphic FK
   question with 11.b as precedent, and the `is_default` question with 022 as
   precedent. Watch the 63-byte cap on
   `acknowledgment_gate_templates` policy names.

**No pending doc-control. No open items. Nothing carried forward.**
