


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE EXTENSION IF NOT EXISTS "pg_net" WITH SCHEMA "extensions";






COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE OR REPLACE FUNCTION "public"."federal_holidays_for_year"("p_year" integer) RETURNS TABLE("holiday_date" "date", "label" "text")
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO 'public'
    AS $$
declare
  v_date  date;
  v_label text;
begin
  if p_year is null or p_year < 1900 or p_year > 9999 then
    raise exception 'federal_holidays_for_year: year out of range: %', p_year;
  end if;

  -- Fixed-date holidays, observed-shift rule applied.
  -- Saturday (dow 6) -> preceding Friday; Sunday (dow 0) -> following Monday.
  -- Five of the eleven are fixed-date: these four plus Veterans Day (below).
  for v_date, v_label in
    select d, l from (values
      (make_date(p_year,  1,  1), 'New Year''s Day'),
      (make_date(p_year,  6, 19), 'Juneteenth National Independence Day'),
      (make_date(p_year,  7,  4), 'Independence Day'),
      (make_date(p_year, 12, 25), 'Christmas Day')
    ) as t(d, l)
  loop
    holiday_date := case extract(dow from v_date)
                      when 6 then v_date - 1   -- Saturday -> Friday
                      when 0 then v_date + 1   -- Sunday   -> Monday
                      else v_date
                    end;
    label := v_label;
    return next;
  end loop;

  -- Nth-weekday holidays. These always fall on a Monday or Thursday by
  -- construction, so the observed-shift rule never applies to them.
  --   third Monday of January
  holiday_date := public.nth_weekday_of_month(p_year, 1, 1, 3);
  label := 'Birthday of Martin Luther King, Jr.';
  return next;

  --   third Monday of February
  holiday_date := public.nth_weekday_of_month(p_year, 2, 1, 3);
  label := 'Washington''s Birthday';
  return next;

  --   LAST Monday of May
  holiday_date := public.last_weekday_of_month(p_year, 5, 1);
  label := 'Memorial Day';
  return next;

  --   first Monday of September
  holiday_date := public.nth_weekday_of_month(p_year, 9, 1, 1);
  label := 'Labor Day';
  return next;

  --   second Monday of October
  holiday_date := public.nth_weekday_of_month(p_year, 10, 1, 2);
  label := 'Columbus Day';
  return next;

  --   fourth Thursday of November
  holiday_date := public.nth_weekday_of_month(p_year, 11, 4, 4);
  label := 'Thanksgiving Day';
  return next;

  -- Veterans Day, November 11 -- fixed-date, so the shift rule applies. Grouped
  -- here rather than in the loop above only because it was added to the federal
  -- list separately; the treatment is identical.
  v_date := make_date(p_year, 11, 11);
  holiday_date := case extract(dow from v_date)
                    when 6 then v_date - 1
                    when 0 then v_date + 1
                    else v_date
                  end;
  label := 'Veterans Day';
  return next;

  return;
end;
$$;


ALTER FUNCTION "public"."federal_holidays_for_year"("p_year" integer) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."federal_holidays_for_year"("p_year" integer) IS 'Returns the eleven U.S. federal holidays for any year, with the federal observed-shift rule (Saturday -> preceding Friday, Sunday -> following Monday) applied to the five fixed-date holidays. Pure computation, reads no tables, IMMUTABLE. Encoding the rule once rather than enumerating literal dates removes the silent-expiry cliff a bounded date list would carry -- business-day math would otherwise stop skipping holidays past the cliff with no error and no alert. Called by this migration''s backfill, by app-layer new-tenant provisioning (Decision 25.3''s "at provisioning"), and by the rolling annual top-up once pg_cron lands. The result is a STARTING DEFAULT that tenants edit -- it is not a claim about what any warrantor observes.';



CREATE OR REPLACE FUNCTION "public"."get_user_tenant_id"() RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select tenant_id
  from public.users
  where id = auth.uid()
    and status = 'active'
    and removed_at is null
$$;


ALTER FUNCTION "public"."get_user_tenant_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."last_weekday_of_month"("p_year" integer, "p_month" integer, "p_dow" integer) RETURNS "date"
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO 'public'
    AS $$
declare
  v_last date := (make_date(p_year, p_month, 1) + interval '1 month - 1 day')::date;
  v_back integer;
begin
  -- days back from the last day of the month to the preceding p_dow
  v_back := (extract(dow from v_last)::integer - p_dow + 7) % 7;
  return v_last - v_back;
end;
$$;


ALTER FUNCTION "public"."last_weekday_of_month"("p_year" integer, "p_month" integer, "p_dow" integer) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."last_weekday_of_month"("p_year" integer, "p_month" integer, "p_dow" integer) IS 'Helper for federal_holidays_for_year(): the last occurrence of a given weekday in a given month. Memorial Day is the LAST Monday of May, which the Nth-weekday helper cannot express. dow follows extract(dow from date). Pure computation, IMMUTABLE.';



CREATE OR REPLACE FUNCTION "public"."nth_weekday_of_month"("p_year" integer, "p_month" integer, "p_dow" integer, "p_n" integer) RETURNS "date"
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO 'public'
    AS $$
declare
  v_first date := make_date(p_year, p_month, 1);
  v_offset integer;
begin
  -- days from the 1st to the first occurrence of p_dow
  v_offset := (p_dow - extract(dow from v_first)::integer + 7) % 7;
  return v_first + v_offset + (p_n - 1) * 7;
end;
$$;


ALTER FUNCTION "public"."nth_weekday_of_month"("p_year" integer, "p_month" integer, "p_dow" integer, "p_n" integer) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."nth_weekday_of_month"("p_year" integer, "p_month" integer, "p_dow" integer, "p_n" integer) IS 'Helper for federal_holidays_for_year(): the Nth occurrence of a given weekday in a given month. dow follows extract(dow from date): 0 = Sunday .. 6 = Saturday. Pure computation, IMMUTABLE.';



CREATE OR REPLACE FUNCTION "public"."protect_system_warranty_types"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
begin
  if tg_op = 'DELETE' then
    if old.is_system then
      raise exception 'Cannot delete a system warranty type (is_system = true).';
    end if;
    return old;
  elsif tg_op = 'UPDATE' then
    if old.is_system and not new.is_system then
      raise exception 'Cannot clear is_system on a system warranty type.';
    end if;
    return new;
  end if;
  return null;
end;
$$;


ALTER FUNCTION "public"."protect_system_warranty_types"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "public"."set_updated_at"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."acknowledgment_gate_records" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "template_id" "uuid" NOT NULL,
    "template_content_snapshot" "jsonb" NOT NULL,
    "acknowledger_name" "text",
    "acknowledged_at" timestamp with time zone NOT NULL,
    "acknowledger_ip" "text",
    "authorized_entity_type" "text" NOT NULL,
    "authorized_entity_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "acknowledgment_gate_records_authorized_entity_type_check" CHECK (("authorized_entity_type" = ANY (ARRAY['claim'::"text", 'work_authorization_document'::"text"])))
);


ALTER TABLE "public"."acknowledgment_gate_records" OWNER TO "postgres";


COMMENT ON TABLE "public"."acknowledgment_gate_records" IS 'Per-acknowledgment-event instantiations (Decision 12): for one specific protected entity, the customer''s acknowledgment with the template content frozen at the moment they agreed, the acknowledger''s identity capture, the timestamp, the IP for audit trail, and a polymorphic reference to the protected entity the acknowledgment authorizes. One gate per protected entity in Phase 1 (12.4): once this row exists, the gate is not shown again for that entity on subsequent link clicks. That "at most one" is enforced by the Server Action''s existence check (12.7 step 3), not by a DB unique. Multi-gate-per-entity is deferred as speculative -- a tenant needing several acknowledgments composes them into one longer template''s content.';



COMMENT ON COLUMN "public"."acknowledgment_gate_records"."template_content_snapshot" IS 'The frozen content the customer actually agreed to, captured at acknowledgment rather than referenced live through template_id. Same defensibility logic as ALA''s content_snapshot and the FK + Snapshot Pattern: a later template revision must not retroactively alter what the customer agreed to. The template_id FK preserves the relationship for reporting; this column preserves the historical truth.';



COMMENT ON COLUMN "public"."acknowledgment_gate_records"."authorized_entity_id" IS 'Polymorphic reference to the protected entity: claims.id when authorized_entity_type = ''claim'', work_authorization_documents.id when ''work_authorization_document''. NO database FK -- Decision 12 locks the two-column (authorized_entity_type + authorized_entity_id) shape by name, and typed per-entity FK columns would delete both locked columns. Same reasoning and same answer as Decision 11.b on 022''s event_reference_id, the structurally identical question; precedent also clock_events.entity_id (013). Deliberately NOT NULL where 022''s event_reference_id is nullable: both are built verbatim to their own locked sketches, and an acknowledgment is by definition an acknowledgment OF something. Do not harmonize. Dispatch and referential integrity are app-layer; the application must check for acknowledgment records before allowing a protected entity to be deleted.';



CREATE TABLE IF NOT EXISTS "public"."acknowledgment_gate_templates" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "gate_purpose" "text" NOT NULL,
    "name" "text" NOT NULL,
    "content" "jsonb" NOT NULL,
    "acknowledgment_label" "text" NOT NULL,
    "requires_typed_name" boolean DEFAULT false NOT NULL,
    "is_default" boolean DEFAULT false NOT NULL,
    "deleted_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "acknowledgment_gate_templates_gate_purpose_check" CHECK (("gate_purpose" = ANY (ARRAY['claim_submission'::"text", 'work_authorization'::"text"])))
);


ALTER TABLE "public"."acknowledgment_gate_templates" OWNER TO "postgres";


COMMENT ON TABLE "public"."acknowledgment_gate_templates" IS 'Tenant-defined gate definitions (Decision 12): which interaction purpose the gate guards, the gate''s content, the acknowledgment text beside the checkbox, whether a typed name is required, and which template is the tenant''s default for the purpose. Same templates-and-records shape as the ALA System and Customer Work Authorization (022). Gates are OPTIONAL per tenant per purpose (12.3): a tenant whose external compliance processes already handle the equivalent acknowledgment leaves the purpose unconfigured, and their customers proceed directly to the interaction form. Zero rows is a valid steady state -- which is why this migration deliberately seeds nothing.';



COMMENT ON COLUMN "public"."acknowledgment_gate_templates"."gate_purpose" IS 'Which tokenized customer interaction this gate guards. Phase 1 values: claim_submission (guards a Claim Intake tokenized intake form), work_authorization (guards a Customer Work Authorization tokenized acceptance form, 022). Extensible the same way Decision 9''s clock_events.event_type is: a future tokenized interaction that benefits from a pre-form gate adds a value and updates this CHECK via migration, without restructuring the tables. Other candidates named but NOT locked by Decision 12: registration assignee submission, supply-only delivery reporting, service report customer review -- each a per-interaction decision when those sections are drafted.';



COMMENT ON COLUMN "public"."acknowledgment_gate_templates"."is_default" IS 'At most one is_default = true per (tenant_id, gate_purpose) is the architectural intent. Enforcement is app-layer: the arch ref offers partial-UNIQUE or app-layer and picks neither, and Decision 17.A.6 caps v1 DB enforcement. Parallel to Work Authorization''s (022) and ALA''s is_default flags -- three parallel flags, one answer.';



