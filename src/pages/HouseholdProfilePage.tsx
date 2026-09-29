import { Link, useParams } from 'react-router-dom';
import { useOrganizationContext } from '../hooks/use-organization-context';
import { usePermissions } from '../hooks/use-permissions';
import { Permissions } from '../types/permissions';
import { useHouseholdProfile } from '../features/households/api/get-household-profile';

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

  const orgId = activeOrganization?.id ?? null;
  const canViewHouseholds = !isPermLoading && hasPermission(Permissions.HouseholdsRecordsView);
  const canViewMembers = !isPermLoading && hasPermission(Permissions.MembersRecordsView);

  const {
    data,
    isLoading,
    error,
  } = useHouseholdProfile(
    orgId,
    householdId ?? null,
    canViewHouseholds && !!householdId
  );

  if (!canViewHouseholds && !isPermLoading) {
    return (
      <div className="mx-auto max-w-5xl px-4 py-8 sm:px-6 lg:px-8">
        <div className="rounded-xl border border-slate-800 bg-slate-900/50 p-6 text-center">
          <p className="text-sm text-slate-400">
            You do not have permission to view household records.
          </p>
        </div>
      </div>
    );
  }

  if (isLoading) {
    return (
      <div className="mx-auto max-w-5xl px-4 py-8 sm:px-6 lg:px-8 space-y-6">
        <div className="h-10 w-48 animate-pulse rounded-lg bg-slate-800/60" />
        <div className="h-40 animate-pulse rounded-xl bg-slate-800/40 border border-slate-700/60" />
        <div className="h-64 animate-pulse rounded-xl bg-slate-800/40 border border-slate-700/60" />
      </div>
    );
  }

  if (error || !data) {
    return (
      <div className="mx-auto max-w-5xl px-4 py-8 sm:px-6 lg:px-8 space-y-4">
        <Link
          to="/app/households"
          className="inline-flex items-center gap-1.5 text-xs text-slate-400 hover:text-slate-200 transition-colors"
        >
          <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
          </svg>
          Back to Households
        </Link>
        <div className="rounded-xl border border-slate-800 bg-slate-900/40 p-10 text-center">
          <h2 className="text-base font-semibold text-slate-200">
            Household Not Found or Inaccessible
          </h2>
          <p className="mt-1 text-xs text-slate-400">
            This household may not exist or does not fall within your authorized pastoral scope.
          </p>
        </div>
      </div>
    );
  }

  const { household, parent_governance, leaders, members, counts } = data;
  const isStatusActive = household.lifecycle_status === 'active';
  const meetingDay = formatDayOfWeek(household.meeting_day_of_week);
  const meetingFreq = formatFrequency(household.meeting_frequency);

  return (
    <div className="mx-auto max-w-5xl px-4 py-8 sm:px-6 lg:px-8 space-y-6">
      {/* Navigation Breadcrumb */}
      <div>
        <Link
          to="/app/households"
          className="inline-flex items-center gap-1.5 text-xs text-slate-400 hover:text-slate-200 transition-colors"
        >
          <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
          </svg>
          Back to Households
        </Link>
      </div>

      {/* Header Banner */}
      <div className="rounded-xl border border-slate-700 bg-slate-800/60 p-6 shadow-sm">
        <div className="flex flex-col sm:flex-row sm:items-start justify-between gap-4">
          <div className="space-y-1.5">
            <div className="flex items-center gap-3 flex-wrap">
              <h1 className="text-2xl font-bold tracking-tight text-slate-100">
                {household.name}
              </h1>
              <span className="font-mono text-xs text-slate-400">
                {household.code}
              </span>
              <span
                className={`inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-medium ${
                  isStatusActive
                    ? 'border-emerald-700/60 bg-emerald-950/40 text-emerald-300'
                    : 'border-slate-600 bg-slate-800 text-slate-400'
                }`}
              >
                {household.lifecycle_status}
              </span>
            </div>

            <p className="text-xs text-slate-400">
              Category:{' '}
              <span className="text-slate-200 capitalize">
                {household.household_category}
              </span>
              {household.language_code && (
                <>
                  <span className="mx-2 text-slate-600">•</span>
                  <span>Language: {household.language_code.toUpperCase()}</span>
                </>
              )}
              {household.is_couple_household && (
                <>
                  <span className="mx-2 text-slate-600">•</span>
                  <span className="text-indigo-300 font-medium">Couples Household</span>
                </>
              )}
            </p>
          </div>

          {/* Quick counts */}
          <div className="flex items-center gap-4 bg-slate-900/50 rounded-lg p-3 border border-slate-700/60">
            <div className="text-center sm:text-right">
              <p className="text-xs text-slate-400">Active Members</p>
              <p className="text-lg font-bold text-slate-100">
                {counts.active_member_count}{' '}
                {counts.target_member_count && (
                  <span className="text-xs font-normal text-slate-400">
                    / {counts.target_member_count}
                  </span>
                )}
              </p>
            </div>
            <div className="h-8 w-px bg-slate-700/60" />
            <div className="text-center sm:text-left">
              <p className="text-xs text-slate-400">Accepting Members</p>
              <p className={`text-xs font-semibold ${counts.accepts_new_members ? 'text-emerald-400' : 'text-amber-400'}`}>
                {counts.accepts_new_members ? 'Open' : 'Full'}
              </p>
            </div>
          </div>
        </div>
      </div>

      {/* Overview Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        {/* Parent Governance & Schedule */}
        <div className="rounded-xl border border-slate-700 bg-slate-800/60 p-5 space-y-4">
          <h2 className="text-xs font-semibold uppercase tracking-wider text-slate-400 border-b border-slate-700 pb-2.5">
            Placement & Schedule
          </h2>

          <div className="space-y-3 text-xs">
            <div className="flex justify-between items-center">
              <span className="text-slate-400">Parent Governance</span>
              <span className="font-medium text-slate-200">
                {parent_governance ? (
                  <>
                    {parent_governance.parent_node_name}{' '}
                    <span className="text-[10px] uppercase text-slate-500">
                      ({parent_governance.parent_node_type})
                    </span>
                  </>
                ) : (
                  <span className="text-slate-500 italic">None</span>
                )}
              </span>
            </div>

            <div className="flex justify-between items-center">
              <span className="text-slate-400">Meeting Frequency</span>
              <span className="font-medium text-slate-200">{meetingFreq}</span>
            </div>

            {meetingDay && (
              <div className="flex justify-between items-center">
                <span className="text-slate-400">Meeting Day & Time</span>
                <span className="font-medium text-slate-200">
                  {meetingDay}
                  {household.meeting_start_time && ` at ${household.meeting_start_time.slice(0, 5)}`}
                  {household.meeting_timezone_name && ` (${household.meeting_timezone_name})`}
                </span>
              </div>
            )}

            <div className="flex justify-between items-center">
              <span className="text-slate-400">Location Type</span>
              <span className="font-medium text-slate-200 capitalize">
                {household.meeting_location_type || 'Residence'}
              </span>
            </div>

            {household.meeting_location_text && (
              <div className="flex justify-between items-center">
                <span className="text-slate-400">Location Details</span>
                <span className="font-medium text-slate-200 text-right max-w-xs truncate">
                  {household.meeting_location_text}
                </span>
              </div>
            )}
          </div>
        </div>

        {/* Pastoral Leadership */}
        <div className="rounded-xl border border-slate-700 bg-slate-800/60 p-5 space-y-4">
          <h2 className="text-xs font-semibold uppercase tracking-wider text-slate-400 border-b border-slate-700 pb-2.5">
            Pastoral Leadership
          </h2>

          {leaders.length === 0 ? (
            <p className="text-xs text-slate-500 italic py-2">
              No formal leaders currently assigned.
            </p>
          ) : (
            <div className="space-y-3">
              {leaders.map((lead) => (
                <div
                  key={lead.leadership_assignment_id}
                  className="rounded-lg border border-slate-700/60 bg-slate-900/40 p-3 flex items-center justify-between text-xs"
                >
                  <div>
                    <p className="font-medium text-slate-100">
                      {lead.display_name}
                    </p>
                    <p className="text-[10px] text-slate-400 mt-0.5">
                      Since {lead.effective_from}
                    </p>
                  </div>
                  <span className="inline-flex items-center rounded-full border border-indigo-700/60 bg-indigo-950/40 px-2 py-0.5 text-[10px] font-medium text-indigo-300">
                    {lead.leadership_role_name}
                  </span>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      {/* Active Member Roster */}
      <div className="rounded-xl border border-slate-700 bg-slate-800/60 overflow-hidden">
        <div className="flex items-center justify-between border-b border-slate-700 px-5 py-3.5">
          <div className="flex items-center gap-3">
            <h2 className="text-sm font-semibold uppercase tracking-wider text-slate-300">
              Active Household Roster
            </h2>
            <span className="rounded-full bg-slate-700/80 px-2 py-0.5 text-[10px] font-medium text-slate-300">
              {members.length} {members.length === 1 ? 'member' : 'members'}
            </span>
          </div>
        </div>

        {members.length === 0 ? (
          <div className="p-8 text-center text-xs text-slate-500 italic">
            No active members assigned to this household.
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left text-xs">
              <thead className="bg-slate-900/60 text-slate-400 border-b border-slate-700/60">
                <tr>
                  <th className="px-5 py-3 font-medium">Member</th>
                  <th className="px-5 py-3 font-medium">Number</th>
                  <th className="px-5 py-3 font-medium">Household Role</th>
                  <th className="px-5 py-3 font-medium">Status</th>
                  <th className="px-5 py-3 font-medium">Joined Date</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-700/40 text-slate-200">
                {members.map((m) => {
                  const isServant = m.membership_role === 'servant' || m.membership_role === 'assistant_servant';

                  return (
                    <tr key={m.household_membership_id} className="hover:bg-slate-800/40 transition-colors">
                      <td className="px-5 py-3">
                        {canViewMembers ? (
                          <Link
                            to={`/app/members/${m.member_id}`}
                            className="font-medium hover:text-indigo-400 hover:underline transition-colors"
                          >
                            {m.display_name}
                          </Link>
                        ) : (
                          <span className="font-medium text-slate-200">
                            {m.display_name}
                          </span>
                        )}
                        {m.is_primary && (
                          <span className="ml-2 text-[10px] text-slate-500">
                            (primary)
                          </span>
                        )}
                      </td>
                      <td className="px-5 py-3 font-mono text-slate-400">
                        {m.member_number || '—'}
                      </td>
                      <td className="px-5 py-3">
                        <span className={`inline-flex items-center rounded-full px-2 py-0.5 text-[10px] font-medium ${
                          isServant
                            ? 'border border-indigo-700/60 bg-indigo-950/40 text-indigo-300'
                            : 'text-slate-300'
                        }`}>
                          {formatRole(m.membership_role)}
                        </span>
                      </td>
                      <td className="px-5 py-3">
                        <span className="inline-flex items-center rounded-full border border-emerald-700/60 bg-emerald-950/40 px-2 py-0.5 text-[10px] font-medium text-emerald-300">
                          {m.membership_status}
                        </span>
                      </td>
                      <td className="px-5 py-3 text-slate-400">
                        {m.effective_from}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
