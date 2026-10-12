import { useEffect, useState } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useFormationCatalog, useRecordFormationProgram } from '../queries';
import { formatProgramCategory } from '../formatters';
import {
  recordFormationProgramSchema,
  type RecordFormationProgramFormValues,
} from '../form-schemas';
import type {
  FormationDatePrecision,
  FormationProgramCategory,
  FormationProgramSummary,
  FormationVerificationMethod,
} from '../types';
import { normalizeError } from '../../../lib/supabase/errors';
import { Alert, Button, FormField, Input, Modal, Select, Textarea } from '../../../components/ui';

interface RecordFormationProgramModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  memberId: string;
  memberName?: string;
  onSuccessToast?: (msg: string) => void;
}

const MONTHS = [
  { value: 1, label: 'January (01)' },
  { value: 2, label: 'February (02)' },
  { value: 3, label: 'March (03)' },
  { value: 4, label: 'April (04)' },
  { value: 5, label: 'May (05)' },
  { value: 6, label: 'June (06)' },
  { value: 7, label: 'July (07)' },
  { value: 8, label: 'August (08)' },
  { value: 9, label: 'September (09)' },
  { value: 10, label: 'October (10)' },
  { value: 11, label: 'November (11)' },
  { value: 12, label: 'December (12)' },
];