COMMENT ON COLUMN "public"."acknowledgment_gate_templates"."deleted_at" IS 'Soft-delete is required, not optional. Records captured against a retired template must remain readable: the frozen template_content_snapshot preserves what the customer actually agreed to, but the template_id FK must remain valid for reporting and historical query. Hard-deleting a template would break that relationship -- hence RESTRICT on records.template_id.';



CREATE TABLE IF NOT EXISTS "public"."ala_document_revisions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "ala_document_id" "uuid" NOT NULL,
    "revised_by_user_id" "uuid" NOT NULL,
    "revision_reason" "jsonb" NOT NULL,
    "field_changes" "jsonb" NOT NULL,
    "revised_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."ala_document_revisions" OWNER TO "postgres";


COMMENT ON TABLE "public"."ala_document_revisions" IS 'Full history of warrantor content changes to one ALA document (Decision 26), resolving the revise-and-resend question Decision 19 deferred: operational pressure surfaced a need to update an ALA''s content (new findings, revised scope) without creating a second ala_documents row, which UNIQUE(claim_id) forbids and continues to forbid (26.2). Distinct from Decision 25''s re-issue: re-issue resends the SAME content after non-response; revise-and-resend changes the content because circumstances changed. The revise action (26.3) updates the row in place, logs prior state here, clears overdue_flagged_at, regenerates the token, and resends. Revising a SIGNED ALA is blocked at v1 (26.4) -- the gate is already cleared on the strength of that signature, and revising accepted terms is a materially different problem; mirrors the O&M provider blocking convention (20.6/20.7). Structurally identical to work_authorization_revisions (022) and built verbatim to the locked 26.1 sketch: revised_at only, no created_at/updated_at, no soft-delete.';



CREATE TABLE IF NOT EXISTS "public"."ala_documents" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "claim_id" "uuid" NOT NULL,
    "template_id" "uuid" NOT NULL,
    "content_snapshot" "jsonb" NOT NULL,
    "markup_percent_snapshot" numeric(4,3) NOT NULL,
    "signer_name" "text",
    "signer_email" "text",
    "signed_at" timestamp with time zone,
    "claimant_decision" "text",
    "decided_at" timestamp with time zone,
    "decline_reason" "text",
    "signature_method" "text" DEFAULT 'in_platform_widget'::"text" NOT NULL,
    "signature_image_url" "text",
    "esignature_envelope_id" "text",
    "overdue_flagged_at" timestamp with time zone,
    "claimant_token" "text",
    "claimant_token_expires_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "ala_documents_claimant_decision_check" CHECK (("claimant_decision" = ANY (ARRAY['accepted'::"text", 'declined'::"text"]))),
    CONSTRAINT "ala_documents_signature_method_check" CHECK (("signature_method" = ANY (ARRAY['in_platform_widget'::"text", 'esignature_service'::"text"])))
);


ALTER TABLE "public"."ala_documents" OWNER TO "postgres";


COMMENT ON TABLE "public"."ala_documents" IS 'One claimant''s Owner''s Consent and Assumption of Liability Agreement for one Indistinct claim (Decision 19). Exists ONLY when a claim''s outcome is Indistinct -- most claims never have one. UNIQUE on claim_id enforces 1:1 and Decision 26.2 explicitly refuses to reopen it: a claim either is Indistinct and has exactly one ALA, or is not Indistinct and has none. The deliberate contrast against work_authorization_documents (022), which is one-to-many because it authorizes a bounded, recurring on-site event; an ALA authorizes financial liability for the claim''s investigation, once. Content changes go through revise-and-resend (026), never a second row.';



COMMENT ON COLUMN "public"."ala_documents"."markup_percent_snapshot" IS 'Decision 7: the tenant''s ala_markup_percent (default 0.10, stored at tenants.settings.ala_markup_percent) frozen at document generation. A tenant who changes their markup later does not retroactively change documents already generated. The 0 to 0.50 validation bounds are app-layer: the numeric(4,3) type constrains precision, not the architectural bounds. v1''s 15% figure was checked against all six claim intake workbooks during drafting and confirmed unsourced; Decision 7''s 10% stands.';



COMMENT ON COLUMN "public"."ala_documents"."claimant_decision" IS 'Half of the DERIVED three-state machine (Decision 19.7). There is deliberately NO status column: unsigned = claimant_decision IS NULL AND signed_at IS NULL; signed = ''accepted'' AND signed_at IS NOT NULL; declined = ''declined'' AND signed_at IS NULL. These three are the complete state set. The app-layer invariant that ''accepted'' implies signed_at non-null follows from Decision 19.1''s atomic accept-and-signature write; it is enforced in the Server Action, not by a DB CHECK (17.A.6).';



COMMENT ON COLUMN "public"."ala_documents"."signature_method" IS 'Decision 19.3. Platform-locked CHECK enum WITH a default, captured at row creation from the tenant''s ala_signature_method setting and frozen for the document''s lifetime. in_platform_widget is the accessibility-compliant default path; esignature_service routes to an external provider. The mechanism-specific artifact lands in signature_image_url or esignature_envelope_id respectively -- both conditional, both app-layer.';



COMMENT ON COLUMN "public"."ala_documents"."overdue_flagged_at" IS 'Decision 25.4: a FOURTH ORTHOGONAL SIGNAL layered on top of the unsigned state -- NOT a fourth state. Set by the clock dispatcher when ala_response_overdue fires with claimant_decision still null (25.5); the claimant is emailed that the window closed with no decision made, and no decision is recorded. Silence never becomes a decision (25.8): there is no auto-terminal state. It persists until the warrantor re-issues (25.7) or escalates manually. Does not unblock the Indistinct gate.';



COMMENT ON COLUMN "public"."ala_documents"."claimant_token" IS 'Stateless Tokenized Interaction Pattern (Decision 19.8), stored on this row per the pattern''s "shape to copy, not shared store" rule -- parallel to work_authorization_documents.customer_token (022). Per-row token regeneration handles expiry recovery: the warrantor updates both token columns on the existing row, and the document''s state combination (claimant_decision, signed_at) is preserved across regeneration.';



CREATE TABLE IF NOT EXISTS "public"."ala_templates" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "content" "jsonb" NOT NULL,
    "is_default" boolean DEFAULT false NOT NULL,
    "deleted_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."ala_templates" OWNER TO "postgres";


COMMENT ON TABLE "public"."ala_templates" IS 'Tenant-defined reusable configuration for the Owner''s Consent and Assumption of Liability Agreement (Decision 19). A tenant has one or more templates; Phase 1 likely has one default per tenant, with multiple templates supporting warrantors who use different agreement variants for different claim types or jurisdictions. Same templates-and-documents shape as Customer Work Authorization (022) and the Acknowledgment Gate Pattern (023). The platform stores template content and any tenant-supplied document-number identifier, but does not reserve or assign document numbers itself -- numbering is data, not architecture. This section does NOT specify the legal form of the agreement: that content is warrantor-specific.';



COMMENT ON COLUMN "public"."ala_templates"."is_default" IS 'At most one is_default = true per tenant is the architectural intent. Enforcement is app-layer: the arch ref offers partial-UNIQUE or app-layer and picks neither, and Decision 17.A.6 caps v1 DB enforcement. The third parallel flag, after work_authorization_templates (022) and acknowledgment_gate_templates (023) -- identical question, identical answer.';



CREATE TABLE IF NOT EXISTS "public"."claims" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "warranty_registration_id" "uuid" NOT NULL,
    "claim_id" "text" NOT NULL,
    "status" "text" DEFAULT 'intake_received'::"text" NOT NULL,
    "is_emergency" boolean DEFAULT false NOT NULL,
    "emergency_stabilized_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "claims_status_check" CHECK (("status" = ANY (ARRAY['intake_received'::"text"])))
);


ALTER TABLE "public"."claims" OWNER TO "postgres";


COMMENT ON TABLE "public"."claims" IS 'Claim shell (Tier 2). A customer''s report against a live warranty registration. Intake data model, tokenized intake link, and the Six Gates status value set are Tier 3 and deliberately absent.';



COMMENT ON COLUMN "public"."claims"."claim_id" IS 'Business-visible ClaimID, generated from tenant_id_sequences (id_type = ''claim_id'', default format CLM-{year}-{seq:07d}) in the same transaction as the insert. Independent per-tenant sequence — NOT derived from the parent WarrantyID (v1''s [WarrantyID]-C[NNNN] form is retired). Immutable once set; immutability is enforced in the Server Action.';



COMMENT ON COLUMN "public"."claims"."status" IS 'Minimum locked value: intake_received. Richer values (v1 Six Gates plus outcome states) are Tier 3; the CHECK is extended by migration when that section lands.';



COMMENT ON COLUMN "public"."claims"."is_emergency" IS 'Decision 27.5. Customer-reported emergency stabilization carve-out.';



COMMENT ON COLUMN "public"."claims"."emergency_stabilized_at" IS 'Decision 27.5. Customer-reported stabilization moment; starts the 24-hour formal-filing window. Self-reported at intake, not independently verified by the platform. Required when is_emergency = true — enforced at the intake form / app layer, NOT as a DB CHECK (Decision 27.6: the 24-hour window is not a submission-blocking validation).';



CREATE TABLE IF NOT EXISTS "public"."clock_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "event_type" "text" NOT NULL,
    "entity_type" "text" NOT NULL,
    "entity_id" "uuid" NOT NULL,
    "fires_at" timestamp with time zone NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "fired_at" timestamp with time zone,
    "failure_reason" "text",
    "payload" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "clock_events_entity_type_check" CHECK (("entity_type" = ANY (ARRAY['project'::"text", 'claim'::"text", 'warranty_coverage'::"text", 'work_authorization_document'::"text", 'service_report'::"text", 'ala_document'::"text", 'warranty_registration'::"text"]))),
    CONSTRAINT "clock_events_event_type_check" CHECK (("event_type" = ANY (ARRAY['registration_prep_pre_trigger'::"text", 'info_request_due'::"text", 'warranty_expiry_warning'::"text", 'trigger_confirmation_overdue'::"text", 'service_report_response_due'::"text", 'work_authorization_response_overdue'::"text", 'ala_decline_window_expired'::"text", 'ala_response_overdue'::"text", 'warranty_id_early_issuance'::"text"]))),
    CONSTRAINT "clock_events_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'fired'::"text", 'cancelled'::"text", 'failed'::"text"])))
);


ALTER TABLE "public"."clock_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."contacts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "contact_type" "text" NOT NULL,
    "name" "text" NOT NULL,
    "email" "text",
    "phone" "text",
    "parent_contact_id" "uuid",
    "linked_om_provider_id" "uuid",
    "imported_via_batch_id" "uuid",
    "deleted_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "contacts_contact_type_check" CHECK (("contact_type" = ANY (ARRAY['customer'::"text", 'customer_contact'::"text", 'subcontractor'::"text", 'subcontractor_contact'::"text", 'vendor'::"text", 'vendor_contact'::"text", 'om_provider'::"text", 'om_provider_contact'::"text", 'registration_assignee'::"text", 'other'::"text"])))
);


