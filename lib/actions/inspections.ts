'use server'
import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import {
  insertInspection,
  type CreateInspectionInput,
  type CreateInspectionResult,
} from '@/lib/core/inspections'

async function getCallerId(): Promise<string | null> {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  return user?.id ?? null
}

// Revalidation per the locked convention (arch-ref 340-377): the page that
// displays the record plus the parent that aggregates it. Targets identified
// per-mutation using the team template. These routes are not built yet;
// revalidatePath against a non-existent route is a safe no-op until the UI
// lands, at which point these become live automatically.
function revalidateInspectionPages(claimId: string) {
  revalidatePath(`/app/claims/${claimId}`)
  revalidatePath('/app')
}

export async function createInspection(
  input: CreateInspectionInput
): Promise<CreateInspectionResult> {
  const callerId = await getCallerId()
  if (!callerId) return { success: false, error: 'Not authenticated' }

  const result = await insertInspection(input, callerId)
  if (result.success) revalidateInspectionPages(input.claim_id)
  return result
}
