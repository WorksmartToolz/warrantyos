import { createAdminClient } from '@/lib/supabase/admin'

// ─────────────────────────────────────────────────────────────────────────────
// C10 — Claim Progression (Tier 3 Six Gates status machine)
//
// Source of truth: Decision 30 (twelve-value enum, migration 030) for the value
// set; SOP 1 (Accepted Warranty Claim Lifecycle) + the Denied/Escalated SOPs +
// the two Denial-Escalation workbooks for the transition map and the actor at
// each transition. Decision 30.3 places the transition map and authorized actors
// HERE, in the Server Action layer, NOT in the DB — same discipline Decision 15
// sets for work_plans. The DB CHECK (030) enforces only the closed value set.
//
// Design notes traceable to locked sources:
//   * evidence_evaluation is Gate 3 (arch-ref 4356): the cleared, investigating
//     state (Joint Inspection / causation work) AFTER the ALA is signed.
//   * indistinct_ala_required is the BLOCKED state at Gate 3: the claim rests
//     here while the ALA gate is open. It advances to evidence_evaluation only
//     when the claim's ala_documents row is in state `signed` (Decision 19.7
//     blocking gate). This is the one transition with a DATA precondition, not
//     just an actor check.
//   * Escalation-verdict transitions authorize against a PER-TENANT setting
//     (tenants.settings.escalation_verdict_authorized_role), platform default
//     'team_admin' — the bias-prevention "higher authority" path. A tenant whose
//     process allows a warranty-department reviewer to render the verdict may set
//     it to 'reviewer'. This is a new instance of the locked tenants.settings
//     configurable pattern (decisions log ~1910: read through the Server Action
//     layer with a platform-default fallback). FIRST built settings-key reader;
//     future settings readers can reference this shape.
// ─────────────────────────────────────────────────────────────────────────────

export type ClaimStatus =
  | 'intake_received'
  | 'administrative_validation'
  | 'responsibility_notice'
  | 'evidence_evaluation'
  | 'work_planning_authorization'
  | 'execution_service_report'
  | 'customer_review'
  | 'resolved'
  | 'closed'
  | 'denied'
  | 'escalated'
  | 'indistinct_ala_required'

export type TransitionResult =
  | { success: true; from: ClaimStatus; to: ClaimStatus }
  | { success: false; error: string }

// Authorization class for a transition. Determines WHO may fire it.
//   'operational'         — reviewer OR team_admin (ordinary warranty work)
//   'escalation_verdict'  — role read from tenants.settings, default team_admin
//   'system'              — no human caller; the clock/cron (B-layer) fires it.
//                           A human request for a system transition is rejected.
type AuthClass = 'operational' | 'escalation_verdict' | 'system'

interface TransitionRule {
  to: ClaimStatus
  auth: AuthClass
  // Optional data precondition beyond status+authz. Returns null if satisfied,
  // or an error string if the transition is blocked. Receives the claim row's
  // id and tenant so it can read related tables (e.g. the ALA gate).
  precondition?: (claimId: string, tenantId: string) => Promise<string | null>
}