ALTER TABLE "public"."contacts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."custom_field_definitions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "entity_type" "text" NOT NULL,
    "label" "text" NOT NULL,
    "field_type" "text" NOT NULL,
    "required" boolean DEFAULT false NOT NULL,
    "options" "jsonb",
    "display_order" integer DEFAULT 0 NOT NULL,
    "deleted_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "custom_field_definitions_entity_type_check" CHECK (("entity_type" = ANY (ARRAY['project'::"text", 'warranty_registration'::"text", 'claim'::"text"]))),
    CONSTRAINT "custom_field_definitions_field_type_check" CHECK (("field_type" = ANY (ARRAY['address'::"text", 'phone'::"text", 'date'::"text", 'number'::"text", 'plain_text'::"text", 'rich_text'::"text", 'dropdown'::"text", 'email'::"text", 'url'::"text", 'checkbox'::"text", 'file_upload'::"text"])))
);


ALTER TABLE "public"."custom_field_definitions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."custom_field_values" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "definition_id" "uuid" NOT NULL,
    "project_id" "uuid",
    "warranty_registration_id" "uuid",
    "claim_id" "uuid",
    "value" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "custom_field_values_one_entity_check" CHECK (((((("project_id" IS NOT NULL))::integer + (("warranty_registration_id" IS NOT NULL))::integer) + (("claim_id" IS NOT NULL))::integer) = 1))
);


ALTER TABLE "public"."custom_field_values" OWNER TO "postgres";


COMMENT ON TABLE "public"."custom_field_values" IS 'One filled-in custom field value for one entity instance (Decision 3, Phase 2 decisions log). Companion to custom_field_definitions (015). Typed nullable FKs to the three Phase 1 entities with an exactly-one-non-null CHECK — not a polymorphic key — so referential integrity is real and ON DELETE CASCADE works per entity.';



COMMENT ON COLUMN "public"."custom_field_values"."tenant_id" IS 'Denormalized per the Standard RLS Pattern''s tenant_id convention; custom_field_values is the named precedent for that convention. Avoids a JOIN through custom_field_definitions on every read. Must match the parent definition''s tenant_id — a stay-in-sync invariant enforced app-layer at insert time, not by the database.';



COMMENT ON COLUMN "public"."custom_field_values"."definition_id" IS 'ON DELETE RESTRICT, not CASCADE. Definitions soft-delete via deleted_at and their values remain queryable for historical display and reporting (Decision 3). Hard-delete is admin-tooling only, never exposed in the Phase 1 UI; CASCADE would cascade-destroy auditable data, which the architecture names as the outcome to avoid.';



COMMENT ON COLUMN "public"."custom_field_values"."value" IS 'Type-safe per the parent definition''s field_type, validated app-layer at write time. rich_text values are ProseMirror-compatible JSON (Decision 4) — a format named for the data, not the editor library, so it outlives TipTap.';



CREATE TABLE IF NOT EXISTS "public"."import_batches" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "initiated_by" "uuid",
    "source_filename" "text",
    "project_count" integer,
    "customer_count" integer,
    "status" "text" DEFAULT 'completed'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "import_batches_status_check" CHECK (("status" = ANY (ARRAY['completed'::"text", 'failed'::"text", 'rolled_back'::"text"])))
);


ALTER TABLE "public"."import_batches" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."inspection_triggers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "value" "text" NOT NULL,
    "label" "text" NOT NULL,
    "lock_tier" "text" NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "disabled_at" timestamp with time zone,
    "deleted_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "inspection_triggers_lock_tier_check" CHECK (("lock_tier" = ANY (ARRAY['platform_locked'::"text", 'platform_seeded'::"text", 'tenant_added'::"text"])))
);


ALTER TABLE "public"."inspection_triggers" OWNER TO "postgres";


COMMENT ON TABLE "public"."inspection_triggers" IS 'Tenant-editable defaults lookup table for inspection triggers: what caused an inspection to be performed. Second canonical application of the Tenant-Editable Defaults Pattern (Decision 17 Part A). Eight platform_locked defaults seeded per tenant (Decision 17.B.2); tenants may add tenant_added rows, and may disable but not rename or soft-delete the platform_locked defaults. The inspections table references this via inspection_trigger_id (FK) + inspection_trigger_value (snapshot) per 17.A.2.';



COMMENT ON COLUMN "public"."inspection_triggers"."value" IS 'Platform-canonical identifier: snake_case, lowercase, stable. Identical across all tenants for platform_locked rows (Decision 17.A.9) so cross-tenant analytics filter by value rather than id. Locked for platform_locked and platform_seeded rows; auto-slugified from label at creation for tenant_added rows. Uniqueness within (tenant_id) is an application-layer invariant.';



COMMENT ON COLUMN "public"."inspection_triggers"."label" IS 'Tenant-displayed name shown in dropdowns, reports, and operational UI. Editable for platform_seeded and tenant_added rows; locked for platform_locked rows. Label edits never re-derive value.';



COMMENT ON COLUMN "public"."inspection_triggers"."lock_tier" IS 'Three-category discriminator (Decision 17.A.5). platform_locked: platform commits to the value as canonical; tenants cannot rename or soft-delete, but CAN disable. platform_seeded: starting point; tenants can rename and disable, cannot soft-delete. tenant_added: full tenant control. Edit permissions are enforced app-layer per 17.A.6; the CHECK constrains the value set only.';



COMMENT ON COLUMN "public"."inspection_triggers"."disabled_at" IS 'Tenant-disabled. Hides the row from new-entry dropdowns and the active admin list view; historical operational records referencing the value continue to display normally (the FK + Snapshot integration preserves the value at row creation). Applies to ALL lock_tiers including platform_locked (17.A.7).';



COMMENT ON COLUMN "public"."inspection_triggers"."deleted_at" IS 'Soft-delete. Applies ONLY to lock_tier = tenant_added rows (17.A.7); the platform commits to structural persistence of platform_locked and platform_seeded rows. disabled_at is the operational analog for those. Enforced app-layer, not by DB CHECK, per 17.A.6.';



CREATE TABLE IF NOT EXISTS "public"."inspection_types" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "value" "text" NOT NULL,
    "label" "text" NOT NULL,
    "lock_tier" "text" NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "disabled_at" timestamp with time zone,
    "deleted_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "inspection_types_lock_tier_check" CHECK (("lock_tier" = ANY (ARRAY['platform_locked'::"text", 'platform_seeded'::"text", 'tenant_added'::"text"])))
);


ALTER TABLE "public"."inspection_types" OWNER TO "postgres";


COMMENT ON TABLE "public"."inspection_types" IS 'Tenant-editable defaults lookup table for inspection types. First canonical application of the Tenant-Editable Defaults Pattern (Decision 17 Part A). Four platform_locked defaults seeded per tenant (Decision 17.B.1); tenants may add tenant_added rows, and may disable but not rename or soft-delete the platform_locked defaults. The inspections table references this via inspection_type_id (FK) + inspection_type_value (snapshot) per 17.A.2.';



COMMENT ON COLUMN "public"."inspection_types"."value" IS 'Platform-canonical identifier: snake_case, lowercase, stable. Identical across all tenants for platform_locked rows (Decision 17.A.9) so cross-tenant analytics filter by value rather than id. Locked for platform_locked and platform_seeded rows; auto-slugified from label at creation for tenant_added rows. Uniqueness within (tenant_id) is an application-layer invariant.';



COMMENT ON COLUMN "public"."inspection_types"."label" IS 'Tenant-displayed name shown in dropdowns, reports, and operational UI. Editable for platform_seeded and tenant_added rows; locked for platform_locked rows. Label edits never re-derive value.';



COMMENT ON COLUMN "public"."inspection_types"."lock_tier" IS 'Three-category discriminator (Decision 17.A.5). platform_locked: platform commits to the value as canonical; tenants cannot rename or soft-delete, but CAN disable. platform_seeded: starting point; tenants can rename and disable, cannot soft-delete. tenant_added: full tenant control. Edit permissions are enforced app-layer per 17.A.6; the CHECK constrains the value set only.';



COMMENT ON COLUMN "public"."inspection_types"."disabled_at" IS 'Tenant-disabled. Hides the row from new-entry dropdowns and the active admin list view; historical operational records referencing the value continue to display normally (the FK + Snapshot integration preserves the value at row creation). Applies to ALL lock_tiers including platform_locked (17.A.7).';



COMMENT ON COLUMN "public"."inspection_types"."deleted_at" IS 'Soft-delete. Applies ONLY to lock_tier = tenant_added rows (17.A.7); the platform commits to structural persistence of platform_locked and platform_seeded rows. disabled_at is the operational analog for those. Enforced app-layer, not by DB CHECK, per 17.A.6.';



CREATE TABLE IF NOT EXISTS "public"."inspections" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "claim_id" "uuid" NOT NULL,
    "performed_by" "text" NOT NULL,
    "paid_by" "text" NOT NULL,
    "inspection_type_id" "uuid" NOT NULL,
    "inspection_type_value" "text" NOT NULL,
    "inspection_trigger_id" "uuid" NOT NULL,
    "inspection_trigger_value" "text" NOT NULL,
    "status" "text" DEFAULT 'open'::"text" NOT NULL,
    "inspection_report" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "inspections_paid_by_check" CHECK (("paid_by" = ANY (ARRAY['warrantor'::"text", 'claimant'::"text", 'third_party'::"text"]))),
    CONSTRAINT "inspections_performed_by_check" CHECK (("performed_by" = ANY (ARRAY['warrantor'::"text", 'third_party'::"text"]))),
    CONSTRAINT "inspections_status_check" CHECK (("status" = ANY (ARRAY['open'::"text", 'in_progress'::"text", 'under_review'::"text", 'issued'::"text"])))
);


ALTER TABLE "public"."inspections" OWNER TO "postgres";


COMMENT ON TABLE "public"."inspections" IS 'A claim-level investigation into a defect''s cause, scope, or fix (Decision 17 Part B, Decision 18). Used when a claim''s information is insufficient to determine corrective actions, or when an Indistinct claim needs investigation before warranty determination. Zero, one, or many per claim. The canonical reference example for the Tenant-Editable Defaults role-based decision tree: five enum-like columns across three patterns.';



COMMENT ON COLUMN "public"."inspections"."performed_by" IS 'WHO PERFORMS the inspection: warrantor (own personnel) or third_party (an external expert, subcontractor, structural engineer, manufacturer''s rep, or independent investigator). Platform-locked CHECK enum — a structural axis universal across warrantor business models. Orthogonal to paid_by: every performer/payer combination is operationally real and valid.';



COMMENT ON COLUMN "public"."inspections"."paid_by" IS 'WHO PAYS for the inspection: warrantor, claimant, or third_party (vendor reimbursement, insurer-funded, or similar cases where cost is borne by a party external to the warrantor-claimant relationship). Platform-locked CHECK enum — a structural axis. Read by the Tier 3 cost-tracking section to determine the cost recovery path. Orthogonal to performed_by.';



