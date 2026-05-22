# WarrantyOS — Session 5e-bridge Phase 2 Handoff Document

Generated: 2026-05-22
Purpose: Comprehensive context for resuming Session 5e-bridge Phase 2 in a fresh chat.
Read this first, then read the referenced documents in the order listed.

---

## I'M CONTINUING WORK ON WARRANTYOS

A multi-tenant SaaS warranty governance platform for mid-sized EPC solar/renewables operations. I'm Andre, solo founder. This handoff exists because the previous chat is getting long and Phase 2 of the Session 5e-bridge needs a clean, responsive working environment for dense decision-making.

## PROJECT IDENTITY

WarrantyOS is a multi-tenant SaaS for managing warranty operations end-to-end. Beachhead customer: mid-sized EPC solar/renewables operations. Decision sequence in target accounts: Warranty Director (champion) → COO/President (money gate) → CIO/IT (hardest gate).

## ME (ANDRE)

Solo founder. Dyslexic but technically savvy — not a developer. Authored Terrasmart SOPs (TSW-GD-202/203/204/204b/205/211) and QCELLS SOP (EHSQ-SOP-201) in past role. Building solo prototype with Claude Code, intend to recruit technical co-founder after prototype validates.

WORKING STYLE:
- Plain language, no jargon
- Click-by-click instructions for technical setup
- Challenge weak assumptions — push back when I'm about to defer something that should be addressed now
- "1 or 2?" responses for Claude Code permission prompts
- Test thoroughly before committing
- Verify pushes succeeded
- Soft-remove for users (audit trail preservation)
- 45-90 minute sessions work best
- Don't reinvent the wheel — if an audit confirms code is correct, that counts as evidence
- Tests are checkpoints, not investigations
- Default to less, not more — don't add belt-and-suspenders verification on already-confirmed work
- If I ask to fix something now vs defer, take "fix it now" seriously

## TECHNICAL ENVIRONMENT

- Machine: Windows desktop running WSL/Ubuntu (NOT switching to native Windows)
- WSL username: andre
- Project path: /home/andre/Projects/warrantyos
- Editor: VS Code on Windows with WSL extension
- AI assistance: Claude Code v2.x (Sonnet 4.6) launched from WSL terminal
- Dev server port: 3000 (port 3001 does NOT work — 3000 is correct)

## TECH STACK

- Frontend: Next.js 14.2 App Router, TypeScript strict
- Styling: Tailwind v4 (migrated from v3 in Session 5c)
- UI Components: shadcn (base-nova style, Base UI primitives — NOT Radix)
- Database: Supabase (PostgreSQL with RLS)
- Auth: Supabase Auth
- Email: Resend (account created, not yet integrated)
- Hosting: Vercel (account exists, not yet deployed)
- Version Control: Git/GitHub (WorksmartToolz/warrantyos)
- Node v24.15.0 via nvm, npm v11.12.1, Git v2.53.0

CRITICAL FRONTEND NOTES:
- shadcn base-nova uses Base UI primitives, not Radix. APIs differ (onClick not onSelect, native button requirements, ref forwarding patterns).
- Tailwind v4 conditional classes (data-disabled:opacity-50, etc.) only apply when the attribute is present on the element. The data-disabled attribute presence is set by Base UI when disabled={true} reaches the primitive.
- When Claude Code wants to run `npx next build` while the dev server is running, REFUSE. Use `npx tsc --noEmit` instead.

## REFERENCE DOCUMENTS (READ IN ORDER)

Before continuing Phase 2 work, the new Claude must read these in order:

1. docs/architecture-reference.md — v1 architecture document. The system's source of truth as it exists today. Treat any decision documented here as anchor architecture unless we explicitly agree to change it. v2's job is to expand and complete, not re-litigate.

2. docs/session-handoffs/5e-bridge-phase1-audit.md — 565-line Phase 1 audit catalog. Read all 15 topics (A/B/C structure) plus the summary section with 5 contradictions, 10 decisions, 6 risks. This is the working reference for Phases 2 and 3 of the bridge.

3. This handoff document.

## PROJECT STATE — GIT

Most recent commits (newest first):
- 122dabb Session 5e-bridge Phase 1: Architecture audit catalog
- 3310bb8 Document Session 5e deferred items
- 5690e05 Fix stale page cache after team mutations
- 1022d16 Fix dashboard stat queries to filter removed and suspended users
- ad2c887 Session 5d: Fix DropdownMenu clicks, suspension loop, AlertDialog warning
- d546767 Session 5c: Migrate Tailwind v3 → v4 to match base-nova component style
- c4b914a [Session 5b checkpoint] Tenant team management: partial — action menus broken
- 35b6f6a Tenant admin foundation: role rename, seat count, app layout, dashboard, team list
- f3cf713 Security hardening and platform admin UI
- 7345dd4 Auth, tenant provisioning, and invitation system

