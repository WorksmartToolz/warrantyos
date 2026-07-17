# CHAT 20 HANDOFF — WarrantyOS Phase 3 Build

**Written at Chat 19 close, 2026-07-17.**

Every state claim below was copied from Andre's actual pasted terminal output.
Nothing here is narrated, predicted, or reconstructed. If you did not see
Andre's output, you do not know what happened — that rule held all of Chat 19
and it is why this document is short.

---

## Ground truth (verified from Andre's terminal)

- **HEAD:** `f5ddc9c`, pushed, `origin/session-5e-bridge-phase3-schema-generator`
- **Branch:** `session-5e-bridge-phase3-schema-generator`
- **Working tree:** clean (`git status --short` empty)
- **Migrations on disk:** 28
- **Built:** 26 tables + 1 view + 3 functions
- **Files panel:** matches disk for `PROJECT-MAP.md` (51,540 bytes) and
  `architecture-reference.md` (396,356 bytes) — both verified `diff -q`,
  both `IDENTICAL`
- **Pending doc-control:** none
- **Open items:** none

### Commit chain this session

| Hash | What |
|------|------|
| `965ef68` | feat(schema): Claim Intake Data Model — 25 columns on claims (027) |
| `f5ddc9c` | docs(project-map): Claim Intake data model built (027) |

**Note the table count did not move.** 027 is an `alter table` on the `claims`
shell (016) — 25 columns, no new table. 26 tables still stands. Migration count
went 27 → 28.

---

## READ THIS FIRST, IN THIS ORDER

1. **`PROJECT-MAP.md`** (repo root) — the durable orientation doc, current as of
   `f5ddc9c`. It carries the full per-table rationale for every built table
   including 027. **This handoff deliberately does not restate it.** Read the map.
2. **`git log --oneline -10`** — clean and accurate.
3. **`CLAUDE-rev6.md`** — doc-control conventions 7/7a/8/9 are committed law.

Ground truth is the git repo and direct disk reads. Not the Files panel, not any
handoff summary, not this document.

---

## STANDING ORDERS (law, in force)

**#1 — Never hand off unfinished work.** The 85-message ceiling is advisory.
Corollary: don't START work that can't finish. *(Applied at Chat 19 close: 24
messages left, Service Report needs ~25. Closed instead of starting.)*

**#2 — Never take the simplest route because it's easy.** Take the option that
best supports the locked decision without altering it.

**#3 — Files-panel swap is the DEFAULT ACTION at every doc-control close.**
Never ask, do it, then verify with `diff -q`.

**#4 — Never assume, always verify.** Before drafting any migration, read the
most recent comparable one's real bytes from disk. Pattern-memory is unreliable.