COMMENT ON COLUMN "public"."inspections"."inspection_type_value" IS 'Snapshot of inspection_types.value at row creation (FK + Snapshot Pattern). Never updated on read, never re-synced when the lookup row changes. Lets cross-tenant analytics filter on value without joining the per-tenant lookup table; per-tenant queries reading the current label join through the FK.';



COMMENT ON COLUMN "public"."inspections"."inspection_trigger_value" IS 'Snapshot of inspection_triggers.value at row creation (FK + Snapshot Pattern). Never re-synced. Also answers the WHO-asked question per Decision 18.2 — Customer Request implies claimant-initiated, Third Party implies external-party-initiated, the remaining trigger values imply warrantor-initiated. There is deliberately no requested_by column.';



COMMENT ON COLUMN "public"."inspections"."status" IS 'Platform-locked workflow-driver enum. open (created, awaiting activity; subsumes the original enum''s requested and scheduled, since no field work has happened in either) -> in_progress (field work actively underway, regardless of session count) -> under_review (observations captured, internal review and documentation drafting) -> issued (documentation finalized and released to customer; terminal on the happy path — some tenant vocabularies call this document a Non-Conformance Report). Backward transitions are not part of the architectural commitment at this layer.';



COMMENT ON COLUMN "public"."inspections"."inspection_report" IS 'Per-inspection findings as JSONB, because inspection shapes capture different things: pile depths and soil conditions on a foundation issue, load calculations and failure mode analysis on a racking failure, a contracted investigator''s narrative elsewhere. Also the flexibility mechanism in lieu of custom fields (Audit Topic 11), and the operational home for claimant attendance if a tenant tracks it (Decision 18.1).';



CREATE TABLE IF NOT EXISTS "public"."internal_teams" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "deleted_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."internal_teams" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."invitations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "email" "text" NOT NULL,
    "role" "text" NOT NULL,
    "full_name" "text",
    "token" "text" NOT NULL,
    "expires_at" timestamp with time zone NOT NULL,
    "consumed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "invited_by" "uuid",
    CONSTRAINT "invitations_role_check" CHECK (("role" = ANY (ARRAY['team_admin'::"text", 'reviewer'::"text", 'viewer'::"text"])))
);


ALTER TABLE "public"."invitations" OWNER TO "postgres";


COMMENT ON TABLE "public"."invitations" IS 'Pending invitations. Token is validated at signup; auth user is created then, not at provisioning time.';



COMMENT ON COLUMN "public"."invitations"."token" IS '64-char hex string (32 random bytes). Sent in the signup URL, never stored hashed — protected by service-role-only writes and RLS.';



COMMENT ON COLUMN "public"."invitations"."consumed_at" IS 'Set when the invited user completes signup. Non-null means the token is spent.';



COMMENT ON COLUMN "public"."invitations"."invited_by" IS 'User who created this invitation. NULL for platform-admin-issued invitations.';



CREATE TABLE IF NOT EXISTS "public"."projects" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "trigger_source" "text" NOT NULL,
    "trigger_status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "trigger_date" "date",
    "integration_config" "jsonb",
    "customer_id" "uuid",
    "customer_name_snapshot" "text",
    "customer_email_snapshot" "text",
    "customer_phone_snapshot" "text",
    "site_address_street" "text",
    "site_address_city" "text",
    "site_address_state" "text",
    "site_address_zip" "text",
    "imported_via_batch_id" "uuid",
    "deleted_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "projects_trigger_source_check" CHECK (("trigger_source" = ANY (ARRAY['contractual_date_manual'::"text", 'wbs_integration'::"text", 'delivery_report_tokenized'::"text", 'delivery_report_api'::"text"]))),
    CONSTRAINT "projects_trigger_status_check" CHECK (("trigger_status" = ANY (ARRAY['pending'::"text", 'confirmed'::"text", 'overdue'::"text"])))
);


ALTER TABLE "public"."projects" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."tenant_holidays" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "holiday_date" "date" NOT NULL,
    "label" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."tenant_holidays" OWNER TO "postgres";


COMMENT ON TABLE "public"."tenant_holidays" IS 'Per-tenant holiday calendar (Decision 25.3). Business-day math skips Saturdays, Sundays, and any date in this table for the tenant in question. Extends the Tenant-Editable Defaults PHILOSOPHY (platform seeds at provisioning, tenant owns forever after, no propagation -- 17.A.3) but deliberately NOT its mechanics: no lock_tier, no is_system, no protection trigger, because no operational table references a holiday by FK. The seed is a STARTING DEFAULT, not a model of what warrantors observe -- no two companies recognize the same set, and every tenant edits from day one. A tenant may delete every row here; business-day math then skips weekends only.';



COMMENT ON COLUMN "public"."tenant_holidays"."holiday_date" IS 'The concrete OBSERVED date the tenant is closed -- not the nominal calendar date of the holiday. The seed applies the federal observed-shift rule (Saturday -> preceding Friday, Sunday -> following Monday) to the four fixed-date holidays, because that is what OPM publishes and what most U.S. warrantors follow, so most tenants edit nothing. Tenants who differ edit rows: taking the Monday instead of the Friday changes this value, taking both adds a row, taking neither deletes. Storing observed dates rather than holiday rules is precisely what makes that variance expressible without any schema support.';



CREATE TABLE IF NOT EXISTS "public"."tenant_id_sequences" (
    "tenant_id" "uuid" NOT NULL,
    "id_type" "text" NOT NULL,
    "format_string" "text" NOT NULL,
    "current_year" integer NOT NULL,
    "current_value" integer DEFAULT 0 NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "tenant_id_sequences_id_type_check" CHECK (("id_type" = ANY (ARRAY['warranty_id'::"text", 'claim_id'::"text"])))
);


ALTER TABLE "public"."tenant_id_sequences" OWNER TO "postgres";


COMMENT ON TABLE "public"."tenant_id_sequences" IS 'Per-(tenant, id_type) gap-free identifier counters. One row per id_type per tenant. Read/updated in the same transaction as the record that consumes the id, giving the gap-free guarantee. Decision 2; architecture-reference.md ID Generation section.';



COMMENT ON COLUMN "public"."tenant_id_sequences"."format_string" IS 'Python format-string syntax: {year} and {seq:NNd}. Validated at settings-save time, not generation time.';



COMMENT ON COLUMN "public"."tenant_id_sequences"."current_year" IS 'UTC year the counter is currently advancing in. On first generation of a new UTC year, the increment UPDATE resets current_value to 1 and updates this.';



CREATE TABLE IF NOT EXISTS "public"."tenants" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "slug" "text" NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "settings" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "max_team_admins" integer DEFAULT 3 NOT NULL,
    CONSTRAINT "tenants_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'suspended'::"text", 'terminated'::"text"])))
);


ALTER TABLE "public"."tenants" OWNER TO "postgres";


COMMENT ON COLUMN "public"."tenants"."slug" IS 'URL-safe identifier for the tenant, e.g. "acme-solar"';



COMMENT ON COLUMN "public"."tenants"."settings" IS 'Per-org configuration: WarrantyID format, ClaimID format, feature flags, etc.';



COMMENT ON COLUMN "public"."tenants"."max_team_admins" IS 'Contracted Team Admin seat count. Enforcement added in Session 5b.';



CREATE TABLE IF NOT EXISTS "public"."users" (
    "id" "uuid" NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "email" "text" NOT NULL,
    "role" "text" NOT NULL,
    "full_name" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "removed_at" timestamp with time zone,
    CONSTRAINT "users_role_check" CHECK (("role" = ANY (ARRAY['team_admin'::"text", 'reviewer'::"text", 'viewer'::"text"]))),
    CONSTRAINT "users_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'suspended'::"text"])))
);


ALTER TABLE "public"."users" OWNER TO "postgres";


COMMENT ON COLUMN "public"."users"."role" IS 'team_admin: tenant configuration and team management; reviewer: claim evaluation; viewer: read-only';



COMMENT ON COLUMN "public"."users"."status" IS 'active: normal access; suspended: temporarily blocked (reversible)';



COMMENT ON COLUMN "public"."users"."removed_at" IS 'Set when a team admin removes a user. Non-null means permanently blocked. Auth account is NOT deleted — historical attribution is preserved.';



CREATE TABLE IF NOT EXISTS "public"."warranty_coverages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "warranty_registration_id" "uuid" NOT NULL,
    "warranty_type_id" "uuid" NOT NULL,
    "start_date" "date" NOT NULL,
    "term_years" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "warranty_coverages_term_years_check" CHECK (("term_years" > 0))
);


ALTER TABLE "public"."warranty_coverages" OWNER TO "postgres";


COMMENT ON TABLE "public"."warranty_coverages" IS 'One warranty type instantiated on one registration. start_date is an immutable trigger_date snapshot (Decision 23.5); end_date is NOT stored - read effective start/end from warranty_coverages_effective (Decision 24). One row per (registration, type).';



COMMENT ON COLUMN "public"."warranty_coverages"."start_date" IS 'Immutable snapshot of projects.trigger_date at coverage creation (Decision 23.5). Never read directly for effective-start purposes - use warranty_coverages_effective.effective_start_date (Decisions 23.5a/24.3).';



CREATE TABLE IF NOT EXISTS "public"."warranty_registrations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "project_id" "uuid" NOT NULL,
    "warranty_id" "text",
    "status" "text" NOT NULL,
    "assigned_to_contact_id" "uuid",
    "assigned_to_user_id" "uuid",
    "assigned_to_name_snapshot" "text",
    "assigned_to_email_snapshot" "text",
    "assigned_to_phone_snapshot" "text",
    "assigned_at" timestamp with time zone,
    "activated_at" timestamp with time zone,
    "actual_start_date" "date",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "warranty_registrations_assignee_check" CHECK (((("status" = 'pre_activation'::"text") AND ("assigned_to_contact_id" IS NULL) AND ("assigned_to_user_id" IS NULL)) OR (("status" = ANY (ARRAY['assigned'::"text", 'active'::"text", 'rejected'::"text"])) AND (("assigned_to_contact_id" IS NOT NULL) <> ("assigned_to_user_id" IS NOT NULL))))),
    CONSTRAINT "warranty_registrations_status_check" CHECK (("status" = ANY (ARRAY['pre_activation'::"text", 'assigned'::"text", 'active'::"text", 'rejected'::"text"])))
);


ALTER TABLE "public"."warranty_registrations" OWNER TO "postgres";


COMMENT ON TABLE "public"."warranty_registrations" IS 'Parent record for one warranty agreement on one project (1:1 with projects, enforced by UNIQUE project_id). Carries WarrantyID once issued, tracks the assignee, parents coverages and claims. Decisions 1/5/23; architecture-reference.md Warranty Registration section.';



COMMENT ON COLUMN "public"."warranty_registrations"."warranty_id" IS 'Business-visible WarrantyID. Issued via tenant_id_sequences no later than effective_start_date (Decisions 2/27). Null until issued; immutable once set (app-layer enforcement).';



COMMENT ON COLUMN "public"."warranty_registrations"."status" IS 'Four-state machine (Decision 23.7): pre_activation (edge fallback), assigned (prep), active (Section 7 passed, WarrantyID issued), rejected (Section 7 rejected, loops back to assigned). Transitions enforced app-layer.';



