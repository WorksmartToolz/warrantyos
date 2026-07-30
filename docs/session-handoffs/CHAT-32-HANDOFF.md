# CHAT 32 HANDOFF — WarrantyOS Phase 3 (C4-create built + runtime-proven)

**Written at Chat 32 close, 2026-07-30.** (Filename is CHAT-32 because it is FOR
the next chat.) Every state claim traces to Andre's pasted terminal output.

---

## ⚖️ THE DIG LAW — STILL GOVERNS, READ FIRST (dig, dig, dig, dig)

**The only gaps are BUILDING, not DECIDING.** Design is ~95%+ complete
(Decisions 1–35, Phase 0 Items, arch-ref). If a future chat thinks it found a
*design* gap, **DIG — do not ask.** Search order: arch-ref → BOTH decisions logs
→ Phase 0 + Phase 1 audit → built migrations' CHECK constraints + column
comments → repo + git history → the SOPs and workbooks.

**Chat 32 is a FOURTH consecutive proof the dig pays off.** The prior handoff's
"recommended next" was C3-action, framed as a clean append with "one seam to
confirm." Digging the seam to the floor DISSOLVED it into a hard blocker instead:

- **C3 customer-facing action is BLOCKED by an undrafted dependency.** The dig
  chain: 027 header L106 ("the gate is an INTERSTITIAL on intake_token — there
  is no second token") -> 031 L137-138 (create_claim_with_generated_id creates
  the claim with intake_token NULL; "issuance subsystem mints it") ->
  lib/core/claims.ts header ("Minting of that token is the issuance subsystem
  (unbuilt) — a finished external edge") -> tokens.ts Decision 35 (a NULL token
  is "unvalidatable") -> **arch-ref L3466: "No tokenized link columns. Tokenized
  intake is Tier 3."** Tier 3 is undrafted. warranty_registrations carries no
  token column (grep-verified). So the C3 action's token-validation step has NO
  real column to bind to — building it means inventing the issuance/Tier-3
  contract, which 027 + claims.ts + arch-ref all forbid. **The roadmap already
  said so** (C3 line: "Depends on E1 (token infra)"). Not a testing seam — a real
  unbuilt layer. **Do not attempt the C3 customer action until the issuance
  subsystem / Tier 3 tokenized-intake storage is designed.**

The dig ROUTED to the dependency-free unit instead: **C4-create**, which the
prior handoff's own buildable-now map named "independent, no token coupling."

---

## Ground truth (verified this session via pasted terminal output)

- **HEAD:** `<FILL: run git log --oneline -1 after the handoff commit>`, pushed, origin = HEAD.
- **Branch:** session-5e-bridge-phase3-schema-generator, working tree clean.
- **Typecheck:** npx tsc --noEmit clean on committed state.
- **Migrations:** 32 on disk (none added this session — C4 is app-layer on 020).

### Session lineage (Chat 31 close -> Chat 32 close)

```
5f47693  (Chat 31 handoff)
38bdfaa  feat  C4 create write-path — insertWorkPlan core + createWorkPlan action
64e8c22  docs  Chat 32 stamp — PROJECT-MAP + ROADMAP (C4-create annotated)
<this handoff commit lands on top>
```

Two-commit convention held: code (38bdfaa) separate from the doc-control stamp
(64e8c22). C4-create adds no migration and touches no arch-ref Status line, so
Convention 9 did not apply — code committed alone, no arch-ref edit.

---

## What Chat 32 did

### 1. C4-create write-path — BUILT + runtime-proven (38bdfaa)
Two new files (neither existed):
- lib/core/work-plans.ts — insertWorkPlan(input, requestedBy). Mirrors the C0
  inspection write-path (lib/core/inspections.ts) exactly: reviewer || team_admin
  operational authz via fetchCallerProfile, cross-tenant guard on the parent
  claim, service-role insert, {success,id}|{success,error} result.
- lib/actions/work-plans.ts — createWorkPlan(input). Thin, mirrors
  lib/actions/inspections.ts: getCallerId() via session client, delegate to
  core, revalidatePath on success.

**Every element traced to migration 020 (read column-by-column) + Decisions
13/15/16 + the inspections precedent. Zero new decisions.**
- Two Decision 13.1 conditional path couplings validated app-layer (DB CHECKs
  are backstop): internal_team_id present iff warrantor_self_performs;
  subcontractor_contact_id present iff a subcontractor path; both null on
  customer_self_services.
