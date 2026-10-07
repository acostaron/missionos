import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useMemberHouseholds } from '../api/get-member-households';
import type { MemberHouseholdAssignment } from '../types';
import { TransferHouseholdMemberModal } from './TransferHouseholdMemberModal';
import { EndHouseholdMembershipModal } from './EndHouseholdMembershipModal';

interface MemberHouseholdCardProps {
  organizationId: string | null;
  memberId: string;
  memberName?: string;
  canViewHouseholds: boolean;
  canAssignHousehold?: boolean;
  canTransferHousehold?: boolean;
  canEndHousehold?: boolean;
}

function formatRole(role: string | null): string {
  if (!role) return 'Member';
  return role
    .replace(/_/g, ' ')
    .replace(/\b\w/g, (char) => char.toUpperCase());
}

function HouseholdItem({
  assignment,
  canTransfer,
  canEnd,
  onOpenTransfer,
  onOpenEnd,
}: {
  assignment: MemberHouseholdAssignment;
  canTransfer: boolean;
  canEnd: boolean;
  onOpenTransfer: (h: MemberHouseholdAssignment) => void;
  onOpenEnd: (h: MemberHouseholdAssignment) => void;
}) {
  const isStatusActive = assignment.household_status === 'active';
  const roleLabel = formatRole(assignment.membership_role);

  return (
    <div className="rounded-lg border border-line bg-surface p-3.5 space-y-2.5">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h3 className="text-sm font-semibold text-ink">
            <Link
              to={`/app/households/${assignment.household_id}`}
              className="hover:text-primary-blue hover:underline transition-colors"
            >
              {assignment.household_name}
            </Link>
          </h3>
          <p className="text-xs text-ink-muted mt-0.5">
            Code: <span className="font-mono text-ink-secondary">{assignment.household_code}</span>
            {assignment.parent_node_name && (
              <>
                <span className="mx-1.5 text-ink-muted">•</span>
                <span>{assignment.parent_node_name}</span>
                {assignment.parent_node_type && (
                  <span className="ml-1 text-[10px] uppercase text-ink-muted">
                    ({assignment.parent_node_type})
                  </span>
                )}
              </>
            )}
          </p>
        </div>
        <div className="flex items-center gap-1.5 flex-wrap justify-end">
          <span
            className={`inline-flex items-center rounded-full border px-2 py-0.5 text-[10px] font-medium ${
              isStatusActive
                ? 'border-success-600/30 bg-success-50 text-success-700'
                : 'border-line-strong bg-surface-muted text-ink-muted'
            }`}
          >
            {assignment.household_status}
          </span>
          {assignment.is_primary && (
            <span className="inline-flex items-center rounded-full border border-navy-100 bg-navy-50 px-2 py-0.5 text-[10px] font-medium text-primary-blue">
              Primary
            </span>
          )}
        </div>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-2 pt-2 border-t border-line text-xs">
        <div className="flex items-center justify-between text-ink-muted pr-2">
          <span>Household role</span>
          <span className="font-medium text-ink">{roleLabel}</span>
        </div>
        <div className="flex items-center justify-between text-ink-muted">
          <span>Effective date</span>
          <span className="font-medium text-ink">{assignment.effective_from}</span>
        </div>
        {assignment.household_servant_name && (
          <div className="flex items-center justify-between text-ink-muted sm:col-span-2 pt-1 border-t border-line">
            <span>Household Servant</span>
            <span className="font-medium text-ink">{assignment.household_servant_name}</span>
          </div>
        )}
      </div>

      {/* Pastoral Actions for current assignment */}
      {(canTransfer || canEnd) && (
        <div className="flex items-center justify-end gap-2 pt-2 border-t border-line">
          {canTransfer && (
            <button
              type="button"
              onClick={() => onOpenTransfer(assignment)}
              className="inline-flex items-center gap-1 rounded px-2 py-1 text-xs font-medium text-primary-blue hover:bg-navy-100 hover:text-primary-blue transition-colors"
            >
              Transfer Household
            </button>
          )}
          {canEnd && (
            <button
              type="button"
              onClick={() => onOpenEnd(assignment)}
              className="inline-flex items-center gap-1 rounded px-2 py-1 text-xs font-medium text-danger-700 hover:bg-danger-100 hover:text-danger-700 transition-colors"
            >
              End Assignment
            </button>
          )}
        </div>
      )}
    </div>
  );
}

