# CHAT 24 HANDOFF — WarrantyOS Phase 3 (app-layer build underway)

**Written at Chat 23 close, 2026-07-21.**

Every state claim below traces to Andre's actual pasted terminal output this session.

---

## ⚖️ READ FIRST — the Locked Decision Rule now governs the build

There is a new canonical doc in the repo: **`docs/ROADMAP-TO-TESTABLE.md`**. It
carries the full build order to a testable product AND a governing law at the
top. Read it before acting on any task. The law, in short:

- **Already-locked decisions win.** ~95%+ is decided; the job is to BUILD, not relitigate.
- **Dig first, every task** — the named locked source, its dependencies, and the nearest built artifact's real bytes.
- **"I need Andre to decide" is a RED FLAG, not a valid state** — it means the dig wasn't deep enough. Stop, go back, dig deeper across arch-ref + both decisions logs + Phase 0 items + audit. Only after a genuine deep dig turns up nothing may a grounded question go to Andre — never a menu.
- **Design gaps (D1 only) are the one exception** — genuinely undrafted, resolved the design way.

Chat 23 proved this rule pays: it caught two would-be defects — the C0 authorization role (would have wrongly copied team_admin-only) and confirmed the revalidation convention was locked not absent; and on C1 it surfaced that the slugification algorithm WAS fully specified (arch-ref 6749-6752) when it first looked like a gap.

---

## Ground truth (verified)

- **HEAD:** `6bfb1d0`, pushed, `origin/session-5e-bridge-phase3-schema-generator` (HEAD = origin, confirmed via `git status`)
- **Branch:** `session-5e-bridge-phase3-schema-generator`
- **Working tree:** clean
- **Compiles:** `npx tsc --noEmit` exits 0 (verified before both code commits)

### Commits this session (Chat 23)

| Hash | What |
|------|------|
| `2c76cf0` | feat(inspections): create-path Server Action + core (C0) |
| `52dcf1b` | docs(project-map): C0 built, pattern PARTIAL pending CRUD |
| `15a6779` | feat(lookup-defaults): tenant-editable-defaults admin CRUD (C1) |
| `efb8164` | docs(project-map): C1 built, pattern APP-LAYER COMPLETE |
| `dde5cd2` | docs(roadmap): add ROADMAP-TO-TESTABLE with governing law |
| `6bfb1d0` | docs(roadmap): strike C1 (correcting stale checkbox) |

Lineage below: `8cd3aa2` (Chat 22 handoff) → prior Chat 22 work.

---

## What Chat 23 built (two operational Server Actions — the FIRST two in the repo)

**C0 — Inspection write-path** (`2c76cf0`). `lib/actions/inspections.ts` (thin) →
`lib/core/inspections.ts` (domain). The first operational Server Action in the
whole codebase. Mirrors the `manage-team` precedent exactly:
- Action resolves `callerId` via `createClient().auth.getUser()` (session client `@/lib/supabase/server`); core resolves tenant + authorizes via a service-role `createAdminClient()` read of `users`. **The action does NOT call `get_user_tenant_id()`** — that was a wrong early proposal; the real pattern is action=callerId, core=tenant+authz.
- **Authorization: `reviewer || team_admin`** (operational-write, arch-ref 780/5145-5148) — NOT team_admin-only. This is the deliberate inverse of governance actions.
- Cross-tenant guard on the parent claim (tenant_id-sync invariant, arch-ref 168-177).
- Validates `inspection_type_id` + `inspection_trigger_id` via the canonical helper (`validateTenantEditableDefaultsReference`, Decision 17.A.6.1); snapshots `inspection_type_value` / `inspection_trigger_value` from the VALIDATED rows the helper returns, never from client input (FK + Snapshot, 17.A.2).
- `status` omitted → DB default `'open'`. Return `{ success: true; id } | { success: false; error }`.
- Revalidation per locked convention (arch-ref 340-377): claim-scoped detail + `/app` parent. Routes don't exist yet — revalidatePath is a safe no-op until the UI lands.

