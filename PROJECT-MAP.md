# WarrantyOS — Project Map

**Purpose:** One durable orientation document. Where the project has been, what
exists as working software, what exists only as locked design, and what the
next real build steps are. Read this first in any new chat.

**Last built:** 2026-07-14 (Chat 10), from verified git history and direct disk
reads. Phase 4 baseline is complete and Phase 3 table construction has begun.
Not from memory or handoff summaries.

---

## The one-paragraph orientation

WarrantyOS is a multi-tenant SaaS warranty-governance platform for mid-sized EPC
solar/renewables operations. Its foundation is **built and working**: auth,
multi-tenancy, RLS isolation, tenant provisioning, invitations, admin UI. Its
entire operational core — claims, ALA, inspections, work authorizations, service
reports, warranty registration, O&M authorization — is **fully designed and
locked (28 architectural decisions)**. The Phase 4 hosted-database baseline (the
gate that had to precede any Phase 3 table) is **done**, and **Phase 3 table
construction has started**: the first two tables (`contacts`, `projects`) are
built, migrated, and committed. The era is now building, not designing.

---

## Phase history (what actually happened, per git)

| Phase | What it was | State |
|-------|-------------|-------|
| Foundation | Next.js/TS/Tailwind/shadcn, Supabase, RLS, TS types | **BUILT** |
| Auth + tenancy | Auth, tenant provisioning, invitations, security hardening | **BUILT** |
| Admin UI | Platform admin, tenant admin, dashboard, team mgmt, seats | **BUILT** |
| Phase 1 | Architecture audit catalog | Done (analysis) |
| Phase 2 | Decisions 1–10 (core patterns) | Done (design) |
| Phase 0 items | Items 16/17/18 locked (contacts, defaults, feature flags) | Done (design) |
| Phase 3 | Decisions 11–28: all entity/workflow architecture | Done (design) |
| Phase 4 | Hosted-DB migration baseline | **DONE (baselined)** |
| Phase 3 build | Implementing the ~20 designed sections as migrations/code | **IN PROGRESS (2 tables built)** |

**The design era:** commit `506b181` ("Phase 3 Tier 1 drafted in v2") began the
design era; ~60 commits of architecture prose and doc-control followed. That era
is over. The build era began with the Phase 4 baseline and the first Phase 3
migrations (005, 006).

---

## BUILT — working software on disk

- Next.js 14.2 App Router, TypeScript strict, Tailwind v4, shadcn base-nova
- Supabase: client, auth, RLS isolation, TypeScript types
- Tenant provisioning + invitation system
- Security hardening (search_path, fall-closed RLS helper)
- Platform admin UI; tenant admin (dashboard, team list, seat counts)
- **Migrations on disk: 7** — 000_baseline through 004_team_admin_management
  (auth/provisioning), plus **005_contacts** and **006_projects** (first Phase 3
  tables).

Architecture sections marked **Implemented**: Standard RLS Pattern, Cache
Invalidation Pattern, Schema Source-of-Truth (foundation), plus **Unified
Contacts Directory** and **Project** (built this session as 005/006).

### Phase 3 tables built (as of Chat 10)

- **`contacts`** (005) — Unified Contacts Directory (Item 16, Decisions 1/20).
  10-value `contact_type` CHECK; self-referential `parent_contact_id` and
  `linked_om_provider_id`; Standard RLS Pattern applied. Cross-row invariants
  are app-layer (per architecture), not DB constraints.
- **`projects`** (006) — the sacred root entity (Decisions 5/23, Item 17).
  Multi-source trigger model with CHECK constraints; `customer_id` is a real FK
  to `contacts(id)`; Standard RLS Pattern applied.

---

## DESIGNED, NOT BUILT — locked architecture, remaining sections

All 28 decisions (11–28) are locked; the Cat 3 backlog is **fully resolved**.
The following architecture sections are marked **Designed** — prose exists, code
does not (contacts and projects have now moved out of this list):

- Claim Intake Data Model
- ALA System (Decision 19)
- Inspections Foundation (Decision 17)
- Service Report Submission (Decision 21)
- Customer Work Authorization (Decision 11)
- Work Plan Workflow (Decisions 13–16)
- Warranty Registration lifecycle (Decision 23)
- Warranty Type Coverages / end_date view (Decision 24)
- Customer-O&M Authorization (Decision 28)
- Tenant-Editable Defaults Pattern (Decision 17)
- Acknowledgment Gate Pattern (Decision 12)
- Clock Event Infrastructure (Decisions 9, extended by 11/21/25/27)
- Stateless Tokenized Interaction Pattern (applied, not yet coded)
- FK + Snapshot Pattern, Feature Flag System, Database Migration Tooling, others

---

## OPEN ITEMS (tracked, not forgotten)

- **`import_batches` table is undesigned.** Both `contacts` and `projects` carry
  an `imported_via_batch_id` column whose FK to `import_batches` is **deferred**
  — the column exists (for import provenance) but the FK CONSTRAINT is not yet
  added. Reason: `import_batches` belongs to the data-migration subsystem
  (Decision 8), whose MVP scope is an **open architectural question** (Phase 1
  audit). This is blocked on a design decision, not on effort. Trail to close:
  (1) decide data-migration MVP scope → (2) build `import_batches` → (3) add the
  `imported_via_batch_id` FK constraint to both `contacts` and `projects` via a
  follow-up migration. Recorded in the 005/006 commit message (`3c08e3d`).

---

## Phase 4 baseline — DONE

The hosted-database migration baseline (Decision 22) — the gate that had to
precede any Phase 3 table — is **complete**. Migration history is established on
the hosted database; all Decision 22.8 transition criteria are satisfied.

- Hosted project ref is recorded in `supabase/PRODUCTION-REF.md`
  (`uzjivnmwedfzcgqnnhos`). Two decoy projects share the org — always verify the
  linked ref before remote ops.
- Execution record: `docs/session-handoffs/phase4-baseline-execution-record.md`.
- The local build loop (write migration → `supabase db reset` → schema
  generator → verify) is proven and is the standard groove for every subsequent
  Phase 3 table.

---

## What "left to do" actually means (the build roadmap)

1. ~~Phase 4 baseline~~ — **DONE.**
2. **Build Phase 3 schema (IN PROGRESS)** — translate the remaining designed
   sections into migrations, following the locked patterns (RLS, FK+snapshot,
   tenant-editable defaults). 2 of ~20 tables built (contacts, projects).
3. **Build Phase 3 application layer** — Server Actions, tokenized flows, clock
   event dispatcher, the entity UIs.
4. **Validate the prototype** — the stated goal that unlocks recruiting a
   technical co-founder.

The design work that used to define "next step" is **done**. From here, "next
step" means code.

---

## How to not lose the thread again

- This file is the orientation anchor. Update it when a phase or milestone
  completes, not every commit.
- Doc-control on the architecture docs is **maintenance, not progress** — it does
  not move the build forward. Time-box it.
- Progress from here = migrations and code committed, not architecture prose
  revised.
