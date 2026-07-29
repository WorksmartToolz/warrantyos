import { randomBytes } from 'node:crypto'
import { createAdminClient } from '@/lib/supabase/admin'
// ─────────────────────────────────────────────────────────────────────────────
// E1 — Stateless Tokenized Interaction: shared token primitives
//
// Source of truth: architecture-reference.md "Stateless Tokenized Interaction
// Pattern" (232-330), plus Decision 35 (validate/consume resolved). The pattern
// names the team-invitation flow (lib/core/invitations.ts) as "the SHAPE to
// copy, not a shared store." Each of the six surfaces keeps its own token on its
// OWN record (claims.intake_token, work_authorization_documents.customer_token,
// ala_documents.claimant_token, notices_of_defect.recipient_token,
// service_reports.submission_token + .customer_review_token); this module
// centralizes the mechanics that are identical across all of them, so they are
// "decided once and reused" rather than reinvented.
//
// THE TWO PURE primitives (table-agnostic, no database):
//   * generateToken()      — the high-entropy token (64-char hex / 32 bytes).
//   * tokenExpiresAt(days)  — the expiry timestamp, TTL supplied by the caller.
//
// THE VALIDATE + CONSUME pair (Decision 35 — resolved at first consumer, C3):
//   The per-row surfaces built NO consumed_at column (022/025/026/027/028 are
//   all two-column: {name}_token + {name}_token_expires_at). So the invitation
//   precedent's consumed_at-based validate/consume CANNOT be copied. Decision 35
//   locks the mechanism instead:
//     * validate = token matches AND token IS NOT NULL AND {token}_expires_at
//                  > now(). A null token is unvalidatable (unissued OR consumed).
//     * consume  = set the token column to NULL, in the SAME atomic Server
//                  Action that writes the surface's domain result. The audit
//                  trail is carried by that domain state (responded_at /
//                  signed_at / reviewed_at / status transition), NOT the token.
//   Parameterized per (table, tokenColumn) — 028 carries TWO tokens, so this
//   keys on the token COLUMN, not the surface. The dynamic-table shape follows
//   the committed house precedent in lookup-defaults.ts (.from(table)) and the
//   type-assertion workaround in tenant-editable-defaults.ts.
// ─────────────────────────────────────────────────────────────────────────────
// The high-entropy, single-purpose token. 32 random bytes as 64-char hex —
// the exact shape the invitation flow established and the arch-ref locks for all
// six surfaces. Table-agnostic: the caller writes this onto its own record's
// token column.
export function generateToken(): string {
  return randomBytes(32).toString('hex')
}
// The expiry timestamp, `ttlDays` from now, as an ISO string. TTL is a PARAMETER
// (not the invitation flow's hardcoded 7) because the tokenized surfaces carry
// their own windows — some per-tenant configurable (e.g. the ALA recant window,
// the customer-review window). The caller supplies the window its surface needs;
// the mechanic (now + N days, ISO) is identical and lives here once.
export function tokenExpiresAt(ttlDays: number): string {
  const d = new Date()
  d.setDate(d.getDate() + ttlDays)
  return d.toISOString()
}
// Validate a per-row surface token (Decision 35). Returns the matching row when
// the token exists, is non-null, and is unexpired; otherwise null. Uses the
// service-role admin client — safe from Server Actions and CLI scripts, never
// from browser-side code. `table` and `tokenColumn` are the surface's real
// storage coordinates (e.g. 'claims', 'intake_token'); the expiry column is
// `${tokenColumn}_expires_at` by the pattern's uniform two-column shape.
export async function validateToken<T = Record<string, unknown>>(
  table: string,
  tokenColumn: string,
  token: string
): Promise<T | null> {
  const admin = createAdminClient()
  const expiresColumn = `${tokenColumn}_expires_at`
  const { data, error } = await admin
    .from(table as 'claims')
    .select('*')
    .eq(tokenColumn, token)
    .not(tokenColumn, 'is', null)
    .gt(expiresColumn, new Date().toISOString())
    .maybeSingle()
  if (error || !data) return null
  return data as T
}
// Consume a per-row surface token (Decision 35): null the token column. Callers
// MUST invoke this inside the same atomic write that records the domain result,
// so a spent link cannot be replayed. No consumed_at is written or needed — the
// null token IS the consumption record; the domain state carries the audit time.
export async function consumeToken(
  table: string,
  tokenColumn: string,
  token: string
): Promise<void> {
  const admin = createAdminClient()
  const { error } = await admin
    .from(table as 'claims')
    .update({ [tokenColumn]: null } as never)
    .eq(tokenColumn, token)
  if (error) {
    throw new Error(`Failed to consume token on ${table}.${tokenColumn}: ${error.message}`)
  }
}
