import { useState, useEffect, useId } from 'react';
import {
  Modal,
  Button,
  FormField,
  Input,
  Alert,
} from '../../../components/ui';
import { useAddProgramSession, useUpdateProgramSession } from '../queries';
import { getEventErrorMessage } from '../../events/error-message';
import { getTodayNyDate, isoToNyLocal, nyLocalToIso } from '../../../lib/ny-time';
import type { EventSummary } from '../../events/types';

interface ScheduleSessionModalProps {
  open: boolean;
  onClose: () => void;
  organizationId: string;
  runId: string;
  sessionNumber: number;
  /** Pass existing session when editing/changing */
  session?: EventSummary | null;
  onSuccess?: () => void;
}

export function ScheduleSessionModal({
  open,
  onClose,
  organizationId,
  runId,
  sessionNumber,
  session,
  onSuccess,
}: ScheduleSessionModalProps) {
  const isEditing = !!session;
  const addMutation = useAddProgramSession();
  const updateMutation = useUpdateProgramSession();
  const isSubmitting = addMutation.isPending || updateMutation.isPending;

  const [startDate, setStartDate] = useState('');
  const [startTime, setStartTime] = useState('19:00');
  const [endDate, setEndDate] = useState('');
  const [endTime, setEndTime] = useState('');
  const [locationText, setLocationText] = useState('');
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const startDateId = useId();
  const startTimeId = useId();
  const endDateId = useId();
  const endTimeId = useId();
  const locationId = useId();

  useEffect(() => {
    if (!open) {
      setErrorMessage(null);
      return;
    }

    if (session) {
      const s = isoToNyLocal(session.starts_at);
      const e = session.ends_at ? isoToNyLocal(session.ends_at) : null;
      setStartDate(s.date);
      setStartTime(s.time);
      setEndDate(e ? e.date : '');
      setEndTime(e ? e.time : '');
      setLocationText(session.location_text || '');
    } else {
      const today = getTodayNyDate();
      setStartDate(today);
      setStartTime('19:00');
      setEndDate('');
      setEndTime('');
      setLocationText('');
    }
    setErrorMessage(null);
  }, [open, session]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);

    if (!startDate) {
      setErrorMessage('Start date is required.');
      return;
    }
    if (!startTime) {
      setErrorMessage('Start time is required.');
      return;
    }

    try {
      const startsAt = nyLocalToIso(startDate, startTime);

      let endsAt: string | null = null;
      if (endTime) {
        const resolvedEndDate = endDate || startDate;
        endsAt = nyLocalToIso(resolvedEndDate, endTime);
        if (endsAt <= startsAt) {
          setErrorMessage('End time must be after start time.');
          return;
        }
      }

      if (isEditing && session) {
        await updateMutation.mutateAsync({
          organizationId,
          eventId: session.id,
          startsAt,
          endsAt,
          locationText: locationText.trim() || null,
        });
      } else {
        await addMutation.mutateAsync({
          organizationId,
          runId,
          sessionNumber,
          startsAt,
          endsAt,
          locationText: locationText.trim() || null,
        });
      }

      onSuccess?.();
      onClose();
    } catch (err) {
      setErrorMessage(getEventErrorMessage(err));
    }
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={isEditing ? `Change Session ${sessionNumber}` : `Schedule Session ${sessionNumber}`}
      size="md"
      footer={
        <div className="flex w-full items-center justify-end gap-3">
          <Button variant="outline" onClick={onClose} disabled={isSubmitting}>
            Cancel
          </Button>
          <Button
            type="submit"
            form="schedule-session-form"
            loading={isSubmitting}
            variant="primary"
          >
            {isEditing ? 'Save Changes' : 'Schedule Session'}
          </Button>
        </div>
      }
    >
      <form id="schedule-session-form" onSubmit={handleSubmit} className="space-y-4">
        {errorMessage && (
          <Alert variant="danger">
            {errorMessage}
          </Alert>
        )}

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <FormField label="Start date" required>
            <Input
              id={startDateId}
              type="date"
              value={startDate}
              onChange={(e) => {
                setStartDate(e.target.value);
                if (!endDate || endDate < e.target.value) {
                  setEndDate(e.target.value);
                }
              }}
              disabled={isSubmitting}
              required
            />
          </FormField>

          <FormField label="Start time" required>
            <Input
              id={startTimeId}
              type="time"
              value={startTime}
              onChange={(e) => setStartTime(e.target.value)}
              disabled={isSubmitting}
              required
            />
          </FormField>
        </div>

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <FormField label="End date (optional)">
            <Input
              id={endDateId}
              type="date"
              min={startDate}
              value={endDate}
              onChange={(e) => setEndDate(e.target.value)}
              disabled={isSubmitting}
            />
          </FormField>

          <FormField label="End time (optional)">
            <Input
              id={endTimeId}
              type="time"
              value={endTime}
              onChange={(e) => setEndTime(e.target.value)}
              disabled={isSubmitting}
            />
          </FormField>
        </div>

        <FormField label="Location (optional)">
          <Input
            id={locationId}
            value={locationText}
            onChange={(e) => setLocationText(e.target.value)}
            placeholder="e.g. St. Patrick Church Hall, Queens, NY"
            disabled={isSubmitting}
            maxLength={300}
          />
        </FormField>
      </form>
    </Modal>
  );
}
