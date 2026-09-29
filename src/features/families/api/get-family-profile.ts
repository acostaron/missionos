import { useQuery } from '@tanstack/react-query';
import { supabase } from '../../../lib/supabase/client';
import { familyKeys } from '../queries';
import type { FamilyProfile } from '../types';

export async function fetchFamilyProfile(
  organizationId: string,
  familyId: string
): Promise<FamilyProfile> {
  const { data, error } = await supabase.rpc('get_family_profile', {
    p_organization_id: organizationId,
    p_family_id: familyId,
  });

  if (error) throw error;
  return data as unknown as FamilyProfile;
}

export function useFamilyProfile(
  organizationId: string | null,
  familyId: string | null,
  enabled: boolean = true
) {
  return useQuery({
    queryKey:
      organizationId && familyId
        ? familyKeys.profile(organizationId, familyId)
        : familyKeys.all,
    queryFn: () => {
      if (!organizationId) throw new Error('organizationId is required');
      if (!familyId) throw new Error('familyId is required');
      return fetchFamilyProfile(organizationId, familyId);
    },
    enabled: !!organizationId && !!familyId && enabled,
    staleTime: 60 * 1000,
    retry: (failureCount, error) => {
      const supabaseError = error as { code?: string };
      if (supabaseError?.code === 'P0002' || supabaseError?.code === '42501') {
        return false;
      }
      return failureCount < 2;
    },
  });
}
