# CHAT 30 HANDOFF — WarrantyOS Phase 3 (doc-drift swept + C3 intake CORE built)

**Written at Chat 30 close, 2026-07-29.** (Filename is CHAT-30 because it is FOR
the next chat.) Every state claim traces to Andre's pasted terminal output.

---

## ⚖️ THE DIG LAW — STILL GOVERNS, READ FIRST (dig, dig, dig, dig)

**The only gaps now are BUILDING, not DECIDING.** Design is ~95%+ complete
(Decisions 1–35, Phase 0 Items, arch-ref). If a future chat thinks it found a
*design* gap, **DIG — do not ask.** Dig across ALL tiers before bringing ANY
question to Andre: arch-ref → BOTH decisions logs → Phase 0 update + Phase 1
audit → built migrations' CHECK constraints + column comments → repo + git
history → the SOPs and workbooks.

**Chat 30 is a fresh proof the dig pays off — TWICE, on the same feature.**
C3 (claim intake) *looked* blocked on an open "where does the intake token live"
seam. Two half-dug questions were handed toward Andre and both DISSOLVED under
the dig instead of needing a decision:

- **"Is C3 create an INSERT or an UPDATE-a-placeholder?"** — dissolved by
  Decision 27.4 + 027's header: the customer files the claim, the row is BORN at
  submission in `intake_received`, no draft state. **C3 = INSERT.** Not open.
