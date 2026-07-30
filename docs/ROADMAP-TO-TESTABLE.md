# WarrantyOS — Roadmap to a Testable Product

**Carry this file forward into every chat.** As tasks complete, strike them
through (`~~task~~`) and note the chat + commit. When every item is struck, you
have a testable end-to-end product.

---

## ⚖️ GOVERNING LAW — read before acting on ANY task below

**This roadmap is a map of steps and a pointer to what to look for in the locked
decisions. It is NOT a license to invent.** Every task names a locked source for
exactly this reason: the answer is already decided far more often than it looks.

**THE LOCKED DECISION RULE (in force, non-negotiable):**

1. **Already-locked decisions win.** The design phase is essentially complete.
   ~95%+ of decisions are locked across the architecture reference, the Phase 2
   and Phase 3 decisions logs, the Phase 0 items, and the Phase 1 audit. The job
   is to BUILD ACCORDINGLY, not to relitigate.

2. **Before executing any task, dig first.** Read the locked source the task
   names, AND the decisions it depends on, AND the nearest comparable already-built
   artifact's real bytes on disk. Pattern-memory is unreliable; verify against the
   actual locked text and the actual committed code.

3. **"I need Andre to decide this" is a RED FLAG, not a valid state.** If the bot
   reaches for a decision from Andre, that is the primary indicator the bot did
   **not dig deep enough** into the already-locked decisions. The correct response
   is to STOP and GO BACK and dig deeper — re-read the architecture reference, both
   decisions logs, the Phase 0 items, and the audit. The answer is almost always
   already there under a name or in a section the bot hasn't checked yet.

4. **Only after a genuine deep dig turns up nothing** — no locked decision, no
   committed precedent, no governing convention anywhere in the sources — may the
   bot bring the question to Andre. Even then it arrives as a grounded, minimal
   question with the dig shown ("I searched X, Y, Z; here is the gap"), never as a
   menu of options that manufactures consent to improvise.

5. **A wrongly-assumed "open question" is how locked architecture gets silently
   overruled.** Manufacturing a decision point where a locked answer exists lets
   improvisation ride in on Andre's authority. This is the named failure mode.
   Guard against it on every task.

**Corollaries already in force (from CLAUDE-rev6 / standing orders):**
- Never take the simplest route because it's easy — take the option that best
  supports the locked decision without altering it.
- The arch-ref's design-era sketches and "outstanding question" blocks PROPOSE;
  committed migration headers and decisions-log entries DECIDE. When they
  disagree, the committed/locked source wins (the naming-collapse and
  open-questions traps).
- `db reset` / `tsc` clean proves execution, not correctness — verify the built
  thing does what the locked decision says.
- The architecture is Andre's; the docs are the bot's to maintain. When Andre
  pushes back on a technical call, he is usually seeing a locked axis the bot
  missed — dig, don't defend.

**Design gaps are the ONE exception.** A task explicitly marked as a DESIGN GAP
(see D1) is genuinely undrafted — locked design does not exist for it. Those, and
only those, are resolved the design way (propose against SOPs/workbooks, ratify,
log a decision). Everything else is a BUILD task with a locked answer to find.

**Starting point (verified from disk, Chat 23, HEAD `52dcf1b`):**
Working software = foundation only: auth, signup, tenant provisioning, platform
admin, tenant admin, team management. Operational core = 29 tables + view +
functions (schema only) plus exactly ONE operational Server Action
(`inspections` action+core, built Chat 23). Everything below is what stands
between here and a clickable warranty workflow.

**How to read the ordering:** grouped by dependency layer. Later layers lean on
earlier ones. Within a layer, order is a recommendation, not a hard constraint —
sequencing is Andre's call. Each task names its locked source so a future chat
digs before building.

---

## ✅ DESIGN GAP (RESOLVED) — D1 closed Chat 25/26 (Decision 30, migration 030); C10 built Chat 27 (`85f7f1b`, Decision 31)

