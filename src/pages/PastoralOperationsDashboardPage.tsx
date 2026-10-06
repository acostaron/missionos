import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useOrganizationContext } from '../hooks/use-organization-context';
import { usePermissions } from '../hooks/use-permissions';
import { Permissions } from '../types/permissions';
import { usePastoralOperationsDashboard } from '../features/households/api/get-pastoral-operations-dashboard';
import { PastoralPlacementReviewModal } from '../features/households/components/PastoralPlacementReviewModal';
import { CreateHouseholdModal } from '../features/households/components/CreateHouseholdModal';
import type {
  PastoralHouseholdSummary,
  PastoralOperationalStatus,
  PastoralCapacityStatus,
} from '../features/households/types';

function formatOperationalStatus(status: PastoralOperationalStatus): {
  label: string;
  className: string;
} {
  switch (status) {
    case 'ready':
      return {
        label: 'Ready',
        className: 'bg-emerald-950/40 text-emerald-300 border-emerald-800/40',
      };
    case 'needs_leader':
      return {
        label: 'Needs Leader',
        className: 'bg-amber-950/40 text-amber-300 border-amber-800/40',
      };
    case 'needs_members':
      return {
        label: 'Needs Members',
        className: 'bg-sky-950/40 text-sky-300 border-sky-800/40',
      };
    case 'at_capacity':
      return {
        label: 'At Capacity',
        className: 'bg-indigo-950/40 text-indigo-300 border-indigo-800/40',
      };
    case 'not_accepting':
      return {
        label: 'Not Accepting',
        className: 'bg-slate-800 text-slate-300 border-slate-700',
      };
    case 'placement_review_required':
      return {
        label: 'Review Required',
        className: 'bg-rose-950/40 text-rose-300 border-rose-800/40',
      };
    case 'inactive':
    default:
      return {
        label: 'Inactive',
        className: 'bg-slate-900 text-slate-500 border-slate-800',
      };
  }
}

function formatCapacityStatus(status: PastoralCapacityStatus): {
  label: string;
  className: string;
} {
  switch (status) {
    case 'available':
      return { label: 'Available', className: 'text-emerald-400' };
    case 'at_target':
      return { label: 'At Target', className: 'text-indigo-300' };
    case 'full':
      return { label: 'Full', className: 'text-amber-400' };
    case 'not_accepting':
      return { label: 'Closed', className: 'text-slate-400' };
  }
}

