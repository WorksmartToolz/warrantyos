# CHAT 33.1 HANDOFF — WarrantyOS Phase 3 (C4 COMPLETE + C3 false-blocker CORRECTED)

> **REV 33.1 CORRECTION (2026-07-30):** The Chat-32 "C3 customer action is
> BLOCKED by undrafted Tier 3 / issuance" conclusion was FALSE and is retracted.
> `claims.intake_token` exists and is built (027 L229-230, indexed); arch-ref
> L3466 is a shell-scope boundary note ("deferred to Tier 3"), not a foreclosure,
> and Tier 3 was built as 027. Chat 32 also dug the wrong table
> (`warranty_registrations`, which correctly carries no intake token — it has no
> connection to intake tokenization at all). **C3's customer action is BUILDABLE**,
> binding `claims.intake_token` exactly like C5/C6/C7. All C3 "blocked" lines below
> are corrected inline. This was a manufactured blocker — the DIG-LAW failure mode
> the docs warn about — caught by Andre's insistence, not the handoff.

# CHAT 33 HANDOFF — WarrantyOS Phase 3 (C4 COMPLETE — edit + status machine built + runtime-proven)

**Written at Chat 33 close, 2026-07-30.** (Filename is CHAT-33 because it is FOR
the next chat.) Every state claim traces to Andre's pasted terminal output.

---

## ⚖️ THE DIG LAW — STILL GOVERNS, READ FIRST (dig, dig, dig, dig)

**The only gaps are BUILDING, not DECIDING.** Design is ~95%+ complete
(Decisions 1–35, Phase 0 Items, arch-ref). If a future chat thinks it found a
*design* gap, **DIG — do not ask.** Search order: arch-ref → BOTH decisions logs
→ Phase 0 + Phase 1 audit → built migrations' CHECK constraints + column
comments → repo + git history → the SOPs and workbooks.

**Chat 33 is a FIFTH proof the dig pays off — but a different shape than C3.**
The C4 edit/status recommended-next was real and buildable, NOT a hidden blocker.
But the dig surfaced that **Decision 15 EXPLICITLY DEFERS two things a status
machine needs** — under its own "Open architectural questions deferred" heading:
(1) per-transition ACTOR rules ("can any Reviewer cancel, or only Team Admin"),
and (2) whether `completed` can transition backward. These are NOT locked. The
DIG LAW worked: digging 020 + Decision 15 for "the per-transition actor rules"
(as the Chat-32 handoff instructed) found the rules marked deferred, not absent
by oversight. This is the arch-ref-open-questions-trap pattern — a deferred block
reads like it could be answered by picking a default, and IS still open.

**Resolution WAS a real decision point, and Andre made both calls (Chat 33):**
- **Actor rules:** use the HOUSE DEFAULT — one `operational` class
  (`reviewer || team_admin`) for every transition, no per-transition
  differentiation. This DECLINES to differentiate rather than answering Decision
  15's deferred question — the conservative reading, identical to C2
  (inspection-progression) and the C4 write-path. If a future chat needs
  "only team_admin can cancel," that is a one-line change and a NEW decision.
- **Backward transitions / edit:** `completed` and `cancelled` are terminal (no
  backward edge). Editing is NOT a status transition — it is ordinary field
  editing, allowed **while no work has been executed against the plan**, i.e.
  before the claim reaches the Service Report stage. Because 15.1 defines
  `completed` AS "a Service Report has been submitted," the execution boundary IS
  the `completed` status → the edit gate is a pure status check (editable in
  `draft`/`sent_for_authorization`/`authorized`, locked in
  `completed`/`cancelled`), NO cross-table lookup. Edit is **content-fields-only**:
  `execution_path` and its coupled structural columns are NOT editable (switching
  who executes is a new-plan operation, not an edit).

