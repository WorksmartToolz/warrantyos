// Auto-generated shape matches Supabase's generated format.
// Regenerate with: npx supabase gen types typescript --project-id <id> > types/database.ts

export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  public: {
    Tables: {
      tenants: {
        Row: {
          id: string
          name: string
          slug: string
          status: 'active' | 'suspended' | 'terminated'
          settings: Json
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          name: string
          slug: string
          status?: 'active' | 'suspended' | 'terminated'
          settings?: Json
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          name?: string
          slug?: string
          status?: 'active' | 'suspended' | 'terminated'
          settings?: Json
          created_at?: string
          updated_at?: string
        }
      }
      users: {
        Row: {
          id: string
          tenant_id: string
          email: string
          role: 'admin' | 'reviewer' | 'viewer'
          full_name: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id: string
          tenant_id: string
          email: string
          role: 'admin' | 'reviewer' | 'viewer'
          full_name?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          tenant_id?: string
          email?: string
          role?: 'admin' | 'reviewer' | 'viewer'
          full_name?: string | null
          created_at?: string
          updated_at?: string
        }
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      get_user_tenant_id: {
        Args: Record<PropertyKey, never>
        Returns: string
      }
    }
    Enums: {
      [_ in never]: never
    }
  }
}

// Convenience aliases
export type Tenant = Database['public']['Tables']['tenants']['Row']
export type TenantInsert = Database['public']['Tables']['tenants']['Insert']
export type TenantUpdate = Database['public']['Tables']['tenants']['Update']

export type User = Database['public']['Tables']['users']['Row']
export type UserInsert = Database['public']['Tables']['users']['Insert']
export type UserUpdate = Database['public']['Tables']['users']['Update']

export type UserRole = User['role']
export type TenantStatus = Tenant['status']
