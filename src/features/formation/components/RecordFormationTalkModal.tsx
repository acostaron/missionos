import { useEffect, useState } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useFormationProgram, useRecordFormationTalk } from '../queries';
import {
  localToday,
  recordFormationTalkSchema,
  type RecordFormationTalkFormValues,
} from '../form-schemas';
import type { FormationSessionStatus, FormationTranscriptProgram } from '../types';
import { getFormationErrorMessage } from '../error-message';
import { Alert, Button, FormField, Input, Modal, Select, Textarea } from '../../../components/ui';

interface RecordFormationTalkModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  memberId: string;
  programRecord: FormationTranscriptProgram;
  onSuccessToast?: (msg: string) => void;
}

export function RecordFormationTalkModal({
  isOpen,
  onClose,
  organizationId,
  memberId,
  programRecord,
  onSuccessToast,
}: RecordFormationTalkModalProps) {
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  // Fetch canonical program talks
  const { data: programDetail, isLoading: isProgramLoading } = useFormationProgram(
    organizationId,
    programRecord.program_id,
    isOpen
  );

  const recordTalkMutation = useRecordFormationTalk(memberId);
  const today = localToday();

  const {
    register,
    handleSubmit,
    reset,
    formState: { errors },
  } = useForm<RecordFormationTalkFormValues>({
    resolver: zodResolver(recordFormationTalkSchema),
    defaultValues: {
      talkId: '',
      sessionStatus: 'attended',
      attendedDate: today,
      notes: '',
    },
  });

  // Calculate unrecorded talks: talks of that program not yet recorded in the parent program record
  const recordedTalkIds = new Set(programRecord.talks.map((t) => t.talk_id));
  const availableTalks = (programDetail?.talks ?? []).filter(
    (t) => !recordedTalkIds.has(t.id)
  );
  const isAllRecorded = !isProgramLoading && !!programDetail && availableTalks.length === 0;

  useEffect(() => {
    if (isOpen) {
      setErrorMessage(null);
      reset({
        talkId: '',
        sessionStatus: 'attended',
        attendedDate: today,
        notes: '',
      });
    }
  }, [isOpen, reset, today]);

  const onSubmit = async (data: RecordFormationTalkFormValues) => {
    setErrorMessage(null);

    try {
      await recordTalkMutation.mutateAsync({
        organizationId,
        programRecordId: programRecord.record_id,
        talkId: data.talkId,
        sessionStatus: data.sessionStatus as FormationSessionStatus,
        attendedDate: data.attendedDate?.trim() || null,
        notes: data.notes?.trim() || null,
      });

      onSuccessToast?.('Talk recorded');
      onClose();
    } catch (err: unknown) {
      setErrorMessage(getFormationErrorMessage(err));
    }
  };

  return (
    <Modal
      open={isOpen}
      onClose={onClose}
      title="Record Talk Participation"
      description={`Record session attendance for ${programRecord.title} (${programRecord.code}).`}
      size="md"
      closeOnBackdrop={false}
      footer={
        <div className="flex items-center justify-end gap-3">
          <Button
            type="button"
            variant="outline"
            onClick={onClose}
            disabled={recordTalkMutation.isPending}
          >
            Cancel
          </Button>
          <Button
            type="submit"
            form="record-formation-talk-form"
            loading={recordTalkMutation.isPending}
            disabled={isProgramLoading || !programDetail || isAllRecorded}
          >
            Save Talk
          </Button>
        </div>
      }
    >
      <form
        id="record-formation-talk-form"
        onSubmit={handleSubmit(onSubmit)}
        className="space-y-4 py-1"
      >
        {errorMessage && (
          <Alert variant="danger">{errorMessage}</Alert>
        )}

        {isAllRecorded && (
          <Alert variant="info">All talks for this course are recorded.</Alert>
        )}

        {/* Talk selection */}
        <FormField
          label="Talk / Session"
          required
          error={errors.talkId?.message}
          hint={
            isAllRecorded
              ? 'All talks for this course are recorded.'
              : 'Select a talk session not yet recorded'
          }
        >
          <Select {...register('talkId')} disabled={isProgramLoading || isAllRecorded}>
            <option value="">
              {isAllRecorded
                ? '-- All talks for this course are recorded --'
                : '-- Select a talk --'}
            </option>
            {availableTalks.map((talk) => (
              <option key={talk.id} value={talk.id}>
                {talk.sequence_order}. {talk.talk_code} — {talk.title}
              </option>
            ))}
          </Select>
        </FormField>

        {/* Session Status */}
        <FormField label="Session Status" required error={errors.sessionStatus?.message}>
          <Select {...register('sessionStatus')} disabled={isAllRecorded}>
            <option value="attended">Attended</option>
            <option value="absent_excused">Excused absence</option>
            <option value="makeup_attended">Make-up attended</option>
            <option value="waived">Waived</option>
          </Select>
        </FormField>

        {/* Attended Date */}
        <FormField
          label="Attended Date"
          hint="Optional date of attendance (cannot be in the future)"
          error={errors.attendedDate?.message}
        >
          <Input type="date" max={today} {...register('attendedDate')} disabled={isAllRecorded} />
        </FormField>

        {/* Note */}
        <FormField
          label="Notes"
          hint="Optional note or context regarding this session"
          error={errors.notes?.message}
        >
          <Textarea
            rows={2}
            placeholder="e.g. Completed via make-up session with household leader"
            maxLength={500}
            {...register('notes')}
            disabled={isAllRecorded}
          />
        </FormField>
      </form>
    </Modal>
  );
}
