# CHAT 27 HANDOFF — WarrantyOS Phase 3 (app-layer build; C10 claim-progression BUILT)

**Written at Chat 27 close, 2026-07-22.** (Filename is CHAT-27 because it is FOR the next chat.)

Every state claim below traces to Andre's actual pasted terminal output this session.

---

## ⚖️ THE DIG LAW still governs (unchanged from Chat 26)

**The only gaps now are BUILDING, not DECIDING.** If a future chat thinks it has
found a *design* gap, DIG — don't ask. The answer is almost always already locked
under a name or in a section not yet checked. Dig across ALL tiers (arch-ref,
BOTH decisions logs, Phase 0 + Phase 1 audit, the built migrations' CHECK
constraints + column comments, the repo + git history, and the SOPs/workbooks
themselves) before bringing any question to Andre. "I need Andre to decide" is a
red flag meaning the dig wasn't deep enough.

**Chat 27 is a fresh example of the dig paying off.** C10 *looked* like it needed
three design decisions (transition map, actor per transition, escalation-verdict
authz). The dig recovered the transition map and actors almost entirely from the
three lifecycle SOPs + the two escalation workbooks, and resolved the one genuine
open question (escalation-verdict authz) against the already-locked
`tenants.settings` pattern — NOT as fresh architecture. Only that single point
(31.4) was design-fresh, and it was ratified by Andre in-session.

**Reminder that saved time this session:** the 7 SOP `.docx` files in the project
Files are PLAIN TEXT with a `.docx` extension — read them with `cat`/`view`, not
pandoc/unzip. The workbooks ARE real `.xlsx` — read with `python3 openpyxl`.

---

## Ground truth (verified this session via pasted terminal output)

- **HEAD:** `7e2ddfd`, pushed, `origin` = HEAD (confirmed via `git push`)
- **Branch:** `session-5e-bridge-phase3-schema-generator`
- **Working tree:** clean (`git status --short` empty after the two commits)
- **Typecheck:** `npx tsc --noEmit` clean (C10 pair compiles against real Database types)
- **Migrations:** 31 on disk (unchanged this session — C10 is app-layer, no migration)

### Commits this session (Chat 27)

| Hash | What |
|------|------|
| `85f7f1b` | feat(claims): C10 claim-progression Six Gates transition machine (2 files, 402 insertions) |
| `7e2ddfd` | docs(decisions,project-map): Decision 31 + PROJECT-MAP C10-built, stamp Chat 27, count 31 |

Lineage: `3e05a3c` (Chat 26 handoff) → `85f7f1b` → `7e2ddfd`.

---

## What Chat 27 built — C10 (claim progression)

**The Tier 3 Six Gates status machine is now BUILT in the app layer.** Two files:

- `lib/core/claim-progression.ts` — the transition map, actor authorization, the
  ALA data precondition, the tenant-settings escalation-verdict reader, and both
  the user path (`transitionClaimStatus`) and the system path
  (`transitionClaimStatusAsSystem`).
- `lib/actions/claims.ts` — the thin `'use server'` wrapper (`progressClaim`),
  mirroring `inspections.ts`.

Decision 31 (Phase 3 decisions log) records it in full. Key points:

- **Transition map** recovered from SOP 1 + the Denied/Escalated SOPs + the two
  Denial-Escalation workbooks. Single declarative structure keyed by current
  status; unlisted transitions are illegal.
- **Authz classes:** `operational` (reviewer OR team_admin — all linear-flow
  transitions), `escalation_verdict` (tenant-configurable, see below), `system`
  (clock-driven, no human caller).
- **ALA data precondition (19.7):** `indistinct_ala_required → evidence_evaluation`
  is permitted only when the claim's `ala_documents` row is `signed`
  (`claimant_decision = 'accepted'` AND `signed_at IS NOT NULL`). The one
  transition gated by data on another table. `indistinct_ala_required` = BLOCKED
  state (UI shows "Indistinct — ALA Required"); `evidence_evaluation` = CLEARED,
  investigating state after the ALA signs.
- **Escalation-verdict authz (31.4 — the one design-fresh point):** a per-tenant
  setting `tenants.settings.escalation_verdict_authorized_role`, default
  `team_admin` (bias-prevention "higher authority" path), tenant may widen to
  `reviewer`. New instance of the locked `tenants.settings` pattern; C10 has the
  FIRST built settings-key reader. Absent/malformed → safe default.
- **Optimistic concurrency guard:** the status write is
  `UPDATE ... WHERE id = claimId AND status = from`, so concurrent transitions
  can't clobber each other.
