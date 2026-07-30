import { useQuery } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase/client';
import type { ProfileContext } from '../../types/auth';

export const identityKeys = {
  profileContext: ['identity', 'profile-context'] as const,
};

export function useProfileContextQuery() {
  return useQuery({
    queryKey: identityKeys.profileContext,
    queryFn: async () => {
      const { data, error } = await (supabase.rpc as any)('get_current_profile_context');
      if (error) throw error;
      return (data as unknown) as ProfileContext;
    },
  });
}
