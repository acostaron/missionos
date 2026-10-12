import { useState } from 'react';
import { BookOpen, Plus } from 'lucide-react';
import { useMemberFormationTranscript } from '../queries';
import { FormationProgramRow } from './FormationProgramRow';
import { RecordFormationProgramModal } from './RecordFormationProgramModal';
import { RecordFormationTalkModal } from './RecordFormationTalkModal';
import { VoidFormationRecordModal } from './VoidFormationRecordModal';
import type { FormationTranscriptProgram } from '../types';
import { Button } from '../../../components/ui';

interface MemberFormationCardProps {
  organizationId: string | null;
  memberId: string;
  memberName?: string;
  memberRecordStatus?: string;
  canViewFormation: boolean;
  canRecord?: boolean;
  canCorrect?: boolean;
  onSuccessToast?: (msg: string) => void;
}

export function MemberFormationCard({
  organizationId,
  memberId,
  memberName,
  memberRecordStatus,
  canViewFormation,
  canRecord = false,
  canCorrect = false,
  onSuccessToast,
}: MemberFormationCardProps) {
  const isMemberActive = memberRecordStatus === 'active';
  const effectiveCanRecord = canRecord && isMemberActive;

  const [isRecordProgramOpen, setIsRecordProgramOpen] = useState(false);
  const [recordTalkProgram, setRecordTalkProgram] = useState<FormationTranscriptProgram | null>(null);
  const [voidModalState, setVoidModalState] = useState<{
    isOpen: boolean;
    mode: 'program' | 'talk';
    recordId: string;
    recordTitle: string;
  }>({
    isOpen: false,
    mode: 'program',
    recordId: '',
    recordTitle: '',
  });

  const {
    data: transcript,
    isLoading,
    error,
  } = useMemberFormationTranscript(organizationId, memberId, canViewFormation);

  // Only rendered if caller has FormationRecordsView
  if (!canViewFormation) {
    return null;
  }

  // Show only records with record_status === 'active' (excludes voided AND superseded)
  const activePrograms = (transcript?.programs ?? []).filter(
    (p) => p.record_status === 'active'
  );

  return (
    <div className="rounded-xl border border-line bg-surface-muted overflow-hidden">
      <div className="flex items-center justify-between border-b border-line px-5 py-3.5">
        <div className="flex items-center gap-3">
          <span className="text-ink-muted">
            <BookOpen className="h-4 w-4" />
          </span>
          <h2 className="text-sm font-semibold uppercase tracking-wider text-ink-secondary">
            Formation
          </h2>
        </div>

        {effectiveCanRecord && organizationId && (
          <Button
            type="button"
            id="record-formation-button"
            variant="outline"
            size="sm"
            onClick={() => setIsRecordProgramOpen(true)}
            className="h-7 text-xs px-2.5 py-0 gap-1.5 font-semibold"
          >
            <Plus className="h-3.5 w-3.5" />
            <span>Record Formation</span>
          </Button>
        )}
      </div>

      <div className="px-5 py-4">
        {isLoading ? (
          <div className="space-y-3 py-1">
            <div className="h-16 animate-pulse rounded-lg bg-surface border border-line" />
          </div>
        ) : error ? (
          <div className="rounded-lg border border-danger-600/30 bg-danger-50 p-3 text-xs text-danger-700">
            Failed to load formation records.
          </div>
        ) : activePrograms.length === 0 ? (
          <p className="text-xs text-ink-muted italic py-1">
            No Formation records yet.
          </p>
        ) : (
          <div className="space-y-3">
            {activePrograms.map((prog) => (
              <FormationProgramRow
                key={prog.record_id}
                program={prog}
                organizationId={organizationId}
                showAdminDetails={true}
                canRecord={effectiveCanRecord}
                canCorrect={canCorrect}
                onOpenRecordTalk={(p) => setRecordTalkProgram(p)}
                onOpenVoidProgram={(p) =>
                  setVoidModalState({
                    isOpen: true,
                    mode: 'program',
                    recordId: p.record_id,
                    recordTitle: `${p.code} — ${p.title}`,
                  })
                }
                onOpenVoidTalk={(talk, title) =>
                  setVoidModalState({
                    isOpen: true,
                    mode: 'talk',
                    recordId: talk.talk_record_id,
                    recordTitle: title,
                  })
                }
              />
            ))}
          </div>
        )}
      </div>

      {/* Record Formation Program Modal */}
      {effectiveCanRecord && organizationId && isRecordProgramOpen && (
        <RecordFormationProgramModal
          isOpen={isRecordProgramOpen}
          onClose={() => setIsRecordProgramOpen(false)}
          organizationId={organizationId}
          memberId={memberId}
          memberName={memberName}
          onSuccessToast={onSuccessToast}
        />
      )}

      {/* Record Formation Talk Modal */}
      {effectiveCanRecord && organizationId && recordTalkProgram && (
        <RecordFormationTalkModal
          isOpen={!!recordTalkProgram}
          onClose={() => setRecordTalkProgram(null)}
          organizationId={organizationId}
          memberId={memberId}
          programRecord={recordTalkProgram}
          onSuccessToast={onSuccessToast}
        />
      )}

      {/* Void Record Modal */}
      {canCorrect && organizationId && voidModalState.isOpen && (
        <VoidFormationRecordModal
          isOpen={voidModalState.isOpen}
          onClose={() =>
            setVoidModalState((prev) => ({ ...prev, isOpen: false }))
          }
          organizationId={organizationId}
          memberId={memberId}
          mode={voidModalState.mode}
          recordId={voidModalState.recordId}
          recordTitle={voidModalState.recordTitle}
          onSuccessToast={onSuccessToast}
        />
      )}
    </div>
  );
}
