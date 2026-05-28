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
