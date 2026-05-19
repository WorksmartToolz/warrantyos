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

export default async function TeamPage() {
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) redirect('/login')

  const { data: members } = await supabase
    .from('users')
    .select('id, full_name, email, role, created_at')
    .order('created_at', { ascending: false })

  return (
    <div className="p-8">
      <div className="mb-6 flex items-center justify-between">
        <h1 className="text-xl font-semibold">Team</h1>
        <span title="Coming in Session 5b" className="cursor-not-allowed">
          <Button size="sm" disabled>
            Invite Team Member
          </Button>
        </span>
      </div>

      {!members || members.length === 0 ? (
        <p className="text-sm text-neutral-400">No team members yet.</p>
      ) : (
        <div className="overflow-hidden rounded-xl border border-neutral-200 bg-white">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Name</TableHead>
                <TableHead>Email</TableHead>
                <TableHead>Role</TableHead>
                <TableHead>Joined</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {members.map((member) => (
                <TableRow key={member.id}>
                  <TableCell className="font-medium">
                    {member.full_name ?? '—'}
                  </TableCell>
                  <TableCell className="text-neutral-500">{member.email}</TableCell>
                  <TableCell>
                    <Badge variant="outline" className={roleBadgeClass(member.role)}>
                      {roleLabel(member.role)}
                    </Badge>
                  </TableCell>
                  <TableCell className="text-neutral-500">
                    {new Date(member.created_at).toLocaleDateString('en-US', {
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
