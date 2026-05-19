'use server'

import { createClient } from '@/lib/supabase/server'
import {
  changeUserRole,
  suspendUser,
  reactivateUser,
  removeUser,
  cancelInvitation,
  type ManageResult,
} from '@/lib/core/manage-team-member'
import type { UserRole } from '@/types/database'

async function getCallerId(): Promise<string | null> {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  return user?.id ?? null
}

export async function changeRole(userId: string, newRole: UserRole): Promise<ManageResult> {
  const callerId = await getCallerId()
  if (!callerId) return { success: false, error: 'Not authenticated' }
  return changeUserRole(userId, newRole, callerId)
}

export async function suspend(userId: string): Promise<ManageResult> {
  const callerId = await getCallerId()
  if (!callerId) return { success: false, error: 'Not authenticated' }
  return suspendUser(userId, callerId)
}

export async function reactivate(userId: string): Promise<ManageResult> {
  const callerId = await getCallerId()
  if (!callerId) return { success: false, error: 'Not authenticated' }
  return reactivateUser(userId, callerId)
}

export async function remove(userId: string): Promise<ManageResult> {
  const callerId = await getCallerId()
  if (!callerId) return { success: false, error: 'Not authenticated' }
  return removeUser(userId, callerId)
}

export async function cancelInvite(invitationId: string): Promise<ManageResult> {
  const callerId = await getCallerId()
  if (!callerId) return { success: false, error: 'Not authenticated' }
  return cancelInvitation(invitationId, callerId)
}
