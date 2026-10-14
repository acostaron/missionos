import { useState, useId } from 'react';
import {
  Modal,
  Button,
  FormField,
  Input,
  Textarea,
  Alert,
} from '../../../components/ui';
import { useAddProgramParticipant } from '../queries';
import { useSearchMembers } from '../../members/queries';
import { getEventErrorMessage } from '../../events/error-message';
import { Search, UserCheck } from 'lucide-react';

interface AddParticipantModalProps {
  open: boolean;
  onClose: () => void;
  organizationId: string;
  runId: string;
  onSuccess?: () => void;
}

export function AddParticipantModal({
  open,
  onClose,
  organizationId,
  runId,
  onSuccess,
}: AddParticipantModalProps) {
  const [activeTab, setActiveTab] = useState<'member' | 'new_person'>('member');
  const addMutation = useAddProgramParticipant();
  const isSubmitting = addMutation.isPending;

  // Member search state
  const [memberSearchQuery, setMemberSearchQuery] = useState('');
  const [selectedMember, setSelectedMember] = useState<{ id: string; name: string; number?: string | null } | null>(null);

  // New person state
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

  // Queries for member search
  const { data: memberSearchResults, isLoading: isMemberSearching } = useSearchMembers(
    organizationId,
    {
      search: memberSearchQuery.trim().length >= 2 ? memberSearchQuery.trim() : undefined,
      recordStatus: 'active',
      pageSize: 10,
    }
  );

  const { data: invitedByResults, isLoading: isInvitedSearching } = useSearchMembers(
    organizationId,
    {
      search: invitedBySearchQuery.trim().length >= 2 ? invitedBySearchQuery.trim() : undefined,
      recordStatus: 'active',
      pageSize: 10,
    }
  );

  const handleReset = () => {
    setActiveTab('member');
    setMemberSearchQuery('');
    setSelectedMember(null);
    setFirstName('');
    setLastName('');
    setPhone('');
    setEmail('');
    setInvitedBySearchQuery('');
    setInvitedByMember(null);
    setNotes('');
    setErrorMessage(null);
  };

  const handleClose = () => {
    handleReset();
    onClose();
  };

  const handleSubmitMember = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);

    if (!selectedMember) {
      setErrorMessage('Please search for and select a member.');
      return;
    }

    try {
      await addMutation.mutateAsync({
        organizationId,
        runId,
        memberId: selectedMember.id,
      });
      onSuccess?.();
      handleClose();
    } catch (err) {
      setErrorMessage(getEventErrorMessage(err));
    }
  };

  const handleSubmitNewPerson = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);

    const fName = firstName.trim();
    const lName = lastName.trim();

    if (!fName || !lName) {
      setErrorMessage('First name and last name are required for a new participant.');
      return;
    }

    try {
      await addMutation.mutateAsync({
        organizationId,
        runId,
        firstName: fName,
        lastName: lName,
        phone: phone.trim() || undefined,
        email: email.trim() || undefined,
        invitedByMemberId: invitedByMember?.id || undefined,
        notes: notes.trim() || undefined,
      });
      onSuccess?.();
      handleClose();
    } catch (err) {
      setErrorMessage(getEventErrorMessage(err));
    }
  };

  return (
    <Modal
      open={open}
      onClose={handleClose}
      title="Add Participant"
      size="md"
      footer={
        <div className="flex w-full items-center justify-end gap-3">
          <Button variant="outline" onClick={handleClose} disabled={isSubmitting}>
            Cancel
          </Button>
          {activeTab === 'member' ? (
            <Button
              type="submit"
              form="add-member-participant-form"
              loading={isSubmitting}
              variant="primary"
              disabled={!selectedMember}
            >
              Add Member
            </Button>
          ) : (
            <Button
              type="submit"
              form="add-new-person-form"
              loading={isSubmitting}
              variant="primary"
            >
              Add Participant
            </Button>
          )}
        </div>
      }
    >
      <div className="space-y-4">
        {errorMessage && (
          <Alert variant="danger">
            {errorMessage}
          </Alert>
        )}

        {/* Tab switch */}
        <div className="flex rounded-control border border-line bg-surface p-0.5">
          <button
            type="button"
            onClick={() => {
              setActiveTab('member');
              setErrorMessage(null);
            }}
            className={`flex-1 rounded-[calc(var(--radius-control)-2px)] py-1.5 text-small font-medium transition-colors ${
              activeTab === 'member'
                ? 'bg-primary text-white shadow-xs'
                : 'text-ink-secondary hover:text-ink'
            }`}
          >
            Member
          </button>
          <button
            type="button"
            onClick={() => {
              setActiveTab('new_person');
              setErrorMessage(null);
            }}
            className={`flex-1 rounded-[calc(var(--radius-control)-2px)] py-1.5 text-small font-medium transition-colors ${
              activeTab === 'new_person'
                ? 'bg-primary text-white shadow-xs'
                : 'text-ink-secondary hover:text-ink'
            }`}
          >
            New person
          </button>
        </div>

        {/* TAB 1: Member Search */}
        {activeTab === 'member' && (
          <form id="add-member-participant-form" onSubmit={handleSubmitMember} className="space-y-4">
            <FormField label="Search active members">
              <div className="relative">
                <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-ink-muted" />
                <Input
                  value={memberSearchQuery}
                  onChange={(e) => setMemberSearchQuery(e.target.value)}
                  placeholder="Type member name or member number..."
                  className="pl-9"
                  disabled={isSubmitting}
                />
              </div>
            </FormField>

            {/* Selected Member pill */}
            {selectedMember && (
              <div className="flex items-center justify-between rounded-control border border-primary/30 bg-primary/5 p-3">
                <div className="flex items-center gap-2">
                  <UserCheck className="h-4 w-4 text-primary" />
                  <div>
                    <p className="text-body font-semibold text-ink">{selectedMember.name}</p>
                    {selectedMember.number && (
                      <p className="text-caption text-ink-muted">{selectedMember.number}</p>
                    )}
                  </div>
                </div>
                <Button
                  size="sm"
                  variant="ghost"
                  onClick={() => setSelectedMember(null)}
                >
                  Change
                </Button>
              </div>
            )}

            {/* Search Results list */}
            {!selectedMember && memberSearchQuery.trim().length >= 2 && (
              <div className="max-h-56 overflow-y-auto divide-y divide-line rounded-control border border-line bg-surface">
                {isMemberSearching && (
                  <p className="p-3 text-small text-ink-muted">Searching members...</p>
                )}
                {!isMemberSearching && memberSearchResults?.members.length === 0 && (
                  <p className="p-3 text-small text-ink-muted">No matching active members found.</p>
                )}
                {!isMemberSearching &&
                  memberSearchResults?.members.map((m) => (
                    <button
                      key={m.id}
                      type="button"
                      onClick={() =>
                        setSelectedMember({
                          id: m.id,
                          name: m.display_name,
                          number: m.member_number,
                        })
                      }
                      className="w-full flex items-center justify-between p-3 text-left transition-colors hover:bg-surface-muted"
                    >
                      <div>
                        <p className="text-body font-medium text-ink">{m.display_name}</p>
                        <p className="text-caption text-ink-muted">
                          {m.member_number || 'No member number'}
                        </p>
                      </div>
                      <span className="text-small font-medium text-primary">Select</span>
                    </button>
                  ))}
              </div>
            )}
          </form>
        )}

        {/* TAB 2: New Person Form */}
        {activeTab === 'new_person' && (
          <form id="add-new-person-form" onSubmit={handleSubmitNewPerson} className="space-y-4">
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <FormField label="First name" required>
                <Input
                  id={firstNameId}
                  value={firstName}
                  onChange={(e) => setFirstName(e.target.value)}
                  placeholder="First name..."
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
                  placeholder="Last name..."
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
                  placeholder="e.g. 555-0123"
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
                  placeholder="e.g. participant@example.com"
                  disabled={isSubmitting}
                  maxLength={200}
                />
              </FormField>
            </div>

            {/* Invited by member (optional search) */}
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
                placeholder="Dietary requirements, sponsor notes, follow-up..."
                disabled={isSubmitting}
                maxLength={1000}
                rows={2}
              />
            </FormField>
          </form>
        )}
      </div>
    </Modal>
  );
}
