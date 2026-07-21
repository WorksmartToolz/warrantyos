import { createAdminClient } from '@/lib/supabase/admin'

export type LookupResult =
  | { success: true }
  | { success: false; error: string }

export type CreateLookupResult =
  | { success: true; id: string }
  | { success: false; error: string }

// 17.A.1 guarantees all pattern lookup tables are structurally identical, so
// one implementation serves both. Constrain the table param to the concrete
// literal set (same soundness technique the validation helper uses).
export type LookupTable = 'inspection_types' | 'inspection_triggers'

type LockTier = 'platform_locked' | 'platform_seeded' | 'tenant_added'

// ── Slugification (arch-ref 6749-6752) ────────────────────────────────────────
// Deterministic, applied once at row creation, never re-derived. Lowercase,
// non-alphanumeric runs collapse to a single underscore, trimmed of leading/
// trailing underscores. "Site Inspection" -> "site_inspection".
export function slugify(label: string): string {
  return label
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
}

// ── Internal helpers ──────────────────────────────────────────────────────────

interface CallerProfile {
  tenantId: string
}

// Definition management is a tenant-admin capability (arch-ref 781-782), so
// lookup-default CRUD gates on team_admin — the deliberate inverse of the
// operational inspection-create path (reviewer || team_admin). Mirrors the
// manage-team governance gate.
async function fetchCallerProfile(requestedBy: string): Promise<CallerProfile | null> {
  const admin = createAdminClient()
  const { data } = await admin
    .from('users')
    .select('role, tenant_id, status, removed_at')
    .eq('id', requestedBy)
    .single()

  if (!data) return null
  if (data.role !== 'team_admin') return null
  if (data.status !== 'active') return null
  if (data.removed_at) return null

  return { tenantId: data.tenant_id }
}

interface LookupRow {
  id: string
  tenant_id: string
  lock_tier: LockTier
  disabled_at: string | null
  deleted_at: string | null
}

// Loads a row and enforces the tenant-match invariant. Returns the row, a
// structured error, or null (not found).
async function fetchLookupRow(
  table: LookupTable,
  id: string,
  callerTenantId: string
): Promise<LookupRow | { error: string } | null> {
  const admin = createAdminClient()
  const { data } = await admin
    .from(table)
    .select('id, tenant_id, lock_tier, disabled_at, deleted_at')
    .eq('id', id)
    .single<LookupRow>()

  if (!data) return null
  if (data.tenant_id !== callerTenantId) return { error: 'Cross-tenant operation not allowed' }
  return data
}

// ── Exported operations ───────────────────────────────────────────────────────

// CREATE — tenant_added only (arch-ref 7090). value auto-slugified from label,
// uniqueness within (tenant_id, table) enforced app-layer at creation
// (arch-ref 6751-6752). Reject on collision — the locked-consistent minimum,
// since auto-suffixing would mint a value the tenant did not author and the
// arch-ref stresses value stability. Revisit if real usage wants suffixing.
export async function createLookupValue(
  table: LookupTable,
  label: string,
  requestedBy: string
): Promise<CreateLookupResult> {
  const caller = await fetchCallerProfile(requestedBy)
  if (!caller) return { success: false, error: 'Unauthorized' }

  const trimmed = label.trim()
  if (!trimmed) return { success: false, error: 'Label is required' }

  const value = slugify(trimmed)
  if (!value) return { success: false, error: 'Label must contain at least one letter or number' }

  const admin = createAdminClient()

  // App-layer uniqueness check on value within (tenant_id, table).
  const { data: existing } = await admin
    .from(table)
    .select('id')
    .eq('tenant_id', caller.tenantId)
    .eq('value', value)
    .maybeSingle()

  if (existing) return { success: false, error: 'A value with that name already exists' }

  const { data: inserted, error } = await admin
    .from(table)
    .insert({
      tenant_id: caller.tenantId,
      value,
      label: trimmed,
      lock_tier: 'tenant_added',
    })
    .select('id')
    .single()

  if (error || !inserted) {
    return { success: false, error: `Failed to create value: ${error?.message ?? 'unknown error'}` }
  }
  return { success: true, id: inserted.id }
}

