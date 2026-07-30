import { createAdminClient } from '@/lib/supabase/admin'

// ─────────────────────────────────────────────────────────────────────────────
// C3 — Claim Intake write-path (domain layer)
//
// Source of truth (all read from disk this session, not memory):
//   * migration 027_claim_intake.sql — THE 27-column contract: seven NOT NULL
//     hard columns, three CHECK enums, the JSONB fields, submitter FK+Snapshot,
//     the intake_token pair. Verified column-by-column.
//   * Decision 27 (27.4) — claim eligibility is warranty_id IS NOT NULL; the
//     customer files the claim; the row is born at submission in
//     status 'intake_received' (no draft state).
//   * Decision 20 (20.4/20.6) — submitter capture is FK + Snapshot: name/email
//     ALWAYS written as snapshot; submitter_contact_id optional (null for a
//     one-off third party). Claim filing by an O&M Provider is INFORMATIONAL
//     (available at v1, NOT gated) — the binding-commitment gate (Cat 3 #9) is
//     for ALA/work-auth/service-report acceptance, none of which is intake.
//   * Decision 4 — rich text is ProseMirror-compatible JSON, capped at
//     tenants.settings.rich_text_max_chars (default 10000, ceiling 50000).
//   * tokens.ts (Decision 35) — validate/consume live in the ACTION layer;
//     this domain function is token-agnostic and takes an explicit tenantId.
//
// AUTHORIZATION SEAM (dug to the floor this session): claim intake is
// EXCLUSIVELY customer-tokenized (arch-ref gate mechanics 5529: "Customer clicks
// a tokenized link… token validation runs first"). There is NO staff/account
// manual-entry path in the locked design — do not add one. The customer has no
// users row, so this core function does NOT take a requestedBy and does NOT call
// fetchCallerProfile (that is the inspections/account pattern). Its tenant anchor
// is the PARENT warranty_registration, resolved and passed by the action layer
// after it validates the entry token. Minting of that token is the issuance
// subsystem (unbuilt) — a finished external edge, not deferred work here.
//
// DELIBERATELY NOT DONE (locked as out-of-scope by 027's own omissions list):
//   * No claim_type_data shape invented for the six unsettled types — only
//     replacement_parts is settled (validated below); the rest pass through as
//     opaque JSONB, exactly like clock_events.payload.
//   * No file/upload handling — supporting_documents is a declaration checklist
//     (a set of category enums), NOT an attachment store. No file, no URL.
//   * No priority_emergency — is_emergency is the built field (naming collapse).
//   * No DB-coupling of conditional fields — enforced app-layer here, per 17.A.6.
// ─────────────────────────────────────────────────────────────────────────────

// The seven claim_type CHECK values (027 claims_claim_type_check).
const CLAIM_TYPES = [
  'billable_service_request',
  'design',
  'equipment',
  'foundation',
  'replacement_parts',
  'tracker',
  'workmanship',
] as const
type ClaimType = (typeof CLAIM_TYPES)[number]

const EQUIPMENT_STATUSES = ['online', 'offline'] as const
type EquipmentStatus = (typeof EQUIPMENT_STATUSES)[number]

const LOTO_REQUIREMENTS = [
  'not_required',
  'required_claimant_responsible',
  'required_warrantor_responsible',
] as const
type LotoRequirement = (typeof LOTO_REQUIREMENTS)[number]

// Rich-text JSONB (ProseMirror-compatible JSON). Opaque to this layer beyond the
// character cap; the client sends the doc structure. `unknown` not `any` so the
// cap check must coerce explicitly.
type RichText = unknown

