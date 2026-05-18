'use client'

import { useState, useRef } from 'react'
import Link from 'next/link'
import { provisionTenant } from '@/lib/actions/provision-tenant'
import type { ProvisionTenantResult } from '@/lib/core/provision-tenant'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'

export function NewTenantForm() {
  const [isPending, setIsPending] = useState(false)
  const [result, setResult] = useState<ProvisionTenantResult | null>(null)
  const [copied, setCopied] = useState(false)
  const copyTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  function handleCopy(url: string) {
    navigator.clipboard.writeText(url).then(() => {
      setCopied(true)
      if (copyTimerRef.current) clearTimeout(copyTimerRef.current)
      copyTimerRef.current = setTimeout(() => setCopied(false), 2000)
    })
  }

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    setIsPending(true)
    const fd = new FormData(e.currentTarget)
    try {
      const res = await provisionTenant({
        tenantName:    fd.get('tenantName')    as string ?? '',
        tenantSlug:    fd.get('tenantSlug')    as string ?? '',
        adminEmail:    fd.get('adminEmail')    as string ?? '',
        adminFullName: fd.get('adminFullName') as string ?? '',
      })
      setResult(res)
    } catch {
      setResult({ success: false, error: 'Unexpected error. Please try again.' })
    } finally {
      setIsPending(false)
    }
  }

  if (result?.success) {
    return (
      <div className="space-y-6">
        <div className="rounded-lg border border-green-200 bg-green-50 p-4">
          <p className="text-sm font-medium text-green-800">
            Tenant <span className="font-mono">{result.tenantSlug}</span> created
            successfully.
          </p>
        </div>

        <div>
          <p className="mb-2 text-sm font-medium text-neutral-700">
            Invitation URL
          </p>
          <p className="mb-2 text-xs text-neutral-500">
            Send this URL to the new tenant admin. It expires in 7 days.
          </p>
          <div className="flex items-start gap-2">
            <div className="min-w-0 flex-1 rounded-lg border border-neutral-200 bg-neutral-50 px-3 py-2">
              <code className="break-all text-xs text-neutral-800">
                {result.invitationUrl}
              </code>
            </div>
            <button
              type="button"
              onClick={() => handleCopy(result.invitationUrl)}
              className="shrink-0 rounded-md border border-neutral-300 bg-white px-3 py-2 text-xs font-medium text-neutral-600 transition-colors hover:bg-neutral-50"
            >
              {copied ? 'Copied!' : 'Copy'}
            </button>
          </div>
        </div>

        <div className="flex gap-3">
          <Button render={<Link href="/admin/tenants" />} variant="outline" size="sm">
            Back to Tenants
          </Button>
          <Button size="sm" onClick={() => setResult(null)}>
            Create Another
          </Button>
        </div>
      </div>
    )
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-5">
      {result && !result.success && (
        <div className="rounded-lg border border-red-200 bg-red-50 px-4 py-3">
          <p className="text-sm text-red-700">{result.error}</p>
        </div>
      )}

      <div className="space-y-1.5">
        <Label htmlFor="tenantName">Tenant Name</Label>
        <Input
          id="tenantName"
          name="tenantName"
          placeholder="Acme Solar"
          required
          disabled={isPending}
        />
      </div>

      <div className="space-y-1.5">
        <Label htmlFor="tenantSlug">Tenant Slug</Label>
        <Input
          id="tenantSlug"
          name="tenantSlug"
          placeholder="acme-solar"
          required
          disabled={isPending}
        />
        <p className="text-xs text-neutral-400">
          Lowercase letters, numbers, and hyphens only.
        </p>
      </div>

      <div className="space-y-1.5">
        <Label htmlFor="adminEmail">Admin Email</Label>
        <Input
          id="adminEmail"
          name="adminEmail"
          type="email"
          placeholder="admin@acmesolar.com"
          required
          disabled={isPending}
        />
      </div>

      <div className="space-y-1.5">
        <Label htmlFor="adminFullName">Admin Full Name</Label>
        <Input
          id="adminFullName"
          name="adminFullName"
          placeholder="Jane Smith"
          required
          disabled={isPending}
        />
      </div>

      <div className="flex gap-3 pt-2">
        <Button type="submit" disabled={isPending}>
          {isPending ? 'Creating…' : 'Create Tenant'}
        </Button>
        <Button render={<Link href="/admin/tenants" />} variant="outline" disabled={isPending}>
          Cancel
        </Button>
      </div>
    </form>
  )
}
