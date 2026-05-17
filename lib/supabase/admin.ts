import { createClient } from '@supabase/supabase-js'
import type { Database } from '@/types/database'

// Service-role client. Bypasses RLS entirely.
// ONLY use inside Server Actions, Route Handlers, and CLI scripts.
// Never pass this client — or any data derived from it without
// re-applying authorization checks — to the browser.
export function createAdminClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY

  if (!url || !key) {
    throw new Error(
      'NEXT_PUBLIC_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set'
    )
  }

  return createClient<Database>(url, key, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  })
}
