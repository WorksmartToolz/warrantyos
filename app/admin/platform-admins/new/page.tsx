import Link from 'next/link'
import { NewPlatformAdminForm } from './new-platform-admin-form'

export default function NewPlatformAdminPage() {
  return (
    <div className="p-8">
      <div className="mb-6">
        <Link
          href="/admin"
          className="text-xs text-neutral-400 hover:text-neutral-600"
        >
          ← Dashboard
        </Link>
        <h1 className="mt-2 text-xl font-semibold">New Platform Admin</h1>
        <p className="mt-1 text-sm text-neutral-500">
          Create a platform-level administrator account. Platform admins have
          access to all tenants and cannot access tenant data through RLS.
        </p>
      </div>

      <div className="max-w-md">
        <NewPlatformAdminForm />
      </div>
    </div>
  )
}
