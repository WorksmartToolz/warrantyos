'use server'
import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import {
  createLookupValue,
  renameLookupValue,
  disableLookupValue,
  enableLookupValue,
  softDeleteLookupValue,
  type LookupTable,
  type LookupResult,
  type CreateLookupResult,
} from '@/lib/core/lookup-defaults'

async function getCallerId(): Promise<string | null> {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  return user?.id ?? null
}

// Revalidation per the locked convention (arch-ref 340-377). The tenant
// lookup-admin settings surface does not exist yet (roadmap F10); revalidatePath
// against a non-existent route is a safe no-op until that UI lands.
function revalidateLookupPages() {
  revalidatePath('/app/settings')
  revalidatePath('/app')
}

export async function createLookup(
  table: LookupTable,
  label: string
): Promise<CreateLookupResult> {
  const callerId = await getCallerId()
  if (!callerId) return { success: false, error: 'Not authenticated' }
  const result = await createLookupValue(table, label, callerId)
  if (result.success) revalidateLookupPages()
  return result
}

export async function renameLookup(
  table: LookupTable,
  id: string,
  newLabel: string
): Promise<LookupResult> {
  const callerId = await getCallerId()
  if (!callerId) return { success: false, error: 'Not authenticated' }
  const result = await renameLookupValue(table, id, newLabel, callerId)
  if (result.success) revalidateLookupPages()
  return result
}

export async function disableLookup(
  table: LookupTable,
  id: string
): Promise<LookupResult> {
  const callerId = await getCallerId()
  if (!callerId) return { success: false, error: 'Not authenticated' }
  const result = await disableLookupValue(table, id, callerId)
  if (result.success) revalidateLookupPages()
  return result
}

export async function enableLookup(
  table: LookupTable,
  id: string
): Promise<LookupResult> {
  const callerId = await getCallerId()
  if (!callerId) return { success: false, error: 'Not authenticated' }
  const result = await enableLookupValue(table, id, callerId)
  if (result.success) revalidateLookupPages()
  return result
}

export async function softDeleteLookup(
  table: LookupTable,
  id: string
): Promise<LookupResult> {
  const callerId = await getCallerId()
  if (!callerId) return { success: false, error: 'Not authenticated' }
  const result = await softDeleteLookupValue(table, id, callerId)
  if (result.success) revalidateLookupPages()
  return result
}
