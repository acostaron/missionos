import { HeartHandshake, House, UserPlus } from 'lucide-react';
import { Alert, Skeleton } from '../../../components/ui';
import { usePastoralOperationsDashboard } from '../../households/api/get-pastoral-operations-dashboard';
import type { PastoralOperationsDashboardV2 } from '../../households/types';
import { Permissions } from '../../../types/permissions';
import { usePermissions } from '../../../hooks/use-permissions';
import AttentionList from './AttentionList';
import type { AttentionItem } from './AttentionList';
import DashboardMetricGrid from './DashboardMetricGrid';
import HomeSection from './HomeSection';
import HomeWelcomeHeader from './HomeWelcomeHeader';
import HomeStat from './HomeStat';
import QuickActions from './QuickActions';
import type { QuickAction } from './QuickActions';
import { formatPastoralRolesList, servantRoleLabel } from '../role-labels';

type Props = {
  organizationId: string;
  organizationName: string | null;
  firstName: string;
  isOrgAdmin: boolean;
};

function buildAttention(d: PastoralOperationsDashboardV2, canViewUnassigned: boolean): AttentionItem[] {
  const m = d.meeting_operations_summary;
  const f = d.formation_operations_summary;
  const pastoral = '/app/pastoral-operations';
  const items: AttentionItem[] = [];
  const add = (i: AttentionItem) => i.count > 0 && items.push(i);

  add({
    key: 'unassigned',
    label: 'Members Without a Household',
    detail: 'Members not currently placed in a household',
    count: d.unassigned_members_count ?? 0,
    tone: 'warning',
    to: canViewUnassigned ? '/app/households/unassigned' : undefined,
  });
  add({
    key: 'vacancies',
    label: 'Leadership Vacancies',
    count: d.leadership_vacancies?.length ?? 0,
    tone: 'warning',
    to: pastoral,
  });
  add({
    key: 'placement',
    label: 'Servant Leaders Needing Pastoral Placement',
    detail: 'Leaders who need a pastoral household or a placement decision',
    count: d.placement_review_summary?.total ?? 0,
    tone: 'neutral',
    to: pastoral,
  });
  add({ key: 'attendance', label: 'Attendance Pending', count: m?.attendance_pending ?? 0, tone: 'warning', to: pastoral });
  add({ key: 'overdue', label: 'Household Meetings Overdue', count: m?.households_overdue ?? 0, tone: 'warning', to: pastoral });
  add({
    key: 'nohistory',
    label: 'Households With No Meeting History',
    count: m?.households_without_meeting_history ?? 0,
    tone: 'neutral',
    to: pastoral,
  });
  add({
    key: 'noplan',
    label: 'Households Without Household Topics',
    count: f?.households_with_no_plan ?? 0,
    tone: 'neutral',
    to: pastoral,
  });
  add({ key: 'topicsdue', label: 'Household Topics Due', count: f?.topics_due ?? 0, tone: 'warning', to: pastoral });
  add({ key: 'topicsoverdue', label: 'Household Topics Overdue', count: f?.topics_overdue ?? 0, tone: 'warning', to: pastoral });
  return items;
}

