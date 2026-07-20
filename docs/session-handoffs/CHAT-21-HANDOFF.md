# CHAT 21 HANDOFF — WarrantyOS Phase 3 Build

**Written at Chat 20 close, 2026-07-20.**

Every state claim below was copied from Andre's actual pasted terminal output.
Nothing here is narrated, predicted, or reconstructed. If you did not see
Andre's output, you do not know what happened — that rule held all of Chat 20
and it is why this document is trustworthy.

---

## Ground truth (verified from Andre's terminal)

- **HEAD:** `d31be56`, pushed, `origin/session-5e-bridge-phase3-schema-generator`
- **Branch:** `session-5e-bridge-phase3-schema-generator`
- **Working tree:** clean (`git status --short` empty)
- **Migrations on disk:** 30 (`ls supabase/migrations/*.sql | wc -l` = 30)
- **Built:** 29 tables + 1 view + 3 functions
- **Files panel:** matches disk for `architecture-reference.md` and
  `PROJECT-MAP.md` — both verified `diff -q` against the Downloads copies,
  `BOTH IDENTICAL`
- **Pending doc-control:** none
- **Open items:** none

### Commit chain this session

| Hash | What |
|------|------|
| `ec76b32` | feat(schema): Service Report Submission — service_reports (028) + Convention 9 arch-ref Status edit, same commit |
| `ca3485c` | feat(schema): Customer-O&M Authorization — om_authorization_documents + om_authorization_templates (029) |
| `d31be56` | docs(project-map): 028 + 029 built — Chat 20 close |

Three new tables this session: 028 added `service_reports` (1); 029 added
`om_authorization_documents` + `om_authorization_templates` (2). Table count
moved 26 → 29. Migration count moved 28 → 30.

---

## THE MILESTONE — read this before planning any build work

**029 was the last section with tables. Phase 3 table construction is COMPLETE.**

The Chat 20 handoff named exactly two remaining table-bearing sections — 028 and
029 — and both are now built and verified in the DB. There are no more table
migrations left in the locked design. What remains for Phase 3 is **app-layer**,
not schema:

- **Tenant-Editable Defaults Pattern (Decision 17) — step 5**, the canonical
  validation helper. Application-layer; does not yet exist. The pattern's Status
  moves to `Implemented (schema)` only when this lands. This is the one genuinely
  unbuilt item still on the DESIGNED-NOT-BUILT list that is *close* to the schema
  layer.
- **Stateless Tokenized Interaction Pattern** — applied in schema across six
  entities (every `*_token` column pair) but not yet coded as interfaces.
- **Server Actions** — none exist yet for any workflow (confirmed by Decision
  28's Session F Claude Code audit: no code for the ALA / Work Authorization /
  Service Report actions). The 28.7 permission-check swaps, the 21.5 feature-flag
  gating, the clock-event insertions, and every trigger condition are all still
  app-layer prose awaiting implementation.
- **FK + Snapshot Pattern, Feature Flag System, Database Migration Tooling** —
  listed as designed patterns, not yet coded.

**Do not go looking for another table to build. There isn't one.** If a future
chat believes it has found an unbuilt table-bearing section, that belief is
almost certainly a stale doc-list entry (see the Claim Intake drift Chat 20
fixed) — verify against the built-tables section of PROJECT-MAP and the git log
before drafting anything.

---

## READ THIS FIRST, IN THIS ORDER

1. **`PROJECT-MAP.md`** (repo root) — the durable orientation doc, current as of
   `d31be56`. It now carries full per-table rationale for all 29 tables including
   028 and 029, and its DESIGNED-NOT-BUILT list is trimmed to only genuinely
   unbuilt (app-layer) items. **This handoff deliberately does not restate the
   per-table rationale.** Read the map.
2. **`git log --oneline -10`** — clean and accurate.
3. **`CLAUDE-rev6.md`** — doc-control conventions 7/7a/8/9 are committed law.

