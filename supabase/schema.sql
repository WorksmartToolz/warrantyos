


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



ALTER TABLE ONLY "public"."claims"
    ADD CONSTRAINT "claims_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."clock_events"
    ADD CONSTRAINT "clock_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."contacts"
    ADD CONSTRAINT "contacts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."custom_field_definitions"
    ADD CONSTRAINT "custom_field_definitions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."import_batches"
    ADD CONSTRAINT "import_batches_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."internal_teams"
    ADD CONSTRAINT "internal_teams_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."invitations"
    ADD CONSTRAINT "invitations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."invitations"
    ADD CONSTRAINT "invitations_token_key" UNIQUE ("token");



ALTER TABLE ONLY "public"."projects"
    ADD CONSTRAINT "projects_pkey" PRIMARY KEY ("id");



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



CREATE INDEX "claims_tenant_id_idx" ON "public"."claims" USING "btree" ("tenant_id");



CREATE INDEX "claims_warranty_registration_id_idx" ON "public"."claims" USING "btree" ("warranty_registration_id");



CREATE INDEX "clock_events_entity_idx" ON "public"."clock_events" USING "btree" ("entity_type", "entity_id");



CREATE INDEX "clock_events_pending_fires_at_idx" ON "public"."clock_events" USING "btree" ("fires_at") WHERE ("status" = 'pending'::"text");



CREATE INDEX "clock_events_tenant_idx" ON "public"."clock_events" USING "btree" ("tenant_id");



CREATE INDEX "contacts_linked_om_provider_id_idx" ON "public"."contacts" USING "btree" ("linked_om_provider_id");



CREATE INDEX "contacts_parent_contact_id_idx" ON "public"."contacts" USING "btree" ("parent_contact_id");



CREATE INDEX "contacts_tenant_id_idx" ON "public"."contacts" USING "btree" ("tenant_id");



CREATE INDEX "custom_field_definitions_tenant_id_idx" ON "public"."custom_field_definitions" USING "btree" ("tenant_id");



CREATE INDEX "import_batches_tenant_id_idx" ON "public"."import_batches" USING "btree" ("tenant_id");



CREATE INDEX "internal_teams_tenant_id_idx" ON "public"."internal_teams" USING "btree" ("tenant_id");



CREATE INDEX "invitations_tenant_id_idx" ON "public"."invitations" USING "btree" ("tenant_id");



CREATE INDEX "invitations_token_idx" ON "public"."invitations" USING "btree" ("token");



CREATE INDEX "projects_customer_id_idx" ON "public"."projects" USING "btree" ("customer_id");



CREATE INDEX "projects_tenant_id_idx" ON "public"."projects" USING "btree" ("tenant_id");



CREATE INDEX "users_tenant_id_idx" ON "public"."users" USING "btree" ("tenant_id");



CREATE UNIQUE INDEX "warranty_types_tenant_name_lower_unique" ON "public"."warranty_types" USING "btree" ("tenant_id", "lower"("name"));



CREATE OR REPLACE TRIGGER "tenants_set_updated_at" BEFORE UPDATE ON "public"."tenants" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "users_set_updated_at" BEFORE UPDATE ON "public"."users" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "warranty_types_protect_system" BEFORE DELETE OR UPDATE ON "public"."warranty_types" FOR EACH ROW EXECUTE FUNCTION "public"."protect_system_warranty_types"();



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



ALTER TABLE ONLY "public"."import_batches"
    ADD CONSTRAINT "import_batches_initiated_by_fkey" FOREIGN KEY ("initiated_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."import_batches"
    ADD CONSTRAINT "import_batches_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id");



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



ALTER TABLE "public"."claims" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "claims: members can view their tenant's rows" ON "public"."claims" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));



ALTER TABLE "public"."clock_events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "clock_events: members can view their tenant's rows" ON "public"."clock_events" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));



ALTER TABLE "public"."contacts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "contacts: members can view their tenant's rows" ON "public"."contacts" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));



ALTER TABLE "public"."custom_field_definitions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "custom_field_definitions: members can view their tenant's rows" ON "public"."custom_field_definitions" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));



ALTER TABLE "public"."import_batches" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "import_batches: members can view their tenant's rows" ON "public"."import_batches" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));



ALTER TABLE "public"."internal_teams" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "internal_teams: members can view their tenant's rows" ON "public"."internal_teams" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));



ALTER TABLE "public"."invitations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "invitations: members can view their tenant's invitations" ON "public"."invitations" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));



ALTER TABLE "public"."projects" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "projects: members can view their tenant's rows" ON "public"."projects" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));



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





ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";





GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";




























































































































































GRANT ALL ON FUNCTION "public"."get_user_tenant_id"() TO "authenticated";


















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



GRANT ALL ON TABLE "public"."import_batches" TO "anon";
GRANT ALL ON TABLE "public"."import_batches" TO "authenticated";
GRANT ALL ON TABLE "public"."import_batches" TO "service_role";



GRANT ALL ON TABLE "public"."internal_teams" TO "anon";
GRANT ALL ON TABLE "public"."internal_teams" TO "authenticated";
GRANT ALL ON TABLE "public"."internal_teams" TO "service_role";



GRANT ALL ON TABLE "public"."invitations" TO "anon";
GRANT ALL ON TABLE "public"."invitations" TO "authenticated";
GRANT ALL ON TABLE "public"."invitations" TO "service_role";



GRANT ALL ON TABLE "public"."projects" TO "anon";
GRANT ALL ON TABLE "public"."projects" TO "authenticated";
GRANT ALL ON TABLE "public"."projects" TO "service_role";



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









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT UPDATE ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT UPDATE ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT UPDATE ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLES TO "service_role";































