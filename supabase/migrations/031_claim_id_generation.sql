-- 031_claim_id_generation.sql
--
-- Atomic claim creation with gap-free ClaimID generation. This is the FIRST
-- consumer of the ID Generation system (migration 009 / Decision 2): the claim
-- intake surface is the first place a business identifier is actually minted.
-- WarrantyID's first consumer (the warranty_id_early_issuance clock event,
-- Decision 27.2) is not built yet, so no generator existed on disk before this.
--
-- Locked sources (all read from disk this session, not memory):
--   * Decision 2 (Phase 2 decisions log) + architecture-reference.md
--     "ID Generation" section -- THE mechanism: one row per (tenant, id_type),
--     locked and incremented IN THE SAME TRANSACTION as the consuming insert,
--     rollback rolls the counter back, no gaps.
--   * arch-ref 1136-1154 "Generation is transactional and gap-free" +
--     "Year-rollover is UTC and atomic with the increment": the increment is a
--     SINGLE UPDATE with CASE on current_year vs EXTRACT(YEAR FROM NOW() AT
--     TIME ZONE 'UTC') -- no separate "is it a new year?" read that could
--     interleave.
--   * Decision 27.2/27.3 (Phase 3 decisions log, 4830-4849): the sibling
--     generator's home is locked as "the Server Action issues <id>
--     synchronously in the same transaction" using the "same generation
--     mechanism". A DB function invoked by the Server Action IS that same
--     transaction -- the action is the caller, the function is how atomicity
--     is achieved (the provision-tenant Server Action already calls a DB
--     function this way via admin.rpc('federal_holidays_for_year')).
--   * migration 009 header: "a Server Action ... locks the relevant row in the
--     SAME transaction, increments current_value, formats via format_string,
--     and writes the id onto the inserting record."
--
-- WHY A DB FUNCTION, NOT TWO SUPABASE-JS CALLS: the locked guarantee is that
-- the counter advance and the claim insert share ONE transaction so a
-- rolled-back insert rolls back the counter. The Supabase JS client cannot wrap
-- two .from() round-trips in a single transaction; a counter increment that
-- committed before a failing insert would leak exactly the gap the whole system
-- exists to prevent (arch-ref 1126-1128 rejects PG SEQUENCE objects for this
-- very reason). One function body = one transaction = the locked guarantee.
--
-- WHY VALIDATION STAYS IN TS (lib/core/claims.ts), NOT HERE: the two-layer
-- pattern is intact. createClaimIntake keeps every business check (enum
-- validation, rich-text caps read from tenants.settings, conditional field
-- couplings, eligibility, cross-tenant guard, submitter FK). This function is a
-- pure atomic-WRITE primitive: it receives already-validated typed column
-- values and does only lock -> rollover -> increment -> format -> insert ->
-- return. The DB CHECK constraints (claim_type / equipment_status /
-- loto_requirement) remain the in-transaction backstop.
--
-- FORMAT EXPANSION SCOPE (the one implementation seam the lock leaves open):
-- arch-ref 1096-1111 locks Python format-string SYNTAX ({year}, {seq:NNd}) and
-- says richer specifiers "work" and are "validated at settings-save time, not at
-- generation time." The shipped Phase 1 default (CLM-{year}-{seq:07d}) uses only
-- {year} and {seq:07d}. This function expands exactly those two placeholders,
-- which reproduces every shipped default faithfully. Full Python-spec expansion
-- (fill chars, alignment) is only reachable once a settings UI lets a tenant
-- save an exotic format -- that UI does not exist in v1, and the arch ref places
-- format validation there. Expanding the two locked placeholders now is faithful
-- to the shipped formats and forecloses nothing: a later richer expander is a
-- settings-era change, not a rework of this atomic primitive.
--
-- SECURITY: security definer + set search_path = public, matching the 002/011
-- hardening precedent for functions that must run with elevated rights. Callable
-- by the service_role admin client only (the C3 core uses createAdminClient).
-- Not immutable/stable -- it writes.

