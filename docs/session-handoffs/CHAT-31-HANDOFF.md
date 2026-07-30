# CHAT 31 HANDOFF — WarrantyOS Phase 3 (C3 core runtime-proven + ID Generation's first implementation built)

**Written at Chat 31 close, 2026-07-29.** (Filename is CHAT-31 because it is FOR
the next chat.) Every state claim traces to Andre's pasted terminal output.

---

## ⚖️ THE DIG LAW — STILL GOVERNS, READ FIRST (dig, dig, dig, dig)

**The only gaps are BUILDING, not DECIDING.** Design is ~95%+ complete
(Decisions 1–35, Phase 0 Items, arch-ref). If a future chat thinks it found a
*design* gap, **DIG — do not ask.** Search order: arch-ref → BOTH decisions logs
→ Phase 0 + Phase 1 audit → built migrations' CHECK constraints + column
comments → repo + git history → the SOPs and workbooks.

**Chat 31 is a THIRD consecutive proof the dig pays off.** Building C3's ID
generation, THREE "open questions" were raised toward Andre and ALL THREE
dissolved against locked sources instead of needing a decision:

- **"Same-transaction vs Server-Action vs Python-format — a three-way
  collision?"** — INVENTED. Dissolved by Decision 27.2 (4848: "the Server Action
  issues warranty_id synchronously in the same transaction") + arch-ref
  1126–1134 (row-level locking is *how* one transaction is achieved). A DB
  function invoked by the action IS "the same transaction"; the action is the
  caller. No collision.
- **"Format-expansion scope — is width locked?"** — YES, and I nearly
  under-built. Decision 2 (Phase 2 log, line 92) locks exactly `{year}` and
  `{seq:NNd}`, width N *part of the placeholder syntax*. My instinct to hardcode
  width-7 would have VIOLATED the lock. The width-reading regex is correct.
- **"Missing-sequence-row behavior — what should the guard do?"** — the
  *invariant* is locked (009 header + arch-ref 1061–1066: row must pre-exist, no
  lazy-create), and the *guard style* follows the locked defense-in-depth
  convention (Phase 2 log line 291). Raising legibly is faithful, not invented.

**Each "I need Andre to decide" was a RED FLAG that the dig wasn't deep enough.**
Same failure mode as Chat 30's two dissolved questions. The correct move every
time was to keep digging until the question dissolved against locked sources.

---

## Ground truth (verified this session via pasted terminal output)

- **HEAD:** `e9b259e`, pushed, `origin` = HEAD.
- **Branch:** `session-5e-bridge-phase3-schema-generator`, working tree clean.
- **Typecheck:** `npx tsc --noEmit` clean on committed state.
- **Migrations:** 32 on disk (031 added this session).

### Session lineage (Chat 30 close → Chat 31 close)

```
b31ddf4  (Chat 30 handoff)
5e2b90e  feat  C3 ID generation — migration 031 + wired core + types + arch-ref Status (Convention 9)
e9b259e  docs  Chat 31 — PROJECT-MAP + ROADMAP (stamp, counts, C3 annotated)
```