- Parts Claims exclusion (16.3): rejects a replacement_parts parent claim,
  app-layer (020's omissions list: no DB constraint couples this table to the
  parent's claim_type).
- Subcontractor FK+Snapshot: name/email/phone captured from the validated
  contacts row (columns verified: name NOT NULL, email/phone nullable), never
  client input. warranty_professional_user_id is a PLAIN FK — 020 defines no
  snapshot columns for it (do not invent them).
- Rich-text cap (Decision 4): confirmed platform-wide per-field (Phase 2 log
  L173-197: "per rich text field value", server-side authoritative), NOT
  claims-specific. Applied to all five ProseMirror JSONB fields, reusing the
  claims.ts richTextLength/richTextMaxChars idiom.
- status omitted on insert — DB defaults draft (Decision 15.1).

### 2. Runtime smoke test — 10/10 PASS
Followed the Chat-31 fixture recipe (env-override tsx, seed the parent chain).
Adaptations: no claim_id sequence row needed (C4 does not generate an ID — seeds
the parent claim directly with a literal claim_id); added a public.users caller
(via admin.auth.admin.createUser first, because public.users.id FKs
auth.users(id) — verified in 000_baseline), an internal_team, a subcontractor
contact, and a second parts claim. Verified directly against the DB:
- All four execution_paths create successfully.
- Both conditional CHECKs reject every mismatched combination (no team on
  warrantor_self; no contact on subcontractor; team present on customer_self).
- Parts claim rejected (16.3). Subcontractor snapshot captured from the contact
  row. Unauthorized caller rejected.
Test script was ephemeral (in-repo c4_smoke.ts, deleted after — git status
clean, only the two source files committed).

### 3. Doc-drift sweep (64e8c22)
- ROADMAP: C4 line annotated (CREATE built + runtime-proven, checkbox open —
  edit/status machine remains), mirroring C3's annotation style.
- PROJECT-MAP: stamp Chat 31/5e2b90e -> Chat 32/38bdfaa; Work Plan Create (C4)
  added to the app-layer BUILT list in the C2/C10 format.

---

## ⚠️ NO loose ends created this session

C4-create is a complete, self-contained unit. The edit/status machine is C4's
OWN next unit (a finished edge here, not half-built work). The test artifact was
removed. Both commits pushed, origin = HEAD.

---

## NEXT UNIT — Andre decides; sequencing is his

**C3 customer-facing action is OFF the buildable-now list** until the issuance
subsystem / Tier 3 tokenized-intake storage is designed (see THE DIG LAW above).
Do not re-attempt it as an append — the dependency is real and undrafted.

Buildable-now, dependency-free candidates:

1. **C4 edit + status machine** — the five-state machine (15.1: draft ->
   sent_for_authorization -> authorized -> completed/cancelled) on the built
   table, plus edit. Finishes C4 (flips its checkbox). Warrantor-authed, mirrors
   the C2 inspection-progression precedent (lib/core/inspection-progression.ts).
   Transition authority per 15.1 is downstream/app-layer — DIG 020 + Decision 15
   for the per-transition actor rules before building. Natural continuation.
2. **B-layer (clock/cron)** — its own full-session arc. Owns C10's two system
   transitions, all clock_events firing, AND WarrantyID generation's first
   consumer warranty_id_early_issuance (mirror 031's shape for the second ID-Gen
   consumer). Do NOT start as a back-half item.
3. **C5/C6/C7/C8/C9** — the tokenized customer-facing action surfaces. Each
   carries its own token (built: tokens.ts validate/consume) + clock row +
   possibly an Acknowledgment Gate. NOTE: unlike C3, these operate on rows the
   WARRANTOR creates first (work_auth documents, notices, ALAs, service reports),
   so their tokens ARE minted by the warrantor-side generate action — no
   undrafted issuance dependency. Confirm this per-surface before building.

**RECOMMENDED:** C4 edit/status — finishes what this session started,
dependency-free, mirrors a built precedent.

---

## Buildable-now map

- **C3 core** — built + runtime-proven (Chat 31). **C3 customer action —
  BLOCKED (Tier 3 / issuance undrafted).**
- **C4 create** — built + runtime-proven (Chat 32). **C4 edit/status — buildable
  now**, mirrors C2 progression.
- **B-layer** — dedicated full-session arc (also builds WarrantyID generation).
- **C5–C9** — tokenized surfaces; token layer ready; warrantor-minted tokens
  (no C3-style issuance blocker — confirm per surface).

---

## Canonical docs (read PROJECT-MAP.md FIRST, then ROADMAP)

- PROJECT-MAP.md — stamp era Chat 32, HEAD 38bdfaa; 35 decisions, 32 migrations,
  29 tables + 1 view + 4 functions. C4-create in the BUILT list.
- docs/ROADMAP-TO-TESTABLE.md — C4 annotated (create proven, checkbox open).
- docs/architecture-reference.md — 7346 lines. Work Plan Workflow section + 020.
  **L3466: tokenized intake is Tier 3 (undrafted) — the C3-action blocker.**
- docs/session-handoffs/5e-bridge-phase3-decisions-log-rev6.md — Decisions
  11–35. Decision 2 is in the Phase 2 log, NOT this one.
- docs/session-handoffs/5e-bridge-phase2-decisions-log.md — Phase 2, incl.
  Decision 2 (ID generation) and Decision 4 (rich-text cap, platform-wide
  per-field, L173-197). BOTH logs live.
- CLAUDE-rev6.md — Conventions 7/7a/8/9, Rule 10, execution discipline (ONE
  command per turn, NO ;/&& chaining without explicit permission).

---

## Standing disciplines still in force

- **THE DIG LAW governs.** Chat 32's dissolved-into-a-blocker dig is the fourth
  consecutive proof. A half-dug "recommended next" from a prior handoff is not
  authority — verify the seam against locked sources before building.
- Andre is dyslexic. **ONE command per WSL message**; the RUN IN WSL label; only
  the command in the code block. **NO ;/&& chaining** without explicit permission.
- **NEVER heredoc for canonical docs** (this session's heredoc for THIS handoff
  hung the shell mid-write — aborted, redone as download + cp). Canonical docs:
  download-from-chat + cp, OR anchored Python scripts run in WSL. Typechecked TS
  MAY use heredoc directly to the repo file (the work-plans.ts pair did).
- **Anchored doc edits:** verify ALL anchors (.count()==1) across ALL files
  BEFORE writing ANY (abort = system working). This session's PROJECT-MAP edit
  checked both anchors before applying either.
- Two-commit convention: code separate from doc-control.
- tsc --noEmit, never next build with the dev server up.
- Verify pushes (git log shows origin = HEAD). Fix doc drift the session you
  find it (Standing Order #1). Handoffs built on VERIFIED disk state (Rule 10).
- **db reset applied clean proves execution, not correctness.** Query the DB for
  computed output. This session's 10/10 smoke test proved the conditional CHECKs
  + 16.3 + snapshot behave correctly — tsc alone could not.
- **.env.local hazard:** NEXT_PUBLIC_SUPABASE_URL points at hosted production.
  Always run local scripts with the
  NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321 SUPABASE_SERVICE_ROLE_KEY=$SVC
  override. createAdminClient reads exactly those two var names (verified).

---

## Document-control state at Chat 32 close

Committed + pushed:
- 38bdfaa — lib/core/work-plans.ts + lib/actions/work-plans.ts.
- 64e8c22 — PROJECT-MAP (stamp + C4 built entry), ROADMAP (C4 annotated).
- <this handoff commit> — docs/session-handoffs/CHAT-32-HANDOFF.md.

**Files-panel swap at Chat 32 close (Standing Order #3):** the panel copies of
PROJECT-MAP, ROADMAP-TO-TESTABLE, and this new CHAT-32-HANDOFF must be replaced
with the Chat-32 disk versions. architecture-reference and the decisions logs
were NOT edited this session — their panel copies are unchanged. Verify each with
diff -q against the Downloads copy.

**Carried cosmetic drift (from Chat 29, STILL open — Standing Order #1, low
value):** panel entries carry -v2 suffixes while repo files are canonical-named;
the panel .txt arch-ref and .docx SOP copies are TRUNCATED FRAGMENTS. A
deliberate panel-reorganization task, better done intentionally than rushed at a
session close. Flagged so it is not lost.

**This handoff (CHAT-32-HANDOFF.md)** is produced as a chat download, cp-ed into
docs/session-handoffs/, then committed. Verify via git log.
