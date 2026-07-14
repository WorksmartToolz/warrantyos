# Handoff → Chat 12

**Written:** 2026-07-14 at the close of Chat 10 (the first Phase 3 build session).
**Built on:** verified git + direct disk reads, not memory. Every claim below was
confirmed this session by command output.

> **Read `PROJECT-MAP.md` (repo root) first.** It is the durable orientation doc
> and it is fully current as of this session. This handoff is the session-specific
> supplement.

---

## The one thing to internalize before building

**The design phase is done. ~95%+ of decisions are already made and locked**
(Decisions 1–28, Phase 0 Items, architecture-reference.md). Your job is to
**build accordingly** — translate locked specs into migrations/code. Do **not**
re-open design questions, and do **not** defer something as "undesigned" without
first checking the decisions log for an existing spec. Most things are already
specified. Only make a decision when a genuine conflict surfaces at a specific
point during the build — flag it, resolve it minimally, keep building.

(Cautionary precedent from this session: `import_batches` was briefly deferred as
"undesigned" when Decision 8 had fully specified it all along. Caught and
corrected same session, but it cost cycles. Check first.)

---

## Where the project stands (verified)

- **Branch:** `session-5e-bridge-phase3-schema-generator`
- **Git HEAD:** `5b52d8b`, pushed, working tree clean, in sync with origin.
- **Phase 4 baseline:** COMPLETE (done in a prior session). Hosted DB is
  baselined; migration history established. Hosted project ref
  `uzjivnmwedfzcgqnnhos` recorded in `supabase/PRODUCTION-REF.md`.
- **Phase 3 build:** IN PROGRESS — **3 of ~20 tables built.**

### Migrations on disk (9 total)
- `000_baseline` → `004_team_admin_management` — auth/provisioning foundation
  (pre-existing).
- `005_contacts.sql` — Unified Contacts Directory (Item 16, Decisions 1/20).
- `006_projects.sql` — Project sacred root (Decisions 5/23, Item 17).
- `007_import_batches.sql` — Data Migration Tooling batch tracking (Decision 8).
- `008_import_batch_fks.sql` — adds the `imported_via_batch_id` FK constraints on
  contacts and projects (closes the FKs deferred in 005/006).

### Commits this session
- `3c08e3d` — feat: contacts + projects (005, 006)
- `f59c2a9` — docs: PROJECT-MAP updated (baseline done, 2 tables)
- `26133be` — feat: import_batches + FK closure (007, 008)
- `5b52d8b` — docs: PROJECT-MAP updated (3 tables, all FKs closed)

### Open items
**None** from the Phase 3 build. Zero deferred FKs. Nothing half-done.

---

## The build loop (PROVEN this session — use it for every new table)

This is the standard groove. It was validated end-to-end on 4 migrations tonight.

1. Draft the migration SQL from the **locked spec** in architecture-reference.md /
   decisions log (do not improvise schema).
2. `cp` the file into `supabase/migrations/NNN_name.sql`.
3. `git status` — confirm it landed (raw bytes, not narration).
4. `supabase db reset` — replays ALL migrations against local Postgres. **This is
   the real validation**: any SQL error, bad FK, or constraint problem fails here,
   locally, harmlessly. Nothing touches the hosted DB.
5. `node scripts/generate-schema-sql.mjs` — regenerates `supabase/schema.sql`.
6. `grep -in "create table" supabase/schema.sql` (or grep the specific table) —
   confirm the new table + constraints are captured.
7. Pre-commit audit: `git diff --stat supabase/schema.sql`; if deletions appear,
   verify they're dump-reordering, not lost content (grep the "deleted" infra
   lines to confirm they still exist elsewhere).
8. Stage, commit (with a descriptive multi-`-m` message citing the Decision),
   push, verify the push (`origin HEAD..NEWHEAD`), confirm clean tree.

### Locked patterns every table follows
- **Standard RLS Pattern** (6 steps): `tenant_id` FK; `enable row level security`;
  SELECT policy `"<table>: members can view their tenant's rows"` using
  `tenant_id = public.get_user_tenant_id()`; writes service-role only (no
  user-facing INSERT/UPDATE/DELETE except the narrow `users` self-profile case);
  `grant all on public.<table> to anon, authenticated, service_role`; self-read
  exception only if genuinely needed (rare).
