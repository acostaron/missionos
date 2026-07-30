import { useQuery } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase/client';
import type { AuthorizationContext } from '../../types/auth';

export const authorizationKeys = {
  all: ['authorization'] as const,
  context: (orgId: string) => [...authorizationKeys.all, 'context', orgId] as const,
};

export function useAuthorizationContextQuery(organizationId: string | null) {
  return useQuery({
    queryKey: organizationId ? authorizationKeys.context(organizationId) : [],
    queryFn: async () => {
      if (!organizationId) return null;
      const { data, error } = await (supabase.rpc as any)('get_current_authorization_context', {
        p_organization_id: organizationId
      });
      if (error) throw error;
      return (data as unknown) as AuthorizationContext;
    },
    enabled: !!organizationId,
  });
}
