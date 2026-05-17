import { randomBytes } from 'node:crypto'
import { createAdminClient } from '@/lib/supabase/admin'
import type { Invitation } from '@/types/database'

const TOKEN_TTL_DAYS = 7

export function generateInvitationToken(): string {
  return randomBytes(32).toString('hex')
}

export function invitationExpiresAt(): string {
  const d = new Date()
  d.setDate(d.getDate() + TOKEN_TTL_DAYS)
  return d.toISOString()
}

// Validates a token: must exist, not consumed, not expired.
// Uses the service-role client — safe to call from Server Actions
// and CLI scripts. Never call from browser-side code.
export async function validateInvitationToken(
  token: string
): Promise<Invitation | null> {
  const admin = createAdminClient()

  const { data, error } = await admin
    .from('invitations')
    .select('*')
    .eq('token', token)
    .is('consumed_at', null)
    .gt('expires_at', new Date().toISOString())
    .maybeSingle()

  if (error || !data) return null
  return data
}

export async function consumeInvitationToken(token: string): Promise<void> {
  const admin = createAdminClient()

  const { error } = await admin
    .from('invitations')
    .update({ consumed_at: new Date().toISOString() })
    .eq('token', token)

  if (error) throw new Error(`Failed to consume invitation: ${error.message}`)
}
