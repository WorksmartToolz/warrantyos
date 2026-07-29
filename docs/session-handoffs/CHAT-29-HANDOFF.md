# CHAT 29 HANDOFF — WarrantyOS Phase 3 (E1b RESOLVED + BUILT; C3 token layer done)

**Written at Chat 29 close, 2026-07-29.** (Filename is CHAT-29 because it is FOR
the next chat.) Every state claim traces to Andre's pasted terminal output.

---

## ⚖️ THE DIG LAW — STILL GOVERNS, READ FIRST (dig, dig, dig, dig)

**The only gaps now are BUILDING, not DECIDING.** Design is ~95%+ complete
(Decisions 1–35, Phase 0 Items, arch-ref). If a future chat thinks it found a
*design* gap, **DIG — do not ask.** Dig across ALL tiers before bringing ANY
question to Andre: arch-ref → BOTH decisions logs → Phase 0 update + Phase 1
audit → built migrations' CHECK constraints + column comments → repo + git
history → **the SOPs (`.docx`, read as plain text) and workbooks (`.xlsx`,
openpyxl)**.

**Chat 29 is THREE fresh proofs the dig pays off — and two proofs that a
half-dug question is worse than none.** E1b *looked* open; the dig closed it
against locked sources (Decision 35). Twice Andre stopped a question mid-draft
("dig dig dig!!!"); both times the dig DISSOLVED the question rather than
answering it:
- The invented "nulling destroys the audit trail" tradeoff — killed by arch-ref
  5809-5811 (audit trail is carried by domain timestamps, never the token).
- The invented "who-initiates-the-claim-row sequencing decision" — killed by the
  SOPs (customer submits → WMS catalogs → team evaluates; arch-ref gate-mechanics
  step 1 "token validation runs first"). There was no decision to make.

**"I need Andre to decide" is a RED FLAG meaning the dig was not deep enough.**
A half-dug question handed up as a decision is how locked architecture gets
silently overruled on Andre's authority — the named failure mode.

---

## Ground truth (verified this session via pasted terminal output)

- **HEAD:** `4398e2b`, pushed, `origin` = HEAD.
- **Branch:** `session-5e-bridge-phase3-schema-generator`, working tree clean.
- **Typecheck:** `npx tsc --noEmit` clean after every code change.
- **Migrations:** 31 on disk (UNCHANGED — all Chat 29 work was app-layer + docs).

### Session lineage (Chat 28 close → Chat 29 close)

```
b620b10  (Chat 28 handoff)
f927d35  docs  correct 34.3 storage claims (three docs)
b8ab6ff  docs  Decision 35 — E1b resolved
0aa08eb  feat  tokens.ts validate/consume per Decision 35
4398e2b  docs  graduate E1b OPEN -> RESOLVED in roadmap + PROJECT-MAP
```

Two-commit convention held: code (`0aa08eb`) separate from its doc commits.

---

## What Chat 29 did

### 1. Corrected 34.3's storage errors (three docs, `f927d35`)
Reading 027 + 022/025/026/028 bytes exposed two errors in the pinned 34.3 text:
the claims token is `intake_token` NOT `claimant_token` (that's 025's); and
there is NO `consumed_at` on ANY per-row tokenized surface. Corrected in the
decisions log (34.3 CORRECTION note, bullets 1-3), roadmap E1b, and PROJECT-MAP.
Established: SIX token columns across FIVE migrations (028 carries TWO —
`submission_token` + `customer_review_token`), all two-column
(`{name}_token` + `{name}_token_expires_at`), zero `consumed_at`.

### 2. Decision 35 — E1b RESOLVED (`b8ab6ff`)
The validate/consume factoring, pinned OPEN since 34.3, resolved at the first
consumer (C3) by reading locked sources to the floor:
- **Validate:** `{token} = ? AND {token} IS NOT NULL AND {token}_expires_at > now()`.
- **Consume:** set `{token} = NULL`, in the SAME atomic Server Action that writes
  the surface's domain result.
