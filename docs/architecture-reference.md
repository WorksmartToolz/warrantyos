# WarrantyOS — Architectural Reference (Prototype Phase)

## What This Platform Is

WarrantyOS is a warranty governance platform for mid-sized EPC warranty operations in solar/renewables. The platform serves warranty operations teams managing warranty obligations on solar construction projects. Its primary value is operational integrity, defensibility, and structured warranty governance — not customer service optimization.

## Core Operational Philosophy

The platform operates per the following named principles:

**Obligation-Not-Assistance:** The warrantor's role is to honor contractual obligations, not to provide service beyond those obligations. The platform supports honest evaluation of obligations and does not pressure toward customer satisfaction at the expense of structural integrity.

**Burden of Proof:** The claimant bears responsibility for demonstrating the basis of warranty claims. The warrantor evaluates evidence; the warrantor does not investigate claims at warranty's expense outside specific structural contexts.

**Methodological Privacy:** Customer-facing communications include operational coordination content. Internal cost details, reviewer notes, and warranty governance reasoning are not customer-visible. The platform structurally separates customer-facing and internal views of the same records.

**Structural Integrity:** The platform's architecture enforces methodology consistency. Reviewers cannot bypass gates, skip required reasoning capture, or extend authority beyond their tier. Structure protects the platform's defensibility.

**Defensibility:** Every consequential decision generates audit-quality reasoning. The audit trail produces externally-usable evidence for regulatory inquiry, contract dispute, or litigation as a byproduct of normal operations.

**System-Managed Clock:** All deadlines, response windows, and time-bound state transitions are managed by the platform, not by reviewers. Manual clock manipulation is structurally prevented.

**Operational Transparency:** Significant claim events are visible to the warranty team broadly via shared dashboards, not solely to the assigned reviewer. Accountability requires visibility.

**Single Reviewer Continuity:** A claim is owned by one reviewer from pickup through outcome. Reassignment is a discrete authority-governed event with audit capture.

**Data Portability:** Warrantor organizations can export their data at any time in structured formats. The platform does not lock data in.

**Stateless Customer Interaction:** Customers do not have platform accounts or logins. All customer engagement is via tokenized email links to focused interfaces. Each customer interaction is structurally independent.

## Core Identifiers

**WarrantyID:** The platform's master operational anchor. Format default `WID-YYYY-NNNNNN` (per-org configurable). Every warranty agreement on a project has a unique WarrantyID. Used internally for warranty agreement context.

**ClaimID:** The point of reference for routine departmental activities and all customer-facing communications. Format default `[WarrantyID]-C[NNNN]` (per-org configurable). Inherits from WarrantyID.

**Tenant:** The highest-level identifier. Each warrantor organization is a tenant. All data is structurally scoped to a tenant. No cross-tenant operations exist except authorized platform administration.

## The Six Evaluation Gates (Claim Review Stage)

Every claim that enters Claim Review passes through six structured gates in sequence:

**Gate 1: Administrative Validation**
Four checks: WarrantyID Valid, Within Warranty Period, Claimant Authorized, Not Duplicate.
Three outcomes: Pass, Correction Required, Deny.

**Gate 2: Coverage Validation**
Four evaluation considerations: Warranted Scope, Exclusions, Maintenance vs. Defect, Other Contractual Considerations.
Seven outcomes: Pass, five Deny subtypes (Out of Scope, Excluded by Contract, Maintenance/Operational, Unauthorized Repairs, Customer-Provided Equipment), Classify as Indistinct.

**Gate 3: Evidence Evaluation**
Three outcomes: Pass, Request Additional Evidence, Deny Insufficient Information.
Information Request workflow: up to 3 attempts, 48-hour standard / 24-hour emergency response window, 2 business days minimum spacing, 15 business days aggregate window.

**Gate 4: Causation Evaluation**
Three causation tests applied disjunctively: But For Test, Failure to Perform Test, Because Of Test.
Application rule: at least one test satisfied with reasonable evidence support.
Four outcomes: Pass, Deny No Causation Established, Classify as Indistinct, Return to Gate 3.

**Gate 5: Failure Mode Assessment**
Three questions: What Failed, How It Failed, Consistent With (Workmanship/Material/External/Indeterminate).
Two outcomes: Pass, Request Additional Evidence.

**Gate 6: Responsibility Classification**
Nine-category taxonomy: Manufacturing Defect, Design-Induced Condition, Installation Defect Warrantor Performed, Installation Defect Third-Party Performed, Maintenance/Misuse, Environmental/External Cause, Vendor-Supplied Component Issue, Indistinct Claim, Goodwill.
Four outcomes: Classify Warranty Obligation, Classify Goodwill, Reconsider Prior Gate, Request Additional Evidence.

## Six Final Claim Review Outcomes

After the six gates and Risk Evaluation, a claim resolves to one of six outcomes:

