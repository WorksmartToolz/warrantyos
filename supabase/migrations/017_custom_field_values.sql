-- Migration 017: custom_field_values
--
-- Source of truth: Decision 3 (Custom Fields Phase 1 Entity Scope) in the
--                  **PHASE 2** decisions log
--                  (docs/session-handoffs/5e-bridge-phase2-decisions-log.md),
--                  plus architecture-reference.md "Custom Field System".
--                  NOTE: Decision 3 is NOT in the Phase 3 log. Grepping only
--                  the Phase 3 log returns nothing and looks like a gap. It
--                  isn't. Both logs are live.
--
-- Companion to custom_field_definitions (migration 015). This table holds one
-- filled-in value for one entity instance, linked to its definition. It was
-- blocked until now: it carries a claim_id FK and claims did not exist until
-- migration 016. All three FK targets now exist, so the exactly-one-non-null
-- CHECK can be built with real referential integrity and zero deferred FKs.
--
-- ON DELETE clauses -- both follow from locked text, neither is improvised:
--
--   * Three entity FKs (project_id, warranty_registration_id, claim_id) ->
--     ON DELETE CASCADE. Decision 3's rationale for choosing typed FK columns
--     over a polymorphic key states it explicitly: the approach "lets ON DELETE
--     CASCADE work per entity" (echoed verbatim in the arch ref's "Typed FK
--     columns, not a polymorphic key" subsection). A custom field value is a
--     dependent attribute of its entity, not an independent record -- it has no
--     meaning once the entity is gone. This does NOT conflict with the RESTRICT
--     clauses on claims (016) and warranty_registrations (010): those protect
--     parent rows that carry independent meaning.
--
--   * definition_id -> ON DELETE RESTRICT. Decision 3 and the arch ref both
--     lock the soft-delete semantics: definitions soft-delete via deleted_at,
--     their existing values "remain queryable for historical display and
--     reporting," and hard-delete "would orphan historical values or
--     cascade-destroy auditable data; it is available only through admin
--     tooling if ever genuinely needed, never through the Phase 1 UI."
--     CASCADE here would be precisely the cascade-destruction of auditable data
--     the architecture names as the thing to avoid. RESTRICT makes the admin
--     tooling path deliberate rather than silently destructive, per the
--     Defensibility Principle.
--
-- Denormalized tenant_id: Decision 3 and the arch ref's "Denormalized tenant_id"
-- subsection. custom_field_values is the NAMED PRECEDENT for the tenant_id
-- denormalization convention in the Standard RLS Pattern section -- it carries
-- its own tenant_id rather than joining through custom_field_definitions on
-- every read.
--
-- NOT NULL on tenant_id per the Standard RLS Pattern's six-step checklist,
-- step 1: "a tenant_id uuid not null references public.tenants(id) column. No
-- tenant-scoped row exists without an owning tenant." The checklist is explicit
-- that "omitting any one of them is a defect." Decision 3's sketch writes
-- `tenant_id uuid FK -> tenants` without the NOT NULL; that is sketch shorthand,
-- not intent -- the pattern already governs it, and all 11 prior tables comply.
--
-- APP-LAYER INVARIANTS (not DB constraints, per the architecture):
--   * tenant_id must match the parent definition's tenant_id. Decision 3:
--     "the stay-in-sync invariant ... must be enforced application-layer at
--     insert time." The redundant column is the acknowledged cost of the
--     simpler RLS policy.
--   * value is type-safe per definition.field_type -- validated at write time
--     against the definition's declared type, not by the database.
--   * Soft-deleted definitions (deleted_at IS NOT NULL) keep their values
--     queryable; the definition-list UI filters them out and new entity edit
--     forms stop rendering their inputs. Values do not migrate or detach --
--     they stay attached to the now-hidden definition.
--
-- rich_text values are stored as ProseMirror-compatible JSON (Decision 4),
-- inside the value jsonb column. The format is deliberately named for the data,
-- not the library, so it outlives TipTap.

create table if not exists public.custom_field_values (
  id                        uuid primary key default gen_random_uuid(),
  tenant_id                 uuid not null references public.tenants(id),
  definition_id             uuid not null
                              references public.custom_field_definitions(id)
                              on delete restrict,
  project_id                uuid
                              references public.projects(id)
                              on delete cascade,
  warranty_registration_id  uuid
                              references public.warranty_registrations(id)
                              on delete cascade,
  claim_id                  uuid
                              references public.claims(id)
                              on delete cascade,
  value                     jsonb,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),

  -- Exactly one of the three entity FKs is non-null (Decision 3).
  constraint custom_field_values_one_entity_check
    check (
      (
        (project_id is not null)::int
        + (warranty_registration_id is not null)::int
        + (claim_id is not null)::int
      ) = 1
    )
);

-- Standard RLS Pattern: tenant index
create index if not exists custom_field_values_tenant_id_idx
  on public.custom_field_values (tenant_id);

-- Parent lookup: values for a definition.
create index if not exists custom_field_values_definition_id_idx
  on public.custom_field_values (definition_id);

-- Entity lookups: "all custom values for this entity" is the primary read.
-- Partial indexes -- each row populates exactly one of the three columns, so
-- unqualified indexes would be two-thirds NULL.
create index if not exists custom_field_values_project_id_idx
  on public.custom_field_values (project_id)
  where project_id is not null;

create index if not exists custom_field_values_warranty_registration_id_idx
  on public.custom_field_values (warranty_registration_id)
  where warranty_registration_id is not null;

create index if not exists custom_field_values_claim_id_idx
  on public.custom_field_values (claim_id)
  where claim_id is not null;

-- Standard RLS Pattern: enable RLS
alter table public.custom_field_values enable row level security;

-- Standard RLS Pattern: tenant-scoped SELECT for members.
-- Writes are service-role only (no INSERT/UPDATE/DELETE policies).
create policy "custom_field_values: members can view their tenant's rows"
  on public.custom_field_values
  for select
  using (tenant_id = public.get_user_tenant_id());

-- Standard RLS Pattern: grants
grant all on table public.custom_field_values to anon;
grant all on table public.custom_field_values to authenticated;
grant all on table public.custom_field_values to service_role;

comment on table public.custom_field_values is
  'One filled-in custom field value for one entity instance (Decision 3, '
  'Phase 2 decisions log). Companion to custom_field_definitions (015). '
  'Typed nullable FKs to the three Phase 1 entities with an '
  'exactly-one-non-null CHECK — not a polymorphic key — so referential '
  'integrity is real and ON DELETE CASCADE works per entity.';

comment on column public.custom_field_values.tenant_id is
  'Denormalized per the Standard RLS Pattern''s tenant_id convention; '
  'custom_field_values is the named precedent for that convention. Avoids a '
  'JOIN through custom_field_definitions on every read. Must match the parent '
  'definition''s tenant_id — a stay-in-sync invariant enforced app-layer at '
  'insert time, not by the database.';

comment on column public.custom_field_values.definition_id is
  'ON DELETE RESTRICT, not CASCADE. Definitions soft-delete via deleted_at and '
  'their values remain queryable for historical display and reporting '
  '(Decision 3). Hard-delete is admin-tooling only, never exposed in the '
  'Phase 1 UI; CASCADE would cascade-destroy auditable data, which the '
  'architecture names as the outcome to avoid.';

comment on column public.custom_field_values.value is
  'Type-safe per the parent definition''s field_type, validated app-layer at '
  'write time. rich_text values are ProseMirror-compatible JSON (Decision 4) — '
  'a format named for the data, not the editor library, so it outlives TipTap.';