export default function PastoralOperationsDashboardPage() {
  const { activeOrganization } = useOrganizationContext();
  const { hasPermission, isLoading: isPermLoading } = usePermissions();

  const [activePlacementAssignmentId, setActivePlacementAssignmentId] = useState<string | null>(null);
  const [isCreateHouseholdOpen, setIsCreateHouseholdOpen] = useState(false);
  const [levelFilter, setLevelFilter] = useState<string>('all');
  const [statusFilter, setStatusFilter] = useState<string>('all');

  const orgId = activeOrganization?.id ?? null;
  const canViewDashboard = !isPermLoading && hasPermission(Permissions.LeadershipPastoralDashboardView);
  const canReviewPlacement = !isPermLoading && hasPermission(Permissions.LeadershipPastoralPlacementReview);
  const canCreateHousehold = !isPermLoading && hasPermission(Permissions.HouseholdsRecordsCreate);

  const { data, isLoading, error } = usePastoralOperationsDashboard(
    orgId,
    null,
    canViewDashboard
  );

  if (!canViewDashboard && !isPermLoading) {
    return (
      <div className="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
        <div className="rounded-xl border border-slate-800 bg-slate-900/50 p-6 text-center">
          <p className="text-sm text-slate-400">
            You do not have permission to view the pastoral operations dashboard.
          </p>
        </div>
      </div>
    );
  }

  if (isLoading) {
    return (
      <div className="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8 space-y-6">
        <div className="h-10 w-64 animate-pulse rounded-lg bg-slate-800/60" />
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
          {[1, 2, 3, 4].map((i) => (
            <div key={i} className="h-28 animate-pulse rounded-xl bg-slate-800/40 border border-slate-700/60" />
          ))}
        </div>
        <div className="h-64 animate-pulse rounded-xl bg-slate-800/40 border border-slate-700/60" />
      </div>
    );
  }

  if (error || !data) {
    return (
      <div className="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
        <div className="rounded-xl border border-rose-900/50 bg-rose-950/20 p-6 text-center">
          <p className="text-sm text-rose-300">
            Failed to load pastoral operations dashboard: {error instanceof Error ? error.message : 'Unknown error'}
          </p>
        </div>
      </div>
    );
  }

  const {
    identity,
    care_responsibilities,
    household_summary,
    leadership_vacancies,
    capacity_summary,
    operational_summary,
    placement_review_summary,
    unassigned_members_count,
    meeting_operations_summary,
    formation_operations_summary,
  } = data;

  const meetingOps = meeting_operations_summary ?? {
    upcoming_meetings: 0,
    meetings_this_month: 0,
    attendance_pending: 0,
    households_without_meeting_history: 0,
    households_overdue: 0,
    member_follow_up_signals: 0,
  };

  const formationOps = formation_operations_summary ?? {
    households_with_no_plan: 0,
    topics_planned: 0,
    topics_completed_this_month: 0,
    topics_due: 0,
    topics_overdue: 0,
  };

  const filteredHouseholds = household_summary.filter((hh: PastoralHouseholdSummary) => {
    if (levelFilter !== 'all' && hh.pastoral_level !== levelFilter) return false;
    if (statusFilter !== 'all' && hh.operational_status !== statusFilter) return false;
    return true;
  });

  return (
    <div className="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8 space-y-8">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 border-b border-slate-800 pb-5">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-slate-100">
            Pastoral Operations
          </h1>
          <p className="text-xs text-slate-400 mt-1">
            Operational visibility, leader nourishment structure, and echelon care responsibilities.
          </p>
        </div>

        <div className="flex items-center gap-3">
          <Link
            to="/app/households/unassigned"
            className="inline-flex items-center gap-1.5 rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-xs font-semibold text-slate-200 hover:bg-slate-700 transition-colors"
          >
            <span>Unassigned Members</span>
            <span className="rounded-full bg-slate-900 px-2 py-0.5 text-[11px] font-bold text-amber-300 border border-slate-700">
              {unassigned_members_count}
            </span>
          </Link>

          {canCreateHousehold && (
            <button
              type="button"
              onClick={() => setIsCreateHouseholdOpen(true)}
              className="inline-flex items-center gap-1.5 rounded-lg bg-indigo-600 px-3.5 py-2 text-xs font-semibold text-white hover:bg-indigo-500 transition-colors shadow-sm"
            >
              + Create Household
            </button>
          )}
        </div>
      </div>

      {/* Leader Personalized Cards (Where I Serve / Where I Receive Pastoral Care) */}
      {identity.has_linked_member && (
        <div className="space-y-4">
          <h2 className="text-xs font-semibold uppercase tracking-wider text-slate-400">
            Leader Perspective · {identity.display_name}
          </h2>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {/* Where I Serve Card */}
            <div className="rounded-xl border border-slate-800 bg-slate-900/60 p-5 space-y-3">
              <div className="flex items-center justify-between border-b border-slate-800 pb-2">
                <span className="text-xs font-semibold uppercase tracking-wider text-indigo-400">
                  Where I Serve
                </span>
                <span className="text-[10px] text-slate-500">Formal Office</span>
              </div>

              {identity.serving_assignments.length === 0 ? (
                <p className="text-xs text-slate-500 italic py-2">
                  No active formal servant leader appointments assigned to this profile.
                </p>
              ) : (
                <div className="space-y-2.5">
                  {identity.serving_assignments.map((asg) => (
                    <div
                      key={asg.leadership_assignment_id}
                      className="rounded-lg border border-slate-700/60 bg-slate-800/40 p-3 text-xs flex justify-between items-center"
                    >
                      <div>
                        <p className="font-semibold text-slate-200">{asg.role_name}</p>
                        <p className="text-[11px] text-slate-400">
                          Scope: {asg.governance_node_name}{' '}
                          {asg.pastoral_level && `(${asg.pastoral_level})`}
                        </p>
                      </div>
                      <span className="text-[10px] font-mono text-slate-400">
                        Since {asg.effective_from}
                      </span>
                    </div>
                  ))}
                </div>
              )}
            </div>

            {/* Where I Receive Pastoral Care Card */}
            <div className="rounded-xl border border-slate-800 bg-slate-900/60 p-5 space-y-3">
              <div className="flex items-center justify-between border-b border-slate-800 pb-2">
                <span className="text-xs font-semibold uppercase tracking-wider text-emerald-400">
                  Where I Receive Pastoral Care
                </span>
                <span className="text-[10px] text-slate-500">Nourishment Household</span>
              </div>

              {identity.pastoral_membership ? (
                <div className="space-y-2 text-xs">
                  <div className="flex justify-between items-center">
                    <span className="font-semibold text-slate-200">
                      {identity.pastoral_membership.household_name}
                    </span>
                    <span className="rounded bg-slate-800 px-2 py-0.5 text-[10px] font-medium uppercase text-slate-300">
                      Level: {identity.pastoral_membership.pastoral_level}
                    </span>
                  </div>

                  <p className="text-[11px] text-slate-400">
                    Scope: {identity.pastoral_membership.scope_node_name ?? 'Root Area'}
                  </p>

                  <div className="text-[11px] text-slate-400 pt-1 border-t border-slate-800">
                    <span>Meeting: {identity.pastoral_membership.meeting_frequency}</span>
                    {identity.pastoral_membership.meeting_start_time && (
                      <span className="ml-2">at {identity.pastoral_membership.meeting_start_time.slice(0, 5)}</span>
                    )}
                  </div>
                </div>
              ) : (
                <div className="py-2 space-y-2">
                  <p className="text-xs text-amber-300/90 font-medium">
                    Pastoral household placement has not yet been established.
                  </p>
                  <p className="text-[11px] text-slate-400">
                    Every servant leader receives pastoral nourishment in a higher-echelon household.
                  </p>
                  {identity.pastoral_household_placement_needed && canReviewPlacement && identity.serving_assignments[0] && (
                    <button
                      type="button"
                      onClick={() => setActivePlacementAssignmentId(identity.serving_assignments[0]?.leadership_assignment_id ?? null)}
                      className="mt-1 rounded bg-amber-950/60 border border-amber-700/60 px-2.5 py-1 text-[11px] font-semibold text-amber-200 hover:bg-amber-900/60 transition-colors"
                    >
                      Review Placement Guidance
                    </button>
                  )}
                </div>
              )}
            </div>
          </div>

          {/* People I Care For Section */}
          {care_responsibilities.length > 0 && (
            <div className="rounded-xl border border-slate-800 bg-slate-900/60 p-5 space-y-4">
              <h3 className="text-xs font-semibold uppercase tracking-wider text-slate-400 border-b border-slate-800 pb-2">
                People I Am Pastorally Responsible For
              </h3>

              <div className="space-y-4">
                {care_responsibilities.map((resp, idx) => (
                  <div key={idx} className="space-y-2">
                    <p className="text-xs font-medium text-slate-300">
                      Scope: <span className="font-semibold text-white">{resp.scope_name}</span> ({resp.responsibility_level})
                    </p>

                    {resp.details.type === 'household_members' && (
                      <div className="text-xs space-y-2">
                        <p className="text-[11px] text-slate-400">
                          {resp.details.member_count ?? 0} active members in this household:
                        </p>
                        <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-2">
                          {(resp.details.members ?? []).map((m) => (
                            <div key={m.member_id} className="rounded border border-slate-800 bg-slate-800/30 p-2 text-xs">
                              <p className="font-medium text-slate-200">{m.display_name}</p>
                              <p className="text-[10px] text-slate-500 uppercase">{m.membership_role}</p>
                            </div>
                          ))}
                        </div>
                      </div>
                    )}

                    {(resp.details.type === 'household_leaders' ||
                      resp.details.type === 'unit_leaders' ||
                      resp.details.type === 'chapter_leaders') && (
                      <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-2 text-xs">
                        {(resp.details.leaders ?? []).map((l, lIdx) => (
                          <div key={lIdx} className="rounded border border-slate-800 bg-slate-800/30 p-2.5 space-y-1">
                            <span className="text-[10px] font-semibold uppercase text-indigo-400 block">
                              {l.derived_pastoral_title}
                            </span>
                            <p className="font-semibold text-slate-200">
                              {l.leader_name}
                              {l.derived_spouse_name && ` & ${l.derived_spouse_name}`}
                            </p>
                            <p className="text-[10px] text-slate-500">
                              {l.household_name ?? l.unit_name ?? l.chapter_name}
                            </p>
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      )}

      {/* Operational Metrics Cards */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
        <div className="rounded-xl border border-slate-800 bg-slate-900/60 p-4 space-y-1">
          <p className="text-xs text-slate-400">Households Ready</p>
          <p className="text-2xl font-bold text-emerald-400">{operational_summary.ready}</p>
          <p className="text-[11px] text-slate-500">{operational_summary.total} total active/configured</p>
        </div>

        <div className="rounded-xl border border-slate-800 bg-slate-900/60 p-4 space-y-1">
          <p className="text-xs text-slate-400">Leadership Vacancies</p>
          <p className={`text-2xl font-bold ${leadership_vacancies.length > 0 ? 'text-amber-400' : 'text-slate-100'}`}>
            {leadership_vacancies.length}
          </p>
          <p className="text-[11px] text-slate-500">Member HH, Unit, Chapter, Area</p>
        </div>

        <div className="rounded-xl border border-slate-800 bg-slate-900/60 p-4 space-y-1">
          <p className="text-xs text-slate-400">Placement Reviews</p>
          <p className={`text-2xl font-bold ${placement_review_summary.total > 0 ? 'text-rose-400' : 'text-slate-100'}`}>
            {placement_review_summary.total}
          </p>
          <p className="text-[11px] text-slate-500">
            {placement_review_summary.manual_review_required} require manual review
          </p>
        </div>

        <div className="rounded-xl border border-slate-800 bg-slate-900/60 p-4 space-y-1">
          <p className="text-xs text-slate-400">Capacity Alerts</p>
          <p className={`text-2xl font-bold ${capacity_summary.full > 0 ? 'text-amber-400' : 'text-slate-100'}`}>
            {capacity_summary.full} Full
          </p>
          <p className="text-[11px] text-slate-500">
            {capacity_summary.available} open for placement
          </p>
        </div>
      </div>

      {/* Meeting Operations Summary */}
      <div className="space-y-3">
        <h2 className="text-xs font-semibold uppercase tracking-wider text-slate-400">
          Meeting Operations
        </h2>
        <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
          <div className="rounded-xl border border-slate-800 bg-slate-900/60 p-4 space-y-1">
            <p className="text-xs text-slate-400">Upcoming</p>
            <p className="text-2xl font-bold text-indigo-300">{meetingOps.upcoming_meetings}</p>
            <p className="text-[11px] text-slate-500">Scheduled meetings</p>
          </div>

          <div className="rounded-xl border border-slate-800 bg-slate-900/60 p-4 space-y-1">
            <p className="text-xs text-slate-400">This Month</p>
            <p className="text-2xl font-bold text-emerald-400">{meetingOps.meetings_this_month}</p>
            <p className="text-[11px] text-slate-500">Completed meetings</p>
          </div>

          <div className={`rounded-xl border p-4 space-y-1 ${
            meetingOps.attendance_pending > 0
              ? 'border-amber-800/60 bg-amber-950/20'
              : 'border-slate-800 bg-slate-900/60'
          }`}>
            <p className="text-xs text-slate-400">Attendance Pending</p>
            <p className={`text-2xl font-bold ${
              meetingOps.attendance_pending > 0 ? 'text-amber-300' : 'text-slate-100'
            }`}>{meetingOps.attendance_pending}</p>
            <p className="text-[11px] text-slate-500">Completed, not recorded</p>
          </div>

          <div className={`rounded-xl border p-4 space-y-1 ${
            meetingOps.households_without_meeting_history > 0
              ? 'border-slate-700 bg-slate-900/60'
              : 'border-slate-800 bg-slate-900/60'
          }`}>
            <p className="text-xs text-slate-400">No Meeting History</p>
            <p className={`text-2xl font-bold ${
              meetingOps.households_without_meeting_history > 0 ? 'text-slate-300' : 'text-slate-100'
            }`}>{meetingOps.households_without_meeting_history}</p>
            <p className="text-[11px] text-slate-500">Households never met</p>
          </div>

          <div className={`rounded-xl border p-4 space-y-1 ${
            meetingOps.households_overdue > 0
              ? 'border-rose-900/50 bg-rose-950/20'
              : 'border-slate-800 bg-slate-900/60'
          }`}>
            <p className="text-xs text-slate-400">Overdue</p>
            <p className={`text-2xl font-bold ${
              meetingOps.households_overdue > 0 ? 'text-rose-400' : 'text-slate-100'
            }`}>{meetingOps.households_overdue}</p>
            <p className="text-[11px] text-slate-500">Past scheduled frequency</p>
          </div>

          <div className={`rounded-xl border p-4 space-y-1 ${
            meetingOps.member_follow_up_signals > 0
              ? 'border-amber-800/60 bg-amber-950/20'
              : 'border-slate-800 bg-slate-900/60'
          }`}>
            <p className="text-xs text-slate-400">Follow-Up Signals</p>
            <p className={`text-2xl font-bold ${
              meetingOps.member_follow_up_signals > 0 ? 'text-amber-300' : 'text-slate-100'
            }`}>{meetingOps.member_follow_up_signals}</p>
            <p className="text-[11px] text-slate-500">Members with 2+ absences</p>
          </div>
        </div>
      </div>

      {/* Formation Operations Summary */}
      <div className="space-y-3">
        <h2 className="text-xs font-semibold uppercase tracking-wider text-slate-400">
          Formation Operations
        </h2>
        <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3">
          <div className="rounded-xl border border-slate-800 bg-slate-900/60 p-4 space-y-1">
            <p className="text-xs text-slate-400">Households With No Plan</p>
            <p className="text-2xl font-bold text-slate-100">{formationOps.households_with_no_plan}</p>
          </div>
          <div className="rounded-xl border border-slate-800 bg-slate-900/60 p-4 space-y-1">
            <p className="text-xs text-slate-400">Topics Planned</p>
            <p className="text-2xl font-bold text-indigo-300">{formationOps.topics_planned}</p>
          </div>
          <div className="rounded-xl border border-slate-800 bg-slate-900/60 p-4 space-y-1">
            <p className="text-xs text-slate-400">Completed This Month</p>
            <p className="text-2xl font-bold text-emerald-400">{formationOps.topics_completed_this_month}</p>
          </div>
          <div className={`rounded-xl border p-4 space-y-1 ${
            formationOps.topics_due > 0
              ? 'border-amber-800/60 bg-amber-950/20'
              : 'border-slate-800 bg-slate-900/60'
          }`}>
            <p className="text-xs text-slate-400">Topics Due</p>
            <p className={`text-2xl font-bold ${
              formationOps.topics_due > 0 ? 'text-amber-300' : 'text-slate-100'
            }`}>{formationOps.topics_due}</p>
          </div>
          <div className={`rounded-xl border p-4 space-y-1 ${
            formationOps.topics_overdue > 0
              ? 'border-rose-900/50 bg-rose-950/20'
              : 'border-slate-800 bg-slate-900/60'
          }`}>
            <p className="text-xs text-slate-400">Topics Overdue</p>
            <p className={`text-2xl font-bold ${
              formationOps.topics_overdue > 0 ? 'text-rose-400' : 'text-slate-100'
            }`}>{formationOps.topics_overdue}</p>
          </div>
        </div>
      </div>
      {/* Leadership Vacancies List (if any) */}
      {leadership_vacancies.length > 0 && (
        <div className="rounded-xl border border-amber-900/50 bg-amber-950/20 p-5 space-y-3">
          <div className="flex items-center justify-between border-b border-amber-800/40 pb-2">
            <div className="flex items-center gap-2">
              <span className="text-xs font-semibold uppercase tracking-wider text-amber-300">
                Action Required · Leadership Vacancies ({leadership_vacancies.length})
              </span>
            </div>
            <span className="text-[10px] text-amber-400/80">Servant leader appointment needed</span>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3 text-xs">
            {leadership_vacancies.map((vac) => (
              <div
                key={vac.governance_node_id}
                className="rounded-lg border border-amber-800/40 bg-slate-900/60 p-3 space-y-1"
              >
                <div className="flex justify-between items-center">
                  <span className="font-semibold text-slate-200">{vac.governance_node_name}</span>
                  <span className="rounded bg-amber-950/60 px-1.5 py-0.5 text-[10px] font-medium text-amber-300 border border-amber-800/40">
                    Vacant
                  </span>
                </div>
                <p className="text-[11px] text-slate-400">Office: {vac.role_name}</p>
                {vac.pastoral_level === 'member' && (
                  <Link
                    to={`/app/households/${vac.governance_node_id}`}
                    className="inline-block text-[11px] text-indigo-400 hover:underline pt-1"
                  >
                    View Household Profile &rarr;
                  </Link>
                )}
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Placement Reviews Actionable Queue (if any) */}
      {placement_review_summary.total > 0 && canReviewPlacement && (
        <div className="rounded-xl border border-rose-900/50 bg-rose-950/20 p-5 space-y-3">
          <div className="flex items-center justify-between border-b border-rose-800/40 pb-2">
            <span className="text-xs font-semibold uppercase tracking-wider text-rose-300">
              Servant Leaders Needing Placement Review ({placement_review_summary.total})
            </span>
            <span className="text-[10px] text-rose-400/80">Couples context &amp; echelon alignment</span>
          </div>

          <div className="space-y-2">
            {placement_review_summary.actionable_items.map((item) => (
              <div
                key={item.leadership_assignment_id}
                className="rounded-lg border border-rose-800/30 bg-slate-900/60 p-3 text-xs flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3"
              >
                <div>
                  <p className="font-semibold text-slate-200">
                    {item.leader_name}{' '}
                    <span className="text-[11px] font-normal text-slate-400">({item.role_name})</span>
                  </p>
                  <p className="text-[11px] text-slate-400">
                    Recommended: {item.recommended_pastoral_level} Household under {item.recommended_scope_name}
                  </p>
                  {item.couples_context_status === 'ambiguous' && (
                    <p className="text-[10px] text-amber-400 mt-0.5">
                      ⚠️ Couples ministry context requires review before placement.
                    </p>
                  )}
                </div>

                <button
                  type="button"
                  onClick={() => setActivePlacementAssignmentId(item.leadership_assignment_id)}
                  className="rounded-lg bg-indigo-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-indigo-500 transition-colors self-start sm:self-auto"
                >
                  Review Placement
                </button>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Household Operations Table Section */}
      <div className="space-y-4">
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <h2 className="text-sm font-bold tracking-tight text-slate-100">
            Household Operations Table ({filteredHouseholds.length})
          </h2>

          <div className="flex items-center gap-2">
            {/* Pastoral Level Filter */}
            <select
              value={levelFilter}
              onChange={(e) => setLevelFilter(e.target.value)}
              className="rounded-lg border border-slate-700 bg-slate-800 px-2.5 py-1.5 text-xs text-slate-200 focus:outline-none focus:ring-1 focus:ring-indigo-500"
            >
              <option value="all">All Pastoral Levels</option>
              <option value="member">Member</option>
              <option value="unit">Unit</option>
              <option value="chapter">Chapter</option>
              <option value="area">Area</option>
              <option value="fraternal">Fraternal</option>
            </select>

            {/* Operational Status Filter */}
            <select
              value={statusFilter}
              onChange={(e) => setStatusFilter(e.target.value)}
              className="rounded-lg border border-slate-700 bg-slate-800 px-2.5 py-1.5 text-xs text-slate-200 focus:outline-none focus:ring-1 focus:ring-indigo-500"
            >
              <option value="all">All Operational Statuses</option>
              <option value="ready">Ready</option>
              <option value="needs_leader">Needs Leader</option>
              <option value="needs_members">Needs Members</option>
              <option value="at_capacity">At Capacity</option>
              <option value="not_accepting">Not Accepting</option>
            </select>
          </div>
        </div>

        {/* Empty State: Zero Households */}
        {household_summary.length === 0 ? (
          <div className="rounded-xl border border-slate-800 bg-slate-900/40 p-12 text-center space-y-4">
            <div className="mx-auto w-12 h-12 rounded-full bg-slate-800 flex items-center justify-center text-slate-400">
              <svg className="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6" />
              </svg>
            </div>
            <div className="space-y-1">
              <h3 className="text-base font-semibold text-slate-200">
                No pastoral households have been created yet.
              </h3>
              <p className="text-xs text-slate-400 max-w-md mx-auto">
                Begin by creating Member Households under Units, or higher-echelon households (Unit, Chapter, Area, Fraternal) for servant leader nourishment.
              </p>
            </div>
            {canCreateHousehold && (
              <button
                type="button"
                onClick={() => setIsCreateHouseholdOpen(true)}
                className="inline-flex items-center gap-1.5 rounded-lg bg-indigo-600 px-4 py-2 text-xs font-semibold text-white hover:bg-indigo-500 transition-colors"
              >
                + Create First Household
              </button>
            )}
          </div>
        ) : filteredHouseholds.length === 0 ? (
          <div className="rounded-xl border border-slate-800 bg-slate-900/40 p-8 text-center">
            <p className="text-xs text-slate-400">No households match the selected filters.</p>
          </div>
        ) : (
          <div className="overflow-x-auto rounded-xl border border-slate-800 bg-slate-900/60">
            <table className="w-full text-left text-xs">
              <thead className="border-b border-slate-800 bg-slate-900/80 text-[11px] font-semibold uppercase tracking-wider text-slate-400">
                <tr>
                  <th className="px-4 py-3">Household</th>
                  <th className="px-4 py-3">Level</th>
                  <th className="px-4 py-3">Scope</th>
                  <th className="px-4 py-3">Leadership</th>
                  <th className="px-4 py-3">Members</th>
                  <th className="px-4 py-3">Capacity</th>
                  <th className="px-4 py-3">Status</th>
                  <th className="px-4 py-3 text-right">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-800 text-slate-300">
                {filteredHouseholds.map((hh) => {
                  const opStatus = formatOperationalStatus(hh.operational_status);
                  const capStatus = formatCapacityStatus(hh.capacity_status);

                  return (
                    <tr key={hh.household_id} className="hover:bg-slate-800/40 transition-colors">
                      <td className="px-4 py-3">
                        <Link
                          to={`/app/households/${hh.household_id}`}
                          className="font-medium text-slate-200 hover:text-indigo-400 transition-colors"
                        >
                          {hh.household_name}
                        </Link>
                        {hh.is_couple_household && (
                          <span className="block text-[10px] text-indigo-400">Couples</span>
                        )}
                      </td>

                      <td className="px-4 py-3">
                        <span className="rounded bg-slate-800 px-2 py-0.5 text-[10px] font-medium uppercase text-slate-300">
                          {hh.pastoral_level}
                        </span>
                      </td>

                      <td className="px-4 py-3 text-slate-400 text-[11px]">
                        {hh.scope_node_name ?? '—'}
                      </td>

                      <td className="px-4 py-3 text-[11px]">
                        <span className={hh.leadership_status === 'vacant' ? 'text-amber-400' : 'text-slate-200'}>
                          {hh.leader_display_label}
                        </span>
                      </td>

                      <td className="px-4 py-3 text-[11px]">
                        <span className="font-semibold text-slate-100">{hh.member_count}</span>
                        {hh.target_member_count && (
                          <span className="text-slate-500"> / {hh.target_member_count}</span>
                        )}
                      </td>

                      <td className="px-4 py-3 text-[11px]">
                        <span className={capStatus.className}>{capStatus.label}</span>
                      </td>

                      <td className="px-4 py-3">
                        <span
                          className={`inline-block rounded-full border px-2 py-0.5 text-[10px] font-semibold ${opStatus.className}`}
                        >
                          {opStatus.label}
                        </span>
                      </td>

                      <td className="px-4 py-3 text-right">
                        <Link
                          to={`/app/households/${hh.household_id}`}
                          className="rounded px-2.5 py-1 text-[11px] font-medium text-slate-300 hover:text-white bg-slate-800 hover:bg-slate-700 transition-colors"
                        >
                          View &rarr;
                        </Link>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Review Placement Modal Integration */}
      {activePlacementAssignmentId && (
        <PastoralPlacementReviewModal
          isOpen={true}
          onClose={() => setActivePlacementAssignmentId(null)}
          organizationId={orgId ?? ''}
          leadershipAssignmentId={activePlacementAssignmentId}
          onSuccessToast={() => {
            setActivePlacementAssignmentId(null);
          }}
        />
      )}

      {/* Create Household Modal Integration */}
      {isCreateHouseholdOpen && (
        <CreateHouseholdModal
          isOpen={true}
          onClose={() => setIsCreateHouseholdOpen(false)}
          organizationId={orgId ?? ''}
          onSuccessToast={() => {
            setIsCreateHouseholdOpen(false);
          }}
        />
      )}

    </div>
  );
}
