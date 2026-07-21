# CHAT 26 HANDOFF — WarrantyOS Phase 3 (app-layer build; D1 design gap CLOSED)

**Written at Chat 26 close, 2026-07-21.** (Filename is CHAT-26 because it is FOR the next chat.)

Every state claim below traces to Andre's actual pasted terminal output this session.

---

## ⚖️ READ FIRST — THE DIG LAW (Andre's standing instruction, hardened this session)

**The only possible gaps now are BUILDING, not DECIDING.** Phase 3 design is
essentially complete. If a future chat thinks it has found a *design* gap — a
decision that needs making — that is the signal to **DIG, NOT ASK.** The answer
is almost always already locked somewhere under a name or in a section not yet
checked.

**The dig protocol (follow it exhaustively before ever bringing a question to Andre):**
1. **Dig.** Read the locked source the task names.
2. **Find something → dig again.** A partial hit (one gate named, one value
   listed) means the rest is nearby — keep going.
3. **Dig again, and again, across ALL tiers**, in this order, until the answer
   is found or every tier is exhausted:
   - the architecture reference (full, not one region)
   - BOTH decisions logs (Phase 2 + Phase 3 rev6)
   - the Phase 0 items + Phase 1 audit
   - **the built migrations on disk** (CHECK constraints + column comments encode
     SOP constraints — Chat 25 found gate names in `016_claims.sql` comments that
     were in NO design doc)
   - the repo + **git history** (`git log --all --diff-filter=A --name-only`)
   - **the SOPs/workbooks themselves** — NOTE: the 7 SOP `.docx` files in the
     project Files are PLAIN TEXT saved with a `.docx` extension. `pandoc`/`unzip`
     FAIL on them ("not a zip file"). Read them with `cat` or `python3` reading
     raw bytes — the content is right there. Chat 25 wasted turns treating them
     as corrupt before discovering this.
4. **"I need Andre to decide" is a RED FLAG** meaning the dig wasn't deep enough.
   Go back and dig further. Only after EVERY tier is exhausted with nothing found
   may a grounded, minimal question go to Andre — with the dig shown.
5. **The ONE exception is a genuine, proven design gap** (locked design truly does
   not exist anywhere, across all tiers). Chat 25's D1 was the last such gap and
   it is now CLOSED. Do not expect another; if one seems to appear, it is almost
   certainly stale doc-drift or an un-dug lock. Prove exhaustion before treating
   anything as design-fresh.

**Chat 25 is the cautionary/exemplary tale both ways:** the D1 gate machine LOOKED
undecided, and four times Andre said "dig deeper, it's locked somewhere." The dig
recovered real gate names from the build info (016 comments) and outcome names from
migration 025 + arch-ref — proving most of it WAS locked. Only the *assembly* (the
closed enum + the four unnamed gates) was genuinely design-fresh. The lesson: dig
until the sources are exhausted; most "gaps" dissolve under a deep enough dig.

---

## Ground truth (verified this session via pasted terminal output)

- **HEAD:** `fc61b14`, pushed, `origin` = HEAD (confirmed via `git push` + `git log`)
- **Branch:** `session-5e-bridge-phase3-schema-generator`
- **Working tree:** clean (`git status --short` empty)
- **Migrations:** 31 on disk, newest is `030_claim_lifecycle_status.sql`
- **DB verified:** `\d public.claims` shows `claims_status_check` carrying all
  twelve values (not just "applied clean" — the constraint bytes were read from
  the live DB)

### Commits this session (Chat 26)

| Hash | What |
|------|------|
| `0b27f70` | feat(claims): Decision 30 — claim lifecycle Six Gates status enum (030) |
| `a7658b3` | docs(decisions): Decision 30 log entry |
| `b50ebf3` | docs(arch-ref): Convention 7 supersession note on the claim-status deferral |
| `201d666` | docs(roadmap): strike D1 done |
| `fc61b14` | docs(project-map): reflect Decision 30 + stamp bump to Chat 26/201d666 |

Lineage: `9a271b8` (Chat 24 close) → `0b27f70` → `a7658b3` → `b50ebf3` → `201d666` → `fc61b14`.

---

## What Chat 26 did — resolved D1 (the last design gap) and built migration 030

**D1 — Tier 3 Claim Lifecycle (Six Gates) — is CLOSED.** Decision 30 locks the
`claims.status` enum at twelve values on the single status column (NO gate-level
columns; arch-ref 3415):

- **Six gate stages** (SOP 1 order): `intake_received` (entry) · `administrative_
  validation` (Gate 1, named in 016) · `responsibility_notice` (Gate 2) ·
  `evidence_evaluation` (Gate 3, named in arch-ref 4356) · `work_planning_
  authorization` (Gate 4) · `execution_service_report` (Gate 5) · `customer_review`
  (Gate 6).
- **Five outcomes:** `resolved` · `closed` · `denied` · `escalated` ·
  `indistinct_ala_required`.
