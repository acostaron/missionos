import { supabase } from '../../../lib/supabase/client';

export interface AcceptInvitationResult {
  invitation_id: string;
  status: 'accepted' | 'already_accepted';
  organization_id: string;
  member_id: string;
  profile_id: string;
  link_id?: string;
  link_status?: string;
  member_access_status?: string;
  accepted_at?: string;
  message?: string;
}

export interface InvitationDetails {
  invitation_id: string;
  status: string;
  organization_id: string;
  organization_name: string;
  member_id: string;
  member_name: string;
  email: string;
  invited_at: string;
  expires_at: string | null;
  is_expired: boolean;
  can_accept: boolean;
  unusable_reason: string | null;
}

export async function fetchInvitationDetails(invitationId?: string): Promise<InvitationDetails> {
  const { data, error } = await supabase.rpc('get_member_account_invitation_details', {
    p_invitation_id: invitationId ?? undefined,
  });
  if (error) throw error;
  return data as unknown as InvitationDetails;
}

export async function acceptMemberAccountInvitation(invitationId?: string): Promise<AcceptInvitationResult> {
  const { data, error } = await supabase.rpc('accept_member_account_invitation', {
    p_invitation_id: invitationId ?? undefined,
  });
  if (error) throw error;
  return data as unknown as AcceptInvitationResult;
}
