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
import {
  EVENT_TYPE_LABELS,
  EVENT_MEETING_TYPE_LABELS,
  REPORT_PRIORITY_LABELS,
} from '../labels';
import {
  useCreateEvent,
  useEventAudienceOptions,
  useEventFormationTalks,
  useUpdateEvent,
} from '../queries';
import { getEventErrorMessage } from '../error-message';
import { getTodayNyDate, isoToNyLocal, nyLocalToIso } from '../../../lib/ny-time';
import type {
  EventDetail,
  EventSummary,
  EventType,
  EventMeetingType,
  EventReportPriority,
} from '../types';

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
  const [meetingType, setMeetingType] = useState<EventMeetingType>('in_person');
  const [virtualMeetingUrl, setVirtualMeetingUrl] = useState('');
  const [includeInQuarterlyReport, setIncludeInQuarterlyReport] = useState(false);
  const [reportPriority, setReportPriority] = useState<EventReportPriority>('routine');
  const [reportHighlight, setReportHighlight] = useState('');
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
  const virtualUrlId = useId();
  const includeReportId = useId();
  const reportPriorityId = useId();
  const reportHighlightId = useId();
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
      setMeetingType(event.meeting_type ?? 'in_person');
      setVirtualMeetingUrl(event.virtual_meeting_url || '');
      setIncludeInQuarterlyReport(event.include_in_quarterly_report ?? false);
      setReportPriority(event.report_priority ?? 'routine');
      setReportHighlight(event.report_highlight || '');
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
      setMeetingType('in_person');
      setVirtualMeetingUrl('');
      setIncludeInQuarterlyReport(false);
      setReportPriority('routine');
      setReportHighlight('');
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

    const trimmedVirtualUrl = meetingType === 'virtual' ? virtualMeetingUrl.trim() : null;
    if (meetingType === 'virtual' && trimmedVirtualUrl) {
      if (!/^https:\/\/[^\s/$.?#].[^\s]*$/i.test(trimmedVirtualUrl) || /^(javascript|data):/i.test(trimmedVirtualUrl)) {
        setErrorMessage('Virtual meeting URL must be a valid secure HTTPS web address.');
        return;
      }
    }

    const reportingPayload = {
      meetingType,
      virtualMeetingUrl: trimmedVirtualUrl || null,
      includeInQuarterlyReport,
      reportPriority: includeInQuarterlyReport ? reportPriority : ('routine' as EventReportPriority),
      reportHighlight: includeInQuarterlyReport && reportHighlight.trim() ? reportHighlight.trim() : null,
    };

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
          locationText: meetingType === 'in_person' ? (locationText.trim() || null) : null,
          description: description.trim() || null,
          audienceCode: audienceCode || undefined,
          formationTalkId: eventType === 'formation_talk' ? formationTalkId : null,
          ...reportingPayload,
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
          locationText: meetingType === 'in_person' ? (locationText.trim() || null) : null,
          description: description.trim() || null,
          audienceCode: audienceCode || undefined,
          formationTalkId: eventType === 'formation_talk' ? formationTalkId : null,
          ...reportingPayload,
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

        {/* Meeting Format & Location / Virtual URL */}
        <div className="space-y-4 rounded-card border border-line bg-surface-muted/30 p-3 sm:p-4">
          <FormField label="Meeting format" required>
            <div className="flex items-center gap-6 pt-1">
              <label className="flex cursor-pointer items-center gap-2 text-body font-medium text-ink">
                <input
                  type="radio"
                  name="meetingType"
                  value="in_person"
                  checked={meetingType === 'in_person'}
                  onChange={() => {
                    setMeetingType('in_person');
                    setVirtualMeetingUrl('');
                  }}
                  disabled={isSubmitting}
                  className="h-4 w-4 text-primary focus:ring-primary"
                />
                {EVENT_MEETING_TYPE_LABELS.in_person}
              </label>
              <label className="flex cursor-pointer items-center gap-2 text-body font-medium text-ink">
                <input
                  type="radio"
                  name="meetingType"
                  value="virtual"
                  checked={meetingType === 'virtual'}
                  onChange={() => setMeetingType('virtual')}
                  disabled={isSubmitting}
                  className="h-4 w-4 text-primary focus:ring-primary"
                />
                {EVENT_MEETING_TYPE_LABELS.virtual}
              </label>
            </div>
          </FormField>

          {meetingType === 'in_person' ? (
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
          ) : (
            <FormField
              label="Virtual Meeting URL"
              hint="Support links from Zoom, Google Meet, Microsoft Teams, Webex, etc."
            >
              <Input
                id={virtualUrlId}
                type="url"
                value={virtualMeetingUrl}
                onChange={(e) => setVirtualMeetingUrl(e.target.value)}
                placeholder="https://zoom.us/j/... or https://meet.google.com/..."
                disabled={isSubmitting}
                maxLength={1000}
              />
            </FormField>
          )}
        </div>

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

        {/* Reporting Details */}
        <div className="space-y-3 rounded-card border border-line bg-surface-muted/30 p-3 sm:p-4">
          <div className="flex items-center justify-between">
            <h4 className="text-body font-semibold text-ink">Reporting Details</h4>
            <span className="text-caption text-ink-muted">Quarterly National Report</span>
          </div>

          <label className="flex cursor-pointer items-center gap-2.5 text-body text-ink">
            <input
              id={includeReportId}
              type="checkbox"
              checked={includeInQuarterlyReport}
              onChange={(e) => setIncludeInQuarterlyReport(e.target.checked)}
              disabled={isSubmitting}
              className="h-4 w-4 rounded border-line text-primary focus:ring-primary"
            />
            <span className="font-medium">Include in Quarterly Report</span>
          </label>

          {includeInQuarterlyReport && (
            <div className="space-y-4 pt-2 border-t border-line">
              <FormField label="Report Priority">
                <Select
                  id={reportPriorityId}
                  value={reportPriority}
                  onChange={(e) => setReportPriority(e.target.value as EventReportPriority)}
                  disabled={isSubmitting}
                >
                  <option value="routine">{REPORT_PRIORITY_LABELS.routine}</option>
                  <option value="ministry_activity">{REPORT_PRIORITY_LABELS.ministry_activity}</option>
                  <option value="major_highlight">{REPORT_PRIORITY_LABELS.major_highlight}</option>
                </Select>
              </FormField>

              <FormField
                label="Event Highlight / Accomplishment"
                hint="Briefly describe the main outcome, accomplishment, or ministry highlight from this event."
              >
                <Textarea
                  id={reportHighlightId}
                  value={reportHighlight}
                  onChange={(e) => setReportHighlight(e.target.value)}
                  placeholder="e.g. Gathered 120 leaders across the area with strong spiritual engagement..."
                  disabled={isSubmitting}
                  maxLength={2000}
                  rows={2}
                />
              </FormField>
            </div>
          )}
        </div>
      </form>
    </Modal>
  );
}
