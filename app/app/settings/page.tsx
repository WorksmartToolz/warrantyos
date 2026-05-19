import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { Badge } from '@/components/ui/badge'

function tenantStatusBadge(status: string) {
  switch (status) {
    case 'active':     return 'border-green-200 bg-green-50 text-green-700'
    case 'suspended':  return 'border-orange-200 bg-orange-50 text-orange-700'
    case 'terminated': return 'border-red-200 bg-red-50 text-red-700'
    default:           return 'border-neutral-200 bg-neutral-50 text-neutral-600'
  }
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="grid grid-cols-3 gap-4 py-4">
      <dt className="text-sm font-medium text-neutral-500">{label}</dt>
      <dd className="col-span-2 text-sm text-neutral-900">{children}</dd>
    </div>
  )
}

export default async function SettingsPage() {
  const supabase = await createClient()

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: profile } = await supabase
    .from('users')
    .select('role, tenant_id')
    .eq('id', user.id)
    .single()

  if (!profile || profile.role !== 'team_admin') redirect('/app')

  const { data: tenant } = await supabase
    .from('tenants')
    .select('name, slug, status, max_team_admins, created_at')
    .eq('id', profile.tenant_id)
    .single()

  if (!tenant) redirect('/app')

  const createdDate = new Date(tenant.created_at).toLocaleDateString('en-US', {
    year: 'numeric', month: 'long', day: 'numeric',
  })

  return (
    <div className="p-8">
      <div className="mb-6">
        <h1 className="text-xl font-semibold">Settings</h1>
        <p className="mt-1 text-sm text-neutral-500">Tenant configuration. Contact your platform administrator to make changes.</p>
      </div>

      <div className="max-w-2xl overflow-hidden rounded-xl border border-neutral-200 bg-white">
        <div className="border-b border-neutral-100 px-6 py-4">
          <h2 className="text-sm font-medium">Tenant</h2>
        </div>
        <dl className="divide-y divide-neutral-100 px-6">
          <Field label="Name">{tenant.name}</Field>
          <Field label="Slug">
            <span className="font-mono text-neutral-600">{tenant.slug}</span>
          </Field>
          <Field label="Status">
            <Badge variant="outline" className={tenantStatusBadge(tenant.status)}>
              {tenant.status.charAt(0).toUpperCase() + tenant.status.slice(1)}
            </Badge>
          </Field>
          <Field label="Team Admin Seats">{tenant.max_team_admins}</Field>
          <Field label="WarrantyID Format">
            <span className="font-mono text-neutral-400">WID-YYYY-NNNNNN</span>
            <span className="ml-2 text-xs text-neutral-400">(default — configurable)</span>
          </Field>
          <Field label="Provisioned">{createdDate}</Field>
        </dl>
      </div>
    </div>
  )
}
