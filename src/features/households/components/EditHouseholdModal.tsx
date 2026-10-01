import { useState, useId } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useQueryClient } from '@tanstack/react-query';
import { householdKeys } from '../queries';
import { updateHousehold } from '../api/update-household';
import { editHouseholdSchema, type EditHouseholdFormValues } from '../schemas';
import type { HouseholdProfileData } from '../types';
import { normalizeError } from '../../../lib/supabase/errors';

interface EditHouseholdModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  householdData: HouseholdProfileData;
  onSuccessToast?: (msg: string) => void;
}

export function EditHouseholdModal({
  isOpen,
  onClose,
  organizationId,
  householdData,
  onSuccessToast,
}: EditHouseholdModalProps) {
  const queryClient = useQueryClient();
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const titleId = useId();
  const { household, parent_governance } = householdData;

  const {
    register,
    handleSubmit,
    reset,
    formState: { errors },
  } = useForm<EditHouseholdFormValues>({
    resolver: zodResolver(editHouseholdSchema),
    defaultValues: {
      name: household.name,
      code: household.code,
      pastoral_level: (household.pastoral_level as any) || 'member',
      household_category: (household.household_category as any) || 'pastoral',
      meeting_frequency: (household.meeting_frequency as any) || 'weekly',
      meeting_day_of_week: household.meeting_day_of_week,
      meeting_start_time: household.meeting_start_time ? household.meeting_start_time.slice(0, 5) : '',
      meeting_timezone_name: household.meeting_timezone_name || 'America/New_York',
      meeting_location_type: (household.meeting_location_type as any) || 'residence',
      meeting_location_text: household.meeting_location_text || '',
      target_member_count: household.target_member_count,
      maximum_member_count: household.maximum_member_count,
      accepts_new_members: household.accepts_new_members,
      language_code: household.language_code || 'en',
      is_couple_household: household.is_couple_household,
    },
  });

  if (!isOpen) return null;

  const handleClose = () => {
    reset();
    setErrorMessage(null);
    onClose();
  };

  const onSubmit = async (data: EditHouseholdFormValues) => {
    try {
      setIsSubmitting(true);
      setErrorMessage(null);

      const result = await updateHousehold(organizationId, {
        household_id: household.id,
        name: data.name,
        code: data.code,
        pastoral_level: data.pastoral_level,
        household_category: data.household_category,
        meeting_frequency: data.meeting_frequency,
        meeting_day_of_week: data.meeting_day_of_week != null ? Number(data.meeting_day_of_week) : null,
        meeting_start_time: data.meeting_start_time ? `${data.meeting_start_time}:00` : null,
        meeting_timezone_name: data.meeting_timezone_name,
        meeting_location_type: data.meeting_location_type,
        meeting_location_text: data.meeting_location_text || null,
        target_member_count: data.target_member_count != null ? Number(data.target_member_count) : null,
        maximum_member_count: data.maximum_member_count != null ? Number(data.maximum_member_count) : null,
        accepts_new_members: data.accepts_new_members,
        language_code: data.language_code,
        is_couple_household: data.is_couple_household,
      });

      // Invalidate household queries
      await queryClient.invalidateQueries({
        queryKey: householdKeys.profile(organizationId, household.id),
      });
      await queryClient.invalidateQueries({
        queryKey: householdKeys.lists(),
      });
      await queryClient.invalidateQueries({
        queryKey: householdKeys.members(),
      });

      onSuccessToast?.(`Household "${result.name}" updated successfully.`);
      handleClose();
    } catch (err: unknown) {
      const normalized = normalizeError(err);
      setErrorMessage(normalized.message);
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-slate-950/80 p-4 backdrop-blur-sm"
      role="dialog"
      aria-modal="true"
      aria-labelledby={titleId}
    >
      <div className="relative w-full max-w-2xl rounded-2xl border border-slate-700 bg-slate-900 p-6 shadow-2xl space-y-6 max-h-[90vh] overflow-y-auto">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-slate-800 pb-4">
          <div>
            <h2 id={titleId} className="text-lg font-bold text-slate-100">
              Edit Household
            </h2>
            <p className="text-xs text-slate-400 mt-1">
              Update operational identity and pastoral meeting configuration.
            </p>
          </div>
          <button
            type="button"
            onClick={handleClose}
            className="rounded-lg p-1.5 text-slate-400 hover:bg-slate-800 hover:text-slate-200 transition-colors"
            aria-label="Close"
          >
            <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* Error banner */}
        {errorMessage && (
          <div className="rounded-xl border border-red-700 bg-red-900/30 p-3.5 text-xs text-red-200">
            {errorMessage}
          </div>
        )}

        <form onSubmit={handleSubmit(onSubmit)} className="space-y-6">
          {/* Read-Only Parent Governance Placement */}
          <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-4 space-y-1">
            <span className="text-[10px] font-semibold uppercase tracking-wider text-slate-500">
              Parent Governance Placement (Read-Only)
            </span>
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-semibold text-slate-200">
                  {parent_governance?.parent_node_name ?? 'Direct Organization'}
                </p>
                {parent_governance && (
                  <p className="text-xs text-slate-400">
                    Code: <span className="font-mono text-slate-300">{parent_governance.parent_node_code}</span> · {parent_governance.parent_node_type}
                  </p>
                )}
              </div>
              <span className="text-[10px] font-medium text-slate-500 italic">
                Placement is immutable
              </span>
            </div>
          </div>

          {/* Identity Section */}
          <div className="space-y-4">
            <h3 className="text-xs font-semibold uppercase tracking-wider text-slate-400">
              Household Identity &amp; Pastoral Echelon
            </h3>

            {/* Pastoral Level Selector */}
            <div>
              <label className="block text-xs font-medium text-slate-300">
                Pastoral Level
              </label>
              <select
                {...register('pastoral_level')}
                disabled={householdData.counts.active_member_count > 0 || householdData.leaders.length > 0}
                className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-800/80 px-3 py-2 text-sm text-slate-100 disabled:opacity-60 disabled:cursor-not-allowed focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
              >
                <option value="member">Member Household (Servant-led; for regular members)</option>
                <option value="unit">Unit Household (Unit Servant-led; for Household Leaders)</option>
                <option value="chapter">Chapter Household (Chapter Servant-led; for Unit Leaders)</option>
                <option value="area">Area Household (Area Servant-led; for Chapter Leaders)</option>
                <option value="fraternal">Fraternal Household (Peer-facilitated; for Area Head &amp; senior members)</option>
              </select>
              {(householdData.counts.active_member_count > 0 || householdData.leaders.length > 0) && (
                <p className="mt-1 text-[11px] text-slate-400 italic">
                  Pastoral level cannot be changed while active members or leaders are assigned.
                </p>
              )}
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div>
                <label className="block text-xs font-medium text-slate-300">
                  Household Name <span className="text-rose-400">*</span>
                </label>
                <input
                  type="text"
                  {...register('name')}
                  placeholder="e.g. St. Joseph Household"
                  className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-800/80 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
                />
                {errors.name && (
                  <p className="mt-1 text-xs text-rose-400">{errors.name.message}</p>
                )}
              </div>

              <div>
                <label className="block text-xs font-medium text-slate-300">
                  Code (Lowercase &amp; Underscores) <span className="text-rose-400">*</span>
                </label>
                <input
                  type="text"
                  {...register('code')}
                  placeholder="e.g. rvc_u01_stjoseph"
                  className="mt-1 w-full font-mono rounded-lg border border-slate-700 bg-slate-800/80 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
                />
                {errors.code && (
                  <p className="mt-1 text-xs text-rose-400">{errors.code.message}</p>
                )}
              </div>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div>
                <label className="block text-xs font-medium text-slate-300">Category</label>
                <select
                  {...register('household_category')}
                  className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-800/80 px-3 py-2 text-sm text-slate-100 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
                >
                  <option value="pastoral">Pastoral</option>
                  <option value="formation">Formation</option>
                  <option value="mission">Mission</option>
                  <option value="temporary">Temporary</option>
                  <option value="welcoming">Welcoming</option>
                  <option value="other">Other</option>
                </select>
              </div>

              <div>
                <label className="block text-xs font-medium text-slate-300">Language</label>
                <select
                  {...register('language_code')}
                  className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-800/80 px-3 py-2 text-sm text-slate-100 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
                >
                  <option value="en">English (en)</option>
                  <option value="es">Spanish (es)</option>
                  <option value="fil">Filipino (fil)</option>
                </select>
              </div>
            </div>
          </div>

          {/* Meeting Schedule & Location */}
          <div className="space-y-4 pt-4 border-t border-slate-800">
            <h3 className="text-xs font-semibold uppercase tracking-wider text-slate-400">
              Meeting Schedule &amp; Format
            </h3>

            <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
              <div>
                <label className="block text-xs font-medium text-slate-300">Frequency</label>
                <select
                  {...register('meeting_frequency')}
                  className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-800/80 px-3 py-2 text-sm text-slate-100 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
                >
                  <option value="weekly">Weekly</option>
                  <option value="biweekly">Biweekly</option>
                  <option value="monthly">Monthly</option>
                  <option value="quarterly">Quarterly</option>
                  <option value="seasonal">Seasonal</option>
                  <option value="variable">Variable</option>
                </select>
              </div>

              <div>
                <label className="block text-xs font-medium text-slate-300">Day of Week</label>
                <select
                  {...register('meeting_day_of_week', {
                    setValueAs: (v) => (v === '' || v == null ? null : Number(v)),
                  })}
                  className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-800/80 px-3 py-2 text-sm text-slate-100 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
                >
                  <option value="">(None / Variable)</option>
                  <option value="0">Sunday</option>
                  <option value="1">Monday</option>
                  <option value="2">Tuesday</option>
                  <option value="3">Wednesday</option>
                  <option value="4">Thursday</option>
                  <option value="5">Friday</option>
                  <option value="6">Saturday</option>
                </select>
              </div>

              <div>
                <label className="block text-xs font-medium text-slate-300">Meeting Time</label>
                <input
                  type="time"
                  {...register('meeting_start_time')}
                  className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-800/80 px-3 py-2 text-sm text-slate-100 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
                />
              </div>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div>
                <label className="block text-xs font-medium text-slate-300">Location Type</label>
                <select
                  {...register('meeting_location_type')}
                  className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-800/80 px-3 py-2 text-sm text-slate-100 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
                >
                  <option value="residence">Residence</option>
                  <option value="church">Church</option>
                  <option value="parish_hall">Parish Hall</option>
                  <option value="online">Online</option>
                  <option value="hybrid">Hybrid</option>
                  <option value="variable">Variable</option>
                  <option value="other">Other</option>
                </select>
              </div>

              <div>
                <label className="block text-xs font-medium text-slate-300">Timezone</label>
                <input
                  type="text"
                  {...register('meeting_timezone_name')}
                  placeholder="America/New_York"
                  className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-800/80 px-3 py-2 text-sm text-slate-100 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
                />
              </div>
            </div>

            <div>
              <label className="block text-xs font-medium text-slate-300">
                Meeting Location Description (Internal Note)
              </label>
              <input
                type="text"
                {...register('meeting_location_text')}
                placeholder="e.g. Residence of Bro. John & Sis. Mary"
                className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-800/80 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
              />
            </div>
          </div>

          {/* Capacity & Flags */}
          <div className="space-y-4 pt-4 border-t border-slate-800">
            <h3 className="text-xs font-semibold uppercase tracking-wider text-slate-400">
              Capacity &amp; Group Options
            </h3>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div>
                <label className="block text-xs font-medium text-slate-300">Target Members</label>
                <input
                  type="number"
                  {...register('target_member_count', {
                    setValueAs: (v) => (v === '' || v == null ? null : Number(v)),
                  })}
                  placeholder="e.g. 8"
                  className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-800/80 px-3 py-2 text-sm text-slate-100 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
                />
                {errors.target_member_count && (
                  <p className="mt-1 text-xs text-rose-400">{errors.target_member_count.message}</p>
                )}
              </div>

              <div>
                <label className="block text-xs font-medium text-slate-300">Maximum Members</label>
                <input
                  type="number"
                  {...register('maximum_member_count', {
                    setValueAs: (v) => (v === '' || v == null ? null : Number(v)),
                  })}
                  placeholder="e.g. 12"
                  className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-800/80 px-3 py-2 text-sm text-slate-100 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
                />
                {errors.maximum_member_count && (
                  <p className="mt-1 text-xs text-rose-400">{errors.maximum_member_count.message}</p>
                )}
              </div>
            </div>

            <div className="flex flex-col sm:flex-row gap-6 pt-2">
              <label className="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  {...register('accepts_new_members')}
                  className="rounded border-slate-700 bg-slate-800 text-indigo-600 focus:ring-indigo-500"
                />
                <span className="text-xs text-slate-300">Accepts New Members</span>
              </label>

              <label className="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  {...register('is_couple_household')}
                  className="rounded border-slate-700 bg-slate-800 text-indigo-600 focus:ring-indigo-500"
                />
                <span className="text-xs text-slate-300">Couple Household</span>
              </label>
            </div>
          </div>

          {/* Action buttons */}
          <div className="flex items-center justify-end gap-3 pt-4 border-t border-slate-800">
            <button
              type="button"
              onClick={handleClose}
              disabled={isSubmitting}
              className="rounded-lg px-4 py-2 text-xs font-medium text-slate-300 hover:bg-slate-800 transition-colors"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={isSubmitting}
              className="inline-flex items-center gap-2 rounded-lg bg-indigo-600 px-4 py-2 text-xs font-medium text-white hover:bg-indigo-500 transition-colors disabled:opacity-50"
            >
              {isSubmitting ? (
                <>
                  <div className="h-3 w-3 animate-spin rounded-full border-2 border-white border-t-transparent" />
                  <span>Saving…</span>
                </>
              ) : (
                'Save Changes'
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