export function RecordFormationProgramModal({
  isOpen,
  onClose,
  organizationId,
  memberId,
  memberName,
  onSuccessToast,
}: RecordFormationProgramModalProps) {
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const { data: catalog, isLoading: isCatalogLoading } = useFormationCatalog(
    organizationId,
    undefined,
    isOpen
  );

  const recordProgramMutation = useRecordFormationProgram();

  const currentYear = new Date().getFullYear();
  const today = new Date().toISOString().split('T')[0];

  const {
    register,
    handleSubmit,
    watch,
    setValue,
    reset,
    formState: { errors },
  } = useForm<RecordFormationProgramFormValues>({
    resolver: zodResolver(recordFormationProgramSchema),
    defaultValues: {
      programId: '',
      status: 'completed',
      datePrecision: 'exact_date',
      completedDate: today,
      completedYear: currentYear,
      completedMonth: new Date().getMonth() + 1,
      verificationMethod: 'leader_attestation',
      sourceReference: '',
      verificationNotes: '',
    },
  });

  const selectedStatus = watch('status');
  const selectedPrecision = watch('datePrecision') as FormationDatePrecision;
  const isWaived = selectedStatus === 'waived';
  const isInProgress = selectedStatus === 'in_progress';

  // If status is waived, force verification method to pastoral_waiver
  useEffect(() => {
    if (isWaived) {
      setValue('verificationMethod', 'pastoral_waiver');
    }
  }, [isWaived, setValue]);

  // Reset form whenever modal opens/closes
  useEffect(() => {
    if (isOpen) {
      setErrorMessage(null);
      reset({
        programId: '',
        status: 'completed',
        datePrecision: 'exact_date',
        completedDate: today,
        completedYear: currentYear,
        completedMonth: new Date().getMonth() + 1,
        verificationMethod: 'leader_attestation',
        sourceReference: '',
        verificationNotes: '',
      });
    }
  }, [isOpen, reset, today, currentYear]);

  // Group active programs by category
  const activePrograms = (catalog ?? []).filter((p) => p.is_active);
  const groupedPrograms = activePrograms.reduce<Record<string, FormationProgramSummary[]>>(
    (acc, prog) => {
      const cat = prog.program_category;
      if (!acc[cat]) acc[cat] = [];
      acc[cat].push(prog);
      return acc;
    },
    {}
  );

  const onSubmit = async (data: RecordFormationProgramFormValues) => {
    setErrorMessage(null);

    let completedDate: string | null = null;
    let completedYear: number | null = null;
    let completedMonth: number | null = null;
    let datePrecision: FormationDatePrecision = 'unknown';

    if (data.status === 'in_progress') {
      datePrecision = 'unknown';
    } else {
      datePrecision = data.datePrecision as FormationDatePrecision;
      if (datePrecision === 'exact_date') {
        completedDate = data.completedDate ? data.completedDate : null;
      } else if (datePrecision === 'month_year') {
        completedYear = data.completedYear ? Number(data.completedYear) : null;
        completedMonth = data.completedMonth ? Number(data.completedMonth) : null;
      } else if (datePrecision === 'year_only' || datePrecision === 'approximate') {
        completedYear = data.completedYear ? Number(data.completedYear) : null;
      }
    }

    const verificationMethod: FormationVerificationMethod =
      data.status === 'waived'
        ? 'pastoral_waiver'
        : (data.verificationMethod as FormationVerificationMethod);

    try {
      await recordProgramMutation.mutateAsync({
        organizationId,
        memberId,
        programId: data.programId,
        status: data.status,
        completedDate,
        completedYear,
        completedMonth,
        datePrecision,
        verificationMethod,
        sourceReference: data.sourceReference?.trim() || null,
        verificationNotes: data.verificationNotes?.trim() || null,
      });

      onSuccessToast?.('Formation recorded');
      onClose();
    } catch (err: unknown) {
      const normalized = normalizeError(err);
      setErrorMessage(normalized.technicalMessage || normalized.message);
    }
  };

  return (
    <Modal
      open={isOpen}
      onClose={onClose}
      title="Record Formation Program"
      description={
        memberName
          ? `Record a pastoral formation course or milestone for ${memberName}.`
          : 'Record a pastoral formation course or curriculum milestone.'
      }
      size="md"
      closeOnBackdrop={false}
      footer={
        <div className="flex items-center justify-end gap-3">
          <Button type="button" variant="outline" onClick={onClose} disabled={recordProgramMutation.isPending}>
            Cancel
          </Button>
          <Button
            type="submit"
            form="record-formation-program-form"
            loading={recordProgramMutation.isPending}
          >
            Save Record
          </Button>
        </div>
      }
    >
      <form
        id="record-formation-program-form"
        onSubmit={handleSubmit(onSubmit)}
        className="space-y-4 py-1"
      >
        {errorMessage && (
          <Alert variant="danger">{errorMessage}</Alert>
        )}

        {/* Course Selection */}
        <FormField
          label="Formation Course"
          required
          error={errors.programId?.message}
          hint="Select the canonical program from the curriculum catalog"
        >
          <Select {...register('programId')} disabled={isCatalogLoading}>
            <option value="">-- Select a course --</option>
            {Object.entries(groupedPrograms).map(([category, progs]) => (
              <optgroup
                key={category}
                label={formatProgramCategory(category as FormationProgramCategory)}
              >
                {progs.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.code} — {p.title}
                  </option>
                ))}
              </optgroup>
            ))}
          </Select>
        </FormField>

        {/* Status */}
        <FormField label="Participation Status" required error={errors.status?.message}>
          <Select {...register('status')}>
            <option value="in_progress">In progress</option>
            <option value="completed">Completed</option>
            <option value="waived">Waived</option>
          </Select>
        </FormField>

        {/* Completion Date (hidden for in_progress) */}
        {!isInProgress && (
          <div className="space-y-3 rounded-lg border border-line bg-surface p-3.5">
            <h4 className="text-xs font-semibold text-ink">When was it completed?</h4>

            <FormField label="Date Precision" required error={errors.datePrecision?.message}>
              <Select {...register('datePrecision')}>
                <option value="exact_date">Exact date</option>
                <option value="month_year">Month and year</option>
                <option value="year_only">Year only</option>
                <option value="approximate">Approximate (c. Year)</option>
                <option value="unknown">Unknown</option>
              </Select>
            </FormField>

            {selectedPrecision === 'exact_date' && (
              <FormField
                label="Exact Completion Date"
                required
                error={errors.completedDate?.message}
              >
                <Input type="date" max={today} {...register('completedDate')} />
              </FormField>
            )}

            {selectedPrecision === 'month_year' && (
              <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                <FormField
                  label="Month"
                  required
                  error={errors.completedMonth?.message}
                >
                  <Select {...register('completedMonth')}>
                    <option value="">-- Select Month --</option>
                    {MONTHS.map((m) => (
                      <option key={m.value} value={m.value}>
                        {m.label}
                      </option>
                    ))}
                  </Select>
                </FormField>

                <FormField
                  label="Year"
                  required
                  error={errors.completedYear?.message}
                >
                  <Input
                    type="number"
                    min={1980}
                    max={currentYear}
                    placeholder="YYYY"
                    {...register('completedYear')}
                  />
                </FormField>
              </div>
            )}

            {(selectedPrecision === 'year_only' || selectedPrecision === 'approximate') && (
              <FormField
                label={selectedPrecision === 'approximate' ? 'Approximate Year (c.)' : 'Year'}
                required
                error={errors.completedYear?.message}
              >
                <div className="flex items-center gap-2">
                  {selectedPrecision === 'approximate' && (
                    <span className="text-sm font-semibold text-ink-muted">c.</span>
                  )}
                  <Input
                    type="number"
                    min={1980}
                    max={currentYear}
                    placeholder="YYYY"
                    {...register('completedYear')}
                  />
                </div>
              </FormField>
            )}
          </div>
        )}

        {/* Verification Method / How do you know? */}
        <FormField
          label="How do you know?"
          required
          error={errors.verificationMethod?.message}
        >
          {isWaived ? (
            <div>
              <Input value="Pastoral waiver" disabled readOnly />
              <input type="hidden" value="pastoral_waiver" {...register('verificationMethod')} />
              <p className="mt-1 text-[11px] text-ink-muted">
                Waived status requires pastoral waiver verification.
              </p>
            </div>
          ) : (
            <Select {...register('verificationMethod')}>
              <option value="leader_attestation">I'm confirming it now</option>
              <option value="attendance_roll">From attendance records</option>
              <option value="historical_backfill">From old records</option>
            </Select>
          )}
        </FormField>

        {/* Source / Certificate Reference */}
        <FormField
          label="Source / Certificate Reference"
          hint="Optional certificate number, batch tag, or source reference"
          error={errors.sourceReference?.message}
        >
          <Input
            placeholder="e.g. Batch 2015-A, Cert #4012"
            maxLength={200}
            {...register('sourceReference')}
          />
        </FormField>

        {/* Internal Note */}
        <FormField
          label="Internal Note"
          hint="Visible to leaders only"
          error={errors.verificationNotes?.message}
        >
          <Textarea
            rows={2}
            placeholder="Additional context or pastoral notes regarding this record..."
            maxLength={1000}
            {...register('verificationNotes')}
          />
        </FormField>
      </form>
    </Modal>
  );
}
