'use server'

import {
  provisionTenant as coreProvisionTenant,
  type ProvisionTenantInput,
  type ProvisionTenantResult,
} from '@/lib/core/provision-tenant'

// Server Action wrapper. Called by future admin UI.
// The CLI scripts call lib/core/provision-tenant directly.
export async function provisionTenant(
  input: ProvisionTenantInput
): Promise<ProvisionTenantResult> {
  return coreProvisionTenant(input)
}
