import { useState, useId } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { useServantLeaderAccessStatus } from '../api/get-servant-leader-access-status';
import { grantServantLeaderAccess } from '../api/grant-servant-leader-access';
import { revokeServantLeaderAccess } from '../api/revoke-servant-leader-access';
import { normalizeError } from '../../../lib/supabase/errors';

interface ServantLeaderAccessModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  leadershipAssignmentId: string;
  leaderDisplayName: string;
  roleName: string;
  governanceNodeName: string;
  onSuccessToast?: (msg: string) => void;
}

export function ServantLeaderAccessModal({
  isOpen,
  onClose,
  organizationId,
  leadershipAssignmentId,
  leaderDisplayName,
  roleName,
  governanceNodeName,
  onSuccessToast,
}: ServantLeaderAccessModalProps) {
  const queryClient = useQueryClient();
  const titleId = useId();
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [showRevokeConfirm, setShowRevokeConfirm] = useState(false);
  const [revokeReason, setRevokeReason] = useState('');

  const {
    data: status,
    isLoading,
    error: statusError,
    refetch,
  } = useServantLeaderAccessStatus(
    organizationId,
    leadershipAssignmentId,
    isOpen
  );

  if (!isOpen) return null;

  const handleGrant = async () => {
    setIsSubmitting(true);
    setErrorMessage(null);
    try {
      await grantServantLeaderAccess(
        organizationId,
        leadershipAssignmentId
      );
      await refetch();
      await queryClient.invalidateQueries({ queryKey: ['household-profile'] });
      await queryClient.invalidateQueries({ queryKey: ['pastoral-operations-dashboard'] });
      onSuccessToast?.(`Application access granted for ${leaderDisplayName}.`);
    } catch (err) {
      setErrorMessage(normalizeError(err).message);
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleRevoke = async () => {
    setIsSubmitting(true);
    setErrorMessage(null);
    try {
      await revokeServantLeaderAccess(organizationId, {
        leadershipAssignmentId,
        reason: revokeReason.trim() || 'Revoked by administrator',
      });
      setShowRevokeConfirm(false);
      setRevokeReason('');
      await refetch();
      await queryClient.invalidateQueries({ queryKey: ['household-profile'] });
      await queryClient.invalidateQueries({ queryKey: ['pastoral-operations-dashboard'] });
      onSuccessToast?.(`Application access revoked for ${leaderDisplayName}.`);
    } catch (err) {
      setErrorMessage(normalizeError(err).message);
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby={titleId}
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-950/80 backdrop-blur-sm animate-in fade-in duration-200"
    >
      <div className="relative w-full max-w-lg rounded-2xl border border-slate-700/80 bg-slate-900 p-6 shadow-2xl space-y-6">
        {/* Header */}
        <div className="flex items-start justify-between border-b border-slate-800 pb-4">
          <div>
            <h2 id={titleId} className="text-lg font-bold text-white tracking-wide">
              Servant Leader Application Access
            </h2>
            <p className="text-xs text-slate-400 mt-0.5">
              Manage delegated software authorization for formal pastoral offices.
            </p>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="rounded-lg p-1 text-slate-400 hover:bg-slate-800 hover:text-white transition-colors"
          >
            <span className="sr-only">Close</span>
            <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* Error Banners */}
        {errorMessage && (
          <div className="rounded-lg border border-rose-500/40 bg-rose-950/40 p-3 text-xs text-rose-300">
            {errorMessage}
          </div>
        )}
        {statusError && (
          <div className="rounded-lg border border-rose-500/40 bg-rose-950/40 p-3 text-xs text-rose-300">
            {normalizeError(statusError).message}
          </div>
        )}

        {/* Loading State */}
        {isLoading ? (
          <div className="space-y-3 py-6">
            <div className="h-4 w-3/4 animate-pulse rounded bg-slate-800" />
            <div className="h-4 w-1/2 animate-pulse rounded bg-slate-800" />
            <div className="h-10 w-full animate-pulse rounded-lg bg-slate-800" />
          </div>
        ) : status ? (
          <div className="space-y-4 text-xs">
            {/* Pastoral Office Metadata */}
            <div className="rounded-xl border border-slate-800 bg-slate-950/60 p-4 space-y-2">
              <div className="flex items-center justify-between">
                <span className="text-[11px] font-medium text-slate-400 uppercase tracking-wider">
                  Formal Office
                </span>
                <span className="rounded-full border border-indigo-700/60 bg-indigo-950/50 px-2 py-0.5 text-[10px] font-semibold text-indigo-300">
                  {status.role_name || roleName}
                </span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-slate-400">Servant Leader:</span>
                <span className="font-semibold text-slate-100">{status.leader_member_name || leaderDisplayName}</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-slate-400">Governance Target:</span>
                <span className="font-medium text-slate-300">{status.governance_node_name || governanceNodeName}</span>
              </div>
            </div>

            {/* Application Access State */}
            <div className="rounded-xl border border-slate-800 bg-slate-950/60 p-4 space-y-2.5">
              <div className="flex items-center justify-between">
                <span className="text-[11px] font-medium text-slate-400 uppercase tracking-wider">
                  Application Authorization
                </span>
                <span
                  className={`rounded-full px-2.5 py-0.5 text-[10px] font-semibold border ${
                    status.access_status === 'active'
                      ? 'border-emerald-600/60 bg-emerald-950/50 text-emerald-300'
                      : status.access_status === 'revoked'
                      ? 'border-rose-600/60 bg-rose-950/50 text-rose-300'
                      : 'border-slate-700 bg-slate-800 text-slate-300'
                  }`}
                >
                  {status.access_status === 'active'
                    ? 'Active Access'
                    : status.access_status === 'revoked'
                    ? 'Revoked'
                    : 'Not Granted'}
                </span>
              </div>

              {/* Linked Profile Check */}
              <div className="flex items-center justify-between pt-1">
                <span className="text-slate-400">Linked Profile:</span>
                {status.has_linked_profile ? (
                  <span className="inline-flex items-center gap-1 text-emerald-400 font-medium">
                    <svg className="h-3.5 w-3.5" fill="currentColor" viewBox="0 0 20 20">
                      <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" />
                    </svg>
                    Verified & Active
                  </span>
                ) : (
                  <span className="inline-flex items-center gap-1 text-amber-400 font-medium">
                    <svg className="h-3.5 w-3.5" fill="currentColor" viewBox="0 0 20 20">
                      <path fillRule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
                    </svg>
                    No Linked Profile
                  </span>
                )}
              </div>

              {status.access_status === 'active' && (
                <>
                  <div className="flex items-center justify-between">
                    <span className="text-slate-400">Application Role:</span>
                    <span className="font-semibold text-slate-100">{status.app_role_name}</span>
                  </div>
                  <div className="flex items-center justify-between">
                    <span className="text-slate-400">Granted At:</span>
                    <span className="text-slate-300">
                      {status.granted_at ? new Date(status.granted_at).toLocaleDateString() : '—'}
                    </span>
                  </div>
                </>
              )}

              {status.access_status === 'revoked' && (
                <div className="rounded-lg border border-rose-900/40 bg-rose-950/20 p-2.5 mt-2 space-y-1">
                  <span className="text-[10px] uppercase font-semibold text-rose-400">Revocation Details</span>
                  <p className="text-slate-300 text-[11px]">
                    Reason: {status.revocation_reason || 'Not specified'}
                  </p>
                  <p className="text-[10px] text-slate-400">
                    Revoked on: {status.revoked_at ? new Date(status.revoked_at).toLocaleDateString() : '—'}
                  </p>
                </div>
              )}
            </div>

            {/* Revoke Confirmation Input */}
            {showRevokeConfirm && (
              <div className="rounded-xl border border-rose-800/80 bg-rose-950/40 p-4 space-y-3">
                <p className="text-xs font-semibold text-rose-200">
                  Confirm Access Revocation
                </p>
                <p className="text-[11px] text-rose-300/80">
                  This will immediately terminate software access for this servant leader, ending their delegated role and scope.
                </p>
                <div>
                  <label className="block text-[11px] font-medium text-slate-300 mb-1">
                    Reason for revocation
                  </label>
                  <input
                    type="text"
                    value={revokeReason}
                    onChange={(e) => setRevokeReason(e.target.value)}
                    placeholder="e.g. End of pastoral term, sabbatical, or administrative review"
                    className="w-full rounded-lg border border-slate-700 bg-slate-900 px-3 py-1.5 text-xs text-slate-100 placeholder-slate-500 focus:border-rose-500 focus:outline-none"
                  />
                </div>
                <div className="flex justify-end gap-2 pt-1">
                  <button
                    type="button"
                    onClick={() => {
                      setShowRevokeConfirm(false);
                      setRevokeReason('');
                    }}
                    disabled={isSubmitting}
                    className="rounded-lg px-3 py-1 text-xs text-slate-400 hover:text-white"
                  >
                    Cancel
                  </button>
                  <button
                    type="button"
                    onClick={handleRevoke}
                    disabled={isSubmitting}
                    className="rounded-lg bg-rose-600 px-3 py-1 text-xs font-semibold text-white hover:bg-rose-500 disabled:opacity-50"
                  >
                    {isSubmitting ? 'Revoking...' : 'Confirm Revoke'}
                  </button>
                </div>
              </div>
            )}
          </div>
        ) : null}

        {/* Footer Actions */}
        <div className="flex items-center justify-between border-t border-slate-800 pt-4">
          <button
            type="button"
            onClick={onClose}
            className="rounded-lg border border-slate-700 bg-slate-800 px-3 py-1.5 text-xs font-medium text-slate-300 hover:bg-slate-700 hover:text-white transition-colors"
          >
            Close
          </button>

          {!showRevokeConfirm && status && (
            <div className="flex items-center gap-2">
              {status.access_status === 'active' ? (
                <button
                  type="button"
                  id="btn-revoke-servant-leader-access"
                  onClick={() => setShowRevokeConfirm(true)}
                  disabled={isSubmitting}
                  className="rounded-lg border border-rose-800/80 bg-rose-950/40 px-3 py-1.5 text-xs font-semibold text-rose-300 hover:bg-rose-900/60 hover:text-rose-100 transition-colors disabled:opacity-50"
                >
                  Revoke Access
                </button>
              ) : status.eligibility_status === 'no_linked_profile' ? (
                <span className="text-[11px] text-amber-400/90 italic">
                  Profile link required before granting access
                </span>
              ) : status.eligibility_status === 'eligible' ? (
                <button
                  type="button"
                  id="btn-grant-servant-leader-access"
                  onClick={handleGrant}
                  disabled={isSubmitting}
                  className="rounded-lg border border-indigo-600 bg-indigo-600 px-3.5 py-1.5 text-xs font-semibold text-white hover:bg-indigo-500 transition-colors shadow-sm disabled:opacity-50"
                >
                  {isSubmitting ? 'Granting...' : 'Grant Application Access'}
                </button>
              ) : (
                <span className="text-[11px] text-slate-400 italic">
                  Ineligible: {status.eligibility_status}
                </span>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
