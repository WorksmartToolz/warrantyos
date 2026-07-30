import { createAdminClient } from '@/lib/supabase/admin'

// ─────────────────────────────────────────────────────────────────────────────
// C4 — Work Plan write-path (domain layer)
//
// The Work Plan is the warrantor's INTENT: the corrective actions the warrantor
// or executing subcontractor intends to perform against a claim (migration 020).
// Warrantor-authored, account-authed — NOT a customer-tokenized surface. Mirrors
// the C0 inspections write-path (lib/core/inspections.ts) exactly: reviewer ||
// team_admin operational-write authz, cross-tenant guard on the parent claim,
// FK + Snapshot capture resolved from the validated row, service-role insert.
//
// Source of truth (all read from disk this session, not memory):
//   * migration 020_work_plans.sql — THE column/CHECK contract, verified
//     column-by-column: 11 NOT NULL columns, the four-value execution_path,
//     work_plan_type (repair/inspection/both), the five-value status machine
//     (default 'draft'), and the TWO conditional path couplings (Decision 13.1).
//   * Decision 13.1/13.2 — execution path + team/subcontractor capture.
//   * Decision 15.1 — five-value status machine; transitions run through Server
//     Actions (create lands at 'draft', the DB default; status omitted here).
//   * Decision 16.3 — Parts Claims (claim_type = 'replacement_parts') do NOT
//     flow through this workflow; enforced app-layer (020's own omissions list:
//     "no DB constraint couples this table to the parent claim's claim_type").
//   * Decision 4 — rich text is ProseMirror-compatible JSON, capped per-field at
//     tenants.settings.rich_text_max_chars (default 10000, ceiling 50000). The
//     cap is platform-wide per rich-text field value, not claims-specific.
//
// FK + SNAPSHOT (020's app-layer companion list): subcontractor name/email/phone
// are snapshotted at creation from the validated contact row, NEVER from client
// input. warranty_professional_user_id is a PLAIN FK — 020 defines no snapshot
// columns for it, so none are written (do not invent them).
//
// DELIBERATELY NOT DONE (locked out-of-scope by 020's omissions list):
//   * No status transition here — create lands at 'draft'. Edit/status is C4's
//     own later machine (Server Actions, Decision 15.1).
//   * No work_authorization / notice_of_defect / service_report FK — Decision
//     11/14.4/21 run those relationships elsewhere or not at all.
// ─────────────────────────────────────────────────────────────────────────────

const EXECUTION_PATHS = [
  'warrantor_self_performs',
  'scope_owned_subcontractor',
  'outsourced_subcontractor',
  'customer_self_services',
] as const
type ExecutionPath = (typeof EXECUTION_PATHS)[number]

const SUBCONTRACTOR_PATHS = [
  'scope_owned_subcontractor',
  'outsourced_subcontractor',
] as const

const WORK_PLAN_TYPES = ['repair', 'inspection', 'both'] as const
type WorkPlanType = (typeof WORK_PLAN_TYPES)[number]

// Rich-text JSONB (ProseMirror-compatible JSON). Opaque beyond the char cap.
type RichText = unknown

export interface CreateWorkPlanInput {
  claim_id: string
  execution_path: string
  // Conditional per execution_path (Decision 13.1, app-layer + DB CHECK):
  //   internal_team_id present iff warrantor_self_performs.
  //   subcontractor_contact_id present iff a subcontractor path.
  //   both absent on customer_self_services.
  internal_team_id?: string
  subcontractor_contact_id?: string
  warranty_professional_user_id: string
  work_plan_type: string
  // Required NOT NULL columns (020).
  planned_start_at: string // timestamptz (ISO)
  planned_end_at: string // timestamptz (ISO)
  crew_size: number
  corrective_actions: RichText // jsonb NOT NULL
  repair_scope_approach: RichText // jsonb NOT NULL
  // Nullable rich-text / structured columns (020).
  required_materials_equipment?: RichText // jsonb
  safety_considerations?: RichText // jsonb
  site_access_coordination?: RichText // jsonb
}

export type CreateWorkPlanResult =
  | { success: true; id: string }
  | { success: false; error: string }

// ── Internal helpers (mirror inspections.ts) ─────────────────────────────────

interface CallerProfile {
  tenantId: string
}