- **Parameterized PER TOKEN COLUMN** (028 has two), not per surface.
- **No `consumed_at` needed:** arch-ref 022 spec says "null after consumption";
  the audit trail is carried by each surface's DOMAIN state (022 `responded_at`,
  025 `signed_at`, 028 `reviewed_at`, 027 `status` off `intake_received`,
  delivery-report `trigger_status pending->confirmed`) — confirmed for all six
  surfaces against locked sources. The token was never the audit record.
- Why nulling not consumed_at: `invitations.ts` (shared store) has `consumed_at`
  and validates on it; the per-row surfaces built none, so that function cannot
  be copied — which is exactly why 34.3 was open. Naming-collapse precedent:
  committed migrations beat the design-era arch-ref "consumed_at" framing.

### 3. tokens.ts validate/consume BUILT (`0aa08eb`)
`lib/core/tokens.ts` gained `validateToken<T>(table, tokenColumn, token)` and
`consumeToken(table, tokenColumn, token)` per Decision 35. Dynamic-table follows
the committed house precedent (`lookup-defaults.ts` `.from(table)`); the update
payload uses `as never` and the table uses `as 'claims'` — the same type-assertion
workaround already in `tenant-editable-defaults.ts`. Header comments corrected
(the file previously said `claims.claimant_token` and framed validate/consume as
an OPEN fork with a phantom consumed column). Typechecked clean.

### 4. Graduated E1b OPEN -> RESOLVED (`4398e2b`)
Roadmap E1b checkbox flipped to `[x]`; PROJECT-MAP Stateless Tokenized entry
flipped to COMPLETE. Both cite Decision 35 + `0aa08eb`.

---

## C3 STATUS — token layer done, create/submit is ORDINARY BUILD (not blocked)

