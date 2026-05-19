import Link from 'next/link'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { MemberActions, InvitationActions } from '@/components/ui/team-member-actions'
import type { UserRole } from '@/types/database'

function roleBadgeClass(role: UserRole) {
  switch (role) {
    case 'team_admin': return 'bg-amber-50 text-amber-700 border-amber-200'
    case 'reviewer':   return 'bg-blue-50 text-blue-700 border-blue-200'
    case 'viewer':     return 'bg-neutral-50 text-neutral-600 border-neutral-200'
  }
}

function roleLabel(role: UserRole) {
  switch (role) {
    case 'team_admin': return 'Team Admin'
    case 'reviewer':   return 'Reviewer'
    case 'viewer':     return 'Viewer'
  }
}

function daysAgo(dateStr: string): string {
  const days = Math.floor((Date.now() - new Date(dateStr).getTime()) / 86_400_000)
  if (days === 0) return 'today'
  if (days === 1) return '1 day ago'
  return `${days} days ago`
}

const APP_URL = process.env.NEXT_PUBLIC_APP_URL ?? 'http://localhost:3000'

export default async function TeamPage() {
  const supabase = await createClient()

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: currentProfile } = await supabase
    .from('users')
    .select('role, tenant_id')
    .eq('id', user.id)
    .single()

  if (!currentProfile) redirect('/login')

  const { tenantId, role: viewerRole } = { tenantId: currentProfile.tenant_id, role: currentProfile.role }
  const isAdmin = viewerRole === 'team_admin'

  // Fetch members (active + suspended; exclude removed)
  const { data: members } = await supabase
    .from('users')
    .select('id, full_name, email, role, status, created_at')
    .is('removed_at', null)
    .order('created_at', { ascending: true })

  // Fetch pending invitations (not consumed, not expired).
  // Token is included to construct the copy-link URL — it's an intended-to-be-shared
  // value, and the RLS policy already restricts these rows to the caller's tenant.
  const { data: pendingInvitations } = await supabase
    .from('invitations')
    .select('id, email, role, full_name, token, created_at')
    .is('consumed_at', null)
    .gt('expires_at', new Date().toISOString())
    .order('created_at', { ascending: false })

  // Compute seat stats for role change hints
  const adminCount = members?.filter(m => m.role === 'team_admin' && m.status === 'active').length ?? 0
  const isLastAdmin = adminCount <= 1

  // Fetch max_team_admins from tenant (uses existing tenant read policy)
  const { data: tenant } = await supabase
    .from('tenants')
    .select('max_team_admins')
    .eq('id', tenantId)
    .single()

  const maxAdmins = tenant?.max_team_admins ?? 3

  return (
    <div className="p-8">
      <div className="mb-6 flex items-center justify-between">
        <h1 className="text-xl font-semibold">Team</h1>
        {isAdmin ? (
          <Button size="sm" render={<Link href="/app/team/invite" />}>
            Invite Team Member
          </Button>
        ) : (
          <span title="Only team admins can invite members" className="cursor-not-allowed">
            <Button size="sm" disabled>Invite Team Member</Button>
          </span>
        )}
      </div>

      {/* Active and suspended members */}
      {!members || members.length === 0 ? (
        <p className="text-sm text-neutral-400">No team members yet.</p>
      ) : (
        <div className="mb-8 overflow-hidden rounded-xl border border-neutral-200 bg-white">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Name</TableHead>
                <TableHead>Email</TableHead>
                <TableHead>Role</TableHead>
                <TableHead>Status</TableHead>
                <TableHead>Joined</TableHead>
                {isAdmin && <TableHead className="w-16" />}
              </TableRow>
            </TableHeader>
            <TableBody>
              {members.map((member) => (
                <TableRow key={member.id} className={member.status === 'suspended' ? 'opacity-60' : undefined}>
                  <TableCell className="font-medium">
                    {member.full_name ?? '—'}
                    {member.id === user.id && (
                      <span className="ml-2 text-xs text-neutral-400">you</span>
                    )}
                  </TableCell>
                  <TableCell className="text-neutral-500">{member.email}</TableCell>
                  <TableCell>
                    <Badge variant="outline" className={roleBadgeClass(member.role)}>
                      {roleLabel(member.role)}
                    </Badge>
                  </TableCell>
                  <TableCell>
                    {member.status === 'suspended' ? (
                      <Badge variant="outline" className="border-orange-200 bg-orange-50 text-orange-700">
                        Suspended
                      </Badge>
                    ) : (
                      <span className="text-sm text-neutral-400">Active</span>
                    )}
                  </TableCell>
                  <TableCell className="text-neutral-500">
                    {new Date(member.created_at).toLocaleDateString('en-US', {
                      year: 'numeric',
                      month: 'short',
                      day: 'numeric',
                    })}
                  </TableCell>
                  {isAdmin && (
                    <TableCell className="text-right">
                      <MemberActions
                        memberId={member.id}
                        memberName={member.full_name ?? member.email}
                        memberRole={member.role}
                        memberStatus={member.status}
                        isCurrentUser={member.id === user.id}
                        isLastAdmin={isLastAdmin && member.role === 'team_admin'}
                        adminCount={adminCount}
                        maxAdmins={maxAdmins}
                      />
                    </TableCell>
                  )}
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}

      {/* Pending invitations */}
      {isAdmin && pendingInvitations && pendingInvitations.length > 0 && (
        <div>
          <h2 className="mb-3 text-sm font-medium text-neutral-500">Pending Invitations</h2>
          <div className="overflow-hidden rounded-xl border border-neutral-200 bg-white">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Name</TableHead>
                  <TableHead>Email</TableHead>
                  <TableHead>Role</TableHead>
                  <TableHead>Invited</TableHead>
                  <TableHead className="w-16" />
                </TableRow>
              </TableHeader>
              <TableBody>
                {pendingInvitations.map((invite) => (
                  <TableRow key={invite.id} className="bg-neutral-50/50">
                    <TableCell className="text-neutral-500">{invite.full_name ?? '—'}</TableCell>
                    <TableCell className="text-neutral-500">{invite.email}</TableCell>
                    <TableCell>
                      <Badge variant="outline" className={roleBadgeClass(invite.role)}>
                        {roleLabel(invite.role)}
                      </Badge>
                    </TableCell>
                    <TableCell className="text-neutral-400 text-sm">
                      {daysAgo(invite.created_at)}
                    </TableCell>
                    <TableCell className="text-right">
                      <InvitationActions
                        invitationId={invite.id}
                        invitationUrl={`${APP_URL}/signup?token=${invite.token}`}
                        inviteeEmail={invite.email}
                      />
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        </div>
      )}
    </div>
  )
}