Verify on resume:
- `cd ~/Projects/warrantyos`
- `git status` — expect clean working tree, up to date with origin/main
- `git log --oneline -5` — expect 122dabb at top

## ROLE TIER MODEL (CRITICAL — being updated in v2)

CURRENT (v1) STATE:
- Platform Admin — Provider-side. is_platform_admin: true in Supabase Auth user_metadata. No row in public.users.
- Team Admin — Tenant-side. role='team_admin' in public.users.
- Reviewer — Tenant-side. role='reviewer'.
- Viewer — Tenant-side. role='viewer'.

v2 ADDITION (locked in during pre-Phase-1 alignment):
- PM (Project Manager) — Tenant-side. Creates and manages warranty registrations. PM assignment per warranty is fluid/reassignable.

Phase 2 must decide HOW the PM role is implemented at the data model level (users.role value, assignment column on warranty_registrations, or both). This is Decision 1 in the Phase 2 sequence.

## WHAT'S BUILT AND VERIFIED (THROUGH SESSION 5e)

Two admin environments fully functional:

PLATFORM ADMIN (`/admin/*`):
- Dashboard with platform-wide stats
- Tenant list and provisioning form (with max_team_admins field)
- Platform admin creation form
- Security hardening complete

TENANT ADMIN (`/app/*`):
- Sidebar layout with conditional nav (Settings admin-only)
- Dashboard with stat cards (Team Members, Team Admin Seats X/Y, Tenant Slug) — fixed in Session 5e to filter removed/suspended users
- Team list page with role badges
- Invite Team Member form (functional, with seat display)
- Settings page (view-only)
- Role management actions (promote, demote, suspend, remove) — working
- Confirmation dialogs for destructive actions
- Suspension blocks login with clear error message
- Last-admin protection enforced server-side AND in UI (verified via Test 2)
- Page cache invalidates after mutations via revalidatePath in Server Actions (added in Session 5e)

DATABASE — 3 TABLES, 4 MIGRATIONS:
- public.tenants
- public.users (with status, removed_at, max_team_admins)
- public.invitations
- get_user_tenant_id() helper function (filters by status='active' AND removed_at IS NULL)
- RLS enabled on all three tables, verified via Test 4 (Sarah cannot read or modify Acme Solar data)

## TEST DATA IN DATABASE

Platform admins:
- admin@warrantyos.dev (password: Test1234!)
- admin2@warrantyos.dev

Tenant: Acme Solar (slug: acme-solar, max_team_admins=3)
- Jane Smith (team_admin)

Tenant: Bright Energy (slug: bright-energy, max_team_admins=3)
- Sarah Mitchell (team_admin, admin@brightenergy.com / TestPass123!)
- Test Reviewer (reviewer, reviewer@brightenergy.com / TestPass123!)
- Remove Test (viewer, removetest@brightenergy.com / TestPass123! — was test artifact from Session 5e cache test, now viewer role)

Tenant: Test Co (no users)

Tenant IDs:
- acme-solar: 39984a81-2b64-431e-a4dc-f2d3541ce25b
- bright-energy: 92b4f6ed-28ab-4cc8-907c-c76b88aad20c
- test-co: 384865ee-916a-4536-a2bb-7e0a57ed5698

## SESSION HISTORY

- Sessions 1-2: Project + database foundation
- Session 3: Auth + invitation system
- Session 4: Platform admin UI + security
- Session 5a: Tenant admin foundation (read-only)
- Session 5b: Tenant team management partial — broke on DropdownMenu Bug 3
- Session 5c: Tailwind v3→v4 migration (foundational fix from Session 1)
- Session 5d: Bug 3 fix, suspension loop fix, 3 of 7 role management tests passed
- Session 5e: 4 remaining role management tests completed. Found and fixed two foundation bugs:
  * Dashboard stat queries missing removed_at filter (commit 1022d16)
  * Page cache not invalidating after team mutations (commit 5690e05)
  * Documented Session 5e deferred items (commit 3310bb8)
  * Tenant team management verified foundational-complete via Tests 1-4
- Session 5e-bridge Phase 1: Architecture audit catalog committed (122dabb)
- Session 5e-bridge Phase 2: THIS IS WHERE WE ARE NOW

## PHASE 0 ALIGNMENT (LOCKED IN — DO NOT RE-LITIGATE)

Decided in pre-Phase-1 conversation. These are decisions made, not open items:

1. Project is the sacred root entity (1:1 with Warranty Registration). Nothing in WarrantyOS exists before a project exists.

2. Warranty Registration is 1:1 with Project. A single warranty registration holds multiple warranty type coverages (Standard, Workmanship, Foundation, Component, etc.) — each with its own term dates — all under one WarrantyID.

