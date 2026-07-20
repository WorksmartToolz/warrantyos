export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      acknowledgment_gate_records: {
        Row: {
          acknowledged_at: string
          acknowledger_ip: string | null
          acknowledger_name: string | null
          authorized_entity_id: string
          authorized_entity_type: string
          created_at: string
          id: string
          template_content_snapshot: Json
          template_id: string
          tenant_id: string
        }
        Insert: {
          acknowledged_at: string
          acknowledger_ip?: string | null
          acknowledger_name?: string | null
          authorized_entity_id: string
          authorized_entity_type: string
          created_at?: string
          id?: string
          template_content_snapshot: Json
          template_id: string
          tenant_id: string
        }
        Update: {
          acknowledged_at?: string
          acknowledger_ip?: string | null
          acknowledger_name?: string | null
          authorized_entity_id?: string
          authorized_entity_type?: string
          created_at?: string
          id?: string
          template_content_snapshot?: Json
          template_id?: string
          tenant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "acknowledgment_gate_records_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "acknowledgment_gate_templates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "acknowledgment_gate_records_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      acknowledgment_gate_templates: {
        Row: {
          acknowledgment_label: string
          content: Json
          created_at: string
          deleted_at: string | null
          gate_purpose: string
          id: string
          is_default: boolean
          name: string
          requires_typed_name: boolean
          tenant_id: string
          updated_at: string
        }
        Insert: {
          acknowledgment_label: string
          content: Json
          created_at?: string
          deleted_at?: string | null
          gate_purpose: string
          id?: string
          is_default?: boolean
          name: string
          requires_typed_name?: boolean
          tenant_id: string
          updated_at?: string
        }
        Update: {
          acknowledgment_label?: string
          content?: Json
          created_at?: string
          deleted_at?: string | null
          gate_purpose?: string
          id?: string
          is_default?: boolean
          name?: string
          requires_typed_name?: boolean
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "acknowledgment_gate_templates_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      ala_document_revisions: {
        Row: {
          ala_document_id: string
          field_changes: Json
          id: string
          revised_at: string
          revised_by_user_id: string
          revision_reason: Json
          tenant_id: string
        }
        Insert: {
          ala_document_id: string
          field_changes: Json
          id?: string
          revised_at?: string
          revised_by_user_id: string
          revision_reason: Json
          tenant_id: string
        }
        Update: {
          ala_document_id?: string
          field_changes?: Json
          id?: string
          revised_at?: string
          revised_by_user_id?: string
          revision_reason?: Json
          tenant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ala_document_revisions_ala_document_id_fkey"
            columns: ["ala_document_id"]
            isOneToOne: false
            referencedRelation: "ala_documents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ala_document_revisions_revised_by_user_id_fkey"
            columns: ["revised_by_user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ala_document_revisions_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      ala_documents: {
        Row: {
          claim_id: string
          claimant_decision: string | null
          claimant_token: string | null
          claimant_token_expires_at: string | null
          content_snapshot: Json
          created_at: string
          decided_at: string | null
          decline_reason: string | null
          esignature_envelope_id: string | null
          id: string
          markup_percent_snapshot: number
          overdue_flagged_at: string | null
          signature_image_url: string | null
          signature_method: string
          signed_at: string | null
          signer_email: string | null
          signer_name: string | null
          template_id: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          claim_id: string
          claimant_decision?: string | null
          claimant_token?: string | null
          claimant_token_expires_at?: string | null
          content_snapshot: Json
          created_at?: string
          decided_at?: string | null
          decline_reason?: string | null
          esignature_envelope_id?: string | null
          id?: string
          markup_percent_snapshot: number
          overdue_flagged_at?: string | null
          signature_image_url?: string | null
          signature_method?: string
          signed_at?: string | null
          signer_email?: string | null
          signer_name?: string | null
          template_id: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          claim_id?: string
          claimant_decision?: string | null
          claimant_token?: string | null
          claimant_token_expires_at?: string | null
          content_snapshot?: Json
          created_at?: string
          decided_at?: string | null
          decline_reason?: string | null
          esignature_envelope_id?: string | null
          id?: string
          markup_percent_snapshot?: number
          overdue_flagged_at?: string | null
          signature_image_url?: string | null
          signature_method?: string
          signed_at?: string | null
          signer_email?: string | null
          signer_name?: string | null
          template_id?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "ala_documents_claim_id_fkey"
            columns: ["claim_id"]
            isOneToOne: true
            referencedRelation: "claims"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ala_documents_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "ala_templates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ala_documents_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      ala_templates: {
        Row: {
          content: Json
          created_at: string
          deleted_at: string | null
          id: string
          is_default: boolean
          name: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          content: Json
          created_at?: string
          deleted_at?: string | null
          id?: string
          is_default?: boolean
          name: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          content?: Json
          created_at?: string
          deleted_at?: string | null
          id?: string
          is_default?: boolean
          name?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "ala_templates_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      claims: {
        Row: {
          claim_id: string
          claim_type: string
          claim_type_data: Json | null
          created_at: string
          date_of_defect_incident: string
          detailed_description: Json
          emergency_details: Json | null
          emergency_stabilized_at: string | null
          equipment_status: string
          id: string
          intake_token: string | null
          intake_token_expires_at: string | null
          is_emergency: boolean
          loto_requirement: string
          offline_condition_explanation: Json | null
          om_contact_email: string | null
          om_contact_name: string | null
          om_contact_phone: string | null
          om_provider_company: string | null
          recipient_name: string | null
          recipient_phone: string | null
          required_docs_provided: boolean
          ship_to_city: string | null
          ship_to_state: string | null
          ship_to_street: string | null
          ship_to_zip: string | null
          status: string
          submitter_contact_id: string | null
          submitter_email: string
          submitter_name: string
          supporting_documents: Json | null
          tenant_id: string
          updated_at: string
          warranty_registration_id: string
        }
        Insert: {
          claim_id: string
          claim_type: string
          claim_type_data?: Json | null
          created_at?: string
          date_of_defect_incident: string
          detailed_description: Json
          emergency_details?: Json | null
          emergency_stabilized_at?: string | null
          equipment_status: string
          id?: string
          intake_token?: string | null
          intake_token_expires_at?: string | null
          is_emergency?: boolean
          loto_requirement: string
          offline_condition_explanation?: Json | null
          om_contact_email?: string | null
          om_contact_name?: string | null
          om_contact_phone?: string | null
          om_provider_company?: string | null
          recipient_name?: string | null
          recipient_phone?: string | null
          required_docs_provided?: boolean
          ship_to_city?: string | null
          ship_to_state?: string | null
          ship_to_street?: string | null
          ship_to_zip?: string | null
          status?: string
          submitter_contact_id?: string | null
          submitter_email: string
          submitter_name: string
          supporting_documents?: Json | null
          tenant_id: string
          updated_at?: string
          warranty_registration_id: string
        }
        Update: {
          claim_id?: string
          claim_type?: string
          claim_type_data?: Json | null
          created_at?: string
          date_of_defect_incident?: string
          detailed_description?: Json
          emergency_details?: Json | null
          emergency_stabilized_at?: string | null
          equipment_status?: string
          id?: string
          intake_token?: string | null
          intake_token_expires_at?: string | null
          is_emergency?: boolean
          loto_requirement?: string
          offline_condition_explanation?: Json | null
          om_contact_email?: string | null
          om_contact_name?: string | null
          om_contact_phone?: string | null
          om_provider_company?: string | null
          recipient_name?: string | null
          recipient_phone?: string | null
          required_docs_provided?: boolean
          ship_to_city?: string | null
          ship_to_state?: string | null
          ship_to_street?: string | null
          ship_to_zip?: string | null
          status?: string
          submitter_contact_id?: string | null
          submitter_email?: string
          submitter_name?: string
          supporting_documents?: Json | null
          tenant_id?: string
          updated_at?: string
          warranty_registration_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "claims_submitter_contact_id_fkey"
            columns: ["submitter_contact_id"]
            isOneToOne: false
            referencedRelation: "contacts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "claims_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "claims_warranty_registration_id_fkey"
            columns: ["warranty_registration_id"]
            isOneToOne: false
            referencedRelation: "warranty_registrations"
            referencedColumns: ["id"]
          },
        ]
      }
      clock_events: {
        Row: {
          created_at: string
          entity_id: string
          entity_type: string
          event_type: string
          failure_reason: string | null
          fired_at: string | null
          fires_at: string
          id: string
          payload: Json | null
          status: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          entity_id: string
          entity_type: string
          event_type: string
          failure_reason?: string | null
          fired_at?: string | null
          fires_at: string
          id?: string
          payload?: Json | null
          status?: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          entity_id?: string
          entity_type?: string
          event_type?: string
          failure_reason?: string | null
          fired_at?: string | null
          fires_at?: string
          id?: string
          payload?: Json | null
          status?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "clock_events_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      contacts: {
        Row: {
          contact_type: string
          created_at: string
          deleted_at: string | null
          email: string | null
          id: string
          imported_via_batch_id: string | null
          linked_om_provider_id: string | null
          name: string
          parent_contact_id: string | null
          phone: string | null
          tenant_id: string
          updated_at: string
        }
        Insert: {
          contact_type: string
          created_at?: string
          deleted_at?: string | null
          email?: string | null
          id?: string
          imported_via_batch_id?: string | null
          linked_om_provider_id?: string | null
          name: string
          parent_contact_id?: string | null
          phone?: string | null
          tenant_id: string
          updated_at?: string
        }
        Update: {
          contact_type?: string
          created_at?: string
          deleted_at?: string | null
          email?: string | null
          id?: string
          imported_via_batch_id?: string | null
          linked_om_provider_id?: string | null
          name?: string
          parent_contact_id?: string | null
          phone?: string | null
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "contacts_imported_via_batch_id_fkey"
            columns: ["imported_via_batch_id"]
            isOneToOne: false
            referencedRelation: "import_batches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contacts_linked_om_provider_id_fkey"
            columns: ["linked_om_provider_id"]
            isOneToOne: false
            referencedRelation: "contacts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contacts_parent_contact_id_fkey"
            columns: ["parent_contact_id"]
            isOneToOne: false
            referencedRelation: "contacts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contacts_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      custom_field_definitions: {
        Row: {
          created_at: string
          deleted_at: string | null
          display_order: number
          entity_type: string
          field_type: string
          id: string
          label: string
          options: Json | null
          required: boolean
          tenant_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          deleted_at?: string | null
          display_order?: number
          entity_type: string
          field_type: string
          id?: string
          label: string
          options?: Json | null
          required?: boolean
          tenant_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          deleted_at?: string | null
          display_order?: number
          entity_type?: string
          field_type?: string
          id?: string
          label?: string
          options?: Json | null
          required?: boolean
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "custom_field_definitions_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      custom_field_values: {
        Row: {
          claim_id: string | null
          created_at: string
          definition_id: string
          id: string
          project_id: string | null
          tenant_id: string
          updated_at: string
          value: Json | null
          warranty_registration_id: string | null
        }
        Insert: {
          claim_id?: string | null
          created_at?: string
          definition_id: string
          id?: string
          project_id?: string | null
          tenant_id: string
          updated_at?: string
          value?: Json | null
          warranty_registration_id?: string | null
        }
        Update: {
          claim_id?: string | null
          created_at?: string
          definition_id?: string
          id?: string
          project_id?: string | null
          tenant_id?: string
          updated_at?: string
          value?: Json | null
          warranty_registration_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "custom_field_values_claim_id_fkey"
            columns: ["claim_id"]
            isOneToOne: false
            referencedRelation: "claims"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "custom_field_values_definition_id_fkey"
            columns: ["definition_id"]
            isOneToOne: false
            referencedRelation: "custom_field_definitions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "custom_field_values_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "custom_field_values_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "custom_field_values_warranty_registration_id_fkey"
            columns: ["warranty_registration_id"]
            isOneToOne: false
            referencedRelation: "warranty_registrations"
            referencedColumns: ["id"]
          },
        ]
      }
      import_batches: {
        Row: {
          created_at: string
          customer_count: number | null
          id: string
          initiated_by: string | null
          project_count: number | null
          source_filename: string | null
          status: string
          tenant_id: string
        }
        Insert: {
          created_at?: string
          customer_count?: number | null
          id?: string
          initiated_by?: string | null
          project_count?: number | null
          source_filename?: string | null
          status?: string
          tenant_id: string
        }
        Update: {
          created_at?: string
          customer_count?: number | null
          id?: string
          initiated_by?: string | null
          project_count?: number | null
          source_filename?: string | null
          status?: string
          tenant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "import_batches_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      inspection_triggers: {
        Row: {
          created_at: string
          deleted_at: string | null
          disabled_at: string | null
          id: string
          label: string
          lock_tier: string
          sort_order: number
          tenant_id: string
          updated_at: string
          value: string
        }
        Insert: {
          created_at?: string
          deleted_at?: string | null
          disabled_at?: string | null
          id?: string
          label: string
          lock_tier: string
          sort_order?: number
          tenant_id: string
          updated_at?: string
          value: string
        }
        Update: {
          created_at?: string
          deleted_at?: string | null
          disabled_at?: string | null
          id?: string
          label?: string
          lock_tier?: string
          sort_order?: number
          tenant_id?: string
          updated_at?: string
          value?: string
        }
        Relationships: [
          {
            foreignKeyName: "inspection_triggers_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      inspection_types: {
        Row: {
          created_at: string
          deleted_at: string | null
          disabled_at: string | null
          id: string
          label: string
          lock_tier: string
          sort_order: number
          tenant_id: string
          updated_at: string
          value: string
        }
        Insert: {
          created_at?: string
          deleted_at?: string | null
          disabled_at?: string | null
          id?: string
          label: string
          lock_tier: string
          sort_order?: number
          tenant_id: string
          updated_at?: string
          value: string
        }
        Update: {
          created_at?: string
          deleted_at?: string | null
          disabled_at?: string | null
          id?: string
          label?: string
          lock_tier?: string
          sort_order?: number
          tenant_id?: string
          updated_at?: string
          value?: string
        }
        Relationships: [
          {
            foreignKeyName: "inspection_types_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      inspections: {
        Row: {
          claim_id: string
          created_at: string
          id: string
          inspection_report: Json | null
          inspection_trigger_id: string
          inspection_trigger_value: string
          inspection_type_id: string
          inspection_type_value: string
          paid_by: string
          performed_by: string
          status: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          claim_id: string
          created_at?: string
          id?: string
          inspection_report?: Json | null
          inspection_trigger_id: string
          inspection_trigger_value: string
          inspection_type_id: string
          inspection_type_value: string
          paid_by: string
          performed_by: string
          status?: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          claim_id?: string
          created_at?: string
          id?: string
          inspection_report?: Json | null
          inspection_trigger_id?: string
          inspection_trigger_value?: string
          inspection_type_id?: string
          inspection_type_value?: string
          paid_by?: string
          performed_by?: string
          status?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "inspections_claim_id_fkey"
            columns: ["claim_id"]
            isOneToOne: false
            referencedRelation: "claims"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inspections_inspection_trigger_id_fkey"
            columns: ["inspection_trigger_id"]
            isOneToOne: false
            referencedRelation: "inspection_triggers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inspections_inspection_type_id_fkey"
            columns: ["inspection_type_id"]
            isOneToOne: false
            referencedRelation: "inspection_types"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inspections_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      internal_teams: {
        Row: {
          created_at: string
          deleted_at: string | null
          description: string | null
          id: string
          name: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          deleted_at?: string | null
          description?: string | null
          id?: string
          name: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          deleted_at?: string | null
          description?: string | null
          id?: string
          name?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "internal_teams_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      invitations: {
        Row: {
          consumed_at: string | null
          created_at: string
          email: string
          expires_at: string
          full_name: string | null
          id: string
          invited_by: string | null
          role: string
          tenant_id: string
          token: string
        }
        Insert: {
          consumed_at?: string | null
          created_at?: string
          email: string
          expires_at: string
          full_name?: string | null
          id?: string
          invited_by?: string | null
          role: string
          tenant_id: string
          token: string
        }
        Update: {
          consumed_at?: string | null
          created_at?: string
          email?: string
          expires_at?: string
          full_name?: string | null
          id?: string
          invited_by?: string | null
          role?: string
          tenant_id?: string
          token?: string
        }
        Relationships: [
          {
            foreignKeyName: "invitations_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      notices_of_defect: {
        Row: {
          claim_id: string
          claim_summary_snapshot: Json
          created_at: string
          expected_response_date: string
          id: string
          notification_message: Json | null
          notified_at: string
          notified_by_user_id: string
          recipient_company_snapshot: string | null
          recipient_contact_id: string | null
          recipient_email_snapshot: string
          recipient_name_snapshot: string
          recipient_token: string | null
          recipient_token_expires_at: string | null
          recipient_user_id: string | null
          response_at: string | null
          response_explanation: Json | null
          response_status: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          claim_id: string
          claim_summary_snapshot: Json
          created_at?: string
          expected_response_date: string
          id?: string
          notification_message?: Json | null
          notified_at?: string
          notified_by_user_id: string
          recipient_company_snapshot?: string | null
          recipient_contact_id?: string | null
          recipient_email_snapshot: string
          recipient_name_snapshot: string
          recipient_token?: string | null
          recipient_token_expires_at?: string | null
          recipient_user_id?: string | null
          response_at?: string | null
          response_explanation?: Json | null
          response_status?: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          claim_id?: string
          claim_summary_snapshot?: Json
          created_at?: string
          expected_response_date?: string
          id?: string
          notification_message?: Json | null
          notified_at?: string
          notified_by_user_id?: string
          recipient_company_snapshot?: string | null
          recipient_contact_id?: string | null
          recipient_email_snapshot?: string
          recipient_name_snapshot?: string
          recipient_token?: string | null
          recipient_token_expires_at?: string | null
          recipient_user_id?: string | null
          response_at?: string | null
          response_explanation?: Json | null
          response_status?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "notices_of_defect_claim_id_fkey"
            columns: ["claim_id"]
            isOneToOne: false
            referencedRelation: "claims"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notices_of_defect_notified_by_user_id_fkey"
            columns: ["notified_by_user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notices_of_defect_recipient_contact_id_fkey"
            columns: ["recipient_contact_id"]
            isOneToOne: false
            referencedRelation: "contacts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notices_of_defect_recipient_user_id_fkey"
            columns: ["recipient_user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notices_of_defect_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      om_authorization_documents: {
        Row: {
          claim_id: string
          content_snapshot: Json
          created_at: string
          customer_id: string
          customer_token: string | null
          customer_token_expires_at: string | null
          event_reference_id: string
          event_type: string
          id: string
          linked_om_provider_id: string
          signed_at: string | null
          signer_name_typed: string | null
          status: string
          template_id: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          claim_id: string
          content_snapshot: Json
          created_at?: string
          customer_id: string
          customer_token?: string | null
          customer_token_expires_at?: string | null
          event_reference_id: string
          event_type: string
          id?: string
          linked_om_provider_id: string
          signed_at?: string | null
          signer_name_typed?: string | null
          status?: string
          template_id: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          claim_id?: string
          content_snapshot?: Json
          created_at?: string
          customer_id?: string
          customer_token?: string | null
          customer_token_expires_at?: string | null
          event_reference_id?: string
          event_type?: string
          id?: string
          linked_om_provider_id?: string
          signed_at?: string | null
          signer_name_typed?: string | null
          status?: string
          template_id?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "om_authorization_documents_claim_id_fkey"
            columns: ["claim_id"]
            isOneToOne: false
            referencedRelation: "claims"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "om_authorization_documents_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "contacts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "om_authorization_documents_linked_om_provider_id_fkey"
            columns: ["linked_om_provider_id"]
            isOneToOne: false
            referencedRelation: "contacts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "om_authorization_documents_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "om_authorization_templates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "om_authorization_documents_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      om_authorization_templates: {
        Row: {
          acknowledgment_text: Json
          created_at: string
          id: string
          is_default: boolean
          name: string
          tenant_id: string
        }
        Insert: {
          acknowledgment_text: Json
          created_at?: string
          id?: string
          is_default?: boolean
          name: string
          tenant_id: string
        }
        Update: {
          acknowledgment_text?: Json
          created_at?: string
          id?: string
          is_default?: boolean
          name?: string
          tenant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "om_authorization_templates_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      projects: {
        Row: {
          created_at: string
          customer_email_snapshot: string | null
          customer_id: string | null
          customer_name_snapshot: string | null
          customer_phone_snapshot: string | null
          deleted_at: string | null
          id: string
          imported_via_batch_id: string | null
          integration_config: Json | null
          name: string
          site_address_city: string | null
          site_address_state: string | null
          site_address_street: string | null
          site_address_zip: string | null
          tenant_id: string
          trigger_date: string | null
          trigger_source: string
          trigger_status: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          customer_email_snapshot?: string | null
          customer_id?: string | null
          customer_name_snapshot?: string | null
          customer_phone_snapshot?: string | null
          deleted_at?: string | null
          id?: string
          imported_via_batch_id?: string | null
          integration_config?: Json | null
          name: string
          site_address_city?: string | null
          site_address_state?: string | null
          site_address_street?: string | null
          site_address_zip?: string | null
          tenant_id: string
          trigger_date?: string | null
          trigger_source: string
          trigger_status?: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          customer_email_snapshot?: string | null
          customer_id?: string | null
          customer_name_snapshot?: string | null
          customer_phone_snapshot?: string | null
          deleted_at?: string | null
          id?: string
          imported_via_batch_id?: string | null
          integration_config?: Json | null
          name?: string
          site_address_city?: string | null
          site_address_state?: string | null
          site_address_street?: string | null
          site_address_zip?: string | null
          tenant_id?: string
          trigger_date?: string | null
          trigger_source?: string
          trigger_status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "projects_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "contacts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "projects_imported_via_batch_id_fkey"
            columns: ["imported_via_batch_id"]
            isOneToOne: false
            referencedRelation: "import_batches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "projects_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      service_reports: {
        Row: {
          accepted_by_acquiescence: boolean | null
          challenges_encountered: Json | null
          claim_id: string
          corrective_actions: Json
          created_at: string
          customer_decided_at: string | null
          customer_decision: string | null
          customer_dispute_details: Json | null
          customer_review_token: string | null
          customer_review_token_expires_at: string | null
          further_work_explanation: Json | null
          id: string
          parts_used: Json | null
          personnel: Json
          photos: Json | null
          repair_completed_at: string
          repair_started_at: string
          resolution_status: string
          reviewed_at: string | null
          reviewer_decision: string | null
          reviewer_user_id: string | null
          submission_token: string | null
          submission_token_expires_at: string | null
          submitted_at: string | null
          submitted_by_contact_id: string | null
          submitted_by_email_snapshot: string | null
          submitted_by_name_snapshot: string | null
          submitted_by_phone_snapshot: string | null
          submitted_by_user_id: string | null
          tenant_id: string
          updated_at: string
        }
        Insert: {
          accepted_by_acquiescence?: boolean | null
          challenges_encountered?: Json | null
          claim_id: string
          corrective_actions: Json
          created_at?: string
          customer_decided_at?: string | null
          customer_decision?: string | null
          customer_dispute_details?: Json | null
          customer_review_token?: string | null
          customer_review_token_expires_at?: string | null
          further_work_explanation?: Json | null
          id?: string
          parts_used?: Json | null
          personnel: Json
          photos?: Json | null
          repair_completed_at: string
          repair_started_at: string
          resolution_status: string
          reviewed_at?: string | null
          reviewer_decision?: string | null
          reviewer_user_id?: string | null
          submission_token?: string | null
          submission_token_expires_at?: string | null
          submitted_at?: string | null
          submitted_by_contact_id?: string | null
          submitted_by_email_snapshot?: string | null
          submitted_by_name_snapshot?: string | null
          submitted_by_phone_snapshot?: string | null
          submitted_by_user_id?: string | null
          tenant_id: string
          updated_at?: string
        }
        Update: {
          accepted_by_acquiescence?: boolean | null
          challenges_encountered?: Json | null
          claim_id?: string
          corrective_actions?: Json
          created_at?: string
          customer_decided_at?: string | null
          customer_decision?: string | null
          customer_dispute_details?: Json | null
          customer_review_token?: string | null
          customer_review_token_expires_at?: string | null
          further_work_explanation?: Json | null
          id?: string
          parts_used?: Json | null
          personnel?: Json
          photos?: Json | null
          repair_completed_at?: string
          repair_started_at?: string
          resolution_status?: string
          reviewed_at?: string | null
          reviewer_decision?: string | null
          reviewer_user_id?: string | null
          submission_token?: string | null
          submission_token_expires_at?: string | null
          submitted_at?: string | null
          submitted_by_contact_id?: string | null
          submitted_by_email_snapshot?: string | null
          submitted_by_name_snapshot?: string | null
          submitted_by_phone_snapshot?: string | null
          submitted_by_user_id?: string | null
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "service_reports_claim_id_fkey"
            columns: ["claim_id"]
            isOneToOne: true
            referencedRelation: "claims"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_reports_reviewer_user_id_fkey"
            columns: ["reviewer_user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_reports_submitted_by_contact_id_fkey"
            columns: ["submitted_by_contact_id"]
            isOneToOne: false
            referencedRelation: "contacts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_reports_submitted_by_user_id_fkey"
            columns: ["submitted_by_user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_reports_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      tenant_holidays: {
        Row: {
          created_at: string
          holiday_date: string
          id: string
          label: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          holiday_date: string
          id?: string
          label: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          holiday_date?: string
          id?: string
          label?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tenant_holidays_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      tenant_id_sequences: {
        Row: {
          current_value: number
          current_year: number
          format_string: string
          id_type: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          current_value?: number
          current_year: number
          format_string: string
          id_type: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          current_value?: number
          current_year?: number
          format_string?: string
          id_type?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tenant_id_sequences_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      tenants: {
        Row: {
          created_at: string
          id: string
          max_team_admins: number
          name: string
          settings: Json
          slug: string
          status: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          max_team_admins?: number
          name: string
          settings?: Json
          slug: string
          status?: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          max_team_admins?: number
          name?: string
          settings?: Json
          slug?: string
          status?: string
          updated_at?: string
        }
        Relationships: []
      }
      users: {
        Row: {
          created_at: string
          email: string
          full_name: string | null
          id: string
          removed_at: string | null
          role: string
          status: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          email: string
          full_name?: string | null
          id: string
          removed_at?: string | null
          role: string
          status?: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          email?: string
          full_name?: string | null
          id?: string
          removed_at?: string | null
          role?: string
          status?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "users_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      warranty_coverages: {
        Row: {
          created_at: string
          id: string
          start_date: string
          tenant_id: string
          term_years: number
          updated_at: string
          warranty_registration_id: string
          warranty_type_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          start_date: string
          tenant_id: string
          term_years: number
          updated_at?: string
          warranty_registration_id: string
          warranty_type_id: string
        }
        Update: {
          created_at?: string
          id?: string
          start_date?: string
          tenant_id?: string
          term_years?: number
          updated_at?: string
          warranty_registration_id?: string
          warranty_type_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "warranty_coverages_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "warranty_coverages_warranty_registration_id_fkey"
            columns: ["warranty_registration_id"]
            isOneToOne: false
            referencedRelation: "warranty_registrations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "warranty_coverages_warranty_type_id_fkey"
            columns: ["warranty_type_id"]
            isOneToOne: false
            referencedRelation: "warranty_types"
            referencedColumns: ["id"]
          },
        ]
      }
      warranty_registrations: {
        Row: {
          activated_at: string | null
          actual_start_date: string | null
          assigned_at: string | null
          assigned_to_contact_id: string | null
          assigned_to_email_snapshot: string | null
          assigned_to_name_snapshot: string | null
          assigned_to_phone_snapshot: string | null
          assigned_to_user_id: string | null
          created_at: string
          id: string
          project_id: string
          status: string
          tenant_id: string
          updated_at: string
          warranty_id: string | null
        }
        Insert: {
          activated_at?: string | null
          actual_start_date?: string | null
          assigned_at?: string | null
          assigned_to_contact_id?: string | null
          assigned_to_email_snapshot?: string | null
          assigned_to_name_snapshot?: string | null
          assigned_to_phone_snapshot?: string | null
          assigned_to_user_id?: string | null
          created_at?: string
          id?: string
          project_id: string
          status: string
          tenant_id: string
          updated_at?: string
          warranty_id?: string | null
        }
        Update: {
          activated_at?: string | null
          actual_start_date?: string | null
          assigned_at?: string | null
          assigned_to_contact_id?: string | null
          assigned_to_email_snapshot?: string | null
          assigned_to_name_snapshot?: string | null
          assigned_to_phone_snapshot?: string | null
          assigned_to_user_id?: string | null
          created_at?: string
          id?: string
          project_id?: string
          status?: string
          tenant_id?: string
          updated_at?: string
          warranty_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "warranty_registrations_assigned_to_contact_id_fkey"
            columns: ["assigned_to_contact_id"]
            isOneToOne: false
            referencedRelation: "contacts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "warranty_registrations_assigned_to_user_id_fkey"
            columns: ["assigned_to_user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "warranty_registrations_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: true
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "warranty_registrations_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      warranty_types: {
        Row: {
          created_at: string
          id: string
          is_system: boolean
          name: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          is_system?: boolean
          name: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          is_system?: boolean
          name?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "warranty_types_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      work_authorization_documents: {
        Row: {
          authorization_acknowledged: boolean | null
          claim_id: string
          created_at: string
          crew_size: number
          customer_comments: Json | null
          customer_decision: string | null
          customer_token: string | null
          customer_token_expires_at: string | null
          denial_explanation: Json | null
          event_reference_id: string | null
          event_type: string
          expected_response_date: string | null
          gate_code_details: Json | null
          gate_code_needed: boolean | null
          id: string
          om_contact_email: string | null
          om_contact_name: string | null
          om_contact_phone: string | null
          om_provider_company: string | null
          operating_hours: string | null
          planned_end_at: string
          planned_start_at: string
          request_completed_by_name: string | null
          requested_at: string
          requestor_company: string
          requestor_email: string
          requestor_name: string
          requestor_phone: string | null
          responded_at: string | null
          signer_name_typed: string | null
          site_accessibility_date: string | null
          site_emergency_address: Json | null
          sow_activities: Json
          special_access_details: Json | null
          special_access_required: boolean | null
          status: string
          template_id: string
          template_snapshot: Json
          tenant_id: string
          updated_at: string
        }
        Insert: {
          authorization_acknowledged?: boolean | null
          claim_id: string
          created_at?: string
          crew_size: number
          customer_comments?: Json | null
          customer_decision?: string | null
          customer_token?: string | null
          customer_token_expires_at?: string | null
          denial_explanation?: Json | null
          event_reference_id?: string | null
          event_type: string
          expected_response_date?: string | null
          gate_code_details?: Json | null
          gate_code_needed?: boolean | null
          id?: string
          om_contact_email?: string | null
          om_contact_name?: string | null
          om_contact_phone?: string | null
          om_provider_company?: string | null
          operating_hours?: string | null
          planned_end_at: string
          planned_start_at: string
          request_completed_by_name?: string | null
          requested_at?: string
          requestor_company: string
          requestor_email: string
          requestor_name: string
          requestor_phone?: string | null
          responded_at?: string | null
          signer_name_typed?: string | null
          site_accessibility_date?: string | null
          site_emergency_address?: Json | null
          sow_activities: Json
          special_access_details?: Json | null
          special_access_required?: boolean | null
          status?: string
          template_id: string
          template_snapshot: Json
          tenant_id: string
          updated_at?: string
        }
        Update: {
          authorization_acknowledged?: boolean | null
          claim_id?: string
          created_at?: string
          crew_size?: number
          customer_comments?: Json | null
          customer_decision?: string | null
          customer_token?: string | null
          customer_token_expires_at?: string | null
          denial_explanation?: Json | null
          event_reference_id?: string | null
          event_type?: string
          expected_response_date?: string | null
          gate_code_details?: Json | null
          gate_code_needed?: boolean | null
          id?: string
          om_contact_email?: string | null
          om_contact_name?: string | null
          om_contact_phone?: string | null
          om_provider_company?: string | null
          operating_hours?: string | null
          planned_end_at?: string
          planned_start_at?: string
          request_completed_by_name?: string | null
          requested_at?: string
          requestor_company?: string
          requestor_email?: string
          requestor_name?: string
          requestor_phone?: string | null
          responded_at?: string | null
          signer_name_typed?: string | null
          site_accessibility_date?: string | null
          site_emergency_address?: Json | null
          sow_activities?: Json
          special_access_details?: Json | null
          special_access_required?: boolean | null
          status?: string
          template_id?: string
          template_snapshot?: Json
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "work_authorization_documents_claim_id_fkey"
            columns: ["claim_id"]
            isOneToOne: false
            referencedRelation: "claims"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_authorization_documents_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "work_authorization_templates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_authorization_documents_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      work_authorization_revisions: {
        Row: {
          field_changes: Json
          id: string
          revised_at: string
          revised_by_user_id: string
          revision_reason: Json
          tenant_id: string
          work_authorization_document_id: string
        }
        Insert: {
          field_changes: Json
          id?: string
          revised_at?: string
          revised_by_user_id: string
          revision_reason: Json
          tenant_id: string
          work_authorization_document_id: string
        }
        Update: {
          field_changes?: Json
          id?: string
          revised_at?: string
          revised_by_user_id?: string
          revision_reason?: Json
          tenant_id?: string
          work_authorization_document_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "work_authorization_revisions_revised_by_user_id_fkey"
            columns: ["revised_by_user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_authorization_revisions_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_authorization_revisions_work_authorization_document_i_fkey"
            columns: ["work_authorization_document_id"]
            isOneToOne: false
            referencedRelation: "work_authorization_documents"
            referencedColumns: ["id"]
          },
        ]
      }
      work_authorization_templates: {
        Row: {
          created_at: string
          customer_field_config: Json
          deleted_at: string | null
          id: string
          is_default: boolean
          legal_language: Json
          name: string
          tenant_id: string
          updated_at: string
          warrantor_field_config: Json
        }
        Insert: {
          created_at?: string
          customer_field_config: Json
          deleted_at?: string | null
          id?: string
          is_default?: boolean
          legal_language: Json
          name: string
          tenant_id: string
          updated_at?: string
          warrantor_field_config: Json
        }
        Update: {
          created_at?: string
          customer_field_config?: Json
          deleted_at?: string | null
          id?: string
          is_default?: boolean
          legal_language?: Json
          name?: string
          tenant_id?: string
          updated_at?: string
          warrantor_field_config?: Json
        }
        Relationships: [
          {
            foreignKeyName: "work_authorization_templates_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      work_plans: {
        Row: {
          claim_id: string
          corrective_actions: Json
          created_at: string
          crew_size: number
          execution_path: string
          id: string
          internal_team_id: string | null
          planned_end_at: string
          planned_start_at: string
          repair_scope_approach: Json
          required_materials_equipment: Json | null
          safety_considerations: Json | null
          site_access_coordination: Json | null
          status: string
          subcontractor_contact_id: string | null
          subcontractor_email_snapshot: string | null
          subcontractor_name_snapshot: string | null
          subcontractor_phone_snapshot: string | null
          tenant_id: string
          updated_at: string
          warranty_professional_user_id: string
          work_plan_type: string
        }
        Insert: {
          claim_id: string
          corrective_actions: Json
          created_at?: string
          crew_size: number
          execution_path: string
          id?: string
          internal_team_id?: string | null
          planned_end_at: string
          planned_start_at: string
          repair_scope_approach: Json
          required_materials_equipment?: Json | null
          safety_considerations?: Json | null
          site_access_coordination?: Json | null
          status?: string
          subcontractor_contact_id?: string | null
          subcontractor_email_snapshot?: string | null
          subcontractor_name_snapshot?: string | null
          subcontractor_phone_snapshot?: string | null
          tenant_id: string
          updated_at?: string
          warranty_professional_user_id: string
          work_plan_type: string
        }
        Update: {
          claim_id?: string
          corrective_actions?: Json
          created_at?: string
          crew_size?: number
          execution_path?: string
          id?: string
          internal_team_id?: string | null
          planned_end_at?: string
          planned_start_at?: string
          repair_scope_approach?: Json
          required_materials_equipment?: Json | null
          safety_considerations?: Json | null
          site_access_coordination?: Json | null
          status?: string
          subcontractor_contact_id?: string | null
          subcontractor_email_snapshot?: string | null
          subcontractor_name_snapshot?: string | null
          subcontractor_phone_snapshot?: string | null
          tenant_id?: string
          updated_at?: string
          warranty_professional_user_id?: string
          work_plan_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "work_plans_claim_id_fkey"
            columns: ["claim_id"]
            isOneToOne: false
            referencedRelation: "claims"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_plans_internal_team_id_fkey"
            columns: ["internal_team_id"]
            isOneToOne: false
            referencedRelation: "internal_teams"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_plans_subcontractor_contact_id_fkey"
            columns: ["subcontractor_contact_id"]
            isOneToOne: false
            referencedRelation: "contacts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_plans_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "work_plans_warranty_professional_user_id_fkey"
            columns: ["warranty_professional_user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      warranty_coverages_effective: {
        Row: {
          effective_end_date: string | null
          effective_start_date: string | null
          id: string | null
          start_date: string | null
          tenant_id: string | null
          term_years: number | null
          warranty_registration_id: string | null
          warranty_type_id: string | null
        }
        Relationships: [
          {
            foreignKeyName: "warranty_coverages_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "warranty_coverages_warranty_registration_id_fkey"
            columns: ["warranty_registration_id"]
            isOneToOne: false
            referencedRelation: "warranty_registrations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "warranty_coverages_warranty_type_id_fkey"
            columns: ["warranty_type_id"]
            isOneToOne: false
            referencedRelation: "warranty_types"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Functions: {
      federal_holidays_for_year: {
        Args: { p_year: number }
        Returns: {
          holiday_date: string
          label: string
        }[]
      }
      get_user_tenant_id: { Args: never; Returns: string }
      last_weekday_of_month: {
        Args: { p_dow: number; p_month: number; p_year: number }
        Returns: string
      }
      nth_weekday_of_month: {
        Args: { p_dow: number; p_month: number; p_n: number; p_year: number }
        Returns: string
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {},
  },
} as const

// ─── HAND-AUTHORED CONVENIENCE ALIASES (preserved across regeneration) ───
// Convenience aliases
export type Tenant = Database['public']['Tables']['tenants']['Row']
export type TenantInsert = Database['public']['Tables']['tenants']['Insert']
export type TenantUpdate = Database['public']['Tables']['tenants']['Update']

export type User = Database['public']['Tables']['users']['Row']
export type UserInsert = Database['public']['Tables']['users']['Insert']
export type UserUpdate = Database['public']['Tables']['users']['Update']

export type Invitation = Database['public']['Tables']['invitations']['Row']
export type InvitationInsert = Database['public']['Tables']['invitations']['Insert']
export type InvitationUpdate = Database['public']['Tables']['invitations']['Update']

export type UserRole = 'team_admin' | 'reviewer' | 'viewer'
export type UserStatus = 'active' | 'suspended'
export type TenantStatus = 'active' | 'suspended' | 'terminated'
