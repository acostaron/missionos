import { useState, useId } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useQueryClient } from '@tanstack/react-query';
import { householdKeys } from '../queries';
import { replaceServantLeader } from '../api/replace-servant-leader';
import { useSearchMembers, type MemberListItem } from '../../members/queries';
import {
  replaceServantLeaderSchema,
  type ReplaceServantLeaderFormValues,
} from '../schemas';
import type { ServantLeaderRoleCode } from '../types';
import { normalizeError } from '../../../lib/supabase/errors';

interface ReplaceServantLeaderModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  governanceNodeId: string;
  governanceNodeName: string;
  currentLeaderMemberId: string;
  currentLeaderDisplayName: string;
  roleCode: ServantLeaderRoleCode;
  roleName: string;
  onSuccessToast?: (msg: string) => void;
}

export function ReplaceServantLeaderModal({
  isOpen,
  onClose,
  organizationId,
  governanceNodeId,
  governanceNodeName,
  currentLeaderMemberId,
  currentLeaderDisplayName,
  roleCode,
  roleName,
  onSuccessToast,
}: ReplaceServantLeaderModalProps) {
  const queryClient = useQueryClient();
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedMember, setSelectedMember] = useState<MemberListItem | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const titleId = useId();
  const todayStr = new Date().toISOString().split('T')[0];

  const {
    handleSubmit,
    setValue,
    watch,
    reset,
    formState: { errors },
  } = useForm<ReplaceServantLeaderFormValues>({
    resolver: zodResolver(replaceServantLeaderSchema),
    defaultValues: {
      role_code: roleCode,
      governance_node_id: governanceNodeId,
      new_member_id: '',
      effective_date: todayStr,
      reason: '',
    },
  });

  const effectiveDate = watch('effective_date');

  const { data: memberData, isLoading: isLoadingMembers } = useSearchMembers(
    isOpen ? organizationId : null,
    {
      search: searchQuery || undefined,
      recordStatus: 'active',
      page: 1,
      pageSize: 20,
    }
  );

  if (!isOpen) return null;

  const handleClose = () => {
    reset();
    setSelectedMember(null);
    setSearchQuery('');
    setErrorMessage(null);
    onClose();
  };

  const handleSelectMember = (m: MemberListItem) => {
    if (m.id === currentLeaderMemberId) {
      setErrorMessage('The incoming replacement cannot be the current leader.');
      return;
    }
    setSelectedMember(m);
    setValue('new_member_id', m.id);
    setErrorMessage(null);
  };

  const onSubmit = async (values: ReplaceServantLeaderFormValues) => {
    try {
      setIsSubmitting(true);
      setErrorMessage(null);

      const result = await replaceServantLeader(organizationId, {
        role_code: values.role_code,
        governance_node_id: values.governance_node_id,
        new_member_id: values.new_member_id,
        effective_date: values.effective_date,
        reason: values.reason,
      });

      if (result.status === 'blocked') {
        setErrorMessage(result.message);
        return;
      }

      queryClient.invalidateQueries({
        queryKey: householdKeys.profile(organizationId, governanceNodeId),
      });
      queryClient.invalidateQueries({ queryKey: householdKeys.lists() });

      onSuccessToast?.(
        `${result.role_name} on ${governanceNodeName} successfully transitioned to ${selectedMember?.display_name ?? 'new leader'}.`
      );
      handleClose();
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
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-950/70 backdrop-blur-sm animate-fade-in"
    >
      <div className="relative w-full max-w-lg rounded-xl border border-slate-700 bg-slate-900 shadow-2xl p-6 text-slate-100 space-y-4">
        <div>
          <h2 id={titleId} className="text-base font-semibold text-white">
            Replace Servant Leader
          </h2>
          <p className="text-xs text-slate-400 mt-0.5">
            Atomically transition the formal office of {roleName} on{' '}
            <span className="text-slate-200 font-medium">{governanceNodeName}</span>.
          </p>
        </div>

        {errorMessage && (
          <div className="p-3 rounded-lg bg-rose-500/10 border border-rose-500/20 text-rose-300 text-xs">
            {errorMessage}
          </div>
        )}

        <div className="p-3 rounded-lg bg-slate-800/40 border border-slate-700/60 text-xs space-y-1">
          <p className="text-slate-300">
            <span className="text-slate-400 font-medium">Formal Office:</span> {roleName}
          </p>
          <p className="text-slate-300">
            <span className="text-slate-400 font-medium">Outgoing Office Holder:</span>{' '}
            <span className="text-rose-300 font-semibold">{currentLeaderDisplayName}</span>
          </p>
        </div>

        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4 text-xs">
          {/* Incoming Candidate Selection */}
          <div>
            <label className="block font-medium text-slate-300 mb-1">
              Incoming Leader <span className="text-rose-400">*</span>
            </label>
            {selectedMember ? (
              <div className="p-3 rounded-lg border border-indigo-500/40 bg-indigo-500/10 flex items-center justify-between">
                <div>
                  <p className="font-semibold text-slate-100">{selectedMember.display_name}</p>
                  <p className="text-[11px] text-slate-400">
                    {selectedMember.member_number ? `#${selectedMember.member_number}` : ''}
                    {selectedMember.membership_status ? ` • ${selectedMember.membership_status.name}` : ''}
                  </p>
                </div>
                <button
                  type="button"
                  onClick={() => {
                    setSelectedMember(null);
                    setValue('new_member_id', '');
                  }}
                  className="text-xs text-slate-400 hover:text-slate-200 underline"
                >
                  Change
                </button>
              </div>
            ) : (
              <div className="space-y-2">
                <input
                  type="text"
                  placeholder="Search active members by name..."
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  className="w-full rounded-lg border border-slate-700 bg-slate-800/80 px-3 py-2 text-slate-100 focus:border-indigo-500 focus:outline-none"
                />
                <div className="max-h-40 overflow-y-auto rounded-lg border border-slate-800 bg-slate-950 divide-y divide-slate-800">
                  {isLoadingMembers ? (
                    <div className="p-3 text-center text-slate-500 text-[11px]">Searching members…</div>
                  ) : (memberData?.members?.length ?? 0) === 0 ? (
                    <div className="p-3 text-center text-slate-500 text-[11px]">No active members found.</div>
                  ) : (
                    memberData?.members
                      .filter((m) => m.id !== currentLeaderMemberId)
                      .map((m) => (
                        <button
                          key={m.id}
                          type="button"
                          onClick={() => handleSelectMember(m)}
                          className="w-full text-left p-2.5 hover:bg-slate-800/60 transition-colors flex items-center justify-between"
                        >
                          <div>
                            <p className="font-medium text-slate-200">{m.display_name}</p>
                            <p className="text-[10px] text-slate-400">
                              {m.member_number ? `#${m.member_number}` : ''}
                              {m.membership_status ? ` • ${m.membership_status.name}` : ''}
                            </p>
                          </div>
                          <span className="text-[11px] text-indigo-400 font-medium">Select</span>
                        </button>
                      ))
                  )}
                </div>
              </div>
            )}
            {errors.new_member_id && (
              <p className="text-rose-400 text-[11px] mt-1">{errors.new_member_id.message}</p>
            )}
          </div>

          {/* Effective Replacement Date */}
          <div>
            <label htmlFor="replace_effective_date" className="block font-medium text-slate-300 mb-1">
              Effective Replacement Date <span className="text-rose-400">*</span>
            </label>
            <input
              type="date"
              id="replace_effective_date"
              max={todayStr}
              value={effectiveDate}
              onChange={(e) => setValue('effective_date', e.target.value)}
              className="w-full rounded-lg border border-slate-700 bg-slate-800/80 px-3 py-2 text-slate-100 focus:border-indigo-500 focus:outline-none"
            />
            {errors.effective_date && (
              <p className="text-rose-400 text-[11px] mt-1">{errors.effective_date.message}</p>
            )}
          </div>

          {/* Reason */}
          <div>
            <label htmlFor="replace_reason" className="block font-medium text-slate-300 mb-1">
              Replacement Reason <span className="text-rose-400">*</span>
            </label>
            <textarea
              id="replace_reason"
              rows={2}
              maxLength={500}
              placeholder="e.g. Scheduled rotation / pastoral succession plan..."
              onChange={(e) => setValue('reason', e.target.value)}
              className="w-full rounded-lg border border-slate-700 bg-slate-800/80 px-3 py-2 text-slate-100 focus:border-indigo-500 focus:outline-none resize-none"
            />
            {errors.reason && (
              <p className="text-rose-400 text-[11px] mt-1">{errors.reason.message}</p>
            )}
          </div>

          {/* Replacement Atomic Notice */}
          <div className="p-2.5 rounded-lg bg-slate-800/40 border border-slate-800 text-[11px] text-slate-400">
            Replacement occurs atomically: the outgoing appointment is concluded as completed, and the incoming appointment becomes the sole active office holder on the effective date.
          </div>

          {/* Modal Actions */}
          <div className="pt-3 border-t border-slate-800 flex justify-end gap-2.5">
            <button
              type="button"
              onClick={handleClose}
              disabled={isSubmitting}
              className="px-4 py-2 text-xs font-semibold text-slate-300 hover:text-slate-100 transition-colors"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={isSubmitting || !selectedMember}
              className="px-4 py-2 text-xs font-semibold bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 text-white rounded-lg shadow-sm transition-colors"
            >
              {isSubmitting ? 'Replacing…' : 'Replace Leader'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