COMMENT ON COLUMN "public"."warranty_registrations"."actual_start_date" IS 'Warrantor-confirmed operational start date (Decision 23.4). Null until confirmed. Effective start is COALESCE(actual_start_date, coverage/trigger date) derived at query time (23.5/23.9) - never read this or trigger_date directly for effective-start purposes (23.5a application invariant).';



CREATE OR REPLACE VIEW "public"."warranty_coverages_effective" WITH ("security_invoker"='true') AS
 SELECT "c"."id",
    "c"."tenant_id",
    "c"."warranty_registration_id",
    "c"."warranty_type_id",
    "c"."start_date",
    "c"."term_years",
    COALESCE("r"."actual_start_date", "c"."start_date") AS "effective_start_date",
    ((COALESCE("r"."actual_start_date", "c"."start_date") + (("c"."term_years" || ' years'::"text"))::interval))::"date" AS "effective_end_date"
   FROM ("public"."warranty_coverages" "c"
     JOIN "public"."warranty_registrations" "r" ON (("r"."id" = "c"."warranty_registration_id")));


ALTER VIEW "public"."warranty_coverages_effective" OWNER TO "postgres";


COMMENT ON VIEW "public"."warranty_coverages_effective" IS 'Canonical read surface for coverage effective_start_date and effective_end_date (Decision 24). COALESCE(registration.actual_start_date, coverage.start_date) for start; start + term_years for end. security_invoker=true so underlying-table RLS is enforced (24.5). All effective start/end reads MUST use this view (24.3).';



CREATE TABLE IF NOT EXISTS "public"."warranty_types" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "is_system" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."warranty_types" OWNER TO "postgres";


COMMENT ON TABLE "public"."warranty_types" IS 'Per-tenant configurable warranty type list. Coverages instantiate these on registrations. Two anchor types (Standard Warranty, Workmanship Warranty) are seeded per tenant with is_system=true and are permanent. Decision 6; architecture-reference.md Warranty Type Coverages section.';



COMMENT ON COLUMN "public"."warranty_types"."is_system" IS 'True on anchor types seeded at provisioning. Protected from DELETE and from is_system->false by defense-in-depth (Server Action + DB trigger, Decision 6). Renameable, not deleteable.';



CREATE TABLE IF NOT EXISTS "public"."work_authorization_documents" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "claim_id" "uuid" NOT NULL,
    "template_id" "uuid" NOT NULL,
    "template_snapshot" "jsonb" NOT NULL,
    "event_type" "text" NOT NULL,
    "event_reference_id" "uuid",
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "expected_response_date" "date",
    "requestor_name" "text" NOT NULL,
    "requestor_company" "text" NOT NULL,
    "requestor_phone" "text",
    "requestor_email" "text" NOT NULL,
    "planned_start_at" timestamp with time zone NOT NULL,
    "planned_end_at" timestamp with time zone NOT NULL,
    "crew_size" integer NOT NULL,
    "sow_activities" "jsonb" NOT NULL,
    "om_provider_company" "text",
    "om_contact_name" "text",
    "om_contact_phone" "text",
    "om_contact_email" "text",
    "site_emergency_address" "jsonb",
    "site_accessibility_date" "date",
    "operating_hours" "text",
    "special_access_required" boolean,
    "special_access_details" "jsonb",
    "gate_code_needed" boolean,
    "gate_code_details" "jsonb",
    "customer_comments" "jsonb",
    "customer_decision" "text",
    "denial_explanation" "jsonb",
    "signer_name_typed" "text",
    "authorization_acknowledged" boolean,
    "request_completed_by_name" "text",
    "customer_token" "text",
    "customer_token_expires_at" timestamp with time zone,
    "requested_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "responded_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "work_authorization_documents_customer_decision_check" CHECK (("customer_decision" = ANY (ARRAY['approved'::"text", 'denied'::"text"]))),
    CONSTRAINT "work_authorization_documents_event_type_check" CHECK (("event_type" = ANY (ARRAY['inspection'::"text", 'repair_work'::"text", 'site_visit'::"text"]))),
    CONSTRAINT "work_authorization_documents_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'sent'::"text", 'approved'::"text", 'denied'::"text", 'revised'::"text", 'resent'::"text", 'withdrawn'::"text"])))
);


ALTER TABLE "public"."work_authorization_documents" OWNER TO "postgres";


COMMENT ON TABLE "public"."work_authorization_documents" IS 'One customer authorization for one bounded on-site event (Decision 11). The customer-facing COMMITMENT generated from a Work Plan''s INTENT. Universal blocking gate: no on-site activity proceeds without an approved document for that specific event -- broader than SOP 1''s inspection-only language, which the architecture treats as the canonical instance, not the limit. One-to-many with claims: each document bounds one event, and a claim may have many across its lifecycle. Contrast ala_documents and service_reports, which are UNIQUE per claim because they bound the claim as a whole.';



COMMENT ON COLUMN "public"."work_authorization_documents"."event_reference_id" IS 'Polymorphic reference to the authorized event: inspections.id when event_type = ''inspection'', work_plans.id when ''repair_work''. NO database FK -- Decision 11 locks the two-column (event_type + event_reference_id) shape, and typed per-event FK columns would delete this locked column. Precedent: clock_events.entity_id. Dispatch and referential integrity are app-layer; the application must check for active authorizations before allowing a referenced event entity to be deleted.';



COMMENT ON COLUMN "public"."work_authorization_documents"."status" IS 'Seven-value state machine. draft (warrantor authoring; customer cannot see it) -> sent (tokenized link emailed) -> approved (terminal happy path; on-site activity authorized) | denied (triggers revise-and-resend) -> revised (warrantor edited the denied document) -> resent (customer decides again, seeing the full revision history) | withdrawn (request scrapped entirely; fallback for denials not recoverable through revision). Transitions run through Server Actions. Authority rules per transition are operational and deferred.';



COMMENT ON COLUMN "public"."work_authorization_documents"."authorization_acknowledged" IS 'The "I authorize" checkbox. Together with signer_name_typed this is the signature artifact constituting legal approval. Deliberately distinct from ALA''s mechanism (Decision 19''s Accept/Decline + atomic signature + recant window): ALA''s assumption of financial liability warrants that ceremony, while authorizing on-site activity fits typed-name-plus-checkbox atomicity. Neither pre-decides the other.';



COMMENT ON COLUMN "public"."work_authorization_documents"."customer_token" IS 'Fifth canonical use of the Stateless Tokenized Interaction Pattern, after claim intake, registration assignee submission, supply-only delivery reporting, and service report customer review. Stored on this row per the pattern''s "shape to copy, not shared store" rule. When a tenant configures an Acknowledgment Gate for gate_purpose = ''work_authorization'' (Decision 12), that gate is an interstitial on THIS token -- there is no second token.';



CREATE TABLE IF NOT EXISTS "public"."work_authorization_revisions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "work_authorization_document_id" "uuid" NOT NULL,
    "revised_by_user_id" "uuid" NOT NULL,
    "revision_reason" "jsonb" NOT NULL,
    "field_changes" "jsonb" NOT NULL,
    "revised_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."work_authorization_revisions" OWNER TO "postgres";


COMMENT ON TABLE "public"."work_authorization_revisions" IS 'Full history of warrantor edits to one Work Authorization document (Decision 11). Revise-and-resend is the PRIMARY recovery path for a denied authorization -- not withdraw-and-recreate. The document''s id, claim_id, and event_reference_id stay the same; the same request evolves through revisions until approved or withdrawn. The customer sees the full revision history transparently on resend (Option A in Decision 11: transparency for trust-building and audit-defensibility; burying the history was rejected). Built verbatim to the locked sketch: revised_at only, no created_at/updated_at, no soft-delete.';



CREATE TABLE IF NOT EXISTS "public"."work_authorization_templates" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "warrantor_field_config" "jsonb" NOT NULL,
    "customer_field_config" "jsonb" NOT NULL,
    "legal_language" "jsonb" NOT NULL,
    "is_default" boolean DEFAULT false NOT NULL,
    "deleted_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."work_authorization_templates" OWNER TO "postgres";


COMMENT ON TABLE "public"."work_authorization_templates" IS 'Tenant-defined reusable configuration for Customer Work Authorization (Decision 11). Same templates-and-documents shape as the ALA System and the Acknowledgment Gate Pattern. Soft-delete is required, not optional: retired templates must remain queryable because documents generated from them reference template_id for reporting.';



COMMENT ON COLUMN "public"."work_authorization_templates"."is_default" IS 'At most one is_default = true per tenant is the architectural intent. Enforcement is app-layer: the arch ref offers partial-UNIQUE or app-layer and picks neither, and Decision 17.A.6 caps v1 DB enforcement. Parallel to ALA''s and Acknowledgment Gate''s is_default flags.';



CREATE TABLE IF NOT EXISTS "public"."work_plans" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "claim_id" "uuid" NOT NULL,
    "execution_path" "text" NOT NULL,
    "internal_team_id" "uuid",
    "subcontractor_contact_id" "uuid",
    "subcontractor_name_snapshot" "text",
    "subcontractor_email_snapshot" "text",
    "subcontractor_phone_snapshot" "text",
    "warranty_professional_user_id" "uuid" NOT NULL,
    "work_plan_type" "text" NOT NULL,
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "planned_start_at" timestamp with time zone NOT NULL,
    "planned_end_at" timestamp with time zone NOT NULL,
    "crew_size" integer NOT NULL,
    "corrective_actions" "jsonb" NOT NULL,
    "required_materials_equipment" "jsonb",
    "repair_scope_approach" "jsonb" NOT NULL,
    "safety_considerations" "jsonb",
    "site_access_coordination" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "work_plans_execution_path_check" CHECK (("execution_path" = ANY (ARRAY['warrantor_self_performs'::"text", 'scope_owned_subcontractor'::"text", 'outsourced_subcontractor'::"text", 'customer_self_services'::"text"]))),
    CONSTRAINT "work_plans_internal_team_path_check" CHECK (((("execution_path" = 'warrantor_self_performs'::"text") AND ("internal_team_id" IS NOT NULL)) OR (("execution_path" <> 'warrantor_self_performs'::"text") AND ("internal_team_id" IS NULL)))),
    CONSTRAINT "work_plans_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'sent_for_authorization'::"text", 'authorized'::"text", 'completed'::"text", 'cancelled'::"text"]))),
    CONSTRAINT "work_plans_subcontractor_path_check" CHECK (((("execution_path" = ANY (ARRAY['scope_owned_subcontractor'::"text", 'outsourced_subcontractor'::"text"])) AND ("subcontractor_contact_id" IS NOT NULL)) OR (("execution_path" <> ALL (ARRAY['scope_owned_subcontractor'::"text", 'outsourced_subcontractor'::"text"])) AND ("subcontractor_contact_id" IS NULL)))),
    CONSTRAINT "work_plans_work_plan_type_check" CHECK (("work_plan_type" = ANY (ARRAY['repair'::"text", 'inspection'::"text", 'both'::"text"])))
);


