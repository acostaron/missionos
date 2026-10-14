import { useState, useId, useMemo } from 'react';
import { Search } from 'lucide-react';
import {
  Modal,
  Button,
  FormField,
  Input,
  Alert,
  Skeleton,
} from '../../../components/ui';
import { useEventRoster, useSetEventGreeter } from '../queries';
import { getEventErrorMessage } from '../error-message';
import type { EventGreeter } from '../types';

interface AddGreeterModalProps {
  open: boolean;
  onClose: () => void;
  organizationId: string;
  eventId: string;
  currentGreeters: EventGreeter[];
  onSuccess?: () => void;
}

export function AddGreeterModal({
  open,
  onClose,
  organizationId,
  eventId,
  currentGreeters,
  onSuccess,
}: AddGreeterModalProps) {
  const [search, setSearch] = useState('');
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [assigningMemberId, setAssigningMemberId] = useState<string | null>(null);

  const searchId = useId();
  const { data: rosterData, isLoading } = useEventRoster(organizationId, open ? eventId : null);
  const greeterMutation = useSetEventGreeter();

  const currentGreeterIds = useMemo(
    () => new Set(currentGreeters.map((g) => g.member_id)),
    [currentGreeters]
  );

  const filteredMembers = useMemo(() => {
    if (!rosterData?.members) return [];
    const q = search.trim().toLowerCase();

    return rosterData.members
      .filter((m) => !currentGreeterIds.has(m.member_id))
      .filter((m) => {
        if (!q) return true;
        const nameMatch = m.display_name.toLowerCase().includes(q);
        const numberMatch = m.member_number ? m.member_number.toLowerCase().includes(q) : false;
        return nameMatch || numberMatch;
      })
      .slice(0, 50); // limit to top 50 matches for performance
  }, [rosterData?.members, currentGreeterIds, search]);

  const handleAssign = async (memberId: string) => {
    setErrorMessage(null);
    setAssigningMemberId(memberId);

    try {
      await greeterMutation.mutateAsync({
        organizationId,
        eventId,
        memberId,
        assign: true,
      });
      onSuccess?.();
      onClose();
    } catch (err) {
      setErrorMessage(getEventErrorMessage(err));
    } finally {
      setAssigningMemberId(null);
    }
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Add Greeter"
      description="Assign an active member with a verified MissionOS login to greet and record attendance."
      size="md"
      footer={
        <div className="flex w-full items-center justify-end">
          <Button variant="outline" onClick={onClose} disabled={!!assigningMemberId}>
            Close
          </Button>
        </div>
      }
    >
      <div className="space-y-4">
        {errorMessage && (
          <Alert variant="danger">
            {errorMessage}
          </Alert>
        )}

        <FormField label="Search members">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-ink-muted" />
            <Input
              id={searchId}
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search by name or member number (e.g. NY10...)"
              className="pl-9"
              autoFocus
            />
          </div>
        </FormField>

        <div className="max-h-72 divide-y divide-line overflow-y-auto rounded-card border border-line bg-surface">
          {isLoading ? (
            <div className="space-y-3 p-4">
              <Skeleton className="h-10" />
              <Skeleton className="h-10" />
              <Skeleton className="h-10" />
            </div>
          ) : filteredMembers.length === 0 ? (
            <div className="p-6 text-center text-small text-ink-muted">
              {search.trim() ? 'No matching members found.' : 'All eligible members are already greeters.'}
            </div>
          ) : (
            filteredMembers.map((m) => (
              <div
                key={m.member_id}
                className="flex items-center justify-between p-3 hover:bg-surface-muted transition-colors"
              >
                <div className="min-w-0 pr-3">
                  <p className="truncate text-body font-medium text-ink">
                    {m.display_name}
                  </p>
                  <p className="text-caption text-ink-muted">
                    {m.member_number ? m.member_number : 'No member number'}
                    {m.section_name ? ` · ${m.section_name}` : ''}
                  </p>
                </div>
                <Button
                  size="sm"
                  variant="outline"
                  loading={assigningMemberId === m.member_id}
                  disabled={!!assigningMemberId}
                  onClick={() => handleAssign(m.member_id)}
                >
                  Assign
                </Button>
              </div>
            ))
          )}
        </div>
      </div>
    </Modal>
  );
}
