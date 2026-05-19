// Run with: npx tsx scripts/provision-tenant.mjs
//
// Usage:
//   npx tsx scripts/provision-tenant.mjs \
//     --name "Acme Solar" \
//     --slug "acme-solar" \
//     --email "admin@acmesolar.com" \
//     --full-name "Jane Smith" \
//     --max-team-admins 3
//
// If any required argument is omitted you will be prompted for it.
// --max-team-admins is optional and defaults to 3 if not provided.

import { readFileSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { createInterface } from 'node:readline/promises'
import { stdin as input, stdout as output } from 'node:process'

// ── Load .env.local ──────────────────────────────────────────
const __dirname = dirname(fileURLToPath(import.meta.url))
try {
  const envContent = readFileSync(resolve(__dirname, '../.env.local'), 'utf8')
  for (const line of envContent.split('\n')) {
    const trimmed = line.trim()
    if (trimmed && !trimmed.startsWith('#') && trimmed.includes('=')) {
      const eqIdx = trimmed.indexOf('=')
      const key = trimmed.slice(0, eqIdx).trim()
      const val = trimmed.slice(eqIdx + 1).trim()
      if (key && !process.env[key]) process.env[key] = val
    }
  }
} catch {
  // .env.local not found — assume env vars are already set
}

// ── Import core provisioning function ───────────────────────
// tsx resolves .js imports to their .ts counterparts
const { provisionTenant } = await import('../lib/core/provision-tenant.js')

// ── Parse CLI args ───────────────────────────────────────────
function getArg(flag) {
  const idx = process.argv.indexOf(flag)
  return idx !== -1 ? process.argv[idx + 1] : undefined
}

async function prompt(rl, question) {
  return (await rl.question(question)).trim()
}

const rl = createInterface({ input, output })

const tenantName    = getArg('--name')             ?? await prompt(rl, 'Tenant name:      ')
const tenantSlug    = getArg('--slug')             ?? await prompt(rl, 'Tenant slug:      ')
const adminEmail    = getArg('--email')            ?? await prompt(rl, 'Admin email:      ')
const adminFullName = getArg('--full-name')        ?? await prompt(rl, 'Admin full name:  ')
const maxTeamAdminsRaw = getArg('--max-team-admins') ?? '3'

rl.close()

const maxTeamAdmins = Number(maxTeamAdminsRaw)

console.log('\nProvisioning tenant…\n')

const result = await provisionTenant({
  tenantName,
  tenantSlug,
  adminEmail,
  adminFullName,
  maxTeamAdmins,
})

if (!result.success) {
  console.error(`Error: ${result.error}`)
  process.exit(1)
}

console.log('Tenant provisioned successfully.')
console.log(`  Tenant ID:        ${result.tenantId}`)
console.log(`  Tenant slug:      ${result.tenantSlug}`)
console.log(`  Max team admins:  ${maxTeamAdmins}`)
console.log()
console.log('Invitation URL (send this to the tenant admin):')
console.log()
console.log(`  ${result.invitationUrl}`)
console.log()
console.log('The link expires in 7 days. The admin will set their password on signup.')
