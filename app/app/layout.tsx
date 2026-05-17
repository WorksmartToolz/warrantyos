import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

// Defense-in-depth: middleware already enforces /app/* access.
// This layout re-checks so individual pages don't have to.
export default async function AppLayout({
  children,
}: {
  children: React.ReactNode
}) {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) redirect('/login')

  const isPlatformAdmin = user.user_metadata?.is_platform_admin === true
  if (isPlatformAdmin) redirect('/admin')

  return <>{children}</>
}
