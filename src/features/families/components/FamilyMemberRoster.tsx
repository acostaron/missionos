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
    <div className="rounded-xl border border-slate-700 bg-slate-800/60 overflow-hidden">
      <div className="flex items-center justify-between border-b border-slate-700 px-5 py-3.5">
        <div className="flex items-center gap-3">
          <span className="text-slate-400">{icon}</span>
          <h2 className="text-sm font-semibold uppercase tracking-wider text-slate-300">
            Family Members
          </h2>
          <span className="text-xs text-slate-400">
            ({members.length})
          </span>
        </div>
        {canAddMember && isFamilyOperational && onAddMember && (
          <button
            type="button"
            id="add-family-member-button"
            onClick={onAddMember}
            className="inline-flex items-center gap-1.5 rounded-lg border border-indigo-700/60 bg-indigo-950/40 px-3 py-1.5 text-xs font-medium text-indigo-300 shadow-sm hover:bg-indigo-900/60 hover:text-indigo-200 transition-colors"
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
          <p className="text-xs text-slate-500 italic py-1">
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
                  className="rounded-lg border border-slate-700 bg-slate-900/40 p-3.5 space-y-2.5"
                >
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <div className="flex items-center gap-2 flex-wrap">
                        <span className="text-sm font-semibold text-slate-100">
                          {member.display_name}
                        </span>
                        {member.preferred_name && member.preferred_name !== member.display_name && (
                          <span className="text-xs text-slate-400">
                            ({member.preferred_name})
                          </span>
                        )}
                        {member.member_number && (
                          <span className="font-mono text-xs text-slate-400">
                            {member.member_number}
                          </span>
                        )}
                      </div>
                      {roleLabel && (
                        <p className="text-xs text-slate-400 mt-0.5">
                          {roleLabel}
                        </p>
                      )}
                    </div>

                    <div className="flex items-center gap-1.5 flex-wrap justify-end">
                      {member.is_deceased && (
                        <span className="inline-flex items-center rounded-full border border-amber-800/60 bg-amber-950/40 px-2 py-0.5 text-[10px] font-medium text-amber-300">
                          Deceased
                        </span>
                      )}
                      {member.record_status === 'archived' && (
                        <span className="inline-flex items-center rounded-full border border-rose-800/60 bg-rose-950/40 px-2 py-0.5 text-[10px] font-medium text-rose-300">
                          Archived record
                        </span>
                      )}
                      <span
                        className={`inline-flex items-center rounded-full border px-2 py-0.5 text-[10px] font-medium ${
                          isStatusActive
                            ? 'border-emerald-700/60 bg-emerald-950/40 text-emerald-300'
                            : 'border-slate-600 bg-slate-800 text-slate-400'
                        }`}
                      >
                        {statusName}
                      </span>
                      {member.is_primary_contact && (
                        <span className="inline-flex items-center rounded-full border border-sky-700/60 bg-sky-950/40 px-2 py-0.5 text-[10px] font-medium text-sky-300">
                          Primary contact
                        </span>
                      )}
                      {member.is_dependent && (
                        <span className="inline-flex items-center rounded-full border border-amber-700/60 bg-amber-950/40 px-2 py-0.5 text-[10px] font-medium text-amber-300">
                          Dependent
                        </span>
                      )}
                    </div>
                  </div>

                  {showRowActions && (
                    <div className="flex items-center gap-2 pt-2 border-t border-slate-800/80 justify-end">
                      {canUpdateMember && onEditMember && (
                        <button
                          type="button"
                          id={`edit-member-btn-${member.family_member_id}`}
                          onClick={() => onEditMember(member)}
                          className="inline-flex items-center gap-1 rounded px-2.5 py-1 text-xs font-medium text-slate-300 hover:bg-slate-800 hover:text-white transition-colors"
                        >
                          <svg className="h-3.5 w-3.5 text-slate-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
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
                          className="inline-flex items-center gap-1 rounded px-2.5 py-1 text-xs font-medium text-rose-400 hover:bg-rose-950/40 hover:text-rose-300 transition-colors"
                        >
                          <svg className="h-3.5 w-3.5 text-rose-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
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