Ground truth is the git repo and direct disk reads. Not the Files panel, not any
handoff summary, not this document.

---

## STANDING ORDERS (law, in force)

**#1 — Never hand off unfinished work.** The 85-message ceiling is advisory.
Corollary: don't START work that can't finish. *(Chat 20 note: Andre explicitly
waived the ceiling to finish 029 and its full doc-control in one session. The
waiver was about not stopping short, NOT about skipping verification — every
step was still DB-verified and diff-checked. "Ignore the ceiling" means finish
clean, not cut corners.)*

**#2 — Never take the simplest route because it's easy.** Take the option that
best supports the locked decision without altering it.

**#3 — Files-panel swap is the DEFAULT ACTION at every doc-control close.**
Never ask, do it, then verify with `diff -q`. *(Fired correctly at Chat 20
close: both arch-ref and PROJECT-MAP swapped and verified BOTH IDENTICAL.)*

**#4 — Never assume, always verify.** Before drafting any migration, read the
most recent comparable one's real bytes from disk. Pattern-memory is unreliable.
*(Chat 20 read 026's full bytes before 028, and 022's full bytes before 029.
Both reads paid off — see below.)*

**#5 — CHECK THE LOCKED SOURCES BEFORE ASKING ANDRE TO DECIDE ANYTHING.**
> **THE NAMED FAILURE MODE:** reading the architecture-reference and stopping,
> when the **DECISIONS LOG** carries the resolution. Its *"Decision implications
> for already-committed sections"* blocks are **BINDING INSTRUCTIONS**.

**#6 — ONE COMMAND AT A TIME. NO EXCEPTIONS.** Andre is dyslexic. Every command
gets its own message, labeled **▶ RUN IN WSL** or **▶ RUN IN CLAUDE CODE**. Wait
for the output. Read it. Confirm it. Then the next one. Never two code blocks.
*(Held all of Chat 20, ~50 commands, zero violations.)*

