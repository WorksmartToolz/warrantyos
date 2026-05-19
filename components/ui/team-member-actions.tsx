'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuSub,
  DropdownMenuSubContent,
  DropdownMenuSubTrigger,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog'
import { changeRole, suspend, reactivate, remove, cancelInvite } from '@/lib/actions/manage-team'
import type { UserRole } from '@/types/database'

// ── Types ──────────────────────────────────────────────────────────────────────

type ActionType = 'suspend' | 'remove' | 'cancel-invite'

interface ConfirmState {
  action: ActionType
  label: string
  description: string
  destructive: boolean
}

// ── Member actions (active / suspended users) ─────────────────────────────────

interface MemberActionsProps {
  memberId: string
  memberName: string
  memberRole: UserRole
  memberStatus: 'active' | 'suspended'
  isCurrentUser: boolean
  isLastAdmin: boolean
  adminCount: number
  maxAdmins: number
}

export function MemberActions({
  memberId,
  memberName,
  memberRole,
  memberStatus,
  isCurrentUser,
  isLastAdmin,
  adminCount,
  maxAdmins,
}: MemberActionsProps) {
  const router = useRouter()
  const [isPending, startTransition] = useTransition()
  const [confirm, setConfirm] = useState<ConfirmState | null>(null)
  const [error, setError] = useState<string | null>(null)

  const cannotManageLastAdmin = isLastAdmin && memberRole === 'team_admin'
  const atSeatLimit = adminCount >= maxAdmins

  function handleAction(fn: () => Promise<{ success: boolean; error?: string }>) {
    startTransition(async () => {
      setError(null)
      const result = await fn()
      if (!result.success) {
        setError(result.error ?? 'An error occurred')
      } else {
        router.refresh()
      }
    })
  }

  const ROLES: { value: UserRole; label: string }[] = [
    { value: 'team_admin', label: 'Team Admin' },
    { value: 'reviewer', label: 'Reviewer' },
    { value: 'viewer', label: 'Viewer' },
  ]

  return (
    <>
      {error && (
        <p className="mt-1 text-xs text-red-600">{error}</p>
      )}

      <DropdownMenu>
        <DropdownMenuTrigger
          disabled={isPending}
          className="inline-flex h-7 items-center justify-center rounded-[min(var(--radius-md),12px)] px-2.5 text-sm text-neutral-500 outline-none transition-all hover:bg-muted hover:text-foreground aria-expanded:bg-muted aria-expanded:text-foreground disabled:pointer-events-none disabled:opacity-50"
        >
          •••
        </DropdownMenuTrigger>

        <DropdownMenuContent align="end" className="w-48">
          {/* Change Role submenu */}
          <DropdownMenuSub>
            <DropdownMenuSubTrigger>Change Role</DropdownMenuSubTrigger>
            <DropdownMenuSubContent>
              {ROLES.map(({ value, label }) => {
                const isCurrent = value === memberRole
                const wouldExceedSeats = value === 'team_admin' && memberRole !== 'team_admin' && atSeatLimit
                const wouldDemoteLastAdmin = value !== 'team_admin' && memberRole === 'team_admin' && isLastAdmin
                const disabled = isCurrent || wouldExceedSeats || wouldDemoteLastAdmin

                return (
                  <DropdownMenuItem
                    key={value}
                    disabled={disabled}
                    onSelect={() => handleAction(() => changeRole(memberId, value))}
                    className={isCurrent ? 'font-medium' : undefined}
                  >
                    {label}
                    {isCurrent && <span className="ml-auto text-xs text-neutral-400">current</span>}
                    {wouldExceedSeats && <span className="ml-auto text-xs text-neutral-400">seats full</span>}
                    {wouldDemoteLastAdmin && <span className="ml-auto text-xs text-neutral-400">last admin</span>}
                  </DropdownMenuItem>
                )
              })}
            </DropdownMenuSubContent>
          </DropdownMenuSub>

          <DropdownMenuSeparator />

          {/* Suspend / Reactivate */}
          {memberStatus === 'active' ? (
            <DropdownMenuItem
              disabled={cannotManageLastAdmin}
              onSelect={() =>
                setConfirm({
                  action: 'suspend',
                  label: 'Suspend user',
                  description: `${memberName}'s access will be blocked immediately. You can reactivate them at any time.`,
                  destructive: false,
                })
              }
            >
              Suspend
              {cannotManageLastAdmin && <span className="ml-auto text-xs text-neutral-400">last admin</span>}
            </DropdownMenuItem>
          ) : (
            <DropdownMenuItem onSelect={() => handleAction(() => reactivate(memberId))}>
              Reactivate
            </DropdownMenuItem>
          )}

          {/* Remove */}
          <DropdownMenuItem
            disabled={cannotManageLastAdmin}
            className="text-red-600 focus:text-red-600"
            onSelect={() =>
              setConfirm({
                action: 'remove',
                label: 'Remove user',
                description: `${memberName} will lose all access. Their historical data and audit records are preserved. This cannot be undone from the UI.`,
                destructive: true,
              })
            }
          >
            Remove
            {cannotManageLastAdmin && <span className="ml-auto text-xs text-neutral-400">last admin</span>}
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>

      {/* Confirmation dialog */}
      <AlertDialog open={confirm !== null} onOpenChange={(open) => !open && setConfirm(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{confirm?.label}</AlertDialogTitle>
            <AlertDialogDescription>{confirm?.description}</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              className={confirm?.destructive ? 'bg-red-600 hover:bg-red-700' : undefined}
              onClick={() => {
                if (!confirm) return
                const action = confirm.action
                setConfirm(null)
                if (action === 'suspend') handleAction(() => suspend(memberId))
                if (action === 'remove') handleAction(() => remove(memberId))
              }}
            >
              Confirm
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  )
}

// ── Invitation actions ─────────────────────────────────────────────────────────

interface InvitationActionsProps {
  invitationId: string
  invitationUrl: string
  inviteeEmail: string
}

export function InvitationActions({
  invitationId,
  invitationUrl,
  inviteeEmail,
}: InvitationActionsProps) {
  const router = useRouter()
  const [isPending, startTransition] = useTransition()
  const [confirm, setConfirm] = useState(false)
  const [copied, setCopied] = useState(false)
  const [error, setError] = useState<string | null>(null)

  function copyLink() {
    navigator.clipboard.writeText(invitationUrl).then(() => {
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    })
  }

  function handleCancel() {
    startTransition(async () => {
      setError(null)
      const result = await cancelInvite(invitationId)
      if (!result.success) {
        setError(result.error ?? 'An error occurred')
      } else {
        router.refresh()
      }
    })
  }

  return (
    <>
      {error && <p className="mt-1 text-xs text-red-600">{error}</p>}

      <DropdownMenu>
        <DropdownMenuTrigger
          disabled={isPending}
          className="inline-flex h-7 items-center justify-center rounded-[min(var(--radius-md),12px)] px-2.5 text-sm text-neutral-500 outline-none transition-all hover:bg-muted hover:text-foreground aria-expanded:bg-muted aria-expanded:text-foreground disabled:pointer-events-none disabled:opacity-50"
        >
          •••
        </DropdownMenuTrigger>

        <DropdownMenuContent align="end" className="w-40">
          <DropdownMenuItem onSelect={copyLink}>
            {copied ? 'Copied!' : 'Copy Link'}
          </DropdownMenuItem>
          <DropdownMenuSeparator />
          <DropdownMenuItem
            className="text-red-600 focus:text-red-600"
            onSelect={() => setConfirm(true)}
          >
            Cancel Invite
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>

      <AlertDialog open={confirm} onOpenChange={setConfirm}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Cancel invitation</AlertDialogTitle>
            <AlertDialogDescription>
              The invitation link sent to {inviteeEmail} will be invalidated immediately. You can send a new invitation at any time.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Keep</AlertDialogCancel>
            <AlertDialogAction
              className="bg-red-600 hover:bg-red-700"
              onClick={() => { setConfirm(false); handleCancel() }}
            >
              Cancel invite
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  )
}
