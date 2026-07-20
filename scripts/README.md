# scripts/

Internal DevOps scripts for the WarrantyOS repo.

## generate-schema-sql.mjs

Regenerates `supabase/schema.sql` from the canonical migration files in
`supabase/migrations/`.

### When to run

After any migration is added, applied, or modified. `schema.sql` is a
generated artifact (per Phase 2 Decision 10) — it is never hand-edited.
The migrations are the source of truth; `schema.sql` is produced from them.

### Prerequisites

- Supabase CLI installed (`supabase --version`)
- Docker running (the CLI starts a local Postgres in Docker to build the
  schema from migrations)
- Local stack running (`supabase start`) before generation, so
  `--local` has a database to dump from

### How to run

    supabase start            # if the local stack isn't already up
    node scripts/generate-schema-sql.mjs

The script runs `supabase db dump --local`, capturing the schema built by
replaying all migrations against the local database, and writes it to
`supabase/schema.sql`.

### What it does NOT do

- Does not modify any migration file
- Does not touch the hosted/remote database
- Does not require network access (operates against the local stack only)

### Decision context

The generator and the "migrations canonical, schema.sql generated"
convention were established in Phase 2 Decision 10 of the 5e-bridge
session. See docs/session-handoffs/5e-bridge-phase2-decisions-log.md.

## generate-types.mjs

Regenerates `types/database.ts` from the local database schema.

### When to run

After any migration is added, applied, or modified — the same trigger as
`generate-schema-sql.mjs`. The generated `Database` type is derived from
the schema, so it must be regenerated whenever the schema changes.

The file has two parts:

- **Generated body** (the `Database` type): produced by the Supabase CLI,
  overwritten on every run. Never hand-edit it.
- **Hand-authored alias tail** (below the marker line): convenience aliases
  and explicit enum unions. Preserved verbatim across regeneration. This is
  the only part that is hand-maintained.

The boundary between the two is a marker comment:

    // ─── HAND-AUTHORED CONVENIENCE ALIASES (preserved across regeneration) ───

Everything above it is regenerated; everything from the marker down is kept.
If the marker is missing, the script aborts rather than discard the aliases.

### Prerequisites

- Supabase CLI installed (`supabase --version`)
- Docker running
- Local stack running (`supabase start`) before generation, so `--local`
  has a database to read from

### How to run

    supabase start            # if the local stack isn't already up
    node scripts/generate-types.mjs

The script runs `supabase gen types typescript --local`, then appends the
preserved alias tail, and writes the result to `types/database.ts`.

### What it does NOT do

- Does not modify any migration file
- Does not touch the hosted/remote database
- Does not require network access (operates against the local stack only)
- Does not hand-edit the generated body — regeneration is a clean overwrite
  of everything above the marker

### Enum type-safety note

The Supabase generator emits `text` columns (including `text` columns with
`CHECK (col IN (...))` constraints) as `string`, not as literal unions —
it does not read CHECK constraints. Where a column's CHECK-constrained
values need compile-time precision, the alias tail defines an explicit
union (for example `UserRole = 'team_admin' | 'reviewer' | 'viewer'`),
sourced from the column's CHECK definition. Reads of such columns are
narrowed at the consumption site with an assertion (for example
`data.role as UserRole`); the assertion is sound because the database
CHECK guarantees the value is a member of the union.