- [x] ~~**D1. Draft the Tier 3 Claim Lifecycle (Six Gates) design.**~~ **Done Chat 25 (design + ratification), committed Chat 26 (`0b27f70` migration 030, `a7658b3` Decision 30 log).** The twelve-value claim `status` enum is locked — six gate stages + five outcomes; transitions/actors live in C10 Server Actions (Decision 30.3). Original framing preserved below as history. This was a
  DESIGN task, not a build task — it is NOT yet locked. The claim `status` value
  set (Gate 1–Gate 6 + outcome states), the transitions between them, the actor
  authorized for each transition, and each transition's effects are all
  explicitly deferred to "a later v2 section that depends on the workbooks"
  (arch-ref 3250-3251, 3358-3399). The claim shell (016) admits only
  `intake_received`; intake (027) and eligibility (Decision 27) ARE done. Until
  the gate machine is designed, a claim can be *filed* but cannot *progress*, so
  no full accept/deny lifecycle can be tested. **Resolve this the design way**
  (propose against the 7 SOPs + 6 workbooks, ratify, log a decision) before
  building the claim-progression Server Actions in C-layer below.
  *Source: arch-ref 3250-3410; the 3 lifecycle SOPs; the 6 claim workbooks.*

---

## LAYER A — Provisioning completeness (unblocks every new tenant having usable data)

Without these, a freshly provisioned tenant is missing the seed rows the
operational tables require, so operational features fail on a new tenant.

- [x] ~~**A1. Seed `tenant_id_sequences` at provisioning.**~~ **Done Chat 24, `ac90fa2`.** Two rows: `warranty_id` (WID-{year}-{seq:06d}) + `claim_id` (CLM-{year}-{seq:07d}), current_value 0. *Source: arch-ref ID Generation; 009.*
- [x] ~~**A2. Seed the two `warranty_types` anchor rows.**~~ **Done Chat 24, `ac90fa2`.** Standard + Workmanship, is_system. Seeded LAST (see Findings). *Source: arch-ref 2945; Decision 6.*
- [x] ~~**A3. Seed the tenant-editable-defaults rows** (4 inspection_types, 8 inspection_triggers).~~ **Done Chat 24, `ac90fa2`,** all platform_locked. *Source: Decision 17.B.*
- [x] ~~**A4. Seed `tenant_holidays`.**~~ **Done Chat 24, `ac90fa2`.** `federal_holidays_for_year` over the locked 2026-2036 horizon (mirrors 024 backfill), 121 rows. *Source: arch-ref 4275; Decision 25.3.*
- [x] ~~**A5. Seed provisioning defaults.**~~ **Partially done Chat 24, `ac90fa2`.** The 6 `tenants.settings` scalar keys (ala_signature_method, ala_decline_warning_text, ala_decline_recant_window_days, ala_markup_percent, ala_response_overdue_business_days, service_report_response_days) ARE seeded. The 3 feature flags (epc_workflow, supply_only_workflow, service_report_acquiesce_window) were deferred to **D2** and are now seeded there (Chat 28, `0bf3713`) — flag storage + the is_feature_enabled reader were built in the same task. *Source: Decisions 7/19/21/25; flags arch-ref 454-481.*

**Findings from the A1-A5 build (Chat 24) — do not rediscover these:**
1. **`.env.local` points `NEXT_PUBLIC_SUPABASE_URL` at HOSTED PRODUCTION** (`uzjivnmwedfzcgqnnhos`). Running `provision-tenant.mjs` with no override hits PROD. For local verification, prefix: `NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321 SUPABASE_SERVICE_ROLE_KEY=<local secret from supabase status> npx tsx scripts/...`. A Chat 24 test hit prod before this was caught (rollback cleaned it up). Never run provisioning/seed tests without the local override.
2. **The Decision 6 trigger makes `warranty_types.is_system` rows un-deletable through the app path** — so the provisioning compensating-rollback CANNOT delete them. warranty_types is therefore seeded LAST; any earlier-step failure rolls back cleanly. Any future seed added after warranty_types would re-break rollback. For manual scratch teardown, `set session_replication_role = replica;` bypasses the trigger (superuser only).
3. **After `supabase db reset`, PostgREST serves a stale schema cache** ("Could not find the table ... in the schema cache" on the NEW tables). Fix: `docker restart supabase_rest_warrantyos` before REST-based verification.

---

## LAYER B — Clock infrastructure (the System-Managed Clock; large, load-bearing)

Nothing ages, expires, or auto-progresses until this exists. Many C-layer
actions must write clock rows in-transaction, so B and C interleave — but the
cron handler + pg_cron must exist before any deadline actually fires.

- [ ] **B1. Enable pg_cron via migration** and schedule the hourly job
  (`'0 * * * *'`), defined in a version-controlled migration.
  *Source: arch-ref 859-875.*