Two smaller digs also resolved against locked sources (neither needed Andre):
- **Ordering:** arch-ref 6550-6551 captures duration as "derivable from the
  difference" of planned_start/end — NO ordering invariant is locked, and the
  create-path enforces none. Edit stays symmetric: no `end > start` check
  (Standing Order #2 — don't add what the decision doesn't call for).
- **Patch semantics:** dug arch-ref + BOTH logs (no convention) and grepped
  lib/core (no prior edit function). First-of-kind. Built as the honest
  application of 020's NOT NULL contract: key PRESENT → set, ABSENT → unchanged,
  null-to-clear ONLY on the three columns 020 declares nullable.

---

## Ground truth (verified this session via pasted terminal output)

- **HEAD:** `<FILL: run git log --oneline -1 after the handoff commit>`, pushed, origin = HEAD.
- **Branch:** session-5e-bridge-phase3-schema-generator, working tree clean.
- **Typecheck:** npx tsc --noEmit clean on committed state.
- **Migrations:** 32 on disk (none added — C4 edit/status is app-layer on 020).

### Session lineage (Chat 32 close -> Chat 33 close)

```
34a8af2  (Chat 32 handoff)
29fc21e  feat  C4 edit + status machine — core (transitionWorkPlanStatus + editWorkPlan) + actions (changeWorkPlanStatus + updateWorkPlan)
214f7fc  docs  Chat 33 stamp — PROJECT-MAP (C4 COMPLETE) + ROADMAP (C4 [x])
<this handoff commit lands on top>
```

Two-commit convention held: code (29fc21e) separate from the doc-control stamp
(214f7fc). C4 edit/status adds no migration and touches no arch-ref Status line,
so Convention 9 did not apply — code committed alone, no arch-ref edit.

---

## What Chat 33 did

### 1. C4 edit + status machine — BUILT + runtime-proven (29fc21e)
Appended to the existing two C4 files (create was 38bdfaa, Chat 32):
- **lib/core/work-plans.ts** — two new exports + their types, reusing the file's
  existing `fetchCallerProfile` / `richTextMaxChars` / `richTextLength` helpers:
  - `transitionWorkPlanStatus(workPlanId, to, requestedBy)` — mirrors C2
    `transitionInspectionStatus` exactly: reads current status from the DB
    (never trusts client for `from`), cross-tenant guard, transition map keyed
    current→legal-next, optimistic `.eq('status', from)` guard on the write.
    Map: `draft → [sent_for_authorization, cancelled]`,
    `sent_for_authorization → [authorized, cancelled]`,
    `authorized → [completed, cancelled]`; `completed`/`cancelled` terminal.
    Returns `{success, from, to, claimId}`.
  - `editWorkPlan(workPlanId, patch, requestedBy)` — content-fields-only patch,
    status-gate (editable statuses only), rich-text cap re-validation on any of
    the five ProseMirror fields present, cross-tenant guard, and an optimistic
    `.in('status', EDITABLE_STATUSES)` guard on the write so a concurrent
    transition to completed/cancelled cannot be clobbered. Returns
    `{success, id, claimId}`.
- **lib/actions/work-plans.ts** — import block expanded (anchored Python replace),
  two thin wrappers appended, verbs distinct from core per the insert/create
  precedent:
  - `changeWorkPlanStatus(workPlanId, to)` → delegates to
    `transitionWorkPlanStatus`, reuses `revalidateWorkPlanPages(claimId)`.
  - `updateWorkPlan(workPlanId, patch)` → delegates to `editWorkPlan`, same
    revalidation.

**Every element traced to 020 (read column-by-column) + Decision 15 + the C2
precedent + Andre's two Chat-33 calls. Zero improvised architecture.**

### 2. Runtime smoke test — 24/24 PASS
Ephemeral `c4_status_smoke.ts` (download + cp to repo root, deleted after — git
status verified clean, only the two source files committed). Seeded against the
DB-verified column/CHECK contract (queried live this session: NOT-NULL columns +
every CHECK's legal values, registration `pre_activation` so both assignee FKs
stay null). Env-override run
(`NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321 SUPABASE_SERVICE_ROLE_KEY=$SVC`).
Proved what tsc cannot:
- **Transitions (11):** full legal chain draft→sent→authorized→completed;
  draft→cancelled; both terminals reject outbound; skip-transitions rejected;
  cross-tenant caller rejected; viewer rejected.
- **Edit (12):** succeeds in all three editable states + actually writes the
  value; rejected in completed & cancelled; **null clears a nullable field;
  absent key leaves another field untouched; null rejected on a required field;
  empty patch rejected; cross-tenant rejected.**
- **16.3 (1):** parts-claim work plan still rejected.
The edit patch-semantics block is the first-of-kind logic with no precedent —
the reason this test existed rather than trusting the C2 mirror. tsc alone could
not have caught a patch-semantics bug.

### 3. Doc-drift sweep (214f7fc)
- PROJECT-MAP: C4 entry merged (Create → Create+Edit+Status, BUILT / UI pending);
  stamp Chat 32/38bdfaa → Chat 33/29fc21e.
- ROADMAP: C4 checkbox flipped `[x]`, edit/status annotation added mirroring the
  create annotation. **C4 COMPLETE** recorded.

---

## ⚠️ NO loose ends created this session

C4 is now a complete unit (create + edit + status). The UI surface is a finished
external edge (a future layer, not half-built work here). The smoke artifact was
removed. Both commits pushed, origin = HEAD.

---

## NEXT UNIT — Andre decides; sequencing is his

**C3 customer-facing action is NOT blocked — the Chat-32 blocker was FALSE
(corrected Chat 33.1).** The dig: `claims.intake_token` + `intake_token_expires_at`
EXIST (027 L229-230, indexed L278-280), structurally identical to `customer_token`
(022/C5), `claimant_token` (025/C7), `recipient_token` (026/C6) — none of which
is blocked. arch-ref L3466 ("tokenized intake is Tier 3") is a SHELL-scope
boundary note under "What is NOT in the shell" (016), meaning "deferred to the
Tier 3 section" — and Tier 3 IS drafted + built as 027. Chat 32 also dug the wrong
table (`warranty_registrations`, which correctly has no token). C3 customer action
binds `claims.intake_token` exactly like C5/C6/C7; the token is minted at
generate/send and validated at customer submit — an ordinary build seam, not an
undrafted subsystem. **C3 IS BUILDABLE.**

Buildable-now, dependency-free candidates:

1. **B-layer (clock/cron)** — its own full-session arc. Owns C10's two system
   transitions, ALL clock_events firing, C4's system `completed` transition (the
   "a service_report exists → advance" path deliberately NOT built here — the
   status machine is caller-driven only, exactly as C2 omitted its system path),
   AND WarrantyID generation's first consumer `warranty_id_early_issuance`
   (mirror 031's shape). Do NOT start as a back-half item.
2. **C5/C6/C7/C8/C9** — the tokenized customer-facing action surfaces. Each
   carries its own token (built: tokens.ts validate/consume) + clock row +
   possibly an Acknowledgment Gate. Unlike C3, these operate on rows the
   WARRANTOR creates first, so their tokens ARE minted by the warrantor-side
   generate action — no undrafted issuance dependency. Confirm per-surface.

**RECOMMENDED:** either B-layer (if a fresh full session) or a C5–C9 surface.
No C4 work remains except the UI (a Phase-4/UI-layer concern).

**NOTE for whoever builds C4's system `completed` transition:** it belongs to the
B-layer. When `editWorkPlan`/`transitionWorkPlanStatus` need a system entry point
(a `transitionWorkPlanStatusAsSystem` analogous to C10's), that is B-layer work —
DIG Decision 15's Service-Report-existence rule + the clock subsystem before
writing it. Deliberately NOT written this session (would be improvising B-layer).

---

## Buildable-now map

- **C3 core** — built + runtime-proven (Chat 31). **C3 customer action —
  BUILDABLE** (Chat-32 "blocked" was FALSE, corrected 33.1; binds `claims.intake_token`).
- **C4** — COMPLETE (create Chat 32, edit/status Chat 33). Only UI remains.
- **B-layer** — dedicated full-session arc (also builds WarrantyID generation
  AND C4/C10 system transitions).
- **C5–C9** — tokenized surfaces; token layer ready; warrantor-minted tokens
  (no C3-style issuance blocker — confirm per surface).

---

## Canonical docs (read PROJECT-MAP.md FIRST, then ROADMAP)

- PROJECT-MAP.md — stamp era Chat 33, HEAD 29fc21e; 35 decisions, 32 migrations,
  29 tables + 1 view + 4 functions. C4 Create+Edit+Status in the BUILT list.
- docs/ROADMAP-TO-TESTABLE.md — C4 `[x]` COMPLETE.
- docs/architecture-reference.md — 7346 lines. Work Plan Workflow section + 020.
  **L3466: "tokenized intake is Tier 3" is a SHELL-scope boundary note (016's
  "What is NOT in the shell"), NOT a foreclosure — Tier 3 is built as 027, which
  added claims.intake_token. NOT a C3 blocker (corrected 33.1).**
  L6550-6551: duration "derivable from the difference" — no ordering invariant.
- docs/session-handoffs/5e-bridge-phase3-decisions-log-rev6.md — Decisions
  11–35. **Decision 15 L961** — Work Plan status machine; its "Open architectural
  questions deferred" block is what Chat 33 resolved via Andre's calls (house
  default + terminal). Decision 2 is in the Phase 2 log, NOT this one.
- docs/session-handoffs/5e-bridge-phase2-decisions-log.md — Phase 2, incl.
  Decision 2 (ID generation) and Decision 4 (rich-text cap, platform-wide
  per-field, L173-197). BOTH logs live.
- CLAUDE-rev6.md — Conventions 7/7a/8/9, Rule 10, execution discipline.

---

## Standing disciplines still in force

- **THE DIG LAW governs.** Chat 33 dug Decision 15 to the floor and found its
  actor/backward-edge questions DEFERRED, not answered — a real decision point,
  correctly routed to Andre rather than improvised. A deferred block that reads
  like a pickable default is STILL open (the arch-ref-open-questions trap).
- Andre is dyslexic. **ONE command per WSL message**; the RUN IN WSL label; only
  the command in the code block. **NO ;/&& chaining** without explicit permission.
- **Canonical docs:** download-from-chat + cp, OR anchored Python scripts run in
  WSL. NEVER heredoc for canonical docs. Typechecked TS MAY heredoc directly to
  the repo file (this session's core/action appends did, both tsc-clean).
- **Anchored doc edits:** verify ALL anchors (.count()==1) across ALL files
  BEFORE writing ANY (abort = system working). Prove uniqueness with `grep -Fc`
  (the `-F` matters — `[ ]`/`**`/backticks/em-dash break bare grep). This
  session's ROADMAP (2 anchors) and PROJECT-MAP (3 anchors) edits each verified
  all anchors before applying any.
- Two-commit convention: code separate from doc-control. Both held this session.
- tsc --noEmit, never next build with the dev server up.
- Verify pushes (git log shows origin = HEAD). Fix doc drift the session you
  find it (Standing Order #1). Handoffs built on VERIFIED disk state (Rule 10).
- **db reset applied clean proves execution, not correctness.** This session's
  24/24 smoke proved the transition rejections + edit gate + first-of-kind patch
  semantics + cross-tenant/viewer authz — tsc proved none of it. "Tests are
  checkpoints, not investigations" means DON'T SKIP the checkpoint for novel
  logic AND don't sprawl it — a focused 24-check test was the right size.
- **.env.local hazard:** NEXT_PUBLIC_SUPABASE_URL points at hosted production.
  Always run local scripts with the
  NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321 SUPABASE_SERVICE_ROLE_KEY=$SVC
  override. Capture $SVC from `supabase status`.
- **psql regclass filter:** `conrelid::regclass::text` renders WITHOUT the
  `public.` prefix — filter on bare table names (`'work_plans'`, not
  `'public.work_plans'`) or a zero-row result misleads.

---

## Document-control state at Chat 33 close

Committed + pushed:
- 29fc21e — lib/core/work-plans.ts + lib/actions/work-plans.ts (C4 edit/status).
- 214f7fc — PROJECT-MAP (C4 COMPLETE + stamp), ROADMAP (C4 `[x]`).
- <this handoff commit> — docs/session-handoffs/CHAT-33-HANDOFF.md.

**Files-panel state (Standing Order #3):** the panel copies edited in-repo via
anchored Python are NEVER downloaded, so there is nothing to "swap" for
PROJECT-MAP / ROADMAP — disk is source of truth, committed and pushed, and a new
chat orients from `git`, not the panel. This retracts the Chat-32 "swap the
panel" instruction for these two. If the panel reads a stale stamp, that is
harmless; trust `git log --oneline -1`. This new CHAT-33-HANDOFF.md may be added
to the panel if desired, but is not required for correctness.

**Carried cosmetic drift (from Chat 29, STILL open — Standing Order #1, low
value):** panel entries carry -v2 suffixes while repo files are canonical-named;
the panel .txt arch-ref and .docx SOP copies are TRUNCATED FRAGMENTS. A
deliberate panel-reorganization task, better done intentionally than at a
session close. Flagged so it is not lost. Unchanged this session.

**This handoff (CHAT-33-HANDOFF.md)** is produced as a chat download, cp-ed into
docs/session-handoffs/, then committed. Verify via git log. After committing,
replace the two `<FILL>` / `<this handoff commit>` placeholders with the real
handoff-commit hash if a self-contained record is wanted (cosmetic one-liner,
not a verification gap — the one-behind pattern is standard).
