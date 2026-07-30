import type { PermissionCode } from './permissions';

export type CurrentOrganization = {
  id: string;
  code: string;
  name: string;
  short_name: string | null;
};

export type OrganizationMembership = {
  id: string;
  organization_id: string;
  organization: CurrentOrganization;
  is_default: boolean;
  membership_status: string;
  effective_from_at: string;
  effective_to_at: string | null;
};

export type ProfileContext = {
  profile: {
    id: string;
    display_name: string;
    account_status: string;
    is_platform_administrator: boolean;
  } | null;
  memberships: OrganizationMembership[];
  member_links: {
    id: string;
    organization_id: string;
    member_id: string;
    link_type: string;
    link_status: string;
    is_primary: boolean;
    verification_method: string;
    verified_at: string;
  }[];
};

export type AuthorizationContext = {
  profile_id: string;
  organization_id: string;
  roles: {
    id: string;
    organization_id: string | null;
    app_role_id: string;
    role_code: string;
    role_name: string;
    role_category: string;
    risk_level: string;
    source_type: string;
    assignment_status: string;
    effective_from_at: string;
    effective_to_at: string | null;
  }[];
  scopes: {
    id: string;
    profile_role_assignment_id: string;
    scope_type: string;
    scope_effect: string;
    governance_node_id: string | null;
    section_node_id: string | null;
    member_id: string | null;
    entity_type: string | null;
    entity_id: string | null;
    includes_descendants: boolean;
    maximum_descendant_depth: number | null;
    assignment_status: string;
    effective_from_at: string;
    effective_to_at: string | null;
  }[];
  permissions: {
    code: PermissionCode;
    state: 'allow' | 'deny' | 'none';
  }[];
};
