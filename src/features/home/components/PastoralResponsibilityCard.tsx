import { Card } from '../../../components/ui';
import type { PastoralOperationsDashboardV2 } from '../../households/types';
import { officeForLevel, pluralize, servantRoleLabel } from '../role-labels';

function responsibilityCount(r: PastoralOperationsDashboardV2['care_responsibilities'][number]): string {
  const d = r.details;
  switch (d.type) {
    case 'household_members':
      return pluralize(d.member_count ?? d.members?.length ?? 0, 'Household Member');
    case 'household_leaders':
      return pluralize(d.leaders?.length ?? 0, 'Household Leader');
    case 'unit_leaders':
      return pluralize(d.leaders?.length ?? 0, 'Unit Leader');
    case 'chapter_leaders':
      return pluralize(d.leaders?.length ?? 0, 'Chapter Leader');
    default:
      return '';
  }
}

function Group({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div>
      <h3 className="mb-2 text-small font-semibold uppercase tracking-wide text-ink-muted">{title}</h3>
      {children}
    </div>
  );
}

/**
 * My Pastoral Responsibility. Every office and responsibility the backend
 * returns is shown; nothing is collapsed to a "highest" office.
 */
export default function PastoralResponsibilityCard({ dashboard }: { dashboard: PastoralOperationsDashboardV2 }) {
  const { serving_assignments, pastoral_membership } = dashboard.identity;
  const care = dashboard.care_responsibilities ?? [];

  return (
    <div className="grid gap-4 lg:grid-cols-3">
      {serving_assignments.length > 0 && (
        <Card padding="compact">
          <Group title="Where I Lead">
            <ul className="space-y-3">
              {serving_assignments.map((a) => (
                <li key={a.leadership_assignment_id}>
                  <p className="text-body font-medium text-ink">{servantRoleLabel(a.role_code)}</p>
                  <p className="text-small text-ink-muted">{a.governance_node_name}</p>
                </li>
              ))}
            </ul>
          </Group>
        </Card>
      )}

      {pastoral_membership && (
        <Card padding="compact">
          <Group title="Where I Receive Pastoral Care">
            <p className="text-body font-medium text-ink">{pastoral_membership.household_name}</p>
            {pastoral_membership.scope_node_name && (
              <p className="text-small text-ink-muted">{pastoral_membership.scope_node_name}</p>
            )}
          </Group>
        </Card>
      )}

      {care.length > 0 && (
        <Card padding="compact">
          <Group title="People Entrusted to My Care">
            <ul className="space-y-3">
              {care.map((r) => (
                <li key={r.leadership_assignment_id}>
                  <p className="text-body font-medium text-ink">{responsibilityCount(r)}</p>
                  <p className="text-small text-ink-muted">
                    {officeForLevel(r.responsibility_level)} · {r.scope_name}
                  </p>
                </li>
              ))}
            </ul>
          </Group>
        </Card>
      )}
    </div>
  );
}
