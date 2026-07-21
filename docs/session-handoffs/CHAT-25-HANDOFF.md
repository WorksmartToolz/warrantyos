# CHAT 25 HANDOFF — WarrantyOS Phase 3 (app-layer build underway)

**Written at Chat 24 close, 2026-07-21.** (Filename is CHAT-25 because it is FOR the next chat.)

Every state claim below traces to Andre's actual pasted terminal output this session.

---

## ⚖️ READ FIRST — the Locked Decision Rule governs (and Chat 24 is the cautionary tale)

`docs/ROADMAP-TO-TESTABLE.md` carries the full build order + the governing law.
Read it before acting on any task. The law, in short: already-locked decisions
win; dig first (named source + dependencies + nearest built artifact's real
bytes); "I need Andre to decide" is a RED FLAG meaning the dig wasn't deep enough;
design gaps (D1 only) are the one exception.

**Chat 24 proved what happens when you DON'T dig first.** Two self-inflicted
problems, both from reasoning-before-checking:
1. Designed a compensating-rollback that tried to delete `warranty_types.is_system`
   rows — which the Decision 6 trigger (migration 011) makes un-deletable through
   the app path. Had 011's trigger been read before designing the rollback, the
   ordering fix would have been known up front instead of discovered by hitting the
   wall twice. Fixed by seeding warranty_types LAST.
2. Burned messages on PostgREST "schema cache" theories before checking `.env.local`
   — which revealed the real cause (see landmine below). The lesson Andre drove
   home: **build accordingly, don't relitigate; check locked sources before
   proposing anything.**

---

## Ground truth (verified)

- **HEAD:** `7a7bfdc`, pushed, `origin` = HEAD (confirmed via `git log`/`push`)
- **Branch:** `session-5e-bridge-phase3-schema-generator`
- **Working tree:** clean
- **Compiles:** `npx tsc --noEmit` exits 0

### Commits this session (Chat 24)

| Hash | What |
|------|------|
| `a737175` | docs(project-map): restamp header to Chat 23 / fe091e2 (drift fix) |
| `ac90fa2` | feat(provisioning): seed operational defaults at tenant creation (A1-A5) |
| `7a7bfdc` | docs(roadmap): strike A1-A4 done, A5 partial, add Chat 24 findings |

Lineage: `fe091e2` (Chat 23 handoff commit) → `a737175` → `ac90fa2` → `7a7bfdc`.

---

## What Chat 24 built — A1-A5 provisioning seeds (roadmap Layer A)

`lib/core/provision-tenant.ts` now seeds a new tenant with everything its
operational tables require. Verified END-TO-END against LOCAL (fresh reset +
provision + direct psql count): **2 sequences / 2 warranty_types / 4
inspection_types / 8 inspection_triggers / 121 holidays, all 6 settings keys.**

- **A1** `tenant_id_sequences`: `warranty_id` (WID-{year}-{seq:06d}) + `claim_id`
  (CLM-{year}-{seq:07d}), current_value 0. NOTE: the built `id_type` values are
  `warranty_id`/`claim_id` and the claim format is `CLM-...` — this supersedes the
  arch-ref line-47 design-era sketch (`[WarrantyID]-C[NNNN]`). Built to the 009
  schema, not the sketch.
- **A2** `warranty_types`: Standard + Workmanship anchors, `is_system: true`.
  **Seeded LAST** (see Finding 2).
- **A3** `inspection_types` (4) + `inspection_triggers` (8), all `platform_locked`,
  values verbatim from Decision 17.B.
- **A4** `tenant_holidays`: `admin.rpc('federal_holidays_for_year', {p_year})`
  looped over the locked **2026-2036** horizon (mirrors 024's backfill span
  exactly), bulk-inserted (~121 rows). The function DOES exist (024 L187) —
  an early Chat 24 grep miss wrongly suggested otherwise; the disk arbitrated.
- **A5** `tenants.settings` (folded into the initial `tenants` insert, atomic-by-
  construction): 6 locked scalar keys — `ala_signature_method`='in_platform_widget',
  `ala_decline_warning_text` (the platform default string), `ala_decline_recant_window_days`=3,
  `ala_markup_percent`=10, `ala_response_overdue_business_days`=7,
  `service_report_response_days`=3.

**Atomicity:** Option B — app-level compensating rollback (the Supabase JS client
has no multi-statement transaction; Andre chose B over a Postgres function). Any
seed failure deletes this tenant's seeded child rows + invitation + tenant, then
returns an error.

**NOT seeded — moved to D2:** the 3 feature flags (`epc_workflow`,
`supply_only_workflow`, `service_report_acquiesce_window`). The feature-flag
storage shape + `is_feature_enabled` reader do not exist yet. Seeding them into a
guessed shape would risk D2 orphaning the keys. D2 now owns these defaults (roadmap
updated).

---

## ⚠️ THREE FINDINGS — do not rediscover these (also in roadmap Layer A)

