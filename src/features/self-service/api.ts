import { useQuery } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase/client';

export interface MyMemberContext {
  organization_id: string;
  profile: { display_name: string | null };
  member: {
    member_id: string;
    member_number: string | null;
    display_name: string;
    membership_status: string | null;
  };
  household: {
    household_id: string;
    household_name: string;
    pastoral_level: string | null;
    leader_display_name: string | null;
    parent_node_name: string | null;
    meeting_frequency: string | null;
    meeting_day_of_week: number | null;
    meeting_start_time: string | null;
    meeting_timezone_name: string | null;
  } | null;
  organizational_context: {
    area: string | null;
    section: string | null;
    chapter: string | null;
    unit: string | null;
  };
}

export interface MyMemberProfile extends MyMemberContext {
  details: {
    preferred_name: string | null;
    joined_on: string | null;
    preferred_language_code: string | null;
  };
  contact: {
    primary_email: string | null;
    primary_phone: string | null;
  };
}

export const selfServiceKeys = {
  all: ['member-self-service'] as const,
  context: (orgId: string) => [...selfServiceKeys.all, 'context', orgId] as const,
  profile: (orgId: string) => [...selfServiceKeys.all, 'profile', orgId] as const,
};

export async function fetchMyMemberContext(organizationId: string): Promise<MyMemberContext> {
  const { data, error } = await supabase.rpc('get_my_member_context', {
    p_organization_id: organizationId,
  });
  if (error) throw error;
  return data as unknown as MyMemberContext;
}

export async function fetchMyMemberProfile(organizationId: string): Promise<MyMemberProfile> {
  const { data, error } = await supabase.rpc('get_my_member_profile', {
    p_organization_id: organizationId,
  });
  if (error) throw error;
  return data as unknown as MyMemberProfile;
}

export function useMyMemberContext(organizationId: string | null, enabled: boolean = true) {
  return useQuery({
    queryKey: organizationId ? selfServiceKeys.context(organizationId) : selfServiceKeys.all,
    queryFn: () => {
      if (!organizationId) throw new Error('organizationId is required');
      return fetchMyMemberContext(organizationId);
    },
    enabled: !!organizationId && enabled,
    staleTime: 60 * 1000,
    retry: false,
  });
}

export function useMyMemberProfile(organizationId: string | null, enabled: boolean = true) {
  return useQuery({
    queryKey: organizationId ? selfServiceKeys.profile(organizationId) : selfServiceKeys.all,
    queryFn: () => {
      if (!organizationId) throw new Error('organizationId is required');
      return fetchMyMemberProfile(organizationId);
    },
    enabled: !!organizationId && enabled,
    staleTime: 60 * 1000,
    retry: false,
  });
}