**C1 — Tenant-editable-defaults lookup admin CRUD** (`15a6779`).
`lib/actions/lookup-defaults.ts` → `lib/core/lookup-defaults.ts`. Five ops:
create / rename / disable / enable / soft-delete, over `inspection_types` and
`inspection_triggers` (one impl serves both — 17.A.1 guarantees structural
identity; `table` param constrained to the literal union).
- **Full lock_tier permission matrix (17.A.5), enforced app-layer:** rename edits label only and is blocked for `platform_locked`; soft-delete is `tenant_added`-only; disable/enable apply to ALL tiers; create forces `tenant_added`.
- **value auto-slugified once at create** (lowercase, non-alphanumeric→`_`, trim), deterministic, never re-derived on rename (arch-ref 6749-6752). **App-layer uniqueness** on `(tenant_id, value)` checked at create; **reject-on-collision** (the locked-consistent minimum — auto-suffix would mint a value the tenant didn't author; arch-ref stresses value stability). Recorded in the commit for a future revisit if usage wants suffixing.
- **Authorization: `team_admin` only** — "Definition management is a tenant-admin capability" (arch-ref 781-782). The deliberate INVERSE of C0. Mirrors manage-team's governance gate.
- No PostgreSQL triggers (17.A.6) — all enforcement app-layer.

Both `tsc --noEmit` clean. Both landed `100755` (exec bit, cosmetic, matches prior files).

**Doc-control this session:** PROJECT-MAP's Tenant-Editable Defaults entry updated
twice (C0 → still PARTIAL; C1 → **APP-LAYER COMPLETE (UI pending)**, only the admin
UI surface / roadmap F10 remains). The pattern's application layer is now COMPLETE.

---

## THE BIG PICTURE (verified from disk this session — do not lose it)

A `find app lib components` this session established the true state:
**working software = FOUNDATION ONLY** (auth, signup, tenant provisioning, platform
admin, tenant admin, team management). **The entire operational product is schema +
now three operational Server Actions** (C0 inspection create, C1 lookup CRUD — the
only operational actions that exist). There are **NO operational UI routes** — every
`app/` page is auth/tenancy/admin/team. The 29 tables are an empty stage.

`docs/ROADMAP-TO-TESTABLE.md` is the full map: ~40 tasks across 7 layers (A
provisioning seeding, B clock/cron infra, C operational Server Actions, D feature
flags, E tokenized infra, F operational UIs, G validate). C0 and C1 are struck.

---

## ⚠️ THE ONE DESIGN GAP — D1 (not a build task)

The **Tier 3 Claim Lifecycle (Six Gates)** is NOT designed — the claim `status`
value set (Gate 1–6 + outcome states), transitions, authorized actors, and effects
are explicitly deferred to an undrafted "later v2 section" (arch-ref 3250-3251,
3358-3399). Claim shell (016), intake (027), and eligibility (Decision 27) ARE done,
so a claim can be filed but cannot progress. **Resolve D1 the design way** (propose
against the 3 lifecycle SOPs + 6 workbooks, ratify, log a decision) BEFORE building
the claim-progression actions (roadmap C10, part of C3). This is the only genuine
design gap; everything else is a BUILD task with a locked answer to find.

---

## OPEN ITEMS — none blocking

Working tree clean, all six commits pushed, HEAD = origin. PROJECT-MAP and the new
ROADMAP were swapped into the Files panel this session (hash-verified against disk,
Andre confirmed the UI delete/upload). No pending doc-control.

---

## RECOMMENDED NEXT (Andre decides; sequencing is his)

Per the roadmap's "suggested first moves":
1. **A1–A5 (provisioning seeding)** — small, self-contained batch (seed tenant_id_sequences, warranty_types anchors, tenant-editable-defaults rows, tenant_holidays, confirm feature-flag defaults) in `lib/core/provision-tenant.ts`. Makes new tenants actually usable. Low-risk, good momentum.
2. **C2 (inspection edit/status machine)** — small, reuses C0's shape, exercises the `open → in_progress → under_review → issued` machine.
3. **D1 (claim lifecycle design)** — the one design gap; tackle as its own scoping arc before C3/C10 need it.
4. **B-layer (clock/cron)** — the biggest structural subsystem; worth its own dedicated arc once smaller wins build momentum.

The C0/C1 shape (action=callerId → core=tenant+authz+mutate, mirroring manage-team)
is now the proven template for every C-layer action. New consumers follow it.

---

## Canonical docs (read PROJECT-MAP.md at repo root FIRST, then the ROADMAP)

- `PROJECT-MAP.md` (repo root) — durable orientation, current as of `efb8164`
- **`docs/ROADMAP-TO-TESTABLE.md`** — build order + governing Locked Decision Rule (NEW this session)
- `docs/architecture-reference.md` — helper rule 6902-6905; Tenant-Editable Defaults pattern ~6700-6800; clock/cron 859-1015; tokenized pattern 228-330; role model 780/5145-5148; revalidation 340-377
- `docs/session-handoffs/5e-bridge-phase3-decisions-log-rev6.md` — Decisions 11-29; 17.A.4/5/6/7 at 1298-1360
- `docs/session-handoffs/5e-bridge-phase2-decisions-log.md` — Phase 2 (Decision 3 here); BOTH logs live
- `CLAUDE-rev6.md` — Conventions 7/7a/8/9, Rule 10

**Files-panel note:** PROJECT-MAP and ROADMAP were swapped to current this session.
If PROJECT-MAP moved again after this handoff, re-swap and verify (hash vs Downloads,
or fresh-chat snapshot).

---

## Standing disciplines still in force (unchanged)

- The Locked Decision Rule above governs everything. Dig before asking.
- One command per WSL message; `▶ RUN IN WSL` / `▶ RUN IN CLAUDE CODE` labels; only the command in the code block. Andre is dyslexic.
- Never edit a canonical doc without showing the exact change and getting approval first. Python in-place edit with anchor-count assertions is the reliable method (heredoc/sed fragile for prose; the download→cp chain can silently copy a stale file — hash-verify).
- Two-commit convention: code commits separate from doc-control stamp commits.
- Verify pushes succeeded. `tsc --noEmit`, never `next build` with the dev server up.
- `db reset` proves execution, not correctness (no schema touched this session — tsc was the correct and only checkpoint).
- Surface message count each response; soft ceiling 85, warn ~65.
- Fix doc drift the session you find it (Standing Order #1 applies to docs too).
