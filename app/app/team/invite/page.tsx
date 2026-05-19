import Link from 'next/link'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { InviteForm } from './invite-form'

export default async function InvitePage() {
  const supabase = await createClient()

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: profile } = await supabase
    .from('users')
    .select('role, tenant_id')
    .eq('id', user.id)
    .single()

  if (!profile || profile.role !== 'team_admin') redirect('/app/team')

  const { data: tenant } = await supabase
    .from('tenants')
    .select('max_team_admins')
    .eq('id', profile.tenant_id)
    .single()

  const { count: adminCount } = await supabase
    .from('users')
    .select('*', { count: 'exact', head: true })
    .eq('tenant_id', profile.tenant_id)
    .eq('role', 'team_admin')
    .eq('status', 'active')
    .is('removed_at', null)

  const maxAdmins = tenant?.max_team_admins ?? 3

  return (
    <div className="p-8">
      <div className="mb-6">
        <Link href="/app/team" className="text-sm text-neutral-400 hover:text-neutral-600">
          ← Back to Team
        </Link>
      </div>

      <InviteForm adminCount={adminCount ?? 0} maxAdmins={maxAdmins} />
    </div>
  )
}
