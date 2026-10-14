import { useState, useEffect, useId } from 'react';
import {
  Modal,
  Button,
  FormField,
  Input,
  Textarea,
  Alert,
} from '../../../components/ui';
import { useUpdateProgramParticipant } from '../queries';
import { useSearchMembers } from '../../members/queries';
import { getEventErrorMessage } from '../../events/error-message';
import { Search } from 'lucide-react';
import type { ProgramParticipant } from '../types';

interface EditParticipantModalProps {
  open: boolean;
  onClose: () => void;
  organizationId: string;
  participant: ProgramParticipant | null;
  onSuccess?: () => void;
}

export function EditParticipantModal({
  open,
  onClose,
  organizationId,
  participant,
  onSuccess,
}: EditParticipantModalProps) {
  const updateMutation = useUpdateProgramParticipant();
  const isSubmitting = updateMutation.isPending;

  const [firstName, setFirstName] = useState('');
  const [lastName, setLastName] = useState('');
  const [phone, setPhone] = useState('');
  const [email, setEmail] = useState('');
  const [invitedBySearchQuery, setInvitedBySearchQuery] = useState('');
  const [invitedByMember, setInvitedByMember] = useState<{ id: string; name: string } | null>(null);
  const [notes, setNotes] = useState('');
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const firstNameId = useId();
  const lastNameId = useId();
  const phoneId = useId();
  const emailId = useId();
  const notesId = useId();

  const { data: invitedByResults, isLoading: isInvitedSearching } = useSearchMembers(
    organizationId,
    {
      search: invitedBySearchQuery.trim().length >= 2 ? invitedBySearchQuery.trim() : undefined,
      recordStatus: 'active',
      pageSize: 10,
    }
  );

  useEffect(() => {
    if (!open || !participant) {
      setErrorMessage(null);
      return;
    }

    setFirstName(participant.first_name || '');
    setLastName(participant.last_name || '');
    setPhone(participant.phone || '');
    setEmail(participant.email || '');
    setInvitedByMember(
      participant.invited_by_member_id
        ? { id: participant.invited_by_member_id, name: participant.invited_by_name || 'Inviting member' }
        : null
    );
    setNotes(participant.notes || '');
    setErrorMessage(null);
  }, [open, participant]);

  if (!participant) return null;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);

    const fName = firstName.trim();
    const lName = lastName.trim();

    if (!participant.is_member && (!fName || !lName)) {
      setErrorMessage('First name and last name are required.');
      return;
    }

    try {
      await updateMutation.mutateAsync({
        organizationId,
        participantId: participant.participant_id,
        firstName: !participant.is_member ? fName : undefined,
        lastName: !participant.is_member ? lName : undefined,
        phone: !participant.is_member ? phone.trim() || undefined : undefined,
        email: !participant.is_member ? email.trim() || undefined : undefined,
        invitedByMemberId: invitedByMember?.id || undefined,
        notes: notes.trim() || undefined,
      });
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
      title={`Edit Participant: ${participant.name}`}
      size="md"
      footer={
        <div className="flex w-full items-center justify-end gap-3">
          <Button variant="outline" onClick={onClose} disabled={isSubmitting}>
            Cancel
          </Button>
          <Button
            type="submit"
            form="edit-participant-form"
            loading={isSubmitting}
            variant="primary"
          >
            Save Changes
          </Button>
        </div>
      }
    >
      <form id="edit-participant-form" onSubmit={handleSubmit} className="space-y-4">
        {errorMessage && (
          <Alert variant="danger">
            {errorMessage}
          </Alert>
        )}

        {/* Member indicator if this is an existing community member */}
        {participant.is_member && (
          <div className="rounded-control bg-surface-muted p-3 text-small text-ink-muted">
            This participant is an active community member ({participant.member_number || 'No member number'}).
            Name and contact details are managed in their member record.
          </div>
        )}

        {/* Non-member name and contact details */}
        {!participant.is_member && (
          <>
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <FormField label="First name" required>
                <Input
                  id={firstNameId}
                  value={firstName}
                  onChange={(e) => setFirstName(e.target.value)}
                  disabled={isSubmitting}
                  maxLength={100}
                  required
                />
              </FormField>

              <FormField label="Last name" required>
                <Input
                  id={lastNameId}
                  value={lastName}
                  onChange={(e) => setLastName(e.target.value)}
                  disabled={isSubmitting}
                  maxLength={100}
                  required
                />
              </FormField>
            </div>

            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <FormField label="Phone (optional)">
                <Input
                  id={phoneId}
                  type="tel"
                  value={phone}
                  onChange={(e) => setPhone(e.target.value)}
                  disabled={isSubmitting}
                  maxLength={40}
                />
              </FormField>

              <FormField label="Email (optional)">
                <Input
                  id={emailId}
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  disabled={isSubmitting}
                  maxLength={200}
                />
              </FormField>
            </div>
          </>
        )}

        {/* Invited by member (for anyone) */}
        <FormField label="Invited by member (optional)">
          {invitedByMember ? (
            <div className="flex items-center justify-between rounded-control border border-line bg-surface-muted p-2.5">
              <span className="text-body font-medium text-ink">{invitedByMember.name}</span>
              <Button
                size="sm"
                variant="ghost"
                onClick={() => setInvitedByMember(null)}
              >
                Remove
              </Button>
            </div>
          ) : (
            <div className="space-y-2">
              <div className="relative">
                <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-ink-muted" />
                <Input
                  value={invitedBySearchQuery}
                  onChange={(e) => setInvitedBySearchQuery(e.target.value)}
                  placeholder="Search inviting member name..."
                  className="pl-9"
                  disabled={isSubmitting}
                />
              </div>

              {invitedBySearchQuery.trim().length >= 2 && (
                <div className="max-h-40 overflow-y-auto divide-y divide-line rounded-control border border-line bg-surface">
                  {isInvitedSearching && (
                    <p className="p-2 text-small text-ink-muted">Searching...</p>
                  )}
                  {!isInvitedSearching && invitedByResults?.members.length === 0 && (
                    <p className="p-2 text-small text-ink-muted">No members found.</p>
                  )}
                  {!isInvitedSearching &&
                    invitedByResults?.members.map((m) => (
                      <button
                        key={m.id}
                        type="button"
                        onClick={() => {
                          setInvitedByMember({ id: m.id, name: m.display_name });
                          setInvitedBySearchQuery('');
                        }}
                        className="w-full flex items-center justify-between p-2 text-left transition-colors hover:bg-surface-muted"
                      >
                        <span className="text-small font-medium text-ink">{m.display_name}</span>
                        <span className="text-caption text-primary">Select</span>
                      </button>
                    ))}
                </div>
              )}
            </div>
          )}
        </FormField>

        <FormField label="Notes (optional)">
          <Textarea
            id={notesId}
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            disabled={isSubmitting}
            maxLength={1000}
            rows={2}
          />
        </FormField>
      </form>
    </Modal>
  );
}
