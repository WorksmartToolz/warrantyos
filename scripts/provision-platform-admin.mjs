// Run with: npx tsx scripts/provision-platform-admin.mjs
//
// Usage:
//   npx tsx scripts/provision-platform-admin.mjs \
//     --email "you@example.com" \
//     --password "yourpassword" \
//     --name "Your Name"
//
// Creates a platform admin auth user with is_platform_admin: true in
// user_metadata. Platform admins have NO row in public.users — they are
// auth-layer identities only and cannot see tenant data through RLS.
//
// Run this once to bootstrap yourself. Do not run it for tenant users.

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

// ── Validate environment ─────────────────────────────────────
const supabaseUrl     = process.env.NEXT_PUBLIC_SUPABASE_URL
const serviceRoleKey  = process.env.SUPABASE_SERVICE_ROLE_KEY

if (!supabaseUrl || !serviceRoleKey) {
  console.error('Error: NEXT_PUBLIC_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set in .env.local')
  process.exit(1)
}

// ── Create service-role client ───────────────────────────────
// Import directly (no TypeScript wrapper needed here)
const { createClient } = await import('@supabase/supabase-js')
const admin = createClient(supabaseUrl, serviceRoleKey, {
  auth: { autoRefreshToken: false, persistSession: false },
})

// ── Parse CLI args or prompt ─────────────────────────────────
function getArg(flag) {
  const idx = process.argv.indexOf(flag)
  return idx !== -1 ? process.argv[idx + 1] : undefined
}

async function prompt(rl, question) {
  return (await rl.question(question)).trim()
}

const rl = createInterface({ input, output })

const email    = getArg('--email')    ?? await prompt(rl, 'Email:      ')
const password = getArg('--password') ?? await prompt(rl, 'Password:   ')
const fullName = getArg('--name')     ?? await prompt(rl, 'Full name:  ')

rl.close()

if (!email || !password) {
  console.error('Error: email and password are required')
  process.exit(1)
}

console.log('\nCreating platform admin…\n')

const { data, error } = await admin.auth.admin.createUser({
  email: email.trim().toLowerCase(),
  password,
  email_confirm: true,
  user_metadata: {
    full_name: fullName.trim() || email,
    // This flag is the platform admin identity mechanism.
    // The middleware reads it from the JWT on every request.
    // Never set this on tenant users.
    is_platform_admin: true,
  },
})

if (error) {
  console.error(`Error: ${error.message}`)
  process.exit(1)
}

console.log('Platform admin created successfully.')
console.log(`  User ID: ${data.user.id}`)
console.log(`  Email:   ${data.user.email}`)
console.log()
console.log(`Sign in at: ${process.env.NEXT_PUBLIC_APP_URL ?? 'http://localhost:3000'}/login`)