// ── The transition map ────────────────────────────────────────────────────────
// Keyed by current status → list of legal next statuses. Recovered from the
// three lifecycle SOPs + escalation workbooks (see header). A transition not
// listed here is illegal and rejected regardless of caller role.
const TRANSITIONS: Partial<Record<ClaimStatus, TransitionRule[]>> = {
  // Entry → Initial Claim Review (SOP 1). Warranty professional picks it up.
  intake_received: [
    { to: 'administrative_validation', auth: 'operational' },
  ],

  // Gate 1: Initial Claim Review outcome (SOP 1 three-outcome shape).
  //   valid + responsible entity identified → Notice of Defect (Gate 2)
  //   causation/ownership indistinct → ALA required (blocked state)
  //   fails Evaluation Decision → denied (Denied SOP)
  administrative_validation: [
    { to: 'responsibility_notice', auth: 'operational' },
    { to: 'indistinct_ala_required', auth: 'operational' },
    { to: 'denied', auth: 'operational' },
  ],

  // Blocked at Gate 3 pending a signed ALA (Decision 19.7). The ONLY transition
  // out — into evidence_evaluation — carries the ALA data precondition.
  indistinct_ala_required: [
    {
      to: 'evidence_evaluation',
      auth: 'operational',
      precondition: alaSignedPrecondition,
    },
  ],

  // Gate 3: causation assessment / Joint Inspection, ALA now in force. Rejoins
  // the linear flow at the Notice of Defect step (SOP 1: investigation precedes
  // the corrective-action path).
  evidence_evaluation: [
    { to: 'responsibility_notice', auth: 'operational' },
    { to: 'denied', auth: 'operational' },
  ],

  // Gate 2: Notice of Defect accepted → Work Plan created → Work Planning &
  // Authorization (Gate 4). (Rejection re-sourcing stays within Gate 4 handling
  // per SOP 1; it does not change claim status.)
  responsibility_notice: [
    { to: 'work_planning_authorization', auth: 'operational' },
    { to: 'denied', auth: 'operational' },
  ],

  // Gate 4: Work Authorization approved by customer → execution (Gate 5).
  work_planning_authorization: [
    { to: 'execution_service_report', auth: 'operational' },
  ],

  // Gate 5: repair executed, Service Report submitted + reviewed, Notice of
  // Resolution sent → customer review window (Gate 6).
  execution_service_report: [
    { to: 'customer_review', auth: 'operational' },
  ],

  // Gate 6: three-day customer review window (Decision 21).
  //   customer accepts (or reviewer marks acceptance) → resolved
  //   customer silence past the window → closed (clock-driven; B-layer)
  customer_review: [
    { to: 'resolved', auth: 'operational' },
    { to: 'closed', auth: 'system' },
  ],

  // Reviewer acceptance of the Service Report (arch-ref 5066). Non-terminal;
  // precedes closure. Customer accept/acquiesce → Notice of Closure (arch-ref 5069).
  resolved: [
    { to: 'closed', auth: 'operational' },
  ],

  // Denied (SOP: Denied Warranty Claim Lifecycle).
  //   claimant appeals within window → escalated (customer-initiated)
  //   dispute window lapses, no rebuttal → closed (clock-driven; B-layer)
  denied: [
    { to: 'escalated', auth: 'operational' },
    { to: 'closed', auth: 'system' },
  ],

  // Escalated for executive review (Escalated/Denied SOP + escalation workbooks).
  // The VERDICT is the bias-sensitive "higher authority" action → tenant-settings
  // authorized role, default team_admin.
  //   appeal upheld/reversed → back into processing (workbook: "reversed by
  //     leadership") → work_planning_authorization
  //   appeal denied / final resolution → closed
  escalated: [
    { to: 'work_planning_authorization', auth: 'escalation_verdict' },
    { to: 'closed', auth: 'escalation_verdict' },
  ],

  // resolved/closed reached above; closed is terminal (no outbound transitions).
}

// ── Data precondition: ALA signed gate (Decision 19.7) ──────────────────────────
// The claim cannot advance from indistinct_ala_required until its ala_documents
// row is in state `signed` (claimant_decision = 'accepted' AND signed_at NOT
// NULL). We derive the state from those columns exactly as 19.7 defines it,
// rather than trusting a denormalized status field.
async function alaSignedPrecondition(
  claimId: string,
  tenantId: string
): Promise<string | null> {
  // UNIQUE(claim_id) on ala_documents (arch-ref 3958: at most one ALA per
  // claim) means a plain single-row fetch is exact — no ordering needed.
  const admin = createAdminClient()
  const { data } = await admin
    .from('ala_documents')
    .select('claimant_decision, signed_at')
    .eq('claim_id', claimId)
    .eq('tenant_id', tenantId)
    .maybeSingle()

  if (!data) {
    return 'Cannot advance: no ALA document exists for this claim'
  }
  const signed = data.claimant_decision === 'accepted' && data.signed_at !== null
  if (!signed) {
    return 'Cannot advance: the ALA has not been signed (Decision 19.7 blocking gate)'
  }
  return null
}

// ── Caller authorization ────────────────────────────────────────────────────────
interface CallerProfile {
  tenantId: string
  role: 'team_admin' | 'reviewer' | 'viewer'
}

// Mirrors the codebase authz idiom (manage-team-member / inspections): role,
// tenant, active status, and not-removed are all read from the DB row, never
// from client input. Viewers are authenticated but hold no write authority.
async function fetchCallerProfile(requestedBy: string): Promise<CallerProfile | null> {
  const admin = createAdminClient()
  const { data } = await admin
    .from('users')
    .select('role, tenant_id, status, removed_at')
    .eq('id', requestedBy)
    .single()

  if (!data) return null
  if (data.status !== 'active') return null
  if (data.removed_at) return null
  if (data.role !== 'team_admin' && data.role !== 'reviewer') return null

  return { tenantId: data.tenant_id, role: data.role as CallerProfile['role'] }
}

// Reads the tenant's configured escalation-verdict authorized role. New instance
// of the locked tenants.settings configurable pattern (decisions log ~1910):
// validated read with a platform-default fallback. Absent/invalid → the safe,
// bias-preventing default ('team_admin'), so C10 is correct even before the
// provisioning layer seeds the key.
async function escalationVerdictAuthorizedRole(
  tenantId: string
): Promise<'team_admin' | 'reviewer'> {
  const admin = createAdminClient()
  const { data } = await admin
    .from('tenants')
    .select('settings')
    .eq('id', tenantId)
    .single()

  const configured = (data?.settings as Record<string, unknown> | null)
    ?.escalation_verdict_authorized_role
  // Only 'reviewer' widens the default; any other value (including absent,
  // malformed, or 'viewer') falls back to the higher-authority default.
  return configured === 'reviewer' ? 'reviewer' : 'team_admin'
}

