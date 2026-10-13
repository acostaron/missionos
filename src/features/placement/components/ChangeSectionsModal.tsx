import { useState, useMemo } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { Modal } from '../../../components/ui/Modal';
import { Button } from '../../../components/ui/Button';
import { Alert } from '../../../components/ui/Alert';
import { useSectionsOverview } from '../../sections/queries';
import { useChangeMembersSectionBulk } from '../queries';
import { changeSectionsSchema, type ChangeSectionsFormValues } from '../schemas';
import { getSectionChangeErrorMessage, formatSkipReason } from '../error-message';
import { localToday } from '../../formation/form-schemas';
import type { SelectedMemberInfo, ChangeMembersSectionBulkResponse } from '../types';

interface ChangeSectionsModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  selectedMembers: Map<string, SelectedMemberInfo>;
  onSectionChangeComplete: (changedMemberIds: string[]) => void;
}

export function ChangeSectionsModal({
  isOpen,
  onClose,
  organizationId,
  selectedMembers,
  onSectionChangeComplete,
}: ChangeSectionsModalProps) {
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [result, setResult] = useState<ChangeMembersSectionBulkResponse | null>(null);

  const { data: sectionsData, isLoading: isSectionsLoading } = useSectionsOverview(
    isOpen ? organizationId : null
  );

  const changeSectionMutation = useChangeMembersSectionBulk(organizationId);

  const today = localToday();

  const {
    register,
    handleSubmit,
    watch,
    reset,
    formState: { errors, isSubmitting },
  } = useForm<ChangeSectionsFormValues>({
    resolver: zodResolver(changeSectionsSchema),
    defaultValues: {
      sectionCode: '',
      effectiveFrom: today,
      reason: '',
    },
  });

  const selectedSectionCode = watch('sectionCode');
  const selectedEffectiveFrom = watch('effectiveFrom') || today;

  const sections = useMemo(() => sectionsData?.sections ?? [], [sectionsData]);

  const selectedSectionName = useMemo(() => {
    return sections.find((s) => s.code === selectedSectionCode)?.name;
  }, [sections, selectedSectionCode]);

  const selectedCount = selectedMembers.size;
  const selectedList = useMemo(() => Array.from(selectedMembers.entries()), [selectedMembers]);

  const hasCouplesMember = useMemo(
    () => selectedList.some(([, info]) => info.section_code === 'sec_couples'),
    [selectedList]
  );

  const handleClose = () => {
    setErrorMessage(null);
    setResult(null);
    reset({
      sectionCode: '',
      effectiveFrom: localToday(),
      reason: '',
    });
    onClose();
  };

  const handleDone = () => {
    if (result) {
      const changedIds = result.changed.map((c) => c.member_id);
      onSectionChangeComplete(changedIds);
    }
    handleClose();
  };

  const onSubmit = async (values: ChangeSectionsFormValues) => {
    setErrorMessage(null);
    try {
      const memberIds = Array.from(selectedMembers.keys());
      const res = await changeSectionMutation.mutateAsync({
        memberIds,
        sectionCode: values.sectionCode,
        effectiveFrom: values.effectiveFrom,
        reason: values.reason,
      });
      setResult(res);
    } catch (err) {
      setErrorMessage(getSectionChangeErrorMessage(err));
    }
  };

  return (
    <Modal
      open={isOpen}
      onClose={handleClose}
      title={result ? 'Section Change Results' : 'Change Section'}
      description={
        result
          ? undefined
          : 'Move selected members to a different ministry section. Each change is recorded in the member history.'
      }
      size="md"
      closeOnBackdrop={false}
    >
      {result ? (
        <div className="space-y-4">
          <div className="rounded-lg border border-emerald-500/30 bg-emerald-500/10 p-4">
            <p className="text-sm font-medium text-emerald-400">
              Changed {result.changed_count}.
            </p>
          </div>

          {result.skipped_count > 0 && (
            <div className="space-y-2">
              <p className="text-sm font-medium text-amber-400">
                Skipped {result.skipped_count}:
              </p>
              <div className="max-h-48 overflow-y-auto space-y-2 rounded-lg border border-border p-3 bg-surface-subtle">
                {result.skipped.map((s) => {
                  const info = selectedMembers.get(s.member_id);
                  const name = info?.display_name || s.member_id;
                  const reason = formatSkipReason(s.reason, s.message);
                  return (
                    <div
                      key={s.member_id}
                      className="flex items-center justify-between text-xs py-1 border-b border-border/50 last:border-b-0"
                    >
                      <span className="font-medium text-ink">{name}</span>
                      <span className="text-ink-muted">{reason}</span>
                    </div>
                  );
                })}
              </div>
            </div>
          )}

          <div className="flex justify-end pt-2">
            <Button variant="primary" onClick={handleDone}>
              Done
            </Button>
          </div>
        </div>
      ) : (
        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
          {errorMessage && <Alert variant="danger">{errorMessage}</Alert>}

          {/* Section Select */}
          <div>
            <label
              htmlFor="section-select"
              className="block text-xs font-semibold text-ink-muted uppercase tracking-wider mb-1"
            >
              Section <span className="text-rose-400">*</span>
            </label>
            <select
              id="section-select"
              {...register('sectionCode')}
              disabled={isSectionsLoading || isSubmitting}
              className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm text-ink focus:border-accent focus:outline-none focus:ring-1 focus:ring-accent"
            >
              <option value="">Select section...</option>
              {sections.map((sec) => (
                <option key={sec.code} value={sec.code}>
                  {sec.name}
                </option>
              ))}
            </select>
            {errors.sectionCode && (
              <p className="mt-1 text-xs text-rose-400">{errors.sectionCode.message}</p>
            )}
          </div>

          {/* Effective Date */}
          <div>
            <label
              htmlFor="section-effective-date-input"
              className="block text-xs font-semibold text-ink-muted uppercase tracking-wider mb-1"
            >
              Effective Date <span className="text-rose-400">*</span>
            </label>
            <input
              id="section-effective-date-input"
              type="date"
              max={today}
              {...register('effectiveFrom')}
              disabled={isSubmitting}
              className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm text-ink focus:border-accent focus:outline-none focus:ring-1 focus:ring-accent"
            />
            {errors.effectiveFrom && (
              <p className="mt-1 text-xs text-rose-400">{errors.effectiveFrom.message}</p>
            )}
          </div>

          {/* Reason */}
          <div>
            <label
              htmlFor="section-reason-textarea"
              className="block text-xs font-semibold text-ink-muted uppercase tracking-wider mb-1"
            >
              Reason <span className="text-rose-400">*</span>
            </label>
            <textarea
              id="section-reason-textarea"
              rows={3}
              placeholder="e.g., Transitioned to Handmaids section"
              {...register('reason')}
              disabled={isSubmitting}
              className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm text-ink focus:border-accent focus:outline-none focus:ring-1 focus:ring-accent placeholder:text-ink-muted/50"
            />
            {errors.reason && (
              <p className="mt-1 text-xs text-rose-400">{errors.reason.message}</p>
            )}
          </div>

          {/* Summary before confirming */}
          <div className="rounded-lg border border-border bg-surface-subtle p-3 space-y-2">
            <p className="text-xs font-medium text-ink">
              Move {selectedCount} {selectedCount === 1 ? 'member' : 'members'} to{' '}
              {selectedSectionName || 'the selected section'}, effective {selectedEffectiveFrom}.
            </p>

            {hasCouplesMember && (
              <p className="text-xs text-amber-400">
                Members leaving Couples will no longer be paired with their spouse in the Couples section.
              </p>
            )}

            {/* Scrollable list of selected members */}
            <div className="max-h-48 overflow-y-auto divide-y divide-border/40 rounded border border-border/60 bg-surface px-2 py-1">
              {selectedList.map(([id, info]) => (
                <div key={id} className="py-1 text-xs flex items-center justify-between">
                  <span className="font-medium text-ink">{info.display_name}</span>
                  {info.member_number && (
                    <span className="text-[11px] font-mono text-ink-muted">
                      {info.member_number}
                    </span>
                  )}
                </div>
              ))}
            </div>
          </div>

          {/* Modal Footer / Actions */}
          <div className="flex justify-end gap-3 pt-2">
            <Button
              id="cancel-change-section-btn"
              type="button"
              variant="outline"
              onClick={handleClose}
              disabled={isSubmitting}
            >
              Cancel
            </Button>
            <Button
              type="submit"
              variant="primary"
              disabled={isSubmitting || selectedCount === 0}
            >
              {isSubmitting
                ? 'Changing section...'
                : `Change section for ${selectedCount} ${selectedCount === 1 ? 'member' : 'members'}`}
            </Button>
          </div>
        </form>
      )}
    </Modal>
  );
}
