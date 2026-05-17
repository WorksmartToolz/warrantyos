'use server'

import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'
import { validateInvitationToken, consumeInvitationToken } from '@/lib/core/invitations'

export interface SignupState {
  error: string | null
}

export async function completeSignup(
  _prevState: SignupState,
  formData: FormData
): Promise<SignupState> {
  const token    = (formData.get('token')     as string | null) ?? ''
  const password = (formData.get('password')  as string | null) ?? ''
  const fullName = (formData.get('full_name') as string | null)?.trim() ?? ''

  if (!token)    return { error: 'Invalid invitation link' }
  if (!fullName) return { error: 'Full name is required' }
  if (password.length < 8) return { error: 'Password must be at least 8 characters' }

  // Re-validate the token (the page load checked it too, but Server Actions
  // must not trust client-supplied state — always verify server-side).
  const invitation = await validateInvitationToken(token)
  if (!invitation) {
    return { error: 'This invitation is invalid, expired, or has already been used' }
  }

  const admin = createAdminClient()

  // Create the auth user. email_confirm: true skips the confirmation email
  // flow — the invitation token itself served as the authorization proof.
  const { data: authData, error: createError } = await admin.auth.admin.createUser({
    email: invitation.email,
    password,
    email_confirm: true,
    user_metadata: { full_name: fullName },
  })

  if (createError || !authData.user) {
    return {
      error: createError?.message ?? 'Failed to create account',
    }
  }

  const userId = authData.user.id

  // Create the public.users profile row
  const { error: profileError } = await admin.from('users').insert({
    id: userId,
    tenant_id: invitation.tenant_id,
    email: invitation.email,
    role: invitation.role,
    full_name: fullName,
  })

  if (profileError) {
    // Roll back auth user to avoid an orphaned account
    await admin.auth.admin.deleteUser(userId)
    return {
      error: `Failed to create user profile: ${profileError.message}`,
    }
  }

  // Mark the invitation consumed so the token cannot be reused
  await consumeInvitationToken(token)

  // Sign in using the SSR client so session cookies are set on the response
  const supabase = await createClient()
  const { error: signInError } = await supabase.auth.signInWithPassword({
    email: invitation.email,
    password,
  })

  if (signInError) {
    // Account is fully created — user can sign in at /login
    return {
      error: 'Account created but sign-in failed. Please log in at /login.',
    }
  }

  redirect('/app')
}