export interface CreateClaimIntakeInput {
  warranty_registration_id: string
  // Seven required hard columns (027 NOT NULL, no default).
  claim_type: string
  date_of_defect_incident: string // date (ISO yyyy-mm-dd)
  equipment_status: string
  loto_requirement: string
  detailed_description: RichText // jsonb NOT NULL
  submitter_name: string
  submitter_email: string
  // Emergency (Decision 27.5). is_emergency lives on the 016 shell; the intake
  // form writes it. emergency_details required when is_emergency (app-layer).
  is_emergency?: boolean
  emergency_details?: RichText // jsonb, required when is_emergency
  emergency_stabilized_at?: string // timestamptz, customer-reported (27.5)
  // Offline detail — required when equipment_status = 'offline' (app-layer).
  offline_condition_explanation?: RichText // jsonb
  // Declaration checklist (a set of category enums), NOT an attachment store.
  supporting_documents?: unknown // jsonb
  required_docs_provided?: boolean // defaults false in DB
  // Submitter FK + Snapshot (20.4). Optional FK; snapshots above are mandatory.
  submitter_contact_id?: string
  // Direct O&M text capture (four columns, 022 parallel — NOT an FK, Decision 20).
  om_provider_company?: string
  om_contact_name?: string
  om_contact_phone?: string
  om_contact_email?: string
  // Supply-only ship-to / recipient (nullable text).
  ship_to_street?: string
  ship_to_city?: string
  ship_to_state?: string
  ship_to_zip?: string
  recipient_name?: string
  recipient_phone?: string
  // Per-claim_type JSONB. Only replacement_parts is settled; others opaque.
  claim_type_data?: unknown // jsonb
}

export type CreateClaimIntakeResult =
  | { success: true; id: string }
  | { success: false; error: string }

// Rich-text cap reader — mirrors escalationVerdictAuthorizedRole's
// tenants.settings scalar idiom (claim-progression.ts). Default 10000, hard
// ceiling 50000 (Decision 4). A configured value above the ceiling is clamped.
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

// Character length of a ProseMirror doc for the cap check. The stored form is
// JSON; the cap is on the serialized character count. Returns +Infinity on
// non-serializable input so the caller rejects malformed rich text explicitly.
function richTextLength(doc: RichText): number {
  if (doc === null || doc === undefined) return 0
  try {
    return JSON.stringify(doc).length
  } catch {
    return Number.POSITIVE_INFINITY
  }
}

