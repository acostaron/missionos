import type { FamilyProfileMember } from '../types';

interface FamilyMemberRosterProps {
  members: FamilyProfileMember[];
  canAddMember?: boolean;
  canUpdateMember?: boolean;
  canEndMember?: boolean;
  isFamilyOperational?: boolean;
  onAddMember?: () => void;
  onEditMember?: (member: FamilyProfileMember) => void;
  onEndMember?: (member: FamilyProfileMember) => void;
}

function formatRole(role: string | null): string | null {
  if (!role) return null;
  return role
    .replace(/_/g, ' ')
    .replace(/\b\w/g, (char) => char.toUpperCase());
}

export function FamilyMemberRoster({
  members,
  canAddMember = false,
  canUpdateMember = false,
  canEndMember = false,
  isFamilyOperational = false,
  onAddMember,
  onEditMember,
  onEndMember,
}: FamilyMemberRosterProps) {
  const icon = (
    <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
      <path strokeLinecap="round" strokeLinejoin="round"
        d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
    </svg>
  );

  const showRowActions = (canUpdateMember || canEndMember) && isFamilyOperational;

  return (
    <div className="rounded-xl border border-line bg-surface-muted overflow-hidden">
      <div className="flex items-center justify-between border-b border-line px-5 py-3.5">
        <div className="flex items-center gap-3">
          <span className="text-ink-muted">{icon}</span>
          <h2 className="text-sm font-semibold uppercase tracking-wider text-ink-secondary">
            Family Members
          </h2>
          <span className="text-xs text-ink-muted">
            ({members.length})
          </span>
        </div>
        {canAddMember && isFamilyOperational && onAddMember && (
          <button
            type="button"
            id="add-family-member-button"
            onClick={onAddMember}
            className="inline-flex items-center gap-1.5 rounded-lg border border-navy-100 bg-navy-50 px-3 py-1.5 text-xs font-medium text-primary-blue shadow-sm hover:bg-navy-100 hover:text-primary-blue transition-colors"
          >
            <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M12 4v16m8-8H4" />
            </svg>
            Add member
          </button>
        )}
      </div>

      <div className="px-5 py-4">
        {members.length === 0 ? (
          <p className="text-xs text-ink-muted italic py-1">
            No family members are currently linked.
          </p>
        ) : (
          <div className="space-y-3">
            {members.map((member) => {
              const roleLabel = formatRole(member.family_role);
              const isStatusActive = member.membership_status?.is_active_membership ?? false;
              const statusName = member.membership_status?.name ?? 'Active';

              return (
                <div
                  key={member.family_member_id}
                  className="rounded-lg border border-line bg-surface p-3.5 space-y-2.5"
                >
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <div className="flex items-center gap-2 flex-wrap">
                        <span className="text-sm font-semibold text-ink">
                          {member.display_name}
                        </span>
                        {member.preferred_name && member.preferred_name !== member.display_name && (
                          <span className="text-xs text-ink-muted">
                            ({member.preferred_name})
                          </span>
                        )}
                        {member.member_number && (
                          <span className="font-mono text-xs text-ink-muted">
                            {member.member_number}
                          </span>
                        )}
                      </div>
                      {roleLabel && (
                        <p className="text-xs text-ink-muted mt-0.5">
                          {roleLabel}
                        </p>
                      )}
                    </div>

                    <div className="flex items-center gap-1.5 flex-wrap justify-end">
                      {member.is_deceased && (
                        <span className="inline-flex items-center rounded-full border border-warning-600/30 bg-warning-50 px-2 py-0.5 text-[10px] font-medium text-warning-700">
                          Deceased
                        </span>
                      )}
                      {member.record_status === 'archived' && (
                        <span className="inline-flex items-center rounded-full border border-danger-600/30 bg-danger-50 px-2 py-0.5 text-[10px] font-medium text-danger-700">
                          Archived record
                        </span>
                      )}
                      <span
                        className={`inline-flex items-center rounded-full border px-2 py-0.5 text-[10px] font-medium ${
                          isStatusActive
                            ? 'border-success-600/30 bg-success-50 text-success-700'
                            : 'border-line-strong bg-surface-muted text-ink-muted'
                        }`}
                      >
                        {statusName}
                      </span>
                      {member.is_primary_contact && (
                        <span className="inline-flex items-center rounded-full border border-navy-100 bg-navy-50 px-2 py-0.5 text-[10px] font-medium text-primary-blue">
                          Primary contact
                        </span>
                      )}
                      {member.is_dependent && (
                        <span className="inline-flex items-center rounded-full border border-warning-600/30 bg-warning-50 px-2 py-0.5 text-[10px] font-medium text-warning-700">
                          Dependent
                        </span>
                      )}
                    </div>
                  </div>

                  {showRowActions && (
                    <div className="flex items-center gap-2 pt-2 border-t border-line justify-end">
                      {canUpdateMember && onEditMember && (
                        <button
                          type="button"
                          id={`edit-member-btn-${member.family_member_id}`}
                          onClick={() => onEditMember(member)}
                          className="inline-flex items-center gap-1 rounded px-2.5 py-1 text-xs font-medium text-ink-secondary hover:bg-surface-muted hover:text-white transition-colors"
                        >
                          <svg className="h-3.5 w-3.5 text-ink-muted" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                            <path strokeLinecap="round" strokeLinejoin="round" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                          </svg>
                          Edit
                        </button>
                      )}
                      {canEndMember && onEndMember && (
                        <button
                          type="button"
                          id={`end-member-btn-${member.family_member_id}`}
                          onClick={() => onEndMember(member)}
                          className="inline-flex items-center gap-1 rounded px-2.5 py-1 text-xs font-medium text-danger-700 hover:bg-danger-100 hover:text-danger-700 transition-colors"
                        >
                          <svg className="h-3.5 w-3.5 text-danger-700" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                            <path strokeLinecap="round" strokeLinejoin="round" d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" />
                          </svg>
                          End membership
                        </button>
                      )}
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
