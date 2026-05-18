'use server'

import { createAdminClient } from '@/lib/supabase/admin'

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

export type CreatePlatformAdminResult =
  | { success: true; email: string }
  | { success: false; error: string }

export async function createPlatformAdmin(input: {
  email: string
  password: string
  fullName: string
}): Promise<CreatePlatformAdminResult> {
  const { email, password, fullName } = input

  if (!email.trim())            return { success: false, error: 'Email is required' }
  if (!EMAIL_RE.test(email))    return { success: false, error: 'Email is not a valid address' }
  if (!password)                return { success: false, error: 'Password is required' }
  if (password.length < 8)      return { success: false, error: 'Password must be at least 8 characters' }
  if (!fullName.trim())         return { success: false, error: 'Full name is required' }

  const admin = createAdminClient()

  const { data, error } = await admin.auth.admin.createUser({
    email: email.trim().toLowerCase(),
    password,
    email_confirm: true,
    user_metadata: {
      full_name: fullName.trim(),
      is_platform_admin: true,
    },
  })

  if (error) return { success: false, error: error.message }

  return { success: true, email: data.user.email! }
}
