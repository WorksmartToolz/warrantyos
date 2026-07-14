


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



ALTER TABLE ONLY "public"."contacts"
    ADD CONSTRAINT "contacts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."import_batches"
    ADD CONSTRAINT "import_batches_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."invitations"
    ADD CONSTRAINT "invitations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."invitations"
    ADD CONSTRAINT "invitations_token_key" UNIQUE ("token");



ALTER TABLE ONLY "public"."projects"
    ADD CONSTRAINT "projects_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."tenants"
    ADD CONSTRAINT "tenants_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."tenants"
    ADD CONSTRAINT "tenants_slug_key" UNIQUE ("slug");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");



CREATE INDEX "contacts_linked_om_provider_id_idx" ON "public"."contacts" USING "btree" ("linked_om_provider_id");



CREATE INDEX "contacts_parent_contact_id_idx" ON "public"."contacts" USING "btree" ("parent_contact_id");



CREATE INDEX "contacts_tenant_id_idx" ON "public"."contacts" USING "btree" ("tenant_id");



CREATE INDEX "import_batches_tenant_id_idx" ON "public"."import_batches" USING "btree" ("tenant_id");



CREATE INDEX "invitations_tenant_id_idx" ON "public"."invitations" USING "btree" ("tenant_id");



CREATE INDEX "invitations_token_idx" ON "public"."invitations" USING "btree" ("token");



CREATE INDEX "projects_customer_id_idx" ON "public"."projects" USING "btree" ("customer_id");



CREATE INDEX "projects_tenant_id_idx" ON "public"."projects" USING "btree" ("tenant_id");



CREATE INDEX "users_tenant_id_idx" ON "public"."users" USING "btree" ("tenant_id");



CREATE OR REPLACE TRIGGER "tenants_set_updated_at" BEFORE UPDATE ON "public"."tenants" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "users_set_updated_at" BEFORE UPDATE ON "public"."users" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



ALTER TABLE ONLY "public"."contacts"
    ADD CONSTRAINT "contacts_imported_via_batch_id_fkey" FOREIGN KEY ("imported_via_batch_id") REFERENCES "public"."import_batches"("id");



ALTER TABLE ONLY "public"."contacts"
    ADD CONSTRAINT "contacts_linked_om_provider_id_fkey" FOREIGN KEY ("linked_om_provider_id") REFERENCES "public"."contacts"("id");



ALTER TABLE ONLY "public"."contacts"
    ADD CONSTRAINT "contacts_parent_contact_id_fkey" FOREIGN KEY ("parent_contact_id") REFERENCES "public"."contacts"("id");



ALTER TABLE ONLY "public"."contacts"
    ADD CONSTRAINT "contacts_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id");



ALTER TABLE ONLY "public"."import_batches"
    ADD CONSTRAINT "import_batches_initiated_by_fkey" FOREIGN KEY ("initiated_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."import_batches"
    ADD CONSTRAINT "import_batches_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id");



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



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE RESTRICT;



ALTER TABLE "public"."contacts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "contacts: members can view their tenant's rows" ON "public"."contacts" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));



ALTER TABLE "public"."import_batches" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "import_batches: members can view their tenant's rows" ON "public"."import_batches" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));



ALTER TABLE "public"."invitations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "invitations: members can view their tenant's invitations" ON "public"."invitations" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));



ALTER TABLE "public"."projects" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "projects: members can view their tenant's rows" ON "public"."projects" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));



ALTER TABLE "public"."tenants" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "tenants: members can view their own tenant" ON "public"."tenants" FOR SELECT USING (("id" = "public"."get_user_tenant_id"()));



ALTER TABLE "public"."users" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "users: authenticated can read their own profile" ON "public"."users" FOR SELECT USING (("id" = "auth"."uid"()));



CREATE POLICY "users: members can update their own profile" ON "public"."users" FOR UPDATE USING (("id" = "auth"."uid"())) WITH CHECK (("id" = "auth"."uid"()));



CREATE POLICY "users: members can view users in their tenant" ON "public"."users" FOR SELECT USING (("tenant_id" = "public"."get_user_tenant_id"()));





ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";





GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";




























































































































































GRANT ALL ON FUNCTION "public"."get_user_tenant_id"() TO "authenticated";


















GRANT ALL ON TABLE "public"."contacts" TO "anon";
GRANT ALL ON TABLE "public"."contacts" TO "authenticated";
GRANT ALL ON TABLE "public"."contacts" TO "service_role";



GRANT ALL ON TABLE "public"."import_batches" TO "anon";
GRANT ALL ON TABLE "public"."import_batches" TO "authenticated";
GRANT ALL ON TABLE "public"."import_batches" TO "service_role";



GRANT ALL ON TABLE "public"."invitations" TO "anon";
GRANT ALL ON TABLE "public"."invitations" TO "authenticated";
GRANT ALL ON TABLE "public"."invitations" TO "service_role";



GRANT ALL ON TABLE "public"."projects" TO "anon";
GRANT ALL ON TABLE "public"."projects" TO "authenticated";
GRANT ALL ON TABLE "public"."projects" TO "service_role";



GRANT ALL ON TABLE "public"."tenants" TO "anon";
GRANT ALL ON TABLE "public"."tenants" TO "authenticated";
GRANT ALL ON TABLE "public"."tenants" TO "service_role";



GRANT ALL ON TABLE "public"."users" TO "anon";
GRANT ALL ON TABLE "public"."users" TO "authenticated";
GRANT ALL ON TABLE "public"."users" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT UPDATE ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT UPDATE ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT UPDATE ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLES TO "service_role";































