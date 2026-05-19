import Link from 'next/link'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'

export default async function AppPage() {
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) redirect('/login')

  const { data: profile } = await supabase
    .from('users')
    .select('full_name, tenant_id')
    .eq('id', user.id)
    .single()

  const [{ data: tenant }, { count: totalMembers }, { count: teamAdminCount }] =
    await Promise.all([
      supabase
        .from('tenants')
        .select('name, slug, max_team_admins')
        .eq('id', profile?.tenant_id ?? '')
        .single(),
      supabase.from('users').select('*', { count: 'exact', head: true }),
      supabase
        .from('users')
        .select('*', { count: 'exact', head: true })
        .eq('role', 'team_admin'),
    ])

  const displayName = profile?.full_name ?? user.email

  return (
    <div className="p-8">
      <div className="mb-8">
        <h1 className="text-xl font-semibold">Welcome, {displayName}</h1>
        <p className="mt-1 text-sm text-neutral-500">{tenant?.name}</p>
      </div>

      <div className="mb-8 grid grid-cols-3 gap-4">
        <Card>
          <CardHeader>
            <CardDescription>Team Members</CardDescription>
            <CardTitle className="text-3xl font-bold tabular-nums">
              {totalMembers ?? 0}
            </CardTitle>
          </CardHeader>
          <CardContent>
            <Link
              href="/app/team"
              className="text-xs text-neutral-400 hover:text-neutral-600"
            >
              View team →
            </Link>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardDescription>Team Admin Seats</CardDescription>
            <CardTitle className="text-3xl font-bold tabular-nums">
              {teamAdminCount ?? 0}
              <span className="ml-1 text-lg font-normal text-neutral-400">
                / {tenant?.max_team_admins ?? 3}
              </span>
            </CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-xs text-neutral-400">of contracted seats used</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardDescription>Tenant Slug</CardDescription>
            <CardTitle className="font-mono text-xl font-medium">
              {tenant?.slug ?? '—'}
            </CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-xs text-neutral-400">Your organization identifier</p>
          </CardContent>
        </Card>
      </div>

      <Button render={<Link href="/app/team" />} size="sm">
        Manage Team →
      </Button>
    </div>
  )
}
