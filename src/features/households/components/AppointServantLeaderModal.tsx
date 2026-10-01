import { useState, useId } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useQueryClient } from '@tanstack/react-query';
import { householdKeys } from '../queries';
import { appointServantLeader } from '../api/appoint-servant-leader';
import { useSearchMembers, type MemberListItem } from '../../members/queries';
import {
  appointServantLeaderSchema,
  type AppointServantLeaderFormValues,
} from '../schemas';
import type { ServantLeaderRoleCode } from '../types';
import { normalizeError } from '../../../lib/supabase/errors';

interface AppointServantLeaderModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  governanceNodeId: string;
  governanceNodeName: string;
  roleCode: ServantLeaderRoleCode;
  onSuccessToast?: (msg: string) => void;
}

const ROLE_LABELS: Record<ServantLeaderRoleCode, string> = {
  household_servant_leader: 'Household Servant Leader',
  unit_servant_leader: 'Unit Servant Leader',
  chapter_servant_leader: 'Chapter Servant Leader',
  area_servant_leader: 'Area Servant Leader',
};

export function AppointServantLeaderModal({
  isOpen,
  onClose,
  organizationId,
  governanceNodeId,
  governanceNodeName,
  roleCode,
  onSuccessToast,
}: AppointServantLeaderModalProps) {
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
  } = useForm<AppointServantLeaderFormValues>({
    resolver: zodResolver(appointServantLeaderSchema),
    defaultValues: {
      role_code: roleCode,
      governance_node_id: governanceNodeId,
      member_id: '',
      effective_from: todayStr,
      reason: '',
    },
  });

  const effectiveFrom = watch('effective_from');

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
    setSelectedMember(m);
    setValue('member_id', m.id);
    setErrorMessage(null);
  };

  const onSubmit = async (values: AppointServantLeaderFormValues) => {
    try {
      setIsSubmitting(true);
      setErrorMessage(null);

      const result = await appointServantLeader(organizationId, {
        role_code: values.role_code,
        governance_node_id: values.governance_node_id,
        member_id: values.member_id,
        effective_from: values.effective_from,
        reason: values.reason,
      });

      queryClient.invalidateQueries({
        queryKey: householdKeys.profile(organizationId, governanceNodeId),
      });
      queryClient.invalidateQueries({ queryKey: householdKeys.lists() });

      onSuccessToast?.(
        `${selectedMember?.display_name ?? 'Candidate'} successfully appointed as ${result.role_name} for ${governanceNodeName}.`
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
            Appoint {ROLE_LABELS[roleCode]}
          </h2>
          <p className="text-xs text-slate-400 mt-0.5">
            Appoint a formal servant leader to <span className="text-slate-200 font-medium">{governanceNodeName}</span>.
          </p>
        </div>

        {errorMessage && (
          <div className="p-3 rounded-lg bg-rose-500/10 border border-rose-500/20 text-rose-300 text-xs">
            {errorMessage}
          </div>
        )}

        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4 text-xs">
          {/* Candidate Member Selection */}
          <div>
            <label className="block font-medium text-slate-300 mb-1">
              Candidate Member <span className="text-rose-400">*</span>
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
                    setValue('member_id', '');
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
                    memberData?.members.map((m) => (
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
            {errors.member_id && (
              <p className="text-rose-400 text-[11px] mt-1">{errors.member_id.message}</p>
            )}
          </div>

          {/* Effective Date */}
          <div>
            <label htmlFor="appoint_effective_from" className="block font-medium text-slate-300 mb-1">
              Effective Appointment Date <span className="text-rose-400">*</span>
            </label>
            <input
              type="date"
              id="appoint_effective_from"
              max={todayStr}
              value={effectiveFrom}
              onChange={(e) => setValue('effective_from', e.target.value)}
              className="w-full rounded-lg border border-slate-700 bg-slate-800/80 px-3 py-2 text-slate-100 focus:border-indigo-500 focus:outline-none"
            />
            {errors.effective_from && (
              <p className="text-rose-400 text-[11px] mt-1">{errors.effective_from.message}</p>
            )}
          </div>

          {/* Reason / Appointment Note */}
          <div>
            <label htmlFor="appoint_reason" className="block font-medium text-slate-300 mb-1">
              Appointment Note / Discernment Reason (Optional)
            </label>
            <textarea
              id="appoint_reason"
              rows={2}
              maxLength={500}
              placeholder="e.g. Appointed following chapter discernment..."
              onChange={(e) => setValue('reason', e.target.value)}
              className="w-full rounded-lg border border-slate-700 bg-slate-800/80 px-3 py-2 text-slate-100 focus:border-indigo-500 focus:outline-none resize-none"
            />
          </div>

          {/* Canonical Office Notice */}
          <div className="p-2.5 rounded-lg bg-slate-800/40 border border-slate-800 text-[11px] text-slate-400">
            Formal appointment creates an active governance assignment in{' '}
            <span className="text-slate-200 font-semibold">{ROLE_LABELS[roleCode]}</span>. It does NOT automatically mutate application access or move the leader’s pastoral household nourishment.
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
              {isSubmitting ? 'Appointing…' : 'Appoint Leader'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
