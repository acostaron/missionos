import { useState, useId } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useQueryClient } from '@tanstack/react-query';
import { householdKeys } from '../queries';
import { concludeServantLeader } from '../api/conclude-servant-leader';
import {
  concludeServantLeaderSchema,
  type ConcludeServantLeaderFormValues,
} from '../schemas';
import { normalizeError } from '../../../lib/supabase/errors';

interface ConcludeServantLeaderModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  governanceNodeId: string;
  governanceNodeName: string;
  leadershipAssignmentId: string;
  leaderDisplayName: string;
  roleName: string;
  onSuccessToast?: (msg: string) => void;
}

export function ConcludeServantLeaderModal({
  isOpen,
  onClose,
  organizationId,
  governanceNodeId,
  governanceNodeName,
  leadershipAssignmentId,
  leaderDisplayName,
  roleName,
  onSuccessToast,
}: ConcludeServantLeaderModalProps) {
  const queryClient = useQueryClient();
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const titleId = useId();
  const todayStr = new Date().toISOString().split('T')[0];

  const {
    handleSubmit,
    setValue,
    watch,
    reset,
    formState: { errors },
  } = useForm<ConcludeServantLeaderFormValues>({
    resolver: zodResolver(concludeServantLeaderSchema),
    defaultValues: {
      leadership_assignment_id: leadershipAssignmentId,
      effective_to: todayStr,
      reason: '',
    },
  });

  const effectiveTo = watch('effective_to');

  if (!isOpen) return null;

  const handleClose = () => {
    reset();
    setErrorMessage(null);
    onClose();
  };

  const onSubmit = async (values: ConcludeServantLeaderFormValues) => {
    try {
      setIsSubmitting(true);
      setErrorMessage(null);

      const result = await concludeServantLeader(organizationId, {
        leadership_assignment_id: values.leadership_assignment_id,
        effective_to: values.effective_to,
        reason: values.reason,
      });

      queryClient.invalidateQueries({
        queryKey: householdKeys.profile(organizationId, governanceNodeId),
      });
      queryClient.invalidateQueries({ queryKey: householdKeys.lists() });

      onSuccessToast?.(
        `${leaderDisplayName} successfully concluded as ${result.role_name} for ${governanceNodeName}.`
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
            Conclude Servant Leader Appointment
          </h2>
          <p className="text-xs text-slate-400 mt-0.5">
            Conclude formal office for <span className="text-slate-200 font-medium">{leaderDisplayName}</span> on{' '}
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
            <span className="text-slate-400 font-medium">Current Holder:</span> {leaderDisplayName}
          </p>
        </div>

        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4 text-xs">
          {/* Effective End Date */}
          <div>
            <label htmlFor="conclude_effective_to" className="block font-medium text-slate-300 mb-1">
              Effective End Date <span className="text-rose-400">*</span>
            </label>
            <input
              type="date"
              id="conclude_effective_to"
              max={todayStr}
              value={effectiveTo}
              onChange={(e) => setValue('effective_to', e.target.value)}
              className="w-full rounded-lg border border-slate-700 bg-slate-800/80 px-3 py-2 text-slate-100 focus:border-indigo-500 focus:outline-none"
            />
            {errors.effective_to && (
              <p className="text-rose-400 text-[11px] mt-1">{errors.effective_to.message}</p>
            )}
          </div>

          {/* Reason */}
          <div>
            <label htmlFor="conclude_reason" className="block font-medium text-slate-300 mb-1">
              Conclusion Reason <span className="text-rose-400">*</span>
            </label>
            <textarea
              id="conclude_reason"
              rows={3}
              maxLength={500}
              placeholder="e.g. End of 3-year term of service / transition to chapter service..."
              onChange={(e) => setValue('reason', e.target.value)}
              className="w-full rounded-lg border border-slate-700 bg-slate-800/80 px-3 py-2 text-slate-100 focus:border-indigo-500 focus:outline-none resize-none"
            />
            {errors.reason && (
              <p className="text-rose-400 text-[11px] mt-1">{errors.reason.message}</p>
            )}
          </div>

          {/* Canonical Guard Warning */}
          <div className="p-2.5 rounded-lg bg-amber-500/10 border border-amber-500/20 text-[11px] text-amber-200">
            <span className="font-semibold">Note:</span> This concludes the formal servant-leader appointment. It does not change the member’s pastoral household assignment.
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
              disabled={isSubmitting}
              className="px-4 py-2 text-xs font-semibold bg-rose-600 hover:bg-rose-500 disabled:opacity-50 text-white rounded-lg shadow-sm transition-colors"
            >
              {isSubmitting ? 'Concluding…' : 'Conclude Appointment'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