ALTER TABLE "public"."work_plans" OWNER TO "postgres";


COMMENT ON TABLE "public"."work_plans" IS 'The warrantor''s INTENT: the planned corrective actions for a claim (Decisions 13/15/16; SOP 6). Customer Work Authorization (Decision 11) is the customer-facing COMMITMENT generated from this intent — the two entities are deliberately separate. One-to-many with claims: each Work Plan bounds one execution event, and a claim may have many across its lifecycle. Parts Claims (claim_type = replacement_parts) do NOT flow through this workflow per Decision 16.3; their fulfillment is a separate future architecture.';



COMMENT ON COLUMN "public"."work_plans"."execution_path" IS 'v1''s Four Work Plan Execution Paths, platform-locked (Decision 13.2). warrantor_self_performs: an internal team executes. scope_owned_subcontractor: the original installer with an active warranty obligation executes (v1 Path 2A). outsourced_subcontractor: a third party procured via RFQ executes (v1 Path 2B). customer_self_services: the customer executes with warrantor reimbursement (v1 Path 3). Extensible via migration if a fifth path surfaces operationally.';



COMMENT ON COLUMN "public"."work_plans"."internal_team_id" IS 'The specific internal team executing, when execution_path = warrantor_self_performs (Decision 13.1). Team labels are tenant data, NOT platform enum values (13.4). ON DELETE RESTRICT is the only architecturally available clause: Decision 13.3 requires soft-delete precisely so historical work_plans retain this FK when teams retire — CASCADE would destroy those rows, and SET NULL would violate work_plans_internal_team_path_check.';



COMMENT ON COLUMN "public"."work_plans"."subcontractor_contact_id" IS 'The executing subcontractor, when execution_path is scope_owned_subcontractor or outsourced_subcontractor (Decision 13.1). FK + Snapshot Pattern, single-FK shape. Single-FK rather than the dual-FK shape Service Report uses for its submitter: execution_path already disambiguates who executes, so the assignee capture splits cleanly by path and needs no column accepting either a contact or a user.';



COMMENT ON COLUMN "public"."work_plans"."warranty_professional_user_id" IS 'The tenant user managing this Work Plan from the warrantor''s side — the workbook''s "Warrantor Contact". Always populated regardless of execution_path. The workbook''s Name/Phone/Email fields resolve through this FK''s joined user record rather than as redundant columns.';



COMMENT ON COLUMN "public"."work_plans"."work_plan_type" IS 'Whether this Work Plan covers repair work, inspection work, or both. From the Work Plan Data Inputs workbook''s "Work Plan Type" dropdown. The relationship between work_plan_type = both and Customer Work Authorization''s event_type (one bundled document vs two separate documents) is a downstream operational question, not locked here.';



COMMENT ON COLUMN "public"."work_plans"."status" IS 'Five-value state machine (Decision 15.1): draft (authored, customer cannot see it) -> sent_for_authorization (bundled into a Customer Work Authorization and sent; stays here across the Work Authorization''s own revision cycles per 15.5) -> authorized (a Work Authorization for this plan was customer-approved) -> completed (a Service Report exists for the claim). cancelled is terminal for abandoned plans. Transitions run through Server Actions, never direct UPDATE. Deliberately absent: submitted (15.2), in_execution (15.3), a scheduling state (15.4), revised/resent (15.5).';



COMMENT ON COLUMN "public"."work_plans"."planned_end_at" IS 'SOP 6 component 6 (Estimated Duration) is captured as the planned_start_at / planned_end_at pair rather than a duration scalar, mirroring Customer Work Authorization (Decision 11) so fields replicate cleanly when a Work Authorization is generated from this plan. The workbook''s "Number of Days to Complete" is derivable from the difference.';



ALTER TABLE ONLY "public"."acknowledgment_gate_records"
    ADD CONSTRAINT "acknowledgment_gate_records_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."acknowledgment_gate_templates"
    ADD CONSTRAINT "acknowledgment_gate_templates_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ala_document_revisions"
    ADD CONSTRAINT "ala_document_revisions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ala_documents"
    ADD CONSTRAINT "ala_documents_claim_id_key" UNIQUE ("claim_id");



ALTER TABLE ONLY "public"."ala_documents"
    ADD CONSTRAINT "ala_documents_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ala_templates"
    ADD CONSTRAINT "ala_templates_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."claims"
    ADD CONSTRAINT "claims_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."clock_events"
    ADD CONSTRAINT "clock_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."contacts"
    ADD CONSTRAINT "contacts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."custom_field_definitions"
    ADD CONSTRAINT "custom_field_definitions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."custom_field_values"
    ADD CONSTRAINT "custom_field_values_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."import_batches"
    ADD CONSTRAINT "import_batches_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."inspection_triggers"
    ADD CONSTRAINT "inspection_triggers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."inspection_types"
    ADD CONSTRAINT "inspection_types_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."inspections"
    ADD CONSTRAINT "inspections_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."internal_teams"
    ADD CONSTRAINT "internal_teams_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."invitations"
    ADD CONSTRAINT "invitations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."invitations"
    ADD CONSTRAINT "invitations_token_key" UNIQUE ("token");



ALTER TABLE ONLY "public"."projects"
    ADD CONSTRAINT "projects_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."tenant_holidays"
    ADD CONSTRAINT "tenant_holidays_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."tenant_id_sequences"
    ADD CONSTRAINT "tenant_id_sequences_pkey" PRIMARY KEY ("tenant_id", "id_type");



ALTER TABLE ONLY "public"."tenants"
    ADD CONSTRAINT "tenants_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."tenants"
    ADD CONSTRAINT "tenants_slug_key" UNIQUE ("slug");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."warranty_coverages"
    ADD CONSTRAINT "warranty_coverages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."warranty_coverages"
    ADD CONSTRAINT "warranty_coverages_registration_type_unique" UNIQUE ("warranty_registration_id", "warranty_type_id");



ALTER TABLE ONLY "public"."warranty_registrations"
    ADD CONSTRAINT "warranty_registrations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."warranty_registrations"
    ADD CONSTRAINT "warranty_registrations_project_id_key" UNIQUE ("project_id");



ALTER TABLE ONLY "public"."warranty_types"
    ADD CONSTRAINT "warranty_types_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."work_authorization_documents"
    ADD CONSTRAINT "work_authorization_documents_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."work_authorization_revisions"
    ADD CONSTRAINT "work_authorization_revisions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."work_authorization_templates"
    ADD CONSTRAINT "work_authorization_templates_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."work_plans"
    ADD CONSTRAINT "work_plans_pkey" PRIMARY KEY ("id");



CREATE INDEX "acknowledgment_gate_records_authorized_entity_idx" ON "public"."acknowledgment_gate_records" USING "btree" ("authorized_entity_type", "authorized_entity_id");



CREATE INDEX "acknowledgment_gate_records_template_id_idx" ON "public"."acknowledgment_gate_records" USING "btree" ("template_id");



CREATE INDEX "acknowledgment_gate_records_tenant_id_idx" ON "public"."acknowledgment_gate_records" USING "btree" ("tenant_id");



CREATE INDEX "acknowledgment_gate_templates_purpose_idx" ON "public"."acknowledgment_gate_templates" USING "btree" ("tenant_id", "gate_purpose");



CREATE INDEX "acknowledgment_gate_templates_tenant_id_idx" ON "public"."acknowledgment_gate_templates" USING "btree" ("tenant_id");



CREATE INDEX "ala_document_revisions_document_id_idx" ON "public"."ala_document_revisions" USING "btree" ("ala_document_id");



CREATE INDEX "ala_document_revisions_tenant_id_idx" ON "public"."ala_document_revisions" USING "btree" ("tenant_id");



CREATE INDEX "ala_documents_template_id_idx" ON "public"."ala_documents" USING "btree" ("template_id");



CREATE INDEX "ala_documents_tenant_id_idx" ON "public"."ala_documents" USING "btree" ("tenant_id");



CREATE INDEX "ala_templates_tenant_id_idx" ON "public"."ala_templates" USING "btree" ("tenant_id");



CREATE INDEX "claims_tenant_id_idx" ON "public"."claims" USING "btree" ("tenant_id");



CREATE INDEX "claims_warranty_registration_id_idx" ON "public"."claims" USING "btree" ("warranty_registration_id");



CREATE INDEX "clock_events_entity_idx" ON "public"."clock_events" USING "btree" ("entity_type", "entity_id");



CREATE INDEX "clock_events_pending_fires_at_idx" ON "public"."clock_events" USING "btree" ("fires_at") WHERE ("status" = 'pending'::"text");



CREATE INDEX "clock_events_tenant_idx" ON "public"."clock_events" USING "btree" ("tenant_id");



CREATE INDEX "contacts_linked_om_provider_id_idx" ON "public"."contacts" USING "btree" ("linked_om_provider_id");



CREATE INDEX "contacts_parent_contact_id_idx" ON "public"."contacts" USING "btree" ("parent_contact_id");



CREATE INDEX "contacts_tenant_id_idx" ON "public"."contacts" USING "btree" ("tenant_id");



CREATE INDEX "custom_field_definitions_tenant_id_idx" ON "public"."custom_field_definitions" USING "btree" ("tenant_id");



CREATE INDEX "custom_field_values_claim_id_idx" ON "public"."custom_field_values" USING "btree" ("claim_id") WHERE ("claim_id" IS NOT NULL);



CREATE INDEX "custom_field_values_definition_id_idx" ON "public"."custom_field_values" USING "btree" ("definition_id");



CREATE INDEX "custom_field_values_project_id_idx" ON "public"."custom_field_values" USING "btree" ("project_id") WHERE ("project_id" IS NOT NULL);



CREATE INDEX "custom_field_values_tenant_id_idx" ON "public"."custom_field_values" USING "btree" ("tenant_id");



CREATE INDEX "custom_field_values_warranty_registration_id_idx" ON "public"."custom_field_values" USING "btree" ("warranty_registration_id") WHERE ("warranty_registration_id" IS NOT NULL);



CREATE INDEX "import_batches_tenant_id_idx" ON "public"."import_batches" USING "btree" ("tenant_id");



CREATE INDEX "inspection_triggers_tenant_id_idx" ON "public"."inspection_triggers" USING "btree" ("tenant_id");



CREATE INDEX "inspection_types_tenant_id_idx" ON "public"."inspection_types" USING "btree" ("tenant_id");



CREATE INDEX "inspections_claim_id_idx" ON "public"."inspections" USING "btree" ("claim_id");



CREATE INDEX "inspections_tenant_id_idx" ON "public"."inspections" USING "btree" ("tenant_id");



CREATE INDEX "internal_teams_tenant_id_idx" ON "public"."internal_teams" USING "btree" ("tenant_id");



CREATE INDEX "invitations_tenant_id_idx" ON "public"."invitations" USING "btree" ("tenant_id");



CREATE INDEX "invitations_token_idx" ON "public"."invitations" USING "btree" ("token");



CREATE INDEX "projects_customer_id_idx" ON "public"."projects" USING "btree" ("customer_id");



CREATE INDEX "projects_tenant_id_idx" ON "public"."projects" USING "btree" ("tenant_id");