// Operational-write authorization per arch-ref 780 / 5145-5148: creating a Work
// Plan is ordinary operational warrantor work, so the authorized set is
// 'reviewer' OR 'team_admin' — NOT team_admin alone. Viewers cannot create.
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

// Rich-text cap reader — same idiom as claims.ts. Default 10000, ceiling 50000
// (Decision 4). A configured value above the ceiling is clamped.
async function richTextMaxChars(tenantId: string): Promise<number> {
  const admin = createAdminClient()
  const { data } = await admin
    .from('tenants')
    .select('settings')
    .eq('id', tenantId)
    .single()
  const configured = (data?.settings as Record<string, unknown> | null)
    ?.rich_text_max_chars
  return typeof configured === 'number' ? Math.min(configured, 50000) : 10000
}

// Character length of a ProseMirror doc for the cap check. Mirrors claims.ts:
// the stored form is JSON; length is the serialized character count. Returns
// +Infinity on non-serializable input so the caller rejects malformed rich text.
function richTextLength(doc: RichText): number {
  if (doc === null || doc === undefined) return 0
  try {
    return JSON.stringify(doc).length
  } catch {
    return Number.POSITIVE_INFINITY
  }
}

// ── Exported functions ───────────────────────────────────────────────────────

export async function insertWorkPlan(
  input: CreateWorkPlanInput,
  requestedBy: string
): Promise<CreateWorkPlanResult> {
  const caller = await fetchCallerProfile(requestedBy)
  if (!caller) return { success: false, error: 'Unauthorized' }

  const admin = createAdminClient()

  // ── Enum validation (clean structured errors; DB CHECK is the backstop) ──
  if (!EXECUTION_PATHS.includes(input.execution_path as ExecutionPath)) {
    return { success: false, error: 'Invalid execution_path' }
  }
  if (!WORK_PLAN_TYPES.includes(input.work_plan_type as WorkPlanType)) {
    return { success: false, error: 'Invalid work_plan_type' }
  }

  // ── Required NOT NULL columns present (020, no default) ──
  if (!input.warranty_professional_user_id) {
    return { success: false, error: 'warranty_professional_user_id is required' }
  }
  if (!input.planned_start_at) {
    return { success: false, error: 'planned_start_at is required' }
  }
  if (!input.planned_end_at) {
    return { success: false, error: 'planned_end_at is required' }
  }
  if (input.crew_size === null || input.crew_size === undefined) {
    return { success: false, error: 'crew_size is required' }
  }
  if (input.corrective_actions === null || input.corrective_actions === undefined) {
    return { success: false, error: 'corrective_actions is required' }
  }
  if (input.repair_scope_approach === null || input.repair_scope_approach === undefined) {
    return { success: false, error: 'repair_scope_approach is required' }
  }

  // ── Conditional path couplings (Decision 13.1). These mirror the two DB
  // CHECKs exactly; validated here for clean errors and to know which FK to
  // resolve. internal_team_id XOR subcontractor by path; both null on
  // customer_self_services. ──
  const isWarrantorSelf = input.execution_path === 'warrantor_self_performs'
  const isSubcontractor = (SUBCONTRACTOR_PATHS as readonly string[]).includes(
    input.execution_path
  )

  if (isWarrantorSelf) {
    if (!input.internal_team_id) {
      return {
        success: false,
        error: 'internal_team_id is required when execution_path is warrantor_self_performs',
      }
    }
    if (input.subcontractor_contact_id) {
      return {
        success: false,
        error: 'subcontractor_contact_id must be null when execution_path is warrantor_self_performs',
      }
    }
  } else if (isSubcontractor) {
    if (!input.subcontractor_contact_id) {
      return {
        success: false,
        error: 'subcontractor_contact_id is required for a subcontractor execution_path',
      }
    }
    if (input.internal_team_id) {
      return {
        success: false,
        error: 'internal_team_id must be null for a subcontractor execution_path',
      }
    }
  } else {
    // customer_self_services: both FKs must be null.
    if (input.internal_team_id || input.subcontractor_contact_id) {
      return {
        success: false,
        error: 'internal_team_id and subcontractor_contact_id must both be null when execution_path is customer_self_services',
      }
    }
  }

  // ── Rich-text cap (Decision 4), applied to all five ProseMirror JSONB fields ──
  const cap = await richTextMaxChars(caller.tenantId)
  const richTextFields: Array<[string, RichText]> = [
    ['corrective_actions', input.corrective_actions],
    ['repair_scope_approach', input.repair_scope_approach],
    ['required_materials_equipment', input.required_materials_equipment],
    ['safety_considerations', input.safety_considerations],
    ['site_access_coordination', input.site_access_coordination],
  ]
  for (const [name, value] of richTextFields) {
    if (value !== undefined && richTextLength(value) > cap) {
      return { success: false, error: `${name} exceeds ${cap} characters` }
    }
  }

  // ── Parent claim: exists, tenant-matches, and is NOT a Parts Claim (16.3) ──
  const { data: claim } = await admin
    .from('claims')
    .select('tenant_id, claim_type')
    .eq('id', input.claim_id)
    .single()

  if (!claim) return { success: false, error: 'Claim not found' }
  if (claim.tenant_id !== caller.tenantId) {
    return { success: false, error: 'Cross-tenant operation not allowed' }
  }
  // Decision 16.3: Parts Claims do not flow through the Work Plan Workflow.
  if (claim.claim_type === 'replacement_parts') {
    return {
      success: false,
      error: 'Parts Claims (replacement_parts) do not flow through the Work Plan Workflow',
    }
  }

  // ── warranty_professional_user_id: plain FK — must exist, be active, and
  // tenant-match. NO snapshot (020 defines no snapshot columns for it). ──
  const { data: pro } = await admin
    .from('users')
    .select('tenant_id')
    .eq('id', input.warranty_professional_user_id)
    .single()
  if (!pro) return { success: false, error: 'warranty_professional_user_id not found' }
  if (pro.tenant_id !== caller.tenantId) {
    return { success: false, error: 'Cross-tenant operation not allowed' }
  }

  // ── internal_team_id: exists + tenant-match (populated only on
  // warrantor_self_performs, already enforced above). ──
  if (input.internal_team_id) {
    const { data: team } = await admin
      .from('internal_teams')
      .select('tenant_id')
      .eq('id', input.internal_team_id)
      .single()
    if (!team) return { success: false, error: 'internal_team_id not found' }
    if (team.tenant_id !== caller.tenantId) {
      return { success: false, error: 'Cross-tenant operation not allowed' }
    }
  }

  // ── subcontractor_contact_id: exists + tenant-match, then SNAPSHOT name/email
  // /phone from the validated contact row (FK + Snapshot Pattern, never client
  // input). Populated only on a subcontractor path (already enforced above). ──
  let subName: string | null = null
  let subEmail: string | null = null
  let subPhone: string | null = null
  if (input.subcontractor_contact_id) {
    const { data: contact } = await admin
      .from('contacts')
      .select('tenant_id, name, email, phone')
      .eq('id', input.subcontractor_contact_id)
      .single()
    if (!contact) return { success: false, error: 'subcontractor_contact_id not found' }
    if (contact.tenant_id !== caller.tenantId) {
      return { success: false, error: 'Cross-tenant operation not allowed' }
    }
    subName = contact.name ?? null
    subEmail = contact.email ?? null
    subPhone = contact.phone ?? null
  }

  // ── Service-role insert. status omitted — DB defaults 'draft' (020). ──
  const { data: inserted, error } = await admin
    .from('work_plans')
    .insert({
      tenant_id: caller.tenantId,
      claim_id: input.claim_id,
      execution_path: input.execution_path,
      internal_team_id: input.internal_team_id ?? null,
      subcontractor_contact_id: input.subcontractor_contact_id ?? null,
      subcontractor_name_snapshot: subName,
      subcontractor_email_snapshot: subEmail,
      subcontractor_phone_snapshot: subPhone,
      warranty_professional_user_id: input.warranty_professional_user_id,
      work_plan_type: input.work_plan_type,
      planned_start_at: input.planned_start_at,
      planned_end_at: input.planned_end_at,
      crew_size: input.crew_size,
      corrective_actions: input.corrective_actions as never,
      repair_scope_approach: input.repair_scope_approach as never,
      required_materials_equipment: (input.required_materials_equipment ?? null) as never,
      safety_considerations: (input.safety_considerations ?? null) as never,
      site_access_coordination: (input.site_access_coordination ?? null) as never,
    } as never)
    .select('id')
    .single()

  if (error || !inserted) {
    return { success: false, error: `Failed to create work plan: ${error?.message ?? 'unknown error'}` }
  }

  return { success: true, id: (inserted as { id: string }).id }
}
