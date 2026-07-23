import { createAdminClient } from '@/lib/supabase/admin'
import {
  generateInvitationToken,
  invitationExpiresAt,
} from '@/lib/core/invitations'

// Input validation helpers
const SLUG_RE = /^[a-z0-9]+(?:-[a-z0-9]+)*$/
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

export interface ProvisionTenantInput {
  tenantName: string
  tenantSlug: string
  adminEmail: string
  adminFullName: string
  maxTeamAdmins?: number
}

export type ProvisionTenantResult =
  | {
      success: true
      tenantId: string
      tenantSlug: string
      invitationToken: string
      invitationUrl: string
    }
  | { success: false; error: string }

// Core provisioning logic — no Next.js dependencies.
// Called by the Server Action wrapper AND the CLI scripts.
//
// What this does NOT do:
// - Create an auth.users row (that happens when the admin completes signup)
// - Send email (deferred to a later session with Resend)
//
// The caller receives an invitationUrl to deliver out-of-band
// (printed by the CLI; passed to the admin UI in a later session).
export async function provisionTenant(
  input: ProvisionTenantInput
): Promise<ProvisionTenantResult> {
  const { tenantName, tenantSlug, adminEmail, adminFullName } = input
  const maxTeamAdmins = input.maxTeamAdmins ?? 3

  // Validate inputs
  if (!tenantName.trim()) return { success: false, error: 'tenant_name is required' }
  if (!tenantSlug.trim()) return { success: false, error: 'tenant_slug is required' }
  if (!SLUG_RE.test(tenantSlug)) {
    return {
      success: false,
      error:
        'tenant_slug must be lowercase letters, numbers, and hyphens only (no leading/trailing/consecutive hyphens)',
    }
  }
  if (!adminEmail.trim()) return { success: false, error: 'admin_email is required' }
  if (!EMAIL_RE.test(adminEmail)) {
    return { success: false, error: 'admin_email is not a valid email address' }
  }
  if (!adminFullName.trim()) return { success: false, error: 'admin_full_name is required' }
  if (!Number.isInteger(maxTeamAdmins) || maxTeamAdmins < 1) {
    return { success: false, error: 'max_team_admins must be a positive integer' }
  }

  const admin = createAdminClient()

  // Check slug uniqueness
  const { data: existing } = await admin
    .from('tenants')
    .select('id')
    .eq('slug', tenantSlug)
    .maybeSingle()

  if (existing) {
    return { success: false, error: `A tenant with slug "${tenantSlug}" already exists` }
  }

  // Create the tenant
  const { data: tenant, error: tenantError } = await admin
    .from('tenants')
    .insert({
      name: tenantName.trim(),
      slug: tenantSlug,
      max_team_admins: maxTeamAdmins,
      settings: {
        ala_signature_method: 'in_platform_widget',
        ala_decline_warning_text:
          'We cannot move forward without your acceptance. Your claim is subject to denial.',
        ala_decline_recant_window_days: 3,
        ala_markup_percent: 10,
        ala_response_overdue_business_days: 7,
        service_report_response_days: 3,
        // C10 / Decision 31.4: who may render an escalation verdict.
        // Default 'team_admin' is the bias-prevention higher-authority path;
        // a tenant whose process allows it may widen this to 'reviewer'.
        escalation_verdict_authorized_role: 'team_admin',
      },
    })
    .select('id')
    .single()

  if (tenantError || !tenant) {
    return {
      success: false,
      error: `Failed to create tenant: ${tenantError?.message ?? 'unknown error'}`,
    }
  }

  // Generate invitation token and create invitation row
  const token = generateInvitationToken()
  const expiresAt = invitationExpiresAt()

  const { error: inviteError } = await admin.from('invitations').insert({
    tenant_id: tenant.id,
    email: adminEmail.trim().toLowerCase(),
    role: 'team_admin',
    full_name: adminFullName.trim(),
    token,
    expires_at: expiresAt,
  })

  if (inviteError) {
    // Roll back the tenant to avoid an orphaned record
    await admin.from('tenants').delete().eq('id', tenant.id)
    return {
      success: false,
      error: `Failed to create invitation: ${inviteError.message}`,
    }
  }

  // --------------------------------------------------------------------------
  // A1-A5 provisioning seeds (roadmap Layer A). A tenant is either fully
  // seeded or does not exist: any seed failure triggers a compensating
  // rollback of this tenant's seeded rows, its invitation, and the tenant,
  // then returns an error. (Option B, app-level compensating rollback --
  // the Supabase JS client has no multi-statement transaction.)
  // Feature flags (epc_workflow, supply_only_workflow,
  // service_report_acquiesce_window) are intentionally NOT seeded here: the
  // feature-flag storage shape + is_feature_enabled reader do not exist yet
  // (roadmap D2). D2 seeds its own flag defaults at provisioning.
  // --------------------------------------------------------------------------
  const rollbackTenant = async (reason: string): Promise<ProvisionTenantResult> => {
    await admin.from('tenant_holidays').delete().eq('tenant_id', tenant.id)
    await admin.from('inspection_triggers').delete().eq('tenant_id', tenant.id)
    await admin.from('inspection_types').delete().eq('tenant_id', tenant.id)
    await admin.from('tenant_id_sequences').delete().eq('tenant_id', tenant.id)
    await admin.from('invitations').delete().eq('tenant_id', tenant.id)
    await admin.from('tenants').delete().eq('id', tenant.id)
    return { success: false, error: reason }
  }

  // A1: tenant_id_sequences (2 rows, gap-free counters; Decision 2)
  const provisioningYear = new Date().getUTCFullYear()
  const { error: seqError } = await admin.from('tenant_id_sequences').insert([
    { tenant_id: tenant.id, id_type: 'warranty_id', format_string: 'WID-{year}-{seq:06d}', current_year: provisioningYear, current_value: 0 },
    { tenant_id: tenant.id, id_type: 'claim_id',    format_string: 'CLM-{year}-{seq:07d}', current_year: provisioningYear, current_value: 0 },
  ])
  if (seqError) return rollbackTenant(`Failed to seed id sequences: ${seqError.message}`)

  // A3: inspection_types (4) + inspection_triggers (8), platform_locked (Decision 17.B)
  const inspectionTypes = [
    { value: 'warranty',                 label: 'Warranty' },
    { value: 'condition_assessment',     label: 'Condition Assessment' },
    { value: 'remediation_verification', label: 'Remediation Verification' },
    { value: 'failure_investigation',    label: 'Failure Investigation' },
  ].map((r, i) => ({ tenant_id: tenant.id, value: r.value, label: r.label, lock_tier: 'platform_locked', sort_order: i }))
  const { error: itError } = await admin.from('inspection_types').insert(inspectionTypes)
  if (itError) return rollbackTenant(`Failed to seed inspection types: ${itError.message}`)

  const inspectionTriggers = [
    { value: 'warranty_claim',                    label: 'Warranty Claim' },
    { value: 'customer_request',                  label: 'Customer Request' },
    { value: 'repeat_condition_verification',     label: 'Repeat Condition Verification' },
    { value: 'post_remediation_verification',     label: 'Post-Remediation Verification' },
    { value: 'failure_investigation',             label: 'Failure Investigation' },
    { value: 'preventative_condition_assessment', label: 'Preventative / Condition Assessment' },
    { value: 'internal_review',                   label: 'Internal Review' },
    { value: 'third_party',                       label: 'Third Party' },
  ].map((r, i) => ({ tenant_id: tenant.id, value: r.value, label: r.label, lock_tier: 'platform_locked', sort_order: i }))
  const { error: trError } = await admin.from('inspection_triggers').insert(inspectionTriggers)
  if (trError) return rollbackTenant(`Failed to seed inspection triggers: ${trError.message}`)

  // A4: tenant_holidays over the locked 2026-2036 horizon (mirrors 024 backfill)
  const holidayRows: { tenant_id: string; holiday_date: string; label: string }[] = []
  for (let y = 2026; y <= 2036; y++) {
    const { data: hol, error: holFnError } = await admin.rpc('federal_holidays_for_year', { p_year: y })
    if (holFnError) return rollbackTenant(`Failed to compute holidays for ${y}: ${holFnError.message}`)
    for (const h of (hol ?? []) as { holiday_date: string; label: string }[]) {
      holidayRows.push({ tenant_id: tenant.id, holiday_date: h.holiday_date, label: h.label })
    }
  }
  const { error: holError } = await admin.from('tenant_holidays').insert(holidayRows)
  if (holError) return rollbackTenant(`Failed to seed holidays: ${holError.message}`)

  // A2: warranty_types anchors (2 rows, is_system; Decision 6). Seeded LAST:
  // the Decision 6 trigger makes is_system rows un-deletable through the app
  // path, so the compensating rollback above cannot delete them. Seeding these
  // last means any earlier failure rolls back cleanly (no warranty_types seeded
  // yet), and a failure here leaves nothing after it to orphan.
  const { error: wtError } = await admin.from('warranty_types').insert([
    { tenant_id: tenant.id, name: 'Standard Warranty',    is_system: true },
    { tenant_id: tenant.id, name: 'Workmanship Warranty', is_system: true },
  ])
  if (wtError) return rollbackTenant(`Failed to seed warranty types: ${wtError.message}`)

  const appUrl = process.env.NEXT_PUBLIC_APP_URL ?? 'http://localhost:3000'
  const invitationUrl = `${appUrl}/signup?token=${token}`

  return {
    success: true,
    tenantId: tenant.id,
    tenantSlug,
    invitationToken: token,
    invitationUrl,
  }
}
