import { House } from 'lucide-react';
import { Card, EmptyState, Skeleton } from '../../../components/ui';
import { useMyMemberContext } from '../../self-service/api';
import { Permissions } from '../../../types/permissions';
import { usePermissions } from '../../../hooks/use-permissions';
import HomeSection from './HomeSection';
import HomeWelcomeHeader from './HomeWelcomeHeader';
import QuickActions from './QuickActions';
import type { QuickAction } from './QuickActions';

type Props = {
  organizationId: string;
  organizationName: string | null;
  firstName: string;
};

/**
 * Minimal Member Home. Uses ONLY the self-service RPC (get_my_member_context),
 * which resolves the caller's own member on the server. No member id is sent.
 * "View My Profile" is deferred until the My Profile pass.
 */
export default function MemberHome({ organizationId, organizationName, firstName }: Props) {
  const { hasPermission } = usePermissions();
  const canSelfService = hasPermission(Permissions.MembersSelfServiceView);
  const { data, isLoading, error } = useMyMemberContext(organizationId, canSelfService);

  if (error) console.error('Member self-service context failed to load', error);

  const errorCode = (error as { code?: string } | null)?.code;
  const notLinked = errorCode === 'P0002';
  const unavailable = !canSelfService || (!!error && !notLinked);
  const household = data?.household ?? null;
  const org = data?.organizational_context;
  const orgLine = [org?.unit, org?.chapter, org?.area].filter(Boolean).join(' · ');

  const actions: QuickAction[] = [];
  if (household && hasPermission(Permissions.HouseholdsRecordsView))
    actions.push({
      key: 'household',
      label: 'View My Household',
      to: `/app/households/${household.household_id}`,
      icon: <House />,
    });

  return (
    <div className="space-y-8">
      <HomeWelcomeHeader name={firstName} organizationName={organizationName} />

      <HomeSection title="My Household">
        <Card padding="compact">
          {notLinked ? (
            <EmptyState
              title="Your account isn't linked to a member record yet"
              message="Once your administrator links it, your household will appear here."
            />
          ) : unavailable ? (
            <EmptyState
              title="Your household information is not available right now"
              message="Please check back later, or contact your servant leader or administrator."
            />
          ) : isLoading ? (
            <Skeleton className="h-16" />
          ) : household ? (
            <div>
              <p className="text-body font-medium text-ink">{household.household_name}</p>
              {household.parent_node_name && (
                <p className="text-small text-ink-muted">{household.parent_node_name}</p>
              )}
              {household.leader_display_name && (
                <p className="mt-1 text-small text-ink-secondary">
                  Household Servant Leader: {household.leader_display_name}
                </p>
              )}
              {orgLine && <p className="mt-1 text-small text-ink-muted">{orgLine}</p>}
            </div>
          ) : (
            <EmptyState
              title="You are not currently placed in a household"
              message="When you are placed in a household, it will appear here."
            />
          )}
        </Card>
      </HomeSection>

      {actions.length > 0 && (
        <HomeSection title="Quick Actions">
          <QuickActions actions={actions} />
        </HomeSection>
      )}
    </div>
  );
}
