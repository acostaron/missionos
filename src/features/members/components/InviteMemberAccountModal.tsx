import { useState, useEffect, useId } from 'react';
import { Mail, AlertTriangle, CheckCircle2, UserCheck } from 'lucide-react';
import { Modal } from '../../../components/ui/Modal';
import { Button } from '../../../components/ui/Button';
import { useProvisionMemberAccount } from '../../auth/invitation/queries';
import type { SuggestedMemberEmail } from '../../auth/invitation/types';

export interface InviteMemberAccountModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  memberId: string;
  memberName: string;
  suggestedEmails?: SuggestedMemberEmail[];
  onSuccessToast?: (msg: string) => void;
}

export function InviteMemberAccountModal({
  isOpen,
  onClose,
  organizationId,
  memberId,
  memberName,
  suggestedEmails = [],
  onSuccessToast,
}: InviteMemberAccountModalProps) {
  const emailInputId = useId();
  const sharedCheckboxId = useId();

  // Find candidate individual email (not shared and not family)
  const individualCandidates = suggestedEmails.filter(
    (e) => !e.is_shared && e.email_type !== 'family' && e.email_type !== 'shared'
  );
  const defaultIndividualEmail =
    individualCandidates.find((e) => e.is_primary)?.email_address ??
    individualCandidates[0]?.email_address ??
    '';

  const [email, setEmail] = useState('');
  const [isSharedAcknowledged, setIsSharedAcknowledged] = useState(false);
  const [showSharedWarning, setShowSharedWarning] = useState(false);
  const [sharedWarningText, setSharedWarningText] = useState('');
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [successState, setSuccessState] = useState<{
    type: 'new' | 'existing';
    email: string;
  } | null>(null);

  const provisionMutation = useProvisionMemberAccount();

  // Reset or pre-fill when modal opens
  useEffect(() => {
    if (isOpen) {
      setEmail(defaultIndividualEmail);
      setIsSharedAcknowledged(false);
      setShowSharedWarning(false);
      setSharedWarningText('');
      setErrorMessage(null);
      setSuccessState(null);
    }
  }, [isOpen, defaultIndividualEmail]);

  const handleSelectSuggested = (suggested: SuggestedMemberEmail) => {
    setEmail(suggested.email_address);
    setErrorMessage(null);
    if (suggested.is_shared || suggested.email_type === 'family' || suggested.email_type === 'shared') {
      setShowSharedWarning(true);
      setSharedWarningText(
        "This email is shared with another member or family record. MissionOS accounts are individual. Confirm that this email should be used for this member's account."
      );
      setIsSharedAcknowledged(false);
    } else {
      setShowSharedWarning(false);
      setIsSharedAcknowledged(false);
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);

    const trimmed = email.trim().toLowerCase();
    const emailRegex = /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/;
    if (!trimmed || !emailRegex.test(trimmed)) {
      setErrorMessage('Please enter a valid email address.');
      return;
    }

    try {
      const res = await provisionMutation.mutateAsync({
        organization_id: organizationId,
        member_id: memberId,
        email: trimmed,
        acknowledge_shared: isSharedAcknowledged,
      });

      if (res.success) {
        if (res.status === 'sent') {
          setSuccessState({ type: 'new', email: res.email });
          onSuccessToast?.('Invitation sent.');
        } else {
          setSuccessState({ type: 'existing', email: res.email });
          onSuccessToast?.('Existing MissionOS account found.');
        }
      } else if (res.status === 'requires_shared_acknowledgment') {
        setShowSharedWarning(true);
        setSharedWarningText(
          res.warning ||
            "This email is shared with another member or family record. MissionOS accounts are individual. Confirm that this email should be used for this member's account."
        );
        setIsSharedAcknowledged(false);
      } else {
        setErrorMessage(res.message);
      }
    } catch {
      setErrorMessage('Unable to send the invitation right now. Please try again.');
    }
  };

  if (!isOpen) return null;

  // ---------------------------------------------------------------------------
  // Success View
  // ---------------------------------------------------------------------------
  if (successState) {
    const isNew = successState.type === 'new';
    return (
      <Modal
        open={isOpen}
        onClose={onClose}
        title={
          <div className="flex items-center gap-2 text-ink">
            {isNew ? (
              <CheckCircle2 className="h-5 w-5 text-success-700" />
            ) : (
              <UserCheck className="h-5 w-5 text-primary-blue" />
            )}
            <span>{isNew ? 'Invitation sent' : 'Existing MissionOS account found'}</span>
          </div>
        }
        description="Account invitation completed"
        footer={
          <div className="flex justify-end w-full">
            <Button
              type="button"
              variant="primary"
              onClick={onClose}
              id="invite-success-done-btn"
              data-autofocus
            >
              Done
            </Button>
          </div>
        }
      >
        <div className="space-y-4 py-2">
          <div
            className={`rounded-xl border p-4 ${
              isNew
                ? 'border-success-600/30 bg-success-50 text-success-700'
                : 'border-primary-blue/30 bg-navy-50 text-primary-blue'
            }`}
          >
            <p className="text-sm font-semibold">
              {isNew ? 'Invitation sent.' : 'Existing MissionOS account found.'}
            </p>
            <p className="mt-1 text-xs leading-relaxed text-ink-secondary">
              {isNew
                ? `An email was sent to ${successState.email}. The member will set a password and accept their MissionOS access.`
                : 'An existing MissionOS account was found. Access to this organization is pending acceptance.'}
            </p>
          </div>
        </div>
      </Modal>
    );
  }

  // ---------------------------------------------------------------------------
  // Invitation Form View
  // ---------------------------------------------------------------------------
  return (
    <Modal
      open={isOpen}
      onClose={onClose}
      title="Invite to MissionOS"
      description={`Send ${memberName} an invitation to create or connect their MissionOS account.`}
      closeOnBackdrop={!provisionMutation.isPending}
      footer={
        <div className="flex flex-col-reverse sm:flex-row sm:items-center sm:justify-end gap-2 w-full">
          <Button
            type="button"
            variant="secondary"
            onClick={onClose}
            disabled={provisionMutation.isPending}
          >
            Cancel
          </Button>
          <Button
            type="button"
            variant="primary"
            onClick={handleSubmit}
            disabled={
              provisionMutation.isPending ||
              !email.trim() ||
              (showSharedWarning && !isSharedAcknowledged)
            }
            id="invite-submit-btn"
          >
            {provisionMutation.isPending
              ? 'Sending Invitation...'
              : showSharedWarning && isSharedAcknowledged
              ? 'Confirm & Send Invitation'
              : 'Send Invitation'}
          </Button>
        </div>
      }
    >
      <form onSubmit={handleSubmit} className="space-y-4 py-1">
        {/* Suggested emails chips */}
        {suggestedEmails.length > 0 && (
          <div className="space-y-1.5">
            <span className="text-xs font-medium text-ink-secondary">Emails on record:</span>
            <div className="flex flex-wrap gap-1.5">
              {suggestedEmails.map((se) => {
                const isSelected = email.toLowerCase() === se.email_address.toLowerCase();
                return (
                  <button
                    key={se.email_address}
                    type="button"
                    onClick={() => handleSelectSuggested(se)}
                    className={`inline-flex items-center gap-1.5 rounded-lg border px-2.5 py-1 text-xs transition-colors ${
                      isSelected
                        ? 'border-primary-blue bg-navy-50 text-primary-blue font-medium shadow-xs'
                        : 'border-line bg-surface hover:border-line-strong text-ink-secondary'
                    }`}
                  >
                    <span>{se.email_address}</span>
                    {se.is_primary && (
                      <span className="text-[10px] uppercase font-bold text-ink-muted">
                        primary
                      </span>
                    )}
                    {se.is_shared && (
                      <span className="text-[10px] text-warning-700 bg-warning-50 border border-warning-600/30 px-1 rounded">
                        Shared/Family
                      </span>
                    )}
                  </button>
                );
              })}
            </div>
          </div>
        )}

        {/* Email input field */}
        <div className="space-y-1.5">
          <label htmlFor={emailInputId} className="block text-xs font-semibold uppercase tracking-wider text-ink-secondary">
            Account Email Address
          </label>
          <div className="relative">
            <input
              id={emailInputId}
              type="email"
              value={email}
              onChange={(e) => {
                setEmail(e.target.value);
                setErrorMessage(null);
                setShowSharedWarning(false);
                setIsSharedAcknowledged(false);
              }}
              disabled={provisionMutation.isPending}
              placeholder="e.g. member@example.com"
              className="w-full rounded-lg border border-line bg-surface px-3 py-2 text-sm text-ink placeholder:text-ink-muted focus:border-primary-blue focus:outline-hidden focus:ring-2 focus:ring-primary-blue/20 transition-all"
              data-autofocus
            />
            <Mail className="absolute right-3 top-2.5 h-4 w-4 text-ink-muted pointer-events-none" />
          </div>
          <p className="text-[11px] text-ink-muted leading-relaxed">
            This individual address will be used to sign in to MissionOS and access this organization.
          </p>
        </div>

        {/* Shared Email Warning Flow */}
        {showSharedWarning && (
          <div className="rounded-xl border border-warning-600/30 bg-warning-50 p-4 space-y-3">
            <div className="flex items-start gap-2.5">
              <AlertTriangle className="h-5 w-5 text-warning-700 shrink-0 mt-0.5" />
              <div className="space-y-1 text-xs text-warning-700">
                <p className="font-semibold">Shared Email Detected</p>
                <p className="leading-relaxed">
                  {sharedWarningText ||
                    "This email is shared with another member or family record. MissionOS accounts are individual. Confirm that this email should be used for this member's account."}
                </p>
              </div>
            </div>

            <label
              htmlFor={sharedCheckboxId}
              className="flex items-start gap-2 pt-1 border-t border-warning-600/20 cursor-pointer"
            >
              <input
                id={sharedCheckboxId}
                type="checkbox"
                checked={isSharedAcknowledged}
                onChange={(e) => setIsSharedAcknowledged(e.target.checked)}
                className="mt-0.5 h-4 w-4 rounded border-warning-600 text-warning-700 focus:ring-warning-700"
              />
              <span className="text-xs font-medium text-warning-700">
                I confirm this email should be used for this member&apos;s MissionOS account.
              </span>
            </label>
          </div>
        )}

        {/* Error message */}
        {errorMessage && (
          <div className="rounded-lg border border-danger-600/30 bg-danger-50 p-3 text-xs text-danger-700">
            {errorMessage}
          </div>
        )}
      </form>
    </Modal>
  );
}