- [ ] **B2. Build the cron handler function** — queries the pending
  `fires_at` partial index each hour, dispatches each due event to its
  per-type dispatcher, flips status to `fired`/`failed`.
  *Source: arch-ref 981-1012.*
- [ ] **B3. Write the nine dispatcher functions**, one per event_type:
  `registration_prep_pre_trigger`, `info_request_due`,
  `warranty_expiry_warning`, `trigger_confirmation_overdue`,
  `service_report_response_due` (mutates: sets acquiescence-acceptance +
  initiates closure), `work_authorization_response_overdue` (reminder-only),
  `ala_decline_window_expired` (marks decline terminal, unblocks denial),
  `ala_response_overdue` (sets `overdue_flagged_at`, reminder-only),
  `warranty_id_early_issuance` (issues warranty_id or no-ops).
  *Source: arch-ref 924-960 (per-type semantics).*
- [ ] **B4. Build the failed-event admin surface** — platform-admin page listing
  `failed` events with `failure_reason` + a manual retry button (no auto-retry).
  *Source: arch-ref 1001-1007.*
- [ ] **B5. Build the rolling annual holiday top-up job** (pg_cron, calls
  `federal_holidays_for_year` to extend every tenant's horizon forward).
  *Source: arch-ref 024 header note; depends on B1.*

---

## LAYER C — Operational Server Actions (action + core, mirroring `manage-team`)

The heart of the product. Each is a `lib/actions/*` (thin) → `lib/core/*`
(domain) pair, service-role writes, structured return, revalidate-on-success,
tenant-match + cross-tenant guards, clock-event sync in-transaction where the
entity has scheduled events. **`inspections` (Chat 23) is the reference shape.**
Each needs a scoping pass before build.

- [x] ~~**C0. Inspection write-path** (create).~~ **Done Chat 23, `2c76cf0`.**
- [x] ~~**C1. Tenant-editable-defaults lookup admin CRUD**~~ — create/rename/disable/
  soft-delete rows in `inspection_types` / `inspection_triggers`, each gated by
  `lock_tier` (platform_locked immutable, platform_seeded limited, tenant_added
  full), plus label→value slugification for tenant_added. Finishes the
  Tenant-Editable Defaults pattern (flips it off PARTIAL). *Most-locked next
  build. Source: Decision 17.A.4/17.A.5/17.A.7.* **Done Chat 23, `15a6779`.**
- [x] ~~**C2. Inspection edit/status-transition actions** — the `open →
  in_progress → under_review → issued` machine on the built table.~~
  **Done Chat 28, `0f7bfa9` (code), `2cfcfb0` (Decision 32 + PROJECT-MAP).**
  Forward-only four-state machine, single `operational` authz class, no system
  path (021 flags inspection clock_events open). *Source: 021; arch-ref inspections section.*
- [ ] **C3. Claim intake write-path** — the customer-facing tokenized intake
  form's Server Action (creates the claim from a tokenized submission).
  **CORE built + runtime-proven, Chat 31 (`5e2b90e`):** `lib/core/claims.ts`
  `createClaimIntake` + migration 031 `create_claim_with_generated_id` (atomic
  gap-free ClaimID, the ID Generation system's FIRST consumer — CLM-2026-0000001/2
  verified, gap-free-on-rollback verified, monotonic increment verified).
  **REMAINING: the token-authed action** (append to `lib/actions/claims.ts`;
  confirm the create-vs-correction token seam against the unbuilt issuance
  subsystem first — do not assume). Checkbox stays open until the action lands.
  *Depends on E1 (token infra). Source: 027; arch-ref Claim Intake + ID Generation.*
- [ ] **C4. Work Plan actions** (create/edit/status) — the warrantor INTENT
  entity, 5 CHECKs, conditional path fields.
  **CREATE built + runtime-proven, Chat 32 (`38bdfaa`):** `lib/core/work-plans.ts`
  `insertWorkPlan` + `lib/actions/work-plans.ts` `createWorkPlan`. Mirrors the C0
  inspections write-path (reviewer||team_admin authz, cross-tenant guard,
  service-role insert). Both conditional path couplings (13.1) reject-verified,
  Parts Claims exclusion (16.3) verified, subcontractor FK+Snapshot verified —
  10/10 smoke cases. **REMAINING: edit + status machine** (Decision 15.1's
  five-state `draft → sent_for_authorization → authorized → completed/cancelled`).
  Checkbox stays open until edit/status lands. *Source: 020; Decisions 13/15/16.*
- [ ] **C5. Customer Work Authorization actions** — generate document from Work
  Plan, tokenized customer approval (typed-name + acknowledgment signature),
  revise-and-resend; writes `work_authorization_response_overdue` clock row.
  Universal blocking-gate enforcement lives here. *Source: 022; Decision 11.*
- [ ] **C6. Notice of Defect actions** — issue notice, tokenized recipient
  response capture; writes `notice_of_defect_response_overdue` clock row.
  *Source: 026; Decision 14.*
- [ ] **C7. ALA actions** — generate at Indistinct outcome, tokenized
  Accept/Decline with atomic accept-and-signature write, decline recant window,
  re-issue; writes `ala_response_overdue` + `ala_decline_window_expired` clock
  rows. *Source: 025; Decisions 19/25/26.*
- [ ] **C8. Service Report actions** — subcontractor tokenized submission,
  warranty-professional accept/return, customer tokenized review (accept/
  dispute/silence-acceptance); writes `service_report_response_due` clock row.
  *Source: 028; Decision 21.*
- [ ] **C9. Customer-O&M Authorization actions** — per-event agent authorization,
  tokenized customer signature, status machine (unsigned/signed/closed/stale).
  *Source: 029; Decision 28.*
- [x] ~~**C10. Claim lifecycle / gate-progression actions** — the Six Gates
  transitions, accept/deny/escalate.~~ **Done Chat 27, `85f7f1b`** (core +
  `lib/actions/claims.ts`). Six Gates transition map + authorized actors in the
  Server Action layer per Decision 30.3; escalation-verdict tenant setting; system
  entry point for the two clock-driven transitions the B-layer will fire. UI (F1)
  remains. *Source: Decision 30/31; migration 030.*
- [ ] **C11. Warranty Registration + trigger actions** — assignee submission,
  the multi-source trigger model (EPC / supply-only / delivery-report),
  warranty_id issuance; writes `registration_prep_pre_trigger` /
  `trigger_confirmation_overdue` / `warranty_id_early_issuance` clock rows.
  *Source: 010; Decisions 5/23/27; Item 17.*
- [ ] **C12. Acknowledgment Gate mechanics (12.7)** — the Server Action that
  renders or skips a configured gate and records the acknowledgment on submit.
  Interstitial on existing tokenized links. *Source: 023; Decision 12.*
- [ ] **C13. Feature-flag admin actions** — platform-admin-gated flag config
  (`is_feature_enabled` reader already the pattern; Team Admins cannot set).
  *Source: arch-ref 393-513.*

---

## LAYER D — Feature Flag System (thin but gates C-layer behavior)

- [x] ~~**D2. Build `is_feature_enabled(tenant, feature)` reader** + storage, AND seed the 3 provisioning feature-flag defaults (epc_workflow, supply_only_workflow, service_report_acquiesce_window) deferred from A5, if
  not already present. Server Actions call it before workflow branches; nothing
  reads flag storage directly.~~ **Done Chat 28, `0bf3713` (code), `2b762a5`
  (Decision 33 + PROJECT-MAP).** Storage is JSONB `tenants.settings.enabled_features`
  (arch-ref part-1 fork exercised as the lighter start, table upgrade held open
  behind the reader); all 3 flags seeded ENABLED at provisioning; fails closed.
  *Source: arch-ref 393-429.*

---

## LAYER E — Stateless Tokenized Interaction infrastructure (six surfaces)

The customer-facing half. Applied in schema across the entities; primitives + validate/consume coded (E1, Decisions 34/35).
Needs its own scoping pass (never scoped). The six surfaces: claim intake,
registration-assignee submission, supply-only delivery reporting, service-report
customer review, work authorization, ALA signing.

- [~] **E1. Token infrastructure** — generation (high-entropy, single-purpose),
  expiry, single-use consumption, the tokenized-link email dispatch. Team-invite
  tokens are the *implemented precedent* to mirror. *Source: arch-ref 228-330.*
  **PARTIAL — pure primitives done Chat 28, `2fd67f9` (Decision 34):**
  ~~generation + expiry~~ built as `generateToken` / `tokenExpiresAt(ttlDays)` in
  `lib/core/tokens.ts` (table-agnostic; `invitations.ts` NOT rewired — shared shape,
  not shared store). Two sub-tasks remain, both unbuilt:
  - [x] **E1b. Validate + consume helper** — RESOLVED + BUILT (Decision 35, `0aa08eb`).
    RESOLVED at the first consumer (C3), Decision 35: the dig reconciled every
    locked source — mechanism is validate-non-null-unexpired + consume-by-nulling,
    no consumed column needed (022 arch-ref "null after consumption"; audit trail
    carried by domain state). Built in `lib/core/tokens.ts` (`0aa08eb`) as
    `validateToken(table, tokenColumn, token)` + `consumeToken(...)`, dynamic-table
    per the lookup-defaults precedent, typechecked. Must be parameterized
    by each token's real columns — a TWO-column shape (`{name}_token` +
    `{name}_token_expires_at`), NO consumed column anywhere (six token columns
    across 022/025/026/027/028, zero `consumed_at`; see Decision 34.3
    CORRECTION). Parameterize PER TOKEN, not per surface: 028 carries TWO
    (`submission_token` + `customer_review_token`), so a one-token-per-consumer
    signature is already wrong. First consumers: `intake_token` (C3/027),
    `customer_token` (C5/022), and C8/028's pair. Single-use enforcement without
    a consumed column is E1b's real open question. **TRIGGER:
    resolve against the FIRST tokenized consumer built (C3/C5/C8), NOT in the
    abstract.** Do not build speculatively — that is the named seam-with-no-
    subsystem anti-pattern. *Source: arch-ref 254-266; Decision 34.3.*
  - [ ] **E1c. Tokenized-link email dispatch** — the Resend send of the focused
    link. Not started. Pairs with each surface's create action. *Source: arch-ref
    254; Resend account already provisioned.*
