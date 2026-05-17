import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { LogoutButton } from '@/components/ui/logout-button'

export default async function AppPage() {
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) redirect('/login')

  // Load the user's profile and tenant name
  const { data: profile } = await supabase
    .from('users')
    .select('full_name, tenant_id')
    .eq('id', user.id)
    .single()

  const { data: tenant } = await supabase
    .from('tenants')
    .select('name')
    .eq('id', profile?.tenant_id ?? '')
    .single()

  const displayName = profile?.full_name ?? user.email

  return (
    <main className="flex min-h-screen flex-col bg-neutral-50">
      <header className="flex items-center justify-between border-b border-neutral-200 bg-white px-6 py-3">
        <span className="text-sm font-medium">WarrantyOS</span>
        <LogoutButton />
      </header>

      <div className="flex flex-1 items-center justify-center">
        <div className="text-center">
          <h1 className="text-2xl font-semibold tracking-tight">
            Welcome, {displayName}
          </h1>
          {tenant?.name && (
            <p className="mt-2 text-neutral-500">
              You&apos;re logged into{' '}
              <span className="font-medium text-neutral-700">{tenant.name}</span>
            </p>
          )}
          <p className="mt-6 text-sm text-neutral-400">
            Tenant workspace — coming in a future session
          </p>
        </div>
      </div>
    </main>
  )
}
