'use server'

import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import {
  inviteTeamMember as coreInviteTeamMember,
  type InviteTeamMemberInput,
  type InviteTeamMemberResult,
} from '@/lib/core/invite-team-member'

export async function inviteTeamMember(
  input: Omit<InviteTeamMemberInput, 'tenantId' | 'invitedBy'>
): Promise<InviteTeamMemberResult> {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { success: false, error: 'Not authenticated' }

  const { data: profile } = await supabase
    .from('users')
    .select('role, tenant_id')
    .eq('id', user.id)
    .single()

  if (!profile) return { success: false, error: 'User profile not found' }
  if (profile.role !== 'team_admin') return { success: false, error: 'Only team admins can invite members' }

  const result = await coreInviteTeamMember({
    ...input,
    tenantId: profile.tenant_id,
    invitedBy: user.id,
  })
  if (result.success) {
    revalidatePath('/app/team')
    revalidatePath('/app')
  }
  return result
}