- [ ] **E2. The six tokenized public interfaces** (no-auth routes rendering the
  focused form for each surface, calling the matching C-layer action). Each pairs
  with its C-layer entry above. *Source: arch-ref 270-320.*

---

## LAYER F — Operational UIs (the clickable product)

None exist. The `/app` shell + shadcn primitives exist; every operational screen
is unbuilt. The revalidate paths written in C-layer point at these routes.

- [ ] **F1. Claims** — list, detail, intake review, gate/status display.
- [ ] **F2. Inspections** — list + detail on the claim (revalidate target of C0).
- [ ] **F3. Work Plans** — create/edit/list on the claim.
- [ ] **F4. Work Authorizations** — list + status + revision history.
- [ ] **F5. Notices of Defect** — issue + response tracking.
- [ ] **F6. ALA** — generate + signature status.
- [ ] **F7. Service Reports** — submission + review status.
- [ ] **F8. O&M Authorizations** — per-event authorization status.
- [ ] **F9. Warranty Registrations + Projects** — list/detail/create.
- [ ] **F10. Tenant settings surfaces** — lookup-table admin (C1), feature flags
  (C13), holiday calendar, warranty types.
- [ ] **F11. Platform-admin failed-events surface** — (pairs with B4).

---

## LAYER G — Validate the testable prototype

