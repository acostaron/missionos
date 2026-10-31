import { useEffect, useState } from 'react';
import { Alert, Button, FormField, Input, Modal, Select, Textarea } from '../../../components/ui';
import { getEventErrorMessage } from '../../events/error-message';
import { useActivityServiceRoles, useSaveActivityServiceAssignment, useSaveActivitySpeaker } from '../queries';
import { MemberPicker } from './MemberPicker';
import {
  SPEAKER_ROLES,
  SPEAKER_ROLE_LABELS,
  type ActivityMemberOption,
  type ActivityServiceAssignment,
  type ActivitySpeaker,
  type ActivityTarget,
  type SpeakerRole,
} from '../types';

export interface SessionOption {
  eventId: string;
  label: string;
}

interface AssignmentModalProps {
  open: boolean;
  onClose: () => void;
  organizationId: string;
  kind: 'speaker' | 'service';
  /** Default target (the event, or the program). */
  target: ActivityTarget;
  /** Program mode: sessions the entry may be attached to. */
  sessionOptions?: SessionOption[];
  editingSpeaker?: ActivitySpeaker | null;
  editingService?: ActivityServiceAssignment | null;
}

const WHOLE = '__whole__';

export function AssignmentModal({
  open,
  onClose,
  organizationId,
  kind,
  target,
  sessionOptions,
  editingSpeaker,
  editingService,
}: AssignmentModalProps) {
  const editing = kind === 'speaker' ? editingSpeaker : editingService;
  const [personType, setPersonType] = useState<'member' | 'external'>('member');
  const [member, setMember] = useState<ActivityMemberOption | null>(null);
  const [externalName, setExternalName] = useState('');
  const [externalTitle, setExternalTitle] = useState('');
  const [externalOrg, setExternalOrg] = useState('');
  const [speakerRole, setSpeakerRole] = useState<SpeakerRole>('speaker');
  const [topic, setTopic] = useState('');
  const [sessionLabel, setSessionLabel] = useState('');
  const [roleCode, setRoleCode] = useState('');
  const [roleLabel, setRoleLabel] = useState('');
  const [teamGroup, setTeamGroup] = useState('');
  const [notes, setNotes] = useState('');
  const [sessionChoice, setSessionChoice] = useState(WHOLE);
  const [error, setError] = useState<string | null>(null);

  const { data: roles } = useActivityServiceRoles(organizationId, open && kind === 'service');
  const saveSpeaker = useSaveActivitySpeaker();
  const saveService = useSaveActivityServiceAssignment();
  const pending = saveSpeaker.isPending || saveService.isPending;
  const isProgramMode = !!target.programRunId && !!sessionOptions;

  useEffect(() => {
    if (!open) return;
    setError(null);
    const e = editing;
    setPersonType(e ? e.person_type : 'member');
    setMember(
      e && e.member_id ? { member_id: e.member_id, display_name: e.display_name, member_number: e.member_number } : null
    );
    setExternalName(e?.external_name ?? '');
    setNotes(e?.notes ?? '');
    setSessionChoice(e?.event_id && isProgramMode ? e.event_id : WHOLE);
    if (kind === 'speaker') {
      const s = editingSpeaker;
      setExternalTitle(s?.external_title ?? '');
      setExternalOrg(s?.external_organization ?? '');
      setSpeakerRole(s?.speaker_role ?? 'speaker');
      setTopic(s?.topic_title ?? '');
      setSessionLabel(s?.session_label ?? '');
    } else {
      const a = editingService;
      setRoleCode(a?.role_code ?? '');
      setRoleLabel(a?.custom_role_label ?? '');
      setTeamGroup(a?.team_group ?? '');
    }
  }, [open, editing, editingSpeaker, editingService, kind, isProgramMode]);

  const resolvedTarget: ActivityTarget = isProgramMode
    ? sessionChoice === WHOLE
      ? { programRunId: target.programRunId }
      : { eventId: sessionChoice }
    : target;

  const handleSave = async () => {
    setError(null);
    if (personType === 'member' && !member) {
      setError('Choose a member.');
      return;
    }
    if (personType === 'external' && externalName.trim().length < 2) {
      setError('Enter a name.');
      return;
    }
    const identity =
      personType === 'member'
        ? { memberId: member!.member_id, externalName: null }
        : { memberId: null, externalName: externalName.trim() };
    try {
      if (kind === 'speaker') {
        await saveSpeaker.mutateAsync({
          organizationId,
          speakerId: editingSpeaker?.id ?? null,
          ...resolvedTarget,
          ...identity,
          externalTitle: personType === 'external' ? externalTitle : null,
          externalOrganization: personType === 'external' ? externalOrg : null,
          speakerRole,
          topicTitle: topic,
          sessionLabel,
          notes,
        });
      } else {
        if (!roleCode) {
          setError('Choose a service role.');
          return;
        }
        await saveService.mutateAsync({
          organizationId,
          assignmentId: editingService?.id ?? null,
          ...resolvedTarget,
          ...identity,
          roleCode,
          roleLabel,
          teamGroup,
          notes,
        });
      }
      onClose();
    } catch (err) {
      setError(getEventErrorMessage(err));
    }
  };

  const title = `${editing ? 'Edit' : 'Add'} ${kind === 'speaker' ? 'speaker' : 'service-team member'}`;

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={title}
      size="md"
      footer={
        <div className="flex w-full items-center justify-end gap-2">
          <Button variant="outline" onClick={onClose} disabled={pending}>
            Cancel
          </Button>
          <Button variant="primary" onClick={handleSave} loading={pending}>
            Save
          </Button>
        </div>
      }
    >
      <div className="space-y-4">
        {error && <Alert variant="danger">{error}</Alert>}

        <div className="inline-flex rounded-control border border-line p-0.5" role="tablist">
          {(['member', 'external'] as const).map((t) => (
            <button
              key={t}
              type="button"
              role="tab"
              aria-selected={personType === t}
              className={`rounded-control px-3 py-1.5 text-small font-medium transition-colors ${
                personType === t ? 'bg-primary text-white' : 'text-ink-secondary hover:bg-surface-muted'
              }`}
              onClick={() => setPersonType(t)}
            >
              {t === 'member' ? 'MFC member' : kind === 'speaker' ? 'External speaker' : 'Non-member volunteer'}
            </button>
          ))}
        </div>

        {personType === 'member' ? (
          <MemberPicker organizationId={organizationId} target={resolvedTarget} selected={member} onSelect={setMember} />
        ) : (
          <div className="space-y-3">
            {kind === 'speaker' && (
              <FormField label="Title (optional)">
                <Input
                  value={externalTitle}
                  onChange={(e) => setExternalTitle(e.target.value)}
                  placeholder="Fr., Rev., Dr., Bro., Sis., Bishop…"
                  maxLength={40}
                />
              </FormField>
            )}
            <FormField label="Name">
              <Input value={externalName} onChange={(e) => setExternalName(e.target.value)} maxLength={150} />
            </FormField>
            {kind === 'speaker' && (
              <FormField label="Organization / parish (optional)">
                <Input
                  value={externalOrg}
                  onChange={(e) => setExternalOrg(e.target.value)}
                  placeholder="e.g. St. Mary Star of the Sea Parish"
                  maxLength={200}
                />
              </FormField>
            )}
          </div>
        )}

        {isProgramMode && (
          <FormField label="Session">
            <Select value={sessionChoice} onChange={(e) => setSessionChoice(e.target.value)}>
              <option value={WHOLE}>Whole program</option>
              {sessionOptions!.map((s) => (
                <option key={s.eventId} value={s.eventId}>
                  {s.label}
                </option>
              ))}
            </Select>
          </FormField>
        )}

        {kind === 'speaker' ? (
          <>
            <FormField label="Role">
              <Select value={speakerRole} onChange={(e) => setSpeakerRole(e.target.value as SpeakerRole)}>
                {SPEAKER_ROLES.map((r) => (
                  <option key={r} value={r}>
                    {SPEAKER_ROLE_LABELS[r]}
                  </option>
                ))}
              </Select>
            </FormField>
            <FormField label="Topic / talk (optional)">
              <Input value={topic} onChange={(e) => setTopic(e.target.value)} maxLength={200} />
            </FormField>
            <FormField label="Session label (optional)">
              <Input
                value={sessionLabel}
                onChange={(e) => setSessionLabel(e.target.value)}
                placeholder="e.g. Talk 3, Morning session"
                maxLength={100}
              />
            </FormField>
          </>
        ) : (
          <>
            <FormField label="Service role">
              <Select value={roleCode} onChange={(e) => setRoleCode(e.target.value)}>
                <option value="">Choose a role…</option>
                {(roles ?? []).map((r) => (
                  <option key={r.code} value={r.code}>
                    {r.label}
                  </option>
                ))}
              </Select>
            </FormField>
            {roleCode === 'other' && (
              <FormField label="Role name">
                <Input value={roleLabel} onChange={(e) => setRoleLabel(e.target.value)} maxLength={80} />
              </FormField>
            )}
            <FormField label="Team / group (optional)">
              <Input value={teamGroup} onChange={(e) => setTeamGroup(e.target.value)} maxLength={80} />
            </FormField>
          </>
        )}

        <FormField label="Internal notes (visible to organizers only)">
          <Textarea value={notes} onChange={(e) => setNotes(e.target.value)} rows={2} maxLength={1000} />
        </FormField>
      </div>
    </Modal>
  );
}
