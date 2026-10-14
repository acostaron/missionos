import { useState, useEffect, useId, useMemo } from 'react';
import {
  Modal,
  Button,
  FormField,
  Input,
  Select,
  Textarea,
  Alert,
} from '../../../components/ui';
import { EVENT_TYPE_LABELS } from '../labels';
import {
  useCreateEvent,
  useEventAudienceOptions,
  useEventFormationTalks,
  useUpdateEvent,
} from '../queries';
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
  const { data: audienceData } = useEventAudienceOptions(organizationId, open);

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

  // Categorize audience options
  const areaOptions = useMemo(
    () => audienceData?.options.filter((o) => o.type === 'area_state') ?? [],
    [audienceData?.options]
  );
  const chapterOptions = useMemo(
    () => audienceData?.options.filter((o) => o.type === 'chapter') ?? [],
    [audienceData?.options]
  );
  const sectionOptions = useMemo(
    () => audienceData?.options.filter((o) => o.type === 'section') ?? [],
    [audienceData?.options]
  );
  const allowAllMembers = audienceData?.allow_all_members ?? false;

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
      setAudienceCode(event.audience_code ?? '');
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

  // Ensure valid audience selection when audience data arrives in create mode
  useEffect(() => {
    if (!open || isEditing || !audienceData) return;
    if (eventType === 'assembly') {
      const hasMfcNy = areaOptions.some((a) => a.code === 'mfc_ny');
      if (hasMfcNy) {
        if (!audienceCode || !areaOptions.some((a) => a.code === audienceCode)) {
          setAudienceCode('mfc_ny');
        }
      } else if (areaOptions.length > 0) {
        if (!areaOptions.some((a) => a.code === audienceCode)) {
          setAudienceCode(areaOptions[0].code);
        }
      }
    }
  }, [open, isEditing, audienceData, eventType, areaOptions, audienceCode]);

  const handleTypeChange = (newType: EventType) => {
    setEventType(newType);

    if (newType === 'chapter_assembly') {
      // Pick first chapter option if current is not a chapter
      const currentIsChapter = chapterOptions.some((c) => c.code === audienceCode);
      if (!currentIsChapter && chapterOptions.length > 0) {
        setAudienceCode(chapterOptions[0].code);
      }
      if (!title.trim() || title === 'Monthly Assembly' || title.endsWith(' Assembly')) {
        setTitle('Chapter Assembly');
      }
    } else if (newType === 'section_assembly') {
      // Pick first section option if current is not a section
      const currentIsSection = sectionOptions.some((s) => s.code === audienceCode);
      const chosenSection = currentIsSection
        ? sectionOptions.find((s) => s.code === audienceCode)
        : sectionOptions[0];

      if (!currentIsSection && chosenSection) {
        setAudienceCode(chosenSection.code);
      }
      const sectionName = chosenSection ? chosenSection.name : '';
      if (!title.trim() || title === 'Monthly Assembly' || title === 'Chapter Assembly' || title.endsWith(' Assembly')) {
        setTitle(sectionName ? `${sectionName} Assembly` : 'Section Assembly');
      }
    } else if (newType === 'assembly') {
      const hasMfcNy = areaOptions.some((a) => a.code === 'mfc_ny');
      if (hasMfcNy) {
        setAudienceCode('mfc_ny');
      } else if (areaOptions.length > 0) {
        setAudienceCode(areaOptions[0].code);
      }
      if (!title.trim() || title === 'Chapter Assembly' || title.endsWith(' Assembly')) {
        setTitle('Monthly Assembly');
      }
    } else if (newType === 'formation_talk') {
      setTitle('');
    }
  };

  const handleSectionAudienceChange = (code: string) => {
    setAudienceCode(code);
    if (eventType === 'section_assembly') {
      const sec = sectionOptions.find((s) => s.code === code);
      if (sec && (!title.trim() || title === 'Section Assembly' || title.endsWith(' Assembly'))) {
        setTitle(`${sec.name} Assembly`);
      }
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);

    // Pastoral formation talk uses talk's title
    let resolvedTitle = title.trim();
    if (eventType === 'formation_talk') {
      resolvedTitle = '';
      if (!formationTalkId) {
        setErrorMessage('Please select a pastoral formation talk.');
        return;
      }
    } else {
      if (resolvedTitle.length < 3) {
        setErrorMessage('Event title must be at least 3 characters.');
        return;
      }
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

    if (eventType === 'chapter_assembly' && !audienceCode) {
      setErrorMessage('Please select a chapter audience.');
      return;
    }

    if (eventType === 'section_assembly' && !audienceCode) {
      setErrorMessage('Please select a section audience.');
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
          title: resolvedTitle,
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
          title: resolvedTitle,
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

  // Render Audience select or message based on event type
  const renderAudienceInput = () => {
    if (eventType === 'chapter_assembly') {
      if (chapterOptions.length === 0) {
        return (
          <p className="rounded-control border border-line bg-surface-muted p-2.5 text-small text-ink-muted">
            No chapter audience options are available for your role.
          </p>
        );
      }
      return (
        <Select
          id={audienceId}
          value={audienceCode}
          onChange={(e) => setAudienceCode(e.target.value)}
          disabled={isSubmitting}
          required
        >
          {chapterOptions.map((opt) => (
            <option key={opt.code} value={opt.code}>
              {opt.sub_area_name ? `${opt.sub_area_name} · ` : ''}{opt.name}
            </option>
          ))}
        </Select>
      );
    }

    if (eventType === 'section_assembly') {
      if (sectionOptions.length === 0) {
        return (
          <p className="rounded-control border border-line bg-surface-muted p-2.5 text-small text-ink-muted">
            No section audience options are available for your role.
          </p>
        );
      }
      return (
        <Select
          id={audienceId}
          value={audienceCode}
          onChange={(e) => handleSectionAudienceChange(e.target.value)}
          disabled={isSubmitting}
          required
        >
          {sectionOptions.map((opt) => (
            <option key={opt.code} value={opt.code}>
              {opt.sub_area_name ? `${opt.sub_area_name} · ` : ''}{opt.name}
            </option>
          ))}
        </Select>
      );
    }

    if (eventType === 'assembly') {
      return (
        <Select
          id={audienceId}
          value={audienceCode}
          onChange={(e) => setAudienceCode(e.target.value)}
          disabled={isSubmitting}
        >
          {areaOptions.map((opt) => (
            <option key={opt.code} value={opt.code}>
              {opt.code === 'mfc_ny' ? 'MFC New York (FMC welcome as guests)' : opt.name}
            </option>
          ))}
        </Select>
      );
    }

    // Generic types: teaching, formation_talk, other
    return (
      <Select
        id={audienceId}
        value={audienceCode}
        onChange={(e) => setAudienceCode(e.target.value)}
        disabled={isSubmitting}
      >
        {allowAllMembers && <option value="">All members</option>}

        {areaOptions.length > 0 && (
          <optgroup label="Area">
            {areaOptions.map((opt) => (
              <option key={opt.code} value={opt.code}>
                {opt.code === 'mfc_ny' ? 'MFC New York (FMC welcome as guests)' : opt.name}
              </option>
            ))}
          </optgroup>
        )}

        {chapterOptions.length > 0 && (
          <optgroup label="Chapters">
            {chapterOptions.map((opt) => (
              <option key={opt.code} value={opt.code}>
                {opt.sub_area_name ? `${opt.sub_area_name} · ` : ''}{opt.name}
              </option>
            ))}
          </optgroup>
        )}

        {sectionOptions.length > 0 && (
          <optgroup label="Sections">
            {sectionOptions.map((opt) => (
              <option key={opt.code} value={opt.code}>
                {opt.sub_area_name ? `${opt.sub_area_name} · ` : ''}{opt.name}
              </option>
            ))}
          </optgroup>
        )}
      </Select>
    );
  };

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
          <FormField label="Pastoral Formation Talk" required>
            <Select
              id={talkId}
              value={formationTalkId}
              onChange={(e) => setFormationTalkId(e.target.value)}
              disabled={isSubmitting}
              required
            >
              <option value="">Select a talk...</option>
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

        {/* Title is hidden for Pastoral Formation Talk */}
        {eventType !== 'formation_talk' && (
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
        )}

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

        <FormField
          label="Audience"
          required={eventType === 'chapter_assembly' || eventType === 'section_assembly'}
        >
          {renderAudienceInput()}
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
