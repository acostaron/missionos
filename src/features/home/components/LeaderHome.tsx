import { HeartHandshake, House, UserPlus, Users } from 'lucide-react';
import { Link } from 'react-router-dom';
import { Alert, Skeleton, StatCard } from '../../../components/ui';
import { usePastoralOperationsDashboard } from '../../households/api/get-pastoral-operations-dashboard';
import type { PastoralOperationsDashboardV2 } from '../../households/types';
import { Permissions } from '../../../types/permissions';
import { usePermissions } from '../../../hooks/use-permissions';
import AttentionList from './AttentionList';
import type { AttentionItem } from './AttentionList';
import DashboardMetricGrid from './DashboardMetricGrid';
import HomeSection from './HomeSection';
import HomeWelcomeHeader from './HomeWelcomeHeader';
import PastoralResponsibilityCard from './PastoralResponsibilityCard';
import QuickActions from './QuickActions';
import type { QuickAction } from './QuickActions';
import { pluralize, servantRoleLabel } from '../role-labels';

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

  const canViewHouseholds = hasPermission(Permissions.HouseholdsRecordsView);
  const actions: QuickAction[] = [];
  if (hasPermission(Permissions.MembersRecordsCreate))
    actions.push({ key: 'add', label: 'Add Member', to: '/app/members/new', icon: <UserPlus /> });
  if (hasPermission(Permissions.MembersRecordsView))
    actions.push({ key: 'people', label: 'View People', to: '/app/members', icon: <Users /> });
  if (canViewHouseholds)
    actions.push({ key: 'households', label: 'View Households', to: '/app/households', icon: <House /> });
  actions.push({ key: 'pastoral', label: 'Pastoral Review', to: '/app/pastoral-operations', icon: <HeartHandshake /> });

  const offices = data ? Array.from(new Set(data.identity.serving_assignments.map((a) => a.role_code))) : [];
  const responsibilities: string[] = [];
  if (isOrgAdmin) responsibilities.push('Organization Administrator');
  if (data && data.identity.serving_assignments.length === 1) {
    responsibilities.push(servantRoleLabel(offices[0]));
  } else if (data && data.identity.serving_assignments.length > 1) {
    responsibilities.push(`Serving in ${data.identity.serving_assignments.length} pastoral leadership roles`);
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
  const hasResponsibility =
    data.identity.serving_assignments.length > 0 ||
    !!data.identity.pastoral_membership ||
    (data.care_responsibilities?.length ?? 0) > 0;

  return (
    <div className="space-y-8">
      {header}

      <HomeSection title="At a Glance">
        <DashboardMetricGrid>
          <StatCard label="Households" value={data.operational_summary?.total ?? 0} />
          <StatCard label="Members Without a Household" value={data.unassigned_members_count ?? 0} />
          <StatCard label="Upcoming Meetings" value={m?.upcoming_meetings ?? 0} />
          <StatCard label="Household Topics Planned" value={data.formation_operations_summary?.topics_planned ?? 0} />
        </DashboardMetricGrid>
      </HomeSection>

      <HomeSection title="Needs Your Attention">
        <AttentionList items={attention} />
      </HomeSection>

      {hasResponsibility && (
        <HomeSection title="My Pastoral Responsibility">
          <PastoralResponsibilityCard dashboard={data} />
        </HomeSection>
      )}

      {(m?.upcoming_meetings ?? 0) > 0 && (
        <HomeSection title="Coming Up">
          <Link
            to="/app/pastoral-operations"
            className="block rounded-card border border-line bg-surface p-4 text-body text-ink hover:bg-surface-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus"
          >
            {pluralize(m.upcoming_meetings, 'household meeting')} coming up
          </Link>
        </HomeSection>
      )}

      <HomeSection title="Quick Actions">
        <QuickActions actions={actions} />
      </HomeSection>
    </div>
  );
}