- **Denial is early-gate only** (SOPs). The map structure keeps later denial
  edges a one-line addition if the operational chain ever requires them (Andre:
  "nothing is concrete, anything is possible even if it hasn't happened yet").

---

## INTERFACE SEAMS (nothing open; these are finished edges, not deferred work)

1. **`escalation_verdict_authorized_role` seeding — CLOSED THIS SESSION** (`244d33d`).
   Seeded in `lib/core/provision-tenant.ts` alongside the six existing settings
   defaults. New tenants get `'team_admin'` (the bias-prevention default) at
   provisioning. D2 does NOT own this; it is done. C10 also
   falls back to the same default if the key is ever absent, so both paths agree.
2. **B-layer inherits `transitionClaimStatusAsSystem`** as the entry point for the
   two clock-driven transitions (`customer_review → closed` on 3-day silence;
   `denied → closed` on lapsed dispute window). The B-layer must verify the
   deadline before calling; C10 does not check the clock itself.
3. **UI surface for C10 not built** (roadmap, whichever F-step owns claim views).
   The `revalidatePath` targets in `claims.ts` are safe no-ops until those routes
   exist.

---

## OPEN ITEMS — none blocking

Working tree clean, all four commits pushed, HEAD = origin, typecheck clean, no
pending doc-control. No drift carried.

---

## RECOMMENDED NEXT (Andre decides; sequencing is his) — all BUILD tasks

From the roadmap, still-unbuilt app-layer:

1. **C2 (inspection edit/status machine)** — small; reuses the C0/C10 shape;
   exercises `open → in_progress → under_review → issued`. *Source: 021.*
2. **B-layer (clock/cron)** — biggest structural subsystem; owns the two C10
   system transitions + all `clock_events` firing. Its own dedicated arc.
3. **D2 (feature-flag reader + storage)** — owns the deferred provisioning
   defaults incl. the new `escalation_verdict_authorized_role`. The flag STORAGE
   SHAPE (JSONB `tenants.settings.enabled_features` vs a dedicated
   `tenant_features` table) is a BUILD-time fork per arch-ref ~400, not a design
   gap — JSONB = lighter start.

---

## Canonical docs (read PROJECT-MAP.md at repo root FIRST, then the ROADMAP)

- `PROJECT-MAP.md` — durable orientation, stamp current as of `7e2ddfd` (Chat 27);
  C10 recorded in the app-layer inventory (~line 748) and the claims-shell note
- `docs/ROADMAP-TO-TESTABLE.md` — build order + the Locked Decision Rule
- `docs/architecture-reference.md` — claim shell 3246+; ALA gate 19.7 / arch-ref
  4304-4309; feature flags ~380-520
- `docs/session-handoffs/5e-bridge-phase3-decisions-log-rev6.md` — Decisions 11-31
  (31 is C10 claim-progression)
- `docs/session-handoffs/5e-bridge-phase2-decisions-log.md` — Phase 2 (Decision 3 here); BOTH logs live
- `CLAUDE-rev6.md` — Conventions 7/7a/8/9, Rule 10

---

## Standing disciplines still in force

- **THE DIG LAW governs. Dig, find, dig again, until exhausted.**
- Andre is dyslexic. **ONE command per WSL message**; `▶ RUN IN WSL` labels; only
  the command in the code block. NEVER paste prose or old scrollback into a
  command block (Chat 27 hit this: a stray `</parameter>` tag + trailing prose
  garbled a git commit — recovered, re-ran clean).
- **Download-collision gotcha (cost Chat 27 a few turns):** re-downloading a
  script with the SAME filename can save as `name(1).py` instead of overwriting,
  so a `cp` re-copies the STALE file. Symptom: an anchored script aborts
  identically after a "fix." Cure: ship the corrected script under a NEW filename
  (`_v2`). Consider Claude Code desktop to remove the relay entirely.
- File writes: sandbox → present_files (download) → Andre `cp`s from
  `/mnt/c/Users/andre/Downloads/`. Doc edits via Python anchored scripts with
  verify-all-anchors-before-write-any (an abort is the system working). NEVER
  heredoc-with-backticks.
- Anchor discipline: prefer SHORT single-line anchors; multi-line anchors risk
  line-boundary mismatches (Chat 27 edit 2 aborted on a 2-line anchor, fixed with
  a 1-line one). Verify anchor uniqueness with `grep -c` before running.
- Two-commit convention: code commits separate from doc-control commits (done
  this session: `85f7f1b` code, `7e2ddfd` docs).
- `tsc --noEmit`, never `next build` with the dev server up.
- Verify pushes succeeded. Fix doc drift the session you find it.
- Handoffs + doc edits built on VERIFIED disk state (Rule 10), never memory.