**#5 — CHECK THE LOCKED SOURCES BEFORE ASKING ANDRE TO DECIDE ANYTHING.**
(Andre verbatim, Chat 17: *"checking before asking me shall be law from this
point on, had i agreed with you and selected B we would have overruled an
already locked decision"*.)

> **THE NAMED FAILURE MODE:** reading the architecture-reference and stopping,
> when the **DECISIONS LOG** carries the resolution. Its *"Decision implications
> for already-committed sections"* blocks are **BINDING INSTRUCTIONS**.

**#6 — ONE COMMAND AT A TIME. NO EXCEPTIONS.** Andre is dyslexic. Every command
gets its own message, labeled **▶ RUN IN WSL** or **▶ RUN IN CLAUDE CODE**. Wait
for the output. Read it. Confirm it. Then the next one. Never two code blocks.

**#7 — THE OUTPUT IS THE ONLY TRUTH.** Do not author it, predict it, or treat an
empty paste as success. **"done" from Andre is NOT verification** — ask for the
bytes. *(Fired twice in Chat 19; both times the re-ask was correct.)*

---

## NEXT UP — 028 = Service Report Submission

**Sequencing is settled and was Andre's correction, not Claude's read.** Chat 19
initially proposed Service Report first on FK-resolvability grounds — the wrong
axis. Andre: *"without the Claim Intake you have no Service Report Submission or
Customer-O&M Authorization. the claim intake is the upstream event of these
three."* He was right. Sequence by the operational event chain, not by what the
database will accept.

That leaves exactly two sections with tables left to build:

| # | Section | Source | State |
|---|---------|--------|-------|
| **028** | **Service Report Submission** | arch-ref §"Service Report Submission" (~line 4833 pre-027; **re-locate by content, 027's doc-control shifted lines**) + Decision 21 | Ready. Full schema in the arch ref. |
| **029** | **Customer-O&M Authorization** | Decision 28 (no arch-ref section) | Blocked until 028 — see below. |

**Work Authorization is NOT a candidate. It is built (022, Decision 11.)**

### What Chat 19 already verified about 028 — do not re-derive

- **Decision 21 adds ZERO columns to `service_reports`.** It says so outright:
  "No changes to service_reports table. No changes to clock_events table." Its
  two additions are `tenants.settings.service_report_response_days` (default 3,
  bounds 3–30, calendar days) and a `service_report_acquiesce_window` feature
  flag. **Both are provisioning-layer. Neither belongs in the migration.**
- **The schema lives in the arch ref, not in a decision.** Decision 21
  presupposes the table's shape.
- **`clock_events` already carries what 028 needs.** Verified in 026's committed
  bytes: `event_type` includes `service_report_response_due`, `entity_type`
  includes `service_report`. **No `alter table` needed** — unlike 026, like 025.
- **`UNIQUE(claim_id)`** — one report per claim, structurally. 026's header names
  the contrast explicitly: `ala_documents` (025) and `service_reports` are UNIQUE
  per claim; `work_plans` (020), `work_authorization_documents` (022), and
  `notices_of_defect` (026) are one-to-many.
- **Two open Phase 3 flags in the section, both answerable from precedent —
  check before asking Andre (#5):** `parts_used` / `photos`
  JSONB-vs-child-table (the section locks `personnel` as JSONB "because no
  downstream join surface" and flags the other two on *cost-tracking* grounds;
  Parts Fulfillment is out of scope per Decision 16, so no join surface exists
  at v1); and `claim_id` ON DELETE (every claim-child FK in the repo is
  RESTRICT — 010/016/020/021/022/025/026; the lone CASCADE is
  `custom_field_values`, which is 017's deliberate choice because values are
  attributes, not records).
- **Dual-FK submitter with a CONDITIONAL XOR.** The arch ref: "exactly one
  non-null **when submitted**; both null when the report is in pre-submission
  draft." This is 010's conditional shape, **not** 026's unconditional one — 026's
  header says "DO NOT HARMONIZE" about exactly this and it cuts both ways.
  A service report HAS a draft state; a Notice of Defect does not.
- **What Chat 19 did NOT read:** the arch-ref section past its schema block (the
  seven-SOP-content-items mapping, the customer review mechanism, the clock
  event prose). **Read the whole section before drafting.**

### 029 is blocked on 028 — and it's a soft block worth understanding

`om_authorization_documents` (Decision 28) is polymorphic over three parents via
`event_type` + `event_reference_id`: `ala_documents` (built, 025),
`work_authorization_documents` (built, 022), and `service_reports` (**not
built**). The FK is app-layer only, matching 022's shape — so the migration would
*execute* fine. That is exactly the "applied clean proves it executes, not that
it's correct" trap. Do not build 029 first.

Decision 28 is otherwise complete and self-contained: two tables
(`om_authorization_documents`, `om_authorization_templates` — read the schema
block, don't trust a count from a handoff), four status values (`unsigned` |
`signed` | `closed` | `stale` — **no `voided`, no `superseded`**, 28.5 is
explicit about why), and zero open items. 28.7's permission-swap is app-layer
prose, not schema.

**Expect the Notice-of-Defect question again:** the arch ref has no Customer-O&M
Authorization section. Chat 18's precedent on 026 was **not to write one** — the
decisions log holds the locked spec, the migration header carries the rationale,
PROJECT-MAP records the gap. Writing the section would be design-era work.

---

## Verification discipline (carried forward, still law)

- **"db reset applied clean" proves a migration EXECUTES, not that it's
  CORRECT.** For anything with computed output, query the DB:
  `docker exec supabase_db_warrantyos psql -U postgres -d postgres -c "..."`
  (psql is NOT installed in WSL; `supabase db shell` does NOT exist in this CLI.)
  Chat 19 used `\d public.claims` to verify all 25 columns, 3 CHECKs, 2 partial
  indexes, and the FK actually landed — not the reset log.
- **db reset creates a fresh DB with ZERO TENANTS** — backfills insert nothing,
  so a clean reset does NOT prove a backfill works.
- **Re-read your OWN draft before handing it to Andre.** This caught two real
  defects in Chat 19 before they reached him — see below.
- **Anchor discipline: verify ALL anchors before writing ANY.** Chat 19's
  PROJECT-MAP script aborted on anchor 2. That is the system working.

### The anchor lesson Chat 19 learned the hard way — read this before any script

`cat -A` shows real bytes but escapes them: an em-dash appears as `M-bM-^@M-^T`.
**Do not reconstruct the anchor from that.** Chat 19 did, and the script aborted —
not because of the em-dashes (those were fine) but because `cat -A` output made
it easy to miss that continuation lines in PROJECT-MAP.md carry **two leading
spaces**. `grep -n` hides leading whitespace the same way.

**The reliable move:** `sed -n 'X,Yp' file > /tmp/f.txt` then `code /tmp/f.txt`
and copy from VS Code. Use `cat -A` only to *check* for blank lines and trailing
whitespace, never as the source you copy from.

---

## Established workflow (unchanged, works)

1. Read the locked sources — **decisions log first**, then arch ref.
2. Read the most recent comparable migration's real bytes (#4).
3. Draft; **re-read your own draft**.
4. Present file → Andre downloads → `cp` into `supabase/migrations/`.
5. `supabase db reset` → verify it applied.
6. `node scripts/generate-schema-sql.mjs`.
7. Verify structure landed **in the DB**, not the log. `/tmp` + `code /tmp/file`.
8. Check the diff is additive (`git diff --stat`); inspect any deletions.
9. **Convention 9: draft the doc-control BEFORE committing** — the arch-ref
   Status-line edit lands in the SAME COMMIT as its migration.
10. Commit (migration + doc-control together) → push → verify the ref line.
11. PROJECT-MAP update → its own commit → push.
12. Files-panel swap (#3) → verify with `diff -q`.

**File writes:** download-from-chat plus `cp`. Not Claude Code, not heredoc.
**Doc-control edits:** Python script with pre-verified anchors, run via `/tmp`.

### Downloads path — use the explicit one

`/mnt/c/Users/*/Downloads/` **fails**: the wildcard matches `postgres`,
`Default`, `Public`, and `andre`, and cp errors on all of them. Use:

```
/mnt/c/Users/andre/Downloads/
```

To hand Andre a repo file for a panel swap, `cp` it INTO that folder. Do not
route him through VS Code Save-As — Chat 19 did and he corrected it.

---

## RECURRING TRAP — expect it on every arch-ref panel swap

The uploaded `architecture-reference.md` lands in `docs/session-handoffs/`
instead of `docs/`. **Fired 6x across Chats 16–19.** Fix:

```
mv docs/session-handoffs/architecture-reference.md docs/architecture-reference.md
```

Then `git status --short` must be empty — the file is byte-identical, so the move
leaves no trace. Verify every swap with `diff -q`, never by eyeball.
*(Does NOT fire on PROJECT-MAP-only swaps. Specific to the arch ref.)*

---

## What Chat 19 resolved — for precedent

**Three flagged Phase 3 implementation details on Claim Intake, all closed by
precedent, none escalated to Andre:**

1. **Intake token storage.** The arch ref left "column on the claim row **or** a
   separate `claim_intake_tokens` table" open. Precedent closed it 3-for-3:
   022's `customer_token`, 025's `claimant_token`, 026's `recipient_token` — all
   a column pair on the entity row per "shape to copy, not shared store." Also
   **no UNIQUE**: `invitations.token` (001) is unique because it is a *shared
   store* where the token IS the lookup key — the shape the pattern explicitly
   does not copy.

2. **O&M Provider capture — the trap worth knowing.** The arch ref's
   open-questions block reads like it is announcing an answer: the FK "is the
   architecturally consistent answer: an `om_provider_contact_id` FK to
   contacts." **It is a proposal in an open-questions list, not a lock.** 022's
   committed header states the governing position and names this very section as
   its parallel: *"No O&M provider FK. Direct field capture ... is Decision 11's
   locked schema, paralleling Claim Intake. Any future move to FK + Snapshot
   warrants its own decision."* No such decision exists. **Committed precedent
   beats an unresolved flag.** Built as four text columns mirroring 022.

3. **`supporting_documents`.** The one with no precedent — every other JSONB in
   the repo is rich text, config, or snapshot. Resolved on the **locked
   semantics**: the column stores the *categories* a claimant declares they are
   providing. A checklist, not an attachment store. No file, no URL, no join
   surface. The child-table argument imagines storing documents; the column
   stores declarations. Andre's call, JSONB.

**THE NAMING COLLAPSE — the highest-value catch of the session.** The arch ref's
hard-column sketch lists `priority_emergency boolean NOT NULL DEFAULT false`.
Migration 016 had already built `is_emergency` from Decision 27.5. **Same field,
two names**, written months apart — the Claim Intake section pre-dates Decision
27. Following the arch ref literally would have created two emergency flags that
can disagree. Resolved as Option A (use the built one, add nothing), with a
doc-control note above the frozen sketch (Convention 7) so a future chat reading
the arch ref literally cannot re-add it.

**Two defects Claude caught in its own draft before it reached Andre:**
- Silently relaxed all seven `NOT NULL` columns to nullable to dodge the
  add-column-to-populated-table problem — a silent deviation from the locked
  spec, exactly what #2 forbids. Andre's ruling: follow the spec. Production
  starts empty at onboarding; there is nothing to backfill and no honest default
  for `date_of_defect_incident`. **Do not weaken these later; drop test rows.**
- The `priority_emergency` duplicate, caught on re-read.

---

## Known state notes

- **`clock_events` after 026:** `event_type` has 10 values, `entity_type` has 8.
  Ordinals in the decisions log ("seventh event type", "sixth canonical use") are
  **stale numbering artifacts** — decisions were drafted in different sessions
  and later ones landed first. The *values* are locked; the *counts* were written
  before later decisions existed. **An ordinal collision is not a conflict.**
- **Four parallel `is_default` flags** (022, 023, 025, and 029's
  `om_authorization_templates` when it lands) — all app-layer, all the same
  answer. Do not ask again.
- **`custom_field_values.claim_id` is CASCADE** while every other claim-child FK
  is RESTRICT. That is 017's deliberate choice — values are attributes of the
  claim, not independent records. Not a defect.
- **Six of seven `claim_type_data` shapes are deliberately unsettled** and need
  **no migration** when they land — shape is validated app-layer, same
  convention as `clock_events.payload`. Do not invent them.
- **Filename consistency:** `CLAUDE-rev6.md` and the decisions log still carry
  `-rev6`; `architecture-reference.md` dropped its suffix. Open, non-blocking.

---

## Communication

- Plain language. Dense, high-signal, minimal scaffolding.
- **One command at a time** (#6). Labeled. Wait for output.
- Direct acknowledgment of mistakes over deflection.
- Push back clearly on concerns *before* commit, not after.
- Pre-commit audits before every substantive commit. Non-negotiable.
- **"Fix it now" means proceed** without per-issue confirmation.
- Explicit checkpoint before drafting: ask *"should I draft this now?"*
- Surface `[msg N/M this session]` at the end of every response.
- Memory updates at session close by default.

---

## Build-era principle (still the governing frame)

~95%+ of architectural decisions are made and locked (Decisions 1–28, Phase 0
Items, the architecture reference). **Claude's job is to BUILD ACCORDINGLY, not
re-open design questions.** Before assuming anything is an "open question" or
deferring it as "undesigned," check the decisions log / arch ref — most things
are already specified. Only decide when a genuine conflict surfaces at a specific
point DURING the build: flag it, resolve it minimally, keep building.

**Do not add architecture prose or doc-control churn unless something is
genuinely broken.** That is maintenance, not progress.

**On doc control, from Chat 19's exchange with Andre.** It has near-zero value as
*process* and high value as *memory*. The `priority_emergency` note is the case
for it — not because a convention caught the collision (reading 016's real bytes
did), but because the note is what makes the catch *survive* into a future chat
that will have no idea this conversation happened. The test to apply: **does this
note prevent a future mistake, or does it just make the docs look tidy?** Rev
suffixes and Last-updated lines are the second thing. Today's notes were the
first.

**And the division of labor, stated plainly:** the docs are Claude's to maintain;
the architecture is Andre's. Chat 19 got the build sequence wrong on
FK-resolvability grounds and Andre corrected it from the warranty event chain. He
also settled the NOT NULL question from operational knowledge — production starts
empty — that Claude had no way to derive. When Andre pushes back on a technical
call, he is usually seeing an axis Claude isn't.
