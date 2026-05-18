import Link from 'next/link'
import { createAdminClient } from '@/lib/supabase/admin'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'

function statusClass(status: string) {
  switch (status) {
    case 'active':     return 'bg-green-50 text-green-700 border-green-200'
    case 'suspended':  return 'bg-amber-50 text-amber-700 border-amber-200'
    case 'terminated': return 'bg-red-50 text-red-700 border-red-200'
    default:           return 'bg-neutral-50 text-neutral-600 border-neutral-200'
  }
}

export default async function AdminPage() {
  const admin = createAdminClient()

  const [
    { count: tenantCount },
    { count: userCount },
    { count: inviteCount },
    { data: recentTenants },
  ] = await Promise.all([
    admin.from('tenants').select('*', { count: 'exact', head: true }),
    admin.from('users').select('*', { count: 'exact', head: true }),
    admin
      .from('invitations')
      .select('*', { count: 'exact', head: true })
      .is('consumed_at', null),
    admin
      .from('tenants')
      .select('id, name, slug, status, created_at')
      .order('created_at', { ascending: false })
      .limit(5),
  ])

  return (
    <div className="p-8">
      <div className="mb-8 flex items-center justify-between">
        <h1 className="text-xl font-semibold">Platform Dashboard</h1>
        <div className="flex gap-2">
          <Button render={<Link href="/admin/platform-admins/new" />} size="sm" variant="outline">
            New Platform Admin
          </Button>
          <Button render={<Link href="/admin/tenants/new" />} size="sm">
            New Tenant
          </Button>
        </div>
      </div>

      <div className="mb-8 grid grid-cols-3 gap-4">
        <Card>
          <CardHeader>
            <CardDescription>Tenants</CardDescription>
            <CardTitle className="text-3xl font-bold tabular-nums">
              {tenantCount ?? 0}
            </CardTitle>
          </CardHeader>
          <CardContent>
            <Link
              href="/admin/tenants"
              className="text-xs text-neutral-400 hover:text-neutral-600"
            >
              View all →
            </Link>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardDescription>Total Users</CardDescription>
            <CardTitle className="text-3xl font-bold tabular-nums">
              {userCount ?? 0}
            </CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-xs text-neutral-400">Across all tenants</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardDescription>Pending Invitations</CardDescription>
            <CardTitle className="text-3xl font-bold tabular-nums">
              {inviteCount ?? 0}
            </CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-xs text-neutral-400">Not yet accepted</p>
          </CardContent>
        </Card>
      </div>

      <div>
        <div className="mb-3 flex items-center justify-between">
          <h2 className="text-sm font-medium text-neutral-700">
            Recent Tenants
          </h2>
          <Link
            href="/admin/tenants"
            className="text-xs text-neutral-400 hover:text-neutral-600"
          >
            View all →
          </Link>
        </div>

        {!recentTenants || recentTenants.length === 0 ? (
          <p className="text-sm text-neutral-400">No tenants yet.</p>
        ) : (
          <div className="overflow-hidden rounded-xl border border-neutral-200 bg-white">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Name</TableHead>
                  <TableHead>Slug</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead>Created</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {recentTenants.map((t) => (
                  <TableRow key={t.id}>
                    <TableCell className="font-medium">{t.name}</TableCell>
                    <TableCell className="font-mono text-xs text-neutral-500">
                      {t.slug}
                    </TableCell>
                    <TableCell>
                      <Badge variant="outline" className={statusClass(t.status)}>
                        {t.status}
                      </Badge>
                    </TableCell>
                    <TableCell className="text-neutral-500">
                      {new Date(t.created_at).toLocaleDateString('en-US', {
                        year: 'numeric',
                        month: 'short',
                        day: 'numeric',
                      })}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        )}
      </div>
    </div>
  )
}
