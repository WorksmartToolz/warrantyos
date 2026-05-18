'use client'

import { useState } from 'react'
import Link from 'next/link'
import {
  createPlatformAdmin,
  type CreatePlatformAdminResult,
} from '@/lib/actions/provision-platform-admin'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'

export function NewPlatformAdminForm() {
  const [isPending, setIsPending] = useState(false)
  const [result, setResult] = useState<CreatePlatformAdminResult | null>(null)

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    setIsPending(true)
    const fd = new FormData(e.currentTarget)
    try {
      const res = await createPlatformAdmin({
        email:    fd.get('email')    as string ?? '',
        password: fd.get('password') as string ?? '',
        fullName: fd.get('fullName') as string ?? '',
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
            Platform admin created for{' '}
            <span className="font-mono">{result.email}</span>.
          </p>
          <p className="mt-1 text-xs text-green-700">
            They can sign in at the /login page using those credentials.
          </p>
        </div>

        <div className="flex gap-3">
          <Button render={<Link href="/admin" />} variant="outline" size="sm">
            Back to Dashboard
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
        <Label htmlFor="email">Email</Label>
        <Input
          id="email"
          name="email"
          type="email"
          placeholder="admin@example.com"
          required
          disabled={isPending}
        />
      </div>

      <div className="space-y-1.5">
        <Label htmlFor="password">Password</Label>
        <Input
          id="password"
          name="password"
          type="password"
          placeholder="Min. 8 characters"
          required
          minLength={8}
          disabled={isPending}
        />
      </div>

      <div className="space-y-1.5">
        <Label htmlFor="fullName">Full Name</Label>
        <Input
          id="fullName"
          name="fullName"
          placeholder="Jane Smith"
          required
          disabled={isPending}
        />
      </div>

      <div className="flex gap-3 pt-2">
        <Button type="submit" disabled={isPending}>
          {isPending ? 'Creating…' : 'Create Platform Admin'}
        </Button>
        <Button render={<Link href="/admin" />} variant="outline" disabled={isPending}>
          Cancel
        </Button>
      </div>
    </form>
  )
}
