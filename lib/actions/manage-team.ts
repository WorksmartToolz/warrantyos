'use server'

import { revalidatePath } from 'next/cache'
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

function revalidateTeamPages() {
  revalidatePath('/app/team')
  revalidatePath('/app')
}

export async function changeRole(userId: string, newRole: UserRole): Promise<ManageResult> {
  const callerId = await getCallerId()
  if (!callerId) return { success: false, error: 'Not authenticated' }
  const result = await changeUserRole(userId, newRole, callerId)
  if (result.success) revalidateTeamPages()
  return result
}

export async function suspend(userId: string): Promise<ManageResult> {
  const callerId = await getCallerId()
  if (!callerId) return { success: false, error: 'Not authenticated' }
  const result = await suspendUser(userId, callerId)
  if (result.success) revalidateTeamPages()
  return result
}

export async function reactivate(userId: string): Promise<ManageResult> {
  const callerId = await getCallerId()
  if (!callerId) return { success: false, error: 'Not authenticated' }
  const result = await reactivateUser(userId, callerId)
  if (result.success) revalidateTeamPages()
  return result
}

export async function remove(userId: string): Promise<ManageResult> {
  const callerId = await getCallerId()
  if (!callerId) return { success: false, error: 'Not authenticated' }
  const result = await removeUser(userId, callerId)
  if (result.success) revalidateTeamPages()
  return result
}

export async function cancelInvite(invitationId: string): Promise<ManageResult> {
  const callerId = await getCallerId()
  if (!callerId) return { success: false, error: 'Not authenticated' }
  const result = await cancelInvitation(invitationId, callerId)
  if (result.success) revalidateTeamPages()
  return result
}
