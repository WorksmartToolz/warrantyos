import { randomBytes } from 'node:crypto'

// ─────────────────────────────────────────────────────────────────────────────
// E1 — Stateless Tokenized Interaction: shared token primitives
//
// Source of truth: architecture-reference.md "Stateless Tokenized Interaction
// Pattern" (232-330). The pattern locks THREE primitives for every tokenized
// surface — a high-entropy token, an expiry, and a consumption record — and
// names the team-invitation flow (lib/core/invitations.ts) as "the SHAPE to
// copy, not a shared store." Each of the six surfaces keeps its own token on its
// OWN record (claims.claimant_token, work_authorization_documents.customer_token,
// etc.); this module centralizes only the mechanics that are identical across
// all of them, so they are "decided once and reused" rather than reinvented.
//
// SCOPE — this module is the TWO PURE primitives only:
//   * generateToken()      — the high-entropy token (64-char hex / 32 bytes).
//   * tokenExpiresAt(days)  — the expiry timestamp, TTL supplied by the caller.
// These are table-agnostic: they touch no database and know about no surface.
//
// DELIBERATELY NOT HERE — validate + consume (the third primitive's helper):
//   The invitation precedent's validateInvitationToken / consumeInvitationToken
//   are hardcoded to `.from('invitations')`. A generalized validate/consume must
//   be parameterized by the surface's table AND its token/expiry/consumed COLUMN
//   NAMES, which differ per surface (claimant_token vs customer_token vs
//   customer_review_token). HOW to factor that (a single dynamic-table primitive
//   vs each surface writing its own literal-table check) is an OPEN fork: the
//   arch-ref locks the token SHAPE and "own record" storage but does NOT lock the
//   helper factoring, and neither decisions log, the Phase 0 update, nor the
//   Phase 1 audit resolves it (dig performed Chat 28). Building it now — with no
//   real consumer to fix the column names against — would be guessing a signature
//   we'd rework. It is therefore deferred to the FIRST tokenized consumer built
//   (C3 claim intake, C5 work authorization, or C8 service report), where the
//   real storage coordinates decide the shape. See roadmap E1 sub-task + the E1
//   decision entry for the pinned trigger condition.
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