1. **`.env.local` points `NEXT_PUBLIC_SUPABASE_URL` at HOSTED PRODUCTION**
   (`uzjivnmwedfzcgqnnhos.supabase.co`). Running `provision-tenant.mjs` with NO
   override hits PROD. A Chat 24 test DID hit prod before this was caught (the
   rollback cleaned it up, so prod is clean — but verify if concerned). For LOCAL
   verification, always prefix:
   `NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321 SUPABASE_SERVICE_ROLE_KEY=<local secret from 'supabase status'> npx tsx scripts/...`
   The local secret key is the `sb_secret_...` value from `supabase status`.
2. **Decision 6 trigger makes `warranty_types.is_system` rows un-deletable via the
   app path.** The provisioning rollback therefore CANNOT delete them → warranty_types
   is seeded LAST so earlier failures roll back cleanly. Any future seed added
   AFTER warranty_types re-breaks rollback. Manual scratch teardown: `set
   session_replication_role = replica;` bypasses the trigger (superuser/postgres only).
3. **After `supabase db reset`, PostgREST serves a STALE schema cache** — REST
   calls to the newly-created tables fail with "Could not find the table ... in the
   schema cache." Fix: `docker restart supabase_rest_warrantyos` before any
   REST-based verification. (Direct `docker exec ... psql` is unaffected and is the
   reliable verification path.)

---

## THE ONE DESIGN GAP — D1 (unchanged, still not a build task)

The **Tier 3 Claim Lifecycle (Six Gates)** is NOT designed (arch-ref 3250-3251,
3358-3399). Resolve the design way (propose against the 3 lifecycle SOPs + 6
workbooks, ratify, log a decision) BEFORE building claim-progression actions
(roadmap C10). Only genuine design gap; everything else is a BUILD task with a
locked answer.

---

## OPEN ITEMS — none blocking

Working tree clean, all three commits pushed, HEAD = origin. Roadmap swapped to
current (A1-A4 struck, A5 partial, findings added). PROJECT-MAP header restamped
to Chat 23/fe091e2 early this session (its body was already current through C0/C1).
No pending doc-control.

**Files-panel note:** if PROJECT-MAP or ROADMAP moved after this handoff, re-swap
and verify (hash vs Downloads, or fresh-chat snapshot). Recurring trap: uploaded
`architecture-reference.md` lands in `docs/session-handoffs/` not `docs/` — `mv` it
back, then `git status --short` must be empty.

---

## RECOMMENDED NEXT (Andre decides; sequencing is his)

The C0/C1 shape (action=callerId → core=tenant+authz+mutate, mirroring manage-team)
is the proven template for every C-layer action. Provisioning seeding (A) is now
done, so a new tenant is fully usable.

1. **C2 (inspection edit/status machine)** — small, reuses C0's shape, exercises
   `open → in_progress → under_review → issued`. *Source: 021.*
2. **D1 (claim lifecycle design)** — the one design gap; its own scoping arc before
   C3/C10 need it.
3. **B-layer (clock/cron)** — biggest structural subsystem; its own dedicated arc.
4. **D2 (feature-flag reader + storage)** — now also owns the 3 provisioning flag
   defaults deferred from A5; unblocks flag-gated C-layer branches.

---

## Canonical docs (read PROJECT-MAP.md at repo root FIRST, then the ROADMAP)

- `PROJECT-MAP.md` (repo root) — durable orientation, header current as of `a737175`
- **`docs/ROADMAP-TO-TESTABLE.md`** — build order + governing Locked Decision Rule + Chat 24 findings
- `docs/architecture-reference.md` — Decision-6 trigger context 2943-2979; ID Generation 1016+; Tenant-Editable Defaults ~6700-6800; clock/cron 859-1015
- `docs/session-handoffs/5e-bridge-phase3-decisions-log-rev6.md` — Decisions 11-29; 17.B seed values 1420-1470; A5 settings defaults (19.6 L1908, 21.2 L2776, 25.2 L4650)
- `docs/session-handoffs/5e-bridge-phase2-decisions-log.md` — Phase 2 (Decision 3 here); BOTH logs live
- `CLAUDE-rev6.md` — Conventions 7/7a/8/9, Rule 10

---

## Standing disciplines still in force

- **The Locked Decision Rule governs. Dig before proposing — Chat 24 is the proof
  of what skipping it costs.** Read the locked source (migration bytes included)
  before designing anything that touches it.
- One command per WSL message; `▶ RUN IN WSL` / `▶ RUN IN CLAUDE CODE` labels; only
  the command in the code block. Andre is dyslexic.
- Never edit a canonical doc without showing the exact change and getting approval.
  Python in-place edit with anchor-count assertions is the reliable method
  (heredoc + backticks/`$` is fragile — write the payload to a /tmp file first, then
  Python-read it; the commit message went via `git commit -F /tmp/file` for the
  same reason).
- Two-commit convention: code commits separate from doc-control commits.
- Verify pushes succeeded. `tsc --noEmit`, never `next build` with the dev server up.
- `db reset` proves execution, not correctness — verify computed output by direct
  `docker exec ... psql` query, not by "applied clean."
- **Verification hits LOCAL only** — always use the `NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321`
  override (Finding 1).
- Fix doc drift the session you find it.
