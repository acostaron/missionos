import { useState, useEffect, useId } from 'react';
import {
  Modal,
  Button,
  FormField,
  Input,
  Select,
  Textarea,
  Alert,
} from '../../../components/ui';
import { AUDIENCE_OPTIONS, EVENT_TYPE_LABELS } from '../labels';
import { useCreateEvent, useEventFormationTalks, useUpdateEvent } from '../queries';
import { getEventErrorMessage } from '../error-message';
import { getTodayNyDate, isoToNyLocal, nyLocalToIso } from '../../../lib/ny-time';
import type { EventDetail, EventSummary, EventType } from '../types';

interface EventFormModalProps {
  open: boolean;
  onClose: () => void;
  organizationId: string;
  /** Pass event for editing; omit for creating */
  event?: EventDetail | EventSummary | null;
  onSuccess?: (event: EventSummary) => void;
}

export function EventFormModal({
  open,
  onClose,
  organizationId,
  event,
  onSuccess,
}: EventFormModalProps) {
  const isEditing = !!event;
  const { data: formationTalks = [] } = useEventFormationTalks(organizationId, open);

  const [eventType, setEventType] = useState<EventType>('assembly');
  const [title, setTitle] = useState('');
  const [date, setDate] = useState('');
  const [startTime, setStartTime] = useState('');
  const [endTime, setEndTime] = useState('');
  const [locationText, setLocationText] = useState('');
  const [audienceCode, setAudienceCode] = useState('mfc_ny');
  const [formationTalkId, setFormationTalkId] = useState('');
  const [description, setDescription] = useState('');
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const createMutation = useCreateEvent();
  const updateMutation = useUpdateEvent();
  const isSubmitting = createMutation.isPending || updateMutation.isPending;

  const typeId = useId();
  const titleId = useId();
  const dateId = useId();
  const startTimeId = useId();
  const endTimeId = useId();
  const locationId = useId();
  const audienceId = useId();
  const talkId = useId();
  const descriptionId = useId();

  // Reset or initialize form fields when opened or event changes
  useEffect(() => {
    if (!open) {
      setErrorMessage(null);
      return;
    }

    if (event) {
      const startNy = isoToNyLocal(event.starts_at);
      const endNy = event.ends_at ? isoToNyLocal(event.ends_at) : null;

      setEventType(event.event_type);
      setTitle(event.title);
      setDate(startNy.date);
      setStartTime(startNy.time);
      setEndTime(endNy ? endNy.time : '');
      setLocationText(event.location_text || '');
      setAudienceCode(event.audience_code ?? 'mfc_ny');
      setFormationTalkId(event.formation_talk_id || '');
      setDescription(event.description || '');
      setErrorMessage(null);
    } else {
      setEventType('assembly');
      setTitle('Monthly Assembly');
      setDate(getTodayNyDate());
      setStartTime('19:00');
      setEndTime('');
      setLocationText('');
      setAudienceCode('mfc_ny');
      setFormationTalkId('');
      setDescription('');
      setErrorMessage(null);
    }
  }, [open, event]);

  const handleTypeChange = (newType: EventType) => {
    setEventType(newType);
    if (newType === 'assembly' && (!title.trim() || title === 'Teaching' || title === 'Course Talk')) {
      setTitle('Monthly Assembly');
    } else if (newType !== 'assembly' && title === 'Monthly Assembly') {
      setTitle('');
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);

    const trimmedTitle = title.trim();
    if (trimmedTitle.length < 3) {
      setErrorMessage('Event title must be at least 3 characters.');
      return;
    }

    if (!date) {
      setErrorMessage('Event date is required.');
      return;
    }

    if (!startTime) {
      setErrorMessage('Start time is required.');
      return;
    }

    if (endTime && endTime <= startTime) {
      setErrorMessage('End time must be after the start time.');
      return;
    }

    if (eventType === 'formation_talk' && !formationTalkId) {
      setErrorMessage('Please select a course talk.');
      return;
    }

    try {
      const startsAt = nyLocalToIso(date, startTime);
      const endsAt = endTime ? nyLocalToIso(date, endTime) : null;

      if (isEditing && event) {
        const result = await updateMutation.mutateAsync({
          organizationId,
          eventId: event.id,
          eventType,
          title: trimmedTitle,
          startsAt,
          endsAt,
          locationText: locationText.trim() || null,
          description: description.trim() || null,
          audienceCode: audienceCode || undefined,
          formationTalkId: eventType === 'formation_talk' ? formationTalkId : null,
        });
        onSuccess?.(result.event);
        onClose();
      } else {
        const result = await createMutation.mutateAsync({
          organizationId,
          eventType,
          title: trimmedTitle,
          startsAt,
          endsAt,
          locationText: locationText.trim() || null,
          description: description.trim() || null,
          audienceCode: audienceCode || undefined,
          formationTalkId: eventType === 'formation_talk' ? formationTalkId : null,
        });
        onSuccess?.(result.event);
        onClose();
      }
    } catch (err) {
      setErrorMessage(getEventErrorMessage(err));
    }
  };

  // Group formation talks by program
  const talksByProgram: Record<string, typeof formationTalks> = {};
  for (const t of formationTalks) {
    if (!talksByProgram[t.program_name]) {
      talksByProgram[t.program_name] = [];
    }
    talksByProgram[t.program_name].push(t);
  }

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={isEditing ? 'Edit Event' : 'New Event'}
      size="md"
      footer={
        <div className="flex w-full items-center justify-end gap-3">
          <Button variant="outline" onClick={onClose} disabled={isSubmitting}>
            Cancel
          </Button>
          <Button
            type="submit"
            form="event-form"
            loading={isSubmitting}
            variant="primary"
          >
            {isEditing ? 'Save Changes' : 'Create Event'}
          </Button>
        </div>
      }
    >
      <form id="event-form" onSubmit={handleSubmit} className="space-y-4">
        {errorMessage && (
          <Alert variant="danger">
            {errorMessage}
          </Alert>
        )}

        <FormField label="Event type" required>
          <Select
            id={typeId}
            value={eventType}
            onChange={(e) => handleTypeChange(e.target.value as EventType)}
            disabled={isSubmitting}
          >
            {(Object.keys(EVENT_TYPE_LABELS) as EventType[]).map((type) => (
              <option key={type} value={type}>
                {EVENT_TYPE_LABELS[type]}
              </option>
            ))}
          </Select>
        </FormField>

        {eventType === 'formation_talk' && (
          <FormField label="Course talk" required>
            <Select
              id={talkId}
              value={formationTalkId}
              onChange={(e) => setFormationTalkId(e.target.value)}
              disabled={isSubmitting}
            >
              <option value="">Select a course talk...</option>
              {Object.entries(talksByProgram).map(([progName, talks]) => (
                <optgroup key={progName} label={progName}>
                  {talks.map((t) => (
                    <option key={t.talk_id} value={t.talk_id}>
                      #{t.sequence_order} {t.talk_title}
                    </option>
                  ))}
                </optgroup>
              ))}
            </Select>
          </FormField>
        )}

        <FormField label="Title" required>
          <Input
            id={titleId}
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="e.g. Monthly Assembly"
            disabled={isSubmitting}
            maxLength={200}
            required
          />
        </FormField>

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <FormField label="Date" required>
            <Input
              id={dateId}
              type="date"
              value={date}
              onChange={(e) => setDate(e.target.value)}
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

          <FormField label="End time">
            <Input
              id={endTimeId}
              type="time"
              value={endTime}
              onChange={(e) => setEndTime(e.target.value)}
              disabled={isSubmitting}
            />
          </FormField>
        </div>

        <FormField label="Location">
          <Input
            id={locationId}
            value={locationText}
            onChange={(e) => setLocationText(e.target.value)}
            placeholder="e.g. St. Patrick Church Hall, Queens, NY"
            disabled={isSubmitting}
            maxLength={300}
          />
        </FormField>

        <FormField label="Audience">
          <Select
            id={audienceId}
            value={audienceCode}
            onChange={(e) => setAudienceCode(e.target.value)}
            disabled={isSubmitting}
          >
            {AUDIENCE_OPTIONS.map((opt) => (
              <option key={opt.code} value={opt.code}>
                {opt.label}
              </option>
            ))}
          </Select>
        </FormField>

        <FormField label="Description (optional)">
          <Textarea
            id={descriptionId}
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="Details, attire, agenda, parking notes..."
            disabled={isSubmitting}
            maxLength={2000}
            rows={3}
          />
        </FormField>
      </form>
    </Modal>
  );
}
