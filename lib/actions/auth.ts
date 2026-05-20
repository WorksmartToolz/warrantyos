'use server'

import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

export interface AuthState {
  error: string | null
}

export async function login(
  _prevState: AuthState,
  formData: FormData
): Promise<AuthState> {
  const email = (formData.get('email') as string | null)?.trim() ?? ''
  const password = (formData.get('password') as string | null) ?? ''

  if (!email || !password) {
    return { error: 'Email and password are required' }
  }

  const supabase = await createClient()
  const { data, error } = await supabase.auth.signInWithPassword({ email, password })

  if (error) {
    return { error: error.message }
  }

  // Check application-level account status before completing login.
  // Both suspended and removed users fail this check — future work could
  // differentiate the error message (suspended vs. removed) if needed.
  const { data: profile } = await supabase
    .from('users')
    .select('status, removed_at')
    .eq('id', data.user.id)
    .maybeSingle()

  if (!profile || profile.removed_at || profile.status !== 'active') {
    await supabase.auth.signOut()
    return { error: 'Your account has been suspended. Contact your administrator.' }
  }

  const isPlatformAdmin = data.user?.user_metadata?.is_platform_admin === true
  redirect(isPlatformAdmin ? '/admin' : '/app')
}

export async function logout(): Promise<void> {
  const supabase = await createClient()
  await supabase.auth.signOut()
  redirect('/login')
}