- **PK convention:** `id uuid primary key default gen_random_uuid()`.
- **tenant_id denormalized** onto child tables (not joined through parent); the
  matches-parent invariant is app-layer, enforced in the Server Action wrapper.
- **FK + Snapshot Pattern** for references to contacts / lookup tables (FK column
  + denormalized value snapshot captured at write time).
- **Cross-row invariants are app-layer**, documented as comments, NOT DB
  constraints (per the architecture's own wording).

---

## What to build next (dependency-ordered suggestion)

Remaining ~17 designed sections (see PROJECT-MAP "DESIGNED, NOT BUILT"). Natural
next targets, roughly in dependency order — but **confirm each against the
decisions log before building**:

- **`warranty_registrations`** (Decision 23) — 1:1 with projects (UNIQUE on
  project_id, ON DELETE RESTRICT), dual-FK assignee model (Decision 1), status
  state machine (Decision 23.7). Direct child of projects, so a clean next step.
- **`tenant_id_sequences`** (ID Generation) — needed by WarrantyID/ClaimID
  issuance; foundational for registrations and claims.
- **Tenant-editable defaults lookup tables** (Decision 17) — inspection_types,
  inspection_triggers, etc.; the canonical lookup-table shape + 6-step convention.
- **`custom_field_definitions` / `custom_field_values`** (Decision 3).
- **`warranty_types` / `warranty_coverages`** (Decision 24) — note `end_date` is
  derived, not stored.
- Then claims, ALA, inspections, work plans, service reports (many are
  workbook/SOP-anchored — the 6 claim intake workbooks and 7 SOPs are the field
  sources).

Pick one, pull its exact locked schema from architecture-reference.md, run the
loop. One table (or one tightly-coupled pair) per focused pass.

---

## Working conventions (unchanged, still in force)

- **Command hygiene (critical — Andre is dyslexic):** ONE command per code block,
  ONLY the command in the block, labeled `▶ RUN IN WSL` or `▶ RUN IN CLAUDE CODE`.
  One at a time, confirm before the next. Never mix prose and commands ambiguously.
- **Environment:** WSL/Ubuntu, `/home/andre/Projects/warrantyos`, Docker running
  the local Supabase stack (Postgres 17 on 54322). Supabase CLI 2.109.1, Claude
  Code 2.1.207 (both current as of this session). Dev server port 3000 only.
- **File writes:** advisor generates full file in chat → Andre downloads →
  `cp "/mnt/c/Users/andre/Downloads/FILE" path/in/repo/FILE` → verify with
  `git diff` before committing. (Do NOT rely on Claude Code for load-bearing file
  writes/reads — force raw bytes; it has fabricated output before. It passed the
  trust test this session but the fallback discipline stands.)
- **Pre-commit audit** before every substantive commit. Non-negotiable.
- **Verify pushes** succeeded (check the `origin` ref line).
- **Doc-control:** keep disk, git, and the Files panel in sync. When PROJECT-MAP
  or a canonical doc changes on disk, swap the Files panel copy too (delete old,
  upload new from Downloads) — no silent drift.
- **When `supabase db reset` runs:** it wipes LOCAL data only (rebuilt from
  migrations). Never run destructive ops against the hosted DB without the
  Decision 22 gates. `npx tsc --noEmit` instead of `npx next build` while the dev
  server runs.
- **Session rhythm:** 45–90 min; soft ceiling 85 messages, warn ~65.

---

## First moves in Chat 12

1. `cd ~/Projects/warrantyos && git status` — expect clean, HEAD `5b52d8b`.
2. `git log --oneline -6` — expect `5b52d8b` at top.
3. Read `PROJECT-MAP.md`.
4. Pick the next table (suggest `warranty_registrations`), pull its locked schema
   from `docs/architecture-reference.md`, run the proven build loop.

No reset/trust-test needed unless Claude Code misbehaves again — the tooling was
reset and verified this session.
