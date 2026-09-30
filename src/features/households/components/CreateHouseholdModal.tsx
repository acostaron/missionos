import { useState, useId } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useNavigate } from 'react-router-dom';
import { useQueryClient } from '@tanstack/react-query';
import { householdKeys } from '../queries';
import { usePlacementNodes } from '../../members/api/get-placement-nodes';
import { createHousehold } from '../api/create-household';
import { createHouseholdSchema, type CreateHouseholdFormValues } from '../schemas';
import { normalizeError } from '../../../lib/supabase/errors';

interface CreateHouseholdModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  onSuccessToast?: (msg: string) => void;
}

export function CreateHouseholdModal({
  isOpen,
  onClose,
  organizationId,
  onSuccessToast,
}: CreateHouseholdModalProps) {
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const titleId = useId();

  // Load selectable Chapter and Unit placement nodes
  const {
    data: nodes,
    isLoading: isNodesLoading,
    error: nodesError,
  } = usePlacementNodes(organizationId, isOpen);

  const {
    register,
    handleSubmit,
    watch,
    setValue,
    reset,
    formState: { errors },
  } = useForm<CreateHouseholdFormValues>({
    resolver: zodResolver(createHouseholdSchema),
    defaultValues: {
      name: '',
      code: '',
      parent_governance_node_id: '',
      household_category: 'pastoral',
      meeting_frequency: 'weekly',
      meeting_day_of_week: 5, // Friday
      meeting_start_time: '19:30',
      meeting_timezone_name: 'America/New_York',
      meeting_location_type: 'residence',
      meeting_location_text: '',
      target_member_count: 8,
      maximum_member_count: 12,
      accepts_new_members: true,
      language_code: 'en',
      is_couple_household: false,
    },
  });

  const selectedParentId = watch('parent_governance_node_id');

  if (!isOpen) return null;

  const handleClose = () => {
    reset();
    setErrorMessage(null);
    onClose();
  };

  const onSubmit = async (data: CreateHouseholdFormValues) => {
    try {
      setIsSubmitting(true);
      setErrorMessage(null);

      const result = await createHousehold(organizationId, {
        name: data.name,
        code: data.code,
        parent_governance_node_id: data.parent_governance_node_id,
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

      // Invalidate household directory lists
      await queryClient.invalidateQueries({
        queryKey: householdKeys.all,
      });

      onSuccessToast?.(`Household "${result.name}" created successfully.`);
      handleClose();
      navigate(`/app/households/${result.household_id}`);
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
              Create Household
            </h2>
            <p className="text-xs text-slate-400 mt-1">
              Establish a new pastoral household grouping under a Unit or Chapter.
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
          {/* Identity Section */}
          <div className="space-y-4">
            <h3 className="text-xs font-semibold uppercase tracking-wider text-slate-400">
              Household Identity
            </h3>

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

            {/* Parent Governance Placement */}
            <div>
              <label className="block text-xs font-medium text-slate-300">
                Parent Unit or Chapter <span className="text-rose-400">*</span>
              </label>

              {isNodesLoading ? (
                <div className="mt-1 h-10 animate-pulse rounded-lg bg-slate-800" />
              ) : nodesError ? (
                <p className="mt-1 text-xs text-rose-400">Failed to load placement hierarchy.</p>
              ) : (
                <div className="mt-1 max-h-48 overflow-y-auto rounded-lg border border-slate-700 bg-slate-950/40 p-2 space-y-1.5">
                  {nodes?.map((node) => {
                    const isSelected = selectedParentId === node.governance_node_id;
                    return (
                      <div
                        key={node.governance_node_id}
                        onClick={() => setValue('parent_governance_node_id', node.governance_node_id, { shouldValidate: true })}
                        className={`flex items-center justify-between p-2.5 rounded-lg border cursor-pointer transition-colors ${
                          isSelected
                            ? 'border-indigo-500 bg-indigo-950/40 text-indigo-200'
                            : 'border-slate-800 bg-slate-900/40 text-slate-300 hover:border-slate-700 hover:bg-slate-800/40'
                        }`}
                      >
                        <div>
                          <p className="text-xs font-medium">{node.node_name}</p>
                          <p className="text-[10px] text-slate-400">
                            Code: <span className="font-mono text-slate-300">{node.node_code}</span>
                            {node.parent_node_name && ` · under ${node.parent_node_name}`}
                          </p>
                        </div>
                        <span className="text-[10px] uppercase font-semibold px-2 py-0.5 rounded bg-slate-800 text-slate-400 border border-slate-700">
                          {node.node_type_code}
                        </span>
                      </div>
                    );
                  })}
                </div>
              )}
              {errors.parent_governance_node_id && (
                <p className="mt-1 text-xs text-rose-400">{errors.parent_governance_node_id.message}</p>
              )}
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
                  <span>Creating…</span>
                </>
              ) : (
                'Create Household'
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