export function MemberHouseholdCard({
  organizationId,
  memberId,
  memberName = 'Member',
  canViewHouseholds,
  canAssignHousehold = false,
  canTransferHousehold = false,
  canEndHousehold = false,
}: MemberHouseholdCardProps) {
  const {
    data: households,
    isLoading,
    error,
  } = useMemberHouseholds(organizationId, memberId, canViewHouseholds);

  const [isTransferModalOpen, setIsTransferModalOpen] = useState(false);
  const [isEndModalOpen, setIsEndModalOpen] = useState(false);
  const [activeAssignment, setActiveAssignment] = useState<MemberHouseholdAssignment | null>(null);

  const handleOpenTransfer = (assignment: MemberHouseholdAssignment) => {
    setActiveAssignment(assignment);
    setIsTransferModalOpen(true);
  };

  const handleOpenEnd = (assignment: MemberHouseholdAssignment) => {
    setActiveAssignment(assignment);
    setIsEndModalOpen(true);
  };

  const icon = (
    <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6"
      />
    </svg>
  );

  const hasAssignment = Boolean(households && households.length > 0);

  return (
    <div className="rounded-xl border border-line bg-surface-muted overflow-hidden">
      <div className="flex items-center justify-between border-b border-line px-5 py-3.5">
        <div className="flex items-center gap-3">
          <span className="text-ink-muted">{icon}</span>
          <h2 className="text-sm font-semibold uppercase tracking-wider text-ink-secondary">
            Household Assignment
          </h2>
        </div>

        {!hasAssignment && canAssignHousehold && (
          <Link
            to="/app/households/unassigned"
            className="inline-flex items-center gap-1.5 rounded-lg border border-navy-100 bg-navy-50 px-2.5 py-1 text-xs font-semibold text-primary-blue hover:bg-navy-100 transition-colors"
          >
            Assign Household
          </Link>
        )}
      </div>

      <div className="px-5 py-4">
        {!canViewHouseholds ? (
          <p className="flex items-center gap-2 text-xs text-ink-muted italic">
            <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
              <path strokeLinecap="round" strokeLinejoin="round"
                d="M12 15v2m-6 4h12a2 2 0 002-2v-5a2 2 0 00-2-2H6a2 2 0 00-2 2v5a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
            </svg>
            Household assignment — access restricted for this role
          </p>
        ) : isLoading ? (
          <div className="space-y-3 py-1">
            <div className="h-16 animate-pulse rounded-lg bg-surface border border-line" />
          </div>
        ) : error ? (
          <div className="rounded-lg border border-danger-600/30 bg-danger-50 p-3 text-xs text-danger-700">
            Failed to load household assignment.
          </div>
        ) : !households || households.length === 0 ? (
          <div className="flex items-center justify-between py-1">
            <p className="text-xs text-ink-muted italic">No household assigned.</p>
            {canAssignHousehold && (
              <span className="text-[11px] text-ink-muted">
                Use the Unassigned Members directory to place this member.
              </span>
            )}
          </div>
        ) : (
          <div className="space-y-3">
            {households.map((h) => (
              <HouseholdItem
                key={h.household_membership_id}
                assignment={h}
                canTransfer={canTransferHousehold}
                canEnd={canEndHousehold}
                onOpenTransfer={handleOpenTransfer}
                onOpenEnd={handleOpenEnd}
              />
            ))}
          </div>
        )}
      </div>

      {/* Transfer Modal */}
      {organizationId && activeAssignment && isTransferModalOpen && (
        <TransferHouseholdMemberModal
          isOpen={isTransferModalOpen}
          onClose={() => {
            setIsTransferModalOpen(false);
            setActiveAssignment(null);
          }}
          organizationId={organizationId}
          memberId={memberId}
          memberName={memberName}
          currentHouseholdId={activeAssignment.household_id}
          currentHouseholdName={activeAssignment.household_name}
        />
      )}

      {/* End Modal */}
      {organizationId && activeAssignment && isEndModalOpen && (
        <EndHouseholdMembershipModal
          isOpen={isEndModalOpen}
          onClose={() => {
            setIsEndModalOpen(false);
            setActiveAssignment(null);
          }}
          organizationId={organizationId}
          memberId={memberId}
          memberName={memberName}
          currentHouseholdId={activeAssignment.household_id}
          currentHouseholdName={activeAssignment.household_name}
        />
      )}
    </div>
  );
}