- [ ] **G1. End-to-end walkthrough** — provision a tenant → configure defaults →
  file a claim (tokenized) → inspect → work plan → authorize → execute → service
  report → close. Whatever gate-progression D1 lands defines how far "close" can
  go. This walkthrough being clickable IS the testable result that unlocks
  recruiting a technical co-founder.

---

## Suggested first moves from here (Andre decides)

> **SUPERSEDED (Chat 30).** All three items below are complete: C1 (Chat 23,
> `15a6779`), A1–A5 (Chat 24, `ac90fa2`), D1 (Chat 25/26). Live next moves:
> **C3 create/submit** (token layer's first consumer, carries E1c email),
> **C4-create** (independent, finishable), **B-layer** (dedicated session).
> Original block preserved below as history (Convention 7).

1. **C1 (lookup admin CRUD)** — most-locked, reuses Chat 23's exact shape,
   finishes the Tenant-Editable Defaults pattern. Cleanest single-session win.
2. **A1–A5 (provisioning seeding)** — small, self-contained, makes new tenants
   actually usable; good low-risk batch.
3. **D1 (claim lifecycle design)** — the one true design gap; tackle it before
   C10/C3 need it, as its own scoping effort.

B-layer (clock) is the biggest structural subsystem and is worth its own
dedicated arc once the smaller wins build momentum.
