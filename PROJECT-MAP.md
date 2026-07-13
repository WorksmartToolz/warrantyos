# WarrantyOS — Project Map

**Purpose:** One durable orientation document. Where the project has been, what
exists as working software, what exists only as locked design, and what the
next real build steps are. Read this first in any new chat.

**Last built:** 2026-07-12 (Chat 9), from verified git history (85 commits) and
the architecture-reference.md status tally. Not from memory or handoff summaries.

---

## The one-paragraph orientation

WarrantyOS is a multi-tenant SaaS warranty-governance platform for mid-sized EPC
solar/renewables operations. Its foundation is **built and working**: auth,
multi-tenancy, RLS isolation, tenant provisioning, invitations, admin UI. Its
entire operational core — claims, ALA, inspections, work authorizations, service
reports, warranty registration, O&M authorization — is **fully designed and
locked (28 architectural decisions) but not yet built in code**. The project
spent its last ~60 commits designing, not building. The next era is building,
and it is gated by one setup task: the Phase 4 hosted-database baseline.

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
| **Phase 4** | **Hosted-DB migration baseline** | **NOT STARTED — the gate** |
| Phase 3 build | Actually implementing the 20 designed sections | **NOT STARTED** |

**The inflection point:** commit `506b181` ("Phase 3 Tier 1 drafted in v2") began
the design era. From there to `597b32c` (~60 commits) is all architecture prose
and doc-control. **The last feature code committed was tenant team management,
~70 commits ago.**

---

## BUILT — working software on disk

- Next.js 14.2 App Router, TypeScript strict, Tailwind v4, shadcn base-nova
- Supabase: client, auth, RLS isolation, TypeScript types
- Tenant provisioning + invitation system
- Security hardening (search_path, fall-closed RLS helper)
- Platform admin UI; tenant admin (dashboard, team list, seat counts)
- **Migrations on disk: 5** — all auth/provisioning (000_baseline through
  004_team_admin_management). **Zero Phase 3 tables.**

Architecture sections marked **Implemented** (3): Standard RLS Pattern, Cache
Invalidation Pattern, Schema Source-of-Truth. These describe the built foundation.

---

## DESIGNED, NOT BUILT — locked architecture, zero code

All 28 decisions (11–28) are locked; the Cat 3 backlog is **fully resolved**.
The following ~20 architecture sections are marked **Designed** — prose exists,
code does not:

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

## THE GATE — Phase 4 hosted-DB baseline (Decision 22)

Before any Phase 3 table is built, the hosted database needs migration history
established. This is flagged across every handoff as a dedicated-session
prerequisite. Key facts:

- Touches the **production database** — least-reversible operation in the project.
- Decision 22 defines the procedure: **six gates (22.3)**, run one at a time,
  then a **six-step repair (22.2)**. Backup first.
- **Gate 4** requires a known-good hosted project ref and is **unrecoverable if
  wrong** ("surgery on the wrong database"); visual inspection is explicitly NOT
  sufficient. **STATUS (verified Chat 9): the hosted project ref is NOT stored in
  any committed file.** config.toml has `project_id = "warrantyos"` (local CLI
  name only), not the hosted `xxxx.supabase.co` ref. **Phase 4's FIRST task:
  locate the correct hosted project ref from the Supabase dashboard and commit it
  so Gate 4 has a verified, version-controlled target.**
- **Gate 6** (drift verification via `supabase db diff`, per 22.9) is called out
  as the most critical gate.
- Full procedure: decisions log Decision 22; CLAUDE-rev6.md stop-point section.

---

## What "left to do" actually means (the build roadmap)

1. **Phase 4 baseline** (the gate above) — dedicated session, backup, six gates.
   First sub-task: store the hosted project ref (see above).
2. **Build Phase 3 schema** — translate the 20 designed sections into migrations,
   following the locked patterns (RLS, FK+snapshot, tenant-editable defaults).
3. **Build Phase 3 application layer** — Server Actions, tokenized flows, clock
   event dispatcher, the entity UIs.
4. **Validate the prototype** — the stated goal that unlocks recruiting a
   technical co-founder.

The design work that used to define "next step" is **done**. From here, "next
step" means code.

---

## How to not lose the thread again

- This file is the orientation anchor. Update it when a phase completes, not
  every commit.
- Doc-control on the architecture docs is **maintenance, not progress** — it does
  not move the build forward. Time-box it.
- Progress from here = migrations and code committed, not architecture prose
  revised.
