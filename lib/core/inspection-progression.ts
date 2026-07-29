import { createAdminClient } from '@/lib/supabase/admin'

// ─────────────────────────────────────────────────────────────────────────────
// C2 — Inspection Progression (four-value status machine)
//
// Source of truth: migration 021 (inspections) status CHECK enum and its column
// comment for the value set AND the transition semantics; Decision 17 Part B for
// the four-value enum. The 021 status comment is explicit: the happy path is the
// linear forward chain open → in_progress → under_review → issued, issued is
// terminal, and "Backward transitions are not part of the architectural
// commitment at this layer." So the map is forward-only; no reopen edge is
// invented here.
//
// Discipline mirrors C10 (claim-progression): the transition map and authorized
// actors live HERE in the Server Action layer, not in the DB (Decision 17.A.6:
// no triggers at v1). The DB CHECK (021) enforces only the closed value set.
//
// Differences from C10, all traceable to locked sources:
//   * ONE auth class only: 'operational' (reviewer OR team_admin), the same
//     operational-write authorization the built inspection write-path uses
//     (lib/core/inspections.ts, arch-ref 780 / 5145-5148). Inspections have no
//     tenant-configurable verdict, so there is no 'escalation_verdict' class.
//   * NO system path. 021 flags clock_events wiring for inspections as an OPEN,
//     deferred question ("Whether inspections insert clock_events rows ... is
//     flagged open"). Nothing in the locked sources gives an inspection a
//     clock-driven transition, so transitionInspectionStatusAsSystem is
//     deliberately NOT written — that would be improvising architecture.
//   * NO data precondition. Inspection transitions gate on status + actor only.
// ─────────────────────────────────────────────────────────────────────────────

export type InspectionStatus =
  | 'open'
  | 'in_progress'
  | 'under_review'
  | 'issued'

// ── The transition map ────────────────────────────────────────────────────────
// Keyed by current status → legal next status(es). Linear forward chain per the
// 021 status comment. A transition not listed here is illegal and rejected
// regardless of caller role. issued has no outbound entry — it is terminal.
const TRANSITIONS: Partial<Record<InspectionStatus, InspectionStatus[]>> = {
  open: ['in_progress'],
  in_progress: ['under_review'],
  under_review: ['issued'],
  // issued: terminal — no outbound transitions.
}

// ── Caller authorization ────────────────────────────────────────────────────────
// Operational-write authorization identical to the inspection write-path
// (lib/core/inspections.ts): reviewer OR team_admin, active, not removed. Role,
// tenant, and status are read from the DB row, never from client input. Viewers
// are authenticated but hold no write authority.
interface CallerProfile {
  tenantId: string
}

async function fetchCallerProfile(requestedBy: string): Promise<CallerProfile | null> {
  const admin = createAdminClient()
  const { data } = await admin
    .from('users')
    .select('role, tenant_id, status, removed_at')
    .eq('id', requestedBy)
    .single()

  if (!data) return null
  if (data.role !== 'reviewer' && data.role !== 'team_admin') return null
  if (data.status !== 'active') return null
  if (data.removed_at) return null

  return { tenantId: data.tenant_id }
}

// ── The transition executor ─────────────────────────────────────────────────────
// The caller needs the claim_id for cache revalidation after a successful write,
// so a successful transition returns it alongside the from/to pair.
export type InspectionTransitionSuccess = {
  success: true
  from: InspectionStatus
  to: InspectionStatus
  claimId: string
}
export type InspectionTransitionOutcome =
  | InspectionTransitionSuccess
  | { success: false; error: string }

export async function transitionInspectionStatus(
  inspectionId: string,
  to: InspectionStatus,
  requestedBy: string
): Promise<InspectionTransitionOutcome> {
  const caller = await fetchCallerProfile(requestedBy)
  if (!caller) return { success: false, error: 'Unauthorized' }

  const admin = createAdminClient()

  // Read the CURRENT status and owning tenant/claim from the DB — never trust
  // the client for the "from" state. Cross-tenant guard mirrors the write-path.
  const { data: inspection } = await admin
    .from('inspections')
    .select('status, tenant_id, claim_id')
    .eq('id', inspectionId)
    .single()

  if (!inspection) return { success: false, error: 'Inspection not found' }
  if (inspection.tenant_id !== caller.tenantId) {
    return { success: false, error: 'Cross-tenant operation not allowed' }
  }

  const from = inspection.status as InspectionStatus
  const legal = TRANSITIONS[from] ?? []
  if (!legal.includes(to)) {
    return { success: false, error: `Illegal transition: ${from} → ${to}` }
  }

  // Optimistic guard: only write if status is still what we validated, so a
  // concurrent transition cannot be clobbered (last-write-wins avoidance).
  const { error } = await admin
    .from('inspections')
    .update({ status: to })
    .eq('id', inspectionId)
    .eq('status', from)

  if (error) {
    return { success: false, error: `Failed to update inspection status: ${error.message}` }
  }

  return { success: true, from, to, claimId: inspection.claim_id }
}
