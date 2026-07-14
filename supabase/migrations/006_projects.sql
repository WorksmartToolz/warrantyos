-- 006_projects.sql
-- Project: the sacred root entity of the WarrantyOS data model. Every warranty
-- registration belongs to exactly one project. Locked across Decisions 5, 23,
-- and Phase 0 Item 17 (multi-source trigger model).
--
-- Follows the Standard RLS Pattern's six steps: tenant_id FK, RLS enabled,
-- tenant-scoped SELECT policy, service-role-only writes, required grants.
-- There is NO project-level user-facing UPDATE policy; project mutations all
-- go through Server Actions (per the Project section).
--
-- No business-visible identifier in Phase 1 (no PRJ- prefix); the uuid PK is
-- sufficient. Projects are internal; customers see warranties and claims.
--
-- DEFERRED FK (blocked on design, NOT deferred by choice):
--   imported_via_batch_id references import_batches(id). Same import_batches
--   design gap as contacts (005). Column present now; FK constraint added once
--   import_batches is designed and built.
--
-- REAL FK closed this session: customer_id -> contacts(id), built in 005.

create table public.projects (
  id                       uuid primary key default gen_random_uuid(),
  tenant_id                uuid not null references public.tenants(id),

  name                     text not null,

  trigger_source           text not null,
  -- 'contractual_date_manual' | 'wbs_integration'
  --   | 'delivery_report_tokenized' | 'delivery_report_api'

  trigger_status           text not null default 'pending',
  -- 'pending' | 'confirmed' | 'overdue'

  trigger_date             date,
  -- Semantics vary by trigger_source (per Decision 23.1):
  --   contractual_date_manual: set at project creation (contractually-agreed
  --     warranty active date); non-null at creation via Server Action
  --     enforcement (exception via migration path per Decision 23.11).
  --   wbs_integration / delivery_report_tokenized / delivery_report_api:
  --     populated when trigger_status becomes 'confirmed'. Null until then.

  integration_config       jsonb,
  -- WBS / API integration identity and project reference; null for
  -- non-integrated trigger sources.

  customer_id              uuid references public.contacts(id),
  -- Single-FK to the contacts directory (per Unified Contacts Directory).
  customer_name_snapshot   text,
  customer_email_snapshot  text,
  customer_phone_snapshot  text,

  site_address_street      text,
  site_address_city        text,
  site_address_state       text,
  site_address_zip         text,

  imported_via_batch_id    uuid,
  -- FK to import_batches DEFERRED (see header).

  deleted_at               timestamptz,
  -- soft-delete discriminator; non-null means the project is retired.

  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),

  constraint projects_trigger_source_check check (
    trigger_source in (
      'contractual_date_manual',
      'wbs_integration',
      'delivery_report_tokenized',
      'delivery_report_api'
    )
  ),
  constraint projects_trigger_status_check check (
    trigger_status in (
      'pending',
      'confirmed',
      'overdue'
    )
  )
);

-- Standard RLS Pattern -------------------------------------------------------

-- Step 2: enable RLS
alter table public.projects enable row level security;

-- Step 3: tenant-scoped SELECT policy
create policy "projects: members can view their tenant's rows"
  on public.projects
  for select
  using (tenant_id = public.get_user_tenant_id());

-- Step 4: writes are service-role only. No user-facing INSERT/UPDATE/DELETE
--         policies; all project mutations go through Server Actions.

-- Step 5: grants (required for PostgREST schema cache visibility)
grant all on public.projects to anon, authenticated, service_role;

create index projects_tenant_id_idx on public.projects (tenant_id);
create index projects_customer_id_idx on public.projects (customer_id);
