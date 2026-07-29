# CHAT 28 HANDOFF — WarrantyOS Phase 3 (app-layer build; C2 + D2 + E1-primitives BUILT)

**Written at Chat 28 close, 2026-07-29.** (Filename is CHAT-28 because it is FOR the next chat.)

Every state claim below traces to Andre's actual pasted terminal output this session.

---

## ⚖️ THE DIG LAW — STILL GOVERNS, READ THIS FIRST (dig, dig, dig, dig)

**The only gaps now are BUILDING, not DECIDING.** The design phase is ~95%+
complete (Decisions 1–34, Phase 0 Items, arch-ref). If a future chat thinks it
has found a *design* gap, **DIG — do not ask.** The answer is almost always
already locked under a name or in a section not yet checked. Dig across ALL tiers
before bringing ANY question to Andre:

1. the architecture-reference,
2. BOTH decisions logs (Phase 2 `.md` AND Phase 3 rev6),
3. the Phase 0 update doc AND the Phase 1 audit,
4. the built migrations' CHECK constraints + column comments (the headers are
   binding, not commentary),
5. the repo + git history,
6. the SOPs (`.docx` = PLAIN TEXT, read with `cat`/`view`) and the workbooks
   (real `.xlsx`, read with `python3 openpyxl`).

**"I need Andre to decide" is a RED FLAG meaning the dig was not deep enough.**
A wrongly-assumed "open question" is how locked architecture gets silently
overruled on Andre's authority — the named failure mode. Only after a genuine
exhaustive dig turns up nothing may a question go to Andre, and then as a
grounded minimal question WITH THE DIG SHOWN ("I checked X, Y, Z; here is the
gap"), never as a menu of options.

**Chat 28 is three fresh proofs the dig pays off.** C2, D2, and E1's primitives
each *looked* like they might need an Andre decision; the dig resolved all three
against already-locked sources and committed precedent. Only ONE genuinely-open
fork surfaced in the whole session (E1's validate/consume factoring, 34.3), and
it was brought correctly — after an exhaustive dig, as a pinned deferral with a
trigger condition, NOT resolved by improvisation.

---

## Ground truth (verified this session via pasted terminal output)

- **HEAD:** `f523cf0`, pushed, `origin` = HEAD (confirmed via `git push`)
- **Branch:** `session-5e-bridge-phase3-schema-generator`
- **Working tree:** clean (all code + docs committed and pushed)
- **Typecheck:** `npx tsc --noEmit` clean after every code change this session
- **Migrations:** 31 on disk (UNCHANGED this session — all work was app-layer)

### Session lineage (Chat 27 close → Chat 28 close)

```
7444bac  (Chat 27 close)
0f7bfa9  feat  C2 inspection status machine
2cfcfb0  docs  Decision 32 + PROJECT-MAP (C2)
0bf3713  feat  D2 is-feature-enabled reader + provisioning seed
2b762a5  docs  Decision 33 + PROJECT-MAP (D2)
2fd67f9  feat  E1 token primitives
f523cf0  docs  Decision 34 + roadmap E1/E1b/E1c + strike C2/D2 + A5 + PROJECT-MAP
```

Two-commit convention held throughout: every code commit has a separate
doc-control commit.

---

## What Chat 28 built (three app-layer items)

### C2 — Inspection status machine (Decision 32)
- `lib/core/inspection-progression.ts` (new) + extended `lib/actions/inspections.ts`
  (added `progressInspection`).
- Forward-only linear chain `open → in_progress → under_review → issued`,
  `issued` terminal. Recovered from migration 021's `status` column comment
  ("Backward transitions are not part of the architectural commitment").
- ONE authz class: `operational` (reviewer OR team_admin), identical to the
  inspection write-path. NO escalation-verdict class, NO system path (021 flags
  inspection clock_events as OPEN — so no clock-driven transition to fire;
  `transitionInspectionStatusAsSystem` deliberately NOT written).
- Optimistic concurrency guard (`WHERE id = ? AND status = from`). Core returns
  `claimId` so the wrapper revalidates the parent claim page.

### D2 — Feature-flag reader + provisioning seeding (Decision 33)
- `lib/core/features/is-feature-enabled.ts` (new) + seeding added to
  `lib/core/provision-tenant.ts` (prior "NOT seeded here" deferral replaced).
- `isFeatureEnabled(tenantId, feature) → boolean`, single source of truth, all
  callers route through it. `feature` typed to the locked Phase-1 union so an
  unknown flag is a compile error.
- **Storage = JSONB `tenants.settings.enabled_features`** — the arch-ref part-1
  open fork EXERCISED as the named "lighter starting point," NOT foreclosed: the
  `tenant_features` table upgrade stays available behind the reader (changes only
  its internals), trigger condition (independent per-toggle audit trail) recorded
  in Decision 33.2.
- Three flags (`epc_workflow`, `supply_only_workflow`,
  `service_report_acquiesce_window`) seeded ENABLED at provisioning (opt-out
  model). Fails closed (absent/malformed → false).

### E1 — Stateless-tokenized shared primitives (Decision 34)
- `lib/core/tokens.ts` (new). `generateToken()` (64-char hex / 32 bytes) +
  `tokenExpiresAt(ttlDays)` (TTL parameterized, not the invitation flow's
  hardcoded 7). Table-agnostic, no DB.
- `invitations.ts` deliberately NOT rewired (shared shape, not shared
  implementation — arch-ref "shape to copy, not a shared store").
- **34.3 OPEN — pinned deferral:** the validate + consume factoring is NOT built
  and NOT locked (dig recorded in Decision 34 across all tiers). Must be
  parameterized per surface's token COLUMN names (`claimant_token` /
  `customer_token` / `customer_review_token`). **TRIGGER: resolve against the
  FIRST tokenized consumer built (C3/C5/C8), NOT in the abstract.** Pinned in
  THREE places: Decision 34.3, roadmap sub-task E1b, PROJECT-MAP Stateless
  Tokenized entry.

---

## OPEN ITEMS — one pinned deferral, nothing blocking

- **E1b (validate/consume token factoring)** — the single genuinely-open fork.
  NOT blocking any current work; it blocks nothing until the first tokenized
  consumer is built, at which point it MUST be resolved (against that surface's
  real columns). Pinned in three places. This is a finished edge with a trigger,
  not unfinished session work.
- Everything else built this session is complete: working tree clean, all seven
  commits pushed, HEAD = origin, typecheck clean, docs in sync on disk.

---

## Blocked-vs-buildable map (dug this session — saves the next chat the dig)

- **C2, D2, E1-primitives** — ✅ built this session.
- **C4-create** — BUILDABLE now (independent; mirrors C0 with two conditional-CHECK
  wrinkles on `execution_path`). C4-status/edit BLOCKED (its transitions gate on
  C5 and C8 which don't exist). If picking C4, build create ONLY; defer status/edit.
- **C3 (claim intake)** — BLOCKED on E1b + email dispatch (tokenized; roadmap line
  itself says "Depends on E1").
- **C5 (work authorization)** — BLOCKED: token-coupled (`customer_token` on 022),
  Acknowledgment Gate mechanics (C12) unbuilt, per-transition authority "deferred"
  per 022's own status comment.
- **C8 (service report)** — tokenized submission; near-certainly the same E1b block
  (not exhaustively dug — confirm if chosen).
- **E1b** — the actual unlock under C3/C5/C8; resolve at first consumer.
- **B-layer** — its own full-session arc; do NOT start as a back-half item.

---

## RECOMMENDED NEXT (Andre decides; sequencing is his)

1. **C4-create** — the one confirmed-independent, confirmed-finishable build.
2. **B-layer** — needs a dedicated full session (clock/cron; owns C10's two
   system transitions + all `clock_events` firing).
3. **A tokenized consumer (C3 or C5)** — higher-value but each carries E1b (and
   C5 also C12 + email dispatch). Whichever is built first RESOLVES E1b.

---

## Canonical docs (read PROJECT-MAP.md at repo root FIRST, then the ROADMAP)

- `PROJECT-MAP.md` — durable orientation, stamped current as of `f523cf0`.
- `docs/ROADMAP-TO-TESTABLE.md` — build order + the Locked Decision Rule; C2/D2
  struck, E1 partial with E1b/E1c sub-tasks.
- `docs/architecture-reference.md` — Stateless Tokenized 232-330; feature flags
  393-455; inspections/021; work_plans/020; work auth/022.
- `docs/session-handoffs/5e-bridge-phase3-decisions-log-rev6.md` — Decisions 11-34
  (32=C2, 33=D2, 34=E1).
- `docs/session-handoffs/5e-bridge-phase2-decisions-log.md` — Phase 2 (Decision 3
  here); BOTH logs live. **NOTE the filename is `.md`, not `.txt`.**
- `CLAUDE-rev6.md` — Conventions 7/7a/8/9, Rule 10.

---

## Standing disciplines still in force

- **THE DIG LAW governs (see top). Dig, dig, dig, dig — until exhausted.**
- Andre is dyslexic. **ONE command per WSL message**; `▶ RUN IN WSL` labels; only
  the command in the code block. Never mix prose and runnable commands.
- **NEW GOTCHA (cost a fix this session): an append/replace anchor that ALSO
  appears inside its own replacement text is unsafe to re-run** — it re-creates
  the anchor, so a second (accidental) run does NOT abort and silently
  duplicates the block. Decision 34 got appended twice this way (the heredoc's
  trailing call + a manual re-run) and had to be de-duplicated with `sed`. Cure:
  use an anchor that will NOT reappear in the new text, and don't leave a script
  invocation on the last heredoc line if you might also run it manually.
- **NEW GOTCHA (cost a rewrite this session): a verification command pasted while
  a heredoc is still open becomes FILE CONTENT.** The first CHAT-28 handoff
  heredoc was written, then a `cat | head` check pasted into a still-open second
  heredoc, corrupting the file (truncated at 51 lines, the check line embedded).
  Cure for CANONICAL DOCS: use download-from-chat + `cp`, NOT terminal heredoc.
- **Download-collision gotcha:** re-downloading a same-named script can save as
  `name(1).py`; a `cp` then re-copies the STALE file. Cure: new filename (`_v2`).
- File writes: heredoc directly to repo is fine for SHORT TypeScript that gets
  type-checked. For CANONICAL DOCS: download-from-chat + `cp`, OR anchored Python
  scripts with verify-all-anchors-before-write-any (an abort is the system
  working). Prefer SHORT single-line anchors. NEVER heredoc-with-backticks for docs.
- Two-commit convention: code commits separate from doc-control commits.
- `tsc --noEmit`, never `next build` with the dev server up.
- Verify pushes succeeded. Fix doc drift the session you find it (Standing Order #1).
- Handoffs + doc edits built on VERIFIED disk state (Rule 10), never memory.
- Ignore the VS Code sync/refresh icon (status bar) — all git is via WSL terminal.

---

## Document-control state at Chat 28 close

All three canonical docs UPDATED on disk AND committed/pushed (`f523cf0`):
- `5e-bridge-phase3-decisions-log-rev6.md` — Decisions 32, 33, 34 appended;
  31.4 supersession note added.
- `PROJECT-MAP.md` — C2, D2, E1 bullets; migration-021 UPDATE note; Feature Flag
  System graduated; stamp `f523cf0`.
- `ROADMAP-TO-TESTABLE.md` — C2/D2 struck; A5 flag note corrected; E1 partial +
  E1b/E1c sub-tasks.

**Files-panel swap at Chat 28 close:** the panel copies of these three docs were
replaced with the Chat-28 versions (uploaded from the Downloads `-v2` files,
verified with `diff -q`). If a future chat finds the panel behind disk, re-swap.

**This handoff (CHAT-28-HANDOFF.md) itself** was produced as a chat download and
`cp`-ed into `docs/session-handoffs/` after the terminal-heredoc attempt
corrupted the first copy — then committed. Verify it is committed via `git log`.
