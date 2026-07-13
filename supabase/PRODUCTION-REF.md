# Production Database Reference

**This file records which hosted Supabase project is WarrantyOS production.**

- **Project ref:** `uzjivnmwedfzcgqnnhos`
- **Project URL:** `https://uzjivnmwedfzcgqnnhos.supabase.co`
- **Postgres major version:** 17 (must match `config.toml` `major_version`)

## Why this file exists

`supabase/config.toml` only holds `project_id = "warrantyos"`, which is the
local CLI nickname — NOT the hosted database. The `supabase link` step writes
the ref to `supabase/.temp/project-ref`, but `.temp/` is gitignored, so nothing
committed records the production target. Phase 4 (Decision 22) runs
least-reversible operations against this database; pointing a gate at the wrong
one is unrecoverable. This file is the durable, human-readable record of the
correct target.

## Before running any Phase 4 gate

Confirm the CLI is linked to THIS ref:

    supabase link --project-ref uzjivnmwedfzcgqnnhos

Committing this file does not by itself point the CLI at the right database —
the `link` step does. Treat both as required safeguards.
