import { useState } from 'react';
import { ShieldCheck, Mail, Clock, AlertCircle } from 'lucide-react';
import { useMemberAccountStatus } from '../../auth/invitation/queries';
import { InviteMemberAccountModal } from './InviteMemberAccountModal';

export interface MemberAccountCardProps {
  organizationId: string | null;
  memberId: string;
  memberName: string;
  canProvision: boolean;
  onSuccessToast?: (msg: string) => void;
}

export function MemberAccountCard({
  organizationId,
  memberId,
  memberName,
  canProvision,
  onSuccessToast,
}: MemberAccountCardProps) {
  const [isInviteModalOpen, setIsInviteModalOpen] = useState(false);

  const { data: status, isLoading, error } = useMemberAccountStatus(
    organizationId,
    memberId,
    { enabled: canProvision && !!organizationId }
  );

  // If not authorized to provision accounts, do not render account management section
  if (!canProvision || !organizationId) {
    return null;
  }

  // Loading skeleton
  if (isLoading) {
    return (
      <div className="rounded-xl border border-line bg-surface-muted p-5 animate-pulse space-y-3">
        <div className="h-4 w-36 bg-surface rounded" />
        <div className="h-12 w-full bg-surface rounded-lg" />
      </div>
    );
  }

  // Error loading status
  if (error || !status) {
    return null;
  }

  const accountState = status.account_state;

  return (
    <>
      <div className="rounded-xl border border-line bg-surface-muted overflow-hidden shadow-xs">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-line px-5 py-3.5">
          <div className="flex items-center gap-3">
            <span className="text-ink-muted">
              <ShieldCheck className="h-4 w-4" />
            </span>
            <h2 className="text-sm font-semibold uppercase tracking-wider text-ink-secondary">
              MissionOS Account
            </h2>
          </div>

          {/* Action button: only shown for 'none' state when authorized */}
          {accountState === 'none' && canProvision && (
            <button
              type="button"
              id="invite-member-account-button"
              onClick={() => setIsInviteModalOpen(true)}
              className="inline-flex items-center gap-1.5 rounded-lg border border-primary-blue bg-primary-blue px-3 py-1.5 text-xs font-semibold text-white hover:bg-primary-blue/90 transition-colors shadow-xs"
            >
              <Mail className="h-3.5 w-3.5" />
              Invite to MissionOS
            </button>
          )}
        </div>

        {/* Content Body */}
        <div className="px-5 py-4">
          {/* STATE A: ACTIVE ACCOUNT */}
          {accountState === 'active' && (
            <div className="space-y-3">
              <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2">
                <div className="flex items-center gap-2">
                  <span className="inline-flex items-center gap-1.5 rounded-full border border-success-600/30 bg-success-50 px-3 py-0.5 text-xs font-semibold text-success-700">
                    <span className="h-1.5 w-1.5 rounded-full bg-success-600" />
                    Active Account
                  </span>
                  <span className="text-xs text-ink-muted">Account Linked</span>
                </div>

                {(status.accepted_at || status.linked_at) && (
                  <span className="text-xs text-ink-muted">
                    {status.accepted_at
                      ? `Accepted ${new Date(status.accepted_at).toLocaleDateString('en-US', {
                          year: 'numeric',
                          month: 'short',
                          day: 'numeric',
                        })}`
                      : `Linked ${new Date(status.linked_at!).toLocaleDateString('en-US', {
                          year: 'numeric',
                          month: 'short',
                          day: 'numeric',
                        })}`}
                  </span>
                )}
              </div>

              {status.email && (
                <div className="flex items-center justify-between rounded-lg border border-line bg-surface px-3.5 py-2.5">
                  <span className="text-xs font-medium text-ink-muted">Account Email</span>
                  <span className="text-sm font-medium text-ink font-mono">{status.email}</span>
                </div>
              )}
            </div>
          )}

          {/* STATE B: INVITATION PENDING */}
          {accountState === 'invitation_pending' && (
            <div className="space-y-3">
              <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2">
                <div className="flex items-center gap-2">
                  <span className="inline-flex items-center gap-1.5 rounded-full border border-warning-600/30 bg-warning-50 px-3 py-0.5 text-xs font-semibold text-warning-700">
                    <Clock className="h-3 w-3" />
                    Invitation Pending
                  </span>
                  <span className="text-xs text-ink-muted">
                    {status.invitation_status === 'existing_account_invitation_pending'
                      ? 'Existing Account'
                      : 'Email Sent'}
                  </span>
                </div>

                {status.invited_at && (
                  <span className="text-xs text-ink-muted">
                    Sent{' '}
                    {new Date(status.invited_at).toLocaleDateString('en-US', {
                      year: 'numeric',
                      month: 'short',
                      day: 'numeric',
                    })}
                  </span>
                )}
              </div>

              <div className="rounded-lg border border-line bg-surface px-3.5 py-2.5 space-y-1">
                <div className="flex items-center justify-between">
                  <span className="text-xs font-medium text-ink-muted">Target Account Email</span>
                  <span className="text-sm font-medium text-ink font-mono">{status.email}</span>
                </div>
                <p className="text-xs text-ink-muted pt-1 border-t border-line">
                  {status.invitation_status === 'existing_account_invitation_pending'
                    ? 'An existing MissionOS account was found. Access to this organization is pending acceptance.'
                    : 'Waiting for the member to accept the invitation.'}
                </p>
              </div>
            </div>
          )}

          {/* STATE C: NO ACCOUNT */}
          {accountState === 'none' && (
            <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
              <div className="space-y-1">
                <div className="flex items-center gap-2">
                  <span className="inline-flex items-center rounded-full border border-line-strong bg-surface px-2.5 py-0.5 text-xs font-medium text-ink-muted">
                    No MissionOS Account
                  </span>
                </div>
                <p className="text-xs text-ink-muted">
                  This member does not currently have MissionOS user access.
                </p>
              </div>
            </div>
          )}

          {/* STATE D: ACCOUNT ISSUE / DRIFT */}
          {accountState === 'needs_review' && (
            <div className="rounded-lg border border-warning-600/30 bg-warning-50 p-3 space-y-2">
              <div className="flex items-center gap-2 text-warning-700 text-xs font-semibold">
                <AlertCircle className="h-4 w-4 shrink-0" />
                <span>Account Setup Needs Review</span>
              </div>
              <p className="text-xs text-warning-700 leading-relaxed">
                This member&apos;s account setup needs review.
              </p>
              {status.email && (
                <p className="text-xs text-ink-muted font-mono pt-1 border-t border-warning-600/20">
                  Associated login email: {status.email}
                </p>
              )}
            </div>
          )}

          {/* STATE E: MEMBER NOT ELIGIBLE */}
          {accountState === 'unavailable' && (
            <div className="text-xs text-ink-muted italic">
              Account invitations are not available for this member.
            </div>
          )}
        </div>
      </div>

      {/* Modal for sending invitation */}
      {isInviteModalOpen && canProvision && (
        <InviteMemberAccountModal
          isOpen={isInviteModalOpen}
          onClose={() => setIsInviteModalOpen(false)}
          organizationId={organizationId}
          memberId={memberId}
          memberName={memberName}
          suggestedEmails={status.suggested_emails}
          onSuccessToast={onSuccessToast}
        />
      )}
    </>
  );
}
