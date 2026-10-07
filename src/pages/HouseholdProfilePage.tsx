import { useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { useOrganizationContext } from '../hooks/use-organization-context';
import { usePermissions } from '../hooks/use-permissions';
import { Permissions } from '../types/permissions';
import { useHouseholdProfile } from '../features/households/api/get-household-profile';
import { EditHouseholdModal } from '../features/households/components/EditHouseholdModal';
import { ArchiveHouseholdModal } from '../features/households/components/ArchiveHouseholdModal';
import { AssignHouseholdMemberModal } from '../features/households/components/AssignHouseholdMemberModal';
import { TransferHouseholdMemberModal } from '../features/households/components/TransferHouseholdMemberModal';
import { EndHouseholdMembershipModal } from '../features/households/components/EndHouseholdMembershipModal';
import { AppointServantLeaderModal } from '../features/households/components/AppointServantLeaderModal';
import { ReplaceServantLeaderModal } from '../features/households/components/ReplaceServantLeaderModal';
import { ConcludeServantLeaderModal } from '../features/households/components/ConcludeServantLeaderModal';
import { PastoralPlacementReviewModal } from '../features/households/components/PastoralPlacementReviewModal';
import { HouseholdMeetingsCard } from '../features/households/components/HouseholdMeetingsCard';
import { HouseholdFormationCard } from '../features/households/components/HouseholdFormationCard';
import { ServantLeaderAccessModal } from '../features/households/components/ServantLeaderAccessModal';
import type { HouseholdMember, HouseholdLeader, ServantLeaderRoleCode } from '../features/households/types';

function formatFrequency(freq: string | null): string {
  if (!freq) return 'Weekly';
  return freq.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
}

function formatDayOfWeek(day: number | null): string | null {
  if (day === null || day === undefined) return null;
  const days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  return days[day] ?? null;
}

function formatRole(role: string | null): string {
  if (!role) return 'Member';
  return role.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
}

export default function HouseholdProfilePage() {
  const { householdId } = useParams<{ householdId: string }>();
  const { activeOrganization } = useOrganizationContext();
  const { hasPermission, isLoading: isPermLoading } = usePermissions();
  const [isEditModalOpen, setIsEditModalOpen] = useState(false);
  const [isArchiveModalOpen, setIsArchiveModalOpen] = useState(false);
  const [isAssignModalOpen, setIsAssignModalOpen] = useState(false);
  const [isTransferModalOpen, setIsTransferModalOpen] = useState(false);
  const [isEndModalOpen, setIsEndModalOpen] = useState(false);
  const [isAppointLeaderModalOpen, setIsAppointLeaderModalOpen] = useState(false);
  const [isReplaceLeaderModalOpen, setIsReplaceLeaderModalOpen] = useState(false);
  const [isConcludeLeaderModalOpen, setIsConcludeLeaderModalOpen] = useState(false);
  const [isPlacementModalOpen, setIsPlacementModalOpen] = useState(false);
  const [isAccessModalOpen, setIsAccessModalOpen] = useState(false);
  const [selectedLeader, setSelectedLeader] = useState<HouseholdLeader | null>(null);
  const [selectedMember, setSelectedMember] = useState<HouseholdMember | null>(null);
  const [toastMessage, setToastMessage] = useState<string | null>(null);

  const orgId = activeOrganization?.id ?? null;
  const canViewHouseholds = !isPermLoading && hasPermission(Permissions.HouseholdsRecordsView);
  const canEditHouseholds = !isPermLoading && hasPermission(Permissions.HouseholdsRecordsUpdate);
  const canArchiveHouseholds = !isPermLoading && hasPermission(Permissions.HouseholdsRecordsArchive);
  const canViewMembers = !isPermLoading && hasPermission(Permissions.MembersRecordsView);
  const canAssignMembers = !isPermLoading && hasPermission(Permissions.HouseholdsMembersAssign);
  const canTransferMembers = !isPermLoading && hasPermission(Permissions.HouseholdsMembersTransfer);
  const canEndMembers = !isPermLoading && hasPermission(Permissions.HouseholdsMembersEnd);
  const canAppointLeader = !isPermLoading && hasPermission(Permissions.LeadershipServantLeadersAppoint);
  const canConcludeLeader = !isPermLoading && hasPermission(Permissions.LeadershipServantLeadersConclude);
  const canReplaceLeader = !isPermLoading && hasPermission(Permissions.LeadershipServantLeadersReplace);
  const canReviewPlacement = !isPermLoading && hasPermission(Permissions.LeadershipPastoralPlacementReview);
  const canViewMeetings = !isPermLoading && hasPermission(Permissions.HouseholdsMeetingsView);
  const canManageMeetings = !isPermLoading && hasPermission(Permissions.HouseholdsMeetingsManage);
  const canRecordAttendance = !isPermLoading && hasPermission(Permissions.HouseholdsAttendanceRecord);
  const canViewFormation =
    !isPermLoading &&
    (hasPermission(Permissions.HouseholdsFormationView) ||
      hasPermission(Permissions.HouseholdsFormationManage));
  const canManageFormation = !isPermLoading && hasPermission(Permissions.HouseholdsFormationManage);
  const canManageDelegatedAccess =
    !isPermLoading &&
    (hasPermission(Permissions.LeadershipDelegatedAccessManage) ||
      hasPermission(Permissions.LeadershipDelegatedAccessView));

  const {
    data,
    isLoading,
    error,
  } = useHouseholdProfile(
    orgId,
    householdId ?? null,
    canViewHouseholds && !!householdId
  );

  const triggerToast = (msg: string) => {
    setToastMessage(msg);
    setTimeout(() => setToastMessage(null), 5000);
  };

  if (!canViewHouseholds && !isPermLoading) {
    return (
      <div className="mx-auto max-w-5xl px-4 py-8 sm:px-6 lg:px-8">
        <div className="rounded-xl border border-line bg-surface p-6 text-center">
          <p className="text-sm text-ink-muted">
            You do not have permission to view household records.
          </p>
        </div>
      </div>
    );
  }

  if (isLoading) {
    return (
      <div className="mx-auto max-w-5xl px-4 py-8 sm:px-6 lg:px-8 space-y-6">
        <div className="h-10 w-48 animate-pulse rounded-lg bg-surface-muted" />
        <div className="h-40 animate-pulse rounded-xl bg-surface-muted border border-line" />
        <div className="h-64 animate-pulse rounded-xl bg-surface-muted border border-line" />
      </div>
    );
  }

  if (error || !data) {
    return (
      <div className="mx-auto max-w-5xl px-4 py-8 sm:px-6 lg:px-8 space-y-4">
        <Link
          to="/app/households"
          className="inline-flex items-center gap-1.5 text-xs text-ink-muted hover:text-ink transition-colors"
        >
          <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
          </svg>
          Back to Households
        </Link>
        <div className="rounded-xl border border-line bg-surface p-10 text-center">
          <h2 className="text-base font-semibold text-ink">
            Household Not Found or Inaccessible
          </h2>
          <p className="mt-1 text-xs text-ink-muted">
            This household may not exist or does not fall within your authorized pastoral scope.
          </p>
        </div>
      </div>
    );
  }

  const { household, parent_governance, leaders, members, counts } = data;
  const isStatusActive = household.lifecycle_status === 'active';
  const isEditable = ['planned', 'active', 'temporarily_inactive'].includes(household.lifecycle_status);
  const isArchivable = ['planned', 'active', 'temporarily_inactive'].includes(household.lifecycle_status);
  const meetingDay = formatDayOfWeek(household.meeting_day_of_week);
  const meetingFreq = formatFrequency(household.meeting_frequency);

  return (
    <div className="mx-auto max-w-5xl px-4 py-8 sm:px-6 lg:px-8 space-y-6">
      {/* Toast Notification */}
      {toastMessage && (
        <div className="rounded-lg border border-success-600/30 bg-success-50 p-4 text-success-700 text-xs flex items-center justify-between">
          <span>{toastMessage}</span>
          <button
            type="button"
            onClick={() => setToastMessage(null)}
            className="text-success-700 hover:text-success-700"
          >
            ✕
          </button>
        </div>
      )}

      {/* Navigation Breadcrumb */}
      <div>
        <Link
          to="/app/households"
          className="inline-flex items-center gap-1.5 text-xs text-ink-muted hover:text-ink transition-colors"
        >
          <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
          </svg>
          Back to Households
        </Link>
      </div>

      {/* Header Banner */}
      <div className="rounded-xl border border-line bg-surface-muted p-6 shadow-sm">
        <div className="flex flex-col sm:flex-row sm:items-start justify-between gap-4">
          <div className="space-y-1.5">
            <div className="flex items-center gap-3 flex-wrap">
              <h1 className="text-2xl font-bold tracking-tight text-ink">
                {household.name}
              </h1>
              <span className="font-mono text-xs text-ink-muted">
                {household.code}
              </span>
              <span className="inline-flex items-center rounded-full border border-navy-100 bg-navy-50 px-2.5 py-0.5 text-xs font-medium text-primary-blue">
                {household.pastoral_level_label ?? (household.pastoral_level ? `${household.pastoral_level.toUpperCase()} HOUSEHOLD` : 'MEMBER HOUSEHOLD')}
              </span>
              <span
                className={`inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-medium ${
                  isStatusActive
                    ? 'border-success-600/30 bg-success-50 text-success-700'
                    : 'border-line-strong bg-surface-muted text-ink-muted'
                }`}
              >
                {household.lifecycle_status}
              </span>
            </div>

            <p className="text-xs text-ink-muted">
              Category:{' '}
              <span className="text-ink capitalize">
                {household.household_category}
              </span>
              {household.language_code && (
                <>
                  <span className="mx-2 text-ink-muted">•</span>
                  <span>Language: {household.language_code.toUpperCase()}</span>
                </>
              )}
              {household.is_couple_household && (
                <>
                  <span className="mx-2 text-ink-muted">•</span>
                  <span className="text-primary-blue font-medium">Couples Household</span>
                </>
              )}
            </p>
          </div>

          <div className="flex flex-col sm:flex-row sm:items-center gap-4">
            {/* Quick counts */}
            <div className="flex items-center gap-4 bg-surface rounded-lg p-3 border border-line">
              <div className="text-center sm:text-right">
                <p className="text-xs text-ink-muted">Active Members</p>
                <p className="text-lg font-bold text-ink">
                  {counts.active_member_count}{' '}
                  {counts.target_member_count && (
                    <span className="text-xs font-normal text-ink-muted">
                      / {counts.target_member_count}
                    </span>
                  )}
                </p>
              </div>
              <div className="h-8 w-px bg-surface-muted" />
              <div className="text-center sm:text-left">
                <p className="text-xs text-ink-muted">Accepting Members</p>
                <p className={`text-xs font-semibold ${counts.accepts_new_members ? 'text-success-700' : 'text-warning-700'}`}>
                  {counts.accepts_new_members ? 'Open' : 'Full'}
                </p>
              </div>
            </div>

            {/* Action buttons */}
            {(canEditHouseholds || canArchiveHouseholds) && (
              <div className="flex items-center gap-2">
                {canEditHouseholds && isEditable && (
                  <button
                    type="button"
                    onClick={() => setIsEditModalOpen(true)}
                    className="inline-flex items-center gap-1.5 rounded-lg border border-line bg-surface-muted px-3 py-2 text-xs font-semibold text-ink hover:bg-line transition-colors"
                  >
                    <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                    </svg>
                    Edit
                  </button>
                )}
                {canArchiveHouseholds && isArchivable && (
                  <button
                    type="button"
                    onClick={() => setIsArchiveModalOpen(true)}
                    className="inline-flex items-center gap-1.5 rounded-lg border border-danger-600/30 bg-danger-50 px-3 py-2 text-xs font-semibold text-danger-700 hover:bg-danger-100 transition-colors"
                  >
                    <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 8h14M5 8a2 2 0 110-4h14a2 2 0 110 4m-14 0v10a2 2 0 002 2h10a2 2 0 002-2V8m-9 4h4" />
                    </svg>
                    Archive
                  </button>
                )}
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Overview Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        {/* Parent Governance & Schedule */}
        <div className="rounded-xl border border-line bg-surface-muted p-5 space-y-4">
          <h2 className="text-xs font-semibold uppercase tracking-wider text-ink-muted border-b border-line pb-2.5">
            Placement & Schedule
          </h2>

          <div className="space-y-3 text-xs">
            <div className="flex justify-between items-center">
              <span className="text-ink-muted">Pastoral Level</span>
              <span className="rounded bg-surface-muted px-2 py-0.5 font-semibold text-ink uppercase text-[10px]">
                {household.pastoral_level ?? 'member'}
              </span>
            </div>

            <div className="flex justify-between items-center">
              <span className="text-ink-muted">Parent Governance</span>
              <span className="font-medium text-ink">
                {parent_governance ? (
                  <>
                    {parent_governance.parent_node_name}{' '}
                    <span className="text-[10px] uppercase text-ink-muted">
                      ({parent_governance.parent_node_type})
                    </span>
                  </>
                ) : (
                  <span className="text-ink-muted italic">None</span>
                )}
              </span>
            </div>


            <div className="flex justify-between items-center">
              <span className="text-ink-muted">Meeting Frequency</span>
              <span className="font-medium text-ink">{meetingFreq}</span>
            </div>

            {meetingDay && (
              <div className="flex justify-between items-center">
                <span className="text-ink-muted">Meeting Day & Time</span>
                <span className="font-medium text-ink">
                  {meetingDay}
                  {household.meeting_start_time && ` at ${household.meeting_start_time.slice(0, 5)}`}
                  {household.meeting_timezone_name && ` (${household.meeting_timezone_name})`}
                </span>
              </div>
            )}

            <div className="flex justify-between items-center">
              <span className="text-ink-muted">Location Type</span>
              <span className="font-medium text-ink capitalize">
                {household.meeting_location_type || 'Residence'}
              </span>
            </div>

            {household.meeting_location_text && (
              <div className="flex justify-between items-center">
                <span className="text-ink-muted">Location Details</span>
                <span className="font-medium text-ink text-right max-w-xs truncate">
                  {household.meeting_location_text}
                </span>
              </div>
            )}
          </div>
        </div>

        {/* Pastoral Leadership */}
        <div className="rounded-xl border border-line bg-surface-muted p-5 space-y-4">
          <div className="flex items-center justify-between border-b border-line pb-2.5">
            <h2 className="text-xs font-semibold uppercase tracking-wider text-ink-muted">
              Leadership &amp; Facilitation
            </h2>
            {household.leadership_source && (
              <span className="text-[10px] font-mono text-ink-muted uppercase">
                {household.leadership_source.replace(/_/g, ' ')}
              </span>
            )}
          </div>

          {/* Fraternal Household Special Peer Facilitation Notice */}
          {household.pastoral_level === 'fraternal' ? (
            <div className="rounded-lg border border-warning-600/30 bg-warning-50 p-4 space-y-2 text-xs text-warning-700">
              <div className="flex items-center gap-2">
                <svg className="h-4 w-4 text-warning-700" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
                <span className="font-semibold text-warning-700 uppercase tracking-wider text-[11px]">
                  Peer Facilitated · No Permanent Servant Leader
                </span>
              </div>
              <p className="text-warning-700 text-xs leading-relaxed">
                The Fraternal Household provides pastoral nourishment to the Area Head/Leader and senior members.
                Meetings are peer-facilitated with members taking turns leading the prayer meetings. No formal Household Servant Leader is assigned.
              </p>
            </div>
          ) : (
            <>
              {/* Derived Pastoral Couple (Couples Section only) */}
              {data.household_leaders && (
                <div className="rounded-lg border border-navy-100 bg-navy-50 p-3.5 space-y-1.5">
                  <span className="text-[10px] font-semibold uppercase tracking-wider text-primary-blue">
                    {data.household_leaders.pastoral_label || 'HOUSEHOLD LEADERS'}
                  </span>
                  <p className="text-sm font-semibold text-ink">
                    {data.household_leaders.formatted_names}
                  </p>
                  <p className="text-[10px] text-ink-muted">
                    Pastoral couple designation for Couples Section ({data.household_leaders.pastoral_label || 'Household Leaders'})
                  </p>
                </div>
              )}

              {/* Formal Office Holders */}
              {leaders.length === 0 ? (
                <div className="py-2 flex items-center justify-between">
                  <p className="text-xs text-ink-muted italic">
                    No formal leaders currently assigned.
                  </p>
                  {canAppointLeader && household.pastoral_level === 'member' && isStatusActive && (
                    <button
                      type="button"
                      id="btn-appoint-household-leader"
                      onClick={() => setIsAppointLeaderModalOpen(true)}
                      className="inline-flex items-center gap-1 rounded-lg border border-navy-100 bg-navy-50 px-2.5 py-1 text-[11px] font-semibold text-primary-blue hover:bg-navy-100 transition-colors"
                    >
                      + Appoint Leader
                    </button>
                  )}
                </div>
              ) : (
                <div className="space-y-3">
                  {leaders.map((lead) => (
                    <div
                      key={lead.leadership_assignment_id}
                      className="rounded-lg border border-line bg-surface p-3 flex items-center justify-between text-xs flex-wrap gap-2"
                    >
                      <div>
                        <span className="text-[10px] font-semibold uppercase tracking-wider text-ink-muted block mb-0.5">
                          {lead.leadership_role_name}
                        </span>
                        <p className="font-medium text-ink">
                          {lead.display_name}
                        </p>
                        <p className="text-[10px] text-ink-muted mt-0.5">
                          Serving since {lead.effective_from}
                        </p>
                      </div>
                      <div className="flex items-center gap-2">
                        <span className="inline-flex items-center rounded-full border border-navy-100 bg-navy-50 px-2 py-0.5 text-[10px] font-medium text-primary-blue">
                          Formal Office
                        </span>
                        {canManageDelegatedAccess && isStatusActive && (
                          <button
                            type="button"
                            onClick={() => {
                              setSelectedLeader(lead);
                              setIsAccessModalOpen(true);
                            }}
                            className="rounded px-2 py-0.5 text-[11px] font-medium text-primary-blue hover:text-primary-blue bg-navy-50 hover:bg-navy-100 border border-navy-100 transition-colors"
                          >
                            App Access
                          </button>
                        )}
                        {canReviewPlacement && (
                          <button
                            type="button"
                            onClick={() => {
                              setSelectedLeader(lead);
                              setIsPlacementModalOpen(true);
                            }}
                            className="rounded px-2 py-0.5 text-[11px] font-medium text-warning-700 hover:text-warning-700 bg-warning-50 hover:bg-warning-100 border border-warning-600/30 transition-colors"
                          >
                            Placement Review
                          </button>
                        )}
                        {canReplaceLeader && isStatusActive && (
                          <button
                            type="button"
                            onClick={() => {
                              setSelectedLeader(lead);
                              setIsReplaceLeaderModalOpen(true);
                            }}
                            className="rounded px-2 py-0.5 text-[11px] font-medium text-ink-secondary hover:text-white bg-surface-muted hover:bg-line transition-colors"
                          >
                            Replace
                          </button>
                        )}
                        {canConcludeLeader && isStatusActive && (
                          <button
                            type="button"
                            onClick={() => {
                              setSelectedLeader(lead);
                              setIsConcludeLeaderModalOpen(true);
                            }}
                            className="rounded px-2 py-0.5 text-[11px] font-medium text-danger-700 hover:text-danger-700 bg-danger-50 hover:bg-danger-100 border border-danger-600/30 transition-colors"
                          >
                            Conclude
                          </button>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </>
          )}
        </div>
      </div>

      {/* Active Member Roster */}
      <div className="rounded-xl border border-line bg-surface-muted overflow-hidden">
        <div className="flex items-center justify-between border-b border-line px-5 py-3.5 flex-wrap gap-2">
          <div className="flex items-center gap-3">
            <h2 className="text-sm font-semibold uppercase tracking-wider text-ink-secondary">
              Active Household Roster
            </h2>
            <span className="rounded-full bg-surface-muted px-2 py-0.5 text-[10px] font-medium text-ink-secondary">
              {members.length} {members.length === 1 ? 'member' : 'members'}
            </span>
          </div>

          {canAssignMembers && household.lifecycle_status === 'active' && (
            <button
              type="button"
              id="btn-add-household-member"
              onClick={() => setIsAssignModalOpen(true)}
              className="inline-flex items-center gap-1.5 rounded-lg border border-navy-100 bg-navy-50 px-3 py-1.5 text-xs font-semibold text-primary-blue hover:bg-navy-100 transition-colors"
            >
              <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M12 4v16m8-8H4" />
              </svg>
              Add Member
            </button>
          )}
        </div>

        {members.length === 0 ? (
          <div className="p-8 text-center text-xs text-ink-muted italic">
            No active members assigned to this household.
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left text-xs">
              <thead className="bg-surface text-ink-muted border-b border-line">
                <tr>
                  <th className="px-5 py-3 font-medium">Member</th>
                  <th className="px-5 py-3 font-medium">Number</th>
                  <th className="px-5 py-3 font-medium">Household Role</th>
                  <th className="px-5 py-3 font-medium">Status</th>
                  <th className="px-5 py-3 font-medium">Joined Date</th>
                  {(canTransferMembers || canEndMembers) && (
                    <th className="px-5 py-3 font-medium text-right">Actions</th>
                  )}
                </tr>
              </thead>
              <tbody className="divide-y divide-line text-ink">
                {members.map((m) => {
                  const isServant = m.membership_role === 'servant';
                  const isDerivedWifeLeader =
                    data.household_leaders &&
                    m.member_id === data.household_leaders.wife.member_id;

                  return (
                    <tr key={m.household_membership_id} className="hover:bg-surface-muted transition-colors">
                      <td className="px-5 py-3">
                        {canViewMembers ? (
                          <Link
                            to={`/app/members/${m.member_id}`}
                            className="font-medium hover:text-primary-blue hover:underline transition-colors"
                          >
                            {m.display_name}
                          </Link>
                        ) : (
                          <span className="font-medium text-ink">
                            {m.display_name}
                          </span>
                        )}
                        {m.is_primary && (
                          <span className="ml-2 text-[10px] text-ink-muted">
                            (primary)
                          </span>
                        )}
                      </td>
                      <td className="px-5 py-3 font-mono text-ink-muted">
                        {m.member_number || '—'}
                      </td>
                      <td className="px-5 py-3">
                        <div className="flex items-center gap-1.5 flex-wrap">
                          <span className={`inline-flex items-center rounded-full px-2 py-0.5 text-[10px] font-medium ${
                            isServant
                              ? 'border border-navy-100 bg-navy-50 text-primary-blue'
                              : 'text-ink-secondary'
                          }`}>
                            {formatRole(m.membership_role)}
                          </span>
                          {isDerivedWifeLeader && (
                            <span
                              title="Pastoral couple designation derived from verified marriage to current Household Servant. No separate formal leadership assignment exists."
                              className="inline-flex items-center rounded-full border border-navy-100 bg-navy-50 px-2 py-0.5 text-[10px] font-medium text-primary-blue"
                            >
                              Household Leader
                            </span>
                          )}
                        </div>
                      </td>
                      <td className="px-5 py-3">
                        <span className="inline-flex items-center rounded-full border border-success-600/30 bg-success-50 px-2 py-0.5 text-[10px] font-medium text-success-700">
                          {m.membership_status}
                        </span>
                      </td>
                      <td className="px-5 py-3 text-ink-muted">
                        {m.effective_from}
                      </td>
                      {(canTransferMembers || canEndMembers) && (
                        <td className="px-5 py-3 text-right">
                          <div className="flex items-center justify-end gap-2">
                            {canTransferMembers && (
                              <button
                                type="button"
                                onClick={() => {
                                  setSelectedMember(m);
                                  setIsTransferModalOpen(true);
                                }}
                                className="inline-flex items-center gap-1 rounded px-2 py-1 text-[11px] font-medium text-primary-blue hover:bg-navy-100 hover:text-primary-blue transition-colors"
                              >
                                Transfer
                              </button>
                            )}
                            {canEndMembers && (
                              <button
                                type="button"
                                onClick={() => {
                                  setSelectedMember(m);
                                  setIsEndModalOpen(true);
                                }}
                                className="inline-flex items-center gap-1 rounded px-2 py-1 text-[11px] font-medium text-danger-700 hover:bg-danger-100 hover:text-danger-700 transition-colors"
                              >
                                End Assignment
                              </button>
                            )}
                          </div>
                        </td>
                      )}
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Household Formation */}
      {orgId && householdId && (
        <HouseholdFormationCard
          organizationId={orgId}
          householdId={householdId}
          householdName={household.name}
          pastoralLevel={household.pastoral_level}
          isHouseholdActive={isStatusActive}
          canView={canViewFormation}
          canManage={canManageFormation}
          summary={data.formation_summary ?? null}
          onSuccessToast={triggerToast}
        />
      )}

      {/* Meeting History */}
      {orgId && householdId && (
        <HouseholdMeetingsCard
          organizationId={orgId}
          householdId={householdId}
          householdName={household.name}
          canView={canViewMeetings}
          canManage={canManageMeetings}
          canRecordAttendance={canRecordAttendance}
          onSuccessToast={triggerToast}
        />
      )}

      {orgId && (
        <>
          <EditHouseholdModal
            isOpen={isEditModalOpen}
            onClose={() => setIsEditModalOpen(false)}
            organizationId={orgId}
            householdData={data}
            onSuccessToast={triggerToast}
          />
          <ArchiveHouseholdModal
            isOpen={isArchiveModalOpen}
            onClose={() => setIsArchiveModalOpen(false)}
            organizationId={orgId}
            householdData={data}
            onSuccessToast={triggerToast}
          />
          <AssignHouseholdMemberModal
            isOpen={isAssignModalOpen}
            onClose={() => setIsAssignModalOpen(false)}
            organizationId={orgId}
            householdId={household.id}
            householdName={household.name}
            parentGovernanceName={parent_governance?.parent_node_name}
            onSuccessToast={triggerToast}
          />
          {selectedMember && (
            <>
              <TransferHouseholdMemberModal
                isOpen={isTransferModalOpen}
                onClose={() => {
                  setIsTransferModalOpen(false);
                  setSelectedMember(null);
                }}
                organizationId={orgId}
                memberId={selectedMember.member_id}
                memberName={selectedMember.display_name}
                currentHouseholdId={household.id}
                currentHouseholdName={household.name}
                onSuccessToast={triggerToast}
              />
              <EndHouseholdMembershipModal
                isOpen={isEndModalOpen}
                onClose={() => {
                  setIsEndModalOpen(false);
                  setSelectedMember(null);
                }}
                organizationId={orgId}
                memberId={selectedMember.member_id}
                memberName={selectedMember.display_name}
                currentHouseholdId={household.id}
                currentHouseholdName={household.name}
                onSuccessToast={triggerToast}
              />
            </>
          )}
          <AppointServantLeaderModal
            isOpen={isAppointLeaderModalOpen}
            onClose={() => setIsAppointLeaderModalOpen(false)}
            organizationId={orgId}
            governanceNodeId={household.id}
            governanceNodeName={household.name}
            roleCode="household_servant_leader"
            onSuccessToast={triggerToast}
          />
          {selectedLeader && (
            <>
              <ReplaceServantLeaderModal
                isOpen={isReplaceLeaderModalOpen}
                onClose={() => {
                  setIsReplaceLeaderModalOpen(false);
                  setSelectedLeader(null);
                }}
                organizationId={orgId}
                governanceNodeId={household.id}
                governanceNodeName={household.name}
                currentLeaderMemberId={selectedLeader.member_id}
                currentLeaderDisplayName={selectedLeader.display_name}
                roleCode={(selectedLeader.leadership_role_code as ServantLeaderRoleCode) || 'household_servant_leader'}
                roleName={selectedLeader.leadership_role_name}
                onSuccessToast={triggerToast}
              />
              <ConcludeServantLeaderModal
                isOpen={isConcludeLeaderModalOpen}
                onClose={() => {
                  setIsConcludeLeaderModalOpen(false);
                  setSelectedLeader(null);
                }}
                organizationId={orgId}
                governanceNodeId={household.id}
                governanceNodeName={household.name}
                leadershipAssignmentId={selectedLeader.leadership_assignment_id}
                leaderDisplayName={selectedLeader.display_name}
                roleName={selectedLeader.leadership_role_name}
                onSuccessToast={triggerToast}
              />
              <PastoralPlacementReviewModal
                isOpen={isPlacementModalOpen}
                onClose={() => {
                  setIsPlacementModalOpen(false);
                  setSelectedLeader(null);
                }}
                organizationId={orgId}
                leadershipAssignmentId={selectedLeader.leadership_assignment_id}
                onSuccessToast={triggerToast}
              />
              <ServantLeaderAccessModal
                isOpen={isAccessModalOpen}
                onClose={() => {
                  setIsAccessModalOpen(false);
                  setSelectedLeader(null);
                }}
                organizationId={orgId}
                leadershipAssignmentId={selectedLeader.leadership_assignment_id}
                leaderDisplayName={selectedLeader.display_name}
                roleName={selectedLeader.leadership_role_name}
                governanceNodeName={household.name}
                onSuccessToast={triggerToast}
              />
            </>
          )}
        </>
      )}
    </div>
  );
}
