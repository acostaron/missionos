import { supabase } from '../../../lib/supabase/client';
import type {
  MemberAccountStatus,
  ProvisionMemberAccountParams,
  ProvisionMemberAccountResult,
} from './types';

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

export async function fetchMemberAccountStatus(
  organizationId: string,
  memberId: string
): Promise<MemberAccountStatus> {
  const { data, error } = await supabase.rpc('get_member_account_status', {
    p_organization_id: organizationId,
    p_member_id: memberId,
  });
  if (error) throw error;
  return data as unknown as MemberAccountStatus;
}

export async function provisionMemberAccount(
  params: ProvisionMemberAccountParams
): Promise<ProvisionMemberAccountResult> {
  const { organization_id, member_id, email, acknowledge_shared } = params;

  const { data, error } = await supabase.functions.invoke('provision-member-account', {
    body: {
      organization_id,
      member_id,
      email: email.trim().toLowerCase(),
      acknowledge_shared: !!acknowledge_shared,
    },
  });

  if (error) {
    let errBody: {
      error?: string;
      code?: string;
      status?: string;
      warning?: string;
    } | null = null;

    try {
      const errContext = (error as unknown as { context?: Response }).context;
      if (errContext && typeof errContext.json === 'function') {
        errBody = await errContext.json();
      } else if (typeof error.message === 'string') {
        try {
          errBody = JSON.parse(error.message);
        } catch {
          // non-json error message
        }
      }
    } catch {
      // fallback
    }

    if (errBody?.status === 'requires_shared_acknowledgment') {
      return {
        success: false,
        status: 'requires_shared_acknowledgment',
        warning:
          errBody.error ||
          errBody.warning ||
          "This email is shared with another member or family record. MissionOS accounts are individual. Confirm that this email should be used for this member's account.",
        is_shared_email: true,
      };
    }

    const code = errBody?.code;
    const rawMsg = errBody?.error || error.message || '';

    if (code === '23505') {
      if (rawMsg.toLowerCase().includes('different member')) {
        return {
          success: false,
          status: 'error',
          code: '23505',
          message: "This email is already connected to another member's account.",
        };
      }
      return {
        success: false,
        status: 'error',
        code: '23505',
        message: 'This member already has an active MissionOS account.',
      };
    }

    if (code === 'ACCOUNT_UNUSABLE') {
      return {
        success: false,
        status: 'error',
        code: 'ACCOUNT_UNUSABLE',
        message:
          'This account cannot currently be used for a new invitation. Please review the account status.',
      };
    }

    if (
      rawMsg.toLowerCase().includes('already pending') ||
      rawMsg.toLowerCase().includes('active invitation')
    ) {
      return {
        success: false,
        status: 'error',
        message: 'An invitation is already pending.',
      };
    }

    if (rawMsg.toLowerCase().includes('not authorized') || code === '42501') {
      return {
        success: false,
        status: 'error',
        code: '42501',
        message: 'You are not authorized to send MissionOS invitations.',
      };
    }

    return {
      success: false,
      status: 'error',
      message: 'Unable to send the invitation right now. Please try again.',
    };
  }

  if (!data || !data.invitation_id) {
    return {
      success: false,
      status: 'error',
      message: 'Unable to send the invitation right now. Please try again.',
    };
  }

  return {
    success: true,
    invitation_id: data.invitation_id,
    member_id: data.member_id,
    profile_id: data.profile_id,
    organization_id: data.organization_id,
    status: data.status,
    email: data.email,
    invited_at: data.invited_at,
  };
}