- **"Does C3 need a staff/account manual-entry auth path?"** — INVENTED, then
  killed by arch-ref gate mechanics (5529): claim intake is EXCLUSIVELY
  customer-tokenized ("Customer clicks a tokenized link… token validation runs
  first"). There is NO staff manual-entry path in the locked design. Proposing
  one was improvising architecture. **Do not add a staff intake path.**

**"I need Andre to decide" was raised twice this session and was WRONG both
times.** It is a RED FLAG that the dig was not deep enough, exactly as the law
says. The correct move both times was to keep digging until the question
dissolved against locked sources.

---

## Ground truth (verified this session via pasted terminal output)

- **HEAD:** `93bf82c`, pushed, `origin` = HEAD.
- **Branch:** `session-5e-bridge-phase3-schema-generator`, working tree clean.
- **Typecheck:** `npx tsc --noEmit` clean after the C3 core landed.
- **Migrations:** 31 on disk (UNCHANGED — all Chat 30 work was app-layer + docs).

### Session lineage (Chat 29 close → Chat 30 close)

```
24cef98  (Chat 29 handoff — panel-drift note)
aa0d331  docs  Chat 30 drift sweep (arch-ref + PROJECT-MAP + roadmap)
93bf82c  feat  C3 claim-intake CORE (lib/core/claims.ts)
```

Two-commit convention held: the doc sweep (`aa0d331`) is separate from the
code commit (`93bf82c`).

---

## What Chat 30 did

### 1. Doc-control drift sweep (`aa0d331`)
A full-session dig found the canonical docs were telling a future chat that
BUILT work was unbuilt. All fixed, all verified against disk:

- **architecture-reference.md** — three Convention-9 (retroactive 7a) Status
  corrections, ALL LINE-NEUTRAL (file stayed 7344 lines, so the ~15 incoming
  line-number citations did NOT shift):
  - Feature Flag System (L399-400): `Designed / not yet built` → `Implemented
    (schema)`, built as D2 (`0bf3713`); storage resolved to JSONB by Decision
    33.2, `tenant_features` table held open (NOT foreclosed — verified against
    33.2's own text; the L415 design-fork prose was left FROZEN per Convention 7).
  - Database Migration Tooling (L1291): the Phase-4 stop-point gate is described
    as cleared (baseline DONE).
  - Tenant-Editable Defaults (L6894/6905/6907): `Partially implemented` →
    `Implemented (schema)`; the section's own self-fired trigger ("Step 5 remains
    unbuilt… until it lands") resolved — step 5 IS built (`d127cc3`), consumed by
    `2c76cf0` + `15a6779`.
- **PROJECT-MAP.md** — stamp → Chat 30 / `24cef98`→`93bf82c` era; `31→35`
  decisions; `27→31` migrations (030 was MISSING from the enumeration + its
  descriptive parenthetical, now added as the claim-lifecycle status enum);
  `twenty-six→twenty-nine` tables; `Decisions 11–28→11–35`.
- **ROADMAP-TO-TESTABLE.md** — C10 struck (`[x]`, Done Chat 27 `85f7f1b`,
  append per the C2 house pattern); DESIGN-GAP header marked RESOLVED; LAYER-E
  "zero coded / never scoped" corrected; recommended-next block given a
  supersession note (all three items — C1/A1-A5/D1 — are complete).

**NOT touched, dug and ruled non-drift** (a chat re-examining these should NOT
"fix" them — they are correct or frozen):
- arch-ref Stateless Tokenized section (232+): conceptual pattern, no table of
  its own, no Convention-9 obligation. `consumed_at` at L264 describes the TRUE
  invitation precedent, not the per-row surfaces.
- arch-ref L415 storage-fork prose: Decision 33.2 held `tenant_features` open,
  section "written to hold either way" — still-accurate design prose, frozen.
- arch-ref L3292 / L6320: correct forward-pointers to separate sections, NOT
  stale "unbuilt" claims. (Both nearly got "fixed" into falsehood — do not.)

### 2. C3 claim-intake CORE built (`93bf82c`) — `lib/core/claims.ts`
`createClaimIntake(input, tenantId)`, the domain write function for the customer
claim-intake surface. Every rule traced to disk-read locked sources:

- **Full 27-column write** per migration 027 (read column-by-column, not from
  memory). Seven NOT NULL hard columns; three CHECK-enum validations
  (`claim_type` 7 values, `equipment_status` 2, `loto_requirement` 3).
- **Three rich-text cap checks** (`detailed_description`, `emergency_details`,
  `offline_condition_explanation`) against `tenants.settings.rich_text_max_chars`
  (Decision 4: default 10000, ceiling 50000). The scalar-settings reader mirrors
  `escalationVerdictAuthorizedRole` (claim-progression.ts) — the house idiom.
- **Conditional couplings app-layer** (17.A.6, no DB CHECK): `emergency_details`
  + `emergency_stabilized_at` required when `is_emergency`;
  `offline_condition_explanation` required when `equipment_status = 'offline'`.
- **claim_type_data: ONLY `replacement_parts` validated** (the one settled shape);
  the other six pass through opaque, exactly like `clock_events.payload`. Do NOT
  invent the six — that is the named restraint.
- **Submitter FK + Snapshot** (Decision 20.4): name/email ALWAYS written as
  snapshot; `submitter_contact_id` optional (null for one-off third party),
  tenant-validated when present. O&M-provider capture is DIRECT TEXT four columns
  (022 parallel), NOT an FK (Decision 20; 027 header confirms against the
  arch-ref open-questions proposal).
- **Eligibility** `warranty_id IS NOT NULL` (Decision 27.4), checked via the
  parent registration.
- **Cross-tenant guard** via the parent `warranty_registration` (arch-ref
  168-177) — the token-authed customer has no `users` row, so tenant is anchored
  to the registration, NOT a caller profile.
- **Token-agnostic by design.** validate/consume live in the ACTION layer
  (Decision 35). `intake_token` is NOT written or consumed in the core — it is
  the issuance subsystem's to mint and the action's to consume. This is a
  FINISHED EDGE facing the unbuilt issuance subsystem, not deferred work.
- Reference shape mirrors `inspections.ts` (discriminated-union return,
  service-role insert, `as never` casts matching the `tenant-editable-defaults.ts`
  house precedent). `tsc --noEmit` clean.

---

## ⚠️ C3 CORE — RUNTIME SMOKE TEST PENDING (tracked, not silent)

**The core is TYPECHECKED, not runtime-proven.** Per the standing verification
discipline ("`tsc` proves compilation, not correctness; for computed output,
query the DB"), the `as never` casts specifically bypass column-name checking,
so a wrong column name could type-check yet fail at insert time. **First action
next chat, BEFORE building the C3 action:**

1. `supabase db reset` (creates zero tenants), then insert a scratch tenant +
   an eligible `warranty_registration` (`warranty_id` NON-NULL — eligibility 27.4).
2. Call `createClaimIntake` with a minimal valid input (a non-emergency,
   `equipment_status='online'` claim needs only the 7 hard columns +
   `warranty_registration_id`).
3. Query the row back via `docker exec supabase_db_warrantyos psql …` — confirm
   all columns landed, `status='intake_received'`, `claim_id` generated.
4. Then a rejection case (bad enum, missing conditional) returns the structured
   error, not a raw PG throw.

This setup is SHARED with the action build (the action needs the same seeded
eligible registration), so it is not wasted work — it is the action's test
fixture.

---

## NEXT UNIT — C3 ACTION (append to EXISTING lib/actions/claims.ts)

**`lib/actions/claims.ts` ALREADY EXISTS** (C10, `85f7f1b`, 1763 bytes). It
imports `revalidatePath` + `createClient` from `@/lib/supabase/server` (the
SESSION client) and exports `progressClaim` (account-authed) + a non-exported
B-layer system function. **The C3 create action is a NEW EXPORT APPENDED to this
file — NOT a new file, NOT an overwrite.**

Critical divergence: `progressClaim` is ACCOUNT-authed (session client). The C3
create action is TOKEN-authed (the customer has no account/session). It must NOT
inherit the session-auth pattern. Its shape follows arch-ref gate mechanics 5529
verbatim:

1. `validateToken('claims', 'intake_token', token)` (admin client, tokens.ts) —
   returns the row or null. **BUT NOTE:** for CREATE, the token authorizes making
   a NEW row; `intake_token` living on the claim row is for the *post-creation*
   customer re-entry/correction loop (27.6 "Correction Required"), NOT the create
   authorization. The create-entry token is minted by the ISSUANCE SUBSYSTEM
   (unbuilt) against an eligible registration. **This is the one seam to confirm
   at build time** — read whether the create link carries the registration's
   token or the claim's. Precedent (022/025/026: token on the acted-upon row)
   plus 027's on-row `intake_token` suggests the correction loop; the create
   entry is likely gated upstream. DIG the issuance flow (C11-era) before wiring
   create-consume — do not assume.
2. Gate check (023): does the tenant have a `claim_submission` gate template? If
   so, has an `acknowledgment_gate_records` row for this entity been recorded?
   (arch-ref 5529 steps 2-3.)
3. Resolve `tenantId` from the validated registration; call `createClaimIntake`.
4. `revalidatePath` the claim list target.

**Because the create-entry issuance is unbuilt, the honest v1 action may be
testable only with a manually-seeded token.** That is a testing seam, not a
design gap. If the create-vs-correction token question does not resolve cleanly
against locked sources, STOP and flag it — do not invent the issuance contract.

Also pairs with **E1c** (Resend tokenized-link dispatch) — still not started.

---

## Buildable-now map (unchanged from Chat 29 except C3 core)

- **C3 core** — ✅ BUILT this session (smoke test pending). Action is next.
- **C3 action** — buildable as an append; confirm the create-token seam first.
- **C4-create** — buildable, independent, no token coupling (mirrors C0, two
  conditional-CHECK wrinkles on `execution_path`). C4-status/edit BLOCKED (C5/C8).
- **B-layer** — its own full-session arc (clock/cron; owns C10's two system
  transitions + all `clock_events` firing). Do NOT start as a back-half item.
- **C5 (work auth)** — token layer ready; carries C12 (Ack Gate mechanics) + email.
- **C8 (service report)** — token layer ready; TWO tokens, each its own consume.

---

## RECOMMENDED NEXT (Andre decides; sequencing is his)

1. **C3 core smoke test → C3 action** — finish the intake surface end to end.
   Confirm the create-token seam against the issuance flow first.
2. **C4-create** — independent, finishable, no token coupling.
3. **B-layer** — dedicated full session.

---

## Canonical docs (read PROJECT-MAP.md FIRST, then ROADMAP)

- `PROJECT-MAP.md` — stamp era Chat 30; counts corrected (35 decisions, 31
  migrations, 29 tables). Stateless Tokenized COMPLETE.
- `docs/ROADMAP-TO-TESTABLE.md` — C10 struck; C3 still `[ ]` (core built, not
  the whole item); DESIGN-GAP resolved.
- `docs/architecture-reference.md` — 7344 lines. Feature-flags / migration-tooling
  / tenant-editable-defaults Status lines now correct. Claim intake data model
  3475+; gate mechanics (token validation first) 5529; eligibility 27.4.
- `docs/session-handoffs/5e-bridge-phase3-decisions-log-rev6.md` — Decisions
  11-35. `.md`, not `.txt`.
- `docs/session-handoffs/5e-bridge-phase2-decisions-log.md` — Phase 2. BOTH live.
- `CLAUDE-rev6.md` — Conventions 7/7a/8/9, Rule 10.

---

## Standing disciplines still in force

- **THE DIG LAW governs. A half-dug question handed up as a decision is the
  failure mode — dig until the question resolves OR every corner is checked.**
  (Chat 30 raised two such questions; both dissolved on digging.)
- Andre is dyslexic. **ONE command per WSL message**; `▶ RUN IN WSL` labels; only
  the command in the code block.
- **Anchored doc edits:** verify ALL anchors across ALL files BEFORE writing ANY
  (Chat 30 held this across 3 files in one script). Prove uniqueness with
  `grep -Fc -e` (the `-F` matters — `**`/`-`/em-dash break bare grep). LINE-NEUTRAL
  arch-ref edits (phrase-swap, no insert) avoid the Convention-8 citation reshift.
- **Canonical docs:** download-from-chat + `cp`, OR anchored Python scripts.
  NEVER terminal heredoc-with-backticks for docs. Typechecked TS: download + `cp`
  (this session's `claims.ts` was download + `cp`).
- Two-commit convention: code separate from doc-control.
- `tsc --noEmit`, never `next build` with the dev server up.
- Verify pushes. Fix doc drift the session you find it (Standing Order #1).
- Handoffs + doc edits built on VERIFIED disk state (Rule 10), never memory.

---

## Document-control state at Chat 30 close

Committed + pushed:
- `aa0d331` — arch-ref (3 Status), PROJECT-MAP (counts+stamp+030), roadmap (C10 +
  DESIGN-GAP + LAYER-E + rec-next).
- `93bf82c` — `lib/core/claims.ts` (C3 core).

**Files-panel swap at Chat 30 close (Standing Order #3):** the panel copies of
PROJECT-MAP, ROADMAP, architecture-reference, the rev6 decisions log, AND this
new CHAT-30-HANDOFF must be replaced with the Chat-30 disk versions. Verify each
with `diff -q` against the Downloads copy. If a future chat finds the panel behind
disk, re-swap and verify.

**Carried cosmetic drift (from Chat 29, still open — Standing Order #1, low
value):** panel entries carry `-v2` suffixes while repo files are canonical-named;
the panel `.txt` arch-ref and `.docx` SOP copies are TRUNCATED FRAGMENTS (the
`.txt` arch-ref is 248 lines vs disk's 7344; the `.docx` files are not valid zip
archives) — a reader trusting the panel `.txt`/`.docx` gets a fraction of the real
content. This is a deliberate panel-reorganization task, better done intentionally
than rushed at a session close. Flagged here so it is not lost.

**This handoff (CHAT-30-HANDOFF.md)** is produced as a chat download and `cp`-ed
into `docs/session-handoffs/`, then committed. Verify via `git log`.
