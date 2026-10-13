import { useQuery, useMutation, useQueryClient, keepPreviousData } from '@tanstack/react-query';
import { fetchPlacementWorklist, placeMembersBulk } from './api';
import { memberKeys } from '../members/queries';
import { pastoralDashboardKeys } from '../households/api/get-pastoral-operations-dashboard';
import type {
  FetchPlacementWorklistParams,
  PlacementWorklistResponse,
  PlaceMembersBulkParams,
  PlaceMembersBulkResponse,
} from './types';

export const placementKeys = {
  all: ['placement'] as const,
  worklists: () => [...placementKeys.all, 'worklist'] as const,
  worklist: (orgId: string, params: FetchPlacementWorklistParams) =>
    [...placementKeys.worklists(), orgId, params] as const,
};

export function usePlacementWorklist(
  orgId: string | null,
  params: FetchPlacementWorklistParams,
  enabled: boolean = true
) {
  return useQuery<PlacementWorklistResponse>({
    queryKey: orgId ? placementKeys.worklist(orgId, params) : ['placement', 'disabled'],
    queryFn: () => {
      if (!orgId) throw new Error('Organization ID is required');
      return fetchPlacementWorklist(orgId, params);
    },
    enabled: !!orgId && enabled,
    placeholderData: keepPreviousData,
  });
}

export function usePlaceMembersBulk(orgId: string | null) {
  const queryClient = useQueryClient();

  return useMutation<PlaceMembersBulkResponse, Error, PlaceMembersBulkParams>({
    mutationFn: (params) => {
      if (!orgId) throw new Error('Organization ID is required');
      return placeMembersBulk(orgId, params);
    },
    onSuccess: () => {
      // Invalidate placement queries
      queryClient.invalidateQueries({ queryKey: placementKeys.all });
      // Invalidate member directory & profile queries
      queryClient.invalidateQueries({ queryKey: memberKeys.all });
      // Invalidate pastoral operations dashboard queries
      queryClient.invalidateQueries({ queryKey: pastoralDashboardKeys.all });
    },
  });
}
