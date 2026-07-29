export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  audit: {
    Tables: {
      entity_changes: {
        Row: {
          after_hash: string | null
          audit_event_id: string
          before_hash: string | null
          changed_fields: string[]
          created_at: string
          entity_id: string
          entity_type: string
          id: string
          operation: string
          organization_id: string | null
          redacted_diff: Json
        }
        Insert: {
          after_hash?: string | null
          audit_event_id: string
          before_hash?: string | null
          changed_fields?: string[]
          created_at?: string
          entity_id: string
          entity_type: string
          id?: string
          operation: string
          organization_id?: string | null
          redacted_diff?: Json
        }
        Update: {
          after_hash?: string | null
          audit_event_id?: string
          before_hash?: string | null
          changed_fields?: string[]
          created_at?: string
          entity_id?: string
          entity_type?: string
          id?: string
          operation?: string
          organization_id?: string | null
          redacted_diff?: Json
        }
        Relationships: [
          {
            foreignKeyName: "fk_audit_entity_changes__events"
            columns: ["audit_event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
        ]
      }
      events: {
        Row: {
          access_reason: string | null
          action: string
          actor_member_id: string | null
          actor_profile_id: string | null
          correlation_id: string | null
          created_at: string
          entity_id: string | null
          entity_type: string | null
          event_category: string
          event_code: string
          id: string
          ip_address: unknown
          metadata: Json
          occurred_at: string
          organization_id: string | null
          outcome: string
          request_id: string | null
          user_agent: string | null
        }
        Insert: {
          access_reason?: string | null
          action: string
          actor_member_id?: string | null
          actor_profile_id?: string | null
          correlation_id?: string | null
          created_at?: string
          entity_id?: string | null
          entity_type?: string | null
          event_category: string
          event_code: string
          id?: string
          ip_address?: unknown
          metadata?: Json
          occurred_at?: string
          organization_id?: string | null
          outcome?: string
          request_id?: string | null
          user_agent?: string | null
        }
        Update: {
          access_reason?: string | null
          action?: string
          actor_member_id?: string | null
          actor_profile_id?: string | null
          correlation_id?: string | null
          created_at?: string
          entity_id?: string | null
          entity_type?: string | null
          event_category?: string
          event_code?: string
          id?: string
          ip_address?: unknown
          metadata?: Json
          occurred_at?: string
          organization_id?: string | null
          outcome?: string
          request_id?: string | null
          user_agent?: string | null
        }
        Relationships: []
      }
      permission_events: {
        Row: {
          app_role_id: string | null
          audit_event_id: string
          created_at: string
          event_type: string
          id: string
          new_state: Json | null
          organization_id: string | null
          permission_code: string | null
          previous_state: Json | null
          profile_id: string
          profile_role_assignment_id: string | null
          profile_scope_assignment_id: string | null
        }
        Insert: {
          app_role_id?: string | null
          audit_event_id: string
          created_at?: string
          event_type: string
          id?: string
          new_state?: Json | null
          organization_id?: string | null
          permission_code?: string | null
          previous_state?: Json | null
          profile_id: string
          profile_role_assignment_id?: string | null
          profile_scope_assignment_id?: string | null
        }
        Update: {
          app_role_id?: string | null
          audit_event_id?: string
          created_at?: string
          event_type?: string
          id?: string
          new_state?: Json | null
          organization_id?: string | null
          permission_code?: string | null
          previous_state?: Json | null
          profile_id?: string
          profile_role_assignment_id?: string | null
          profile_scope_assignment_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_audit_permission_events__events"
            columns: ["audit_event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      [_ in never]: never
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
      addresses: {
        Row: {
          address_line_1: string
          address_line_2: string | null
          address_line_3: string | null
          city_id: string | null
          city_name: string
          country_code: string
          created_at: string
          created_by_profile_id: string | null
          formatted_address: string | null
          geocode_precision: string | null
          id: string
          latitude: number | null
          longitude: number | null
          organization_id: string
          postal_code: string | null
          source: string
          state_province_id: string | null
          state_province_name: string | null
          updated_at: string
          updated_by_profile_id: string | null
          verification_status: string
          verified_at: string | null
        }
        Insert: {
          address_line_1: string
          address_line_2?: string | null
          address_line_3?: string | null
          city_id?: string | null
          city_name: string
          country_code: string
          created_at?: string
          created_by_profile_id?: string | null
          formatted_address?: string | null
          geocode_precision?: string | null
          id?: string
          latitude?: number | null
          longitude?: number | null
          organization_id: string
          postal_code?: string | null
          source?: string
          state_province_id?: string | null
          state_province_name?: string | null
          updated_at?: string
          updated_by_profile_id?: string | null
          verification_status?: string
          verified_at?: string | null
        }
        Update: {
          address_line_1?: string
          address_line_2?: string | null
          address_line_3?: string | null
          city_id?: string | null
          city_name?: string
          country_code?: string
          created_at?: string
          created_by_profile_id?: string | null
          formatted_address?: string | null
          geocode_precision?: string | null
          id?: string
          latitude?: number | null
          longitude?: number | null
          organization_id?: string
          postal_code?: string | null
          source?: string
          state_province_id?: string | null
          state_province_name?: string | null
          updated_at?: string
          updated_by_profile_id?: string | null
          verification_status?: string
          verified_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_addresses__cities"
            columns: ["city_id"]
            isOneToOne: false
            referencedRelation: "cities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_addresses__countries"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "countries"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "fk_addresses__created_by"
            columns: ["created_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_addresses__organizations"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_addresses__states_provinces"
            columns: ["state_province_id"]
            isOneToOne: false
            referencedRelation: "states_provinces"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_addresses__updated_by"
            columns: ["updated_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      app_roles: {
        Row: {
          code: string
          created_at: string
          created_by_profile_id: string | null
          description: string | null
          display_order: number
          id: string
          is_active: boolean
          is_assignable: boolean
          is_system_role: boolean
          name: string
          organization_id: string | null
          requires_approval: boolean
          requires_scope: boolean
          risk_level: string
          role_category: string
          updated_at: string
          updated_by_profile_id: string | null
        }
        Insert: {
          code: string
          created_at?: string
          created_by_profile_id?: string | null
          description?: string | null
          display_order?: number
          id?: string
          is_active?: boolean
          is_assignable?: boolean
          is_system_role?: boolean
          name: string
          organization_id?: string | null
          requires_approval?: boolean
          requires_scope?: boolean
          risk_level?: string
          role_category: string
          updated_at?: string
          updated_by_profile_id?: string | null
        }
        Update: {
          code?: string
          created_at?: string
          created_by_profile_id?: string | null
          description?: string | null
          display_order?: number
          id?: string
          is_active?: boolean
          is_assignable?: boolean
          is_system_role?: boolean
          name?: string
          organization_id?: string | null
          requires_approval?: boolean
          requires_scope?: boolean
          risk_level?: string
          role_category?: string
          updated_at?: string
          updated_by_profile_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_app_roles__created_by"
            columns: ["created_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_app_roles__organizations"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_app_roles__updated_by"
            columns: ["updated_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      chapters: {
        Row: {
          chapter_category: string
          created_at: string
          created_by: string | null
          id: string
          maximum_unit_count: number | null
          organization_id: string
          parish_id: string | null
          service_area_description: string | null
          target_unit_count: number | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          chapter_category?: string
          created_at?: string
          created_by?: string | null
          id: string
          maximum_unit_count?: number | null
          organization_id: string
          parish_id?: string | null
          service_area_description?: string | null
          target_unit_count?: number | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          chapter_category?: string
          created_at?: string
          created_by?: string | null
          id?: string
          maximum_unit_count?: number | null
          organization_id?: string
          parish_id?: string | null
          service_area_description?: string | null
          target_unit_count?: number | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_chapters__governance_nodes"
            columns: ["organization_id", "id"]
            isOneToOne: false
            referencedRelation: "governance_nodes"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      cities: {
        Row: {
          country_code: string
          county_district_name: string | null
          created_at: string
          id: string
          is_active: boolean
          latitude: number | null
          longitude: number | null
          name: string
          state_province_id: string | null
        }
        Insert: {
          country_code: string
          county_district_name?: string | null
          created_at?: string
          id?: string
          is_active?: boolean
          latitude?: number | null
          longitude?: number | null
          name: string
          state_province_id?: string | null
        }
        Update: {
          country_code?: string
          county_district_name?: string | null
          created_at?: string
          id?: string
          is_active?: boolean
          latitude?: number | null
          longitude?: number | null
          name?: string
          state_province_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "cities_country_code_fkey"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "countries"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "cities_state_province_id_fkey"
            columns: ["state_province_id"]
            isOneToOne: false
            referencedRelation: "states_provinces"
            referencedColumns: ["id"]
          },
        ]
      }
      communication_preferences: {
        Row: {
          channel: string
          communication_purpose: string
          consent_record_id: string | null
          created_at: string
          effective_from_at: string
          effective_to_at: string | null
          id: string
          member_id: string
          organization_id: string
          preference_status: string
          preferred_contact_window: string | null
          preferred_language_code: string | null
          recorded_at: string
          recorded_by_profile_id: string | null
          source: string
        }
        Insert: {
          channel: string
          communication_purpose: string
          consent_record_id?: string | null
          created_at?: string
          effective_from_at?: string
          effective_to_at?: string | null
          id?: string
          member_id: string
          organization_id: string
          preference_status?: string
          preferred_contact_window?: string | null
          preferred_language_code?: string | null
          recorded_at?: string
          recorded_by_profile_id?: string | null
          source?: string
        }
        Update: {
          channel?: string
          communication_purpose?: string
          consent_record_id?: string | null
          created_at?: string
          effective_from_at?: string
          effective_to_at?: string | null
          id?: string
          member_id?: string
          organization_id?: string
          preference_status?: string
          preferred_contact_window?: string | null
          preferred_language_code?: string | null
          recorded_at?: string
          recorded_by_profile_id?: string | null
          source?: string
        }
        Relationships: [
          {
            foreignKeyName: "fk_communication_preferences__languages"
            columns: ["preferred_language_code"]
            isOneToOne: false
            referencedRelation: "languages"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "fk_communication_preferences__members"
            columns: ["organization_id", "member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_communication_preferences__recorded_by"
            columns: ["recorded_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      consent_records: {
        Row: {
          consent_type_id: string
          created_at: string
          decided_at: string
          decision: string
          effective_from_at: string
          effective_to_at: string | null
          evidence: Json
          guardian_contact: string | null
          guardian_name: string | null
          guardian_relationship: string | null
          id: string
          member_id: string | null
          organization_id: string
          profile_id: string | null
          recorded_by_profile_id: string | null
          source: string
          subject_reference_id: string | null
          subject_type: string
          withdrawal_of_consent_record_id: string | null
        }
        Insert: {
          consent_type_id: string
          created_at?: string
          decided_at?: string
          decision: string
          effective_from_at?: string
          effective_to_at?: string | null
          evidence?: Json
          guardian_contact?: string | null
          guardian_name?: string | null
          guardian_relationship?: string | null
          id?: string
          member_id?: string | null
          organization_id: string
          profile_id?: string | null
          recorded_by_profile_id?: string | null
          source?: string
          subject_reference_id?: string | null
          subject_type: string
          withdrawal_of_consent_record_id?: string | null
        }
        Update: {
          consent_type_id?: string
          created_at?: string
          decided_at?: string
          decision?: string
          effective_from_at?: string
          effective_to_at?: string | null
          evidence?: Json
          guardian_contact?: string | null
          guardian_name?: string | null
          guardian_relationship?: string | null
          id?: string
          member_id?: string | null
          organization_id?: string
          profile_id?: string | null
          recorded_by_profile_id?: string | null
          source?: string
          subject_reference_id?: string | null
          subject_type?: string
          withdrawal_of_consent_record_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_consent_records__members"
            columns: ["organization_id", "member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_consent_records__profiles"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_consent_records__types"
            columns: ["consent_type_id"]
            isOneToOne: false
            referencedRelation: "consent_types"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_consent_records__withdrawal"
            columns: ["withdrawal_of_consent_record_id"]
            isOneToOne: false
            referencedRelation: "consent_records"
            referencedColumns: ["id"]
          },
        ]
      }
      consent_types: {
        Row: {
          code: string
          consent_category: string
          created_at: string
          description: string | null
          document_storage_path: string | null
          id: string
          is_active: boolean
          name: string
          organization_id: string | null
          published_at: string | null
          published_by_profile_id: string | null
          requires_guardian: boolean
          retired_at: string | null
          subject_type: string
          version_code: string
        }
        Insert: {
          code: string
          consent_category: string
          created_at?: string
          description?: string | null
          document_storage_path?: string | null
          id?: string
          is_active?: boolean
          name: string
          organization_id?: string | null
          published_at?: string | null
          published_by_profile_id?: string | null
          requires_guardian?: boolean
          retired_at?: string | null
          subject_type?: string
          version_code: string
        }
        Update: {
          code?: string
          consent_category?: string
          created_at?: string
          description?: string | null
          document_storage_path?: string | null
          id?: string
          is_active?: boolean
          name?: string
          organization_id?: string | null
          published_at?: string | null
          published_by_profile_id?: string | null
          requires_guardian?: boolean
          retired_at?: string | null
          subject_type?: string
          version_code?: string
        }
        Relationships: []
      }
      countries: {
        Row: {
          code: string
          created_at: string
          default_currency_code: string | null
          display_order: number
          is_active: boolean
          iso3_code: string
          name: string
          numeric_code: string | null
          official_name: string | null
          phone_calling_code: string | null
        }
        Insert: {
          code: string
          created_at?: string
          default_currency_code?: string | null
          display_order?: number
          is_active?: boolean
          iso3_code: string
          name: string
          numeric_code?: string | null
          official_name?: string | null
          phone_calling_code?: string | null
        }
        Update: {
          code?: string
          created_at?: string
          default_currency_code?: string | null
          display_order?: number
          is_active?: boolean
          iso3_code?: string
          name?: string
          numeric_code?: string | null
          official_name?: string | null
          phone_calling_code?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "countries_default_currency_code_fkey"
            columns: ["default_currency_code"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["code"]
          },
        ]
      }
      currencies: {
        Row: {
          code: string
          created_at: string
          decimal_digits: number
          display_order: number
          is_active: boolean
          name: string
          symbol: string | null
        }
        Insert: {
          code: string
          created_at?: string
          decimal_digits?: number
          display_order?: number
          is_active?: boolean
          name: string
          symbol?: string | null
        }
        Update: {
          code?: string
          created_at?: string
          decimal_digits?: number
          display_order?: number
          is_active?: boolean
          name?: string
          symbol?: string | null
        }
        Relationships: []
      }
      data_classifications: {
        Row: {
          allows_general_member_access: boolean
          code: string
          created_at: string
          description: string | null
          is_active: boolean
          level: number
          name: string
          requires_access_logging: boolean
          requires_access_reason: boolean
        }
        Insert: {
          allows_general_member_access?: boolean
          code: string
          created_at?: string
          description?: string | null
          is_active?: boolean
          level: number
          name: string
          requires_access_logging?: boolean
          requires_access_reason?: boolean
        }
        Update: {
          allows_general_member_access?: boolean
          code?: string
          created_at?: string
          description?: string | null
          is_active?: boolean
          level?: number
          name?: string
          requires_access_logging?: boolean
          requires_access_reason?: boolean
        }
        Relationships: []
      }
      device_authorizations: {
        Row: {
          authorization_status: string
          authorization_type: string
          authorized_at: string
          authorized_by_profile_id: string | null
          created_at: string
          effective_from_at: string
          effective_to_at: string | null
          ending_reason: string | null
          id: string
          organization_id: string
          profile_id: string
          scope_configuration: Json
          updated_at: string
          user_device_id: string
        }
        Insert: {
          authorization_status?: string
          authorization_type: string
          authorized_at?: string
          authorized_by_profile_id?: string | null
          created_at?: string
          effective_from_at?: string
          effective_to_at?: string | null
          ending_reason?: string | null
          id?: string
          organization_id: string
          profile_id: string
          scope_configuration?: Json
          updated_at?: string
          user_device_id: string
        }
        Update: {
          authorization_status?: string
          authorization_type?: string
          authorized_at?: string
          authorized_by_profile_id?: string | null
          created_at?: string
          effective_from_at?: string
          effective_to_at?: string | null
          ending_reason?: string | null
          id?: string
          organization_id?: string
          profile_id?: string
          scope_configuration?: Json
          updated_at?: string
          user_device_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "fk_device_authorizations__devices"
            columns: ["user_device_id"]
            isOneToOne: false
            referencedRelation: "user_devices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_device_authorizations__organizations"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_device_authorizations__profiles"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      device_revocations: {
        Row: {
          created_at: string
          device_authorization_id: string | null
          id: string
          organization_id: string
          reason_code: string
          reason_summary: string | null
          revoked_at: string
          revoked_by_profile_id: string | null
          security_event_id: string | null
          user_device_id: string
        }
        Insert: {
          created_at?: string
          device_authorization_id?: string | null
          id?: string
          organization_id: string
          reason_code: string
          reason_summary?: string | null
          revoked_at?: string
          revoked_by_profile_id?: string | null
          security_event_id?: string | null
          user_device_id: string
        }
        Update: {
          created_at?: string
          device_authorization_id?: string | null
          id?: string
          organization_id?: string
          reason_code?: string
          reason_summary?: string | null
          revoked_at?: string
          revoked_by_profile_id?: string | null
          security_event_id?: string | null
          user_device_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "fk_device_revocations__authorizations"
            columns: ["device_authorization_id"]
            isOneToOne: false
            referencedRelation: "device_authorizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_device_revocations__devices"
            columns: ["user_device_id"]
            isOneToOne: false
            referencedRelation: "user_devices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_device_revocations__security_events"
            columns: ["security_event_id"]
            isOneToOne: false
            referencedRelation: "security_events"
            referencedColumns: ["id"]
          },
        ]
      }
      duplicate_member_candidates: {
        Row: {
          candidate_status: string
          created_at: string
          detected_at: string
          detected_by: string
          id: string
          match_basis: Json
          match_score: number
          member_id_high: string
          member_id_low: string
          member_merge_request_id: string | null
          organization_id: string
          review_summary: string | null
          reviewed_at: string | null
          reviewed_by_profile_id: string | null
          updated_at: string
        }
        Insert: {
          candidate_status?: string
          created_at?: string
          detected_at?: string
          detected_by?: string
          id?: string
          match_basis?: Json
          match_score: number
          member_id_high: string
          member_id_low: string
          member_merge_request_id?: string | null
          organization_id: string
          review_summary?: string | null
          reviewed_at?: string | null
          reviewed_by_profile_id?: string | null
          updated_at?: string
        }
        Update: {
          candidate_status?: string
          created_at?: string
          detected_at?: string
          detected_by?: string
          id?: string
          match_basis?: Json
          match_score?: number
          member_id_high?: string
          member_id_low?: string
          member_merge_request_id?: string | null
          organization_id?: string
          review_summary?: string | null
          reviewed_at?: string | null
          reviewed_by_profile_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "fk_duplicate_member_candidates__high"
            columns: ["organization_id", "member_id_high"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_duplicate_member_candidates__low"
            columns: ["organization_id", "member_id_low"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_duplicate_member_candidates__merge_requests"
            columns: ["member_merge_request_id"]
            isOneToOne: false
            referencedRelation: "member_merge_requests"
            referencedColumns: ["id"]
          },
        ]
      }
      entity_tags: {
        Row: {
          assigned_at: string
          assigned_by: string | null
          assignment_reason: string | null
          created_at: string
          entity_id: string
          entity_type: string
          expires_at: string | null
          id: string
          organization_id: string
          tag_id: string
        }
        Insert: {
          assigned_at?: string
          assigned_by?: string | null
          assignment_reason?: string | null
          created_at?: string
          entity_id: string
          entity_type: string
          expires_at?: string | null
          id?: string
          organization_id: string
          tag_id: string
        }
        Update: {
          assigned_at?: string
          assigned_by?: string | null
          assignment_reason?: string | null
          created_at?: string
          entity_id?: string
          entity_type?: string
          expires_at?: string | null
          id?: string
          organization_id?: string
          tag_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "entity_tags_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "entity_tags_tag_id_fkey"
            columns: ["tag_id"]
            isOneToOne: false
            referencedRelation: "tags"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_entity_tags__assigned_by"
            columns: ["assigned_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      families: {
        Row: {
          administrative_notes: string | null
          created_at: string
          created_by_profile_id: string | null
          directory_visibility: string
          display_name: string
          ended_on: string | null
          family_name: string
          family_status: string
          family_type: string
          formed_on: string | null
          id: string
          organization_id: string
          primary_address_id: string | null
          primary_parish_id: string | null
          updated_at: string
          updated_by_profile_id: string | null
        }
        Insert: {
          administrative_notes?: string | null
          created_at?: string
          created_by_profile_id?: string | null
          directory_visibility?: string
          display_name: string
          ended_on?: string | null
          family_name: string
          family_status?: string
          family_type?: string
          formed_on?: string | null
          id?: string
          organization_id: string
          primary_address_id?: string | null
          primary_parish_id?: string | null
          updated_at?: string
          updated_by_profile_id?: string | null
        }
        Update: {
          administrative_notes?: string | null
          created_at?: string
          created_by_profile_id?: string | null
          directory_visibility?: string
          display_name?: string
          ended_on?: string | null
          family_name?: string
          family_status?: string
          family_type?: string
          formed_on?: string | null
          id?: string
          organization_id?: string
          primary_address_id?: string | null
          primary_parish_id?: string | null
          updated_at?: string
          updated_by_profile_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_families__created_by"
            columns: ["created_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_families__organizations"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_families__primary_addresses"
            columns: ["organization_id", "primary_address_id"]
            isOneToOne: false
            referencedRelation: "addresses"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_families__updated_by"
            columns: ["updated_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      family_members: {
        Row: {
          created_at: string
          created_by_profile_id: string | null
          effective_from: string | null
          effective_to: string | null
          family_id: string
          family_role: string | null
          id: string
          is_dependent: boolean
          is_primary_contact: boolean
          member_id: string
          membership_status: string
          organization_id: string
          updated_at: string
          updated_by_profile_id: string | null
        }
        Insert: {
          created_at?: string
          created_by_profile_id?: string | null
          effective_from?: string | null
          effective_to?: string | null
          family_id: string
          family_role?: string | null
          id?: string
          is_dependent?: boolean
          is_primary_contact?: boolean
          member_id: string
          membership_status?: string
          organization_id: string
          updated_at?: string
          updated_by_profile_id?: string | null
        }
        Update: {
          created_at?: string
          created_by_profile_id?: string | null
          effective_from?: string | null
          effective_to?: string | null
          family_id?: string
          family_role?: string | null
          id?: string
          is_dependent?: boolean
          is_primary_contact?: boolean
          member_id?: string
          membership_status?: string
          organization_id?: string
          updated_at?: string
          updated_by_profile_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_family_members__created_by"
            columns: ["created_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_family_members__families"
            columns: ["organization_id", "family_id"]
            isOneToOne: false
            referencedRelation: "families"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_family_members__members"
            columns: ["organization_id", "member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_family_members__updated_by"
            columns: ["updated_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      family_relationship_types: {
        Row: {
          allows_multiple_current: boolean
          code: string
          created_at: string
          display_order: number
          id: string
          inverse_code: string | null
          is_active: boolean
          is_symmetric: boolean
          name: string
          organization_id: string | null
          relationship_category: string
          requires_same_family: boolean
        }
        Insert: {
          allows_multiple_current?: boolean
          code: string
          created_at?: string
          display_order?: number
          id?: string
          inverse_code?: string | null
          is_active?: boolean
          is_symmetric?: boolean
          name: string
          organization_id?: string | null
          relationship_category: string
          requires_same_family?: boolean
        }
        Update: {
          allows_multiple_current?: boolean
          code?: string
          created_at?: string
          display_order?: number
          id?: string
          inverse_code?: string | null
          is_active?: boolean
          is_symmetric?: boolean
          name?: string
          organization_id?: string | null
          relationship_category?: string
          requires_same_family?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "fk_family_relationship_types__organizations"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      family_relationships: {
        Row: {
          created_at: string
          created_by_profile_id: string | null
          effective_from: string | null
          effective_to: string | null
          family_id: string | null
          from_member_id: string
          id: string
          is_primary_relationship: boolean
          organization_id: string
          relationship_status: string
          relationship_type_id: string
          source: string
          to_member_id: string
          updated_at: string
          updated_by_profile_id: string | null
          verification_status: string
          verified_at: string | null
          verified_by_profile_id: string | null
        }
        Insert: {
          created_at?: string
          created_by_profile_id?: string | null
          effective_from?: string | null
          effective_to?: string | null
          family_id?: string | null
          from_member_id: string
          id?: string
          is_primary_relationship?: boolean
          organization_id: string
          relationship_status?: string
          relationship_type_id: string
          source?: string
          to_member_id: string
          updated_at?: string
          updated_by_profile_id?: string | null
          verification_status?: string
          verified_at?: string | null
          verified_by_profile_id?: string | null
        }
        Update: {
          created_at?: string
          created_by_profile_id?: string | null
          effective_from?: string | null
          effective_to?: string | null
          family_id?: string | null
          from_member_id?: string
          id?: string
          is_primary_relationship?: boolean
          organization_id?: string
          relationship_status?: string
          relationship_type_id?: string
          source?: string
          to_member_id?: string
          updated_at?: string
          updated_by_profile_id?: string | null
          verification_status?: string
          verified_at?: string | null
          verified_by_profile_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_family_relationships__created_by"
            columns: ["created_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_family_relationships__families"
            columns: ["organization_id", "family_id"]
            isOneToOne: false
            referencedRelation: "families"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_family_relationships__from_members"
            columns: ["organization_id", "from_member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_family_relationships__relationship_types"
            columns: ["relationship_type_id"]
            isOneToOne: false
            referencedRelation: "family_relationship_types"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_family_relationships__to_members"
            columns: ["organization_id", "to_member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_family_relationships__updated_by"
            columns: ["updated_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_family_relationships__verified_by"
            columns: ["verified_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      governance_node_history: {
        Row: {
          actor_profile_id: string | null
          change_summary: string | null
          change_type: string
          correlation_id: string | null
          created_at: string
          effective_at: string
          governance_node_id: string
          id: string
          new_state: Json | null
          organization_id: string
          previous_state: Json | null
          source: string
        }
        Insert: {
          actor_profile_id?: string | null
          change_summary?: string | null
          change_type: string
          correlation_id?: string | null
          created_at?: string
          effective_at?: string
          governance_node_id: string
          id?: string
          new_state?: Json | null
          organization_id: string
          previous_state?: Json | null
          source?: string
        }
        Update: {
          actor_profile_id?: string | null
          change_summary?: string | null
          change_type?: string
          correlation_id?: string | null
          created_at?: string
          effective_at?: string
          governance_node_id?: string
          id?: string
          new_state?: Json | null
          organization_id?: string
          previous_state?: Json | null
          source?: string
        }
        Relationships: [
          {
            foreignKeyName: "fk_governance_node_history__nodes"
            columns: ["organization_id", "governance_node_id"]
            isOneToOne: false
            referencedRelation: "governance_nodes"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      governance_node_relationships: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          change_reason_code: string | null
          change_summary: string | null
          child_node_id: string
          created_at: string
          created_by: string | null
          effective_from: string
          effective_to: string | null
          ended_at: string | null
          ended_by: string | null
          ending_reason: string | null
          id: string
          inherited_scope_enabled: boolean
          is_primary: boolean
          maximum_inheritance_depth: number | null
          organization_id: string
          parent_node_id: string
          relationship_status: string
          relationship_type: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          change_reason_code?: string | null
          change_summary?: string | null
          child_node_id: string
          created_at?: string
          created_by?: string | null
          effective_from?: string
          effective_to?: string | null
          ended_at?: string | null
          ended_by?: string | null
          ending_reason?: string | null
          id?: string
          inherited_scope_enabled?: boolean
          is_primary?: boolean
          maximum_inheritance_depth?: number | null
          organization_id: string
          parent_node_id: string
          relationship_status?: string
          relationship_type?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          change_reason_code?: string | null
          change_summary?: string | null
          child_node_id?: string
          created_at?: string
          created_by?: string | null
          effective_from?: string
          effective_to?: string | null
          ended_at?: string | null
          ended_by?: string | null
          ending_reason?: string | null
          id?: string
          inherited_scope_enabled?: boolean
          is_primary?: boolean
          maximum_inheritance_depth?: number | null
          organization_id?: string
          parent_node_id?: string
          relationship_status?: string
          relationship_type?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_governance_node_relationships__approved_by"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_governance_node_relationships__child_nodes"
            columns: ["organization_id", "child_node_id"]
            isOneToOne: false
            referencedRelation: "governance_nodes"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_governance_node_relationships__created_by"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_governance_node_relationships__ended_by"
            columns: ["ended_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_governance_node_relationships__parent_nodes"
            columns: ["organization_id", "parent_node_id"]
            isOneToOne: false
            referencedRelation: "governance_nodes"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_governance_node_relationships__updated_by"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      governance_node_types: {
        Row: {
          allows_children: boolean
          allows_leadership_assignment: boolean
          allows_member_assignment: boolean
          code: string
          created_at: string
          created_by: string | null
          description: string | null
          detail_table_name: string | null
          display_order: number
          hierarchy_rank: number
          id: string
          is_active: boolean
          is_household_type: boolean
          is_section_type: boolean
          name: string
          organization_id: string
          requires_detail_record: boolean
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          allows_children?: boolean
          allows_leadership_assignment?: boolean
          allows_member_assignment?: boolean
          code: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          detail_table_name?: string | null
          display_order?: number
          hierarchy_rank: number
          id?: string
          is_active?: boolean
          is_household_type?: boolean
          is_section_type?: boolean
          name: string
          organization_id: string
          requires_detail_record?: boolean
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          allows_children?: boolean
          allows_leadership_assignment?: boolean
          allows_member_assignment?: boolean
          code?: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          detail_table_name?: string | null
          display_order?: number
          hierarchy_rank?: number
          id?: string
          is_active?: boolean
          is_household_type?: boolean
          is_section_type?: boolean
          name?: string
          organization_id?: string
          requires_detail_record?: boolean
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_governance_node_types__organizations"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      governance_nodes: {
        Row: {
          allows_leadership_assignment_override: boolean | null
          allows_member_assignment_override: boolean | null
          archive_reason: string | null
          archived_at: string | null
          archived_by: string | null
          code: string | null
          created_at: string
          created_by: string | null
          description: string | null
          effective_from: string
          effective_to: string | null
          governance_node_type_id: string
          id: string
          lifecycle_status: string
          locale_code: string | null
          maximum_member_count: number | null
          meeting_day_of_week: number | null
          meeting_location_text: string | null
          meeting_start_time: string | null
          meeting_timezone_name: string | null
          metadata: Json
          name: string
          organization_id: string
          primary_city_id: string | null
          public_contact_email: string | null
          public_contact_phone: string | null
          short_name: string | null
          timezone_name: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          allows_leadership_assignment_override?: boolean | null
          allows_member_assignment_override?: boolean | null
          archive_reason?: string | null
          archived_at?: string | null
          archived_by?: string | null
          code?: string | null
          created_at?: string
          created_by?: string | null
          description?: string | null
          effective_from?: string
          effective_to?: string | null
          governance_node_type_id: string
          id?: string
          lifecycle_status?: string
          locale_code?: string | null
          maximum_member_count?: number | null
          meeting_day_of_week?: number | null
          meeting_location_text?: string | null
          meeting_start_time?: string | null
          meeting_timezone_name?: string | null
          metadata?: Json
          name: string
          organization_id: string
          primary_city_id?: string | null
          public_contact_email?: string | null
          public_contact_phone?: string | null
          short_name?: string | null
          timezone_name?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          allows_leadership_assignment_override?: boolean | null
          allows_member_assignment_override?: boolean | null
          archive_reason?: string | null
          archived_at?: string | null
          archived_by?: string | null
          code?: string | null
          created_at?: string
          created_by?: string | null
          description?: string | null
          effective_from?: string
          effective_to?: string | null
          governance_node_type_id?: string
          id?: string
          lifecycle_status?: string
          locale_code?: string | null
          maximum_member_count?: number | null
          meeting_day_of_week?: number | null
          meeting_location_text?: string | null
          meeting_start_time?: string | null
          meeting_timezone_name?: string | null
          metadata?: Json
          name?: string
          organization_id?: string
          primary_city_id?: string | null
          public_contact_email?: string | null
          public_contact_phone?: string | null
          short_name?: string | null
          timezone_name?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_governance_nodes__archived_by"
            columns: ["archived_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_governance_nodes__cities"
            columns: ["primary_city_id"]
            isOneToOne: false
            referencedRelation: "cities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_governance_nodes__created_by"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_governance_nodes__locales"
            columns: ["locale_code"]
            isOneToOne: false
            referencedRelation: "locales"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "fk_governance_nodes__meeting_timezones"
            columns: ["meeting_timezone_name"]
            isOneToOne: false
            referencedRelation: "timezones"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "fk_governance_nodes__node_types"
            columns: ["organization_id", "governance_node_type_id"]
            isOneToOne: false
            referencedRelation: "governance_node_types"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_governance_nodes__organizations"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_governance_nodes__timezones"
            columns: ["timezone_name"]
            isOneToOne: false
            referencedRelation: "timezones"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "fk_governance_nodes__updated_by"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      household_memberships: {
        Row: {
          approved_at: string | null
          approved_by_profile_id: string | null
          created_at: string
          created_by_profile_id: string | null
          effective_from: string
          effective_to: string | null
          ending_reason: string | null
          household_node_id: string
          id: string
          is_primary: boolean
          member_id: string
          membership_role: string
          membership_status: string
          organization_id: string
          placement_source: string
          updated_at: string
          updated_by_profile_id: string | null
        }
        Insert: {
          approved_at?: string | null
          approved_by_profile_id?: string | null
          created_at?: string
          created_by_profile_id?: string | null
          effective_from?: string
          effective_to?: string | null
          ending_reason?: string | null
          household_node_id: string
          id?: string
          is_primary?: boolean
          member_id: string
          membership_role?: string
          membership_status?: string
          organization_id: string
          placement_source?: string
          updated_at?: string
          updated_by_profile_id?: string | null
        }
        Update: {
          approved_at?: string | null
          approved_by_profile_id?: string | null
          created_at?: string
          created_by_profile_id?: string | null
          effective_from?: string
          effective_to?: string | null
          ending_reason?: string | null
          household_node_id?: string
          id?: string
          is_primary?: boolean
          member_id?: string
          membership_role?: string
          membership_status?: string
          organization_id?: string
          placement_source?: string
          updated_at?: string
          updated_by_profile_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_household_memberships__households"
            columns: ["organization_id", "household_node_id"]
            isOneToOne: false
            referencedRelation: "governance_nodes"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_household_memberships__members"
            columns: ["organization_id", "member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      households: {
        Row: {
          accepts_new_members: boolean
          created_at: string
          created_by: string | null
          household_category: string
          id: string
          is_couple_household: boolean
          language_code: string | null
          maximum_member_count: number | null
          meeting_address_id: string | null
          meeting_day_of_week: number | null
          meeting_frequency: string
          meeting_location_text: string | null
          meeting_location_type: string | null
          meeting_start_time: string | null
          meeting_timezone_name: string | null
          organization_id: string
          target_member_count: number | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          accepts_new_members?: boolean
          created_at?: string
          created_by?: string | null
          household_category?: string
          id: string
          is_couple_household?: boolean
          language_code?: string | null
          maximum_member_count?: number | null
          meeting_address_id?: string | null
          meeting_day_of_week?: number | null
          meeting_frequency?: string
          meeting_location_text?: string | null
          meeting_location_type?: string | null
          meeting_start_time?: string | null
          meeting_timezone_name?: string | null
          organization_id: string
          target_member_count?: number | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          accepts_new_members?: boolean
          created_at?: string
          created_by?: string | null
          household_category?: string
          id?: string
          is_couple_household?: boolean
          language_code?: string | null
          maximum_member_count?: number | null
          meeting_address_id?: string | null
          meeting_day_of_week?: number | null
          meeting_frequency?: string
          meeting_location_text?: string | null
          meeting_location_type?: string | null
          meeting_start_time?: string | null
          meeting_timezone_name?: string | null
          organization_id?: string
          target_member_count?: number | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_households__governance_nodes"
            columns: ["organization_id", "id"]
            isOneToOne: false
            referencedRelation: "governance_nodes"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_households__languages"
            columns: ["language_code"]
            isOneToOne: false
            referencedRelation: "languages"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "fk_households__meeting_addresses"
            columns: ["organization_id", "meeting_address_id"]
            isOneToOne: false
            referencedRelation: "addresses"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_households__timezones"
            columns: ["meeting_timezone_name"]
            isOneToOne: false
            referencedRelation: "timezones"
            referencedColumns: ["name"]
          },
        ]
      }
      languages: {
        Row: {
          code: string
          created_at: string
          display_order: number
          is_active: boolean
          name: string
          native_name: string | null
        }
        Insert: {
          code: string
          created_at?: string
          display_order?: number
          is_active?: boolean
          name: string
          native_name?: string | null
        }
        Update: {
          code?: string
          created_at?: string
          display_order?: number
          is_active?: boolean
          name?: string
          native_name?: string | null
        }
        Relationships: []
      }
      leadership_assignment_history: {
        Row: {
          actor_profile_id: string | null
          change_summary: string | null
          change_type: string
          correlation_id: string | null
          created_at: string
          effective_at: string
          id: string
          leadership_assignment_id: string
          new_state: Json | null
          new_status: string
          organization_id: string
          previous_state: Json | null
          previous_status: string | null
          source: string
        }
        Insert: {
          actor_profile_id?: string | null
          change_summary?: string | null
          change_type: string
          correlation_id?: string | null
          created_at?: string
          effective_at?: string
          id?: string
          leadership_assignment_id: string
          new_state?: Json | null
          new_status: string
          organization_id: string
          previous_state?: Json | null
          previous_status?: string | null
          source?: string
        }
        Update: {
          actor_profile_id?: string | null
          change_summary?: string | null
          change_type?: string
          correlation_id?: string | null
          created_at?: string
          effective_at?: string
          id?: string
          leadership_assignment_id?: string
          new_state?: Json | null
          new_status?: string
          organization_id?: string
          previous_state?: Json | null
          previous_status?: string | null
          source?: string
        }
        Relationships: [
          {
            foreignKeyName: "fk_leadership_assignment_history__actor"
            columns: ["actor_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_leadership_assignment_history__assignments"
            columns: ["organization_id", "leadership_assignment_id"]
            isOneToOne: false
            referencedRelation: "leadership_assignments"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      leadership_assignments: {
        Row: {
          accepted_at: string | null
          activated_at: string | null
          appointment_summary: string | null
          appointment_type: string
          approved_at: string | null
          approved_by_profile_id: string | null
          assignment_status: string
          created_at: string
          created_by_profile_id: string | null
          declined_at: string | null
          effective_from: string | null
          effective_to: string | null
          ended_at: string | null
          ended_by_profile_id: string | null
          ending_reason: string | null
          governance_node_id: string
          id: string
          leadership_role_definition_id: string
          member_id: string
          metadata: Json
          organization_id: string
          paired_assignment_id: string | null
          proposed_at: string
          proposed_by_profile_id: string | null
          suspension_ended_at: string | null
          suspension_reason: string | null
          suspension_started_at: string | null
          updated_at: string
          updated_by_profile_id: string | null
        }
        Insert: {
          accepted_at?: string | null
          activated_at?: string | null
          appointment_summary?: string | null
          appointment_type?: string
          approved_at?: string | null
          approved_by_profile_id?: string | null
          assignment_status?: string
          created_at?: string
          created_by_profile_id?: string | null
          declined_at?: string | null
          effective_from?: string | null
          effective_to?: string | null
          ended_at?: string | null
          ended_by_profile_id?: string | null
          ending_reason?: string | null
          governance_node_id: string
          id?: string
          leadership_role_definition_id: string
          member_id: string
          metadata?: Json
          organization_id: string
          paired_assignment_id?: string | null
          proposed_at?: string
          proposed_by_profile_id?: string | null
          suspension_ended_at?: string | null
          suspension_reason?: string | null
          suspension_started_at?: string | null
          updated_at?: string
          updated_by_profile_id?: string | null
        }
        Update: {
          accepted_at?: string | null
          activated_at?: string | null
          appointment_summary?: string | null
          appointment_type?: string
          approved_at?: string | null
          approved_by_profile_id?: string | null
          assignment_status?: string
          created_at?: string
          created_by_profile_id?: string | null
          declined_at?: string | null
          effective_from?: string | null
          effective_to?: string | null
          ended_at?: string | null
          ended_by_profile_id?: string | null
          ending_reason?: string | null
          governance_node_id?: string
          id?: string
          leadership_role_definition_id?: string
          member_id?: string
          metadata?: Json
          organization_id?: string
          paired_assignment_id?: string | null
          proposed_at?: string
          proposed_by_profile_id?: string | null
          suspension_ended_at?: string | null
          suspension_reason?: string | null
          suspension_started_at?: string | null
          updated_at?: string
          updated_by_profile_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_leadership_assignments__approved_by"
            columns: ["approved_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_leadership_assignments__created_by"
            columns: ["created_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_leadership_assignments__ended_by"
            columns: ["ended_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_leadership_assignments__governance_nodes"
            columns: ["organization_id", "governance_node_id"]
            isOneToOne: false
            referencedRelation: "governance_nodes"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_leadership_assignments__members"
            columns: ["organization_id", "member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_leadership_assignments__paired_assignment"
            columns: ["paired_assignment_id"]
            isOneToOne: false
            referencedRelation: "leadership_assignments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_leadership_assignments__proposed_by"
            columns: ["proposed_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_leadership_assignments__role_definitions"
            columns: ["organization_id", "leadership_role_definition_id"]
            isOneToOne: false
            referencedRelation: "leadership_role_definitions"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_leadership_assignments__updated_by"
            columns: ["updated_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      leadership_role_definitions: {
        Row: {
          allows_interim_assignment: boolean
          appointment_scope_type: string
          cardinality_type: string
          code: string
          created_at: string
          created_by: string | null
          creates_application_access_review: boolean
          default_term_months: number | null
          description: string | null
          display_order: number
          id: string
          is_active: boolean
          leadership_category: string
          maximum_assignees: number | null
          maximum_term_months: number | null
          minimum_assignees: number
          name: string
          organization_id: string
          requires_approval: boolean
          requires_couple_pair: boolean
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          allows_interim_assignment?: boolean
          appointment_scope_type?: string
          cardinality_type?: string
          code: string
          created_at?: string
          created_by?: string | null
          creates_application_access_review?: boolean
          default_term_months?: number | null
          description?: string | null
          display_order?: number
          id?: string
          is_active?: boolean
          leadership_category: string
          maximum_assignees?: number | null
          maximum_term_months?: number | null
          minimum_assignees?: number
          name: string
          organization_id: string
          requires_approval?: boolean
          requires_couple_pair?: boolean
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          allows_interim_assignment?: boolean
          appointment_scope_type?: string
          cardinality_type?: string
          code?: string
          created_at?: string
          created_by?: string | null
          creates_application_access_review?: boolean
          default_term_months?: number | null
          description?: string | null
          display_order?: number
          id?: string
          is_active?: boolean
          leadership_category?: string
          maximum_assignees?: number | null
          maximum_term_months?: number | null
          minimum_assignees?: number
          name?: string
          organization_id?: string
          requires_approval?: boolean
          requires_couple_pair?: boolean
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_leadership_role_definitions__organizations"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      leadership_role_node_types: {
        Row: {
          created_at: string
          created_by: string | null
          governance_node_type_id: string
          id: string
          is_active: boolean
          is_primary_mapping: boolean
          leadership_role_definition_id: string
          maximum_node_rank: number | null
          minimum_node_rank: number | null
          organization_id: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          governance_node_type_id: string
          id?: string
          is_active?: boolean
          is_primary_mapping?: boolean
          leadership_role_definition_id: string
          maximum_node_rank?: number | null
          minimum_node_rank?: number | null
          organization_id: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          governance_node_type_id?: string
          id?: string
          is_active?: boolean
          is_primary_mapping?: boolean
          leadership_role_definition_id?: string
          maximum_node_rank?: number | null
          minimum_node_rank?: number | null
          organization_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "fk_leadership_role_node_types__node_types"
            columns: ["organization_id", "governance_node_type_id"]
            isOneToOne: false
            referencedRelation: "governance_node_types"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_leadership_role_node_types__roles"
            columns: ["organization_id", "leadership_role_definition_id"]
            isOneToOne: false
            referencedRelation: "leadership_role_definitions"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      locales: {
        Row: {
          code: string
          country_code: string | null
          created_at: string
          display_order: number
          is_active: boolean
          language_code: string
          name: string
        }
        Insert: {
          code: string
          country_code?: string | null
          created_at?: string
          display_order?: number
          is_active?: boolean
          language_code: string
          name: string
        }
        Update: {
          code?: string
          country_code?: string | null
          created_at?: string
          display_order?: number
          is_active?: boolean
          language_code?: string
          name?: string
        }
        Relationships: [
          {
            foreignKeyName: "locales_country_code_fkey"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "countries"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "locales_language_code_fkey"
            columns: ["language_code"]
            isOneToOne: false
            referencedRelation: "languages"
            referencedColumns: ["code"]
          },
        ]
      }
      login_history: {
        Row: {
          authentication_method: string | null
          created_at: string
          failure_reason_code: string | null
          id: string
          ip_address: unknown
          login_outcome: string
          metadata: Json
          occurred_at: string
          organization_id: string | null
          profile_id: string | null
          session_public_id: string | null
          user_agent: string | null
          user_device_id: string | null
        }
        Insert: {
          authentication_method?: string | null
          created_at?: string
          failure_reason_code?: string | null
          id?: string
          ip_address?: unknown
          login_outcome: string
          metadata?: Json
          occurred_at?: string
          organization_id?: string | null
          profile_id?: string | null
          session_public_id?: string | null
          user_agent?: string | null
          user_device_id?: string | null
        }
        Update: {
          authentication_method?: string | null
          created_at?: string
          failure_reason_code?: string | null
          id?: string
          ip_address?: unknown
          login_outcome?: string
          metadata?: Json
          occurred_at?: string
          organization_id?: string | null
          profile_id?: string | null
          session_public_id?: string | null
          user_agent?: string | null
          user_device_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_login_history__devices"
            columns: ["user_device_id"]
            isOneToOne: false
            referencedRelation: "user_devices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_login_history__organizations"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_login_history__profiles"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      member_addresses: {
        Row: {
          address_id: string
          address_type: string
          created_at: string
          created_by_profile_id: string | null
          effective_from: string | null
          effective_to: string | null
          id: string
          is_mailing_address: boolean
          is_primary: boolean
          is_shared_family_address: boolean
          member_id: string
          organization_id: string
          updated_at: string
          updated_by_profile_id: string | null
          verified_at: string | null
          verified_by_profile_id: string | null
          visibility: string
        }
        Insert: {
          address_id: string
          address_type?: string
          created_at?: string
          created_by_profile_id?: string | null
          effective_from?: string | null
          effective_to?: string | null
          id?: string
          is_mailing_address?: boolean
          is_primary?: boolean
          is_shared_family_address?: boolean
          member_id: string
          organization_id: string
          updated_at?: string
          updated_by_profile_id?: string | null
          verified_at?: string | null
          verified_by_profile_id?: string | null
          visibility?: string
        }
        Update: {
          address_id?: string
          address_type?: string
          created_at?: string
          created_by_profile_id?: string | null
          effective_from?: string | null
          effective_to?: string | null
          id?: string
          is_mailing_address?: boolean
          is_primary?: boolean
          is_shared_family_address?: boolean
          member_id?: string
          organization_id?: string
          updated_at?: string
          updated_by_profile_id?: string | null
          verified_at?: string | null
          verified_by_profile_id?: string | null
          visibility?: string
        }
        Relationships: [
          {
            foreignKeyName: "fk_member_addresses__addresses"
            columns: ["organization_id", "address_id"]
            isOneToOne: false
            referencedRelation: "addresses"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_member_addresses__created_by"
            columns: ["created_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_member_addresses__members"
            columns: ["organization_id", "member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_member_addresses__updated_by"
            columns: ["updated_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_member_addresses__verified_by"
            columns: ["verified_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      member_emails: {
        Row: {
          allows_ministry_email: boolean
          created_at: string
          created_by_profile_id: string | null
          effective_from_at: string
          effective_to_at: string | null
          email_address: string
          email_type: string
          id: string
          is_primary: boolean
          is_shared: boolean
          member_id: string
          normalized_email: string
          organization_id: string
          updated_at: string
          updated_by_profile_id: string | null
          verification_source: string | null
          verification_status: string
          verified_at: string | null
        }
        Insert: {
          allows_ministry_email?: boolean
          created_at?: string
          created_by_profile_id?: string | null
          effective_from_at?: string
          effective_to_at?: string | null
          email_address: string
          email_type?: string
          id?: string
          is_primary?: boolean
          is_shared?: boolean
          member_id: string
          normalized_email: string
          organization_id: string
          updated_at?: string
          updated_by_profile_id?: string | null
          verification_source?: string | null
          verification_status?: string
          verified_at?: string | null
        }
        Update: {
          allows_ministry_email?: boolean
          created_at?: string
          created_by_profile_id?: string | null
          effective_from_at?: string
          effective_to_at?: string | null
          email_address?: string
          email_type?: string
          id?: string
          is_primary?: boolean
          is_shared?: boolean
          member_id?: string
          normalized_email?: string
          organization_id?: string
          updated_at?: string
          updated_by_profile_id?: string | null
          verification_source?: string | null
          verification_status?: string
          verified_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_member_emails__created_by"
            columns: ["created_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_member_emails__members"
            columns: ["organization_id", "member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_member_emails__updated_by"
            columns: ["updated_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      member_governance_assignments: {
        Row: {
          approved_at: string | null
          approved_by_profile_id: string | null
          assignment_basis: string
          assignment_status: string
          assignment_type: string
          created_at: string
          created_by_profile_id: string | null
          effective_from: string
          effective_to: string | null
          ending_reason: string | null
          governance_node_id: string
          id: string
          is_primary: boolean
          member_id: string
          organization_id: string
          updated_at: string
          updated_by_profile_id: string | null
        }
        Insert: {
          approved_at?: string | null
          approved_by_profile_id?: string | null
          assignment_basis?: string
          assignment_status?: string
          assignment_type?: string
          created_at?: string
          created_by_profile_id?: string | null
          effective_from?: string
          effective_to?: string | null
          ending_reason?: string | null
          governance_node_id: string
          id?: string
          is_primary?: boolean
          member_id: string
          organization_id: string
          updated_at?: string
          updated_by_profile_id?: string | null
        }
        Update: {
          approved_at?: string | null
          approved_by_profile_id?: string | null
          assignment_basis?: string
          assignment_status?: string
          assignment_type?: string
          created_at?: string
          created_by_profile_id?: string | null
          effective_from?: string
          effective_to?: string | null
          ending_reason?: string | null
          governance_node_id?: string
          id?: string
          is_primary?: boolean
          member_id?: string
          organization_id?: string
          updated_at?: string
          updated_by_profile_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_member_governance_assignments__members"
            columns: ["organization_id", "member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_member_governance_assignments__nodes"
            columns: ["organization_id", "governance_node_id"]
            isOneToOne: false
            referencedRelation: "governance_nodes"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      member_id_cards: {
        Row: {
          card_public_id: string
          card_status: string
          card_version: number
          created_at: string
          expires_on: string | null
          id: string
          issued_at: string
          issued_by_profile_id: string | null
          member_id: string
          member_qr_token_id: string
          organization_id: string
          rendered_file_storage_path: string | null
          revocation_reason: string | null
          revoked_at: string | null
          revoked_by_profile_id: string | null
        }
        Insert: {
          card_public_id?: string
          card_status?: string
          card_version?: number
          created_at?: string
          expires_on?: string | null
          id?: string
          issued_at?: string
          issued_by_profile_id?: string | null
          member_id: string
          member_qr_token_id: string
          organization_id: string
          rendered_file_storage_path?: string | null
          revocation_reason?: string | null
          revoked_at?: string | null
          revoked_by_profile_id?: string | null
        }
        Update: {
          card_public_id?: string
          card_status?: string
          card_version?: number
          created_at?: string
          expires_on?: string | null
          id?: string
          issued_at?: string
          issued_by_profile_id?: string | null
          member_id?: string
          member_qr_token_id?: string
          organization_id?: string
          rendered_file_storage_path?: string | null
          revocation_reason?: string | null
          revoked_at?: string | null
          revoked_by_profile_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_member_id_cards__issued_by"
            columns: ["issued_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_member_id_cards__members"
            columns: ["organization_id", "member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_member_id_cards__revoked_by"
            columns: ["revoked_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_member_id_cards__tokens"
            columns: ["member_qr_token_id"]
            isOneToOne: false
            referencedRelation: "member_qr_tokens"
            referencedColumns: ["id"]
          },
        ]
      }
      member_identifiers: {
        Row: {
          created_at: string
          created_by_profile_id: string | null
          effective_from: string | null
          effective_to: string | null
          id: string
          identifier_type: string
          identifier_value: string
          is_primary: boolean
          member_id: string
          metadata: Json
          normalized_value: string
          organization_id: string
          source_system: string | null
          verification_status: string
          verified_at: string | null
          verified_by_profile_id: string | null
        }
        Insert: {
          created_at?: string
          created_by_profile_id?: string | null
          effective_from?: string | null
          effective_to?: string | null
          id?: string
          identifier_type: string
          identifier_value: string
          is_primary?: boolean
          member_id: string
          metadata?: Json
          normalized_value: string
          organization_id: string
          source_system?: string | null
          verification_status?: string
          verified_at?: string | null
          verified_by_profile_id?: string | null
        }
        Update: {
          created_at?: string
          created_by_profile_id?: string | null
          effective_from?: string | null
          effective_to?: string | null
          id?: string
          identifier_type?: string
          identifier_value?: string
          is_primary?: boolean
          member_id?: string
          metadata?: Json
          normalized_value?: string
          organization_id?: string
          source_system?: string | null
          verification_status?: string
          verified_at?: string | null
          verified_by_profile_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_member_identifiers__created_by"
            columns: ["created_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_member_identifiers__members"
            columns: ["organization_id", "member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_member_identifiers__verified_by"
            columns: ["verified_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      member_merge_actions: {
        Row: {
          action_status: string
          action_type: string
          after_state: Json | null
          before_state: Json | null
          blocking_issue: string | null
          created_at: string
          id: string
          member_merge_request_id: string
          organization_id: string
          processed_at: string | null
          processed_by_profile_id: string | null
          target_record_id: string | null
          target_table: string | null
        }
        Insert: {
          action_status?: string
          action_type: string
          after_state?: Json | null
          before_state?: Json | null
          blocking_issue?: string | null
          created_at?: string
          id?: string
          member_merge_request_id: string
          organization_id: string
          processed_at?: string | null
          processed_by_profile_id?: string | null
          target_record_id?: string | null
          target_table?: string | null
        }
        Update: {
          action_status?: string
          action_type?: string
          after_state?: Json | null
          before_state?: Json | null
          blocking_issue?: string | null
          created_at?: string
          id?: string
          member_merge_request_id?: string
          organization_id?: string
          processed_at?: string | null
          processed_by_profile_id?: string | null
          target_record_id?: string | null
          target_table?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_member_merge_actions__requests"
            columns: ["organization_id", "member_merge_request_id"]
            isOneToOne: false
            referencedRelation: "member_merge_requests"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      member_merge_history: {
        Row: {
          correlation_id: string
          created_at: string
          id: string
          member_merge_request_id: string
          merged_at: string
          merged_by_profile_id: string | null
          organization_id: string
          retired_member_id: string
          summary: string | null
          survivor_member_id: string
        }
        Insert: {
          correlation_id?: string
          created_at?: string
          id?: string
          member_merge_request_id: string
          merged_at?: string
          merged_by_profile_id?: string | null
          organization_id: string
          retired_member_id: string
          summary?: string | null
          survivor_member_id: string
        }
        Update: {
          correlation_id?: string
          created_at?: string
          id?: string
          member_merge_request_id?: string
          merged_at?: string
          merged_by_profile_id?: string | null
          organization_id?: string
          retired_member_id?: string
          summary?: string | null
          survivor_member_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "fk_member_merge_history__requests"
            columns: ["organization_id", "member_merge_request_id"]
            isOneToOne: false
            referencedRelation: "member_merge_requests"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_member_merge_history__retired"
            columns: ["organization_id", "retired_member_id"]
            isOneToOne: true
            referencedRelation: "members"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_member_merge_history__survivor"
            columns: ["organization_id", "survivor_member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      member_merge_requests: {
        Row: {
          approved_at: string | null
          approved_by_profile_id: string | null
          created_at: string
          duplicate_member_candidate_id: string | null
          executed_at: string | null
          executed_by_profile_id: string | null
          id: string
          merge_summary: string | null
          organization_id: string
          rejection_reason: string | null
          request_status: string
          requested_at: string
          requested_by_profile_id: string | null
          retiring_member_id: string
          reviewed_at: string | null
          reviewed_by_profile_id: string | null
          survivor_member_id: string
          updated_at: string
        }
        Insert: {
          approved_at?: string | null
          approved_by_profile_id?: string | null
          created_at?: string
          duplicate_member_candidate_id?: string | null
          executed_at?: string | null
          executed_by_profile_id?: string | null
          id?: string
          merge_summary?: string | null
          organization_id: string
          rejection_reason?: string | null
          request_status?: string
          requested_at?: string
          requested_by_profile_id?: string | null
          retiring_member_id: string
          reviewed_at?: string | null
          reviewed_by_profile_id?: string | null
          survivor_member_id: string
          updated_at?: string
        }
        Update: {
          approved_at?: string | null
          approved_by_profile_id?: string | null
          created_at?: string
          duplicate_member_candidate_id?: string | null
          executed_at?: string | null
          executed_by_profile_id?: string | null
          id?: string
          merge_summary?: string | null
          organization_id?: string
          rejection_reason?: string | null
          request_status?: string
          requested_at?: string
          requested_by_profile_id?: string | null
          retiring_member_id?: string
          reviewed_at?: string | null
          reviewed_by_profile_id?: string | null
          survivor_member_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "fk_member_merge_requests__candidate"
            columns: ["duplicate_member_candidate_id"]
            isOneToOne: false
            referencedRelation: "duplicate_member_candidates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_member_merge_requests__retiring"
            columns: ["organization_id", "retiring_member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_member_merge_requests__survivor"
            columns: ["organization_id", "survivor_member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      member_names: {
        Row: {
          created_at: string
          created_by_profile_id: string | null
          effective_from: string | null
          effective_to: string | null
          family_name: string | null
          full_name: string
          given_names: string | null
          id: string
          is_primary: boolean
          is_searchable: boolean
          language_code: string | null
          member_id: string
          middle_names: string | null
          name_type: string
          native_script_name: string | null
          organization_id: string
          preferred_given_name: string | null
          prefix: string | null
          sort_name: string
          suffix: string | null
          updated_at: string
          updated_by_profile_id: string | null
          verification_status: string
          verified_at: string | null
          verified_by_profile_id: string | null
        }
        Insert: {
          created_at?: string
          created_by_profile_id?: string | null
          effective_from?: string | null
          effective_to?: string | null
          family_name?: string | null
          full_name: string
          given_names?: string | null
          id?: string
          is_primary?: boolean
          is_searchable?: boolean
          language_code?: string | null
          member_id: string
          middle_names?: string | null
          name_type?: string
          native_script_name?: string | null
          organization_id: string
          preferred_given_name?: string | null
          prefix?: string | null
          sort_name: string
          suffix?: string | null
          updated_at?: string
          updated_by_profile_id?: string | null
          verification_status?: string
          verified_at?: string | null
          verified_by_profile_id?: string | null
        }
        Update: {
          created_at?: string
          created_by_profile_id?: string | null
          effective_from?: string | null
          effective_to?: string | null
          family_name?: string | null
          full_name?: string
          given_names?: string | null
          id?: string
          is_primary?: boolean
          is_searchable?: boolean
          language_code?: string | null
          member_id?: string
          middle_names?: string | null
          name_type?: string
          native_script_name?: string | null
          organization_id?: string
          preferred_given_name?: string | null
          prefix?: string | null
          sort_name?: string
          suffix?: string | null
          updated_at?: string
          updated_by_profile_id?: string | null
          verification_status?: string
          verified_at?: string | null
          verified_by_profile_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_member_names__created_by"
            columns: ["created_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_member_names__languages"
            columns: ["language_code"]
            isOneToOne: false
            referencedRelation: "languages"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "fk_member_names__members"
            columns: ["organization_id", "member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_member_names__updated_by"
            columns: ["updated_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_member_names__verified_by"
            columns: ["verified_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      member_notes: {
        Row: {
          created_at: string
          created_by_profile_id: string
          id: string
          is_resolved: boolean
          member_id: string
          note_text: string
          note_type: string
          organization_id: string
          resolution_summary: string | null
          resolved_at: string | null
          resolved_by_profile_id: string | null
          specific_profile_id: string | null
          updated_at: string
          updated_by_profile_id: string | null
          visibility_scope: string
        }
        Insert: {
          created_at?: string
          created_by_profile_id: string
          id?: string
          is_resolved?: boolean
          member_id: string
          note_text: string
          note_type: string
          organization_id: string
          resolution_summary?: string | null
          resolved_at?: string | null
          resolved_by_profile_id?: string | null
          specific_profile_id?: string | null
          updated_at?: string
          updated_by_profile_id?: string | null
          visibility_scope?: string
        }
        Update: {
          created_at?: string
          created_by_profile_id?: string
          id?: string
          is_resolved?: boolean
          member_id?: string
          note_text?: string
          note_type?: string
          organization_id?: string
          resolution_summary?: string | null
          resolved_at?: string | null
          resolved_by_profile_id?: string | null
          specific_profile_id?: string | null
          updated_at?: string
          updated_by_profile_id?: string | null
          visibility_scope?: string
        }
        Relationships: [
          {
            foreignKeyName: "fk_member_notes__created_by"
            columns: ["created_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_member_notes__members"
            columns: ["organization_id", "member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_member_notes__resolved_by"
            columns: ["resolved_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_member_notes__specific_profile"
            columns: ["specific_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_member_notes__updated_by"
            columns: ["updated_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      member_phones: {
        Row: {
          allows_messaging_apps: boolean
          allows_sms: boolean
          allows_voice_calls: boolean
          country_code: string | null
          created_at: string
          created_by_profile_id: string | null
          effective_from_at: string
          effective_to_at: string | null
          extension: string | null
          id: string
          is_primary: boolean
          is_shared: boolean
          member_id: string
          normalized_e164: string | null
          organization_id: string
          phone_number: string
          phone_type: string
          updated_at: string
          updated_by_profile_id: string | null
          verification_status: string
          verified_at: string | null
        }
        Insert: {
          allows_messaging_apps?: boolean
          allows_sms?: boolean
          allows_voice_calls?: boolean
          country_code?: string | null
          created_at?: string
          created_by_profile_id?: string | null
          effective_from_at?: string
          effective_to_at?: string | null
          extension?: string | null
          id?: string
          is_primary?: boolean
          is_shared?: boolean
          member_id: string
          normalized_e164?: string | null
          organization_id: string
          phone_number: string
          phone_type?: string
          updated_at?: string
          updated_by_profile_id?: string | null
          verification_status?: string
          verified_at?: string | null
        }
        Update: {
          allows_messaging_apps?: boolean
          allows_sms?: boolean
          allows_voice_calls?: boolean
          country_code?: string | null
          created_at?: string
          created_by_profile_id?: string | null
          effective_from_at?: string
          effective_to_at?: string | null
          extension?: string | null
          id?: string
          is_primary?: boolean
          is_shared?: boolean
          member_id?: string
          normalized_e164?: string | null
          organization_id?: string
          phone_number?: string
          phone_type?: string
          updated_at?: string
          updated_by_profile_id?: string | null
          verification_status?: string
          verified_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_member_phones__countries"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "countries"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "fk_member_phones__created_by"
            columns: ["created_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_member_phones__members"
            columns: ["organization_id", "member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_member_phones__updated_by"
            columns: ["updated_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      member_qr_token_events: {
        Row: {
          actor_profile_id: string | null
          correlation_id: string | null
          created_at: string
          device_id: string | null
          event_summary: string | null
          event_type: string
          id: string
          member_id: string
          member_qr_token_id: string
          metadata: Json
          occurred_at: string
          organization_id: string
          reason_code: string | null
        }
        Insert: {
          actor_profile_id?: string | null
          correlation_id?: string | null
          created_at?: string
          device_id?: string | null
          event_summary?: string | null
          event_type: string
          id?: string
          member_id: string
          member_qr_token_id: string
          metadata?: Json
          occurred_at?: string
          organization_id: string
          reason_code?: string | null
        }
        Update: {
          actor_profile_id?: string | null
          correlation_id?: string | null
          created_at?: string
          device_id?: string | null
          event_summary?: string | null
          event_type?: string
          id?: string
          member_id?: string
          member_qr_token_id?: string
          metadata?: Json
          occurred_at?: string
          organization_id?: string
          reason_code?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_member_qr_token_events__actor"
            columns: ["actor_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_member_qr_token_events__device"
            columns: ["device_id"]
            isOneToOne: false
            referencedRelation: "user_devices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_member_qr_token_events__members"
            columns: ["organization_id", "member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_member_qr_token_events__tokens"
            columns: ["member_qr_token_id"]
            isOneToOne: false
            referencedRelation: "member_qr_tokens"
            referencedColumns: ["id"]
          },
        ]
      }
      member_qr_tokens: {
        Row: {
          created_at: string
          expires_at: string | null
          id: string
          is_primary: boolean
          issued_at: string
          issued_by_profile_id: string | null
          last_used_at: string | null
          member_id: string
          organization_id: string
          replaced_by_token_id: string | null
          revocation_reason: string | null
          revoked_at: string | null
          revoked_by_profile_id: string | null
          token_hash: string
          token_public_id: string
          token_status: string
          token_version: number
          use_count: number
        }
        Insert: {
          created_at?: string
          expires_at?: string | null
          id?: string
          is_primary?: boolean
          issued_at?: string
          issued_by_profile_id?: string | null
          last_used_at?: string | null
          member_id: string
          organization_id: string
          replaced_by_token_id?: string | null
          revocation_reason?: string | null
          revoked_at?: string | null
          revoked_by_profile_id?: string | null
          token_hash: string
          token_public_id?: string
          token_status?: string
          token_version?: number
          use_count?: number
        }
        Update: {
          created_at?: string
          expires_at?: string | null
          id?: string
          is_primary?: boolean
          issued_at?: string
          issued_by_profile_id?: string | null
          last_used_at?: string | null
          member_id?: string
          organization_id?: string
          replaced_by_token_id?: string | null
          revocation_reason?: string | null
          revoked_at?: string | null
          revoked_by_profile_id?: string | null
          token_hash?: string
          token_public_id?: string
          token_status?: string
          token_version?: number
          use_count?: number
        }
        Relationships: [
          {
            foreignKeyName: "fk_member_qr_tokens__issued_by"
            columns: ["issued_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_member_qr_tokens__members"
            columns: ["organization_id", "member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_member_qr_tokens__replacement"
            columns: ["replaced_by_token_id"]
            isOneToOne: false
            referencedRelation: "member_qr_tokens"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_member_qr_tokens__revoked_by"
            columns: ["revoked_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      member_status_history: {
        Row: {
          approved_at: string | null
          approved_by_profile_id: string | null
          change_reason_code: string | null
          change_summary: string | null
          effective_from_at: string
          effective_to_at: string | null
          id: string
          member_id: string
          member_status_id: string
          metadata: Json
          organization_id: string
          recorded_at: string
          recorded_by_profile_id: string | null
          source: string
        }
        Insert: {
          approved_at?: string | null
          approved_by_profile_id?: string | null
          change_reason_code?: string | null
          change_summary?: string | null
          effective_from_at?: string
          effective_to_at?: string | null
          id?: string
          member_id: string
          member_status_id: string
          metadata?: Json
          organization_id: string
          recorded_at?: string
          recorded_by_profile_id?: string | null
          source?: string
        }
        Update: {
          approved_at?: string | null
          approved_by_profile_id?: string | null
          change_reason_code?: string | null
          change_summary?: string | null
          effective_from_at?: string
          effective_to_at?: string | null
          id?: string
          member_id?: string
          member_status_id?: string
          metadata?: Json
          organization_id?: string
          recorded_at?: string
          recorded_by_profile_id?: string | null
          source?: string
        }
        Relationships: [
          {
            foreignKeyName: "fk_member_status_history__approved_by"
            columns: ["approved_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_member_status_history__members"
            columns: ["organization_id", "member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_member_status_history__recorded_by"
            columns: ["recorded_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_member_status_history__statuses"
            columns: ["organization_id", "member_status_id"]
            isOneToOne: false
            referencedRelation: "member_statuses"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      member_statuses: {
        Row: {
          allows_event_registration: boolean
          allows_household_assignment: boolean
          allows_leadership_assignment: boolean
          allows_section_assignment: boolean
          code: string
          created_at: string
          created_by_profile_id: string | null
          description: string | null
          display_order: number
          id: string
          is_active: boolean
          is_active_membership: boolean
          is_terminal: boolean
          name: string
          organization_id: string
          requires_followup_review: boolean
          status_category: string
          updated_at: string
          updated_by_profile_id: string | null
        }
        Insert: {
          allows_event_registration?: boolean
          allows_household_assignment?: boolean
          allows_leadership_assignment?: boolean
          allows_section_assignment?: boolean
          code: string
          created_at?: string
          created_by_profile_id?: string | null
          description?: string | null
          display_order?: number
          id?: string
          is_active?: boolean
          is_active_membership?: boolean
          is_terminal?: boolean
          name: string
          organization_id: string
          requires_followup_review?: boolean
          status_category: string
          updated_at?: string
          updated_by_profile_id?: string | null
        }
        Update: {
          allows_event_registration?: boolean
          allows_household_assignment?: boolean
          allows_leadership_assignment?: boolean
          allows_section_assignment?: boolean
          code?: string
          created_at?: string
          created_by_profile_id?: string | null
          description?: string | null
          display_order?: number
          id?: string
          is_active?: boolean
          is_active_membership?: boolean
          is_terminal?: boolean
          name?: string
          organization_id?: string
          requires_followup_review?: boolean
          status_category?: string
          updated_at?: string
          updated_by_profile_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_member_statuses__created_by"
            columns: ["created_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_member_statuses__organizations"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_member_statuses__updated_by"
            columns: ["updated_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      members: {
        Row: {
          archive_reason: string | null
          archived_at: string | null
          archived_by_profile_id: string | null
          birth_date: string | null
          birth_date_precision: string | null
          civil_status: string | null
          created_at: string
          created_by_profile_id: string | null
          data_quality_status: string
          deceased_on: string | null
          deceased_on_precision: string | null
          directory_visibility: string
          display_name: string
          first_contact_on: string | null
          home_country_code: string | null
          id: string
          is_deceased: boolean
          joined_on: string | null
          last_verified_at: string | null
          last_verified_by_profile_id: string | null
          member_number: string | null
          membership_status_id: string
          organization_id: string
          parish_id: string | null
          preferred_language_code: string | null
          preferred_name: string
          primary_governance_node_id: string | null
          primary_household_node_id: string | null
          primary_section_node_id: string | null
          profile_photo_storage_path: string | null
          record_status: string
          sex: string | null
          sort_name: string
          updated_at: string
          updated_by_profile_id: string | null
        }
        Insert: {
          archive_reason?: string | null
          archived_at?: string | null
          archived_by_profile_id?: string | null
          birth_date?: string | null
          birth_date_precision?: string | null
          civil_status?: string | null
          created_at?: string
          created_by_profile_id?: string | null
          data_quality_status?: string
          deceased_on?: string | null
          deceased_on_precision?: string | null
          directory_visibility?: string
          display_name: string
          first_contact_on?: string | null
          home_country_code?: string | null
          id?: string
          is_deceased?: boolean
          joined_on?: string | null
          last_verified_at?: string | null
          last_verified_by_profile_id?: string | null
          member_number?: string | null
          membership_status_id: string
          organization_id: string
          parish_id?: string | null
          preferred_language_code?: string | null
          preferred_name: string
          primary_governance_node_id?: string | null
          primary_household_node_id?: string | null
          primary_section_node_id?: string | null
          profile_photo_storage_path?: string | null
          record_status?: string
          sex?: string | null
          sort_name: string
          updated_at?: string
          updated_by_profile_id?: string | null
        }
        Update: {
          archive_reason?: string | null
          archived_at?: string | null
          archived_by_profile_id?: string | null
          birth_date?: string | null
          birth_date_precision?: string | null
          civil_status?: string | null
          created_at?: string
          created_by_profile_id?: string | null
          data_quality_status?: string
          deceased_on?: string | null
          deceased_on_precision?: string | null
          directory_visibility?: string
          display_name?: string
          first_contact_on?: string | null
          home_country_code?: string | null
          id?: string
          is_deceased?: boolean
          joined_on?: string | null
          last_verified_at?: string | null
          last_verified_by_profile_id?: string | null
          member_number?: string | null
          membership_status_id?: string
          organization_id?: string
          parish_id?: string | null
          preferred_language_code?: string | null
          preferred_name?: string
          primary_governance_node_id?: string | null
          primary_household_node_id?: string | null
          primary_section_node_id?: string | null
          profile_photo_storage_path?: string | null
          record_status?: string
          sex?: string | null
          sort_name?: string
          updated_at?: string
          updated_by_profile_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_members__archived_by"
            columns: ["archived_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_members__created_by"
            columns: ["created_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_members__home_countries"
            columns: ["home_country_code"]
            isOneToOne: false
            referencedRelation: "countries"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "fk_members__last_verified_by"
            columns: ["last_verified_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_members__member_statuses"
            columns: ["organization_id", "membership_status_id"]
            isOneToOne: false
            referencedRelation: "member_statuses"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_members__organizations"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_members__preferred_languages"
            columns: ["preferred_language_code"]
            isOneToOne: false
            referencedRelation: "languages"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "fk_members__primary_governance_nodes"
            columns: ["organization_id", "primary_governance_node_id"]
            isOneToOne: false
            referencedRelation: "governance_nodes"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_members__primary_household_nodes"
            columns: ["organization_id", "primary_household_node_id"]
            isOneToOne: false
            referencedRelation: "governance_nodes"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_members__primary_section_nodes"
            columns: ["organization_id", "primary_section_node_id"]
            isOneToOne: false
            referencedRelation: "governance_nodes"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_members__updated_by"
            columns: ["updated_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      number_sequences: {
        Row: {
          created_at: string
          created_by: string | null
          current_value: number
          id: string
          increment_by: number
          is_active: boolean
          last_reset_year: number | null
          minimum_digits: number
          organization_id: string
          prefix: string
          reset_policy: string
          sequence_code: string
          suffix: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          current_value?: number
          id?: string
          increment_by?: number
          is_active?: boolean
          last_reset_year?: number | null
          minimum_digits?: number
          organization_id: string
          prefix?: string
          reset_policy?: string
          sequence_code: string
          suffix?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          current_value?: number
          id?: string
          increment_by?: number
          is_active?: boolean
          last_reset_year?: number | null
          minimum_digits?: number
          organization_id?: string
          prefix?: string
          reset_policy?: string
          sequence_code?: string
          suffix?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_number_sequences__created_by"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_number_sequences__updated_by"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "number_sequences_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_features: {
        Row: {
          configuration: Json
          created_at: string
          created_by: string | null
          disabled_at: string | null
          disabled_by: string | null
          enabled_at: string | null
          enabled_by: string | null
          feature_code: string
          id: string
          is_enabled: boolean
          organization_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          configuration?: Json
          created_at?: string
          created_by?: string | null
          disabled_at?: string | null
          disabled_by?: string | null
          enabled_at?: string | null
          enabled_by?: string | null
          feature_code: string
          id?: string
          is_enabled?: boolean
          organization_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          configuration?: Json
          created_at?: string
          created_by?: string | null
          disabled_at?: string | null
          disabled_by?: string | null
          enabled_at?: string | null
          enabled_by?: string | null
          feature_code?: string
          id?: string
          is_enabled?: boolean
          organization_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_organization_features__created_by"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_organization_features__disabled_by"
            columns: ["disabled_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_organization_features__enabled_by"
            columns: ["enabled_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_organization_features__updated_by"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organization_features_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_settings: {
        Row: {
          created_at: string
          created_by: string | null
          data_classification_code: string
          effective_from_at: string
          effective_to_at: string | null
          id: string
          organization_id: string
          setting_key: string
          setting_value: Json
          updated_at: string
          updated_by: string | null
          value_type: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          data_classification_code?: string
          effective_from_at?: string
          effective_to_at?: string | null
          id?: string
          organization_id: string
          setting_key: string
          setting_value?: Json
          updated_at?: string
          updated_by?: string | null
          value_type?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          data_classification_code?: string
          effective_from_at?: string
          effective_to_at?: string | null
          id?: string
          organization_id?: string
          setting_key?: string
          setting_value?: Json
          updated_at?: string
          updated_by?: string | null
          value_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "fk_organization_settings__created_by"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_organization_settings__updated_by"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organization_settings_data_classification_code_fkey"
            columns: ["data_classification_code"]
            isOneToOne: false
            referencedRelation: "data_classifications"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "organization_settings_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organizations: {
        Row: {
          archive_reason: string | null
          archived_at: string | null
          archived_by: string | null
          code: string
          contact_email: string | null
          contact_phone: string | null
          country_code: string | null
          created_at: string
          created_by: string | null
          default_currency_code: string | null
          default_locale_code: string | null
          default_timezone_name: string | null
          description: string | null
          effective_from: string
          effective_to: string | null
          id: string
          lifecycle_status: string
          logo_storage_path: string | null
          name: string
          organization_type: string
          parent_organization_id: string | null
          short_name: string | null
          updated_at: string
          updated_by: string | null
          website_url: string | null
        }
        Insert: {
          archive_reason?: string | null
          archived_at?: string | null
          archived_by?: string | null
          code: string
          contact_email?: string | null
          contact_phone?: string | null
          country_code?: string | null
          created_at?: string
          created_by?: string | null
          default_currency_code?: string | null
          default_locale_code?: string | null
          default_timezone_name?: string | null
          description?: string | null
          effective_from?: string
          effective_to?: string | null
          id?: string
          lifecycle_status?: string
          logo_storage_path?: string | null
          name: string
          organization_type?: string
          parent_organization_id?: string | null
          short_name?: string | null
          updated_at?: string
          updated_by?: string | null
          website_url?: string | null
        }
        Update: {
          archive_reason?: string | null
          archived_at?: string | null
          archived_by?: string | null
          code?: string
          contact_email?: string | null
          contact_phone?: string | null
          country_code?: string | null
          created_at?: string
          created_by?: string | null
          default_currency_code?: string | null
          default_locale_code?: string | null
          default_timezone_name?: string | null
          description?: string | null
          effective_from?: string
          effective_to?: string | null
          id?: string
          lifecycle_status?: string
          logo_storage_path?: string | null
          name?: string
          organization_type?: string
          parent_organization_id?: string | null
          short_name?: string | null
          updated_at?: string
          updated_by?: string | null
          website_url?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_organizations__archived_by"
            columns: ["archived_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_organizations__created_by"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_organizations__updated_by"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organizations_country_code_fkey"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "countries"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "organizations_default_currency_code_fkey"
            columns: ["default_currency_code"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "organizations_default_locale_code_fkey"
            columns: ["default_locale_code"]
            isOneToOne: false
            referencedRelation: "locales"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "organizations_default_timezone_name_fkey"
            columns: ["default_timezone_name"]
            isOneToOne: false
            referencedRelation: "timezones"
            referencedColumns: ["name"]
          },
          {
            foreignKeyName: "organizations_parent_organization_id_fkey"
            columns: ["parent_organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      pastoral_responsibility_scopes: {
        Row: {
          approved_at: string | null
          approved_by_profile_id: string | null
          created_at: string
          created_by_profile_id: string | null
          effective_from_at: string | null
          effective_to_at: string | null
          id: string
          includes_descendants: boolean
          leadership_assignment_id: string | null
          maximum_descendant_depth: number | null
          member_id: string | null
          organization_id: string
          profile_id: string | null
          responsibility_holder_type: string
          responsibility_status: string
          responsibility_summary: string | null
          responsibility_type: string
          revocation_reason: string | null
          revoked_at: string | null
          revoked_by_profile_id: string | null
          root_governance_node_id: string
          scope_effect: string
          section_node_id: string | null
          updated_at: string
          updated_by_profile_id: string | null
        }
        Insert: {
          approved_at?: string | null
          approved_by_profile_id?: string | null
          created_at?: string
          created_by_profile_id?: string | null
          effective_from_at?: string | null
          effective_to_at?: string | null
          id?: string
          includes_descendants?: boolean
          leadership_assignment_id?: string | null
          maximum_descendant_depth?: number | null
          member_id?: string | null
          organization_id: string
          profile_id?: string | null
          responsibility_holder_type: string
          responsibility_status?: string
          responsibility_summary?: string | null
          responsibility_type: string
          revocation_reason?: string | null
          revoked_at?: string | null
          revoked_by_profile_id?: string | null
          root_governance_node_id: string
          scope_effect?: string
          section_node_id?: string | null
          updated_at?: string
          updated_by_profile_id?: string | null
        }
        Update: {
          approved_at?: string | null
          approved_by_profile_id?: string | null
          created_at?: string
          created_by_profile_id?: string | null
          effective_from_at?: string | null
          effective_to_at?: string | null
          id?: string
          includes_descendants?: boolean
          leadership_assignment_id?: string | null
          maximum_descendant_depth?: number | null
          member_id?: string | null
          organization_id?: string
          profile_id?: string | null
          responsibility_holder_type?: string
          responsibility_status?: string
          responsibility_summary?: string | null
          responsibility_type?: string
          revocation_reason?: string | null
          revoked_at?: string | null
          revoked_by_profile_id?: string | null
          root_governance_node_id?: string
          scope_effect?: string
          section_node_id?: string | null
          updated_at?: string
          updated_by_profile_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_pastoral_responsibility_scopes__approved_by"
            columns: ["approved_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_pastoral_responsibility_scopes__created_by"
            columns: ["created_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_pastoral_responsibility_scopes__leadership_assignments"
            columns: ["organization_id", "leadership_assignment_id"]
            isOneToOne: false
            referencedRelation: "leadership_assignments"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_pastoral_responsibility_scopes__members"
            columns: ["organization_id", "member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_pastoral_responsibility_scopes__organizations"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_pastoral_responsibility_scopes__profiles"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_pastoral_responsibility_scopes__revoked_by"
            columns: ["revoked_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_pastoral_responsibility_scopes__root_nodes"
            columns: ["organization_id", "root_governance_node_id"]
            isOneToOne: false
            referencedRelation: "governance_nodes"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_pastoral_responsibility_scopes__section_nodes"
            columns: ["organization_id", "section_node_id"]
            isOneToOne: false
            referencedRelation: "governance_nodes"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_pastoral_responsibility_scopes__updated_by"
            columns: ["updated_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      permissions: {
        Row: {
          action_code: string
          code: string
          created_at: string
          description: string | null
          domain_code: string
          id: string
          is_active: boolean
          name: string
          requires_access_logging: boolean
          requires_access_reason: boolean
          risk_level: string
          scope_type: string
          updated_at: string
        }
        Insert: {
          action_code: string
          code: string
          created_at?: string
          description?: string | null
          domain_code: string
          id?: string
          is_active?: boolean
          name: string
          requires_access_logging?: boolean
          requires_access_reason?: boolean
          risk_level?: string
          scope_type?: string
          updated_at?: string
        }
        Update: {
          action_code?: string
          code?: string
          created_at?: string
          description?: string | null
          domain_code?: string
          id?: string
          is_active?: boolean
          name?: string
          requires_access_logging?: boolean
          requires_access_reason?: boolean
          risk_level?: string
          scope_type?: string
          updated_at?: string
        }
        Relationships: []
      }
      profile_member_links: {
        Row: {
          created_at: string
          ended_at: string | null
          ended_by_profile_id: string | null
          ending_reason: string | null
          id: string
          is_primary: boolean
          link_status: string
          link_type: string
          member_id: string
          organization_id: string
          profile_id: string
          proposed_at: string
          proposed_by_profile_id: string | null
          updated_at: string
          updated_by_profile_id: string | null
          verification_method: string | null
          verification_summary: string | null
          verified_at: string | null
          verified_by_profile_id: string | null
        }
        Insert: {
          created_at?: string
          ended_at?: string | null
          ended_by_profile_id?: string | null
          ending_reason?: string | null
          id?: string
          is_primary?: boolean
          link_status?: string
          link_type?: string
          member_id: string
          organization_id: string
          profile_id: string
          proposed_at?: string
          proposed_by_profile_id?: string | null
          updated_at?: string
          updated_by_profile_id?: string | null
          verification_method?: string | null
          verification_summary?: string | null
          verified_at?: string | null
          verified_by_profile_id?: string | null
        }
        Update: {
          created_at?: string
          ended_at?: string | null
          ended_by_profile_id?: string | null
          ending_reason?: string | null
          id?: string
          is_primary?: boolean
          link_status?: string
          link_type?: string
          member_id?: string
          organization_id?: string
          profile_id?: string
          proposed_at?: string
          proposed_by_profile_id?: string | null
          updated_at?: string
          updated_by_profile_id?: string | null
          verification_method?: string | null
          verification_summary?: string | null
          verified_at?: string | null
          verified_by_profile_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_profile_member_links__ended_by"
            columns: ["ended_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_profile_member_links__members"
            columns: ["organization_id", "member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_profile_member_links__organizations"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_profile_member_links__profiles"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_profile_member_links__proposed_by"
            columns: ["proposed_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_profile_member_links__updated_by"
            columns: ["updated_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_profile_member_links__verified_by"
            columns: ["verified_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      profile_organization_memberships: {
        Row: {
          accepted_at: string | null
          created_at: string
          created_by_profile_id: string | null
          effective_from_at: string
          effective_to_at: string | null
          ended_at: string | null
          ended_by_profile_id: string | null
          ending_reason: string | null
          id: string
          invited_at: string | null
          invited_by_profile_id: string | null
          is_default: boolean
          membership_status: string
          organization_id: string
          profile_id: string
          suspended_at: string | null
          suspended_by_profile_id: string | null
          suspension_reason: string | null
          updated_at: string
          updated_by_profile_id: string | null
        }
        Insert: {
          accepted_at?: string | null
          created_at?: string
          created_by_profile_id?: string | null
          effective_from_at?: string
          effective_to_at?: string | null
          ended_at?: string | null
          ended_by_profile_id?: string | null
          ending_reason?: string | null
          id?: string
          invited_at?: string | null
          invited_by_profile_id?: string | null
          is_default?: boolean
          membership_status?: string
          organization_id: string
          profile_id: string
          suspended_at?: string | null
          suspended_by_profile_id?: string | null
          suspension_reason?: string | null
          updated_at?: string
          updated_by_profile_id?: string | null
        }
        Update: {
          accepted_at?: string | null
          created_at?: string
          created_by_profile_id?: string | null
          effective_from_at?: string
          effective_to_at?: string | null
          ended_at?: string | null
          ended_by_profile_id?: string | null
          ending_reason?: string | null
          id?: string
          invited_at?: string | null
          invited_by_profile_id?: string | null
          is_default?: boolean
          membership_status?: string
          organization_id?: string
          profile_id?: string
          suspended_at?: string | null
          suspended_by_profile_id?: string | null
          suspension_reason?: string | null
          updated_at?: string
          updated_by_profile_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_profile_organization_memberships__created_by"
            columns: ["created_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_profile_organization_memberships__ended_by"
            columns: ["ended_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_profile_organization_memberships__invited_by"
            columns: ["invited_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_profile_organization_memberships__organizations"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_profile_organization_memberships__profiles"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_profile_organization_memberships__suspended_by"
            columns: ["suspended_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_profile_organization_memberships__updated_by"
            columns: ["updated_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      profile_preferences: {
        Row: {
          accessibility_preferences: Json
          created_at: string
          email_notifications_enabled: boolean
          preferred_locale_code: string | null
          preferred_theme: string
          preferred_timezone_name: string | null
          profile_id: string
          push_notifications_enabled: boolean
          reduced_motion: boolean
          updated_at: string
        }
        Insert: {
          accessibility_preferences?: Json
          created_at?: string
          email_notifications_enabled?: boolean
          preferred_locale_code?: string | null
          preferred_theme?: string
          preferred_timezone_name?: string | null
          profile_id: string
          push_notifications_enabled?: boolean
          reduced_motion?: boolean
          updated_at?: string
        }
        Update: {
          accessibility_preferences?: Json
          created_at?: string
          email_notifications_enabled?: boolean
          preferred_locale_code?: string | null
          preferred_theme?: string
          preferred_timezone_name?: string | null
          profile_id?: string
          push_notifications_enabled?: boolean
          reduced_motion?: boolean
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "fk_profile_preferences__locales"
            columns: ["preferred_locale_code"]
            isOneToOne: false
            referencedRelation: "locales"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "fk_profile_preferences__profiles"
            columns: ["profile_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_profile_preferences__timezones"
            columns: ["preferred_timezone_name"]
            isOneToOne: false
            referencedRelation: "timezones"
            referencedColumns: ["name"]
          },
        ]
      }
      profile_role_assignments: {
        Row: {
          activated_at: string | null
          app_role_id: string
          approved_at: string | null
          approved_by_profile_id: string | null
          assignment_status: string
          assignment_summary: string | null
          created_at: string
          effective_from_at: string | null
          effective_to_at: string | null
          ended_at: string | null
          ended_by_profile_id: string | null
          ending_reason: string | null
          id: string
          leadership_assignment_id: string | null
          organization_id: string | null
          profile_id: string
          proposed_at: string
          proposed_by_profile_id: string | null
          source_type: string
          suspended_at: string | null
          suspended_by_profile_id: string | null
          suspension_reason: string | null
          updated_at: string
          updated_by_profile_id: string | null
        }
        Insert: {
          activated_at?: string | null
          app_role_id: string
          approved_at?: string | null
          approved_by_profile_id?: string | null
          assignment_status?: string
          assignment_summary?: string | null
          created_at?: string
          effective_from_at?: string | null
          effective_to_at?: string | null
          ended_at?: string | null
          ended_by_profile_id?: string | null
          ending_reason?: string | null
          id?: string
          leadership_assignment_id?: string | null
          organization_id?: string | null
          profile_id: string
          proposed_at?: string
          proposed_by_profile_id?: string | null
          source_type?: string
          suspended_at?: string | null
          suspended_by_profile_id?: string | null
          suspension_reason?: string | null
          updated_at?: string
          updated_by_profile_id?: string | null
        }
        Update: {
          activated_at?: string | null
          app_role_id?: string
          approved_at?: string | null
          approved_by_profile_id?: string | null
          assignment_status?: string
          assignment_summary?: string | null
          created_at?: string
          effective_from_at?: string | null
          effective_to_at?: string | null
          ended_at?: string | null
          ended_by_profile_id?: string | null
          ending_reason?: string | null
          id?: string
          leadership_assignment_id?: string | null
          organization_id?: string | null
          profile_id?: string
          proposed_at?: string
          proposed_by_profile_id?: string | null
          source_type?: string
          suspended_at?: string | null
          suspended_by_profile_id?: string | null
          suspension_reason?: string | null
          updated_at?: string
          updated_by_profile_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_profile_role_assignments__approved_by"
            columns: ["approved_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_profile_role_assignments__ended_by"
            columns: ["ended_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_profile_role_assignments__leadership_assignments"
            columns: ["organization_id", "leadership_assignment_id"]
            isOneToOne: false
            referencedRelation: "leadership_assignments"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_profile_role_assignments__organizations"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_profile_role_assignments__profiles"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_profile_role_assignments__proposed_by"
            columns: ["proposed_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_profile_role_assignments__roles"
            columns: ["app_role_id"]
            isOneToOne: false
            referencedRelation: "app_roles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_profile_role_assignments__suspended_by"
            columns: ["suspended_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_profile_role_assignments__updated_by"
            columns: ["updated_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      profile_scope_assignments: {
        Row: {
          assigned_at: string
          assigned_by_profile_id: string | null
          assignment_status: string
          assignment_summary: string | null
          created_at: string
          effective_from_at: string
          effective_to_at: string | null
          entity_id: string | null
          entity_type: string | null
          governance_node_id: string | null
          id: string
          includes_descendants: boolean
          maximum_descendant_depth: number | null
          member_id: string | null
          organization_id: string
          profile_role_assignment_id: string
          revocation_reason: string | null
          revoked_at: string | null
          revoked_by_profile_id: string | null
          scope_effect: string
          scope_type: string
          section_node_id: string | null
          updated_at: string
          updated_by_profile_id: string | null
        }
        Insert: {
          assigned_at?: string
          assigned_by_profile_id?: string | null
          assignment_status?: string
          assignment_summary?: string | null
          created_at?: string
          effective_from_at?: string
          effective_to_at?: string | null
          entity_id?: string | null
          entity_type?: string | null
          governance_node_id?: string | null
          id?: string
          includes_descendants?: boolean
          maximum_descendant_depth?: number | null
          member_id?: string | null
          organization_id: string
          profile_role_assignment_id: string
          revocation_reason?: string | null
          revoked_at?: string | null
          revoked_by_profile_id?: string | null
          scope_effect?: string
          scope_type: string
          section_node_id?: string | null
          updated_at?: string
          updated_by_profile_id?: string | null
        }
        Update: {
          assigned_at?: string
          assigned_by_profile_id?: string | null
          assignment_status?: string
          assignment_summary?: string | null
          created_at?: string
          effective_from_at?: string
          effective_to_at?: string | null
          entity_id?: string | null
          entity_type?: string | null
          governance_node_id?: string | null
          id?: string
          includes_descendants?: boolean
          maximum_descendant_depth?: number | null
          member_id?: string | null
          organization_id?: string
          profile_role_assignment_id?: string
          revocation_reason?: string | null
          revoked_at?: string | null
          revoked_by_profile_id?: string | null
          scope_effect?: string
          scope_type?: string
          section_node_id?: string | null
          updated_at?: string
          updated_by_profile_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_profile_scope_assignments__assigned_by"
            columns: ["assigned_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_profile_scope_assignments__governance_nodes"
            columns: ["organization_id", "governance_node_id"]
            isOneToOne: false
            referencedRelation: "governance_nodes"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_profile_scope_assignments__members"
            columns: ["organization_id", "member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_profile_scope_assignments__organizations"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_profile_scope_assignments__revoked_by"
            columns: ["revoked_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_profile_scope_assignments__role_assignments"
            columns: ["organization_id", "profile_role_assignment_id"]
            isOneToOne: false
            referencedRelation: "profile_role_assignments"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_profile_scope_assignments__section_nodes"
            columns: ["organization_id", "section_node_id"]
            isOneToOne: false
            referencedRelation: "governance_nodes"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_profile_scope_assignments__updated_by"
            columns: ["updated_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          account_status: string
          avatar_storage_path: string | null
          created_at: string
          display_name: string
          id: string
          is_platform_administrator: boolean
          last_active_at: string | null
          preferred_name: string | null
          privacy_acknowledged_at: string | null
          terms_accepted_at: string | null
          updated_at: string
        }
        Insert: {
          account_status?: string
          avatar_storage_path?: string | null
          created_at?: string
          display_name: string
          id: string
          is_platform_administrator?: boolean
          last_active_at?: string | null
          preferred_name?: string | null
          privacy_acknowledged_at?: string | null
          terms_accepted_at?: string | null
          updated_at?: string
        }
        Update: {
          account_status?: string
          avatar_storage_path?: string | null
          created_at?: string
          display_name?: string
          id?: string
          is_platform_administrator?: boolean
          last_active_at?: string | null
          preferred_name?: string | null
          privacy_acknowledged_at?: string | null
          terms_accepted_at?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      role_permissions: {
        Row: {
          app_role_id: string
          approval_status: string
          approved_at: string | null
          approved_by_profile_id: string | null
          created_at: string
          created_by_profile_id: string | null
          effective_from_at: string
          effective_to_at: string | null
          id: string
          organization_id: string | null
          permission_effect: string
          permission_id: string
          updated_at: string
          updated_by_profile_id: string | null
        }
        Insert: {
          app_role_id: string
          approval_status?: string
          approved_at?: string | null
          approved_by_profile_id?: string | null
          created_at?: string
          created_by_profile_id?: string | null
          effective_from_at?: string
          effective_to_at?: string | null
          id?: string
          organization_id?: string | null
          permission_effect?: string
          permission_id: string
          updated_at?: string
          updated_by_profile_id?: string | null
        }
        Update: {
          app_role_id?: string
          approval_status?: string
          approved_at?: string | null
          approved_by_profile_id?: string | null
          created_at?: string
          created_by_profile_id?: string | null
          effective_from_at?: string
          effective_to_at?: string | null
          id?: string
          organization_id?: string | null
          permission_effect?: string
          permission_id?: string
          updated_at?: string
          updated_by_profile_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_role_permissions__approved_by"
            columns: ["approved_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_role_permissions__created_by"
            columns: ["created_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_role_permissions__organizations"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_role_permissions__permissions"
            columns: ["permission_id"]
            isOneToOne: false
            referencedRelation: "permissions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_role_permissions__roles"
            columns: ["app_role_id"]
            isOneToOne: false
            referencedRelation: "app_roles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_role_permissions__updated_by"
            columns: ["updated_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      scope_inheritance_rules: {
        Row: {
          applies_to_leadership_role_definition_id: string | null
          created_at: string
          created_by: string | null
          id: string
          inheritance_effect: string
          is_active: boolean
          maximum_depth: number | null
          organization_id: string
          permission_code_pattern: string | null
          priority: number
          source_node_type_id: string
          target_node_type_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          applies_to_leadership_role_definition_id?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          inheritance_effect?: string
          is_active?: boolean
          maximum_depth?: number | null
          organization_id: string
          permission_code_pattern?: string | null
          priority?: number
          source_node_type_id: string
          target_node_type_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          applies_to_leadership_role_definition_id?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          inheritance_effect?: string
          is_active?: boolean
          maximum_depth?: number | null
          organization_id?: string
          permission_code_pattern?: string | null
          priority?: number
          source_node_type_id?: string
          target_node_type_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_scope_inheritance_rules__leadership_roles"
            columns: [
              "organization_id",
              "applies_to_leadership_role_definition_id",
            ]
            isOneToOne: false
            referencedRelation: "leadership_role_definitions"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_scope_inheritance_rules__source_types"
            columns: ["organization_id", "source_node_type_id"]
            isOneToOne: false
            referencedRelation: "governance_node_types"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_scope_inheritance_rules__target_types"
            columns: ["organization_id", "target_node_type_id"]
            isOneToOne: false
            referencedRelation: "governance_node_types"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      section_memberships: {
        Row: {
          approved_at: string | null
          approved_by_profile_id: string | null
          created_at: string
          created_by_profile_id: string | null
          effective_from: string
          effective_to: string | null
          ending_reason: string | null
          id: string
          is_primary: boolean
          member_id: string
          membership_status: string
          organization_id: string
          paired_member_id: string | null
          placement_source: string
          section_node_id: string
          updated_at: string
          updated_by_profile_id: string | null
        }
        Insert: {
          approved_at?: string | null
          approved_by_profile_id?: string | null
          created_at?: string
          created_by_profile_id?: string | null
          effective_from?: string
          effective_to?: string | null
          ending_reason?: string | null
          id?: string
          is_primary?: boolean
          member_id: string
          membership_status?: string
          organization_id: string
          paired_member_id?: string | null
          placement_source?: string
          section_node_id: string
          updated_at?: string
          updated_by_profile_id?: string | null
        }
        Update: {
          approved_at?: string | null
          approved_by_profile_id?: string | null
          created_at?: string
          created_by_profile_id?: string | null
          effective_from?: string
          effective_to?: string | null
          ending_reason?: string | null
          id?: string
          is_primary?: boolean
          member_id?: string
          membership_status?: string
          organization_id?: string
          paired_member_id?: string | null
          placement_source?: string
          section_node_id?: string
          updated_at?: string
          updated_by_profile_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_section_memberships__members"
            columns: ["organization_id", "member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_section_memberships__paired_members"
            columns: ["organization_id", "paired_member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "fk_section_memberships__sections"
            columns: ["organization_id", "section_node_id"]
            isOneToOne: false
            referencedRelation: "governance_nodes"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      sections: {
        Row: {
          created_at: string
          created_by: string | null
          formation_program_code: string | null
          id: string
          maximum_age: number | null
          minimum_age: number | null
          organization_id: string
          pastoral_notes: string | null
          section_category: string
          supports_couple_membership: boolean
          supports_individual_membership: boolean
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          formation_program_code?: string | null
          id: string
          maximum_age?: number | null
          minimum_age?: number | null
          organization_id: string
          pastoral_notes?: string | null
          section_category: string
          supports_couple_membership?: boolean
          supports_individual_membership?: boolean
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          formation_program_code?: string | null
          id?: string
          maximum_age?: number | null
          minimum_age?: number | null
          organization_id?: string
          pastoral_notes?: string | null
          section_category?: string
          supports_couple_membership?: boolean
          supports_individual_membership?: boolean
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_sections__governance_nodes"
            columns: ["organization_id", "id"]
            isOneToOne: false
            referencedRelation: "governance_nodes"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      security_events: {
        Row: {
          correlation_id: string | null
          created_at: string
          details: Json
          detected_by: string
          event_code: string
          event_status: string
          event_summary: string
          id: string
          ip_address: unknown
          occurred_at: string
          organization_id: string | null
          profile_id: string | null
          resolution_summary: string | null
          reviewed_at: string | null
          reviewed_by_profile_id: string | null
          severity: string
          user_agent: string | null
          user_device_id: string | null
        }
        Insert: {
          correlation_id?: string | null
          created_at?: string
          details?: Json
          detected_by?: string
          event_code: string
          event_status?: string
          event_summary: string
          id?: string
          ip_address?: unknown
          occurred_at?: string
          organization_id?: string | null
          profile_id?: string | null
          resolution_summary?: string | null
          reviewed_at?: string | null
          reviewed_by_profile_id?: string | null
          severity: string
          user_agent?: string | null
          user_device_id?: string | null
        }
        Update: {
          correlation_id?: string | null
          created_at?: string
          details?: Json
          detected_by?: string
          event_code?: string
          event_status?: string
          event_summary?: string
          id?: string
          ip_address?: unknown
          occurred_at?: string
          organization_id?: string | null
          profile_id?: string | null
          resolution_summary?: string | null
          reviewed_at?: string | null
          reviewed_by_profile_id?: string | null
          severity?: string
          user_agent?: string | null
          user_device_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_security_events__devices"
            columns: ["user_device_id"]
            isOneToOne: false
            referencedRelation: "user_devices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_security_events__organizations"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_security_events__profiles"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_security_events__reviewed_by"
            columns: ["reviewed_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      states_provinces: {
        Row: {
          code: string
          country_code: string
          created_at: string
          display_order: number
          id: string
          is_active: boolean
          name: string
          subdivision_type: string | null
        }
        Insert: {
          code: string
          country_code: string
          created_at?: string
          display_order?: number
          id?: string
          is_active?: boolean
          name: string
          subdivision_type?: string | null
        }
        Update: {
          code?: string
          country_code?: string
          created_at?: string
          display_order?: number
          id?: string
          is_active?: boolean
          name?: string
          subdivision_type?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "states_provinces_country_code_fkey"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "countries"
            referencedColumns: ["code"]
          },
        ]
      }
      tags: {
        Row: {
          code: string
          created_at: string
          created_by: string | null
          data_classification_code: string
          description: string | null
          display_order: number
          id: string
          is_active: boolean
          name: string
          organization_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          code: string
          created_at?: string
          created_by?: string | null
          data_classification_code?: string
          description?: string | null
          display_order?: number
          id?: string
          is_active?: boolean
          name: string
          organization_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          code?: string
          created_at?: string
          created_by?: string | null
          data_classification_code?: string
          description?: string | null
          display_order?: number
          id?: string
          is_active?: boolean
          name?: string
          organization_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_tags__created_by"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_tags__updated_by"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tags_data_classification_code_fkey"
            columns: ["data_classification_code"]
            isOneToOne: false
            referencedRelation: "data_classifications"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "tags_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      timezones: {
        Row: {
          country_code: string | null
          created_at: string
          display_order: number
          is_active: boolean
          name: string
          observes_daylight_saving: boolean | null
          utc_offset_standard_minutes: number | null
        }
        Insert: {
          country_code?: string | null
          created_at?: string
          display_order?: number
          is_active?: boolean
          name: string
          observes_daylight_saving?: boolean | null
          utc_offset_standard_minutes?: number | null
        }
        Update: {
          country_code?: string | null
          created_at?: string
          display_order?: number
          is_active?: boolean
          name?: string
          observes_daylight_saving?: boolean | null
          utc_offset_standard_minutes?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "timezones_country_code_fkey"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "countries"
            referencedColumns: ["code"]
          },
        ]
      }
      units: {
        Row: {
          created_at: string
          created_by: string | null
          id: string
          maximum_household_count: number | null
          organization_id: string
          service_area_description: string | null
          target_household_count: number | null
          unit_category: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          id: string
          maximum_household_count?: number | null
          organization_id: string
          service_area_description?: string | null
          target_household_count?: number | null
          unit_category?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          id?: string
          maximum_household_count?: number | null
          organization_id?: string
          service_area_description?: string | null
          target_household_count?: number | null
          unit_category?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_units__governance_nodes"
            columns: ["organization_id", "id"]
            isOneToOne: false
            referencedRelation: "governance_nodes"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      user_devices: {
        Row: {
          app_version: string | null
          created_at: string
          device_model: string | null
          device_name: string
          device_public_id: string
          device_status: string
          first_seen_at: string
          id: string
          last_ip: unknown
          last_seen_at: string
          metadata: Json
          platform: string
          profile_id: string
          push_token_hash: string | null
          updated_at: string
        }
        Insert: {
          app_version?: string | null
          created_at?: string
          device_model?: string | null
          device_name: string
          device_public_id?: string
          device_status?: string
          first_seen_at?: string
          id?: string
          last_ip?: unknown
          last_seen_at?: string
          metadata?: Json
          platform: string
          profile_id: string
          push_token_hash?: string | null
          updated_at?: string
        }
        Update: {
          app_version?: string | null
          created_at?: string
          device_model?: string | null
          device_name?: string
          device_public_id?: string
          device_status?: string
          first_seen_at?: string
          id?: string
          last_ip?: unknown
          last_seen_at?: string
          metadata?: Json
          platform?: string
          profile_id?: string
          push_token_hash?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "fk_user_devices__profiles"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      activate_leadership_assignment: {
        Args: {
          p_accepted_at?: string
          p_actor_profile_id: string
          p_assignment_id: string
        }
        Returns: undefined
      }
      activate_profile_role_assignment: {
        Args: { p_actor_profile_id: string; p_assignment_id: string }
        Returns: undefined
      }
      appoint_leader: {
        Args: {
          p_actor_profile_id?: string
          p_appointment_type?: string
          p_effective_from?: string
          p_effective_to?: string
          p_governance_node_id: string
          p_member_id: string
          p_organization_id: string
          p_role_code: string
          p_summary?: string
        }
        Returns: string
      }
      approve_leadership_assignment: {
        Args: {
          p_actor_profile_id: string
          p_assignment_id: string
          p_effective_from?: string
        }
        Returns: undefined
      }
      approve_profile_role_assignment: {
        Args: { p_actor_profile_id: string; p_assignment_id: string }
        Returns: undefined
      }
      assign_member_to_household: {
        Args: {
          p_actor_profile_id?: string
          p_effective_from?: string
          p_household_node_id: string
          p_member_id: string
          p_organization_id: string
          p_temporary?: boolean
        }
        Returns: string
      }
      assign_member_to_section: {
        Args: {
          p_actor_profile_id?: string
          p_effective_from?: string
          p_member_id: string
          p_organization_id: string
          p_section_node_id: string
        }
        Returns: string
      }
      assign_profile_role: {
        Args: {
          p_actor_profile_id?: string
          p_effective_from_at?: string
          p_effective_to_at?: string
          p_leadership_assignment_id?: string
          p_organization_id: string
          p_profile_id: string
          p_role_code: string
          p_source_type?: string
          p_summary?: string
        }
        Returns: string
      }
      assign_profile_scope: {
        Args: {
          p_actor_profile_id?: string
          p_effective_from_at?: string
          p_effective_to_at?: string
          p_includes_descendants?: boolean
          p_maximum_descendant_depth?: number
          p_role_assignment_id: string
          p_scope_effect?: string
          p_scope_reference_id: string
          p_scope_type: string
          p_summary?: string
        }
        Returns: string
      }
      authorize_device: {
        Args: {
          p_actor_profile_id?: string
          p_authorization_type: string
          p_effective_to_at?: string
          p_organization_id: string
          p_user_device_id: string
        }
        Returns: string
      }
      close_governance_node: {
        Args: {
          p_actor_profile_id?: string
          p_effective_to?: string
          p_node_id: string
          p_organization_id: string
          p_reason?: string
        }
        Returns: undefined
      }
      create_governance_node: {
        Args: {
          p_code: string
          p_created_by?: string
          p_detail_data?: Json
          p_effective_from?: string
          p_lifecycle_status?: string
          p_name: string
          p_node_type_code: string
          p_organization_id: string
          p_parent_node_id?: string
        }
        Returns: string
      }
      end_leadership_assignment: {
        Args: {
          p_actor_profile_id: string
          p_assignment_id: string
          p_effective_to: string
          p_end_status: string
          p_reason: string
        }
        Returns: undefined
      }
      end_profile_member_link: {
        Args: {
          p_actor_profile_id: string
          p_link_id: string
          p_reason: string
        }
        Returns: undefined
      }
      end_profile_role_assignment: {
        Args: {
          p_actor_profile_id: string
          p_assignment_id: string
          p_reason: string
        }
        Returns: undefined
      }
      execute_member_merge: {
        Args: { p_actor_profile_id: string; p_merge_request_id: string }
        Returns: string
      }
      issue_member_qr_token: {
        Args: {
          p_actor_profile_id?: string
          p_expires_at?: string
          p_member_id: string
          p_organization_id: string
        }
        Returns: {
          raw_token: string
          token_id: string
          token_public_id: string
        }[]
      }
      move_governance_node: {
        Args: {
          p_actor_profile_id?: string
          p_effective_from?: string
          p_new_parent_node_id: string
          p_node_id: string
          p_organization_id: string
          p_reason?: string
        }
        Returns: string
      }
      propose_member_merge: {
        Args: {
          p_actor_profile_id?: string
          p_candidate_id?: string
          p_organization_id: string
          p_retiring_member_id: string
          p_summary?: string
          p_survivor_member_id: string
        }
        Returns: string
      }
      record_consent: {
        Args: {
          p_actor_profile_id?: string
          p_consent_type_id: string
          p_decision?: string
          p_evidence?: Json
          p_member_id?: string
          p_organization_id: string
          p_profile_id?: string
          p_subject_reference_id?: string
          p_subject_type: string
        }
        Returns: string
      }
      register_user_device: {
        Args: {
          p_app_version?: string
          p_device_model?: string
          p_device_name: string
          p_platform: string
          p_profile_id: string
          p_push_token?: string
        }
        Returns: string
      }
      revoke_device: {
        Args: {
          p_actor_profile_id: string
          p_organization_id: string
          p_reason_code: string
          p_reason_summary: string
          p_user_device_id: string
        }
        Returns: undefined
      }
      revoke_member_qr_token: {
        Args: {
          p_actor_profile_id: string
          p_reason: string
          p_token_id: string
        }
        Returns: undefined
      }
      revoke_profile_scope: {
        Args: {
          p_actor_profile_id: string
          p_reason: string
          p_scope_assignment_id: string
        }
        Returns: undefined
      }
      show_limit: { Args: never; Returns: number }
      show_trgm: { Args: { "": string }; Returns: string[] }
      suspend_profile_role_assignment: {
        Args: {
          p_actor_profile_id: string
          p_assignment_id: string
          p_reason: string
        }
        Returns: undefined
      }
      validate_governance_parent: {
        Args: {
          p_child_node_id: string
          p_organization_id: string
          p_parent_node_id: string
        }
        Returns: boolean
      }
      validate_member_qr_token: {
        Args: {
          p_organization_id: string
          p_raw_token: string
          p_token_public_id: string
        }
        Returns: string
      }
      verify_profile_member_link: {
        Args: {
          p_actor_profile_id: string
          p_member_id: string
          p_organization_id: string
          p_profile_id: string
          p_verification_method: string
          p_verification_summary: string
        }
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
  audit: {
    Enums: {},
  },
  public: {
    Enums: {},
  },
} as const
