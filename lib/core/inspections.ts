import { createAdminClient } from '@/lib/supabase/admin'
import { validateTenantEditableDefaultsReference } from '@/lib/core/tenant-editable-defaults'

export type CreateInspectionResult =
  | { success: true; id: string }
  | { success: false; error: string }

export interface CreateInspectionInput {
  claim_id: string
  performed_by: string // 'warrantor' | 'third_party' — DB CHECK enforces
  paid_by: string // 'warrantor' | 'claimant' | 'third_party' — DB CHECK enforces
  inspection_type_id: string
  inspection_trigger_id: string
}

// ── Internal helpers ──────────────────────────────────────────────────────────

interface CallerProfile {
  tenantId: string
}

// Operational-write authorization per arch-ref 780 / 5145-5148:
// creating an inspection is ordinary operational work, so the authorized
// set is 'reviewer' OR 'team_admin' — NOT team_admin alone (that gate is for
// governance actions like team management). Viewers cannot create.
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

// ── Exported functions ────────────────────────────────────────────────────────

export async function insertInspection(
  input: CreateInspectionInput,
  requestedBy: string
): Promise<CreateInspectionResult> {
  const caller = await fetchCallerProfile(requestedBy)
  if (!caller) return { success: false, error: 'Unauthorized' }

  const admin = createAdminClient()

  // Cross-tenant guard on the parent claim (arch-ref tenant_id-sync invariant,
  // arch-ref 168-177): the child's tenant_id must match the parent claim's.
  const { data: claim } = await admin
    .from('claims')
    .select('tenant_id')
    .eq('id', input.claim_id)
    .single()

  if (!claim) return { success: false, error: 'Claim not found' }
  if (claim.tenant_id !== caller.tenantId) {
    return { success: false, error: 'Cross-tenant operation not allowed' }
  }

  // Tenant-editable defaults validation via the single canonical helper
  // (Decision 17.A.6 commitment 1). The snapshot value comes from the
  // validated row the helper returns — never from client input.
  const typeRow = await validateTenantEditableDefaultsReference(
    'inspection_types',
    input.inspection_type_id,
    caller.tenantId
  )
  if (!typeRow) return { success: false, error: 'Invalid inspection type' }

  const triggerRow = await validateTenantEditableDefaultsReference(
    'inspection_triggers',
    input.inspection_trigger_id,
    caller.tenantId
  )
  if (!triggerRow) return { success: false, error: 'Invalid inspection trigger' }

  // Service-role insert. status is omitted — the DB defaults it to 'open'
  // (arch-ref inspections schema). Snapshots captured from the validated rows
  // per the FK + Snapshot Pattern (17.A.2).
  const { data: inserted, error } = await admin
    .from('inspections')
    .insert({
      tenant_id: caller.tenantId,
      claim_id: input.claim_id,
      performed_by: input.performed_by,
      paid_by: input.paid_by,
      inspection_type_id: input.inspection_type_id,
      inspection_type_value: typeRow.value,
      inspection_trigger_id: input.inspection_trigger_id,
      inspection_trigger_value: triggerRow.value,
    })
    .select('id')
    .single()

  if (error || !inserted) {
    return { success: false, error: `Failed to create inspection: ${error?.message ?? 'unknown error'}` }
  }

  return { success: true, id: inserted.id }
}
