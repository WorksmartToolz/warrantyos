# Phase 4 Baseline — Execution Record

**Status:** COMPLETE — baseline executed and verified.
**Execution date:** 2026-07-12
**Verifier:** Andre (solo founder)
**CLI version (pinned baseline):** supabase 2.101.0
**Branch:** session-5e-bridge-phase3-schema-generator
**Governing decision:** Decision 22 (Database Migration Tooling), decisions-log-rev6.

---

## What was done

Established migration history on the hosted/production Supabase database so
Phase 3 schema construction can begin. The remote's `supabase_migrations`
history was empty (the tables were originally created by hand in the SQL Editor
before the migrations directory existed); this procedure marked migrations
000-004 as already-applied on the remote **without re-running them**.

## Prerequisite closed

The hosted project ref was not stored in any committed file (punted across
Chats 7/8/9). Resolved this session: committed `supabase/PRODUCTION-REF.md`
recording ref `uzjivnmwedfzcgqnnhos` - commit `845b717`.

## Pre-procedure gates (Decision 22.3) - all passed

- Gate 1 (clean repo / correct branch): pass - HEAD 845b717, tree clean.
- Gate 2 (five migration files present): pass - 000-004.
- Gate 3 (CLI authenticated, version pinned): pass - supabase 2.101.0
  (no previously-pinned version existed; 2.101.0 is now the tested baseline
  version). Update to 2.109.1 deliberately deferred to avoid introducing a
  variable before the least-reversible operation.
- Gate 4 (linked project verified exact): pass - linked to uzjivnmwedfzcgqnnhos
  (warrantyos), verified character-by-character against PRODUCTION-REF.md; two
  decoy projects (qravve, halalapp-dev) in the same org confirmed NOT linked.
- Gate 5 (remote migration-history pre-state): pass - empty history (greenfield,
  pre-state case "a"). Step 0 backup therefore a no-op (no state to capture).
- Gate 6 (drift verification, Decision 22.9): **drift reported, determined
  cosmetic, accepted by Andre.** `supabase db diff` emitted three functions
  (rls_auto_enable, get_user_tenant_id, set_updated_at). Direct query of the
  remote confirmed all three exist; `get_user_tenant_id` body verified
  byte-identical in logic to the migration definition (004 version present:
  `status = 'active' and removed_at is null`). Differences are CRLF-vs-LF line
  endings on three hand-created functions, non-behavioral. No Mode D risk:
  the remote holds the correct state. Accepted per 22.9 with this record as
  the required documentation.

## Repair (Decision 22.2 Step 2) and per-command verification (22.4)

Ran `supabase migration repair --status applied` for 000, 001, 002, 003, 004
sequentially, one at a time, verifying via `supabase migration list --linked`
after each. Final state: all five present in both Local and Remote columns.

## Post-baseline generator check (Decision 22.8 condition 2)

`node scripts/generate-schema-sql.mjs` ran successfully post-baseline
(local stack up). Regenerated schema.sql; `git diff` showed no change from the
committed file - expected per Decision 22 Step 5 (baseline established the same
state already on disk).

## Transition criteria (Decision 22.8)

1. Baseline executed and verified - DONE.
2. Generator verified working post-baseline - DONE.
3. Session-handoff entry (this document) - DONE.
4. CLAUDE-rev6.md stop-point -> RESOLVED - the final step; see companion commit.

## Anomalies

None requiring recovery. No failure modes (A-F) triggered. Gate 6's cosmetic
drift is the only deviation from a fully clean run and is documented above.