**#7 — THE OUTPUT IS THE ONLY TRUTH.** Do not author it, predict it, or treat an
empty paste as success. **"done" from Andre is NOT verification** — ask for the
bytes. *(Chat 20: the handoff predicted HEAD `f5ddc9c`; the real tip was
`1adf70a` — a handoff-commit Chat 19 landed on top. The prediction was wrong and
the terminal was right, exactly as #7 anticipates.)*

---

## WHAT CHAT 20 BUILT — for precedent, not to re-derive

### 028 = service_reports (commit `ec76b32`)

Built verbatim to the arch-ref "Service Report Submission" section + Decision 21.
DB-verified via `\d public.service_reports`: 30 columns, 9 NOT NULL, `claim_id`
UNIQUE, 4 CHECKs, 4 RESTRICT FKs, 5 indexes, RLS policy. Key locked calls:

- **Conditional submitter XOR gated on `submitted_at`.** Both null in
  pre-submission draft; exactly one non-null when submitted. This is 010's
  conditional shape, **NOT 026's unconditional one**. 026's header says DO NOT
  HARMONIZE about exactly this contrast and it cuts both ways — a service report
  has a draft state, a Notice of Defect does not. The DB confirmed the CHECK
  landed as `(submitted_at IS NULL AND both null) OR (submitted_at IS NOT NULL
  AND (contact) <> (user))`.
- **`submission_token` pair — the one non-trivial judgment of the section.** The
  arch-ref schema block lists ONLY `customer_review_token`; the *submitter's*
  link was prose-flagged (line ~4901) as "a column or columns on this table,
  parallel to customer_review_token ... Phase 3 implementation detail." Resolved
  NOT by a new decision but by **Tier 1 pattern law**: the Stateless Tokenized
  Interaction Pattern (arch-ref §228, locked by Decision 1 + Item 17) states the
  token lives on the entity's own row per "shape to copy, not shared store."
  Built as a nullable column pair, no UNIQUE, mirroring 026's `recipient_token` /
  025's `claimant_token` / 022's `customer_token`. Andre chose the name
  `submission_token` (over `submitter_token`/`sr_submission_token`) after
  confirming it collides with nothing — token names are per-table, and this
  table's two tokens (`submission_token`, `customer_review_token`) are distinct.
- **Decision 21 adds ZERO columns** to this table. Its two additions are
  provisioning-layer (`tenants.settings.service_report_response_days` + the
  `service_report_acquiesce_window` feature flag). **No window snapshot column**
  (21.7: derivable from `fires_at` minus `issued_at`). **No `clock_events`
  alter** — 026 already landed `service_report_response_due` + `service_report`.
- Convention 9 honored: the arch-ref Status line ("Designed at the architectural
  level" → "Implemented (schema). Built by migration 028...") landed in the SAME
  commit as the migration (`ec76b32`).

### 029 = om_authorization_documents + om_authorization_templates (commit `ca3485c`)

Built verbatim to Decision 28's two schema sketches. **No arch-ref section**
(Chat 18's Notice-of-Defect precedent: the decisions log holds the spec, the
migration header the rationale, PROJECT-MAP the gap record). DB-verified via `\d`
on both tables. Key locked calls:

- **Polymorphic `event_type` + `event_reference_id`, NO database FK on
  `event_reference_id`.** 022's exact app-layer shape (precedent
  `clock_events.entity_id`, 013). The `\d` output confirmed NO foreign-key
  constraint on `event_reference_id` — this is deliberate. **The
  executes-clean-≠-correct property, stated plainly for the next chat:** this
  migration applied cleanly even though `event_reference_id` can point at a
  `service_reports` row, with zero DB enforcement of that reference. Integrity is
  a Server-Action concern. "Applied clean" proved execution, not correctness —
  the `\d` verification is what proved correctness.
- **Four-value status: unsigned | signed | closed | stale.** NO `voided`, NO
  `superseded` (28.5 eliminates both). This is a DIFFERENT four-value set from
  Decision 20.8's superseded unsigned/signed/voided/superseded model. Decision 28
  is a substantive scope DEPARTURE from 20.8 (per-event, not standing), not a
  refinement — do not reintroduce voided/superseded or a standing-document shape
  by analogy to 20.8.
- **One-to-many with claims, no UNIQUE — and no UNIQUE on `(event_type,
  event_reference_id)` either.** 28.3 requires a reopened event to create a
  brand-new row for the same reference, which a DB UNIQUE would forbid. "One per
  event" is an app-layer invariant (one non-terminal row), not a DB constraint.
- **Template carries `created_at` only, no `updated_at`.** The locked sketch's
  column set, built verbatim (an applying table does not vary the locked column
  set — 022's rule). Note this CONTRASTS `om_authorization_documents`, which does
  carry `updated_at` because its sketch lists it. The `\d` confirmed the template
  has exactly 6 columns, no `updated_at`.
- **Templates created first** in the migration file, because
  `om_authorization_documents.template_id` is a real FK to it (RESTRICT). The
  `\d` "Referenced by" line confirmed the wiring.
- **Seventh canonical token use** (`customer_token` pair). The "seventh" ordinal
  collides with 026's "sixth" and others — a numbering artifact from decisions
  drafted in different sessions, not a conflict.

### The one defect Chat 20 caught — and how

While fixing a stray Unicode character (an Arabic shadda `U+0651` that had slipped
into a comment), Claude replaced it with a plain apostrophe `'` **inside a
single-quoted SQL string literal**. That apostrophe closed the string early. The
first `supabase db reset` caught it: `ERROR: syntax error at or near "counts"`.
Fix: double the apostrophe (`''`) per SQL escaping, then a programmatic sweep
confirmed no other unescaped apostrophe lived inside any comment string. **Lesson
for the next chat: when editing SQL comment bodies, every apostrophe inside a
`'...'` literal must be doubled. The reset is what catches this; "it looks fine"
does not.**

---

## PROJECT-MAP alignment (commit `d31be56`) — including a drift fix

Six edits, applied via a Python script with abort-first anchor verification (one
anchor, 5a, failed on the first run because the real file had a blank line before
a bullet list that the chat-paste had collapsed — the abort worked, the anchor
was rebuilt from the true bytes via `sed > /tmp/f.txt` + `code`, and the re-run
applied all six). The edits: header metadata (HEAD `d31be56`, 29 tables),
migration inventory (+028, +029), Phase 3 status line, two new built-table
entries, the DESIGNED-NOT-BUILT list trim, and the narrative table count.

**The drift fix worth internalizing:** the DESIGNED-NOT-BUILT list still carried
`Claim Intake Data Model` even though 027 built it in Chat 19. Chat 19 added 027
to the built section but never removed it from the not-built list. Chat 20 caught
and fixed this rather than kicking it forward — Andre's instruction: *"fix the
stale Claim Intake entry now rather than kick it to the next chat so when we close
this session all things are aligned, nothing left open."* This is Standing Order
#1 applied to doc drift, not just to build work. **A doc-list entry surviving past
the thing it describes being built is exactly the kind of stale state that
misleads a future chat into hunting for a table that already exists.**

---

## Established workflow (unchanged, works)

1. Read locked sources — **decisions log first** (#5), then arch ref.
2. Read the most recent comparable migration's real bytes (#4). Terminal paste
   garbles long files — `cp` to `/tmp` and `code /tmp/file`, copy from VS Code.
3. Draft; **re-read your own draft** (caught the apostrophe class of defect, and
   the NOT NULL / naming-collapse defects in prior chats).
4. Present file → Andre downloads → `cp` into `supabase/migrations/`.
5. `supabase db reset` → verify it applied.
6. Verify structure **in the DB** with `docker exec supabase_db_warrantyos psql
   -U postgres -d postgres -c "\d public.TABLE"` — NOT the reset log. This is
   what proves correctness, especially for app-layer/polymorphic FKs where the
   migration executing tells you nothing about whether the shape is right.
7. `node scripts/generate-schema-sql.mjs`.
8. Pre-commit audit: `git status --short` + `git diff --stat` (additive?), then
   grep the schema diff for stray objects touching other tables.
9. **Convention 9: if the section has an arch-ref Status line, draft the
   doc-control BEFORE committing** — the Status edit lands in the SAME COMMIT as
   its migration. (029 had NO arch-ref section, so no Convention 9 edit — the
   migration committed alone.)
10. Commit → push → verify the ref line (`git push` output shows `old..new`).
11. PROJECT-MAP update → its own commit → push (two-commit convention: code and
    doc-control stamps are separate commits).
12. Files-panel swap (#3) → verify with `diff -q`.

**File writes:** download-from-chat plus `cp`. Not Claude Code, not heredoc.
**Doc-control edits:** Python script with pre-verified anchors, run via `/tmp`.
**Downloads path — use the explicit one:** `/mnt/c/Users/andre/Downloads/`. The
wildcard `/mnt/c/Users/*/Downloads/` fails (matches postgres/Default/Public).

---

## RECURRING TRAP — still fires on every arch-ref panel swap

The uploaded `architecture-reference.md` lands in `docs/session-handoffs/`
instead of `docs/`. **Fired again at Chat 20 close (7th time, Chats 16–20).**
After the swap, `git status --short` showed:

```
 D docs/architecture-reference.md
?? docs/session-handoffs/architecture-reference.md
```

Fix:

```
mv docs/session-handoffs/architecture-reference.md docs/architecture-reference.md
```

Then `git status --short` must be empty — the file is byte-identical, so the
move leaves no trace. Verify every swap with `diff -q`, never by eyeball.
*(Does NOT fire on PROJECT-MAP-only swaps. Specific to the arch ref.)*

---

## Known state notes (carried forward + new)

- **`clock_events` after 026 (unchanged by 028/029):** `event_type` has 10
  values, `entity_type` has 8. 028 needed no alter (026 pre-landed its values);
  029 schedules no clock event of its own. Ordinals in the decisions log are
  stale numbering artifacts — the *values* are locked, the *counts* were written
  before later decisions. An ordinal collision is not a conflict.
- **Token columns now span six entities:** `work_authorization_documents`
  .customer_token (022), `ala_documents`.claimant_token (025),
  `notices_of_defect`.recipient_token (026), `claims`.intake_token (027),
  `service_reports`.submission_token + customer_review_token (028),
  `om_authorization_documents`.customer_token (029). All column-pairs on their own
  row, no UNIQUE, per "shape to copy, not shared store." The `service_reports`
  case is the only entity with TWO distinct tokens.
- **`is_default` flags now on four+ template tables** (022, 023, 025, and 029's
  `om_authorization_templates`) — all app-layer, no partial-UNIQUE index, per
  17.A.6. Same answer every time; do not re-ask.
- **`custom_field_values.claim_id` is CASCADE** while every other claim-child FK
  is RESTRICT — 017's deliberate choice (values are attributes, not records).
  Confirmed again as the lone exception when 028/029 both used RESTRICT.
- **Six of seven `claim_type_data` shapes remain deliberately unsettled** and
  need no migration when they land — validated app-layer, same as
  `clock_events.payload`. Do not invent them.
- **Cosmetic, non-blocking:** migration files 028 and 029 committed with mode
  `100755` (executable bit) rather than `100644`. Harmless for `.sql`; a future
  chat may `chmod 644` them in a housekeeping commit if desired, not worth a
  dedicated one.
- **Filename-suffix inconsistency (still open, still non-blocking):**
  `CLAUDE-rev6.md` and `5e-bridge-phase3-decisions-log-rev6.md` carry `-rev6`;
  `architecture-reference.md` dropped its suffix. Cosmetic.

---

## Communication

- Plain language. Dense, high-signal, minimal scaffolding.
- **One command at a time** (#6). Labeled **▶ RUN IN WSL**. Wait for output.
- Direct acknowledgment of mistakes over deflection. *(Chat 20: Claude owned the
  apostrophe defect plainly — "it's my fault" — and the reset-caught-it framing
  was honest, not spun.)*
- Push back clearly on concerns *before* commit, not after.
- Pre-commit audits before every substantive commit. Non-negotiable.
- Explicit checkpoint before drafting: ask *"should I draft this now?"*
- Surface `[msg N/M this session]` at the end of every response.
- Memory updates at session close by default.

---

## Build-era principle (still the governing frame)

~95%+ of architectural decisions are locked (Decisions 1–28, Phase 0 Items, the
architecture reference). **Claude's job is to BUILD ACCORDINGLY, not re-open
design questions.** With table construction now COMPLETE, the frame shifts: the
next phase of work is app-layer (Server Actions, the tokenized interfaces, the
Tenant-Editable Defaults validation helper), which will involve genuinely new
implementation questions the schema phase did not. Those are still governed by
the locked decisions — check the decisions log / arch ref before treating
anything as open — but the next chat should expect to be writing *code against
the schema*, not more schema.

**On doc control (Andre, carried from Chat 19, reaffirmed in Chat 20):** near-zero
value as *process*, high value as *memory*. The test: **does this note prevent a
future mistake, or does it just make the docs look tidy?** The stale-Claim-Intake
fix and the apostrophe-escaping lesson are the first kind. Rev suffixes and
exec-bit cleanup are the second.

**Division of labor, stated plainly:** the docs are Claude's to maintain; the
architecture is Andre's. Chat 20 ran clean on Claude's side (build, verify,
doc-control), and Andre's calls — the `submission_token` naming, the waive-the-
ceiling-to-finish-clean instruction, the fix-the-drift-now instruction — were the
judgment layer. When Andre pushes, he is usually seeing an axis Claude isn't.
