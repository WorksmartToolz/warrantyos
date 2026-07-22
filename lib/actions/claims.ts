'use server'
import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import {
  transitionClaimStatus,
  type ClaimStatus,
  type TransitionResult,
} from '@/lib/core/claim-progression'

// C10 action layer. Thin by convention (mirrors lib/actions/inspections.ts):
// resolve the authenticated caller, delegate all authz + transition logic to
// core, revalidate on success. No business logic here.
//
// The system-initiated path (transitionClaimStatusAsSystem) is intentionally
// NOT exported as a Server Action — it is called by the B-layer/cron subsystem,
// not from the browser. Exposing it here would let a client fire clock-driven
// transitions manually, which core already rejects; keeping it out of the
// action layer removes the surface entirely.

async function getCallerId(): Promise<string | null> {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  return user?.id ?? null
}

// Revalidation per the locked convention (arch-ref 340-377) and the inspections
// precedent: the claim page plus the parent aggregate. These routes are not
// built yet; revalidatePath against a non-existent route is a safe no-op until
// the UI lands, at which point it becomes live automatically.
function revalidateClaimPages(claimId: string) {
  revalidatePath(`/app/claims/${claimId}`)
  revalidatePath('/app')
}

export async function progressClaim(
  claimId: string,
  to: ClaimStatus
): Promise<TransitionResult> {
  const callerId = await getCallerId()
  if (!callerId) return { success: false, error: 'Not authenticated' }

  const result = await transitionClaimStatus(claimId, to, callerId)
  if (result.success) revalidateClaimPages(claimId)
  return result
}
