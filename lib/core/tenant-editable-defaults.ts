import { createAdminClient } from '@/lib/supabase/admin'
import type { Database } from '@/types/database'

export type TenantEditableDefaultsTable =
  | 'inspection_types'
  | 'inspection_triggers'

type DefaultsRow<T extends TenantEditableDefaultsTable> =
  Database['public']['Tables'][T]['Row']

type DefaultsRowConcrete =
  Database['public']['Tables']['inspection_types']['Row']

// Single canonical validation helper (Decision 17.A.6 commitment 1).
// Rule (arch-ref Tenant-Editable Defaults "Defense-in-Depth"):
//   row exists AND tenant_id matches AND disabled_at IS NULL
//   AND deleted_at IS NULL AND lock_tier permits the operation.
// lock_tier clause intentionally omitted: it governs edits to the
// lookup row, not an operational row REFERENCING it, so on the
// operational write path it is structurally satisfied. No `operation`
// param (ratified Chat 21). Do not add one without a lock_tier-gated
// write path that needs it.
// Service-role client — Server Actions and CLI scripts only, never
// browser-side. Mirrors validateInvitationToken (lib/core/invitations.ts).
export async function validateTenantEditableDefaultsReference<
  T extends TenantEditableDefaultsTable,
>(
  tableName: T,
  id: string,
  tenantId: string
): Promise<DefaultsRow<T> | null> {
  const admin = createAdminClient()
  const { data, error } = await admin
    .from(tableName as 'inspection_types')
    .select('*')
    .eq('id', id)
    .eq('tenant_id', tenantId)
    .is('disabled_at', null)
    .is('deleted_at', null)
    .maybeSingle<DefaultsRowConcrete>()
  if (error || !data) return null
  return data as DefaultsRow<T>
}
