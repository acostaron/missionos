// Schedule or edit a household meeting from the household card (Pass 9.9, written by Claude 2026-10-16).
import { useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { addDaysToDateStr, getTodayNyDate, isoToNyLocal, nyLocalToIso } from '../../lib/ny-time';
import { normalizeError } from '../../lib/supabase/errors';
import { Alert, Button, Input, Modal, Select } from '../../components/ui';
import {
  LOCATION_TYPES,
  invalidateHouseholdCards,
  scheduleMeeting,
  updateMeeting,
  useHouseholdRoster,
  type CardMeeting,
} from './household-card-api';

export function HouseholdMeetingFormModal({
  organizationId,
  householdId,
  householdName,
  meeting,
  onClose,
}: {
  organizationId: string;
  householdId: string;
  householdName: string;
  /** null = schedule a new meeting */
  meeting: CardMeeting | null;
  onClose: () => void;
}) {
  const qc = useQueryClient();
  const today = getTodayNyDate();
  const { data: roster = [], isLoading: isRosterLoading } = useHouseholdRoster(organizationId, householdId, true);

  const start = meeting?.scheduled_start_at ? isoToNyLocal(meeting.scheduled_start_at) : null;
  const [date, setDate] = useState(meeting?.meeting_date ?? today);
  const [time, setTime] = useState(start?.time ?? '');
  const [locationType, setLocationType] = useState(meeting?.location_type ?? '');
  const [locationText, setLocationText] = useState(meeting?.location_text ?? '');
  const [hostId, setHostId] = useState(meeting?.host_member_id ?? '');
  const [isSaving, setIsSaving] = useState(false);
  const [errorText, setErrorText] = useState<string | null>(null);

  const minDate = addDaysToDateStr(today, -30);
  const maxDate = addDaysToDateStr(today, 90);

  const save = async () => {
    if (!date) return;
    try {
      setIsSaving(true);
      setErrorText(null);
      const fields = {
        meetingDate: date,
        scheduledStartAt: time ? nyLocalToIso(date, time) : null,
        locationType: locationType || null,
        locationText: locationText.trim() || null,
        hostMemberId: hostId || null,
      };
      if (meeting) {
        await updateMeeting(organizationId, meeting.household_meeting_id, fields);
      } else {
        await scheduleMeeting(organizationId, householdId, fields);
      }
      await invalidateHouseholdCards(qc);
      onClose();
    } catch (e) {
      setErrorText(normalizeError(e).message);
    } finally {
      setIsSaving(false);
    }
  };

  return (
    <Modal
      open
      onClose={onClose}
      closeOnBackdrop={false}
      title={meeting ? 'Edit meeting' : 'Schedule a meeting'}
      description={householdName}
      footer={
        <div className="flex w-full justify-end gap-2">
          <Button variant="ghost" onClick={onClose} disabled={isSaving}>
            Cancel
          </Button>
          <Button onClick={save} disabled={!date || isSaving} loading={isSaving}>
            Save
          </Button>
        </div>
      }
    >
      <div className="space-y-4">
        {errorText && (
          <Alert variant="danger" title="Could not save">
            {errorText}
          </Alert>
        )}
        <div className="grid grid-cols-2 gap-3">
          <label className="block">
            <span className="mb-1 block text-xs font-medium text-ink-secondary">Date</span>
            <Input type="date" value={date} min={minDate} max={maxDate} onChange={(e) => setDate(e.target.value)} />
          </label>
          <label className="block">
            <span className="mb-1 block text-xs font-medium text-ink-secondary">Start time (optional)</span>
            <Input type="time" value={time} onChange={(e) => setTime(e.target.value)} />
          </label>
        </div>
        <label className="block">
          <span className="mb-1 block text-xs font-medium text-ink-secondary">Format</span>
          <Select value={locationType} onChange={(e) => setLocationType(e.target.value)}>
            <option value="">— Not specified —</option>
            {Object.entries(LOCATION_TYPES).map(([value, label]) => (
              <option key={value} value={value}>
                {label}
              </option>
            ))}
          </Select>
        </label>
        <label className="block">
          <span className="mb-1 block text-xs font-medium text-ink-secondary">Location or meeting link (optional)</span>
          <Input value={locationText} maxLength={200} onChange={(e) => setLocationText(e.target.value)} />
        </label>
        <label className="block">
          <span className="mb-1 block text-xs font-medium text-ink-secondary">Host (optional)</span>
          <Select value={hostId} onChange={(e) => setHostId(e.target.value)} disabled={isRosterLoading}>
            <option value="">{isRosterLoading ? 'Loading members…' : '— No host —'}</option>
            {roster.map((m) => (
              <option key={m.member_id} value={m.member_id}>
                {m.display_name}
              </option>
            ))}
          </Select>
        </label>
        {meeting && meeting.topics.some((t) => t.assignment_status === 'planned') && (
          <p className="text-xs text-ink-muted">The planned topic moves with the meeting.</p>
        )}
      </div>
    </Modal>
  );
}