**C3's tokenized flow is fully understood and NOT decision-blocked.** The SOPs +
arch-ref settle the flow with no open decision:
- The customer files the claim through the tokenized intake form (SOP: "the
  customer uses the form to submit a warranty claim"). The WMS catalogs it on
  receipt; only then does the warranty team see "a new claim awaiting evaluation."
- The claim row carries `intake_token` (027, on-row, column-not-table settled).
  Gate-mechanics step 1: the token validation runs first, before the optional
  `claim_submission` Acknowledgment Gate (023 interstitial), before the form.
- 027's seven NOT NULL columns + `status='intake_received'` = the row is complete
  once intake completes; there is no draft state. This is consistent with
  customer-submission-as-completion.

**What remains for C3 (ordinary build, next chat, no Andre decision needed):**
- the create/submit Server Action(s): token-authenticated (NOT `getCallerId()` —
  the customer has no account), writing the seven hard columns + `claim_type_data`
  JSONB + supporting docs, consuming `intake_token` via `consumeToken('claims',
  'intake_token', token)` in the same atomic write.
- **Two 027-build sub-questions the arch-ref flagged as "settled at migration
  time" — READ 027 to see which way it went (a read, not a decision):**
  supporting-documents shape (JSONB vs `claim_attachments` child table) and
  O&M-provider-as-contact FK (`om_provider_contact_id`). 027 is built, so both
  are settled on disk; confirm before building the submit action.
- E1c (tokenized-link email dispatch, Resend) still not started — pairs with the
  create action.

---

## Buildable-now map (unchanged from Chat 28 except E1b)

- **E1b** — ✅ RESOLVED + BUILT this session.
- **C3 create/submit** — buildable, ordinary work (token layer + flow both settled).
  Carries E1c (email) for the outbound link.
- **C4-create** — buildable, independent (mirrors C0, two conditional-CHECK
  wrinkles on `execution_path`). C4-status/edit BLOCKED (gates on C5/C8).
- **B-layer** — its own full-session arc (clock/cron; owns C10's two system
  transitions + all `clock_events` firing). Do NOT start as a back-half item.
- **C5 (work auth)** — now unblocked on the token layer; still carries C12
  (Acknowledgment Gate mechanics) + email. `consumeToken('work_authorization_
  documents', 'customer_token', token)`.
- **C8 (service report)** — token layer ready; TWO tokens (`submission_token`,
  `customer_review_token`), each its own consumeToken call.

---

## RECOMMENDED NEXT (Andre decides; sequencing is his)

1. **C3 create/submit** — the token layer's first real consumer; proves E1b end
   to end. Carries E1c (email dispatch).
2. **C4-create** — independent, finishable, no token coupling.
3. **B-layer** — dedicated full session.

---

## Canonical docs (read PROJECT-MAP.md FIRST, then ROADMAP)

- `PROJECT-MAP.md` — Stateless Tokenized entry now COMPLETE; stamp will move to
  `4398e2b` at panel swap.
- `docs/ROADMAP-TO-TESTABLE.md` — E1b `[x]` RESOLVED.
- `docs/architecture-reference.md` — Stateless Tokenized 232-330; claim intake
  data model 3248+; stateless intake link 3680+; gate mechanics (token validation
  first); audit-trail-by-domain-state 5809-5811.
- `docs/session-handoffs/5e-bridge-phase3-decisions-log-rev6.md` — Decisions
  11-35 (35 = E1b resolved). **`.md`, not `.txt`.**
- `docs/session-handoffs/5e-bridge-phase2-decisions-log.md` — Phase 2. BOTH live.
- `CLAUDE-rev6.md` — Conventions 7/7a/8/9, Rule 10.

---

## Standing disciplines still in force

- **THE DIG LAW governs. A half-dug question handed up as a decision is the
  failure mode — dig until the question resolves OR every corner is checked.**
- Andre is dyslexic. **ONE command per WSL message**; `▶ RUN IN WSL` labels; only
  the command in the code block.
- **Anchored doc edits:** verify ALL anchors before writing ANY (an abort is the
  system working). For MULTI-FILE edits, verify every anchor across every file
  BEFORE writing the first (Chat 29 hardened the graduation script this way).
  Prefer single-line or fully-replaced anchors so a re-run aborts clean.
- **Canonical docs:** download-from-chat + `cp`, OR anchored Python scripts.
  NEVER terminal heredoc-with-backticks for docs. Type-checked TS MAY be
  heredoc'd (or downloaded); `tokens.ts` this session was download + `cp`.
- Two-commit convention: code separate from doc-control.
- `tsc --noEmit`, never `next build` with the dev server up.
- Verify pushes. Fix doc drift the session you find it (Standing Order #1).
- Handoffs + doc edits built on VERIFIED disk state (Rule 10), never memory.

---

## Document-control state at Chat 29 close

Committed + pushed (`4398e2b`):
- `5e-bridge-phase3-decisions-log-rev6.md` — 34.3 CORRECTION (3 bullets) +
  Decision 35 appended.
- `ROADMAP-TO-TESTABLE.md` — 34.3 correction + E1b graduated to `[x]`.
- `PROJECT-MAP.md` — 34.3 correction + Stateless Tokenized entry COMPLETE.

**Files-panel swap at Chat 29 close:** the panel copies of the decisions log,
roadmap, and PROJECT-MAP must be replaced with the Chat-29 disk versions. (This
handoff records that the swap is the final close-out action; if a future chat
finds the panel behind disk, re-swap and verify with `diff -q`.)

**PROJECT-MAP stamp:** currently reads `f523cf0`/Chat-28-era in its stamp line;
should move to `4398e2b`. NOT done this session (ran to close-out) — first doc
drift for the next chat to fix under Standing Order #1.

**This handoff (CHAT-29-HANDOFF.md)** was produced as a chat download and `cp`-ed
into `docs/session-handoffs/`, then committed. Verify via `git log`.
