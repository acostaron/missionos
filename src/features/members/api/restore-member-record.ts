import { useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '../../../lib/supabase/client';
import { memberKeys } from '../queries';

export interface RestoreMemberRecordInput {
  organizationId: string;
  memberId: string;
  reason: string;
}

export interface RestoreMemberRecordResponse {
  status: 'success';
  member_id: string;
  previous_record_status: string;
  new_record_status: string;
  restore_reason: string;
}

export function useRestoreMemberRecord() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({
      organizationId,
      memberId,
      reason,
    }: RestoreMemberRecordInput): Promise<RestoreMemberRecordResponse> => {
      const { data, error } = await supabase.rpc('restore_member_record', {
        p_organization_id: organizationId,
        p_member_id: memberId,
        p_reason: reason,
      });

      if (error) throw error;
      return data as unknown as RestoreMemberRecordResponse;
    },

    onSuccess: (_data, variables) => {
      // Invalidate profile and active member lists.
      // Do NOT invalidate statusHistory — membership status history is unchanged by restore.
      queryClient.invalidateQueries({
        queryKey: memberKeys.profile(variables.organizationId, variables.memberId),
      });
      queryClient.invalidateQueries({
        queryKey: memberKeys.lists(),
      });
    },
  });
}