// Given a transition's auth class and the caller, decide if the caller may fire
// it. Returns null if authorized, or an error string if not.
async function authorizeTransition(
  auth: AuthClass,
  caller: CallerProfile
): Promise<string | null> {
  switch (auth) {
    case 'operational':
      // reviewer OR team_admin (fetchCallerProfile already excluded viewer).
      return null
    case 'escalation_verdict': {
      const required = await escalationVerdictAuthorizedRole(caller.tenantId)
      if (required === 'team_admin' && caller.role !== 'team_admin') {
        return 'This escalation verdict requires a team admin (higher authority). Your tenant has not authorized reviewers to render escalation verdicts.'
      }
      // required === 'reviewer' → reviewer OR team_admin both qualify.
      return null
    }
    case 'system':
      // No human may fire a clock-driven transition through this path. The
      // B-layer calls transitionClaimStatusAsSystem() instead.
      return 'This transition is automatic and cannot be triggered manually'
  }
}

// ── The transition executor ─────────────────────────────────────────────────────
interface TransitionContext {
  claimId: string
  tenantId: string
  from: ClaimStatus
  rule: TransitionRule
}

// Shared core: validates the target is a legal transition from the claim's
// CURRENT status (read from the DB, never trusted from the client), runs any
// data precondition, then writes. Used by both the user-facing and system paths.
async function loadAndValidateTransition(
  claimId: string,
  callerTenantId: string,
  to: ClaimStatus
): Promise<TransitionContext | { error: string }> {
  const admin = createAdminClient()
  const { data: claim } = await admin
    .from('claims')
    .select('status, tenant_id')
    .eq('id', claimId)
    .single()

  if (!claim) return { error: 'Claim not found' }
  if (claim.tenant_id !== callerTenantId) {
    return { error: 'Cross-tenant operation not allowed' }
  }

  const from = claim.status as ClaimStatus
  const rule = (TRANSITIONS[from] ?? []).find((r) => r.to === to)
  if (!rule) {
    return { error: `Illegal transition: ${from} → ${to}` }
  }

  return { claimId, tenantId: claim.tenant_id, from, rule }
}

async function commitTransition(ctx: TransitionContext): Promise<TransitionResult> {
  if (ctx.rule.precondition) {
    const blocked = await ctx.rule.precondition(ctx.claimId, ctx.tenantId)
    if (blocked) return { success: false, error: blocked }
  }

  const admin = createAdminClient()
  const { error } = await admin
    .from('claims')
    .update({ status: ctx.rule.to })
    .eq('id', ctx.claimId)
    // Optimistic guard: only write if status is still what we validated, so a
    // concurrent transition cannot be clobbered (last-write-wins avoidance).
    .eq('status', ctx.from)

  if (error) {
    return { success: false, error: `Failed to update claim status: ${error.message}` }
  }
  return { success: true, from: ctx.from, to: ctx.rule.to }
}

// ── Exported: user-initiated transition ─────────────────────────────────────────
export async function transitionClaimStatus(
  claimId: string,
  to: ClaimStatus,
  requestedBy: string
): Promise<TransitionResult> {
  const caller = await fetchCallerProfile(requestedBy)
  if (!caller) return { success: false, error: 'Unauthorized' }

  const loaded = await loadAndValidateTransition(claimId, caller.tenantId, to)
  if ('error' in loaded) return { success: false, error: loaded.error }

  const authError = await authorizeTransition(loaded.rule.auth, caller)
  if (authError) return { success: false, error: authError }

  return commitTransition(loaded)
}

// ── Exported: system-initiated transition (B-layer / cron) ──────────────────────
// The clock-driven transitions (customer_review→closed on 3-day silence;
// denied→closed on lapsed dispute window) have auth class 'system'. They cannot
// be fired by a human. The B-layer calls this with the tenant it is operating on;
// there is no caller role to check — the authority is the clock reaching the
// deadline, which the B-layer is responsible for verifying before calling.
export async function transitionClaimStatusAsSystem(
  claimId: string,
  to: ClaimStatus,
  tenantId: string
): Promise<TransitionResult> {
  const loaded = await loadAndValidateTransition(claimId, tenantId, to)
  if ('error' in loaded) return { success: false, error: loaded.error }

  if (loaded.rule.auth !== 'system') {
    return {
      success: false,
      error: `Transition ${loaded.from} → ${to} is not a system transition`,
    }
  }

  return commitTransition(loaded)
}