create or replace function public.create_claim_with_generated_id(
  p_tenant_id                     uuid,
  p_warranty_registration_id      uuid,
  p_claim_type                    text,
  p_date_of_defect_incident       date,
  p_equipment_status              text,
  p_loto_requirement              text,
  p_detailed_description          jsonb,
  p_submitter_name                text,
  p_submitter_email               text,
  p_is_emergency                  boolean,
  p_emergency_details             jsonb,
  p_emergency_stabilized_at       timestamptz,
  p_offline_condition_explanation jsonb,
  p_supporting_documents          jsonb,
  p_required_docs_provided        boolean,
  p_submitter_contact_id          uuid,
  p_om_provider_company           text,
  p_om_contact_name               text,
  p_om_contact_phone              text,
  p_om_contact_email              text,
  p_ship_to_street                text,
  p_ship_to_city                  text,
  p_ship_to_state                 text,
  p_ship_to_zip                   text,
  p_recipient_name                text,
  p_recipient_phone               text,
  p_claim_type_data               jsonb
)
returns table (id uuid, claim_id text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_year integer := extract(year from now() at time zone 'utc')::int;
  v_seq  integer;
  v_fmt  text;
  v_claim_id text;
begin
  -- Locked single-statement increment + UTC year-rollover (arch-ref 1146-1154).
  -- The UPDATE takes the row lock; if current_year is stale the counter resets
  -- to 1 for the new year, else it increments. RETURNING gives the value used.
  -- The format_string is read from the same row in the same statement.
  update public.tenant_id_sequences
     set current_value = case
                           when current_year = v_year then current_value + 1
                           else 1
                         end,
         current_year  = v_year,
         updated_at    = now()
   where tenant_id = p_tenant_id
     and id_type   = 'claim_id'
  returning current_value, format_string into v_seq, v_fmt;

  if v_seq is null then
    -- No sequence row: provisioning did not seed it (009's no-lazy-create rule).
    raise exception 'claim_id sequence row missing for tenant %', p_tenant_id
      using errcode = 'foreign_key_violation';
  end if;

  -- Expand the two locked placeholders. {year} -> v_year; {seq:0Nd} -> the
  -- counter, zero-padded to width N. The default format uses width 7; the regex
  -- honors whatever width the tenant's format_string carries so a configured
  -- CLM-{year}-{seq:05d} still expands correctly without a code change here.
  v_fmt := replace(v_fmt, '{year}', v_year::text);
  v_claim_id := regexp_replace(
    v_fmt,
    '\{seq:0(\d+)d\}',
    lpad(v_seq::text, (regexp_match(v_fmt, '\{seq:0(\d+)d\}'))[1]::int, '0'),
    'g'
  );

  -- Atomic insert in the same transaction. status defaults 'intake_received'
  -- (016); id defaults gen_random_uuid(); intake_token stays null (issuance
  -- subsystem mints it). A CHECK violation here rolls the whole function back,
  -- including the counter increment above -> gap-free.
  return query
  insert into public.claims (
    tenant_id, warranty_registration_id, claim_id, claim_type,
    date_of_defect_incident, equipment_status, loto_requirement,
    detailed_description, submitter_name, submitter_email, submitter_contact_id,
    is_emergency, emergency_details, emergency_stabilized_at,
    offline_condition_explanation, supporting_documents, required_docs_provided,
    om_provider_company, om_contact_name, om_contact_phone, om_contact_email,
    ship_to_street, ship_to_city, ship_to_state, ship_to_zip,
    recipient_name, recipient_phone, claim_type_data
  ) values (
    p_tenant_id, p_warranty_registration_id, v_claim_id, p_claim_type,
    p_date_of_defect_incident, p_equipment_status, p_loto_requirement,
    p_detailed_description, p_submitter_name, p_submitter_email, p_submitter_contact_id,
    coalesce(p_is_emergency, false), p_emergency_details, p_emergency_stabilized_at,
    p_offline_condition_explanation, p_supporting_documents, coalesce(p_required_docs_provided, false),
    p_om_provider_company, p_om_contact_name, p_om_contact_phone, p_om_contact_email,
    p_ship_to_street, p_ship_to_city, p_ship_to_state, p_ship_to_zip,
    p_recipient_name, p_recipient_phone, p_claim_type_data
  )
  returning public.claims.id, public.claims.claim_id;
end;
$$;

comment on function public.create_claim_with_generated_id is
  'Atomic claim creation with gap-free ClaimID generation (Decision 2; arch-ref '
  'ID Generation section). Locks and increments the (tenant, claim_id) '
  'tenant_id_sequences row, expands the format_string, and inserts the claim in '
  'ONE transaction so a rolled-back insert rolls back the counter -- no gaps. '
  'The FIRST consumer of the ID Generation system. Business validation lives in '
  'lib/core/claims.ts (createClaimIntake); this function is a pure atomic-write '
  'primitive receiving already-validated typed values. Service-role only.';

grant execute on function public.create_claim_with_generated_id to service_role;
