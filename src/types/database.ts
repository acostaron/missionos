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
      event_attendance: {
        Row: {
          check_in_method: string
          event_id: string
          id: string
          member_id: string
          organization_id: string
          recorded_at: string
          recorded_by_profile_id: string
          removed_at: string | null
          removed_by_profile_id: string | null
        }
        Insert: {
          check_in_method?: string
          event_id: string
          id?: string
          member_id: string
          organization_id: string
          recorded_at?: string
          recorded_by_profile_id: string
          removed_at?: string | null
          removed_by_profile_id?: string | null
        }
        Update: {
          check_in_method?: string
          event_id?: string
          id?: string
          member_id?: string
          organization_id?: string
          recorded_at?: string
          recorded_by_profile_id?: string
          removed_at?: string | null
          removed_by_profile_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "event_attendance_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_attendance_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_attendance_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_attendance_recorded_by_profile_id_fkey"
            columns: ["recorded_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_attendance_removed_by_profile_id_fkey"
            columns: ["removed_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      event_check_ins: {
        Row: {
          check_in_date: string
          check_in_method: string
          event_id: string
          id: string
          member_id: string
          organization_id: string
          recorded_at: string
          recorded_by_profile_id: string
        }
        Insert: {
          check_in_date: string
          check_in_method?: string
          event_id: string
          id?: string
          member_id: string
          organization_id: string
          recorded_at?: string
          recorded_by_profile_id: string
        }
        Update: {
          check_in_date?: string
          check_in_method?: string
          event_id?: string
          id?: string
          member_id?: string
          organization_id?: string
          recorded_at?: string
          recorded_by_profile_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "event_check_ins_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_check_ins_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_check_ins_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_check_ins_recorded_by_profile_id_fkey"
            columns: ["recorded_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      event_fee_waivers: {
        Row: {
          event_id: string
          id: string
          member_id: string
          organization_id: string
          removed_at: string | null
          removed_by_profile_id: string | null
          waived_at: string
          waived_by_profile_id: string
        }
        Insert: {
          event_id: string
          id?: string
          member_id: string
          organization_id: string
          removed_at?: string | null
          removed_by_profile_id?: string | null
          waived_at?: string
          waived_by_profile_id: string
        }
        Update: {
          event_id?: string
          id?: string
          member_id?: string
          organization_id?: string
          removed_at?: string | null
          removed_by_profile_id?: string | null
          waived_at?: string
          waived_by_profile_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "event_fee_waivers_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_fee_waivers_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_fee_waivers_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_fee_waivers_removed_by_profile_id_fkey"
            columns: ["removed_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_fee_waivers_waived_by_profile_id_fkey"
            columns: ["waived_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      event_greeters: {
        Row: {
          assigned_at: string
          assigned_by_profile_id: string
          event_id: string
          id: string
          member_id: string
          organization_id: string
          removed_at: string | null
          removed_by_profile_id: string | null
        }
        Insert: {
          assigned_at?: string
          assigned_by_profile_id: string
          event_id: string
          id?: string
          member_id: string
          organization_id: string
          removed_at?: string | null
          removed_by_profile_id?: string | null
        }
        Update: {
          assigned_at?: string
          assigned_by_profile_id?: string
          event_id?: string
          id?: string
          member_id?: string
          organization_id?: string
          removed_at?: string | null
          removed_by_profile_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "event_greeters_assigned_by_profile_id_fkey"
            columns: ["assigned_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_greeters_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_greeters_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_greeters_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_greeters_removed_by_profile_id_fkey"
            columns: ["removed_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      event_guest_check_ins: {
        Row: {
          check_in_date: string
          check_in_method: string
          event_id: string
          guest_id: string
          id: string
          organization_id: string
          recorded_at: string
          recorded_by_profile_id: string
        }
        Insert: {
          check_in_date: string
          check_in_method: string
          event_id: string
          guest_id: string
          id?: string
          organization_id: string
          recorded_at?: string
          recorded_by_profile_id: string
        }
        Update: {
          check_in_date?: string
          check_in_method?: string
          event_id?: string
          guest_id?: string
          id?: string
          organization_id?: string
          recorded_at?: string
          recorded_by_profile_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "event_guest_check_ins_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_guest_check_ins_guest_id_fkey"
            columns: ["guest_id"]
            isOneToOne: false
            referencedRelation: "event_guests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_guest_check_ins_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_guest_check_ins_recorded_by_profile_id_fkey"
            columns: ["recorded_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      event_guest_payments: {
        Row: {
          amount: number
          guest_id: string
          id: string
          organization_id: string
          payment_method: string
          recorded_at: string
          recorded_by_profile_id: string
          voided_at: string | null
          voided_by_profile_id: string | null
        }
        Insert: {
          amount: number
          guest_id: string
          id?: string
          organization_id: string
          payment_method: string
          recorded_at?: string
          recorded_by_profile_id: string
          voided_at?: string | null
          voided_by_profile_id?: string | null
        }
        Update: {
          amount?: number
          guest_id?: string
          id?: string
          organization_id?: string
          payment_method?: string
          recorded_at?: string
          recorded_by_profile_id?: string
          voided_at?: string | null
          voided_by_profile_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "event_guest_payments_guest_id_fkey"
            columns: ["guest_id"]
            isOneToOne: false
            referencedRelation: "event_guests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_guest_payments_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_guest_payments_recorded_by_profile_id_fkey"
            columns: ["recorded_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_guest_payments_voided_by_profile_id_fkey"
            columns: ["voided_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      event_guests: {
        Row: {
          amount_due: number
          cancelled_at: string | null
          cancelled_by_profile_id: string | null
          email: string | null
          event_id: string
          first_name: string
          guest_code: string
          host_member_id: string | null
          id: string
          last_name: string
          organization_id: string
          phone: string | null
          price_tier: string
          registered_at: string
          registered_by_profile_id: string
          registration_type: string
          source: string
          waived_at: string | null
          waived_by_profile_id: string | null
        }
        Insert: {
          amount_due: number
          cancelled_at?: string | null
          cancelled_by_profile_id?: string | null
          email?: string | null
          event_id: string
          first_name: string
          guest_code: string
          host_member_id?: string | null
          id?: string
          last_name: string
          organization_id: string
          phone?: string | null
          price_tier: string
          registered_at?: string
          registered_by_profile_id: string
          registration_type: string
          source: string
          waived_at?: string | null
          waived_by_profile_id?: string | null
        }
        Update: {
          amount_due?: number
          cancelled_at?: string | null
          cancelled_by_profile_id?: string | null
          email?: string | null
          event_id?: string
          first_name?: string
          guest_code?: string
          host_member_id?: string | null
          id?: string
          last_name?: string
          organization_id?: string
          phone?: string | null
          price_tier?: string
          registered_at?: string
          registered_by_profile_id?: string
          registration_type?: string
          source?: string
          waived_at?: string | null
          waived_by_profile_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "event_guests_cancelled_by_profile_id_fkey"
            columns: ["cancelled_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_guests_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_guests_host_member_id_fkey"
            columns: ["host_member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_guests_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_guests_registered_by_profile_id_fkey"
            columns: ["registered_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_guests_waived_by_profile_id_fkey"
            columns: ["waived_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      event_payments: {
        Row: {
          amount: number
          event_id: string
          id: string
          member_id: string
          organization_id: string
          payment_method: string
          recorded_at: string
          recorded_by_profile_id: string
          voided_at: string | null
          voided_by_profile_id: string | null
        }
        Insert: {
          amount: number
          event_id: string
          id?: string
          member_id: string
          organization_id: string
          payment_method: string
          recorded_at?: string
          recorded_by_profile_id: string
          voided_at?: string | null
          voided_by_profile_id?: string | null
        }
        Update: {
          amount?: number
          event_id?: string
          id?: string
          member_id?: string
          organization_id?: string
          payment_method?: string
          recorded_at?: string
          recorded_by_profile_id?: string
          voided_at?: string | null
          voided_by_profile_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "event_payments_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_payments_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_payments_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_payments_recorded_by_profile_id_fkey"
            columns: ["recorded_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_payments_voided_by_profile_id_fkey"
            columns: ["voided_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      event_registrations: {
        Row: {
          amount_due: number
          cancelled_at: string | null
          cancelled_by_profile_id: string | null
          event_id: string
          id: string
          member_id: string
          organization_id: string
          price_tier: string
          registered_at: string
          registered_by_profile_id: string
          registration_type: string
          source: string
        }
        Insert: {
          amount_due: number
          cancelled_at?: string | null
          cancelled_by_profile_id?: string | null
          event_id: string
          id?: string
          member_id: string
          organization_id: string
          price_tier: string
          registered_at?: string
          registered_by_profile_id: string
          registration_type: string
          source: string
        }
        Update: {
          amount_due?: number
          cancelled_at?: string | null
          cancelled_by_profile_id?: string | null
          event_id?: string
          id?: string
          member_id?: string
          organization_id?: string
          price_tier?: string
          registered_at?: string
          registered_by_profile_id?: string
          registration_type?: string
          source?: string
        }
        Relationships: [
          {
            foreignKeyName: "event_registrations_cancelled_by_profile_id_fkey"
            columns: ["cancelled_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_registrations_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_registrations_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_registrations_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_registrations_registered_by_profile_id_fkey"
            columns: ["registered_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      events: {
        Row: {
          audience_node_id: string | null
          cancel_reason: string | null
          created_at: string
          created_by_profile_id: string
          description: string | null
          early_bird_fee: number | null
          early_bird_until: string | null
          ends_at: string | null
          event_status: string
          event_type: string
          fee_amount: number | null
          formation_posted_at: string | null
          formation_posted_by_profile_id: string | null
          formation_program_id: string | null
          formation_talk_id: string | null
          guest_fee: number | null
          id: string
          location_text: string | null
          organization_id: string
          program_run_id: string | null
          registration_open: boolean
          session_number: number | null
          starts_at: string
          title: string
          updated_at: string
          updated_by_profile_id: string | null
          walk_in_fee: number | null
        }
        Insert: {
          audience_node_id?: string | null
          cancel_reason?: string | null
          created_at?: string
          created_by_profile_id: string
          description?: string | null
          early_bird_fee?: number | null
          early_bird_until?: string | null
          ends_at?: string | null
          event_status?: string
          event_type: string
          fee_amount?: number | null
          formation_posted_at?: string | null
          formation_posted_by_profile_id?: string | null
          formation_program_id?: string | null
          formation_talk_id?: string | null
          guest_fee?: number | null
          id?: string
          location_text?: string | null
          organization_id: string
          program_run_id?: string | null
          registration_open?: boolean
          session_number?: number | null
          starts_at: string
          title: string
          updated_at?: string
          updated_by_profile_id?: string | null
          walk_in_fee?: number | null
        }
        Update: {
          audience_node_id?: string | null
          cancel_reason?: string | null
          created_at?: string
          created_by_profile_id?: string
          description?: string | null
          early_bird_fee?: number | null
          early_bird_until?: string | null
          ends_at?: string | null
          event_status?: string
          event_type?: string
          fee_amount?: number | null
          formation_posted_at?: string | null
          formation_posted_by_profile_id?: string | null
          formation_program_id?: string | null
          formation_talk_id?: string | null
          guest_fee?: number | null
          id?: string
          location_text?: string | null
          organization_id?: string
          program_run_id?: string | null
          registration_open?: boolean
          session_number?: number | null
          starts_at?: string
          title?: string
          updated_at?: string
          updated_by_profile_id?: string | null
          walk_in_fee?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "events_audience_node_id_fkey"
            columns: ["audience_node_id"]
            isOneToOne: false
            referencedRelation: "governance_nodes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "events_created_by_profile_id_fkey"
            columns: ["created_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "events_formation_posted_by_profile_id_fkey"
            columns: ["formation_posted_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "events_formation_program_id_fkey"
            columns: ["formation_program_id"]
            isOneToOne: false
            referencedRelation: "formation_programs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "events_formation_talk_id_fkey"
            columns: ["formation_talk_id"]
            isOneToOne: false
            referencedRelation: "formation_talks"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "events_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "events_program_run_id_fkey"
            columns: ["program_run_id"]
            isOneToOne: false
            referencedRelation: "program_runs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "events_updated_by_profile_id_fkey"
            columns: ["updated_by_profile_id"]
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
      finance_coordinators: {
        Row: {
          appointed_at: string
          appointed_by_profile_id: string
          ended_at: string | null
          ended_by_profile_id: string | null
          id: string
          member_id: string
          organization_id: string
          role_title: string
        }
        Insert: {
          appointed_at?: string
          appointed_by_profile_id: string
          ended_at?: string | null
          ended_by_profile_id?: string | null
          id?: string
          member_id: string
          organization_id: string
          role_title: string
        }
        Update: {
          appointed_at?: string
          appointed_by_profile_id?: string
          ended_at?: string | null
          ended_by_profile_id?: string | null
          id?: string
          member_id?: string
          organization_id?: string
          role_title?: string
        }
        Relationships: [
          {
            foreignKeyName: "finance_coordinators_appointed_by_profile_id_fkey"
            columns: ["appointed_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "finance_coordinators_ended_by_profile_id_fkey"
            columns: ["ended_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "finance_coordinators_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "finance_coordinators_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      formation_program_requirements: {
        Row: {
          created_at: string
          id: string
          is_active: boolean
          is_mandatory: boolean
          notes: string | null
          program_id: string
          target_audience: string
          timing_norm: string | null
          updated_at: string
          valid_from: string | null
          valid_to: string | null
        }
        Insert: {
          created_at?: string
          id?: string
          is_active?: boolean
          is_mandatory?: boolean
          notes?: string | null
          program_id: string
          target_audience: string
          timing_norm?: string | null
          updated_at?: string
          valid_from?: string | null
          valid_to?: string | null
        }
        Update: {
          created_at?: string
          id?: string
          is_active?: boolean
          is_mandatory?: boolean
          notes?: string | null
          program_id?: string
          target_audience?: string
          timing_norm?: string | null
          updated_at?: string
          valid_from?: string | null
          valid_to?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "formation_program_requirements_program_id_fkey"
            columns: ["program_id"]
            isOneToOne: false
            referencedRelation: "formation_programs"
            referencedColumns: ["id"]
          },
        ]
      }
      formation_programs: {
        Row: {
          code: string
          created_at: string
          description: string | null
          edition: string
          effective_from: string | null
          effective_to: string | null
          id: string
          is_active: boolean
          organization_id: string | null
          program_category: string
          program_type: string
          retired_at: string | null
          sequence_order: number | null
          source_document: string | null
          source_url: string | null
          source_verified_at: string | null
          title: string
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          description?: string | null
          edition?: string
          effective_from?: string | null
          effective_to?: string | null
          id?: string
          is_active?: boolean
          organization_id?: string | null
          program_category: string
          program_type: string
          retired_at?: string | null
          sequence_order?: number | null
          source_document?: string | null
          source_url?: string | null
          source_verified_at?: string | null
          title: string
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          description?: string | null
          edition?: string
          effective_from?: string | null
          effective_to?: string | null
          id?: string
          is_active?: boolean
          organization_id?: string | null
          program_category?: string
          program_type?: string
          retired_at?: string | null
          sequence_order?: number | null
          source_document?: string | null
          source_url?: string | null
          source_verified_at?: string | null
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "formation_programs_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      formation_talks: {
        Row: {
          created_at: string
          description: string | null
          effective_from: string | null
          effective_to: string | null
          id: string
          is_active: boolean
          is_required: boolean
          program_id: string
          retired_at: string | null
          sequence_order: number
          session_label: string | null
          talk_code: string
          title: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          description?: string | null
          effective_from?: string | null
          effective_to?: string | null
          id?: string
          is_active?: boolean
          is_required?: boolean
          program_id: string
          retired_at?: string | null
          sequence_order: number
          session_label?: string | null
          talk_code: string
          title: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          description?: string | null
          effective_from?: string | null
          effective_to?: string | null
          id?: string
          is_active?: boolean
          is_required?: boolean
          program_id?: string
          retired_at?: string | null
          sequence_order?: number
          session_label?: string | null
          talk_code?: string
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "formation_talks_program_id_fkey"
            columns: ["program_id"]
            isOneToOne: false
            referencedRelation: "formation_programs"
            referencedColumns: ["id"]
          },
        ]
      }
      formation_topic_content_versions: {
        Row: {
          content_blocks: Json
          content_hash: string
          created_at: string
          id: string
          organization_id: string
          review_notes: string | null
          review_status: string
          reviewed_at: string | null
          reviewed_by_profile_id: string | null
          source_fetched_at: string
          source_url: string
          topic_id: string
          version_number: number
        }
        Insert: {
          content_blocks: Json
          content_hash: string
          created_at?: string
          id?: string
          organization_id: string
          review_notes?: string | null
          review_status?: string
          reviewed_at?: string | null
          reviewed_by_profile_id?: string | null
          source_fetched_at: string
          source_url: string
          topic_id: string
          version_number: number
        }
        Update: {
          content_blocks?: Json
          content_hash?: string
          created_at?: string
          id?: string
          organization_id?: string
          review_notes?: string | null
          review_status?: string
          reviewed_at?: string | null
          reviewed_by_profile_id?: string | null
          source_fetched_at?: string
          source_url?: string
          topic_id?: string
          version_number?: number
        }
        Relationships: [
          {
            foreignKeyName: "formation_topic_content_versions_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "formation_topic_content_versions_reviewed_by_profile_id_fkey"
            columns: ["reviewed_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "formation_topic_content_versions_topic_id_fkey"
            columns: ["topic_id"]
            isOneToOne: false
            referencedRelation: "formation_topics"
            referencedColumns: ["id"]
          },
        ]
      }
      formation_topics: {
        Row: {
          created_at: string
          created_by_profile_id: string | null
          description: string | null
          effective_from: string | null
          effective_to: string | null
          id: string
          is_active: boolean
          material_kind: string | null
          objectives: string | null
          organization_id: string | null
          recommended_duration_minutes: number | null
          recommended_pastoral_level: string | null
          scripture_reference: string | null
          series_code: string | null
          series_title: string | null
          short_title: string | null
          sort_order: number | null
          source_type: string
          source_url: string | null
          title: string
          topic_code: string | null
          topic_month: string | null
          updated_at: string
          updated_by_profile_id: string | null
        }
        Insert: {
          created_at?: string
          created_by_profile_id?: string | null
          description?: string | null
          effective_from?: string | null
          effective_to?: string | null
          id?: string
          is_active?: boolean
          material_kind?: string | null
          objectives?: string | null
          organization_id?: string | null
          recommended_duration_minutes?: number | null
          recommended_pastoral_level?: string | null
          scripture_reference?: string | null
          series_code?: string | null
          series_title?: string | null
          short_title?: string | null
          sort_order?: number | null
          source_type?: string
          source_url?: string | null
          title: string
          topic_code?: string | null
          topic_month?: string | null
          updated_at?: string
          updated_by_profile_id?: string | null
        }
        Update: {
          created_at?: string
          created_by_profile_id?: string | null
          description?: string | null
          effective_from?: string | null
          effective_to?: string | null
          id?: string
          is_active?: boolean
          material_kind?: string | null
          objectives?: string | null
          organization_id?: string | null
          recommended_duration_minutes?: number | null
          recommended_pastoral_level?: string | null
          scripture_reference?: string | null
          series_code?: string | null
          series_title?: string | null
          short_title?: string | null
          sort_order?: number | null
          source_type?: string
          source_url?: string | null
          title?: string
          topic_code?: string | null
          topic_month?: string | null
          updated_at?: string
          updated_by_profile_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "formation_topics_created_by_profile_id_fkey"
            columns: ["created_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "formation_topics_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "formation_topics_updated_by_profile_id_fkey"
            columns: ["updated_by_profile_id"]
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
      household_meeting_attendance: {
        Row: {
          arrival_time: string | null
          attendance_status: string
          household_meeting_id: string
          id: string
          member_id: string
          organization_id: string
          recorded_at: string
          recorded_by_profile_id: string | null
          updated_at: string
          updated_by_profile_id: string | null
        }
        Insert: {
          arrival_time?: string | null
          attendance_status: string
          household_meeting_id: string
          id?: string
          member_id: string
          organization_id: string
          recorded_at?: string
          recorded_by_profile_id?: string | null
          updated_at?: string
          updated_by_profile_id?: string | null
        }
        Update: {
          arrival_time?: string | null
          attendance_status?: string
          household_meeting_id?: string
          id?: string
          member_id?: string
          organization_id?: string
          recorded_at?: string
          recorded_by_profile_id?: string | null
          updated_at?: string
          updated_by_profile_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_hma__meeting"
            columns: ["household_meeting_id"]
            isOneToOne: false
            referencedRelation: "household_meetings"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_hma__member"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_hma__organization"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      household_meetings: {
        Row: {
          actual_end_at: string | null
          actual_start_at: string | null
          attendance_recorded_at: string | null
          attendance_recorded_by_profile_id: string | null
          created_at: string
          created_by_profile_id: string | null
          facilitator_member_id: string | null
          host_member_id: string | null
          household_node_id: string
          id: string
          location_text: string | null
          location_type: string | null
          meeting_date: string
          meeting_status: string
          meeting_type: string
          notes_summary: string | null
          organization_id: string
          scheduled_end_at: string | null
          scheduled_start_at: string | null
          updated_at: string
          updated_by_profile_id: string | null
        }
        Insert: {
          actual_end_at?: string | null
          actual_start_at?: string | null
          attendance_recorded_at?: string | null
          attendance_recorded_by_profile_id?: string | null
          created_at?: string
          created_by_profile_id?: string | null
          facilitator_member_id?: string | null
          host_member_id?: string | null
          household_node_id: string
          id?: string
          location_text?: string | null
          location_type?: string | null
          meeting_date: string
          meeting_status?: string
          meeting_type?: string
          notes_summary?: string | null
          organization_id: string
          scheduled_end_at?: string | null
          scheduled_start_at?: string | null
          updated_at?: string
          updated_by_profile_id?: string | null
        }
        Update: {
          actual_end_at?: string | null
          actual_start_at?: string | null
          attendance_recorded_at?: string | null
          attendance_recorded_by_profile_id?: string | null
          created_at?: string
          created_by_profile_id?: string | null
          facilitator_member_id?: string | null
          host_member_id?: string | null
          household_node_id?: string
          id?: string
          location_text?: string | null
          location_type?: string | null
          meeting_date?: string
          meeting_status?: string
          meeting_type?: string
          notes_summary?: string | null
          organization_id?: string
          scheduled_end_at?: string | null
          scheduled_start_at?: string | null
          updated_at?: string
          updated_by_profile_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_household_meetings__facilitator"
            columns: ["facilitator_member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_household_meetings__host"
            columns: ["host_member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_household_meetings__household_node"
            columns: ["household_node_id"]
            isOneToOne: false
            referencedRelation: "governance_nodes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_household_meetings__organization"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
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
      household_topic_assignments: {
        Row: {
          assigned_at: string
          assigned_by_profile_id: string
          assignment_status: string
          cancelled_at: string | null
          cancelled_by_profile_id: string | null
          change_reason_code: string | null
          completed_at: string | null
          completed_by_profile_id: string | null
          completed_household_meeting_id: string | null
          created_at: string
          created_by_profile_id: string | null
          due_date: string | null
          household_node_id: string
          id: string
          organization_id: string
          planned_for_date: string | null
          planned_household_meeting_id: string | null
          replaced_by_assignment_id: string | null
          replaces_assignment_id: string | null
          rescheduled_at: string | null
          rescheduled_by_profile_id: string | null
          resolution_reason_code: string | null
          sequence_number: number | null
          skipped_at: string | null
          skipped_by_profile_id: string | null
          topic_id: string
          updated_at: string
          updated_by_profile_id: string | null
          used_topic_title: string | null
        }
        Insert: {
          assigned_at?: string
          assigned_by_profile_id: string
          assignment_status?: string
          cancelled_at?: string | null
          cancelled_by_profile_id?: string | null
          change_reason_code?: string | null
          completed_at?: string | null
          completed_by_profile_id?: string | null
          completed_household_meeting_id?: string | null
          created_at?: string
          created_by_profile_id?: string | null
          due_date?: string | null
          household_node_id: string
          id?: string
          organization_id: string
          planned_for_date?: string | null
          planned_household_meeting_id?: string | null
          replaced_by_assignment_id?: string | null
          replaces_assignment_id?: string | null
          rescheduled_at?: string | null
          rescheduled_by_profile_id?: string | null
          resolution_reason_code?: string | null
          sequence_number?: number | null
          skipped_at?: string | null
          skipped_by_profile_id?: string | null
          topic_id: string
          updated_at?: string
          updated_by_profile_id?: string | null
          used_topic_title?: string | null
        }
        Update: {
          assigned_at?: string
          assigned_by_profile_id?: string
          assignment_status?: string
          cancelled_at?: string | null
          cancelled_by_profile_id?: string | null
          change_reason_code?: string | null
          completed_at?: string | null
          completed_by_profile_id?: string | null
          completed_household_meeting_id?: string | null
          created_at?: string
          created_by_profile_id?: string | null
          due_date?: string | null
          household_node_id?: string
          id?: string
          organization_id?: string
          planned_for_date?: string | null
          planned_household_meeting_id?: string | null
          replaced_by_assignment_id?: string | null
          replaces_assignment_id?: string | null
          rescheduled_at?: string | null
          rescheduled_by_profile_id?: string | null
          resolution_reason_code?: string | null
          sequence_number?: number | null
          skipped_at?: string | null
          skipped_by_profile_id?: string | null
          topic_id?: string
          updated_at?: string
          updated_by_profile_id?: string | null
          used_topic_title?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "household_topic_assignments_assigned_by_profile_id_fkey"
            columns: ["assigned_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "household_topic_assignments_cancelled_by_profile_id_fkey"
            columns: ["cancelled_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "household_topic_assignments_completed_by_profile_id_fkey"
            columns: ["completed_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "household_topic_assignments_completed_household_meeting_id_fkey"
            columns: ["completed_household_meeting_id"]
            isOneToOne: false
            referencedRelation: "household_meetings"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "household_topic_assignments_created_by_profile_id_fkey"
            columns: ["created_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "household_topic_assignments_household_node_id_fkey"
            columns: ["household_node_id"]
            isOneToOne: false
            referencedRelation: "governance_nodes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "household_topic_assignments_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "household_topic_assignments_planned_household_meeting_id_fkey"
            columns: ["planned_household_meeting_id"]
            isOneToOne: false
            referencedRelation: "household_meetings"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "household_topic_assignments_replaced_by_assignment_id_fkey"
            columns: ["replaced_by_assignment_id"]
            isOneToOne: false
            referencedRelation: "household_topic_assignments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "household_topic_assignments_replaces_assignment_id_fkey"
            columns: ["replaces_assignment_id"]
            isOneToOne: false
            referencedRelation: "household_topic_assignments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "household_topic_assignments_rescheduled_by_profile_id_fkey"
            columns: ["rescheduled_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "household_topic_assignments_skipped_by_profile_id_fkey"
            columns: ["skipped_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "household_topic_assignments_topic_id_fkey"
            columns: ["topic_id"]
            isOneToOne: false
            referencedRelation: "formation_topics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "household_topic_assignments_updated_by_profile_id_fkey"
            columns: ["updated_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
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
          meeting_frequency: string | null
          meeting_location_text: string | null
          meeting_location_type: string | null
          meeting_start_time: string | null
          meeting_timezone_name: string | null
          organization_id: string
          pastoral_level: string
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
          meeting_frequency?: string | null
          meeting_location_text?: string | null
          meeting_location_type?: string | null
          meeting_start_time?: string | null
          meeting_timezone_name?: string | null
          organization_id: string
          pastoral_level?: string
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
          meeting_frequency?: string | null
          meeting_location_text?: string | null
          meeting_location_type?: string | null
          meeting_start_time?: string | null
          meeting_timezone_name?: string | null
          organization_id?: string
          pastoral_level?: string
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
      member_account_invitations: {
        Row: {
          accepted_at: string | null
          auth_user_id: string | null
          cancelled_at: string | null
          cancelled_by_profile_id: string | null
          created_at: string
          email: string
          expires_at: string | null
          failure_reason: string | null
          id: string
          invitation_status: string
          invited_at: string
          invited_by_profile_id: string
          member_id: string
          normalized_email: string
          organization_id: string
          profile_id: string | null
          updated_at: string
        }
        Insert: {
          accepted_at?: string | null
          auth_user_id?: string | null
          cancelled_at?: string | null
          cancelled_by_profile_id?: string | null
          created_at?: string
          email: string
          expires_at?: string | null
          failure_reason?: string | null
          id?: string
          invitation_status?: string
          invited_at?: string
          invited_by_profile_id: string
          member_id: string
          normalized_email: string
          organization_id: string
          profile_id?: string | null
          updated_at?: string
        }
        Update: {
          accepted_at?: string | null
          auth_user_id?: string | null
          cancelled_at?: string | null
          cancelled_by_profile_id?: string | null
          created_at?: string
          email?: string
          expires_at?: string | null
          failure_reason?: string | null
          id?: string
          invitation_status?: string
          invited_at?: string
          invited_by_profile_id?: string
          member_id?: string
          normalized_email?: string
          organization_id?: string
          profile_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "member_account_invitations_cancelled_by_profile_id_fkey"
            columns: ["cancelled_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_account_invitations_invited_by_profile_id_fkey"
            columns: ["invited_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_account_invitations_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_account_invitations_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_account_invitations_profile_id_fkey"
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
      member_claim_code_failures: {
        Row: {
          client_key: string
          failed_at: string
          id: number
        }
        Insert: {
          client_key: string
          failed_at?: string
          id?: number
        }
        Update: {
          client_key?: string
          failed_at?: string
          id?: number
        }
        Relationships: []
      }
      member_claim_codes: {
        Row: {
          code_hash: string
          code_hint: string
          code_status: string
          expires_at: string
          id: string
          issued_at: string
          issued_by_profile_id: string
          member_id: string
          organization_id: string
          redeemed_at: string | null
          redeemed_profile_id: string | null
          revoked_at: string | null
          revoked_by_profile_id: string | null
        }
        Insert: {
          code_hash: string
          code_hint: string
          code_status?: string
          expires_at?: string
          id?: string
          issued_at?: string
          issued_by_profile_id: string
          member_id: string
          organization_id: string
          redeemed_at?: string | null
          redeemed_profile_id?: string | null
          revoked_at?: string | null
          revoked_by_profile_id?: string | null
        }
        Update: {
          code_hash?: string
          code_hint?: string
          code_status?: string
          expires_at?: string
          id?: string
          issued_at?: string
          issued_by_profile_id?: string
          member_id?: string
          organization_id?: string
          redeemed_at?: string | null
          redeemed_profile_id?: string | null
          revoked_at?: string | null
          revoked_by_profile_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "member_claim_codes_issued_by_profile_id_fkey"
            columns: ["issued_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_claim_codes_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_claim_codes_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_claim_codes_redeemed_profile_id_fkey"
            columns: ["redeemed_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_claim_codes_revoked_by_profile_id_fkey"
            columns: ["revoked_by_profile_id"]
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
      member_formation_program_records: {
        Row: {
          attempt_number: number
          completed_date: string | null
          completed_month: number | null
          completed_year: number | null
          created_at: string
          date_precision: string
          id: string
          member_id: string
          organization_id: string
          program_id: string
          record_status: string
          recorded_at: string
          recorded_by_profile_id: string
          source_reference: string | null
          status: string
          updated_at: string
          verification_method: string
          verification_notes: string | null
          verified_at: string | null
          verified_by_profile_id: string | null
          void_reason: string | null
          voided_at: string | null
          voided_by_profile_id: string | null
        }
        Insert: {
          attempt_number?: number
          completed_date?: string | null
          completed_month?: number | null
          completed_year?: number | null
          created_at?: string
          date_precision?: string
          id?: string
          member_id: string
          organization_id: string
          program_id: string
          record_status?: string
          recorded_at?: string
          recorded_by_profile_id: string
          source_reference?: string | null
          status: string
          updated_at?: string
          verification_method: string
          verification_notes?: string | null
          verified_at?: string | null
          verified_by_profile_id?: string | null
          void_reason?: string | null
          voided_at?: string | null
          voided_by_profile_id?: string | null
        }
        Update: {
          attempt_number?: number
          completed_date?: string | null
          completed_month?: number | null
          completed_year?: number | null
          created_at?: string
          date_precision?: string
          id?: string
          member_id?: string
          organization_id?: string
          program_id?: string
          record_status?: string
          recorded_at?: string
          recorded_by_profile_id?: string
          source_reference?: string | null
          status?: string
          updated_at?: string
          verification_method?: string
          verification_notes?: string | null
          verified_at?: string | null
          verified_by_profile_id?: string | null
          void_reason?: string | null
          voided_at?: string | null
          voided_by_profile_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "member_formation_program_records_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_formation_program_records_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_formation_program_records_program_id_fkey"
            columns: ["program_id"]
            isOneToOne: false
            referencedRelation: "formation_programs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_formation_program_records_recorded_by_profile_id_fkey"
            columns: ["recorded_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_formation_program_records_verified_by_profile_id_fkey"
            columns: ["verified_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_formation_program_records_voided_by_profile_id_fkey"
            columns: ["voided_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      member_formation_talk_records: {
        Row: {
          attended_date: string | null
          created_at: string
          id: string
          member_id: string
          notes: string | null
          organization_id: string
          program_id: string
          program_record_id: string
          record_status: string
          recorded_at: string
          recorded_by_profile_id: string
          session_status: string
          talk_id: string
          updated_at: string
          void_reason: string | null
          voided_at: string | null
          voided_by_profile_id: string | null
        }
        Insert: {
          attended_date?: string | null
          created_at?: string
          id?: string
          member_id: string
          notes?: string | null
          organization_id: string
          program_id: string
          program_record_id: string
          record_status?: string
          recorded_at?: string
          recorded_by_profile_id: string
          session_status: string
          talk_id: string
          updated_at?: string
          void_reason?: string | null
          voided_at?: string | null
          voided_by_profile_id?: string | null
        }
        Update: {
          attended_date?: string | null
          created_at?: string
          id?: string
          member_id?: string
          notes?: string | null
          organization_id?: string
          program_id?: string
          program_record_id?: string
          record_status?: string
          recorded_at?: string
          recorded_by_profile_id?: string
          session_status?: string
          talk_id?: string
          updated_at?: string
          void_reason?: string | null
          voided_at?: string | null
          voided_by_profile_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_member_talk_parent_attempt"
            columns: [
              "program_record_id",
              "organization_id",
              "member_id",
              "program_id",
            ]
            isOneToOne: false
            referencedRelation: "member_formation_program_records"
            referencedColumns: [
              "id",
              "organization_id",
              "member_id",
              "program_id",
            ]
          },
          {
            foreignKeyName: "fk_member_talk_parent_talk"
            columns: ["talk_id", "program_id"]
            isOneToOne: false
            referencedRelation: "formation_talks"
            referencedColumns: ["id", "program_id"]
          },
          {
            foreignKeyName: "member_formation_talk_records_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_formation_talk_records_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_formation_talk_records_program_id_fkey"
            columns: ["program_id"]
            isOneToOne: false
            referencedRelation: "formation_programs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_formation_talk_records_recorded_by_profile_id_fkey"
            columns: ["recorded_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_formation_talk_records_voided_by_profile_id_fkey"
            columns: ["voided_by_profile_id"]
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
      program_participant_attendance: {
        Row: {
          event_id: string
          id: string
          organization_id: string
          participant_id: string
          recorded_at: string
          recorded_by_profile_id: string
          removed_at: string | null
          removed_by_profile_id: string | null
        }
        Insert: {
          event_id: string
          id?: string
          organization_id: string
          participant_id: string
          recorded_at?: string
          recorded_by_profile_id: string
          removed_at?: string | null
          removed_by_profile_id?: string | null
        }
        Update: {
          event_id?: string
          id?: string
          organization_id?: string
          participant_id?: string
          recorded_at?: string
          recorded_by_profile_id?: string
          removed_at?: string | null
          removed_by_profile_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "program_participant_attendance_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "program_participant_attendance_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "program_participant_attendance_participant_id_fkey"
            columns: ["participant_id"]
            isOneToOne: false
            referencedRelation: "program_participants"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "program_participant_attendance_recorded_by_profile_id_fkey"
            columns: ["recorded_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "program_participant_attendance_removed_by_profile_id_fkey"
            columns: ["removed_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      program_participants: {
        Row: {
          created_at: string
          created_by_profile_id: string
          email: string | null
          first_name: string | null
          id: string
          invited_by_member_id: string | null
          last_name: string | null
          member_id: string | null
          notes: string | null
          organization_id: string
          participant_status: string
          phone: string | null
          program_run_id: string
          updated_at: string
          updated_by_profile_id: string | null
        }
        Insert: {
          created_at?: string
          created_by_profile_id: string
          email?: string | null
          first_name?: string | null
          id?: string
          invited_by_member_id?: string | null
          last_name?: string | null
          member_id?: string | null
          notes?: string | null
          organization_id: string
          participant_status?: string
          phone?: string | null
          program_run_id: string
          updated_at?: string
          updated_by_profile_id?: string | null
        }
        Update: {
          created_at?: string
          created_by_profile_id?: string
          email?: string | null
          first_name?: string | null
          id?: string
          invited_by_member_id?: string | null
          last_name?: string | null
          member_id?: string | null
          notes?: string | null
          organization_id?: string
          participant_status?: string
          phone?: string | null
          program_run_id?: string
          updated_at?: string
          updated_by_profile_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "program_participants_created_by_profile_id_fkey"
            columns: ["created_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "program_participants_invited_by_member_id_fkey"
            columns: ["invited_by_member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "program_participants_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "program_participants_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "program_participants_program_run_id_fkey"
            columns: ["program_run_id"]
            isOneToOne: false
            referencedRelation: "program_runs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "program_participants_updated_by_profile_id_fkey"
            columns: ["updated_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      program_runs: {
        Row: {
          audience_node_id: string | null
          cancel_reason: string | null
          chapter_node_id: string | null
          created_at: string
          created_by_profile_id: string
          description: string | null
          id: string
          organization_id: string
          program_code: string
          run_status: string
          section_node_ids: string[]
          session_count: number
          title: string
          updated_at: string
          updated_by_profile_id: string | null
        }
        Insert: {
          audience_node_id?: string | null
          cancel_reason?: string | null
          chapter_node_id?: string | null
          created_at?: string
          created_by_profile_id: string
          description?: string | null
          id?: string
          organization_id: string
          program_code: string
          run_status?: string
          section_node_ids?: string[]
          session_count: number
          title: string
          updated_at?: string
          updated_by_profile_id?: string | null
        }
        Update: {
          audience_node_id?: string | null
          cancel_reason?: string | null
          chapter_node_id?: string | null
          created_at?: string
          created_by_profile_id?: string
          description?: string | null
          id?: string
          organization_id?: string
          program_code?: string
          run_status?: string
          section_node_ids?: string[]
          session_count?: number
          title?: string
          updated_at?: string
          updated_by_profile_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "program_runs_audience_node_id_fkey"
            columns: ["audience_node_id"]
            isOneToOne: false
            referencedRelation: "governance_nodes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "program_runs_chapter_node_id_fkey"
            columns: ["chapter_node_id"]
            isOneToOne: false
            referencedRelation: "governance_nodes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "program_runs_created_by_profile_id_fkey"
            columns: ["created_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "program_runs_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "program_runs_updated_by_profile_id_fkey"
            columns: ["updated_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
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
      servant_leader_access_grants: {
        Row: {
          access_status: string
          app_role_id: string
          created_at: string
          effective_from: string
          effective_to: string | null
          governance_node_id: string
          granted_at: string
          granted_by_profile_id: string | null
          id: string
          leadership_assignment_id: string
          member_id: string
          organization_id: string
          profile_id: string
          profile_role_assignment_id: string | null
          profile_scope_assignment_id: string | null
          revocation_reason: string | null
          revoked_at: string | null
          revoked_by_profile_id: string | null
          updated_at: string
        }
        Insert: {
          access_status?: string
          app_role_id: string
          created_at?: string
          effective_from?: string
          effective_to?: string | null
          governance_node_id: string
          granted_at?: string
          granted_by_profile_id?: string | null
          id?: string
          leadership_assignment_id: string
          member_id: string
          organization_id: string
          profile_id: string
          profile_role_assignment_id?: string | null
          profile_scope_assignment_id?: string | null
          revocation_reason?: string | null
          revoked_at?: string | null
          revoked_by_profile_id?: string | null
          updated_at?: string
        }
        Update: {
          access_status?: string
          app_role_id?: string
          created_at?: string
          effective_from?: string
          effective_to?: string | null
          governance_node_id?: string
          granted_at?: string
          granted_by_profile_id?: string | null
          id?: string
          leadership_assignment_id?: string
          member_id?: string
          organization_id?: string
          profile_id?: string
          profile_role_assignment_id?: string | null
          profile_scope_assignment_id?: string | null
          revocation_reason?: string | null
          revoked_at?: string | null
          revoked_by_profile_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "servant_leader_access_grants_app_role_id_fkey"
            columns: ["app_role_id"]
            isOneToOne: false
            referencedRelation: "app_roles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "servant_leader_access_grants_governance_node_id_fkey"
            columns: ["governance_node_id"]
            isOneToOne: false
            referencedRelation: "governance_nodes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "servant_leader_access_grants_granted_by_profile_id_fkey"
            columns: ["granted_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "servant_leader_access_grants_leadership_assignment_id_fkey"
            columns: ["leadership_assignment_id"]
            isOneToOne: false
            referencedRelation: "leadership_assignments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "servant_leader_access_grants_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "servant_leader_access_grants_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "servant_leader_access_grants_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "servant_leader_access_grants_profile_role_assignment_id_fkey"
            columns: ["profile_role_assignment_id"]
            isOneToOne: false
            referencedRelation: "profile_role_assignments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "servant_leader_access_grants_profile_scope_assignment_id_fkey"
            columns: ["profile_scope_assignment_id"]
            isOneToOne: false
            referencedRelation: "profile_scope_assignments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "servant_leader_access_grants_revoked_by_profile_id_fkey"
            columns: ["revoked_by_profile_id"]
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
          tag_group: string | null
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
          tag_group?: string | null
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
          tag_group?: string | null
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
      topic_library_sync_runs: {
        Row: {
          changed_count: number
          failed_count: number
          id: string
          new_count: number
          newest_month: string | null
          organization_id: string
          ran_at: string
          run_by_profile_id: string | null
          trigger_source: string
          unchanged_count: number
        }
        Insert: {
          changed_count?: number
          failed_count?: number
          id?: string
          new_count?: number
          newest_month?: string | null
          organization_id: string
          ran_at?: string
          run_by_profile_id?: string | null
          trigger_source: string
          unchanged_count?: number
        }
        Update: {
          changed_count?: number
          failed_count?: number
          id?: string
          new_count?: number
          newest_month?: string | null
          organization_id?: string
          ran_at?: string
          run_by_profile_id?: string | null
          trigger_source?: string
          unchanged_count?: number
        }
        Relationships: [
          {
            foreignKeyName: "topic_library_sync_runs_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "topic_library_sync_runs_run_by_profile_id_fkey"
            columns: ["run_by_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
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
      accept_member_account_invitation: {
        Args: { p_invitation_id?: string }
        Returns: Json
      }
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
      add_event_guest: {
        Args: {
          p_as_staff?: boolean
          p_email?: string
          p_event_id: string
          p_first_name: string
          p_host_member_id?: string
          p_last_name: string
          p_organization_id: string
          p_is_child?: boolean
          p_phone?: string
          p_walk_in?: boolean
        }
        Returns: Json
      }
      add_family_member: {
        Args: {
          p_confirm_multiple_active_family?: boolean
          p_effective_from?: string
          p_family_id: string
          p_family_role?: string
          p_is_dependent?: boolean
          p_is_primary_contact?: boolean
          p_member_id: string
          p_organization_id: string
        }
        Returns: Json
      }
      add_family_relationship: {
        Args: {
          p_effective_from?: string
          p_family_id: string
          p_from_member_id: string
          p_organization_id: string
          p_relationship_type_code: string
          p_to_member_id: string
        }
        Returns: Json
      }
      add_program_participant: {
        Args: {
          p_email?: string
          p_first_name?: string
          p_invited_by_member_id?: string
          p_last_name?: string
          p_member_id?: string
          p_notes?: string
          p_organization_id: string
          p_phone?: string
          p_run_id: string
        }
        Returns: Json
      }
      add_program_session: {
        Args: {
          p_ends_at?: string
          p_location_text?: string
          p_organization_id: string
          p_run_id: string
          p_session_number: number
          p_starts_at: string
        }
        Returns: Json
      }
      add_standard_sections: {
        Args: { p_organization_id: string; p_sub_area_node_id: string }
        Returns: Json
      }
      apply_official_documents_listing: { Args: { p_items: Json; p_organization_id: string }; Returns: Json }
      appoint_area_coordinator: {
        Args: {
          p_effective_from?: string
          p_exception_reason?: string
          p_member_id: string
          p_node_id: string
          p_organization_id: string
          p_role_code: string
        }
        Returns: Json
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
      appoint_servant_leader: {
        Args: {
          p_effective_from?: string
          p_governance_node_id: string
          p_member_id: string
          p_organization_id: string
          p_reason?: string
          p_role_code: string
        }
        Returns: Json
      }
      appoint_servant_leader_with_spouse: {
        Args: {
          p_governance_node_id: string
          p_member_id: string
          p_organization_id: string
          p_reason?: string
          p_role_code: string
          p_spouse_member_id?: string
        }
        Returns: Json
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
      archive_family_record: {
        Args: {
          p_confirm_with_active_members?: boolean
          p_family_id: string
          p_organization_id: string
          p_reason: string
        }
        Returns: Json
      }
      archive_household: {
        Args: {
          p_household_id: string
          p_organization_id: string
          p_reason: string
        }
        Returns: Json
      }
      archive_member_record: {
        Args: {
          p_member_id: string
          p_organization_id: string
          p_reason: string
        }
        Returns: Json
      }
      assign_household_topic: {
        Args: {
          p_household_node_id: string
          p_organization_id: string
          p_planned_for_date?: string
          p_sequence_number?: number
          p_topic_id: string
        }
        Returns: Json
      }
      assign_household_topic_to_meeting: {
        Args: {
          p_household_node_id: string
          p_meeting_id: string
          p_organization_id: string
          p_topic_id: string
        }
        Returns: Json
      }
      assign_member_to_household: {
        Args: {
          p_confirm_governance_mismatch?: boolean
          p_effective_from?: string
          p_household_id: string
          p_member_id: string
          p_organization_id: string
        }
        Returns: Json
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
      can_manage_topic_library: {
        Args: { p_organization_id: string }
        Returns: boolean
      }
      can_read_member_photo: {
        Args: { p_object_name: string }
        Returns: boolean
      }
      can_read_official_document: { Args: { p_name: string }; Returns: boolean }
      can_write_member_photo: {
        Args: { p_object_name: string }
        Returns: boolean
      }
      cancel_event_guest: {
        Args: { p_guest_id: string; p_organization_id: string }
        Returns: Json
      }
      cancel_event_registration: {
        Args: {
          p_event_id: string
          p_member_id?: string
          p_organization_id: string
        }
        Returns: Json
      }
      cancel_household_meeting: {
        Args: {
          p_meeting_id: string
          p_organization_id: string
          p_reason?: string
        }
        Returns: Json
      }
      cancel_household_topic_assignment: {
        Args: {
          p_household_topic_assignment_id: string
          p_organization_id: string
          p_reason_code?: string
        }
        Returns: Json
      }
      change_meeting_topic: {
        Args: {
          p_meeting_id: string
          p_new_topic_id?: string
          p_organization_id: string
          p_other_title?: string
          p_reason_code: string
          p_replaced_assignment_id?: string
        }
        Returns: Json
      }
      change_member_governance_assignment: {
        Args: {
          p_effective_from?: string
          p_member_id: string
          p_organization_id: string
          p_reason?: string
          p_target_governance_node_id?: string
        }
        Returns: Json
      }
      change_member_membership_status: {
        Args: {
          p_effective_from?: string
          p_member_id: string
          p_organization_id: string
          p_reason?: string
          p_target_status_id: string
        }
        Returns: Json
      }
      change_member_section: {
        Args: {
          p_effective_from?: string
          p_member_id: string
          p_organization_id: string
          p_reason?: string
          p_section_code: string
        }
        Returns: Json
      }
      change_members_section_bulk: {
        Args: {
          p_effective_from?: string
          p_member_ids: string[]
          p_organization_id: string
          p_reason?: string
          p_section_code: string
        }
        Returns: Json
      }
      check_in_event_guest: {
        Args: { p_guest_id: string; p_organization_id: string }
        Returns: Json
      }
      check_member_claim_code: {
        Args: { p_client_key: string; p_code: string }
        Returns: Json
      }
      claim_email_has_login: { Args: { p_email: string }; Returns: boolean }
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
      complete_household_meeting: {
        Args: {
          p_actual_end_at?: string
          p_actual_start_at?: string
          p_meeting_id: string
          p_notes_summary?: string
          p_organization_id: string
        }
        Returns: Json
      }
      complete_household_topic: {
        Args: {
          p_household_meeting_id: string
          p_household_topic_assignment_id: string
          p_organization_id: string
        }
        Returns: Json
      }
      conclude_servant_leader: {
        Args: {
          p_effective_to?: string
          p_leadership_assignment_id: string
          p_organization_id: string
          p_reason?: string
        }
        Returns: Json
      }
      create_event: {
        Args: {
          p_audience_code?: string
          p_description?: string
          p_ends_at?: string
          p_event_type: string
          p_formation_talk_id?: string
          p_location_text?: string
          p_organization_id: string
          p_starts_at: string
          p_title: string
        }
        Returns: Json
      }
      create_family: {
        Args: {
          p_confirm_duplicate?: boolean
          p_display_name: string
          p_family_name: string
          p_family_type?: string
          p_formed_on?: string
          p_organization_id: string
        }
        Returns: Json
      }
      create_formation_topic: {
        Args: {
          p_description?: string
          p_objectives?: string
          p_organization_id: string
          p_recommended_duration_minutes?: number
          p_recommended_pastoral_level?: string
          p_scripture_reference?: string
          p_short_title?: string
          p_sort_order?: number
          p_source_type?: string
          p_title: string
          p_topic_code?: string
        }
        Returns: Json
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
      create_household: {
        Args: {
          p_accepts_new_members?: boolean
          p_code: string
          p_effective_from?: string
          p_household_category?: string
          p_is_couple_household?: boolean
          p_language_code?: string
          p_maximum_member_count?: number
          p_meeting_day_of_week?: number
          p_meeting_frequency?: string
          p_meeting_location_text?: string
          p_meeting_location_type?: string
          p_meeting_start_time?: string
          p_meeting_timezone_name?: string
          p_name: string
          p_organization_id: string
          p_parent_governance_node_id: string
          p_pastoral_level?: string
          p_target_member_count?: number
        }
        Returns: Json
      }
      create_household_meeting: {
        Args: {
          p_facilitator_member_id?: string
          p_host_member_id?: string
          p_household_id: string
          p_location_text?: string
          p_location_type?: string
          p_meeting_date: string
          p_meeting_type?: string
          p_notes_summary?: string
          p_organization_id: string
          p_scheduled_end_at?: string
          p_scheduled_start_at?: string
        }
        Returns: Json
      }
      create_member: {
        Args: {
          p_address_country_code?: string
          p_address_line_1?: string
          p_address_line_2?: string
          p_allocate_member_number?: boolean
          p_allow_potential_duplicate?: boolean
          p_birth_date?: string
          p_city_name?: string
          p_civil_status?: string
          p_email?: string
          p_family_name: string
          p_given_names: string
          p_governance_node_id?: string
          p_home_country_code?: string
          p_joined_on?: string
          p_middle_names?: string
          p_organization_id: string
          p_phone?: string
          p_phone_country_code?: string
          p_postal_code?: string
          p_preferred_name?: string
          p_sex?: string
          p_state_province_name?: string
        }
        Returns: Json
      }
      create_program_run: {
        Args: {
          p_chapter_code?: string
          p_description?: string
          p_organization_id: string
          p_program_code: string
          p_section_codes?: string[]
          p_session_count?: number
          p_title: string
        }
        Returns: Json
      }
      create_structure_node: {
        Args: {
          p_name: string
          p_node_type: string
          p_organization_id: string
          p_parent_node_id: string
        }
        Returns: Json
      }
      create_sub_area_sections: {
        Args: { p_organization_id: string; p_sub_area_node_id: string }
        Returns: Json
      }
      end_area_coordinator: {
        Args: {
          p_assignment_id: string
          p_organization_id: string
          p_reason?: string
        }
        Returns: Json
      }
      end_family_membership: {
        Args: {
          p_effective_to?: string
          p_family_member_id: string
          p_organization_id: string
          p_reason?: string
        }
        Returns: Json
      }
      end_family_relationship: {
        Args: {
          p_effective_to?: string
          p_organization_id: string
          p_reason?: string
          p_relationship_id: string
        }
        Returns: Json
      }
      end_household_membership: {
        Args: {
          p_effective_to?: string
          p_member_id: string
          p_organization_id: string
          p_reason?: string
        }
        Returns: Json
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
      execute_pastoral_placement: {
        Args: {
          p_destination_household_id: string
          p_effective_date?: string
          p_include_verified_spouse?: boolean
          p_leadership_assignment_id: string
          p_organization_id: string
          p_reason?: string
        }
        Returns: Json
      }
      finalize_member_account_invitation: {
        Args: {
          p_actor_profile_id: string
          p_auth_user_id: string
          p_email: string
          p_invitation_status?: string
          p_member_id: string
          p_organization_id: string
        }
        Returns: Json
      }
      get_check_in_settings: { Args: { p_organization_id: string }; Returns: Json }
      get_current_authorization_context: {
        Args: { p_organization_id: string }
        Returns: Json
      }
      get_current_profile_context: { Args: never; Returns: Json }
      get_event: {
        Args: { p_event_id: string; p_organization_id: string }
        Returns: Json
      }
      get_event_attendance_roster: {
        Args: { p_event_id: string; p_organization_id: string }
        Returns: Json
      }
      get_event_check_in_summary: {
        Args: { p_event_id: string; p_organization_id: string }
        Returns: Json
      }
      get_event_guests: {
        Args: { p_event_id: string; p_organization_id: string }
        Returns: Json
      }
      get_event_payment_access: {
        Args: { p_event_id: string; p_organization_id: string }
        Returns: Json
      }
      get_event_payments: {
        Args: { p_event_id: string; p_organization_id: string }
        Returns: Json
      }
      get_family_profile: {
        Args: { p_family_id: string; p_organization_id: string }
        Returns: Json
      }
      get_family_relationship_types: {
        Args: { p_organization_id: string }
        Returns: {
          allows_multiple_current: boolean
          code: string
          display_order: number
          inverse_code: string
          is_active: boolean
          is_symmetric: boolean
          name: string
          relationship_category: string
          requires_same_family: boolean
          type_id: string
        }[]
      }
      get_formation_catalog: {
        Args: {
          p_include_inactive?: boolean
          p_organization_id: string
          p_program_category?: string
        }
        Returns: Json
      }
      get_formation_program: {
        Args: { p_organization_id: string; p_program_id: string }
        Returns: Json
      }
      get_household_formation_plan: {
        Args: { p_household_node_id: string; p_organization_id: string }
        Returns: Json
      }
      get_household_meeting_cadence: {
        Args: { p_household_id: string; p_organization_id: string }
        Returns: Json
      }
      get_household_meeting_detail: {
        Args: { p_meeting_id: string; p_organization_id: string }
        Returns: Json
      }
      get_household_meeting_history: {
        Args: {
          p_household_id: string
          p_limit?: number
          p_offset?: number
          p_organization_id: string
        }
        Returns: Json
      }
      get_household_meeting_topics: {
        Args: { p_household_node_id: string; p_organization_id: string }
        Returns: Json
      }
      get_household_profile: {
        Args: { p_household_id: string; p_organization_id: string }
        Returns: Json
      }
      get_household_sections: { Args: { p_organization_id: string }; Returns: Json }
      get_household_topic_history: {
        Args: {
          p_household_node_id: string
          p_limit?: number
          p_offset?: number
          p_organization_id: string
        }
        Returns: Json
      }
      get_member_account_invitation_details: {
        Args: { p_invitation_id?: string }
        Returns: Json
      }
      get_member_account_link_drift: {
        Args: { p_organization_id: string }
        Returns: {
          detail: string
          drift_type: string
          link_id: string
          member_id: string
          profile_id: string
          role_assignment_id: string
        }[]
      }
      get_member_account_status: {
        Args: { p_member_id: string; p_organization_id: string }
        Returns: Json
      }
      get_member_families: {
        Args: { p_member_id: string; p_organization_id: string }
        Returns: {
          active_member_count: number
          display_name: string
          effective_from: string
          effective_to: string
          family_id: string
          family_member_id: string
          family_name: string
          family_role: string
          family_status: string
          family_type: string
          is_dependent: boolean
          is_primary_contact: boolean
        }[]
      }
      get_member_formation_transcript: {
        Args: { p_member_id: string; p_organization_id: string }
        Returns: Json
      }
      get_member_households: {
        Args: { p_member_id: string; p_organization_id: string }
        Returns: Json
      }
      get_member_photo_path: {
        Args: { p_member_id: string; p_organization_id: string }
        Returns: Json
      }
      get_member_photo_paths: {
        Args: { p_member_ids: string[]; p_organization_id: string }
        Returns: Json
      }
      get_member_profile: {
        Args: { p_member_id: string; p_organization_id: string }
        Returns: Json
      }
      get_member_section: {
        Args: { p_member_id: string; p_organization_id: string }
        Returns: Json
      }
      get_member_status_history: {
        Args: { p_member_id: string; p_organization_id: string }
        Returns: {
          change_reason_code: string
          change_summary: string
          effective_from_at: string
          effective_to_at: string
          history_id: string
          is_active_membership: boolean
          is_current: boolean
          recorded_at: string
          recorded_by_name: string
          recorded_by_profile_id: string
          source: string
          status_category: string
          status_code: string
          status_id: string
          status_name: string
        }[]
      }
      get_member_statuses: {
        Args: { p_organization_id: string }
        Returns: {
          code: string
          description: string
          display_order: number
          is_active_membership: boolean
          name: string
          status_category: string
          status_id: string
        }[]
      }
      get_activity_report: {
        Args: { p_day?: string; p_organization_id: string }
        Returns: Json
      }
      get_my_event_access: {
        Args: { p_organization_id: string }
        Returns: Json
      }
      get_my_formation_transcript: {
        Args: { p_organization_id?: string }
        Returns: Json
      }
      get_my_member_card: { Args: { p_organization_id: string }; Returns: Json }
      get_my_push_status: { Args: { p_organization_id: string }; Returns: Json }
      get_my_reminder_preferences: {
        Args: { p_organization_id: string }
        Returns: Json
      }
      get_my_member_context: {
        Args: { p_organization_id: string }
        Returns: Json
      }
      get_my_member_profile: {
        Args: { p_organization_id: string }
        Returns: Json
      }
      get_my_pending_account_invitations: { Args: never; Returns: Json }
      get_my_profile_details: {
        Args: { p_organization_id: string }
        Returns: Json
      }
      get_my_service: { Args: { p_organization_id: string }; Returns: Json }
      get_node_section: {
        Args: { p_node_id: string; p_organization_id: string }
        Returns: Json
      }
      get_official_documents_access: { Args: { p_organization_id: string }; Returns: Json }
      get_official_documents_folder: { Args: { p_organization_id: string }; Returns: string }
      get_pastoral_household_roster: {
        Args: { p_household_id: string; p_organization_id: string }
        Returns: Json
      }
      get_pastoral_operations_dashboard: {
        Args: { p_governance_node_id?: string; p_organization_id: string }
        Returns: Json
      }
      get_pastoral_placement_review: {
        Args: { p_leadership_assignment_id: string; p_organization_id: string }
        Returns: Json
      }
      get_placement_nodes: {
        Args: { p_organization_id: string }
        Returns: {
          governance_node_id: string
          hierarchy_rank: number
          node_code: string
          node_name: string
          node_type_code: string
          parent_governance_node_id: string
          parent_node_name: string
        }[]
      }
      get_placement_worklist: {
        Args: {
          p_organization_id: string
          p_page?: number
          p_page_size?: number
          p_search?: string
          p_section_node_id?: string
          p_view?: string
        }
        Returns: Json
      }
      get_program_run: {
        Args: { p_organization_id: string; p_run_id: string }
        Returns: Json
      }
      get_program_session_roster: {
        Args: { p_event_id: string; p_organization_id: string }
        Returns: Json
      }
      get_section_options: { Args: { p_organization_id: string }; Returns: Json }
      get_sections_overview: {
        Args: { p_organization_id: string }
        Returns: Json
      }
      get_servant_leader_access_status: {
        Args: { p_leadership_assignment_id: string; p_organization_id: string }
        Returns: Json
      }
      get_servant_leader_pastoral_placement_guidance: {
        Args: {
          p_leadership_assignment_id?: string
          p_member_id: string
          p_organization_id: string
        }
        Returns: Json
      }
      get_structure_tree: { Args: { p_organization_id: string }; Returns: Json }
      get_sub_area_placement_targets: {
        Args: { p_organization_id: string; p_sub_area_node_id: string }
        Returns: Json
      }
      get_topic_library_item: {
        Args: { p_organization_id: string; p_topic_id: string }
        Returns: Json
      }
      grant_servant_leader_access: {
        Args: {
          p_leadership_assignment_id: string
          p_organization_id: string
          p_profile_id?: string
        }
        Returns: Json
      }
      ingest_topic_library_page: {
        Args: {
          p_content_blocks: Json
          p_fetched_at?: string
          p_material_kind: string
          p_organization_id: string
          p_series_code: string
          p_series_title: string
          p_source_url: string
          p_title: string
          p_topic_month: string
        }
        Returns: Json
      }
      issue_member_claim_codes: {
        Args: { p_member_ids: string[]; p_organization_id: string }
        Returns: Json
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
      link_member_account: {
        Args: {
          p_member_id: string
          p_organization_id: string
          p_profile_id: string
          p_verification_method: string
          p_verification_summary?: string
        }
        Returns: Json
      }
      list_event_audience_options: {
        Args: { p_organization_id: string }
        Returns: Json
      }
      list_event_formation_talks: {
        Args: { p_organization_id: string }
        Returns: Json
      }
      list_events: {
        Args: { p_from: string; p_organization_id: string; p_to: string }
        Returns: Json
      }
      list_member_login_status: {
        Args: { p_organization_id: string }
        Returns: Json
      }
      list_my_attendance: {
        Args: { p_from?: string; p_organization_id: string; p_to?: string }
        Returns: Json
      }
      list_my_event_guests: {
        Args: { p_organization_id: string }
        Returns: Json
      }
      list_my_event_registrations: {
        Args: { p_organization_id: string }
        Returns: Json
      }
      list_my_events: {
        Args: { p_from: string; p_organization_id: string; p_to: string }
        Returns: Json
      }
      list_my_fraternal_topics: {
        Args: { p_organization_id: string }
        Returns: Json
      }
      list_my_household_meetings: {
        Args: { p_from: string; p_organization_id: string; p_to: string }
        Returns: Json
      }
      list_my_household_topics: {
        Args: { p_organization_id: string }
        Returns: Json
      }
      list_official_documents: { Args: { p_organization_id: string }; Returns: Json }
      list_program_runs: {
        Args: { p_include_closed?: boolean; p_organization_id: string }
        Returns: Json
      }
      list_servant_leader_offices: {
        Args: { p_organization_id: string }
        Returns: Json
      }
      list_topic_library: {
        Args: { p_organization_id: string; p_series_code?: string }
        Returns: Json
      }
      lookup_auth_user_for_invitation: {
        Args: { p_email: string; p_organization_id: string }
        Returns: Json
      }
      mark_official_document_copied: {
        Args: {
          p_copied_md5: string
          p_copied_modified_at: string
          p_drive_file_id: string
          p_file_size: number
          p_organization_id: string
          p_storage_path: string
        }
        Returns: string
      }
      member_assign_fraternal_topic: {
        Args: {
          p_meeting_id: string
          p_organization_id: string
          p_topic_id: string
        }
        Returns: Json
      }
      member_assign_household_topic: {
        Args: {
          p_meeting_id: string
          p_organization_id: string
          p_topic_id: string
        }
        Returns: Json
      }
      member_change_fraternal_meeting_topic: {
        Args: {
          p_meeting_id: string
          p_new_topic_id?: string
          p_organization_id: string
          p_other_title?: string
          p_reason_code: string
          p_replaced_assignment_id?: string
        }
        Returns: Json
      }
      member_change_household_meeting_topic: {
        Args: {
          p_meeting_id: string
          p_new_topic_id?: string
          p_organization_id: string
          p_other_title?: string
          p_reason_code: string
          p_replaced_assignment_id?: string
        }
        Returns: Json
      }
      member_get_household_attendance: {
        Args: { p_meeting_id: string; p_organization_id: string }
        Returns: Json
      }
      member_household_roster: {
        Args: { p_household_id: string; p_organization_id: string }
        Returns: Json
      }
      member_record_household_attendance: {
        Args: {
          p_attendance: Json
          p_complete_meeting?: boolean
          p_meeting_id: string
          p_organization_id: string
        }
        Returns: Json
      }
      member_schedule_household_meeting: {
        Args: {
          p_host_member_id?: string
          p_household_id: string
          p_location_text?: string
          p_location_type?: string
          p_meeting_date: string
          p_organization_id: string
          p_scheduled_start_at?: string
        }
        Returns: Json
      }
      member_set_household_meeting_status: {
        Args: {
          p_meeting_id: string
          p_new_status: string
          p_organization_id: string
        }
        Returns: Json
      }
      member_update_household_meeting: {
        Args: {
          p_host_member_id?: string
          p_location_text?: string
          p_location_type?: string
          p_meeting_date: string
          p_meeting_id: string
          p_organization_id: string
          p_scheduled_start_at?: string
        }
        Returns: Json
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
      move_member_to_sub_area: {
        Args: {
          p_effective_from?: string
          p_member_id: string
          p_organization_id: string
          p_reason?: string
          p_section_code: string
          p_target_governance_node_id: string
        }
        Returns: Json
      }
      official_documents_to_copy: { Args: { p_organization_id: string }; Returns: Json }
      place_members_bulk: {
        Args: {
          p_effective_from: string
          p_member_ids: string[]
          p_organization_id: string
          p_reason: string
          p_target_governance_node_id: string
        }
        Returns: Json
      }
      post_event_attendance_to_formation: {
        Args: { p_event_id: string; p_organization_id: string }
        Returns: Json
      }
      prepare_member_account_invitation: {
        Args: {
          p_acknowledge_shared?: boolean
          p_email: string
          p_member_id: string
          p_organization_id: string
        }
        Returns: Json
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
      record_my_app_open: { Args: { p_organization_id: string }; Returns: undefined }
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
      record_event_guest_payment: {
        Args: {
          p_amount: number
          p_guest_id: string
          p_organization_id: string
          p_payment_method: string
        }
        Returns: Json
      }
      record_event_payment: {
        Args: {
          p_amount: number
          p_event_id: string
          p_member_id: string
          p_organization_id: string
          p_payment_method: string
        }
        Returns: Json
      }
      record_household_meeting_attendance: {
        Args: {
          p_attendance: Json
          p_meeting_id: string
          p_organization_id: string
        }
        Returns: Json
      }
      record_member_account_invitation_failure: {
        Args: {
          p_actor_profile_id: string
          p_email: string
          p_failure_reason: string
          p_member_id: string
          p_organization_id: string
        }
        Returns: Json
      }
      record_member_deceased: {
        Args: {
          p_deceased_on?: string
          p_deceased_on_precision?: string
          p_effective_from?: string
          p_member_id: string
          p_organization_id: string
          p_reason?: string
        }
        Returns: Json
      }
      record_member_formation_program: {
        Args: {
          p_completed_date?: string
          p_completed_month?: number
          p_completed_year?: number
          p_date_precision?: string
          p_member_id: string
          p_organization_id: string
          p_program_id: string
          p_source_reference?: string
          p_status: string
          p_verification_method?: string
          p_verification_notes?: string
        }
        Returns: Json
      }
      record_member_formation_talk: {
        Args: {
          p_attended_date?: string
          p_notes?: string
          p_organization_id: string
          p_program_record_id: string
          p_session_status: string
          p_talk_id: string
        }
        Returns: Json
      }
      record_official_documents_sync_run: {
        Args: {
          p_error: string
          p_failed: number
          p_listed: number
          p_new: number
          p_organization_id: string
          p_pending: number
          p_removed: number
          p_skipped: number
          p_trigger_source: string
          p_updated: number
        }
        Returns: string
      }
      record_topic_library_sync_run: {
        Args: {
          p_changed_count: number
          p_failed_count: number
          p_new_count: number
          p_newest_month: string
          p_organization_id: string
          p_run_by_profile_id?: string
          p_trigger_source: string
          p_unchanged_count: number
        }
        Returns: string
      }
      redeem_member_claim_code: {
        Args: {
          p_auth_user_id: string
          p_client_key: string
          p_code: string
          p_email: string
        }
        Returns: Json
      }
      register_for_event: {
        Args: {
          p_event_id: string
          p_member_id?: string
          p_organization_id: string
          p_walk_in?: boolean
        }
        Returns: Json
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
      remove_my_push_subscription: {
        Args: { p_endpoint: string; p_organization_id: string }
        Returns: Json
      }
      reissue_member_card: {
        Args: {
          p_member_id?: string
          p_organization_id: string
          p_reason?: string
        }
        Returns: Json
      }
      rename_structure_node: {
        Args: { p_name: string; p_node_id: string; p_organization_id: string }
        Returns: Json
      }
      repair_family_relationship_reciprocal: {
        Args: {
          p_organization_id: string
          p_reason: string
          p_relationship_id: string
        }
        Returns: Json
      }
      replace_servant_leader: {
        Args: {
          p_effective_date?: string
          p_governance_node_id: string
          p_new_member_id: string
          p_organization_id: string
          p_reason?: string
          p_role_code: string
        }
        Returns: Json
      }
      reschedule_household_topic: {
        Args: {
          p_household_topic_assignment_id: string
          p_organization_id: string
          p_planned_for_date: string
        }
        Returns: Json
      }
      resolve_member_qr: {
        Args: { p_organization_id: string; p_payload: string }
        Returns: Json
      }
      restore_member_record: {
        Args: {
          p_member_id: string
          p_organization_id: string
          p_reason: string
        }
        Returns: Json
      }
      retire_structure_node: {
        Args: { p_node_id: string; p_organization_id: string; p_reason?: string }
        Returns: Json
      }
      revert_member_deceased: {
        Args: {
          p_effective_from?: string
          p_member_id: string
          p_organization_id: string
          p_reason?: string
        }
        Returns: Json
      }
      review_topic_content_version: {
        Args: {
          p_decision: string
          p_notes?: string
          p_organization_id: string
          p_version_id: string
        }
        Returns: Json
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
      revoke_member_claim_code: {
        Args: { p_member_id: string; p_organization_id: string }
        Returns: Json
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
      revoke_servant_leader_access: {
        Args: {
          p_grant_id?: string
          p_leadership_assignment_id?: string
          p_organization_id: string
          p_reason?: string
        }
        Returns: Json
      }
      scan_event_check_in: {
        Args: {
          p_event_id: string
          p_organization_id: string
          p_payload: string
        }
        Returns: Json
      }
      search_formation_topics: {
        Args: {
          p_limit?: number
          p_offset?: number
          p_organization_id: string
          p_pastoral_level?: string
          p_search?: string
          p_source_type?: string
        }
        Returns: Json
      }
      search_households: {
        Args: {
          p_lifecycle_status?: string
          p_limit?: number
          p_offset?: number
          p_organization_id: string
          p_parent_governance_node_id?: string
          p_search?: string
        }
        Returns: Json
      }
      search_members: {
        Args: {
          p_organization_id: string
          p_page?: number
          p_page_size?: number
          p_record_status?: string
          p_search?: string
          p_status_ids?: string[]
        }
        Returns: Json
      }
      search_members_for_event_payment: {
        Args: { p_event_id: string; p_organization_id: string; p_query: string }
        Returns: Json
      }
      search_members_without_household: {
        Args: {
          p_limit?: number
          p_offset?: number
          p_organization_id: string
          p_search?: string
        }
        Returns: Json
      }
      search_servant_leader_access_reconciliation: {
        Args: { p_organization_id: string }
        Returns: Json
      }
      search_servant_leaders_needing_pastoral_placement: {
        Args: {
          p_include_correct?: boolean
          p_limit?: number
          p_offset?: number
          p_organization_id: string
        }
        Returns: Json
      }
      set_accept_legacy_id_cards: {
        Args: { p_accept: boolean; p_organization_id: string }
        Returns: Json
      }
      set_event_attendance: {
        Args: {
          p_check_in_method?: string
          p_event_id: string
          p_member_ids: string[]
          p_organization_id: string
          p_present?: boolean
        }
        Returns: Json
      }
      set_event_fee: {
        Args: {
          p_event_id: string
          p_fee_amount?: number
          p_organization_id: string
        }
        Returns: Json
      }
      set_event_fee_waiver: {
        Args: {
          p_event_id: string
          p_member_id: string
          p_organization_id: string
          p_waived: boolean
        }
        Returns: Json
      }
      set_event_greeter: {
        Args: {
          p_assign?: boolean
          p_event_id: string
          p_member_id: string
          p_organization_id: string
        }
        Returns: Json
      }
      set_event_guest_fee: {
        Args: {
          p_event_id: string
          p_guest_fee?: number
          p_organization_id: string
        }
        Returns: Json
      }
      set_event_guest_waiver: {
        Args: {
          p_guest_id: string
          p_organization_id: string
          p_waived: boolean
        }
        Returns: Json
      }
      set_event_pricing: {
        Args: {
          p_child_fee?: number
          p_early_bird_fee?: number
          p_early_bird_until?: string
          p_event_id: string
          p_fee_amount?: number
          p_organization_id: string
          p_registration_open?: boolean
          p_walk_in_fee?: number
        }
        Returns: Json
      }
      set_event_status: {
        Args: {
          p_event_id: string
          p_organization_id: string
          p_reason?: string
          p_status: string
        }
        Returns: Json
      }
      set_finance_coordinator: {
        Args: {
          p_active: boolean
          p_member_id: string
          p_organization_id: string
          p_role_title: string
        }
        Returns: Json
      }
      set_household_section: {
        Args: {
          p_household_id: string
          p_organization_id: string
          p_section_node_id: string
        }
        Returns: Json
      }
      set_member_contact_point: {
        Args: {
          p_address_data?: Json
          p_contact_type: string
          p_effective_from?: string
          p_member_id: string
          p_operation: string
          p_organization_id: string
          p_phone_country_code?: string
          p_reason?: string
          p_target_id?: string
          p_value?: string
        }
        Returns: Json
      }
      set_member_number: {
        Args: {
          p_member_id: string
          p_member_number: string
          p_organization_id: string
          p_reason?: string
        }
        Returns: Json
      }
      set_member_photo: {
        Args: {
          p_member_id?: string
          p_organization_id: string
          p_storage_path?: string
        }
        Returns: Json
      }
      set_my_contact_point: {
        Args: {
          p_address_data?: Json
          p_contact_type: string
          p_operation: string
          p_organization_id: string
          p_target_id?: string
          p_value?: string
        }
        Returns: Json
      }
      set_my_wedding_date: {
        Args: { p_organization_id: string; p_wedding_date: string }
        Returns: Json
      }
      set_official_documents_folder: {
        Args: { p_drive_folder_id: string; p_organization_id: string }
        Returns: Json
      }
      set_program_participant_attendance: {
        Args: {
          p_event_id: string
          p_organization_id: string
          p_participant_ids: string[]
          p_present?: boolean
        }
        Returns: Json
      }
      set_program_participant_status: {
        Args: {
          p_organization_id: string
          p_participant_id: string
          p_status: string
        }
        Returns: Json
      }
      set_program_run_status: {
        Args: {
          p_organization_id: string
          p_reason?: string
          p_run_id: string
          p_status: string
        }
        Returns: Json
      }
      show_limit: { Args: never; Returns: number }
      show_trgm: { Args: { "": string }; Returns: string[] }
      set_servant_leader_interim: {
        Args: {
          p_is_interim: boolean
          p_leadership_assignment_id: string
          p_organization_id: string
        }
        Returns: Json
      }
      get_event_replies: {
        Args: { p_event_id: string; p_organization_id: string }
        Returns: Json
      }
      get_meeting_replies: {
        Args: { p_household_meeting_id: string; p_organization_id: string }
        Returns: Json
      }
      list_my_replies: {
        Args: { p_organization_id: string }
        Returns: Json
      }
      set_my_reply: {
        Args: {
          p_event_id?: string
          p_household_meeting_id?: string
          p_organization_id: string
          p_response?: string
        }
        Returns: Json
      }
      get_payment_details: {
        Args: { p_event_id?: string; p_organization_id: string }
        Returns: Json
      }
      list_event_payment_reports: {
        Args: { p_event_id: string; p_organization_id: string }
        Returns: Json
      }
      list_my_payment_reports: {
        Args: { p_organization_id: string }
        Returns: Json
      }
      report_my_event_payment: {
        Args: {
          p_amount: number
          p_event_id: string
          p_organization_id: string
          p_payment_method: string
          p_reference?: string
          p_report_kind?: string
        }
        Returns: Json
      }
      review_event_payment_report: {
        Args: {
          p_confirm: boolean
          p_decline_reason?: string
          p_organization_id: string
          p_report_id: string
        }
        Returns: Json
      }
      save_my_push_subscription: {
        Args: {
          p_auth: string
          p_device_label?: string
          p_endpoint: string
          p_organization_id: string
          p_p256dh: string
        }
        Returns: Json
      }
      set_my_reminder_preferences: {
        Args: { p_email_enabled: boolean; p_organization_id: string }
        Returns: Json
      }
      set_payment_details: {
        Args: {
          p_cash_check_note?: string
          p_check_mailing_address?: string
          p_check_payable_to?: string
          p_event_id?: string
          p_organization_id: string
          p_payment_note?: string
          p_paypal_link?: string
          p_zelle_name?: string
          p_zelle_recipient?: string
        }
        Returns: Json
      }
      verify_docs_sync_secret: { Args: { p_secret: string }; Returns: boolean }
      withdraw_my_payment_report: {
        Args: { p_organization_id: string; p_report_id: string }
        Returns: Json
      }
      skip_household_topic: {
        Args: {
          p_household_topic_assignment_id: string
          p_organization_id: string
          p_reason_code?: string
        }
        Returns: Json
      }
      suspend_profile_role_assignment: {
        Args: {
          p_actor_profile_id: string
          p_assignment_id: string
          p_reason: string
        }
        Returns: undefined
      }
      transfer_household_member: {
        Args: {
          p_confirm_governance_mismatch?: boolean
          p_destination_household_id: string
          p_effective_date?: string
          p_member_id: string
          p_organization_id: string
          p_reason?: string
        }
        Returns: Json
      }
      unlink_member_account: {
        Args: {
          p_organization_id: string
          p_profile_id: string
          p_reason: string
        }
        Returns: Json
      }
      update_event: {
        Args: {
          p_audience_code?: string
          p_description?: string
          p_ends_at?: string
          p_event_id: string
          p_event_type: string
          p_formation_talk_id?: string
          p_location_text?: string
          p_organization_id: string
          p_starts_at: string
          p_title: string
        }
        Returns: Json
      }
      update_family_identity: {
        Args: {
          p_display_name: string
          p_family_id: string
          p_family_name: string
          p_family_type?: string
          p_formed_on?: string
          p_organization_id: string
        }
        Returns: Json
      }
      update_family_member: {
        Args: {
          p_family_member_id: string
          p_family_role: string
          p_is_dependent: boolean
          p_is_primary_contact: boolean
          p_organization_id: string
        }
        Returns: Json
      }
      update_household: {
        Args: {
          p_accepts_new_members?: boolean
          p_code: string
          p_household_category?: string
          p_household_id: string
          p_is_couple_household?: boolean
          p_language_code?: string
          p_maximum_member_count?: number
          p_meeting_day_of_week?: number
          p_meeting_frequency?: string
          p_meeting_location_text?: string
          p_meeting_location_type?: string
          p_meeting_start_time?: string
          p_meeting_timezone_name?: string
          p_name: string
          p_organization_id: string
          p_pastoral_level?: string
          p_target_member_count?: number
        }
        Returns: Json
      }
      update_member_basic_profile: {
        Args: {
          p_birth_date?: string
          p_change_reason?: string
          p_civil_status?: string
          p_effective_from?: string
          p_family_name: string
          p_given_names: string
          p_home_country_code?: string
          p_is_name_change?: boolean
          p_member_id: string
          p_middle_names?: string
          p_organization_id: string
          p_preferred_language_code?: string
          p_preferred_name?: string
          p_sex?: string
        }
        Returns: Json
      }
      update_my_basic_profile: {
        Args: {
          p_birth_date?: string
          p_family_name: string
          p_given_names: string
          p_middle_names?: string
          p_organization_id: string
          p_preferred_name?: string
          p_sex?: string
        }
        Returns: Json
      }
      update_program_participant: {
        Args: {
          p_email?: string
          p_first_name?: string
          p_invited_by_member_id?: string
          p_last_name?: string
          p_notes?: string
          p_organization_id: string
          p_participant_id: string
          p_phone?: string
        }
        Returns: Json
      }
      update_program_run: {
        Args: {
          p_description?: string
          p_organization_id: string
          p_run_id: string
          p_title: string
        }
        Returns: Json
      }
      update_program_session: {
        Args: {
          p_ends_at?: string
          p_event_id: string
          p_location_text?: string
          p_organization_id: string
          p_starts_at: string
        }
        Returns: Json
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
      verify_topic_sync_secret: { Args: { p_secret: string }; Returns: boolean }
      void_event_guest_payment: {
        Args: { p_organization_id: string; p_payment_id: string }
        Returns: Json
      }
      void_event_payment: {
        Args: { p_organization_id: string; p_payment_id: string }
        Returns: Json
      }
      void_member_formation_program_record: {
        Args: {
          p_organization_id: string
          p_record_id: string
          p_void_reason: string
        }
        Returns: Json
      }
      void_member_formation_talk_record: {
        Args: {
          p_organization_id: string
          p_talk_record_id: string
          p_void_reason: string
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
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
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
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
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
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
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
