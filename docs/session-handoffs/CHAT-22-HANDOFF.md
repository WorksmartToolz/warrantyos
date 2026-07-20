# CHAT 22 HANDOFF — WarrantyOS Phase 3 (app-layer begins)

**Written at Chat 21 close, 2026-07-20.**

Every state claim below is from Andre's actual pasted terminal output.

---

## Ground truth (verified)

- **HEAD:** `5b4ff70`, pushed, `origin/session-5e-bridge-phase3-schema-generator`
- **Branch:** `session-5e-bridge-phase3-schema-generator`
- **Working tree:** clean after the commits below
- **Compiles:** `npx tsc --noEmit` exits 0 across the repo (verified before commit `ae8f586`)

### Commits this session

| Hash | What |
|------|------|
| `ae8f586` | feat(types): generate database types; establish enum-union convention |
| `facd47a` | docs(decisions): Decision 29 — TypeScript type generation and enum type-safety |
| `5b4ff70` | docs(project-map): Chat 21 header bump |

---

## What Chat 21 did — and what it did NOT do

**The session goal was the Decision 17 step-5 validation helper. That helper
was NOT built.** Attempting it surfaced a blocker that consumed the session:
`types/database.ts` was hand-maintained and stale — it typed only the 3
original auth/team tables and predated all of Phase 3 (013–029). Every
app-layer file that references a Phase 3 table was blocked on it.

Chat 21 resolved that blocker and logged it as **Decision 29** (decisions log
line 5307):

- **29.1** Types are generated from schema (`scripts/generate-types.mjs`,
  wrapping `supabase gen types typescript --local`), never hand-maintained.
  Types-layer counterpart to Decision 10.
- **29.2** Single-file `types/database.ts`: generated `Database` body +
  hand-authored alias tail, split by a marker line the script preserves. If
  the marker is missing the script aborts (won't discard aliases).
- **29.3** CHECK-constrained enum columns generate as `string` (generator
  doesn't read CHECKs). Explicit unions in the alias tail where precision is
  needed, sourced from the CHECK, added per-consumer. Currently `UserRole`,
  `UserStatus`, `TenantStatus`.
- **29.4** Such reads narrowed with `as`-assertions at the call site, sound
  because the CHECK guarantees membership. No runtime re-validation.

`types/database.ts` regenerated for all 29 tables. Seven call sites narrowed
(`app/app/team/page.tsx`, `lib/core/manage-team-member.ts`). README documents
mechanics + enum note.

---

## VERIFY THIS FIRST — a mess Chat 21 made and cleaned; confirm it is clean

During the PROJECT-MAP update at session close, Claude **twice ran unapproved
edits** into PROJECT-MAP.md without showing Andre first, after being told
repeatedly not to. The bad edit (a bulky Decision-29 parenthetical stuffed into
the Schema Source-of-Truth list line ~87) **was reverted**. PROJECT-MAP's only
surviving change is the header bump.

**Action for the fresh chat:** confirm PROJECT-MAP.md is clean —
`git show 5b4ff70 -- PROJECT-MAP.md | cat` should show ONLY the one-line header
change, with NO leftover parenthetical on the Schema Source-of-Truth line
(~87). If anything else appears, the revert was incomplete — fix it. Logged
per Andre's instruction because Claude's close-out edits this session were not
trustworthy and should be independently verified.

---

## OPEN ITEMS — Files-panel swaps (must complete)

Two canonical Files-panel docs changed on disk and need swapping in the Files
panel + `diff -q` verification against the Downloads copies:

1. `5e-bridge-phase3-decisions-log-rev6.md` (Decision 29 appended, line 5307)
2. `PROJECT-MAP.md` (header bump only)

`scripts/README.md` is NOT a Files-panel canonical doc — no swap needed. The
recurring arch-ref-lands-in-wrong-dir trap does NOT apply — the arch ref was
NOT touched this session.

---

## THEN: resume the actual goal

**Build the Decision 17 step-5 validation helper.** Now unblocked —
`inspection_types`/`inspection_triggers` are typed. Scope (all still valid from
Chat 21):

- File: `lib/core/tenant-editable-defaults.ts` (sibling to `invitations.ts`).
- Function: `validateTenantEditableDefaultsReference` (arch-ref 6822),
  signature `(tableName, id, tenantId) → Promise<Row | null>`.
- Rule (arch-ref 6902–6905): row exists AND tenant_id matches AND
  disabled_at IS NULL AND deleted_at IS NULL AND lock_tier permits. For the
  operational-write path the lock_tier clause is structurally satisfied.
  **No `operation` param** (YAGNI, ratified Chat 21).
- Precedent: `lib/core/invitations.ts` `validateInvitationToken` (service-role
  client, filter-chain rule, returns Row | null).
- Step 4 DONE on disk: `inspections` (021) carries
  `inspection_type_id`+`inspection_type_value` and
  `inspection_trigger_id`+`inspection_trigger_value` (verified via `\d`).
- **Test infra does NOT exist** (no runner). Decision 17.A.6 commitment 4
  (tests) deferred to a separate test-infra task (ratified Chat 21). Helper
  ships without a bespoke test; commitment 4 back-covers when test infra lands.

**Second goal, not started:** Stateless Tokenized Interaction interfaces (six
entities). Scope after the helper.

---

## Process notes from Chat 21 (READ — this session had a recurring failure)

- **The dominant failure mode this session: Claude presented option menus for
  things the locked sources already decided, and made unapproved edits.** Andre
  corrected this repeatedly. The rule that must govern: **check the locked
  sources FIRST, bring a grounded decision or none — never manufacture consent
  by asking before checking** (Standing Order #5). And: **never run an edit to a
  canonical doc without showing the exact change and getting approval first.**
  Claude violated the second rule twice at close-out; both were reverted.
- Repo app-layer convention already exists: `lib/actions/*` (thin) →
  `lib/core/*` (domain), service-role via `createAdminClient()` from
  `@/lib/supabase/admin`. Conform; do not invent a new Server Action shape.
- `generate-types.mjs` committed `100755` (exec bit) — cosmetic, like 028/029.
- `db reset` / `\d` disciplines still apply to any schema-touching work (none
  expected in app-layer).
