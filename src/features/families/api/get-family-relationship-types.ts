import { useQuery } from '@tanstack/react-query';
import { supabase } from '../../../lib/supabase/client';
import type { FamilyRelationshipType } from '../types';

export async function getFamilyRelationshipTypes(
  organizationId: string
): Promise<FamilyRelationshipType[]> {
  const { data, error } = await supabase.rpc('get_family_relationship_types', {
    p_organization_id: organizationId,
  });

  if (error) throw error;
  return (data || []) as unknown as FamilyRelationshipType[];
}

export function useFamilyRelationshipTypes(
  organizationId: string | null,
  enabled: boolean = true
) {
  return useQuery({
    queryKey: ['family_relationship_types', organizationId],
    queryFn: () => getFamilyRelationshipTypes(organizationId!),
    enabled: enabled && !!organizationId,
    staleTime: 1000 * 60 * 60, // Reference data: cache for 1 hour
  });
}