3. Standard Warranty + Workmanship Warranty are anchor types: seeded at tenant provisioning, can be renamed, cannot be deleted. Other warranty types are tenant-configurable without code changes.

4. WarrantyID is issued at the Section 7 activation gate (not at registration creation). Pending registrations don't have WarrantyIDs. Approved registrations do.

5. Section 7 (Registration Review & Activation) is anchor architecture. Expand if needed, do not restructure or replace.

6. ClaimID format changes in v2: from v1's [WarrantyID]-C[NNNN] (derived) to v2's CLM-YYYY-NNNNNNN (independent sequence). Per-tenant configurable.

7. WarrantyID format: WID-YYYY-NNNNNN, per-tenant configurable. Sequence mechanics TBD in Phase 2.

8. PM role added to tenant role model. PM creates warranty registrations. PM assignment per warranty is fluid/reassignable. Implementation details TBD in Phase 2.

9. Projects exist in WarrantyOS once their contractual milestone date is known. Registration prep is triggered registration_lead_time_days before the milestone (default 21 days, per-tenant configurable).

10. Term + start = derived end. Don't store warranty end dates explicitly — compute them from start + term_years.

11. Data migration tooling moves from v1's "Out of Scope" to v2's MVP scope. Sales-critical onboarding experience — bulk import of project portfolios with field mapping, preview, graceful errors.

12. Document storage via Supabase Storage with metadata table. NO URL string storage (warranty horizons up to 25 years — links rot, permissions move, files disappear).

13. Custom field system is foundational, not deferred. Per-tenant custom field definitions. Field types: address, phone, date, number, plain text, rich text, dropdown, email, URL, checkbox, file upload. Possibly also: signature, multi-select, currency (TBD in Phase 2). Rich text stored as JSON, not HTML.

