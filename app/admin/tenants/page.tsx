import Link from 'next/link'
import { createAdminClient } from '@/lib/supabase/admin'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
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

export default async function TenantsPage() {
  const admin = createAdminClient()

  const { data: tenants, error } = await admin
    .from('tenants')
    .select('id, name, slug, status, created_at')
    .order('created_at', { ascending: false })

  return (
    <div className="p-8">
      <div className="mb-6 flex items-center justify-between">
        <h1 className="text-xl font-semibold">Tenants</h1>
        <Button render={<Link href="/admin/tenants/new" />} size="sm">
          New Tenant
        </Button>
      </div>

      {error && (
        <p className="mb-4 text-sm text-red-600">
          Failed to load tenants: {error.message}
        </p>
      )}

      {!error && (!tenants || tenants.length === 0) && (
        <div className="rounded-xl border border-neutral-200 bg-white px-6 py-12 text-center">
          <p className="text-sm text-neutral-500">No tenants yet.</p>
          <Button render={<Link href="/admin/tenants/new" />} size="sm" className="mt-4">
            Create your first tenant
          </Button>
        </div>
      )}

      {tenants && tenants.length > 0 && (
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
              {tenants.map((t) => (
                <TableRow key={t.id}>
                  <TableCell className="font-medium">{t.name}</TableCell>
                  <TableCell className="font-mono text-xs text-neutral-500">
                    {t.slug}
                  </TableCell>
                  <TableCell>
                    <Badge
                      variant="outline"
                      className={statusClass(t.status)}
                    >
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
  )
}