export default function LeaderHome({ organizationId, organizationName, firstName, isOrgAdmin }: Props) {
  const { hasPermission } = usePermissions();
  const { data, isLoading, error } = usePastoralOperationsDashboard(organizationId);

  if (error) console.error('Home dashboard failed to load', error);

  const canCreateMembers = hasPermission(Permissions.MembersRecordsCreate);
  const canAssignMembers = hasPermission(Permissions.HouseholdsMembersAssign);
  const canViewHouseholds = hasPermission(Permissions.HouseholdsRecordsView);
  const canViewPastoralOps = hasPermission(Permissions.LeadershipPastoralDashboardView);

  const hslAssignments = data?.identity.serving_assignments.filter(
    (a) => a.role_code === 'household_servant_leader'
  ) ?? [];
  const singleLedHouseholdId = hslAssignments.length === 1 ? hslAssignments[0].governance_node_id : null;

  const actions: QuickAction[] = [];

  if (canCreateMembers) {
    actions.push({
      key: 'add-member',
      label: 'Add Member',
      to: '/app/members/new',
      icon: <UserPlus />,
    });
  }

  // Pass 9.19: "Members Without a Household" and "View Households" quick actions removed on Home
  // (the At a Glance tiles now open those same pages).

  if (singleLedHouseholdId && canViewHouseholds) {
    actions.push({
      key: 'my-household',
      label: 'My Household',
      to: `/app/households/${singleLedHouseholdId}`,
      icon: <House />,
    });
  }


  if (canViewPastoralOps) {
    actions.push({
      key: 'pastoral-operations',
      label: 'Pastoral Operations',
      to: '/app/pastoral-operations',
      icon: <HeartHandshake />,
    });
  }

  const distinctRoleCodes = data
    ? Array.from(new Set(data.identity.serving_assignments.map((a) => a.role_code)))
    : [];
  const pastoralTitles = distinctRoleCodes.map((code) => servantRoleLabel(code));

  const responsibilities: string[] = [];
  if (isOrgAdmin) {
    responsibilities.push('Organization Administrator');
  }
  if (pastoralTitles.length > 0) {
    responsibilities.push(`Serving as ${formatPastoralRolesList(pastoralTitles)}`);
  }

  const header = (
    <HomeWelcomeHeader name={firstName} organizationName={organizationName} responsibilities={responsibilities} />
  );

  if (isLoading) {
    return (
      <div className="space-y-6">
        {header}
        <DashboardMetricGrid>
          {[0, 1, 2, 3].map((i) => (
            <Skeleton key={i} className="h-24" />
          ))}
        </DashboardMetricGrid>
        <Skeleton className="h-40" />
      </div>
    );
  }

  if (error || !data) {
    return (
      <div className="space-y-6">
        {header}
        <Alert variant="warning" title="Pastoral information is unavailable right now">
          Please try again in a moment. If this continues, contact your administrator.
        </Alert>
        <HomeSection title="Quick Actions">
          <QuickActions actions={actions} />
        </HomeSection>
      </div>
    );
  }

  const m = data.meeting_operations_summary;
  const attention = buildAttention(data, hasPermission(Permissions.HouseholdsMembersAssign));
  // Pass 9.19 (Ron, 2026-10-16): Home fits one phone screen. "My Pastoral Responsibility" removed here
  // (the Pastoral tab shows the same cards); "Coming Up" folded into the Upcoming Meetings tile.
  return (
    <div className="space-y-4 sm:space-y-8">
      {header}

      <HomeSection title="At a Glance">
        <DashboardMetricGrid>
          <HomeStat
            label="Households"
            shortLabel="Households"
            value={data.operational_summary?.total ?? 0}
            to={canViewHouseholds ? '/app/households' : undefined}
          />
          <HomeStat
            label="Members Without a Household"
            shortLabel="No household"
            value={data.unassigned_members_count ?? 0}
            to={canAssignMembers ? '/app/households/unassigned' : undefined}
          />
          <HomeStat
            label="Upcoming Meetings"
            shortLabel="Meetings"
            value={m?.upcoming_meetings ?? 0}
            to={canViewPastoralOps ? '/app/pastoral-operations' : undefined}
          />
          <HomeStat
            label="Household Topics Planned"
            shortLabel="Topics"
            value={data.formation_operations_summary?.topics_planned ?? 0}
            to={canViewPastoralOps ? '/app/pastoral-operations' : undefined}
          />
        </DashboardMetricGrid>
      </HomeSection>

      <HomeSection title="Needs Your Attention">
        <AttentionList items={attention} />
      </HomeSection>

      <HomeSection title="Quick Actions">
        <QuickActions actions={actions} />
      </HomeSection>
    </div>
  );
}
