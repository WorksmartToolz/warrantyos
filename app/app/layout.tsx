import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { LogoutButton } from '@/components/ui/logout-button'
import { NavLink } from '@/components/ui/nav-link'

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

  const { data: profile } = await supabase
    .from('users')
    .select('full_name, tenant_id, role')
    .eq('id', user.id)
    .single()

  const { data: tenant } = await supabase
    .from('tenants')
    .select('name')
    .eq('id', profile?.tenant_id ?? '')
    .single()

  const displayName = profile?.full_name ?? user.email
  const isAdmin = profile?.role === 'team_admin'

  return (
    <div className="flex min-h-screen bg-neutral-50">
      <aside className="flex w-56 shrink-0 flex-col border-r border-neutral-200 bg-white">
        <div className="border-b border-neutral-200 px-4 py-4">
          <p className="text-sm font-semibold">WarrantyOS</p>
          <p className="truncate text-xs text-neutral-400">
            {tenant?.name ?? 'Tenant Workspace'}
          </p>
        </div>

        <nav className="flex-1 space-y-0.5 p-3">
          <NavLink href="/app" exact>Dashboard</NavLink>
          <NavLink href="/app/team">Team</NavLink>
          {isAdmin && <NavLink href="/app/settings">Settings</NavLink>}
        </nav>

        <div className="border-t border-neutral-200 p-3">
          <p className="mb-2 truncate px-3 text-xs text-neutral-400">
            {displayName}
          </p>
          <LogoutButton />
        </div>
      </aside>

      <main className="flex-1 overflow-y-auto">{children}</main>
    </div>
  )
}