CREATE INDEX "tenant_holidays_tenant_date_idx" ON "public"."tenant_holidays" USING "btree" ("tenant_id", "holiday_date");



CREATE INDEX "tenant_holidays_tenant_id_idx" ON "public"."tenant_holidays" USING "btree" ("tenant_id");



CREATE INDEX "users_tenant_id_idx" ON "public"."users" USING "btree" ("tenant_id");



CREATE UNIQUE INDEX "warranty_types_tenant_name_lower_unique" ON "public"."warranty_types" USING "btree" ("tenant_id", "lower"("name"));



CREATE INDEX "work_authorization_documents_claim_id_idx" ON "public"."work_authorization_documents" USING "btree" ("claim_id");



CREATE INDEX "work_authorization_documents_event_reference_idx" ON "public"."work_authorization_documents" USING "btree" ("event_type", "event_reference_id");



CREATE INDEX "work_authorization_documents_template_id_idx" ON "public"."work_authorization_documents" USING "btree" ("template_id");



CREATE INDEX "work_authorization_documents_tenant_id_idx" ON "public"."work_authorization_documents" USING "btree" ("tenant_id");



CREATE INDEX "work_authorization_revisions_document_id_idx" ON "public"."work_authorization_revisions" USING "btree" ("work_authorization_document_id");



CREATE INDEX "work_authorization_revisions_tenant_id_idx" ON "public"."work_authorization_revisions" USING "btree" ("tenant_id");



CREATE INDEX "work_authorization_templates_tenant_id_idx" ON "public"."work_authorization_templates" USING "btree" ("tenant_id");



CREATE INDEX "work_plans_claim_id_idx" ON "public"."work_plans" USING "btree" ("claim_id");



CREATE INDEX "work_plans_tenant_id_idx" ON "public"."work_plans" USING "btree" ("tenant_id");



CREATE OR REPLACE TRIGGER "tenants_set_updated_at" BEFORE UPDATE ON "public"."tenants" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "users_set_updated_at" BEFORE UPDATE ON "public"."users" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "warranty_types_protect_system" BEFORE DELETE OR UPDATE ON "public"."warranty_types" FOR EACH ROW EXECUTE FUNCTION "public"."protect_system_warranty_types"();



ALTER TABLE ONLY "public"."acknowledgment_gate_records"
    ADD CONSTRAINT "acknowledgment_gate_records_template_id_fkey" FOREIGN KEY ("template_id") REFERENCES "public"."acknowledgment_gate_templates"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."acknowledgment_gate_records"
    ADD CONSTRAINT "acknowledgment_gate_records_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id");



ALTER TABLE ONLY "public"."acknowledgment_gate_templates"
    ADD CONSTRAINT "acknowledgment_gate_templates_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id");



ALTER TABLE ONLY "public"."ala_document_revisions"
    ADD CONSTRAINT "ala_document_revisions_ala_document_id_fkey" FOREIGN KEY ("ala_document_id") REFERENCES "public"."ala_documents"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ala_document_revisions"
    ADD CONSTRAINT "ala_document_revisions_revised_by_user_id_fkey" FOREIGN KEY ("revised_by_user_id") REFERENCES "public"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."ala_document_revisions"
    ADD CONSTRAINT "ala_document_revisions_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id");



ALTER TABLE ONLY "public"."ala_documents"
    ADD CONSTRAINT "ala_documents_claim_id_fkey" FOREIGN KEY ("claim_id") REFERENCES "public"."claims"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."ala_documents"
    ADD CONSTRAINT "ala_documents_template_id_fkey" FOREIGN KEY ("template_id") REFERENCES "public"."ala_templates"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."ala_documents"
    ADD CONSTRAINT "ala_documents_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id");



ALTER TABLE ONLY "public"."ala_templates"
    ADD CONSTRAINT "ala_templates_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id");



ALTER TABLE ONLY "public"."claims"
    ADD CONSTRAINT "claims_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id");



ALTER TABLE ONLY "public"."claims"
    ADD CONSTRAINT "claims_warranty_registration_id_fkey" FOREIGN KEY ("warranty_registration_id") REFERENCES "public"."warranty_registrations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."clock_events"
    ADD CONSTRAINT "clock_events_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id");



ALTER TABLE ONLY "public"."contacts"
    ADD CONSTRAINT "contacts_imported_via_batch_id_fkey" FOREIGN KEY ("imported_via_batch_id") REFERENCES "public"."import_batches"("id");



ALTER TABLE ONLY "public"."contacts"
    ADD CONSTRAINT "contacts_linked_om_provider_id_fkey" FOREIGN KEY ("linked_om_provider_id") REFERENCES "public"."contacts"("id");



ALTER TABLE ONLY "public"."contacts"
    ADD CONSTRAINT "contacts_parent_contact_id_fkey" FOREIGN KEY ("parent_contact_id") REFERENCES "public"."contacts"("id");



ALTER TABLE ONLY "public"."contacts"
    ADD CONSTRAINT "contacts_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id");



ALTER TABLE ONLY "public"."custom_field_definitions"
    ADD CONSTRAINT "custom_field_definitions_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id");



ALTER TABLE ONLY "public"."custom_field_values"
    ADD CONSTRAINT "custom_field_values_claim_id_fkey" FOREIGN KEY ("claim_id") REFERENCES "public"."claims"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."custom_field_values"
    ADD CONSTRAINT "custom_field_values_definition_id_fkey" FOREIGN KEY ("definition_id") REFERENCES "public"."custom_field_definitions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."custom_field_values"
    ADD CONSTRAINT "custom_field_values_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."custom_field_values"
    ADD CONSTRAINT "custom_field_values_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id");



ALTER TABLE ONLY "public"."custom_field_values"
    ADD CONSTRAINT "custom_field_values_warranty_registration_id_fkey" FOREIGN KEY ("warranty_registration_id") REFERENCES "public"."warranty_registrations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."import_batches"
    ADD CONSTRAINT "import_batches_initiated_by_fkey" FOREIGN KEY ("initiated_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."import_batches"
    ADD CONSTRAINT "import_batches_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id");



ALTER TABLE ONLY "public"."inspection_triggers"
    ADD CONSTRAINT "inspection_triggers_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id");



ALTER TABLE ONLY "public"."inspection_types"
    ADD CONSTRAINT "inspection_types_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id");



ALTER TABLE ONLY "public"."inspections"
    ADD CONSTRAINT "inspections_claim_id_fkey" FOREIGN KEY ("claim_id") REFERENCES "public"."claims"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."inspections"
    ADD CONSTRAINT "inspections_inspection_trigger_id_fkey" FOREIGN KEY ("inspection_trigger_id") REFERENCES "public"."inspection_triggers"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."inspections"
    ADD CONSTRAINT "inspections_inspection_type_id_fkey" FOREIGN KEY ("inspection_type_id") REFERENCES "public"."inspection_types"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."inspections"
    ADD CONSTRAINT "inspections_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id");



ALTER TABLE ONLY "public"."internal_teams"
    ADD CONSTRAINT "internal_teams_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id");



ALTER TABLE ONLY "public"."invitations"
    ADD CONSTRAINT "invitations_invited_by_fkey" FOREIGN KEY ("invited_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."invitations"
    ADD CONSTRAINT "invitations_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."projects"
    ADD CONSTRAINT "projects_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."contacts"("id");



ALTER TABLE ONLY "public"."projects"
    ADD CONSTRAINT "projects_imported_via_batch_id_fkey" FOREIGN KEY ("imported_via_batch_id") REFERENCES "public"."import_batches"("id");



ALTER TABLE ONLY "public"."projects"
    ADD CONSTRAINT "projects_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id");



ALTER TABLE ONLY "public"."tenant_holidays"
    ADD CONSTRAINT "tenant_holidays_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id");



ALTER TABLE ONLY "public"."tenant_id_sequences"
    ADD CONSTRAINT "tenant_id_sequences_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."warranty_coverages"
    ADD CONSTRAINT "warranty_coverages_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id");



ALTER TABLE ONLY "public"."warranty_coverages"
    ADD CONSTRAINT "warranty_coverages_warranty_registration_id_fkey" FOREIGN KEY ("warranty_registration_id") REFERENCES "public"."warranty_registrations"("id");



ALTER TABLE ONLY "public"."warranty_coverages"
    ADD CONSTRAINT "warranty_coverages_warranty_type_id_fkey" FOREIGN KEY ("warranty_type_id") REFERENCES "public"."warranty_types"("id");



ALTER TABLE ONLY "public"."warranty_registrations"
    ADD CONSTRAINT "warranty_registrations_assigned_to_contact_id_fkey" FOREIGN KEY ("assigned_to_contact_id") REFERENCES "public"."contacts"("id");



ALTER TABLE ONLY "public"."warranty_registrations"
    ADD CONSTRAINT "warranty_registrations_assigned_to_user_id_fkey" FOREIGN KEY ("assigned_to_user_id") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."warranty_registrations"
    ADD CONSTRAINT "warranty_registrations_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."warranty_registrations"
    ADD CONSTRAINT "warranty_registrations_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id");



ALTER TABLE ONLY "public"."warranty_types"
    ADD CONSTRAINT "warranty_types_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id");



ALTER TABLE ONLY "public"."work_authorization_documents"
    ADD CONSTRAINT "work_authorization_documents_claim_id_fkey" FOREIGN KEY ("claim_id") REFERENCES "public"."claims"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."work_authorization_documents"
    ADD CONSTRAINT "work_authorization_documents_template_id_fkey" FOREIGN KEY ("template_id") REFERENCES "public"."work_authorization_templates"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."work_authorization_documents"
    ADD CONSTRAINT "work_authorization_documents_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id");



ALTER TABLE ONLY "public"."work_authorization_revisions"
    ADD CONSTRAINT "work_authorization_revisions_revised_by_user_id_fkey" FOREIGN KEY ("revised_by_user_id") REFERENCES "public"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."work_authorization_revisions"
    ADD CONSTRAINT "work_authorization_revisions_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id");



ALTER TABLE ONLY "public"."work_authorization_revisions"
    ADD CONSTRAINT "work_authorization_revisions_work_authorization_document_i_fkey" FOREIGN KEY ("work_authorization_document_id") REFERENCES "public"."work_authorization_documents"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."work_authorization_templates"
    ADD CONSTRAINT "work_authorization_templates_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id");



ALTER TABLE ONLY "public"."work_plans"
    ADD CONSTRAINT "work_plans_claim_id_fkey" FOREIGN KEY ("claim_id") REFERENCES "public"."claims"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."work_plans"
    ADD CONSTRAINT "work_plans_internal_team_id_fkey" FOREIGN KEY ("internal_team_id") REFERENCES "public"."internal_teams"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."work_plans"
    ADD CONSTRAINT "work_plans_subcontractor_contact_id_fkey" FOREIGN KEY ("subcontractor_contact_id") REFERENCES "public"."contacts"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."work_plans"
    ADD CONSTRAINT "work_plans_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id");



ALTER TABLE ONLY "public"."work_plans"
    ADD CONSTRAINT "work_plans_warranty_professional_user_id_fkey" FOREIGN KEY ("warranty_professional_user_id") REFERENCES "public"."users"("id") ON DELETE RESTRICT;



