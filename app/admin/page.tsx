import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { LogoutButton } from '@/components/ui/logout-button'

export default async function AdminPage() {
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) redirect('/login')

  const displayName = user.user_metadata?.full_name ?? user.email

  return (
    <main className="flex min-h-screen flex-col bg-neutral-50">
      <header className="flex items-center justify-between border-b border-neutral-200 bg-white px-6 py-3">
        <span className="text-sm font-medium">WarrantyOS — Platform Admin</span>
        <LogoutButton />
      </header>

      <div className="flex flex-1 items-center justify-center">
        <div className="text-center">
          <h1 className="text-2xl font-semibold tracking-tight">
            Welcome, {displayName}
          </h1>
          <p className="mt-2 text-neutral-500">Platform administrator</p>
          <p className="mt-6 text-sm text-neutral-400">
            Admin panel — coming in a future session
          </p>
        </div>
      </div>
    </main>
  )
}
