import { createAdminClient } from '@/lib/supabase/admin'
import type { UserRole } from '@/types/database'

export type ManageResult = { success: true } | { success: false; error: string }

// ── Internal helpers ──────────────────────────────────────────────────────────

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
  if (data.role !== 'team_admin') return null
  if (data.status !== 'active') return null
  if (data.removed_at) return null

  return { tenantId: data.tenant_id }
}

interface TargetUser {
  role: UserRole
  tenantId: string
  status: 'active' | 'suspended'
  removedAt: string | null
}

async function fetchTargetUser(
  userId: string,
  callerTenantId: string
): Promise<TargetUser | { error: string } | null> {
  const admin = createAdminClient()
  const { data } = await admin
    .from('users')
    .select('role, tenant_id, status, removed_at')
    .eq('id', userId)
    .single()

  if (!data) return null
  if (data.removed_at) return { error: 'User has already been removed' }
  if (data.tenant_id !== callerTenantId) return { error: 'Cross-tenant operation not allowed' }

  return {
    role: data.role,
    tenantId: data.tenant_id,
    status: data.status,
    removedAt: data.removed_at,
  }
}

async function isLastTeamAdmin(tenantId: string): Promise<boolean> {
  const admin = createAdminClient()
  const { count } = await admin
    .from('users')
    .select('*', { count: 'exact', head: true })
    .eq('tenant_id', tenantId)
    .eq('role', 'team_admin')
    .eq('status', 'active')
    .is('removed_at', null)

  return (count ?? 0) <= 1
}

// ── Exported functions ────────────────────────────────────────────────────────

export async function changeUserRole(
  userId: string,
  newRole: UserRole,
  requestedBy: string
): Promise<ManageResult> {
  const caller = await fetchCallerProfile(requestedBy)
  if (!caller) return { success: false, error: 'Unauthorized' }

  const target = await fetchTargetUser(userId, caller.tenantId)
  if (!target) return { success: false, error: 'User not found' }
  if ('error' in target) return { success: false, error: target.error }

  // Prevent demoting the last team admin
  if (target.role === 'team_admin' && newRole !== 'team_admin') {
    if (await isLastTeamAdmin(caller.tenantId)) {
      return { success: false, error: 'Cannot demote the last team admin. Assign another team admin first.' }
    }
  }

  // Seat count check when promoting to team_admin
  if (target.role !== 'team_admin' && newRole === 'team_admin') {
    const admin = createAdminClient()
    const { data: tenant } = await admin
      .from('tenants')
      .select('max_team_admins')
      .eq('id', caller.tenantId)
      .single()

    const { count } = await admin
      .from('users')
      .select('*', { count: 'exact', head: true })
      .eq('tenant_id', caller.tenantId)
      .eq('role', 'team_admin')
      .eq('status', 'active')
      .is('removed_at', null)

    if (tenant && count !== null && count >= tenant.max_team_admins) {
      return {
        success: false,
        error: `Team admin seats are full (${count}/${tenant.max_team_admins}). Demote an existing admin or contact your platform administrator to increase the limit.`,
      }
    }
  }

  const admin = createAdminClient()
  const { error } = await admin
    .from('users')
    .update({ role: newRole })
    .eq('id', userId)

  if (error) return { success: false, error: `Failed to update role: ${error.message}` }
  return { success: true }
}

export async function suspendUser(
  userId: string,
  requestedBy: string
): Promise<ManageResult> {
  const caller = await fetchCallerProfile(requestedBy)
  if (!caller) return { success: false, error: 'Unauthorized' }

  const target = await fetchTargetUser(userId, caller.tenantId)
  if (!target) return { success: false, error: 'User not found' }
  if ('error' in target) return { success: false, error: target.error }

  if (target.status === 'suspended') {
    return { success: false, error: 'User is already suspended' }
  }

  // Prevent suspending the last active team admin
  if (target.role === 'team_admin') {
    if (await isLastTeamAdmin(caller.tenantId)) {
      return { success: false, error: 'Cannot suspend the last team admin. Assign another team admin first.' }
    }
  }

  const admin = createAdminClient()
  const { error } = await admin
    .from('users')
    .update({ status: 'suspended' })
    .eq('id', userId)

  if (error) return { success: false, error: `Failed to suspend user: ${error.message}` }
  return { success: true }
}

export async function reactivateUser(
  userId: string,
  requestedBy: string
): Promise<ManageResult> {
  const caller = await fetchCallerProfile(requestedBy)
  if (!caller) return { success: false, error: 'Unauthorized' }

  const target = await fetchTargetUser(userId, caller.tenantId)
  if (!target) return { success: false, error: 'User not found' }
  if ('error' in target) return { success: false, error: target.error }

  if (target.status === 'active') {
    return { success: false, error: 'User is already active' }
  }

  const admin = createAdminClient()
  const { error } = await admin
    .from('users')
    .update({ status: 'active' })
    .eq('id', userId)

  if (error) return { success: false, error: `Failed to reactivate user: ${error.message}` }
  return { success: true }
}

export async function removeUser(
  userId: string,
  requestedBy: string
): Promise<ManageResult> {
  const caller = await fetchCallerProfile(requestedBy)
  if (!caller) return { success: false, error: 'Unauthorized' }

  const target = await fetchTargetUser(userId, caller.tenantId)
  if (!target) return { success: false, error: 'User not found' }
  if ('error' in target) return { success: false, error: target.error }

  // Prevent removing the last team admin
  if (target.role === 'team_admin') {
    if (await isLastTeamAdmin(caller.tenantId)) {
      return { success: false, error: 'Cannot remove the last team admin. Assign another team admin first.' }
    }
  }

  const admin = createAdminClient()
  const { error } = await admin
    .from('users')
    .update({ removed_at: new Date().toISOString() })
    .eq('id', userId)

  if (error) return { success: false, error: `Failed to remove user: ${error.message}` }
  return { success: true }
}

export async function cancelInvitation(
  invitationId: string,
  requestedBy: string
): Promise<ManageResult> {
  const caller = await fetchCallerProfile(requestedBy)
  if (!caller) return { success: false, error: 'Unauthorized' }

  const admin = createAdminClient()

  // Verify the invitation belongs to the caller's tenant
  const { data: invite } = await admin
    .from('invitations')
    .select('tenant_id, consumed_at')
    .eq('id', invitationId)
    .single()

  if (!invite) return { success: false, error: 'Invitation not found' }
  if (invite.tenant_id !== caller.tenantId) return { success: false, error: 'Cross-tenant operation not allowed' }
  if (invite.consumed_at) return { success: false, error: 'Invitation has already been accepted' }

  // Cancel by setting expires_at to the past, which makes it invalid
  // without deleting the row (preserves audit trail of who was invited).
  const { error } = await admin
    .from('invitations')
    .update({ expires_at: new Date(0).toISOString() })
    .eq('id', invitationId)

  if (error) return { success: false, error: `Failed to cancel invitation: ${error.message}` }
  return { success: true }
}
