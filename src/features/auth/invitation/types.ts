// =============================================================================
// Member Account Invitation & Status Types
// MissionOS Stage 2B — Pass 2H-3: Admin Member Account Invite UI
// =============================================================================

export type MemberAccountState =
  | 'none'
  | 'invitation_pending'
  | 'active'
  | 'needs_review'
  | 'unavailable';

export interface SuggestedMemberEmail {
  email_address: string;
  email_type: string | null;
  is_primary: boolean;
  is_shared: boolean;
}

export interface MemberAccountStatus {
  member_id: string;
  account_state: MemberAccountState;
  email: string | null;
  invited_at: string | null;
  accepted_at: string | null;
  linked_at: string | null;
  invitation_status: string | null;
  profile_status: string | null;
  suggested_emails: SuggestedMemberEmail[];
}

export interface ProvisionMemberAccountParams {
  organization_id: string;
  member_id: string;
  email: string;
  acknowledge_shared?: boolean;
}

export type ProvisionMemberAccountStatus =
  | 'sent'
  | 'existing_account_invitation_pending';

export interface ProvisionMemberAccountSuccess {
  success: true;
  invitation_id: string;
  member_id: string;
  profile_id: string;
  organization_id: string;
  status: ProvisionMemberAccountStatus;
  email: string;
  invited_at: string;
}

export interface ProvisionMemberAccountSharedWarning {
  success: false;
  status: 'requires_shared_acknowledgment';
  warning: string;
  is_shared_email: boolean;
}

export interface ProvisionMemberAccountError {
  success: false;
  status: 'error';
  code?: string;
  message: string;
}

export type ProvisionMemberAccountResult =
  | ProvisionMemberAccountSuccess
  | ProvisionMemberAccountSharedWarning
  | ProvisionMemberAccountError;

export interface PendingAccountInvitation {
  invitation_id: string;
  organization_id: string;
  organization_name: string;
  invitation_status: string;
  invited_at: string;
  expires_at: string | null;
}

export interface MyPendingAccountInvitationsResponse {
  invitations: PendingAccountInvitation[];
}