1. Accepted — Standard Processing
2. Accepted — Pending Vendor Review (conditional)
3. Coverage Confirmed — Direct Engagement Required
4. Indistinct Claim — ALA Required
5. Denied — Non-Warrantable
6. Escalated — Significant Claim (temporary; resolves to one of 1-4 after CRC)

## Three Escalation Pathways

**Pathway A: Significant Claim Escalation** (internal-initiated, investigation-focused)
Triggered by Risk Evaluation. Seven-phase workflow including CRC convening, investigation, corrective actions. Switchable per organization.

**Pathway B: Disputed Claim Escalation** (external-initiated, dispute-focused)
Triggered by claimant rebuttal. Single-level escalation; senior management final resolution. Three trigger types: Denial Dispute, Completion Dispute, ALA Outcome Dispute.

**Pathway C: Authority Threshold Escalation** (internal-initiated, routing-focused)
Triggered when decisions exceed reviewer authority. Two request modes: Standard Authority Request and Guidance Request.

## Four Work Plan Execution Paths

**Path 1: Warrantor Self-Performs** (in-house team)
**Path 2A: Scope-Owned Subcontractor** (original installer with active warranty obligation)
**Path 2B: Outsourced Subcontractor** (procured via RFQ)
**Path 3: Customer Self-Services** (customer performs with warrantor reimbursement; includes locked inspection waiver disclaimer)

## Lifecycle Stages

1. Registration (issues WarrantyID after tiered gate completion)
2. Claim Intake (stateless customer interaction via tokenized link)
3. Claim Review (Six Gates + Risk Evaluation + Final Outcome)
4. Escalation Pathways (Pathways A, B, C)
5. Work Plan Workflow (four execution paths through closure)
6. Cost Tracking (twelve cost fields with variance and recovery tracking)

## Customer-Facing Communications Inventory

1. Automated Submission Confirmation
2. Notice of Receipt
3. Notice of Acceptance — Standard Processing
4. Notice of Acceptance — Pending Vendor Review
5. Notice of Coverage Confirmed — Direct Engagement Required
6. Notice of Indistinct Classification + ALA Request
7. Notice of Denial
8. Notice of Investigation in Progress
9. Information Requests
10. Work Plan Transmission
11. Work Plan Alteration Notice
12. Notice of Completion
13. Notice of Closure
14. Pathway B notices (right to dispute, final resolution)

## Role Tier Model

The platform uses four roles across two distinct tiers:

**Platform Admin** — Provider-side. Full cross-tenant administrative authority. Manages tenant provisioning, platform admin accounts, and platform-level configuration. Stored as `is_platform_admin: true` in Supabase Auth user_metadata. No row in `public.users`. This role name is intentional and stable — it is not renamed to "Super Admin" or any other term.

**Team Admin** — Organization-side. Tenant-scoped. Manages team membership (invitations, role changes, suspend, remove) and tenant settings within their own tenant only. No cross-tenant access. Stored as `role = 'team_admin'` in `public.users`.

**Reviewer** — Operational user. Performs claim evaluation work within a tenant. Stored as `role = 'reviewer'` in `public.users`.

**Viewer** — Read-only user within a tenant. Stored as `role = 'viewer'` in `public.users`.

### Team Admin Seat Count

Each tenant has a `max_team_admins` integer column (default 3) representing the contracted number of Team Admin seats. This value is set at provisioning time and is configurable per contract. Seat count enforcement (blocking role assignments that would exceed the limit) is implemented in Session 5b.

### Session 5b Deferred Items

The following tenant admin capabilities are deferred to Session 5b:
- Invitation flow for adding team members from within the tenant app
- Role management actions: promote, demote, suspend, remove
- Tenant settings page
- Team Admin seat count enforcement logic


## Technology Stack

- Frontend: Next.js 14+ with App Router
- Styling: Tailwind CSS with shadcn/ui components
- Database: PostgreSQL via Supabase with Row-Level Security
- Authentication: Supabase Auth
- File Storage: Supabase Storage
- Email: Resend
- Hosting: Vercel
- Version Control: Git with GitHub

## Prototype Scope

The prototype demonstrates the core lifecycle workflow end-to-end:

In Scope:
- Tenant setup and basic configuration
- WarrantyID registration with structured data categories
- Warranty Coverage Matrix with Equipment and Workmanship sub-tables
- Claim Intake via tokenized link
- The Six Gates with structured reasoning capture
- Basic notice generation and email delivery
- Audit trail data layer
- Operations Dashboard with claim queue
- One execution path end-to-end (Path 1: Warrantor Self-Performs)
- Basic closure mechanics

Out of Scope (defer to post-prototype):
- Full configurability layer
- Path 2A/2B/3 work plan execution
- Significant Claim Pathway
- Knowledge Asset library
- Cost tracking beyond basic capture
- Sophisticated reporting
- Data migration tooling
- Multi-tenant operations at scale