Two-commit convention held: code (`5e2b90e`, which INCLUDES the arch-ref Status
note per Convention 9's same-commit-as-migration rule) is separate from the
PROJECT-MAP/ROADMAP doc-control commit (`e9b259e`).

---

## What Chat 31 did

### 1. C3 core smoke test — the pending flag is CLEARED
Chat 30 left C3 core typechecked but NOT runtime-proven, flagging that the
`as never` casts bypass column-name checking. The smoke test found EXACTLY that
class of gap — but not a wrong column name. The gap was structural: **`claims.claim_id`
is NOT NULL with no DB default, and nothing generated it.** The core's comment
claimed "claim_id generated at insert" but no generator existed — because C3 is
the FIRST consumer of the ID Generation system (migration 009 / Decision 2),
which had a table but no code.

### 2. Migration 031 — the ID Generation system's first implementation (`5e2b90e`)
`create_claim_with_generated_id(...)` — a `security definer set search_path = public`
Postgres function (matching the 002/011 hardening precedent) invoked by
`lib/core/claims.ts` via `admin.rpc()`. In ONE transaction it:
1. Locks the `(tenant, 'claim_id')` `tenant_id_sequences` row via the locked
   single-statement UTC year-rollover CASE UPDATE (arch-ref 1146–1154),
   `RETURNING current_value, format_string`.
2. Expands the two locked placeholders `{year}` / `{seq:0Nd}` (width read from
   the tenant's own `format_string` — Decision 2 locks width as part of the
   `{seq:NNd}` syntax).
3. INSERTs the full 27-column claim.
4. Returns `id` + `claim_id`.

A rolled-back insert rolls back the counter → **gap-free** (arch-ref 1126–1128
rejects PG SEQUENCE objects for exactly this reason). This is why it MUST be a
DB function, not two Supabase-JS `.from()` calls: the JS client can't wrap two
round-trips in one transaction.

**Two-layer pattern intact:** `createClaimIntake` keeps ALL business validation
in TS (enums, rich-text caps from `tenants.settings`, conditional couplings,
eligibility, cross-tenant guard, submitter FK). The function is a pure
atomic-WRITE primitive receiving already-validated typed values. DB CHECKs are
the in-transaction backstop.

**Runtime-proven directly against the DB (not just tsc):**
- `CLM-2026-0000001`, `CLM-2026-0000002` — format expansion exact, 7-digit pad.
- Counter monotonic `0 → 1 → 2`, one advance per valid claim.
- A rejected insert (bad enum, bypassing TS to hit the DB CHECK) left the
  counter UNADVANCED at 1 — **gap-free-on-rollback demonstrated.**
- Missing-sequence-row guard raised legibly (caught the scratch-seed fixture
  gap: direct SQL tenant insert bypasses provisioning's sequence seeding).
- `types/database.ts` regenerated (Decision 29) so the RPC is typed.

### 3. Full doc-drift sweep — nothing stale (`5e2b90e` arch-ref + `e9b259e`)
- **arch-ref ID Generation Status (L1037):** Convention-7 supersession note —
  ClaimID logic now built (scope: ClaimID ONLY; WarrantyID still unbuilt, its
  consumer being the `warranty_id_early_issuance` clock event, B-layer). Also
  corrected a clause that was ALREADY stale before this session: the provisioning
  seed described as "not yet built" in fact EXISTS (`provision-tenant.ts:163-164`).
  Line-shift safe: no arch-ref internal citations point below L1043 (verified).
- **PROJECT-MAP:** stamp Chat 30/`24cef98` → Chat 31/`e9b259e`... (NOTE: the
  in-doc stamp reads `5e2b90e`, the code commit, written before the doc commit
  existed — this is the normal one-behind stamp, same pattern as every prior
  handoff); migrations 31→32 (031 enumerated + descriptor); functions 3→4
  (distinguished from the calendar functions); ID-Gen Implemented-note updated.
- **ROADMAP:** C3 annotated CORE built + runtime-proven; **checkbox
  deliberately LEFT OPEN** — the token-authed action is the remaining piece.

---

## ⚠️ NO loose ends created this session

The core's ID-generation gap was created by Chat 30 and CLOSED here (Genuine
loose ends vs interface seams, Chat 27). The `intake_token` seam facing the
unbuilt issuance subsystem is a FINISHED EDGE, not deferred work. Nothing
half-built was left behind.

---

## NEXT UNIT — C3 ACTION (append to EXISTING lib/actions/claims.ts)

**Unchanged from Chat 30's plan** — the core work this session did not alter it.
`lib/actions/claims.ts` ALREADY EXISTS (C10, `85f7f1b`) with `progressClaim`
(account-authed, session client). The C3 create action is a NEW EXPORT APPENDED
— NOT a new file, NOT an overwrite.

Critical divergence: `progressClaim` is ACCOUNT-authed. The C3 create action is
TOKEN-authed (the customer has no account/session) — it must NOT inherit the
session-auth pattern. Shape follows arch-ref gate mechanics 5529:
1. `validateToken('claims', 'intake_token', token)` (admin client, tokens.ts).
2. Gate check (023): does the tenant have a `claim_submission` gate template? If
   so, is an `acknowledgment_gate_records` row recorded?
3. Resolve `tenantId` from the validated registration; call `createClaimIntake`.
4. `revalidatePath` the claim list target.

**THE ONE SEAM TO CONFIRM FIRST (do not assume):** whether the create-entry link
carries the *registration's* token or the *claim's* `intake_token`. The
`intake_token` on the claim row is for the *post-creation* correction loop
(27.6 "Correction Required"); the create-entry token is minted by the ISSUANCE
SUBSYSTEM (unbuilt) against an eligible registration. Precedent (022/025/026:
token on the acted-upon row) + 027's on-row `intake_token` suggests the
correction loop; the create entry is likely gated upstream. **DIG the issuance
flow (C11-era) before wiring create-consume.** If it does not resolve cleanly
against locked sources, STOP and flag — do not invent the issuance contract.

Because create-entry issuance is unbuilt, the honest v1 action may be testable
only with a manually-seeded token. That is a testing seam, not a design gap.
Pairs with **E1c** (Resend tokenized-link dispatch) — still not started.

### Smoke-test fixture recipe (reuse for the action)
The action needs the same seeded eligible registration the core test used. From
a fresh `supabase db reset` (zero tenants):
1. Insert tenant (name, slug) → project (tenant_id, name,
   `trigger_source='contractual_date_manual'`) → warranty_registration
   (tenant_id, project_id, `status='pre_activation'`, `warranty_id='...'`
   NON-NULL for eligibility 27.4). **`pre_activation` is the minimal eligible
   status** — the `assignee_check` CHECK requires an assignee XOR for
   assigned/active/rejected, but permits null assignees on pre_activation, and
   nothing couples `warranty_id` to status.
2. **CRITICAL:** also insert the `tenant_id_sequences` `claim_id` row
   (`format_string='CLM-{year}-{seq:07d}'`, `current_value=0`) — a direct-SQL
   tenant bypasses provisioning's seeding, and the generator's missing-row guard
   will (correctly) refuse without it.
3. Run via env-override: `NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321
   SUPABASE_SERVICE_ROLE_KEY=$SVC npx tsx /tmp/<script>.ts` (capture $SVC once
   with `export SVC=$(supabase status -o env | grep SERVICE_ROLE_KEY | cut -d= -f2 | tr -d '"')`
   — never paste the key inline).

---

## Buildable-now map (unchanged except C3 core)

- **C3 core** — ✅ BUILT + runtime-proven this session. Action is next.
- **C3 action** — buildable as an append; confirm the create-token seam first.
- **C4-create** — buildable, independent, no token coupling (mirrors C0, two
  conditional-CHECK wrinkles on `execution_path`). C4-status/edit BLOCKED (C5/C8).
- **B-layer** — its own full-session arc (clock/cron; owns C10's two system
  transitions + all `clock_events` firing, AND WarrantyID generation's first
  consumer `warranty_id_early_issuance`). Do NOT start as a back-half item.
- **C5 (work auth)** — token layer ready; carries C12 (Ack Gate) + email.
- **C8 (service report)** — token layer ready; TWO tokens, each its own consume.

---

## RECOMMENDED NEXT (Andre decides; sequencing is his)

1. **C3 action** — finish the intake surface end to end. Confirm the create-token
   seam against the issuance flow FIRST.
2. **C4-create** — independent, finishable, no token coupling.
3. **B-layer** — dedicated full session (also builds WarrantyID generation, the
   ID Generation system's *second* consumer — mirror 031's shape).

---

## Canonical docs (read PROJECT-MAP.md FIRST, then ROADMAP)

- `PROJECT-MAP.md` — stamp era Chat 31; 35 decisions, **32 migrations**, 29
  tables, **4 functions**. 031 enumerated.
- `docs/ROADMAP-TO-TESTABLE.md` — C3 annotated (core proven, checkbox open).
- `docs/architecture-reference.md` — 7346 lines (one paragraph added at ID
  Generation). ID Generation Status now carries the Chat-31 supersession note.
  Claim intake data model 3475+; gate mechanics (token validation first) 5529;
  eligibility 27.4; ID Generation section 1035.
- `docs/session-handoffs/5e-bridge-phase3-decisions-log-rev6.md` — Decisions
  11–35. Decision 2 is in the **Phase 2** log (line 54+), NOT this one.
- `docs/session-handoffs/5e-bridge-phase2-decisions-log.md` — Phase 2, incl.
  Decision 2 (ID generation; line 92 locks the `{year}`/`{seq:NNd}` placeholders).
  BOTH logs live.
- `CLAUDE-rev6.md` — Conventions 7/7a/8/9, Rule 10, execution discipline (ONE
  command per turn, NO `;`/`&&` chaining without explicit permission).

---

## Standing disciplines still in force

- **THE DIG LAW governs.** A half-dug question handed up as a decision is THE
  failure mode. Chat 31 raised three; all three dissolved on digging.
- **Standing Order #4 applies even to COSMETICS.** This session I flagged 031's
  `100755` exec bit as "stray drift" from memory — then checked the siblings
  (`git ls-files -s`): 029/030 are BOTH `100755`. Every migration is committed
  executable. The 755 was CONVENTION, not drift; "fixing" it to 644 would have
  made 031 the odd one out. Reverted via `git checkout`. **Don't flag cosmetic
  drift against a remembered ideal — check the neighbors first.**
- Andre is dyslexic. **ONE command per WSL message**; `▶ RUN IN WSL` labels; only
  the command in the code block. **NO `;`/`&&` chaining** without explicit
  permission (CLAUDE-rev6 execution discipline — violated once this session with
  a chained psql DO-block; acknowledged, corrected).
- **Anchored doc edits:** verify ALL anchors (`.count()==1`) across ALL files
  BEFORE writing ANY (an abort is the system working — it fired usefully this
  session on a phantom blank-line "fix" that didn't exist). Use `cat -A` only to
  CHECK bytes, never as an anchor source (it escapes em-dashes to `M-bM-^@M-^T`).
- **Canonical docs:** download-from-chat + `cp`, OR anchored Python scripts run
  in WSL (never Claude's sandbox — it can't reach the repo). Typechecked TS:
  download + `cp` OR a surgical anchored script (this session's `claims.ts` RPC
  wire was an anchored script).
- Two-commit convention: code separate from doc-control. Convention 9: arch-ref
  Status edit rides in the migration's commit (done — arch-ref note is in `5e2b90e`).
- `tsc --noEmit`, never `next build` with the dev server up.
- Verify pushes (`git log` shows origin = HEAD). Fix doc drift the session you
  find it (Standing Order #1). Handoffs built on VERIFIED disk state (Rule 10).
- **`db reset applied clean` proves execution, not correctness.** For computed
  output, query the DB via `docker exec supabase_db_warrantyos psql -U postgres
  -d postgres -c "..."`. This session that discipline caught the whole
  ID-generation gap that tsc missed.

---

## Document-control state at Chat 31 close

Committed + pushed:
- `5e2b90e` — migration 031, wired `lib/core/claims.ts`, `types/database.ts`,
  arch-ref ID Generation Status note (Convention 9).
- `e9b259e` — PROJECT-MAP (counts/stamp/031), ROADMAP (C3 annotated).

**Files-panel swap at Chat 31 close (Standing Order #3):** the panel copies of
`PROJECT-MAP`, `ROADMAP-TO-TESTABLE`, `architecture-reference`, the rev6
decisions log, AND this new `CHAT-31-HANDOFF` must be replaced with the Chat-31
disk versions. Verify each with `diff -q` against the Downloads copy. If a future
chat finds the panel behind disk, re-swap and verify.

**Carried cosmetic drift (from Chat 29, STILL open — Standing Order #1, low
value):** panel entries carry `-v2` suffixes while repo files are canonical-named;
the panel `.txt` arch-ref and `.docx` SOP copies are TRUNCATED FRAGMENTS (the
`.txt` arch-ref is 248 lines vs disk's 7346; the `.docx` files are not valid zip
archives). A reader trusting the panel `.txt`/`.docx` gets a fraction of the real
content. A deliberate panel-reorganization task, better done intentionally than
rushed at a session close. Flagged here so it is not lost. (The 031 exec-bit
item that appeared on Chat 31's working list is NOT carried — it was a false
flag, resolved: 755 is convention.)

**This handoff (CHAT-31-HANDOFF.md)** is produced as a chat download and `cp`-ed
into `docs/session-handoffs/`, then committed. Verify via `git log`.
