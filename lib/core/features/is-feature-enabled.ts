import { createAdminClient } from '@/lib/supabase/admin'

// ─────────────────────────────────────────────────────────────────────────────
// D2 — Feature Flag Reader (the single source of truth for "is this feature on
// for this tenant")
//
// Source of truth: architecture-reference.md "The feature flag system", part 2
// ("Application-layer helper") and part 4 ("Defaults at provisioning"). Phase-1
// flag set is locked to the three flags the arch-ref names.
//
// STORAGE CHOICE (arch-ref part 1 — an open Phase 3 implementation detail):
// this reader uses the JSONB shape `tenants.settings.enabled_features`, the
// arch-ref's named "lighter starting point" and the shape provision-tenant.ts
// already uses for every other tenant setting. The arch-ref writes the whole
// feature-flag section "to hold either way" and encapsulates the storage choice
// behind THIS ONE FUNCTION (part 2): no Server Action or Server Component reads
// the flag storage directly. The "natural upgrade" to a dedicated
// `tenant_features` table (its own audit trail of who toggled what and when)
// therefore remains fully available and would change only the internals of this
// function — every caller is insulated. Building JSONB now is not a foreclosure
// of that fork; it is the arch-ref's intended Phase-1 shape.
//
// Reader idiom mirrors C10's escalationVerdictAuthorizedRole
// (lib/core/claim-progression.ts): a validated read of tenants.settings through
// the admin client with a safe fallback. See FALLBACK POLICY below for the
// absent/malformed case (fails closed, does not assume the provisioning default).
// ─────────────────────────────────────────────────────────────────────────────

// The locked Phase-1 flag set (arch-ref "Phase 1 features"). A union, not a bare
// string, so an unknown flag name is a compile error rather than a silent false.
export type FeatureFlag =
  | 'epc_workflow'
  | 'supply_only_workflow'
  | 'service_report_acquiesce_window'

// FALLBACK POLICY. If a tenant's enabled_features is absent or malformed, or the
// specific key is missing, the feature reads as DISABLED (false). This is the
// safe default for a gate: a missing flag must not silently open a feature-gated
// path. Provisioning (part 4) seeds all three flags enabled, so a correctly
// provisioned tenant never hits this fallback; it exists only to fail closed if
// the settings blob is ever incomplete. (Note this is the opposite polarity from
// C10's escalation reader, whose safe default is the MORE restrictive role — in
// both cases the fallback is the safe direction; for a feature gate that is
// "off".)
export async function isFeatureEnabled(
  tenantId: string,
  feature: FeatureFlag
): Promise<boolean> {
  const admin = createAdminClient()
  const { data } = await admin
    .from('tenants')
    .select('settings')
    .eq('id', tenantId)
    .single()

  const settings = data?.settings as Record<string, unknown> | null
  const enabledFeatures = settings?.enabled_features as
    | Record<string, unknown>
    | null
    | undefined

  // Strict boolean check: only an explicit `true` enables. Any other value
  // (false, absent, malformed) fails closed.
  return enabledFeatures?.[feature] === true
}