- **Transitions + authorized actors are NOT in the DB** (Decision 30.3) — same
  discipline as work_plans (Decision 15). They live in the C10 claim-progression
  Server Actions, still unbuilt.

Migration 030 is a CHECK swap on `claims_status_check` (016's one-value shell →
twelve values) + refreshed column comment. No table/column added.

**Honest carry-forward (from Decision 30's own "design-fresh" flag):** Gates
2/4/5/6 names and the `denied`/`escalated` outcomes were DESIGNED against SOP 1's
flow + the escalation workbooks, not recovered verbatim from a prior lock. Gates
1/3 and `resolved`/`closed`/`indistinct_ala_required` ARE named in locked sources.
If Andre's original SOP gate terminology ever surfaces and differs, those value
names are the thing to reconcile.

**Doc-control (all committed, no drift left):** arch-ref got a Convention 7
supersession note at the "Claim status interactions (deferred to claim lifecycle)"
section (narrative frozen, forward-pointer added); roadmap D1 struck; PROJECT-MAP
claim-status line updated + stamp bumped.

---

## OPEN ITEMS — none blocking

Working tree clean, all five commits pushed, HEAD = origin, DB verified, no
pending doc-control. D1 removed from the roadmap's open list.

---

## RECOMMENDED NEXT (Andre decides; sequencing is his) — all BUILD tasks, no design left

The C0/C1 shape (action=callerId → core=tenant+authz+mutate, mirroring manage-team)
is the proven template. From the roadmap:

1. **C2 (inspection edit/status machine)** — small, reuses C0's shape, exercises
   `open → in_progress → under_review → issued`. *Source: 021.*
2. **C10 (claim progression)** — now UNBLOCKED by Decision 30. Builds the gate
   transitions + authorized actors that 030 deliberately left to the app layer.
   *Source: Decision 30.3; the twelve-value enum in 030.*
3. **B-layer (clock/cron)** — biggest structural subsystem; its own dedicated arc.
4. **D2 (feature-flag reader + storage)** — owns the 3 provisioning flag defaults
   deferred from A5; unblocks flag-gated C-layer branches. NOTE: the flag STORAGE
   SHAPE (JSONB `tenants.settings.enabled_features` vs dedicated `tenant_features`
   table) is the one remaining "open Phase 3 implementation choice" per arch-ref
   ~400 — a small BUILD-time fork, not a design gap; pick per the arch-ref's
   stated tradeoffs (JSONB = lighter start).

---

## Canonical docs (read PROJECT-MAP.md at repo root FIRST, then the ROADMAP)

- `PROJECT-MAP.md` — durable orientation, header current as of `fc61b14` (Chat 26)
- **`docs/ROADMAP-TO-TESTABLE.md`** — build order + the Locked Decision Rule; D1 struck
- `docs/architecture-reference.md` — Decision-30 supersession note at "Claim status
  interactions"; claim shell 3246+; feature flags ~380-520
- `docs/session-handoffs/5e-bridge-phase3-decisions-log-rev6.md` — Decisions 11-30
  (30 is the claim lifecycle Six Gates)
- `docs/session-handoffs/5e-bridge-phase2-decisions-log.md` — Phase 2 (Decision 3 here); BOTH logs live
- `CLAUDE-rev6.md` — Conventions 7/7a/8/9, Rule 10

---

## Standing disciplines still in force

- **THE DIG LAW governs (top of this file). Dig, find, dig again, until exhausted.
  The only gaps are building, not deciding.**
- Andre is dyslexic. **ONE command per WSL message**; `▶ RUN IN WSL` /
  `▶ RUN IN CLAUDE CODE` labels; only the command in the code block. NEVER give a
  command with old scrollback text pasted around it (Chat 26 hit a stuck-shell
  from a garbled multi-line paste — recovered with Ctrl+C).
- **File writes to Andre's repo go: sandbox → present_files (download link) →
  Andre `cp`s from `/mnt/c/Users/andre/Downloads/`.** For doc edits, use a Python
  script with anchor-count assertions (aborts safely if anchors are wrong); NEVER
  heredoc-with-backticks. Two commands (cp, then run) as separate messages.
- Two-commit convention: code commits separate from doc-control commits.
- Verify pushes succeeded. `tsc --noEmit`, never `next build` with the dev server up.
- `db reset` proves EXECUTION, not correctness — verify computed output by direct
  `docker exec supabase_db_warrantyos psql -U postgres -d postgres -c "..."`. (For a
  plain CHECK swap like 030, applied-clean DOES prove correctness — but still read
  the constraint bytes back, as Chat 26 did.)
- Verification hits LOCAL only — `.env.local` points at HOSTED PROD
  (`uzjivnmwedfzcgqnnhos`); always prefix local runs with
  `NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321` (Chat 24 Finding 1).
- Fix doc drift the session you find it (done this session — no drift carried).
- Handoffs and doc edits are built on VERIFIED disk state (Rule 10), never memory.
