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
    .insert({ name: tenantName.trim(), slug: tenantSlug })
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
    role: 'admin',
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
