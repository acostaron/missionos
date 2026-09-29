import { useState, useId } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useQueryClient } from '@tanstack/react-query';
import { familyKeys } from '../queries';
import { addFamilyMember } from '../api/add-family-member';
import { useSearchMembers, type MemberListItem } from '../../members/queries';
import {
  FAMILY_ROLES,
  type AddFamilyMemberWarningResponse,
} from '../types';
import {
  addFamilyMemberSchema,
  type AddFamilyMemberFormValues,
} from '../schemas/add-family-member-schema';
import { normalizeError } from '../../../lib/supabase/errors';

interface AddFamilyMemberModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  familyId: string;
  familyName: string;
}

export function AddFamilyMemberModal({
  isOpen,
  onClose,
  organizationId,
  familyId,
  familyName,
}: AddFamilyMemberModalProps) {
  const queryClient = useQueryClient();
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [warningData, setWarningData] = useState<AddFamilyMemberWarningResponse | null>(null);

  // Member search state
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedMember, setSelectedMember] = useState<MemberListItem | null>(null);

  const titleId = useId();
  const todayStr = new Date().toISOString().split('T')[0];

  const {
    register,
    handleSubmit,
    setValue,
    reset,
    watch,
    formState: { errors },
  } = useForm<AddFamilyMemberFormValues>({
    resolver: zodResolver(addFamilyMemberSchema),
    defaultValues: {
      member_id: '',
      family_role: '',
      is_primary_contact: false,
      is_dependent: false,
      effective_from: todayStr,
    },
  });

  const memberIdValue = watch('member_id');

  // Search members query (active only)
  const { data: searchResults, isLoading: isSearching } = useSearchMembers(
    isOpen && searchQuery.trim().length >= 2 ? organizationId : null,
    { search: searchQuery.trim(), recordStatus: 'active', pageSize: 10 }
  );

  const handleClose = () => {
    reset();
    setSearchQuery('');
    setSelectedMember(null);
    setErrorMessage(null);
    setWarningData(null);
    onClose();
  };

  const handleSelectMember = (member: MemberListItem) => {
    setSelectedMember(member);
    setValue('member_id', member.id, { shouldValidate: true });
    setSearchQuery('');
    setWarningData(null);
    setErrorMessage(null);
  };

  const handleClearSelectedMember = () => {
    setSelectedMember(null);
    setValue('member_id', '', { shouldValidate: true });
    setWarningData(null);
    setErrorMessage(null);
  };

  const executeAdd = async (
    data: AddFamilyMemberFormValues,
    confirmMultiple: boolean = false
  ) => {
    try {
      setIsSubmitting(true);
      setErrorMessage(null);

      const res = await addFamilyMember({
        organizationId,
        familyId,
        memberId: data.member_id,
        familyRole: data.family_role || null,
        isPrimaryContact: data.is_primary_contact,
        isDependent: data.is_dependent,
        effectiveFrom: data.effective_from || null,
        confirmMultipleActiveFamily: confirmMultiple,
      });

      if (res.status === 'warning') {
        setWarningData(res);
        return;
      }

      // Success: Invalidate family profile & member-family query caches
      await queryClient.invalidateQueries({
        queryKey: familyKeys.profile(organizationId, familyId),
      });
      await queryClient.invalidateQueries({
        queryKey: ['members', 'families'],
      });

      handleClose();
    } catch (err: unknown) {
      const normalized = normalizeError(err);
      if (normalized.code === '42501') {
        setErrorMessage('You do not have permission to add family members.');
      } else if (normalized.code === '22023') {
        const msg = normalized.technicalMessage || '';
        if (msg.includes('already has an active membership')) {
          setErrorMessage('This member already has an active membership in this family.');
        } else if (msg.includes('status')) {
          setErrorMessage('Membership changes are not allowed for this family in its current status.');
        } else if (msg.includes('Deceased') || msg.includes('Archived')) {
          setErrorMessage('This member cannot be added to a new active family membership.');
        } else {
          setErrorMessage(msg || 'Invalid family membership information provided.');
        }
      } else if (normalized.code === '23502') {
        setErrorMessage('Required membership information is missing.');
      } else if (normalized.code === 'P0002') {
        setErrorMessage('Family or member was not found or is not accessible.');
      } else {
        setErrorMessage(normalized.message || 'Failed to add family member.');
      }
    } finally {
      setIsSubmitting(false);
    }
  };

  if (!isOpen) return null;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-sm"
      role="dialog"
      aria-modal="true"
      aria-labelledby={titleId}
    >
      <div className="relative w-full max-w-lg bg-white dark:bg-slate-900 rounded-xl shadow-2xl border border-slate-200 dark:border-slate-800 overflow-hidden flex flex-col max-h-[90vh]">
        {/* Header */}
        <div className="px-6 py-4 border-b border-slate-100 dark:border-slate-800 flex items-center justify-between">
          <div>
            <h2 id={titleId} className="text-lg font-bold text-slate-900 dark:text-white">
              Add Member to Family
            </h2>
            <p className="text-xs text-slate-500 dark:text-slate-400 mt-0.5">
              Adding to <span className="font-semibold text-slate-700 dark:text-slate-300">{familyName}</span>
            </p>
          </div>
          <button
            type="button"
            onClick={handleClose}
            className="p-1 rounded-lg text-slate-400 hover:text-slate-600 dark:hover:text-slate-200 hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors"
            aria-label="Close"
          >
            <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* Content Body */}
        <div className="p-6 overflow-y-auto space-y-4">
          {/* Relational Separation Callout */}
          <div className="p-3 bg-blue-50/70 dark:bg-blue-950/30 border border-blue-200 dark:border-blue-900/50 rounded-lg text-xs text-blue-800 dark:text-blue-300">
            <span className="font-semibold">Note:</span> Adding a member links them to this family unit. It does not automatically create spouse, parent, or child relationships.
          </div>

          {/* Error Banner */}
          {errorMessage && (
            <div className="p-3 bg-red-50 dark:bg-red-950/40 border border-red-200 dark:border-red-900/50 rounded-lg text-sm text-red-700 dark:text-red-300 flex items-start gap-2">
              <svg className="w-4 h-4 mt-0.5 shrink-0 text-red-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              <span>{errorMessage}</span>
            </div>
          )}

          {/* Multi-Family Warning Banner */}
          {warningData && selectedMember && (
            <div className="p-4 bg-amber-50 dark:bg-amber-950/40 border border-amber-300 dark:border-amber-800 rounded-lg text-sm text-amber-900 dark:text-amber-200 space-y-3">
              <div className="flex items-start gap-2">
                <svg className="w-5 h-5 text-amber-600 dark:text-amber-400 shrink-0 mt-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                </svg>
                <div className="space-y-1">
                  <p className="font-semibold text-amber-950 dark:text-amber-100">
                    {selectedMember.display_name} is already linked to other families:
                  </p>
                  <ul className="list-disc list-inside text-xs space-y-0.5 mt-1 text-amber-800 dark:text-amber-300">
                    {warningData.existing_families.map((ef) => (
                      <li key={ef.family_id}>
                        <span className="font-medium">{ef.display_name || ef.family_name}</span>
                        {ef.family_role ? ` (${ef.family_role})` : ''}
                      </li>
                    ))}
                  </ul>
                  <p className="text-xs text-amber-700 dark:text-amber-300/90 pt-1">
                    A member can belong to more than one family when appropriate. Confirm only if this additional family link is intentional.
                  </p>
                </div>
              </div>

              <div className="flex justify-end gap-2 pt-2 border-t border-amber-200 dark:border-amber-800/60">
                <button
                  type="button"
                  onClick={() => setWarningData(null)}
                  className="px-3 py-1.5 text-xs font-medium text-amber-800 dark:text-amber-300 hover:bg-amber-100 dark:hover:bg-amber-900/40 rounded-md transition-colors"
                >
                  Cancel
                </button>
                <button
                  type="button"
                  disabled={isSubmitting}
                  onClick={handleSubmit((data) => executeAdd(data, true))}
                  className="px-3 py-1.5 text-xs font-medium bg-amber-600 hover:bg-amber-700 text-white rounded-md shadow-sm transition-colors disabled:opacity-50"
                >
                  {isSubmitting ? 'Adding...' : 'Add anyway'}
                </button>
              </div>
            </div>
          )}

          {/* Form */}
          <form id="add-family-member-form" onSubmit={handleSubmit((data) => executeAdd(data, false))} className="space-y-4">
            {/* Member Picker */}
            <div>
              <label className="block text-xs font-semibold text-slate-700 dark:text-slate-300 mb-1">
                Select Member <span className="text-red-500">*</span>
              </label>

              {selectedMember ? (
                <div className="flex items-center justify-between p-3 bg-slate-50 dark:bg-slate-800/60 border border-slate-200 dark:border-slate-700 rounded-lg">
                  <div className="flex items-center gap-2.5">
                    <div className="w-8 h-8 rounded-full bg-blue-100 dark:bg-blue-900/60 text-blue-700 dark:text-blue-300 flex items-center justify-center font-bold text-xs">
                      {selectedMember.display_name.charAt(0)}
                    </div>
                    <div>
                      <div className="text-sm font-semibold text-slate-900 dark:text-white">
                        {selectedMember.display_name}
                      </div>
                      {selectedMember.member_number && (
                        <div className="text-xs text-slate-500 dark:text-slate-400">
                          #{selectedMember.member_number}
                        </div>
                      )}
                    </div>
                  </div>
                  <button
                    type="button"
                    onClick={handleClearSelectedMember}
                    className="text-xs text-blue-600 dark:text-blue-400 hover:underline font-medium"
                  >
                    Change
                  </button>
                </div>
              ) : (
                <div className="space-y-2">
                  <div className="relative">
                    <input
                      type="text"
                      value={searchQuery}
                      onChange={(e) => setSearchQuery(e.target.value)}
                      placeholder="Type at least 2 characters to search members..."
                      className="w-full px-3 py-2 text-sm bg-white dark:bg-slate-800 border border-slate-300 dark:border-slate-700 rounded-lg text-slate-900 dark:text-white placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-500"
                    />
                    {isSearching && (
                      <div className="absolute right-3 top-2.5 text-xs text-slate-400">
                        Searching...
                      </div>
                    )}
                  </div>

                  {/* Search Results Dropdown List */}
                  {searchQuery.trim().length >= 2 && searchResults && (
                    <div className="max-h-48 overflow-y-auto border border-slate-200 dark:border-slate-700 rounded-lg bg-white dark:bg-slate-800 shadow-md divide-y divide-slate-100 dark:divide-slate-700/60">
                      {searchResults.members.length === 0 ? (
                        <div className="p-3 text-xs text-slate-500 dark:text-slate-400 text-center">
                          No active members found matching &quot;{searchQuery}&quot;
                        </div>
                      ) : (
                        searchResults.members.map((member) => (
                          <button
                            key={member.id}
                            type="button"
                            onClick={() => handleSelectMember(member)}
                            className="w-full px-3 py-2 text-left hover:bg-blue-50 dark:hover:bg-slate-700/60 flex items-center justify-between transition-colors"
                          >
                            <span className="text-sm font-medium text-slate-800 dark:text-slate-200">
                              {member.display_name}
                            </span>
                            {member.member_number && (
                              <span className="text-xs text-slate-500 dark:text-slate-400">
                                #{member.member_number}
                              </span>
                            )}
                          </button>
                        ))
                      )}
                    </div>
                  )}
                </div>
              )}

              {errors.member_id && !memberIdValue && (
                <p className="text-xs text-red-500 mt-1">{errors.member_id.message}</p>
              )}
            </div>

            {/* Family Role */}
            <div>
              <label htmlFor="family-role-select" className="block text-xs font-semibold text-slate-700 dark:text-slate-300 mb-1">
                Family Role
              </label>
              <select
                id="family-role-select"
                {...register('family_role')}
                className="w-full px-3 py-2 text-sm bg-white dark:bg-slate-800 border border-slate-300 dark:border-slate-700 rounded-lg text-slate-900 dark:text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
              >
                <option value="">None / Unspecified</option>
                {FAMILY_ROLES.map((role) => (
                  <option key={role.value} value={role.value}>
                    {role.label}
                  </option>
                ))}
              </select>
              <p className="text-xs text-slate-500 dark:text-slate-400 mt-1">
                Administrative descriptor only; does not infer or create relationship records.
              </p>
            </div>

            {/* Flags: Primary Contact & Dependent */}
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 pt-1">
              <label className="flex items-start gap-2.5 p-3 rounded-lg border border-slate-200 dark:border-slate-700 hover:bg-slate-50 dark:hover:bg-slate-800/50 cursor-pointer transition-colors">
                <input
                  type="checkbox"
                  {...register('is_primary_contact')}
                  className="mt-0.5 rounded border-slate-300 text-blue-600 focus:ring-blue-500"
                />
                <div>
                  <span className="text-xs font-semibold text-slate-800 dark:text-slate-200 block">
                    Primary Contact
                  </span>
                  <span className="text-[11px] text-slate-500 dark:text-slate-400">
                    Family administrative point of contact
                  </span>
                </div>
              </label>

              <label className="flex items-start gap-2.5 p-3 rounded-lg border border-slate-200 dark:border-slate-700 hover:bg-slate-50 dark:hover:bg-slate-800/50 cursor-pointer transition-colors">
                <input
                  type="checkbox"
                  {...register('is_dependent')}
                  className="mt-0.5 rounded border-slate-300 text-blue-600 focus:ring-blue-500"
                />
                <div>
                  <span className="text-xs font-semibold text-slate-800 dark:text-slate-200 block">
                    Dependent
                  </span>
                  <span className="text-[11px] text-slate-500 dark:text-slate-400">
                    Mark as household or tax dependent
                  </span>
                </div>
              </label>
            </div>

            {/* Effective From */}
            <div>
              <label htmlFor="effective-from-input" className="block text-xs font-semibold text-slate-700 dark:text-slate-300 mb-1">
                Effective From
              </label>
              <input
                id="effective-from-input"
                type="date"
                max={todayStr}
                {...register('effective_from')}
                className="w-full px-3 py-2 text-sm bg-white dark:bg-slate-800 border border-slate-300 dark:border-slate-700 rounded-lg text-slate-900 dark:text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
              {errors.effective_from && (
                <p className="text-xs text-red-500 mt-1">{errors.effective_from.message}</p>
              )}
            </div>
          </form>
        </div>

        {/* Footer Actions */}
        <div className="px-6 py-4 border-t border-slate-100 dark:border-slate-800 bg-slate-50/50 dark:bg-slate-900/50 flex items-center justify-end gap-3">
          <button
            type="button"
            onClick={handleClose}
            disabled={isSubmitting}
            className="px-4 py-2 text-xs font-medium text-slate-700 dark:text-slate-300 hover:bg-slate-100 dark:hover:bg-slate-800 rounded-lg transition-colors"
          >
            Cancel
          </button>
          {!warningData && (
            <button
              type="submit"
              form="add-family-member-form"
              disabled={isSubmitting || !selectedMember}
              className="px-4 py-2 text-xs font-medium bg-blue-600 hover:bg-blue-700 text-white rounded-lg shadow-sm transition-colors disabled:opacity-50 flex items-center gap-1.5"
            >
              {isSubmitting ? (
                <>
                  <svg className="animate-spin w-3.5 h-3.5" viewBox="0 0 24 24" fill="none">
                    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
                  </svg>
                  <span>Adding...</span>
                </>
              ) : (
                'Add Member'
              )}
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
