import { useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '../../../lib/supabase/client';
import { memberKeys } from '../queries';

export interface SetMemberNumberInput {
  organizationId: string;
  memberId: string;
  memberNumber: string;
  reason?: string | null;
}

export interface SetMemberNumberResponse {
  status: 'success';
  member_id: string;
  member_number: string;
  previous_member_number: string | null;
}

export async function setMemberNumber({
  organizationId,
  memberId,
  memberNumber,
  reason,
}: SetMemberNumberInput): Promise<SetMemberNumberResponse> {
  const { data, error } = await (supabase.rpc as any)('set_member_number', {
    p_organization_id: organizationId,
    p_member_id: memberId,
    p_member_number: memberNumber.trim(),
    p_reason: reason && reason.trim().length > 0 ? reason.trim() : null,
  });

  if (error) {
    throw error;
  }

  return data as unknown as SetMemberNumberResponse;
}

export function useSetMemberNumber() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: setMemberNumber,
    onSuccess: (_data, variables) => {
      queryClient.invalidateQueries({
        queryKey: memberKeys.profile(variables.organizationId, variables.memberId),
      });
      queryClient.invalidateQueries({
        queryKey: memberKeys.lists(),
      });
    },
  });
}