ALTER TABLE "public"."acknowledgment_gate_records" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "acknowledgment_gate_records: tenant read" ON "public"."acknowledgment_gate_records" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));



ALTER TABLE "public"."acknowledgment_gate_templates" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "acknowledgment_gate_templates: tenant read" ON "public"."acknowledgment_gate_templates" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));



ALTER TABLE "public"."ala_document_revisions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "ala_document_revisions: tenant read" ON "public"."ala_document_revisions" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));



ALTER TABLE "public"."ala_documents" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "ala_documents: tenant read" ON "public"."ala_documents" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));



ALTER TABLE "public"."ala_templates" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "ala_templates: tenant read" ON "public"."ala_templates" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));



ALTER TABLE "public"."claims" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "claims: members can view their tenant's rows" ON "public"."claims" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));



ALTER TABLE "public"."clock_events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "clock_events: members can view their tenant's rows" ON "public"."clock_events" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));



ALTER TABLE "public"."contacts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "contacts: members can view their tenant's rows" ON "public"."contacts" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));



ALTER TABLE "public"."custom_field_definitions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "custom_field_definitions: members can view their tenant's rows" ON "public"."custom_field_definitions" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));



ALTER TABLE "public"."custom_field_values" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "custom_field_values: members can view their tenant's rows" ON "public"."custom_field_values" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));



ALTER TABLE "public"."import_batches" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "import_batches: members can view their tenant's rows" ON "public"."import_batches" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));



ALTER TABLE "public"."inspection_triggers" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "inspection_triggers: members can view their tenant's rows" ON "public"."inspection_triggers" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));



ALTER TABLE "public"."inspection_types" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "inspection_types: members can view their tenant's rows" ON "public"."inspection_types" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));



ALTER TABLE "public"."inspections" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "inspections: members can view their tenant's rows" ON "public"."inspections" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));



ALTER TABLE "public"."internal_teams" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "internal_teams: members can view their tenant's rows" ON "public"."internal_teams" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));



ALTER TABLE "public"."invitations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "invitations: members can view their tenant's invitations" ON "public"."invitations" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));



ALTER TABLE "public"."projects" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "projects: members can view their tenant's rows" ON "public"."projects" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));



ALTER TABLE "public"."tenant_holidays" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "tenant_holidays: tenant read" ON "public"."tenant_holidays" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));



ALTER TABLE "public"."tenant_id_sequences" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "tenant_id_sequences: members can view their tenant's rows" ON "public"."tenant_id_sequences" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));



ALTER TABLE "public"."tenants" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "tenants: members can view their own tenant" ON "public"."tenants" FOR SELECT USING (("id" = "public"."get_user_tenant_id"()));



ALTER TABLE "public"."users" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "users: authenticated can read their own profile" ON "public"."users" FOR SELECT USING (("id" = "auth"."uid"()));



CREATE POLICY "users: members can update their own profile" ON "public"."users" FOR UPDATE USING (("id" = "auth"."uid"())) WITH CHECK (("id" = "auth"."uid"()));



CREATE POLICY "users: members can view users in their tenant" ON "public"."users" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));



ALTER TABLE "public"."warranty_coverages" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "warranty_coverages: members can view their tenant's rows" ON "public"."warranty_coverages" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));



ALTER TABLE "public"."warranty_registrations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "warranty_registrations: members can view their tenant's rows" ON "public"."warranty_registrations" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));



ALTER TABLE "public"."warranty_types" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "warranty_types: members can view their tenant's rows" ON "public"."warranty_types" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));



ALTER TABLE "public"."work_authorization_documents" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "work_authorization_documents: tenant read" ON "public"."work_authorization_documents" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));



ALTER TABLE "public"."work_authorization_revisions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "work_authorization_revisions: tenant read" ON "public"."work_authorization_revisions" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));



ALTER TABLE "public"."work_authorization_templates" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "work_authorization_templates: tenant read" ON "public"."work_authorization_templates" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));



ALTER TABLE "public"."work_plans" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "work_plans: members can view their tenant's rows" ON "public"."work_plans" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));





ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";





GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";




























































































































































GRANT ALL ON FUNCTION "public"."get_user_tenant_id"() TO "authenticated";


















GRANT ALL ON TABLE "public"."acknowledgment_gate_records" TO "anon";
GRANT ALL ON TABLE "public"."acknowledgment_gate_records" TO "authenticated";
GRANT ALL ON TABLE "public"."acknowledgment_gate_records" TO "service_role";



GRANT ALL ON TABLE "public"."acknowledgment_gate_templates" TO "anon";
GRANT ALL ON TABLE "public"."acknowledgment_gate_templates" TO "authenticated";
GRANT ALL ON TABLE "public"."acknowledgment_gate_templates" TO "service_role";



GRANT ALL ON TABLE "public"."ala_document_revisions" TO "anon";
GRANT ALL ON TABLE "public"."ala_document_revisions" TO "authenticated";
GRANT ALL ON TABLE "public"."ala_document_revisions" TO "service_role";



GRANT ALL ON TABLE "public"."ala_documents" TO "anon";
GRANT ALL ON TABLE "public"."ala_documents" TO "authenticated";
GRANT ALL ON TABLE "public"."ala_documents" TO "service_role";



GRANT ALL ON TABLE "public"."ala_templates" TO "anon";
GRANT ALL ON TABLE "public"."ala_templates" TO "authenticated";
GRANT ALL ON TABLE "public"."ala_templates" TO "service_role";



GRANT ALL ON TABLE "public"."claims" TO "anon";
GRANT ALL ON TABLE "public"."claims" TO "authenticated";
GRANT ALL ON TABLE "public"."claims" TO "service_role";



GRANT ALL ON TABLE "public"."clock_events" TO "anon";
GRANT ALL ON TABLE "public"."clock_events" TO "authenticated";
GRANT ALL ON TABLE "public"."clock_events" TO "service_role";



GRANT ALL ON TABLE "public"."contacts" TO "anon";
GRANT ALL ON TABLE "public"."contacts" TO "authenticated";
GRANT ALL ON TABLE "public"."contacts" TO "service_role";



GRANT ALL ON TABLE "public"."custom_field_definitions" TO "anon";
GRANT ALL ON TABLE "public"."custom_field_definitions" TO "authenticated";
GRANT ALL ON TABLE "public"."custom_field_definitions" TO "service_role";



GRANT ALL ON TABLE "public"."custom_field_values" TO "anon";
GRANT ALL ON TABLE "public"."custom_field_values" TO "authenticated";
GRANT ALL ON TABLE "public"."custom_field_values" TO "service_role";



GRANT ALL ON TABLE "public"."import_batches" TO "anon";
GRANT ALL ON TABLE "public"."import_batches" TO "authenticated";
GRANT ALL ON TABLE "public"."import_batches" TO "service_role";



GRANT ALL ON TABLE "public"."inspection_triggers" TO "anon";
GRANT ALL ON TABLE "public"."inspection_triggers" TO "authenticated";
GRANT ALL ON TABLE "public"."inspection_triggers" TO "service_role";



GRANT ALL ON TABLE "public"."inspection_types" TO "anon";
GRANT ALL ON TABLE "public"."inspection_types" TO "authenticated";
GRANT ALL ON TABLE "public"."inspection_types" TO "service_role";



GRANT ALL ON TABLE "public"."inspections" TO "anon";
GRANT ALL ON TABLE "public"."inspections" TO "authenticated";
GRANT ALL ON TABLE "public"."inspections" TO "service_role";



GRANT ALL ON TABLE "public"."internal_teams" TO "anon";
GRANT ALL ON TABLE "public"."internal_teams" TO "authenticated";
GRANT ALL ON TABLE "public"."internal_teams" TO "service_role";



GRANT ALL ON TABLE "public"."invitations" TO "anon";
GRANT ALL ON TABLE "public"."invitations" TO "authenticated";
GRANT ALL ON TABLE "public"."invitations" TO "service_role";



GRANT ALL ON TABLE "public"."projects" TO "anon";
GRANT ALL ON TABLE "public"."projects" TO "authenticated";
GRANT ALL ON TABLE "public"."projects" TO "service_role";



GRANT ALL ON TABLE "public"."tenant_holidays" TO "anon";
GRANT ALL ON TABLE "public"."tenant_holidays" TO "authenticated";
GRANT ALL ON TABLE "public"."tenant_holidays" TO "service_role";



GRANT ALL ON TABLE "public"."tenant_id_sequences" TO "anon";
GRANT ALL ON TABLE "public"."tenant_id_sequences" TO "authenticated";
GRANT ALL ON TABLE "public"."tenant_id_sequences" TO "service_role";



GRANT ALL ON TABLE "public"."tenants" TO "anon";
GRANT ALL ON TABLE "public"."tenants" TO "authenticated";
GRANT ALL ON TABLE "public"."tenants" TO "service_role";



GRANT ALL ON TABLE "public"."users" TO "anon";
GRANT ALL ON TABLE "public"."users" TO "authenticated";
GRANT ALL ON TABLE "public"."users" TO "service_role";



GRANT ALL ON TABLE "public"."warranty_coverages" TO "anon";
GRANT ALL ON TABLE "public"."warranty_coverages" TO "authenticated";
GRANT ALL ON TABLE "public"."warranty_coverages" TO "service_role";



GRANT ALL ON TABLE "public"."warranty_registrations" TO "anon";
GRANT ALL ON TABLE "public"."warranty_registrations" TO "authenticated";
GRANT ALL ON TABLE "public"."warranty_registrations" TO "service_role";



GRANT ALL ON TABLE "public"."warranty_coverages_effective" TO "anon";
GRANT ALL ON TABLE "public"."warranty_coverages_effective" TO "authenticated";
GRANT ALL ON TABLE "public"."warranty_coverages_effective" TO "service_role";



GRANT ALL ON TABLE "public"."warranty_types" TO "anon";
GRANT ALL ON TABLE "public"."warranty_types" TO "authenticated";
GRANT ALL ON TABLE "public"."warranty_types" TO "service_role";



GRANT ALL ON TABLE "public"."work_authorization_documents" TO "anon";
GRANT ALL ON TABLE "public"."work_authorization_documents" TO "authenticated";
GRANT ALL ON TABLE "public"."work_authorization_documents" TO "service_role";



GRANT ALL ON TABLE "public"."work_authorization_revisions" TO "anon";
GRANT ALL ON TABLE "public"."work_authorization_revisions" TO "authenticated";
GRANT ALL ON TABLE "public"."work_authorization_revisions" TO "service_role";



GRANT ALL ON TABLE "public"."work_authorization_templates" TO "anon";
GRANT ALL ON TABLE "public"."work_authorization_templates" TO "authenticated";
GRANT ALL ON TABLE "public"."work_authorization_templates" TO "service_role";



GRANT ALL ON TABLE "public"."work_plans" TO "anon";
GRANT ALL ON TABLE "public"."work_plans" TO "authenticated";
GRANT ALL ON TABLE "public"."work_plans" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT UPDATE ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT UPDATE ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT UPDATE ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLES TO "service_role";































