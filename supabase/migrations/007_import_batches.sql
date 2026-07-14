-- 007_import_batches.sql
-- Data Migration Tooling batch tracking (Decision 8). Records each CSV/Excel
-- import batch (platform-admin-initiated in MVP) so imported projects and
-- contacts can be traced to the batch that created them.
--
-- Follows the Standard RLS Pattern's six steps: tenant_id FK, RLS enabled,
-- tenant-scoped SELECT policy, service-role-only writes, required grants.
--
-- Schema is exactly per Decision 8's locked shape.

create table public.import_batches (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references public.tenants(id),

  initiated_by    uuid references auth.users(id),
  -- platform admin who initiated the import (MVP). References the Supabase
  -- auth schema, consistent with how the platform identifies acting users.

  source_filename text,
  project_count   integer,
  customer_count  integer,

  status          text not null default 'completed',
  -- 'completed' | 'failed' | 'rolled_back'

  created_at      timestamptz not null default now(),

  constraint import_batches_status_check check (
    status in ('completed', 'failed', 'rolled_back')
  )
);

-- Standard RLS Pattern -------------------------------------------------------

-- Step 2: enable RLS
alter table public.import_batches enable row level security;

-- Step 3: tenant-scoped SELECT policy
create policy "import_batches: members can view their tenant's rows"
  on public.import_batches
  for select
  using (tenant_id = public.get_user_tenant_id());

-- Step 4: writes are service-role only. Import execution runs through a
--         Server Action using the admin client.

-- Step 5: grants (required for PostgREST schema cache visibility)
grant all on public.import_batches to anon, authenticated, service_role;

create index import_batches_tenant_id_idx on public.import_batches (tenant_id);
