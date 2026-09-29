import { useState, useId } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useQueryClient } from '@tanstack/react-query';
import { memberKeys, type MemberProfile } from '../queries';
import { updateMemberBasicProfile } from '../api/update-member-basic-profile';
import {
  createEditProfileSchema,
  type EditProfileFormData,
} from './edit-profile-schema';
import { normalizeError } from '../../../lib/supabase/errors';

interface EditMemberProfileModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  profile: MemberProfile;
  onSuccessToast?: (msg: string) => void;
}

export function EditMemberProfileModal({
  isOpen,
  onClose,
  organizationId,
  profile,
  onSuccessToast,
}: EditMemberProfileModalProps) {
  const queryClient = useQueryClient();
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const titleId = useId();

  const {
    register,
    handleSubmit,
    watch,
    formState: { errors },
  } = useForm<EditProfileFormData>({
    resolver: zodResolver(createEditProfileSchema(profile.name_effective_from)),
    defaultValues: {
      givenNames: profile.given_names ?? '',
      middleNames: profile.middle_names ?? '',
      familyName: profile.family_name ?? '',
      preferredName: profile.preferred_given_name ?? '',
      birthDate: profile.birth_date ?? '',
      sex: (profile.sex as '' | 'male' | 'female' | 'other') ?? '',
      civilStatus:
        (profile.civil_status as
          | ''
          | 'single'
          | 'married'
          | 'widowed'
          | 'separated'
          | 'divorced') ?? '',
      homeCountryCode: profile.home_country_code ?? '',
      preferredLanguageCode: profile.preferred_language_code ?? '',
      isNameChange: false,
      effectiveFrom: new Date().toISOString().split('T')[0],
      changeReason: '',
    },
  });

  const isNameChange = watch('isNameChange');

  if (!isOpen) return null;

  const onSubmit = async (data: EditProfileFormData) => {
    setIsSubmitting(true);
    setErrorMessage(null);

    try {
      await updateMemberBasicProfile({
        organizationId,
        memberId: profile.id,
        givenNames: data.givenNames,
        familyName: data.familyName,
        middleNames: data.middleNames,
        preferredName: data.preferredName,
        birthDate: data.birthDate,
        sex: data.sex,
        civilStatus: data.civilStatus,
        homeCountryCode: data.homeCountryCode,
        preferredLanguageCode: data.preferredLanguageCode,
        isNameChange: data.isNameChange,
        effectiveFrom: data.isNameChange ? data.effectiveFrom : null,
        changeReason: data.isNameChange ? data.changeReason : null,
      });

      // Invalidate member profile query
      queryClient.invalidateQueries({
        queryKey: memberKeys.profile(organizationId, profile.id),
      });

      // Invalidate member search/directory lists because display_name or sort_name may have changed
      queryClient.invalidateQueries({
        queryKey: memberKeys.lists(),
      });

      if (onSuccessToast) {
        onSuccessToast('Member profile updated.');
      }

      onClose();
    } catch (err: unknown) {
      const normalized = normalizeError(err);
      if (normalized.code === '42501') {
        setErrorMessage(
          'Access denied: You do not have permission to update member records for this profile.'
        );
      } else if (normalized.code === '22023') {
        setErrorMessage(
          normalized.message || 'Invalid input or effective date.'
        );
      } else if (normalized.code === 'P0002') {
        setErrorMessage(
          'Member record or active primary name not found or inaccessible.'
        );
      } else {
        setErrorMessage(normalized.message);
      }
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby={titleId}
      className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/80 p-4 backdrop-blur-sm overflow-y-auto"
    >
      <div className="w-full max-w-2xl rounded-2xl border border-slate-700 bg-slate-900 p-6 sm:p-8 shadow-2xl space-y-6 my-8">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-slate-800 pb-4">
          <div>
            <h2 id={titleId} className="text-xl font-bold tracking-tight text-slate-100">
              Edit Member Profile
            </h2>
            <p className="mt-1 text-xs text-slate-400">
              Update personal identity details and demographic information.
            </p>
          </div>
          <button
            type="button"
            onClick={onClose}
            disabled={isSubmitting}
            aria-label="Close dialog"
            className="rounded-lg p-1.5 text-slate-400 hover:bg-slate-800 hover:text-slate-200 transition-colors"
          >
            <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* Global Error Banner */}
        {errorMessage && (
          <div className="rounded-xl border border-red-700 bg-red-900/30 p-4 text-sm text-red-200">
            {errorMessage}
          </div>
        )}

        <form onSubmit={handleSubmit(onSubmit)} className="space-y-6">
          {/* SECTION 1: IDENTITY */}
          <div className="space-y-4">
            <h3 className="text-xs font-semibold uppercase tracking-wider text-slate-400">
              Identity & Names
            </h3>

            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              {/* Given Names */}
              <div>
                <label htmlFor="givenNames" className="block text-xs font-medium text-slate-300">
                  Given Name(s) <span className="text-rose-400">*</span>
                </label>
                <input
                  id="givenNames"
                  type="text"
                  {...register('givenNames')}
                  className="mt-1 block w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
                />
                {errors.givenNames && (
                  <p className="mt-1 text-xs text-rose-400">{errors.givenNames.message}</p>
                )}
              </div>

              {/* Family Name */}
              <div>
                <label htmlFor="familyName" className="block text-xs font-medium text-slate-300">
                  Family Name <span className="text-rose-400">*</span>
                </label>
                <input
                  id="familyName"
                  type="text"
                  {...register('familyName')}
                  className="mt-1 block w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
                />
                {errors.familyName && (
                  <p className="mt-1 text-xs text-rose-400">{errors.familyName.message}</p>
                )}
              </div>

              {/* Middle Names */}
              <div>
                <label htmlFor="middleNames" className="block text-xs font-medium text-slate-300">
                  Middle Name(s) <span className="text-slate-500">(optional)</span>
                </label>
                <input
                  id="middleNames"
                  type="text"
                  {...register('middleNames')}
                  className="mt-1 block w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
                />
              </div>

              {/* Preferred Name */}
              <div>
                <label htmlFor="preferredName" className="block text-xs font-medium text-slate-300">
                  Preferred First Name <span className="text-slate-500">(optional)</span>
                </label>
                <input
                  id="preferredName"
                  type="text"
                  {...register('preferredName')}
                  className="mt-1 block w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
                />
              </div>
            </div>
          </div>

          {/* SECTION 2: NAME UPDATE TYPE */}
          <div className="rounded-xl border border-slate-700/80 bg-slate-800/40 p-4 space-y-4">
            <div>
              <p className="text-xs font-semibold uppercase tracking-wider text-slate-300">
                Name Update Type
              </p>
              <p className="text-xs text-slate-400 mt-0.5">
                Specify whether this edit corrects a typo or records an official legal change.
              </p>
            </div>

            <div className="space-y-3">
              <label
                className={`flex items-start gap-3 rounded-lg border p-3 cursor-pointer transition-colors ${
                  !isNameChange
                    ? 'border-indigo-500/80 bg-indigo-950/20 text-indigo-100'
                    : 'border-slate-700/60 bg-slate-900/40 hover:bg-slate-800/60 text-slate-300'
                }`}
              >
                <input
                  type="radio"
                  name="nameUpdateType"
                  checked={!isNameChange}
                  onChange={() => {
                    const setValue = register('isNameChange').onChange;
                    setValue({ target: { value: false, name: 'isNameChange' } });
                  }}
                  className="mt-1 h-4 w-4 border-slate-700 bg-slate-900 text-indigo-600 focus:ring-indigo-500"
                />
                <div className="text-xs">
                  <p className="font-semibold text-slate-200">Correct existing record</p>
                  <p className="text-slate-400 mt-0.5 leading-relaxed">
                    Use this for spelling mistakes, data-entry corrections, or fixing an incorrectly recorded name. Updates current name in place.
                  </p>
                </div>
              </label>

              <label
                className={`flex items-start gap-3 rounded-lg border p-3 cursor-pointer transition-colors ${
                  isNameChange
                    ? 'border-indigo-500/80 bg-indigo-950/20 text-indigo-100'
                    : 'border-slate-700/60 bg-slate-900/40 hover:bg-slate-800/60 text-slate-300'
                }`}
              >
                <input
                  type="radio"
                  name="nameUpdateType"
                  checked={isNameChange}
                  onChange={() => {
                    const setValue = register('isNameChange').onChange;
                    setValue({ target: { value: true, name: 'isNameChange' } });
                  }}
                  className="mt-1 h-4 w-4 border-slate-700 bg-slate-900 text-indigo-600 focus:ring-indigo-500"
                />
                <div className="text-xs">
                  <p className="font-semibold text-slate-200">Record an official name change</p>
                  <p className="text-slate-400 mt-0.5 leading-relaxed">
                    Use this when the person&apos;s name actually changed, such as after marriage or a legal name change. Preserves name history.
                  </p>
                </div>
              </label>
            </div>

            {/* Official Name Change Fields */}
            {isNameChange && (
              <div className="mt-4 pt-4 border-t border-slate-700/60 grid grid-cols-1 gap-4 sm:grid-cols-2">
                <div>
                  <label htmlFor="effectiveFrom" className="block text-xs font-medium text-slate-300">
                    Effective Date <span className="text-rose-400">*</span>
                  </label>
                  <input
                    id="effectiveFrom"
                    type="date"
                    {...register('effectiveFrom')}
                    className="mt-1 block w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
                  />
                  {errors.effectiveFrom && (
                    <p className="mt-1 text-xs text-rose-400">{errors.effectiveFrom.message}</p>
                  )}
                  {profile.name_effective_from && (
                    <p className="mt-1 text-[11px] text-slate-500">
                      Cannot precede current name start date ({profile.name_effective_from})
                    </p>
                  )}
                </div>

                <div>
                  <label htmlFor="changeReason" className="block text-xs font-medium text-slate-300">
                    Reason for Change <span className="text-slate-500">(e.g., Marriage, Legal change)</span>
                  </label>
                  <input
                    id="changeReason"
                    type="text"
                    {...register('changeReason')}
                    placeholder="e.g. Marriage"
                    className="mt-1 block w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
                  />
                </div>
              </div>
            )}
          </div>

          {/* SECTION 3: DEMOGRAPHICS */}
          <div className="space-y-4">
            <h3 className="text-xs font-semibold uppercase tracking-wider text-slate-400">
              Demographics
            </h3>

            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              {/* Birth Date */}
              <div>
                <label htmlFor="birthDate" className="block text-xs font-medium text-slate-300">
                  Birth Date <span className="text-slate-500">(optional)</span>
                </label>
                <input
                  id="birthDate"
                  type="date"
                  max={new Date().toISOString().split('T')[0]}
                  {...register('birthDate')}
                  className="mt-1 block w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
                />
                {errors.birthDate && (
                  <p className="mt-1 text-xs text-rose-400">{errors.birthDate.message}</p>
                )}
              </div>

              {/* Sex */}
              <div>
                <label htmlFor="sex" className="block text-xs font-medium text-slate-300">
                  Sex <span className="text-slate-500">(optional)</span>
                </label>
                <select
                  id="sex"
                  {...register('sex')}
                  className="mt-1 block w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
                >
                  <option value="">Not specified</option>
                  <option value="male">Male</option>
                  <option value="female">Female</option>
                  <option value="other">Other</option>
                </select>
              </div>

              {/* Civil Status */}
              <div>
                <label htmlFor="civilStatus" className="block text-xs font-medium text-slate-300">
                  Civil Status <span className="text-slate-500">(optional)</span>
                </label>
                <select
                  id="civilStatus"
                  {...register('civilStatus')}
                  className="mt-1 block w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
                >
                  <option value="">Not specified</option>
                  <option value="single">Single</option>
                  <option value="married">Married</option>
                  <option value="widowed">Widowed</option>
                  <option value="separated">Separated</option>
                  <option value="divorced">Divorced</option>
                </select>
              </div>

              {/* Home Country */}
              <div>
                <label htmlFor="homeCountryCode" className="block text-xs font-medium text-slate-300">
                  Home Country <span className="text-slate-500">(optional)</span>
                </label>
                <select
                  id="homeCountryCode"
                  {...register('homeCountryCode')}
                  className="mt-1 block w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
                >
                  <option value="">Not specified</option>
                  <option value="US">United States (US)</option>
                  <option value="PH">Philippines (PH)</option>
                  <option value="CA">Canada (CA)</option>
                  <option value="GB">United Kingdom (GB)</option>
                  <option value="AU">Australia (AU)</option>
                </select>
              </div>

              {/* Preferred Language */}
              <div className="sm:col-span-2">
                <label htmlFor="preferredLanguageCode" className="block text-xs font-medium text-slate-300">
                  Preferred Language <span className="text-slate-500">(optional)</span>
                </label>
                <select
                  id="preferredLanguageCode"
                  {...register('preferredLanguageCode')}
                  className="mt-1 block w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
                >
                  <option value="">Not specified</option>
                  <option value="en">English (en)</option>
                  <option value="tl">Tagalog (tl)</option>
                  <option value="es">Spanish (es)</option>
                  <option value="fr">French (fr)</option>
                </select>
              </div>
            </div>
          </div>

          {/* Form Actions */}
          <div className="flex items-center justify-end gap-3 border-t border-slate-800 pt-5">
            <button
              type="button"
              onClick={onClose}
              disabled={isSubmitting}
              className="rounded-lg border border-slate-700 px-4 py-2 text-sm font-medium text-slate-300 hover:bg-slate-800 transition-colors disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={isSubmitting}
              className="inline-flex items-center justify-center rounded-lg bg-indigo-600 px-5 py-2 text-sm font-medium text-white hover:bg-indigo-500 transition-colors shadow-sm disabled:opacity-50"
            >
              {isSubmitting ? (
                <>
                  <svg className="mr-2 h-4 w-4 animate-spin text-white" viewBox="0 0 24 24" fill="none">
                    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8z" />
                  </svg>
                  Saving…
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
