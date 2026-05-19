'use client'

import { useState, useTransition } from 'react'
import Link from 'next/link'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { inviteTeamMember } from '@/lib/actions/invite-team-member'
import type { UserRole } from '@/types/database'

interface InviteFormProps {
  adminCount: number
  maxAdmins: number
}

export function InviteForm({ adminCount, maxAdmins }: InviteFormProps) {
  const [isPending, startTransition] = useTransition()

  const [email, setEmail] = useState('')
  const [fullName, setFullName] = useState('')
  const [role, setRole] = useState<UserRole>('reviewer')
  const [error, setError] = useState<string | null>(null)
  const [result, setResult] = useState<{ invitationUrl: string; expiresAt: string } | null>(null)
  const [copied, setCopied] = useState(false)

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setError(null)
    startTransition(async () => {
      const res = await inviteTeamMember({ email, role, fullName })
      if (!res.success) {
        setError(res.error)
      } else {
        setResult({ invitationUrl: res.invitationUrl, expiresAt: res.expiresAt })
      }
    })
  }

  function copyUrl() {
    if (!result) return
    navigator.clipboard.writeText(result.invitationUrl).then(() => {
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    })
  }

  if (result) {
    const expiresDate = new Date(result.expiresAt).toLocaleDateString('en-US', {
      month: 'short', day: 'numeric', year: 'numeric',
    })

    return (
      <div className="max-w-lg">
        <h1 className="mb-1 text-xl font-semibold">Invitation created</h1>
        <p className="mb-6 text-sm text-neutral-500">
          Share this link with {email}. It expires on {expiresDate}.
        </p>

        <div className="rounded-xl border border-neutral-200 bg-white p-5">
          <p className="mb-2 text-xs font-medium uppercase tracking-wide text-neutral-400">
            Signup Link
          </p>
          <div className="flex items-center gap-2">
            <Input
              readOnly
              value={result.invitationUrl}
              className="font-mono text-xs text-neutral-600"
            />
            <Button variant="outline" size="sm" onClick={copyUrl} className="shrink-0">
              {copied ? 'Copied!' : 'Copy'}
            </Button>
          </div>
        </div>

        <div className="mt-6 flex gap-3">
          <Button
            variant="outline"
            onClick={() => {
              setResult(null)
              setEmail('')
              setFullName('')
              setRole('reviewer')
            }}
          >
            Invite another
          </Button>
          <Button render={<Link href="/app/team" />}>Done</Button>
        </div>
      </div>
    )
  }

  return (
    <div className="max-w-lg">
      <h1 className="mb-6 text-xl font-semibold">Invite Team Member</h1>

      <form onSubmit={handleSubmit} className="space-y-5">
        <div className="space-y-1.5">
          <Label htmlFor="fullName">Full Name</Label>
          <Input
            id="fullName"
            placeholder="Jane Smith"
            value={fullName}
            onChange={(e) => setFullName(e.target.value)}
            required
            disabled={isPending}
          />
        </div>

        <div className="space-y-1.5">
          <Label htmlFor="email">Email Address</Label>
          <Input
            id="email"
            type="email"
            placeholder="jane@example.com"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
            disabled={isPending}
          />
        </div>

        <div className="space-y-1.5">
          <Label htmlFor="role">Role</Label>
          <select
            id="role"
            value={role}
            onChange={(e) => setRole(e.target.value as UserRole)}
            disabled={isPending}
            className="h-8 w-full rounded-lg border border-input bg-transparent px-2.5 text-sm outline-none transition-colors focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 disabled:cursor-not-allowed disabled:opacity-50"
          >
            <option value="team_admin">Team Admin</option>
            <option value="reviewer">Reviewer</option>
            <option value="viewer">Viewer</option>
          </select>
          <div className="flex items-center justify-between">
            <p className="text-xs text-neutral-400">
              {role === 'team_admin' && 'Can manage team membership and tenant settings.'}
              {role === 'reviewer' && 'Can perform claim evaluation work.'}
              {role === 'viewer' && 'Read-only access to claims and team.'}
            </p>
            {role === 'team_admin' && (
              <p className="text-xs text-neutral-400">
                {adminCount} of {maxAdmins} seat{maxAdmins !== 1 ? 's' : ''} used
              </p>
            )}
          </div>
        </div>

        {error && (
          <p className="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
            {error}
          </p>
        )}

        <div className="flex gap-3 pt-1">
          <Button type="submit" disabled={isPending}>
            {isPending ? 'Creating invitation…' : 'Create Invitation'}
          </Button>
          <Button type="button" variant="outline" render={<Link href="/app/team" />}>
            Cancel
          </Button>
        </div>
      </form>
    </div>
  )
}
