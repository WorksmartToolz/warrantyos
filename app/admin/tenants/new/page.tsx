import Link from 'next/link'
import { NewTenantForm } from './new-tenant-form'

export default function NewTenantPage() {
  return (
    <div className="p-8">
      <div className="mb-6">
        <Link
          href="/admin/tenants"
          className="text-xs text-neutral-400 hover:text-neutral-600"
        >
          ← Tenants
        </Link>
        <h1 className="mt-2 text-xl font-semibold">New Tenant</h1>
        <p className="mt-1 text-sm text-neutral-500">
          Provision a new tenant and generate an invitation for their first admin
          user.
        </p>
      </div>

      <div className="max-w-md">
        <NewTenantForm />
      </div>
    </div>
  )
}
