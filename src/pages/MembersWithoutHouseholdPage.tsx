import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { useOrganizationContext } from '../hooks/use-organization-context';
import { usePermissions } from '../hooks/use-permissions';
import { Permissions } from '../types/permissions';
import { householdKeys } from '../features/households/queries';
import { searchMembersWithoutHousehold } from '../features/households/api/search-members-without-household';
import type { MemberWithoutHousehold } from '../features/households/types';
import { AssignHouseholdMemberModal } from '../features/households/components/AssignHouseholdMemberModal';
import { searchHouseholds } from '../features/households/api/search-households';

export default function MembersWithoutHouseholdPage() {
  const { activeOrganization } = useOrganizationContext();
  const orgId = activeOrganization?.id ?? null;
  const { hasPermission, isLoading: isPermLoading } = usePermissions();

  const canAssign = !isPermLoading && hasPermission(Permissions.HouseholdsMembersAssign);
  const canViewMembers = !isPermLoading && hasPermission(Permissions.MembersRecordsView);

  const [searchTerm, setSearchTerm] = useState('');
  const [selectedMember, setSelectedMember] = useState<MemberWithoutHousehold | null>(null);
  const [isAssignModalOpen, setIsAssignModalOpen] = useState(false);
  const [targetHouseholdId, setTargetHouseholdId] = useState<string>('');
  const [targetHouseholdName, setTargetHouseholdName] = useState<string>('');
  const [toastMessage, setToastMessage] = useState<string | null>(null);

  // Load members without household query
  const {
    data: unplacedData,
    isLoading,
    error,
  } = useQuery({
    queryKey: householdKeys.membersWithoutHousehold(orgId ?? '', searchTerm),
    queryFn: () => searchMembersWithoutHousehold(orgId ?? '', { search: searchTerm, limit: 100 }),
    enabled: Boolean(orgId),
    staleTime: 30_000,
  });

  // Load available active households for assigning
  const { data: householdsData } = useQuery({
    queryKey: householdKeys.list(orgId ?? '', { lifecycle_status: 'active' }),
    queryFn: () => searchHouseholds(orgId ?? '', { lifecycleStatus: 'active', limit: 100 }),
    enabled: Boolean(orgId && isAssignModalOpen),
    staleTime: 30_000,
  });

  const activeHouseholds = householdsData?.households ?? [];

  const handleOpenAssign = (member: MemberWithoutHousehold) => {
    setSelectedMember(member);
    if (activeHouseholds.length > 0) {
      setTargetHouseholdId(activeHouseholds[0].household_id);
      setTargetHouseholdName(activeHouseholds[0].name);
    }
    setIsAssignModalOpen(true);
  };

  const triggerToast = (msg: string) => {
    setToastMessage(msg);
    setTimeout(() => setToastMessage(null), 5000);
  };

  const members = unplacedData?.members ?? [];
  const totalCount = unplacedData?.total_count ?? 0;

  return (
    <div className="space-y-6">
      {/* Toast Notification */}
      {toastMessage && (
        <div className="rounded-lg bg-success-50 border border-success-600 p-4 text-success-700 text-sm flex items-center justify-between shadow-lg">
          <div className="flex items-center gap-2">
            <svg className="h-5 w-5 text-success-700" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
            </svg>
            <span>{toastMessage}</span>
          </div>
          <button
            onClick={() => setToastMessage(null)}
            className="text-xs text-success-700 hover:text-success-700"
          >
            Dismiss
          </button>
        </div>
      )}

      {/* Breadcrumb & Header */}
      <div>
        <nav className="mb-2">
          <Link
            to="/app/households"
            className="inline-flex items-center gap-1.5 text-xs font-medium text-ink-muted hover:text-ink transition-colors"
          >
            <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
            </svg>
            Back to Households Directory
          </Link>
        </nav>

        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
          <div>
            <h1 className="text-2xl font-bold tracking-tight text-ink">
              Members Without a Household
            </h1>
            <p className="text-sm text-ink-muted mt-1">
              Active members who currently have no primary pastoral household assignment.
            </p>
          </div>

          <div className="inline-flex items-center gap-2 rounded-lg bg-navy-50 border border-navy-100 px-3.5 py-2 text-primary-blue text-xs font-semibold self-start sm:self-auto">
            <span>Total Count:</span>
            <span className="font-bold text-sm text-primary-blue">{totalCount}</span>
          </div>
        </div>
      </div>

      {/* Search Bar */}
      <div className="relative max-w-md">
        <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
          <svg className="h-4 w-4 text-ink-muted" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
          </svg>
        </div>
        <input
          type="text"
          value={searchTerm}
          onChange={(e) => setSearchTerm(e.target.value)}
          placeholder="Filter members by name…"
          className="w-full rounded-lg border border-line bg-surface py-2 pl-9 pr-4 text-sm text-ink placeholder-slate-500 focus:border-focus focus:outline-none focus:ring-1 focus:ring-focus"
        />
      </div>

      {/* Content Table */}
      <div className="rounded-xl border border-line bg-surface-muted overflow-hidden shadow-sm">
        {isLoading ? (
          <div className="p-8 text-center text-sm text-ink-muted italic">
            Loading members without a household…
          </div>
        ) : error ? (
          <div className="p-6 text-center text-xs text-danger-700">
            Failed to load members without a household. Please verify permissions.
          </div>
        ) : members.length === 0 ? (
          <div className="p-12 text-center text-ink-muted space-y-2">
            <p className="text-sm font-semibold text-ink-secondary">No members without a household found</p>
            <p className="text-xs text-ink-muted">
              {searchTerm ? 'Try adjusting your search criteria.' : 'All active members are placed in a pastoral household.'}
            </p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left text-xs">
              <thead className="bg-surface text-ink-muted border-b border-line">
                <tr>
                  <th className="px-5 py-3 font-medium">Member</th>
                  <th className="px-5 py-3 font-medium">Number</th>
                  <th className="px-5 py-3 font-medium">Governance Placement</th>
                  <th className="px-5 py-3 font-medium">Member Since</th>
                  {canAssign && (
                    <th className="px-5 py-3 font-medium text-right">Actions</th>
                  )}
                </tr>
              </thead>
              <tbody className="divide-y divide-line text-ink">
                {members.map((m) => (
                  <tr key={m.member_id} className="hover:bg-surface-muted transition-colors">
                    <td className="px-5 py-3.5 font-medium">
                      {canViewMembers ? (
                        <Link
                          to={`/app/members/${m.member_id}`}
                          className="hover:text-primary-blue hover:underline transition-colors"
                        >
                          {m.display_name}
                        </Link>
                      ) : (
                        <span>{m.display_name}</span>
                      )}
                    </td>
                    <td className="px-5 py-3.5 font-mono text-ink-muted">
                      {m.member_number || '—'}
                    </td>
                    <td className="px-5 py-3.5">
                      {m.primary_governance_name ? (
                        <span className="text-ink-secondary">
                          {m.primary_governance_name}
                          {m.primary_governance_type && (
                            <span className="ml-1 text-[10px] text-ink-muted uppercase">
                              ({m.primary_governance_type})
                            </span>
                          )}
                        </span>
                      ) : (
                        <span className="text-ink-muted italic">Unplaced in governance</span>
                      )}
                    </td>
                    <td className="px-5 py-3.5 text-ink-muted">
                      {m.joined_on || '—'}
                    </td>
                    {canAssign && (
                      <td className="px-5 py-3.5 text-right">
                        <button
                          type="button"
                          onClick={() => handleOpenAssign(m)}
                          className="inline-flex items-center gap-1 rounded-lg border border-navy-100 bg-navy-50 px-2.5 py-1 text-xs font-semibold text-primary-blue hover:bg-navy-100 transition-colors"
                        >
                          Assign Household
                        </button>
                      </td>
                    )}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Assign Modal */}
      {orgId && selectedMember && isAssignModalOpen && (
        <AssignHouseholdMemberModal
          isOpen={isAssignModalOpen}
          onClose={() => {
            setIsAssignModalOpen(false);
            setSelectedMember(null);
          }}
          organizationId={orgId}
          householdId={targetHouseholdId}
          householdName={targetHouseholdName || 'Selected Household'}
          preselectedMember={selectedMember}
          onSuccessToast={triggerToast}
        />
      )}
    </div>
  );
}
