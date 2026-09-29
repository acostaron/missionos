import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useQueryClient } from '@tanstack/react-query';
import { createMemberSchema, type CreateMemberFormData } from './schema';
import { Step1Identity } from './steps/Step1Identity';
import { Step2Membership } from './steps/Step2Membership';
import { Step3Placement } from './steps/Step3Placement';
import { Step4Contact } from './steps/Step4Contact';
import { Step5Review } from './steps/Step5Review';
import { DuplicateWarningModal } from './DuplicateWarningModal';
import { createMember } from '../api/create-member';
import { usePlacementNodes } from '../api/get-placement-nodes';
import { memberKeys } from '../queries';
import { normalizeError } from '../../../lib/supabase/errors';
import type { DuplicateCandidateMatch, CreateMemberSuccessResponse } from '../types';

interface WizardProps {
  organizationId: string;
  canManageIdentifiers: boolean;
  canManagePlacements: boolean;
  canManageContacts: boolean;
  canManageAddresses: boolean;
  canViewStructure: boolean;
}

const STEPS = [
  { id: 1, label: 'Identity' },
  { id: 2, label: 'Membership' },
  { id: 3, label: 'Placement' },
  { id: 4, label: 'Contact' },
  { id: 5, label: 'Review' },
];

export function MemberOnboardingWizard({
  organizationId,
  canManageIdentifiers,
  canManagePlacements,
  canManageContacts,
  canManageAddresses,
  canViewStructure,
}: WizardProps) {
  const navigate = useNavigate();
  const queryClient = useQueryClient();

  const [currentStep, setCurrentStep] = useState(1);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  // Duplicate Warning Modal state
  const [duplicateWarning, setDuplicateWarning] = useState<{
    isOpen: boolean;
    count: number;
    matches: DuplicateCandidateMatch[];
  }>({
    isOpen: false,
    count: 0,
    matches: [],
  });

  // Success state
  const [successResult, setSuccessResult] = useState<CreateMemberSuccessResponse | null>(null);

  // Form initialization
  const {
    register,
    handleSubmit,
    trigger,
    watch,
    getValues,
    formState: { errors },
  } = useForm<CreateMemberFormData>({
    resolver: zodResolver(createMemberSchema),
    mode: 'onBlur',
    defaultValues: {
      givenNames: '',
      middleNames: '',
      familyName: '',
      preferredName: '',
      birthDate: '',
      sex: '',
      civilStatus: '',
      joinedOn: new Date().toISOString().split('T')[0],
      homeCountryCode: 'US',
      allocateMemberNumber: canManageIdentifiers,
      governanceNodeId: '',
      email: '',
      phone: '',
      phoneCountryCode: 'US',
      addressLine1: '',
      addressLine2: '',
      cityName: '',
      stateProvinceName: '',
      postalCode: '',
      addressCountryCode: 'US',
    },
  });

  // Query placement nodes for review step label lookup
  const { data: placementNodes } = usePlacementNodes(
    organizationId,
    canManagePlacements && canViewStructure
  );

  // Validate only the current step before advancing
  const handleNext = async () => {
    let fieldsToValidate: (keyof CreateMemberFormData)[] = [];

    if (currentStep === 1) {
      fieldsToValidate = ['givenNames', 'familyName', 'birthDate', 'sex', 'civilStatus'];
    } else if (currentStep === 2) {
      fieldsToValidate = ['joinedOn', 'homeCountryCode', 'allocateMemberNumber'];
    } else if (currentStep === 3) {
      fieldsToValidate = ['governanceNodeId'];
    } else if (currentStep === 4) {
      fieldsToValidate = [
        'email',
        'phone',
        'phoneCountryCode',
        'addressLine1',
        'addressLine2',
        'cityName',
        'stateProvinceName',
        'postalCode',
        'addressCountryCode',
      ];
    }

    const isValid = await trigger(fieldsToValidate);
    if (isValid) {
      setCurrentStep((prev) => Math.min(prev + 1, STEPS.length));
    }
  };

  const handlePrev = () => {
    setCurrentStep((prev) => Math.max(prev - 1, 1));
  };

  // Submit to create_member RPC
  const executeSubmission = async (formData: CreateMemberFormData, allowDuplicateOverride: boolean = false) => {
    setIsSubmitting(true);
    setErrorMessage(null);

    try {
      const response = await createMember(
        {
          organizationId,
          givenNames: formData.givenNames,
          familyName: formData.familyName,
          middleNames: formData.middleNames,
          preferredName: formData.preferredName,
          birthDate: formData.birthDate,
          sex: formData.sex,
          civilStatus: formData.civilStatus,
          joinedOn: formData.joinedOn,
          homeCountryCode: formData.homeCountryCode,
          governanceNodeId: formData.governanceNodeId,
          allocateMemberNumber: formData.allocateMemberNumber,
          email: formData.email,
          phone: formData.phone,
          phoneCountryCode: formData.phoneCountryCode,
          addressLine1: formData.addressLine1,
          addressLine2: formData.addressLine2,
          cityName: formData.cityName,
          stateProvinceName: formData.stateProvinceName,
          postalCode: formData.postalCode,
          addressCountryCode: formData.addressCountryCode,
          allowPotentialDuplicate: allowDuplicateOverride,
        },
        {
          canManageIdentifiers,
          canManagePlacements,
          canManageContacts,
          canManageAddresses,
        }
      );

      if (response.status === 'duplicate_warning') {
        setDuplicateWarning({
          isOpen: true,
          count: response.warning_count,
          matches: response.candidate_matches,
        });
        return;
      }

      // Success
      setSuccessResult(response);
      setDuplicateWarning({ isOpen: false, count: 0, matches: [] });

      // Invalidate member queries so directory updates immediately
      queryClient.invalidateQueries({ queryKey: memberKeys.all });
    } catch (err: unknown) {
      const normalized = normalizeError(err);
      if (
        normalized.code === '42501' &&
        normalized.technicalMessage?.includes('unplaced')
      ) {
        setErrorMessage(
          'You do not have permission to create an unplaced member. Select a Chapter or Unit you are authorized to manage.'
        );
      } else {
        setErrorMessage(normalized.message);
      }
    } finally {
      setIsSubmitting(false);
    }
  };

  const onSubmit = (data: CreateMemberFormData) => {
    executeSubmission(data, false);
  };

  const handleCreateAnyway = () => {
    const currentValues = getValues();
    executeSubmission(currentValues, true);
  };

  // ---------------------------------------------------------------------------
  // Success Screen
  // ---------------------------------------------------------------------------
  if (successResult) {
    return (
      <div className="rounded-2xl border border-slate-700 bg-slate-900/60 p-8 text-center space-y-6">
        <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-emerald-500/20 text-emerald-400">
          <svg className="h-8 w-8" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
          </svg>
        </div>

        <div>
          <h2 className="text-2xl font-bold text-slate-100">Member Created Successfully</h2>
          <p className="mt-1 text-sm text-slate-400">
            {successResult.display_name} has been enrolled into MissionOS.
          </p>
        </div>

        {successResult.member_number ? (
          <div className="inline-block rounded-xl border border-indigo-500/30 bg-indigo-950/40 px-6 py-4">
            <span className="text-xs uppercase tracking-wider text-indigo-300 font-semibold">
              Assigned Member Number
            </span>
            <p className="mt-1 font-mono text-2xl font-bold text-indigo-200">
              {successResult.member_number}
            </p>
          </div>
        ) : (
          <p className="text-xs text-slate-500 italic">No member number assigned.</p>
        )}

        <div className="flex justify-center gap-3 pt-4">
          <button
            type="button"
            onClick={() => navigate('/app/members')}
            className="rounded-lg border border-slate-700 px-4 py-2 text-sm font-medium text-slate-300 hover:bg-slate-800 transition-colors"
          >
            Member Directory
          </button>
          <button
            type="button"
            onClick={() => navigate(`/app/members/${successResult.member_id}`)}
            className="rounded-lg bg-indigo-600 px-5 py-2 text-sm font-medium text-white hover:bg-indigo-500 transition-colors shadow-sm"
          >
            View Member Profile →
          </button>
        </div>
      </div>
    );
  }

  // ---------------------------------------------------------------------------
  // Wizard Shell
  // ---------------------------------------------------------------------------
  return (
    <div className="space-y-8">
      {/* Progress Steps */}
      <nav aria-label="Progress">
        <ol className="flex items-center justify-between border-b border-slate-800 pb-4">
          {STEPS.map((step) => {
            const isCompleted = step.id < currentStep;
            const isCurrent = step.id === currentStep;

            return (
              <li key={step.id} className="flex items-center gap-2">
                <span
                  className={`flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-xs font-semibold ${
                    isCurrent
                      ? 'bg-indigo-600 text-white'
                      : isCompleted
                      ? 'bg-emerald-600 text-white'
                      : 'bg-slate-800 text-slate-400 border border-slate-700'
                  }`}
                >
                  {isCompleted ? '✓' : step.id}
                </span>
                <span
                  className={`text-xs font-medium hidden sm:inline ${
                    isCurrent ? 'text-slate-100 font-bold' : isCompleted ? 'text-slate-300' : 'text-slate-500'
                  }`}
                >
                  {step.label}
                </span>
              </li>
            );
          })}
        </ol>
      </nav>

      {/* Error Alert */}
      {errorMessage && (
        <div className="rounded-xl border border-red-700 bg-red-900/20 p-4 flex items-start gap-3">
          <svg className="h-5 w-5 text-red-400 shrink-0 mt-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          <div className="text-sm text-red-300">
            <p className="font-medium">Could not create member</p>
            <p className="mt-0.5 text-xs text-red-400">{errorMessage}</p>
          </div>
        </div>
      )}

      {/* Form Form Body */}
      <form onSubmit={handleSubmit(onSubmit)}>
        {currentStep === 1 && <Step1Identity register={register} errors={errors} />}

        {currentStep === 2 && (
          <Step2Membership
            register={register}
            errors={errors}
            canManageIdentifiers={canManageIdentifiers}
          />
        )}

        {currentStep === 3 && (
          <Step3Placement
            register={register}
            watch={watch}
            organizationId={organizationId}
            canManagePlacements={canManagePlacements}
            canViewStructure={canViewStructure}
          />
        )}

        {currentStep === 4 && (
          <Step4Contact
            register={register}
            errors={errors}
            canManageContacts={canManageContacts}
            canManageAddresses={canManageAddresses}
          />
        )}

        {currentStep === 5 && (
          <Step5Review
            formData={watch()}
            placementNodes={placementNodes}
            canManageIdentifiers={canManageIdentifiers}
            canManagePlacements={canManagePlacements}
            canManageContacts={canManageContacts}
            canManageAddresses={canManageAddresses}
          />
        )}

        {/* Wizard Controls */}
        <div className="mt-8 flex items-center justify-between border-t border-slate-800 pt-5">
          {currentStep > 1 ? (
            <button
              type="button"
              onClick={handlePrev}
              disabled={isSubmitting}
              className="rounded-lg border border-slate-700 px-4 py-2 text-sm font-medium text-slate-300 hover:bg-slate-800 transition-colors disabled:opacity-50"
            >
              ← Back
            </button>
          ) : (
            <button
              type="button"
              onClick={() => navigate('/app/members')}
              disabled={isSubmitting}
              className="rounded-lg border border-slate-800 px-4 py-2 text-sm font-medium text-slate-400 hover:text-slate-200 transition-colors"
            >
              Cancel
            </button>
          )}

          {currentStep < STEPS.length ? (
            <button
              type="button"
              onClick={handleNext}
              className="rounded-lg bg-indigo-600 px-5 py-2 text-sm font-medium text-white hover:bg-indigo-500 transition-colors shadow-sm"
            >
              Continue →
            </button>
          ) : (
            <button
              type="submit"
              disabled={isSubmitting}
              className="rounded-lg bg-indigo-600 px-6 py-2 text-sm font-medium text-white hover:bg-indigo-500 transition-colors shadow-sm disabled:opacity-50 flex items-center gap-2"
            >
              {isSubmitting ? (
                <>
                  <svg className="h-4 w-4 animate-spin text-white" viewBox="0 0 24 24" fill="none">
                    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8z" />
                  </svg>
                  Creating Member…
                </>
              ) : (
                'Create Member'
              )}
            </button>
          )}
        </div>
      </form>

      {/* Duplicate Warning Modal */}
      <DuplicateWarningModal
        isOpen={duplicateWarning.isOpen}
        candidateMatches={duplicateWarning.matches}
        warningCount={duplicateWarning.count}
        onCancel={() => setDuplicateWarning((prev) => ({ ...prev, isOpen: false }))}
        onCreateAnyway={handleCreateAnyway}
        isSubmitting={isSubmitting}
      />
    </div>
  );
}
