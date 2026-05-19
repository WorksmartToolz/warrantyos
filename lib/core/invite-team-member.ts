import { createAdminClient } from '@/lib/supabase/admin'
import { generateInvitationToken, invitationExpiresAt } from '@/lib/core/invitations'
import type { UserRole } from '@/types/database'

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
const VALID_ROLES: UserRole[] = ['team_admin', 'reviewer', 'viewer']

export interface InviteTeamMemberInput {
  tenantId: string
  email: string
  role: UserRole
  fullName: string
  invitedBy: string
}

export type InviteTeamMemberResult =
  | { success: true; invitationUrl: string; expiresAt: string }
  | { success: false; error: string }

export async function inviteTeamMember(
  input: InviteTeamMemberInput
): Promise<InviteTeamMemberResult> {
  const { tenantId, role, invitedBy } = input
  const email = input.email.trim().toLowerCase()
  const fullName = input.fullName.trim()

  if (!EMAIL_RE.test(email)) {
    return { success: false, error: 'Invalid email address' }
  }
  if (!VALID_ROLES.includes(role)) {
    return { success: false, error: 'Invalid role' }
  }
  if (!fullName) {
    return { success: false, error: 'Full name is required' }
  }

  const admin = createAdminClient()
  const appUrl = process.env.NEXT_PUBLIC_APP_URL ?? 'http://localhost:3000'

  // Verify the tenant exists and is active
  const { data: tenant } = await admin
    .from('tenants')
    .select('id, max_team_admins, status')
    .eq('id', tenantId)
    .single()

  if (!tenant) return { success: false, error: 'Tenant not found' }
  if (tenant.status !== 'active') return { success: false, error: 'Tenant is not active' }

  // Reject if the email is already an active member of this tenant
  const { data: existingUser } = await admin
    .from('users')
    .select('id')
    .eq('tenant_id', tenantId)
    .eq('email', email)
    .is('removed_at', null)
    .maybeSingle()

  if (existingUser) {
    return { success: false, error: 'This email is already a member of the team' }
  }

  // If an unconsumed, unexpired invitation already exists for this email+tenant,
  // return that URL rather than creating a duplicate.
  const { data: existingInvite } = await admin
    .from('invitations')
    .select('token, expires_at')
    .eq('tenant_id', tenantId)
    .eq('email', email)
    .is('consumed_at', null)
    .gt('expires_at', new Date().toISOString())
    .maybeSingle()

  if (existingInvite) {
    return {
      success: true,
      invitationUrl: `${appUrl}/signup?token=${existingInvite.token}`,
      expiresAt: existingInvite.expires_at,
    }
  }

  // Seat count check for team_admin invitations
  if (role === 'team_admin') {
    const { count } = await admin
      .from('users')
      .select('*', { count: 'exact', head: true })
      .eq('tenant_id', tenantId)
      .eq('role', 'team_admin')
      .eq('status', 'active')
      .is('removed_at', null)

    if (count !== null && count >= tenant.max_team_admins) {
      return {
        success: false,
        error: `Team admin seats are full (${count}/${tenant.max_team_admins}). Demote an existing admin or contact your platform administrator to increase the limit.`,
      }
    }
  }

  const token = generateInvitationToken()
  const expiresAt = invitationExpiresAt()

  const { error: insertError } = await admin.from('invitations').insert({
    tenant_id: tenantId,
    email,
    role,
    full_name: fullName,
    token,
    expires_at: expiresAt,
    invited_by: invitedBy,
  })

  if (insertError) {
    return { success: false, error: `Failed to create invitation: ${insertError.message}` }
  }

  return {
    success: true,
    invitationUrl: `${appUrl}/signup?token=${token}`,
    expiresAt,
  }
}
