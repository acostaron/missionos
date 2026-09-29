import { useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '../../../lib/supabase/client';
import { memberKeys } from '../queries';

export interface RevertMemberDeceasedInput {
  organizationId: string;
  memberId: string;
  effectiveFrom: string; // YYYY-MM-DD
  reason: string;
}

export interface RevertMemberDeceasedResponse {
  status: 'success';
  member_id: string;
  previous_status_id: string;
  previous_status_code: string;
  restored_status_id: string;
  restored_status_code: string;
  is_deceased: false;
  effective_from: string;
}

export function useRevertMemberDeceased() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({
      organizationId,
      memberId,
      effectiveFrom,
      reason,
    }: RevertMemberDeceasedInput): Promise<RevertMemberDeceasedResponse> => {
      const { data, error } = await supabase.rpc('revert_member_deceased', {
        p_organization_id: organizationId,
        p_member_id: memberId,
        p_effective_from: effectiveFrom,
        p_reason: reason,
      });

      if (error) throw error;
      return data as unknown as RevertMemberDeceasedResponse;
    },

    onSuccess: (_data, variables) => {
      // Invalidate profile, active member lists, and status history
      queryClient.invalidateQueries({
        queryKey: memberKeys.profile(variables.organizationId, variables.memberId),
      });
      queryClient.invalidateQueries({
        queryKey: memberKeys.lists(),
      });
      queryClient.invalidateQueries({
        queryKey: memberKeys.statusHistory(variables.organizationId, variables.memberId),
      });
    },
  });
}