// RENAME — edits label only; value is immutable for all tiers (17.A.4).
// Permitted for platform_seeded and tenant_added; NOT platform_locked.
export async function renameLookupValue(
  table: LookupTable,
  id: string,
  newLabel: string,
  requestedBy: string
): Promise<LookupResult> {
  const caller = await fetchCallerProfile(requestedBy)
  if (!caller) return { success: false, error: 'Unauthorized' }

  const trimmed = newLabel.trim()
  if (!trimmed) return { success: false, error: 'Label is required' }

  const row = await fetchLookupRow(table, id, caller.tenantId)
  if (!row) return { success: false, error: 'Value not found' }
  if ('error' in row) return { success: false, error: row.error }
  if (row.lock_tier === 'platform_locked') {
    return { success: false, error: 'Platform-locked values cannot be renamed' }
  }

  const admin = createAdminClient()
  const { error } = await admin.from(table).update({ label: trimmed }).eq('id', id)
  if (error) return { success: false, error: `Failed to rename value: ${error.message}` }
  return { success: true }
}

// DISABLE — sets disabled_at. Applies to ALL lock_tiers (17.A.7).
export async function disableLookupValue(
  table: LookupTable,
  id: string,
  requestedBy: string
): Promise<LookupResult> {
  const caller = await fetchCallerProfile(requestedBy)
  if (!caller) return { success: false, error: 'Unauthorized' }

  const row = await fetchLookupRow(table, id, caller.tenantId)
  if (!row) return { success: false, error: 'Value not found' }
  if ('error' in row) return { success: false, error: row.error }
  if (row.disabled_at) return { success: false, error: 'Value is already disabled' }

  const admin = createAdminClient()
  const { error } = await admin
    .from(table)
    .update({ disabled_at: new Date().toISOString() })
    .eq('id', id)
  if (error) return { success: false, error: `Failed to disable value: ${error.message}` }
  return { success: true }
}

// ENABLE — clears disabled_at. Applies to ALL lock_tiers (the "view disabled"
// re-enable surface, 17.A.7).
export async function enableLookupValue(
  table: LookupTable,
  id: string,
  requestedBy: string
): Promise<LookupResult> {
  const caller = await fetchCallerProfile(requestedBy)
  if (!caller) return { success: false, error: 'Unauthorized' }

  const row = await fetchLookupRow(table, id, caller.tenantId)
  if (!row) return { success: false, error: 'Value not found' }
  if ('error' in row) return { success: false, error: row.error }
  if (!row.disabled_at) return { success: false, error: 'Value is already active' }

  const admin = createAdminClient()
  const { error } = await admin.from(table).update({ disabled_at: null }).eq('id', id)
  if (error) return { success: false, error: `Failed to enable value: ${error.message}` }
  return { success: true }
}

// SOFT-DELETE — sets deleted_at. tenant_added ONLY (17.A.7).
export async function softDeleteLookupValue(
  table: LookupTable,
  id: string,
  requestedBy: string
): Promise<LookupResult> {
  const caller = await fetchCallerProfile(requestedBy)
  if (!caller) return { success: false, error: 'Unauthorized' }

  const row = await fetchLookupRow(table, id, caller.tenantId)
  if (!row) return { success: false, error: 'Value not found' }
  if ('error' in row) return { success: false, error: row.error }
  if (row.lock_tier !== 'tenant_added') {
    return { success: false, error: 'Only tenant-added values can be deleted' }
  }
  if (row.deleted_at) return { success: false, error: 'Value is already deleted' }

  const admin = createAdminClient()
  const { error } = await admin
    .from(table)
    .update({ deleted_at: new Date().toISOString() })
    .eq('id', id)
  if (error) return { success: false, error: `Failed to delete value: ${error.message}` }
  return { success: true }
}
