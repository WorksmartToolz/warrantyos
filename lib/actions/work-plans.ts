'use server'
import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import {
  insertWorkPlan,
  transitionWorkPlanStatus,
  editWorkPlan,
  type CreateWorkPlanInput,
  type CreateWorkPlanResult,
  type WorkPlanStatus,
  type WorkPlanTransitionOutcome,
  type EditWorkPlanInput,
  type EditWorkPlanResult,
} from '@/lib/core/work-plans'

// C4 action layer. Thin by convention (mirrors lib/actions/inspections.ts):
// resolve the authenticated caller, delegate all authz + validation + write to
// core, revalidate on success. No business logic here.

async function getCallerId(): Promise<string | null> {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  return user?.id ?? null
}

// Revalidation per the locked convention (arch-ref 340-377): the page that
// displays the record plus the parent that aggregates it. A Work Plan is
// aggregated on its parent claim's page. These routes are not built yet;
// revalidatePath against a non-existent route is a safe no-op until the UI
// lands, at which point these become live automatically.
function revalidateWorkPlanPages(claimId: string) {
  revalidatePath(`/app/claims/${claimId}`)
  revalidatePath('/app')
}

export async function createWorkPlan(
  input: CreateWorkPlanInput
): Promise<CreateWorkPlanResult> {
  const callerId = await getCallerId()
  if (!callerId) return { success: false, error: 'Not authenticated' }

  const result = await insertWorkPlan(input, callerId)
  if (result.success) revalidateWorkPlanPages(input.claim_id)
  return result
}

// ── C4 status machine + edit (action wrappers) ───────────────────────────────
// Same thin convention as createWorkPlan: resolve caller, delegate to core,
// revalidate on success. Action verbs differ from core verbs per the
// insert/create precedent:
//   core transitionWorkPlanStatus → action changeWorkPlanStatus
//   core editWorkPlan             → action updateWorkPlan
// Both core functions return claimId, so both reuse revalidateWorkPlanPages.

export async function changeWorkPlanStatus(
  workPlanId: string,
  to: WorkPlanStatus
): Promise<WorkPlanTransitionOutcome> {
  const callerId = await getCallerId()
  if (!callerId) return { success: false, error: 'Not authenticated' }
  const result = await transitionWorkPlanStatus(workPlanId, to, callerId)
  if (result.success) revalidateWorkPlanPages(result.claimId)
  return result
}

export async function updateWorkPlan(
  workPlanId: string,
  patch: EditWorkPlanInput
): Promise<EditWorkPlanResult> {
  const callerId = await getCallerId()
  if (!callerId) return { success: false, error: 'Not authenticated' }
  const result = await editWorkPlan(workPlanId, patch, callerId)
  if (result.success) revalidateWorkPlanPages(result.claimId)
  return result
}