14. Out of Scope binary structure (v1's In Scope / Out of Scope) is replaced in v2 with three-column structure: MVP / Post-MVP / Explicitly Out of Scope.

15. The data model hierarchy:
    Project (sacred root)
    ↓ 1:1
    Warranty Registration (issues WarrantyID at activation gate)
    ↓ 1:many
    Warranty Type Coverages (per-type term tracking)
    
    Warranty Registration also has:
    ↓ 1:many
    Claims (each gets ClaimID)
    ↓ 1:many (per claim)
    ALA Documents, Inspections, Work Plans, Costs, Communications, Audit Trail Entries
    
    All scoped to a Tenant via tenant_id.

## PHASE 2 PURPOSE AND APPROACH

Phase 2 is decision-making only. No code changes. No documentation drafting. We walk through 10 architectural decisions surfaced in the Phase 1 audit catalog, in dependency order. Each decision gets discussed in plain language, options laid out, Andre makes the call, decision is captured.

Phase 2 output: a Phase 2 Decisions Log committed to disk at the end of the phase. That log becomes the input for Phase 3 (v2 doc drafting).

PHASE 2 DECISIONS (IN DEPENDENCY ORDER):

1. PM role data model — Is PM a users.role value, an assignment column on warranty_registrations, or both? Blocks: projects schema, warranty_registrations schema, RLS for projects.

2. ClaimID sequence mechanics + WarrantyID format configurability — How are sequences managed (per-tenant? global? PostgreSQL SEQUENCE? application counter in tenants.settings?), what's the zero-padding width, where does the per-tenant format string live? Blocks: any ID generation work.

3. Custom fields Phase 1 entity scope — Which entities support custom fields in Phase 1 (projects only, claims only, all)? Blocks: claim intake schema, warranty registration schema.

4. Rich text editor choice — TipTap vs Lexical vs Plate. JSON formats differ between editors and aren't easily migrated. Blocks: custom_field_values storage format.

5. Project ↔ WarrantyRegistration FK direction — Almost certainly warranty_registrations.project_id (project comes first), but needs explicit confirmation.

6. Warranty type anchor delete protection — Application-layer check vs database trigger vs is_system column flag.

7. ALA markup percent — Reconciliation may not be needed (10% in Terrasmart spec; v1 doc may not actually mention 15% — the audit couldn't find it). Investigation first, then decision.

8. Data migration tooling MVP scope — CSV with fixed mapping (minimal) vs Excel + mapping UI + preview + partial success (full)? Where does it live (platform admin or tenant app)?

9. Clock event infrastructure — Supabase pg_cron vs Vercel Cron Functions vs external scheduler. Largest decision; may be deferred to Session 5f if too large for bridge scope.

10. Schema source of truth — schema.sql vs numbered migrations have no documented relationship. Worth addressing but doesn't block drafting.

## ARCHITECTURAL CONTRADICTIONS TO RESOLVE IN V2 (FROM AUDIT SUMMARY)

1. Session 5b deferred items are stale (all built) — v2 retires this section
2. ClaimID format change ([WarrantyID]-C[NNNN] → CLM-YYYY-NNNNNNN) — v2 announces deliberately
3. "Equipment and Workmanship sub-tables" language is superseded by per-tenant configurable types — v2 updates language
4. Data migration tooling scope change (out of scope → MVP) — v2 un-lists it
5. Two schema sources of truth (schema.sql + numbered migrations) — v2 needs to clarify the relationship or pick one

## RISKS AND CONCERNS ABOUT V2 SCOPE (FROM AUDIT SUMMARY)

1. v2 will be 600-900+ lines (v1 is ~250). Scope the effort.
2. Topics 6, 9, 10, 12 reference external specs — incorporate before writing those sections.
3. Session-numbered deferred sections accumulate rot. v2 uses single living "Outstanding Items" organized by category.
4. Schema is very early; doc may get ahead of code. v2 should mark each major section with implementation status (Implemented / Designed / Deferred).
5. The "Out of Scope" binary doesn't capture reality (some built, some in-progress, some deferred-but-planned, some genuinely post-MVP). Three-column structure (MVP / Post-MVP / Explicitly Out) is more accurate.
6. middleware.ts:77 has a TODO for moving auth lookup to JWT claim. Real performance debt. v2 surfaces this as a named architectural debt item.

## KEY ARCHITECTURAL PRINCIPLES (FROM V1 — STILL HOLD)

- Defensibility Principle: Every consequential decision generates audit-quality reasoning.
- Burden of Proof Principle: Claimant bears responsibility for demonstrating warranty basis.
- Structural Integrity Principle: Foundation issues compound. Deferred items become blockers.
- Multi-tenancy Isolation Principle: Strict tenant isolation enforced at database level via RLS.
- Soft Remove Principle (newly named, was implicit): Removed users preserve auth + data; tracked via removed_at, not status.
- System-Managed Clock Principle: All deadlines and time-bound state transitions managed by the platform.
- Stateless Customer Interaction Principle: Customers have no platform accounts; all engagement via tokenized email links.
- Methodological Privacy Principle: Customer-facing communications include only operational content; internal cost/notes/reasoning is not customer-visible.
- Obligation-Not-Assistance Principle: The warrantor honors contractual obligations, not customer service.
- Operational Transparency Principle: Significant claim events visible to the warranty team broadly via shared dashboards.
- Single Reviewer Continuity Principle: A claim owned by one reviewer pickup through outcome.
- Data Portability Principle: Warrantor organizations can export their data at any time.

## RECENT LESSONS LEARNED

From Session 5b/5c: When Claude Code wants to run `npx next build` while the dev server is running, REFUSE. Use `npx tsc --noEmit` instead.

From Session 5b: shadcn base-nova uses Base UI primitives, NOT Radix UI. APIs differ.

From Session 1 deferral: When Andre asks if a foundational issue should be fixed now or deferred, take "fix it now" seriously.

From Session 5e Test 1: Foundation bugs that look like "just a UI issue" often have database-layer roots. Audit before assuming.

From Session 5e Test 2: Stale page cache after server mutations is a real Next.js issue. revalidatePath in Server Actions is the standard fix.

From Session 5e overall: Tests are checkpoints, not investigations. When a test passes, declare it passed and move on. Don't invent additional verification layers on already-confirmed work.

## COMMUNICATION STYLE FOR ANDRE

When responding to Andre:
1. Acknowledge state clearly before acting
2. Walk through plans before code changes
3. Push back if Andre is about to defer something that should be addressed now
4. Use plain language
5. Give "1 or 2?" responses for Claude Code permission prompts in Andre's terminal
6. Verify thoroughly before declaring success
7. Be honest about tradeoffs
8. Acknowledge mistakes when made rather than deflecting
9. Don't reinvent the wheel — audit findings count as evidence
10. Default to less, not more

## ENVIRONMENT VERIFICATION COMMANDS

When ready to start Phase 2:
1. Open WSL terminal
2. cd ~/Projects/warrantyos
3. git status (expects clean, up to date with origin/main)
4. git log --oneline -5 (expects 122dabb at top)
5. NO dev server needed for Phase 2 (documentation only)
6. NO Claude Code needed at the start of Phase 2 (discussion happens in chat first; Claude Code only invoked at end of Phase 2 to commit the decisions log)

## CONFIRM YOU UNDERSTAND

Before starting Phase 2 work, please:
1. Read docs/architecture-reference.md
2. Read docs/session-handoffs/5e-bridge-phase1-audit.md (all 565 lines, all 15 topics, full summary)
3. Read this handoff document
4. Confirm you understand the project state, Phase 0 alignment, and Phase 2 purpose
5. Confirm you understand which decisions are locked vs which are open in Phase 2
6. Begin Phase 2 by walking through Decision 1 (PM role data model). Lay out the decision space in plain language, surface tradeoffs, then ask for my answer.