export async function createClaimIntake(
  input: CreateClaimIntakeInput,
  tenantId: string
): Promise<CreateClaimIntakeResult> {
  const admin = createAdminClient()

  // ── Enum validation (clean structured errors; DB CHECK is the backstop) ──
  if (!CLAIM_TYPES.includes(input.claim_type as ClaimType)) {
    return { success: false, error: 'Invalid claim_type' }
  }
  if (!EQUIPMENT_STATUSES.includes(input.equipment_status as EquipmentStatus)) {
    return { success: false, error: 'Invalid equipment_status' }
  }
  if (!LOTO_REQUIREMENTS.includes(input.loto_requirement as LotoRequirement)) {
    return { success: false, error: 'Invalid loto_requirement' }
  }

  // ── Required hard columns present (027 NOT NULL, no default) ──
  if (!input.date_of_defect_incident) {
    return { success: false, error: 'date_of_defect_incident is required' }
  }
  if (!input.submitter_name?.trim()) {
    return { success: false, error: 'submitter_name is required' }
  }
  if (!input.submitter_email?.trim()) {
    return { success: false, error: 'submitter_email is required' }
  }
  if (input.detailed_description === null || input.detailed_description === undefined) {
    return { success: false, error: 'detailed_description is required' }
  }

  // ── Rich-text cap (Decision 4), applied to all three rich-text fields ──
  const cap = await richTextMaxChars(tenantId)
  if (richTextLength(input.detailed_description) > cap) {
    return { success: false, error: `detailed_description exceeds ${cap} characters` }
  }
  if (input.emergency_details !== undefined && richTextLength(input.emergency_details) > cap) {
    return { success: false, error: `emergency_details exceeds ${cap} characters` }
  }
  if (
    input.offline_condition_explanation !== undefined &&
    richTextLength(input.offline_condition_explanation) > cap
  ) {
    return { success: false, error: `offline_condition_explanation exceeds ${cap} characters` }
  }

  // ── Conditional couplings (arch-ref: "present only when…"; app-layer, no DB CHECK) ──
  if (input.is_emergency) {
    if (input.emergency_details === null || input.emergency_details === undefined) {
      return { success: false, error: 'emergency_details is required when is_emergency is true' }
    }
    if (!input.emergency_stabilized_at) {
      // 27.5: emergency_stabilized_at is customer-reported and required when emergency.
      return {
        success: false,
        error: 'emergency_stabilized_at is required when is_emergency is true',
      }
    }
  }
  if (input.equipment_status === 'offline') {
    if (
      input.offline_condition_explanation === null ||
      input.offline_condition_explanation === undefined
    ) {
      return {
        success: false,
        error: 'offline_condition_explanation is required when equipment_status is offline',
      }
    }
  }

  // ── claim_type_data: validate ONLY replacement_parts (the one settled shape).
  // The other six are deliberately unsettled — pass through opaque, do not invent.
  if (input.claim_type === 'replacement_parts') {
    const d = input.claim_type_data
    if (d === null || d === undefined || typeof d !== 'object') {
      return {
        success: false,
        error: 'claim_type_data is required for replacement_parts claims',
      }
    }
  }

  // ── Parent registration: exists, tenant-matches, and is claim-eligible ──
  // Tenant anchor is the parent registration (the token-authed customer has no
  // users row). Cross-tenant guard mirrors inspections.ts (arch-ref 168-177).
  const { data: reg } = await admin
    .from('warranty_registrations')
    .select('tenant_id, warranty_id')
    .eq('id', input.warranty_registration_id)
    .single()

  if (!reg) return { success: false, error: 'Warranty registration not found' }
  if (reg.tenant_id !== tenantId) {
    return { success: false, error: 'Cross-tenant operation not allowed' }
  }
  // Eligibility (Decision 27.4): warranty_id IS NOT NULL.
  if (!reg.warranty_id) {
    return { success: false, error: 'Claim not eligible: WarrantyID not yet issued' }
  }

  // ── Submitter FK validation (20.4): if a contact is named, it must exist and
  // tenant-match. Snapshots (name/email) are written regardless. ──
  if (input.submitter_contact_id) {
    const { data: contact } = await admin
      .from('contacts')
      .select('tenant_id')
      .eq('id', input.submitter_contact_id)
      .single()
    if (!contact) return { success: false, error: 'submitter_contact_id not found' }
    if (contact.tenant_id !== tenantId) {
      return { success: false, error: 'Cross-tenant operation not allowed' }
    }
  }

  // ── Atomic create via the ID Generation system (migration 031). The RPC
  // locks the (tenant, claim_id) sequence row, increments with UTC year-rollover,
  // expands CLM-{year}-{seq:07d}, and INSERTs the claim in ONE transaction so a
  // failed insert rolls the counter back — gap-free (Decision 2; arch-ref ID
  // Generation). status defaults 'intake_received' (016); intake_token stays
  // null (issuance subsystem's to mint). ──
  const { data: inserted, error } = await admin
    .rpc('create_claim_with_generated_id', {
      p_tenant_id: tenantId,
      p_warranty_registration_id: input.warranty_registration_id,
      p_claim_type: input.claim_type,
      p_date_of_defect_incident: input.date_of_defect_incident,
      p_equipment_status: input.equipment_status,
      p_loto_requirement: input.loto_requirement,
      p_detailed_description: input.detailed_description as never,
      p_submitter_name: input.submitter_name,
      p_submitter_email: input.submitter_email,
      p_is_emergency: input.is_emergency ?? false,
      p_emergency_details: (input.emergency_details ?? null) as never,
      p_emergency_stabilized_at: input.emergency_stabilized_at ?? null,
      p_offline_condition_explanation: (input.offline_condition_explanation ?? null) as never,
      p_supporting_documents: (input.supporting_documents ?? null) as never,
      p_required_docs_provided: input.required_docs_provided ?? false,
      p_submitter_contact_id: input.submitter_contact_id ?? null,
      p_om_provider_company: input.om_provider_company ?? null,
      p_om_contact_name: input.om_contact_name ?? null,
      p_om_contact_phone: input.om_contact_phone ?? null,
      p_om_contact_email: input.om_contact_email ?? null,
      p_ship_to_street: input.ship_to_street ?? null,
      p_ship_to_city: input.ship_to_city ?? null,
      p_ship_to_state: input.ship_to_state ?? null,
      p_ship_to_zip: input.ship_to_zip ?? null,
      p_recipient_name: input.recipient_name ?? null,
      p_recipient_phone: input.recipient_phone ?? null,
      p_claim_type_data: (input.claim_type_data ?? null) as never,
    } as never)
    .single()
  if (error || !inserted) {
    return {
      success: false,
      error: `Failed to create claim: ${error?.message ?? 'unknown error'}`,
    }
  }
  return { success: true, id: (inserted as { id: string }).id }
}
