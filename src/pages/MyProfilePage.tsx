import { Link } from 'react-router-dom';
import { ArrowLeft, ExternalLink, House, Mail, Phone, ShieldAlert, User, Users } from 'lucide-react';
import { useOrganizationContext } from '../hooks/use-organization-context';
import { usePermissions } from '../hooks/use-permissions';
import { Permissions } from '../types/permissions';
import { useMyMemberProfile } from '../features/self-service/api';
import { formatMeetingSchedule } from '../features/self-service/formatters';
import { Badge, Card, EmptyState, PageHeader, Skeleton } from '../components/ui';

function formatDate(dateStr: string | null | undefined): string | null {
  if (!dateStr) return null;
  try {
    const parts = dateStr.split('-');
    if (parts.length === 3) {
      const year = parseInt(parts[0], 10);
      const month = parseInt(parts[1], 10) - 1;
      const day = parseInt(parts[2], 10);
      const d = new Date(year, month, day);
      if (!Number.isNaN(d.getTime())) {
        return d.toLocaleDateString('en-US', {
          year: 'numeric',
          month: 'long',
          day: 'numeric',
        });
      }
    }
    return dateStr;
  } catch {
    return dateStr;
  }
}

function formatLanguage(code: string | null | undefined): string | null {
  if (!code) return null;
  const normalized = code.toLowerCase().trim();
  switch (normalized) {
    case 'en':
      return 'English';
    case 'es':
      return 'Spanish';
    case 'tl':
    case 'fil':
      return 'Tagalog / Filipino';
    default:
      return code.toUpperCase();
  }
}

function formatPastoralLevel(level: string | null | undefined): string | null {
  if (!level) return null;
  return level.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
}

export default function MyProfilePage() {
  const { activeOrganization } = useOrganizationContext();
  const { hasPermission, isLoading: isPermLoading } = usePermissions();

  const canSelfService = hasPermission(Permissions.MembersSelfServiceView);
  const canViewHouseholdWorkspace = hasPermission(Permissions.HouseholdsRecordsView);

  const orgId = activeOrganization?.id ?? null;
  const { data, isLoading, error } = useMyMemberProfile(orgId, canSelfService);

  const errorCode = (error as { code?: string } | null)?.code;
  const errorMessage = (error as { message?: string } | null)?.message ?? '';
  const notLinked = errorCode === 'P0002' || errorMessage.toLowerCase().includes('not linked');

  return (
    <div className="mx-auto max-w-5xl space-y-8 px-4 py-8 sm:px-6 lg:px-8">
      <PageHeader
        title="My Profile"
        description="Your personal information, household details, and community context in MissionOS."
        breadcrumb={
          <nav aria-label="Breadcrumb" className="flex items-center gap-2 text-xs text-ink-muted">
            <Link
              to="/app/dashboard"
              className="inline-flex items-center gap-1 hover:text-ink transition-colors"
            >
              <ArrowLeft className="h-3.5 w-3.5" aria-hidden="true" />
              Back to Home
            </Link>
            <span aria-hidden="true">/</span>
            <span className="font-medium text-ink">My Profile</span>
          </nav>
        }
      />

      {/* Permission guard / loading / error / content states */}
      {!isPermLoading && !canSelfService ? (
        <Card padding="comfortable">
          <EmptyState
            icon={<ShieldAlert />}
            title="Access Restricted"
            message="You do not currently have permission to view your self-service member profile. Please contact your servant leader or administrator."
            action={
              <Link
                to="/app/dashboard"
                className="inline-flex h-9 items-center rounded-control border border-line-strong bg-surface px-4 text-small font-medium text-ink hover:bg-surface-muted"
              >
                Return to Home
              </Link>
            }
          />
        </Card>
      ) : notLinked ? (
        <Card padding="comfortable">
          <EmptyState
            icon={<User />}
            title="Account Not Linked"
            message="Your MissionOS account is not currently linked to a member record. Once your servant leader or administrator connects your profile, your information will appear here."
            action={
              <Link
                to="/app/dashboard"
                className="inline-flex h-9 items-center rounded-control border border-line-strong bg-surface px-4 text-small font-medium text-ink hover:bg-surface-muted"
              >
                Return to Home
              </Link>
            }
          />
        </Card>
      ) : error ? (
        <Card padding="comfortable">
          <EmptyState
            icon={<ShieldAlert />}
            title="Unable to Load Profile"
            message="We encountered an issue loading your profile details. Please try again later or refresh the page."
            action={
              <button
                type="button"
                onClick={() => window.location.reload()}
                className="inline-flex h-9 items-center rounded-control border border-line-strong bg-surface px-4 text-small font-medium text-ink hover:bg-surface-muted"
              >
                Reload Page
              </button>
            }
          />
        </Card>
      ) : isLoading || !data ? (
        <div className="space-y-6">
          <Card padding="comfortable" className="space-y-4">
            <Skeleton className="h-6 w-48" />
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <Skeleton className="h-14" />
              <Skeleton className="h-14" />
              <Skeleton className="h-14" />
              <Skeleton className="h-14" />
            </div>
          </Card>
          <Card padding="comfortable" className="space-y-4">
            <Skeleton className="h-6 w-48" />
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <Skeleton className="h-14" />
              <Skeleton className="h-14" />
            </div>
          </Card>
          <Card padding="comfortable" className="space-y-4">
            <Skeleton className="h-6 w-48" />
            <Skeleton className="h-20" />
          </Card>
        </div>
      ) : (
        <div className="space-y-6">
          {/* Section A: Personal Information */}
          <Card padding="comfortable">
            <div className="flex items-center justify-between border-b border-line pb-4">
              <div className="flex items-center gap-2.5">
                <div
                  className="flex h-9 w-9 items-center justify-center rounded-full bg-navy-50 text-primary-blue"
                  aria-hidden="true"
                >
                  <User className="h-5 w-5" />
                </div>
                <div>
                  <h2 className="text-card-title font-semibold text-ink">Personal Information</h2>
                  <p className="text-caption text-ink-muted">Basic profile details registered with MFC</p>
                </div>
              </div>
              {data.member.membership_status && (
                <Badge
                  variant={
                    data.member.membership_status.toLowerCase() === 'active'
                      ? 'success'
                      : 'neutral'
                  }
                >
                  {data.member.membership_status}
                </Badge>
              )}
            </div>

            <dl className="mt-4 grid grid-cols-1 gap-x-6 gap-y-4 sm:grid-cols-2 lg:grid-cols-3">
              <div>
                <dt className="text-caption font-medium text-ink-muted">Member Number</dt>
                <dd className="mt-1 font-mono text-small font-medium text-ink">
                  {data.member.member_number || 'Not assigned'}
                </dd>
              </div>

              <div>
                <dt className="text-caption font-medium text-ink-muted">Full Name</dt>
                <dd className="mt-1 text-small font-medium text-ink">
                  {data.member.display_name}
                </dd>
              </div>

              {data.details.preferred_name && (
                <div>
                  <dt className="text-caption font-medium text-ink-muted">Preferred Name</dt>
                  <dd className="mt-1 text-small text-ink">
                    {data.details.preferred_name}
                  </dd>
                </div>
              )}

              <div>
                <dt className="text-caption font-medium text-ink-muted">Joined MFC</dt>
                <dd className="mt-1 text-small text-ink">
                  {formatDate(data.details.joined_on) || 'Not provided'}
                </dd>
              </div>

              <div>
                <dt className="text-caption font-medium text-ink-muted">Preferred Language</dt>
                <dd className="mt-1 text-small text-ink">
                  {formatLanguage(data.details.preferred_language_code) || 'Not provided'}
                </dd>
              </div>
            </dl>
          </Card>

          {/* Section B: Contact Information */}
          <Card padding="comfortable">
            <div className="flex items-center gap-2.5 border-b border-line pb-4">
              <div
                className="flex h-9 w-9 items-center justify-center rounded-full bg-navy-50 text-primary-blue"
                aria-hidden="true"
              >
                <Mail className="h-5 w-5" />
              </div>
              <div>
                <h2 className="text-card-title font-semibold text-ink">Contact Information</h2>
                <p className="text-caption text-ink-muted">Primary communication channels on file</p>
              </div>
            </div>

            <dl className="mt-4 grid grid-cols-1 gap-x-6 gap-y-4 sm:grid-cols-2">
              <div className="flex items-start gap-3">
                <Mail className="mt-1 h-4 w-4 shrink-0 text-ink-muted" aria-hidden="true" />
                <div className="min-w-0">
                  <dt className="text-caption font-medium text-ink-muted">Primary Email</dt>
                  <dd className="mt-1 text-small text-ink break-words">
                    {data.contact.primary_email || 'Not provided'}
                  </dd>
                </div>
              </div>

              <div className="flex items-start gap-3">
                <Phone className="mt-1 h-4 w-4 shrink-0 text-ink-muted" aria-hidden="true" />
                <div className="min-w-0">
                  <dt className="text-caption font-medium text-ink-muted">Primary Phone</dt>
                  <dd className="mt-1 text-small text-ink">
                    {data.contact.primary_phone || 'Not provided'}
                  </dd>
                </div>
              </div>
            </dl>
          </Card>

          {/* Section C: My Household */}
          <Card padding="comfortable">
            <div className="flex items-center justify-between border-b border-line pb-4">
              <div className="flex items-center gap-2.5">
                <div
                  className="flex h-9 w-9 items-center justify-center rounded-full bg-navy-50 text-primary-blue"
                  aria-hidden="true"
                >
                  <House className="h-5 w-5" />
                </div>
                <div>
                  <h2 className="text-card-title font-semibold text-ink">My Household</h2>
                  <p className="text-caption text-ink-muted">Your pastoral household fellowship</p>
                </div>
              </div>
              {data.household && canViewHouseholdWorkspace && (
                <Link
                  to={`/app/households/${data.household.household_id}`}
                  className="inline-flex items-center gap-1.5 text-xs font-medium text-primary-blue hover:underline"
                >
                  <span>View Household Workspace</span>
                  <ExternalLink className="h-3.5 w-3.5" aria-hidden="true" />
                </Link>
              )}
            </div>

            {data.household ? (
              <dl className="mt-4 grid grid-cols-1 gap-x-6 gap-y-4 sm:grid-cols-2">
                <div>
                  <dt className="text-caption font-medium text-ink-muted">Household Name</dt>
                  <dd className="mt-1 text-small font-medium text-ink">
                    {data.household.household_name}
                  </dd>
                </div>

                {data.household.pastoral_level && (
                  <div>
                    <dt className="text-caption font-medium text-ink-muted">Pastoral Level</dt>
                    <dd className="mt-1 text-small text-ink">
                      {formatPastoralLevel(data.household.pastoral_level)}
                    </dd>
                  </div>
                )}

                <div>
                  <dt className="text-caption font-medium text-ink-muted">Household Servant Leader</dt>
                  <dd className="mt-1 text-small text-ink">
                    {data.household.leader_display_name || 'Not assigned'}
                  </dd>
                </div>

                <div>
                  <dt className="text-caption font-medium text-ink-muted">Meeting Schedule</dt>
                  <dd className="mt-1 text-small text-ink">
                    {formatMeetingSchedule({
                      frequency: data.household.meeting_frequency,
                      dayOfWeek: data.household.meeting_day_of_week,
                      startTime: data.household.meeting_start_time,
                      timezoneName: data.household.meeting_timezone_name,
                    })}
                  </dd>
                </div>

                {data.household.parent_node_name && (
                  <div className="sm:col-span-2">
                    <dt className="text-caption font-medium text-ink-muted">Parent Group</dt>
                    <dd className="mt-1 text-small text-ink">
                      {data.household.parent_node_name}
                    </dd>
                  </div>
                )}
              </dl>
            ) : (
              <div className="py-6 text-center">
                <p className="text-small font-medium text-ink">Household assignment pending</p>
                <p className="mt-1 text-caption text-ink-muted">
                  You are not currently placed in a household. When your servant leader or administrator assigns your household, it will appear here.
                </p>
              </div>
            )}
          </Card>

          {/* Section D: My Community */}
          <Card padding="comfortable">
            <div className="flex items-center gap-2.5 border-b border-line pb-4">
              <div
                className="flex h-9 w-9 items-center justify-center rounded-full bg-navy-50 text-primary-blue"
                aria-hidden="true"
              >
                <Users className="h-5 w-5" />
              </div>
              <div>
                <h2 className="text-card-title font-semibold text-ink">My Community</h2>
                <p className="text-caption text-ink-muted">Organizational placement within MFC</p>
              </div>
            </div>

            <dl className="mt-4 grid grid-cols-1 gap-x-6 gap-y-4 sm:grid-cols-2 lg:grid-cols-3">
              <div>
                <dt className="text-caption font-medium text-ink-muted">Organization</dt>
                <dd className="mt-1 text-small font-medium text-ink">
                  {activeOrganization?.name || 'Missionary Families of Christ'}
                </dd>
              </div>

              {data.organizational_context.area && (
                <div>
                  <dt className="text-caption font-medium text-ink-muted">Area / State</dt>
                  <dd className="mt-1 text-small text-ink">
                    {data.organizational_context.area}
                  </dd>
                </div>
              )}

              {data.organizational_context.chapter && (
                <div>
                  <dt className="text-caption font-medium text-ink-muted">Chapter</dt>
                  <dd className="mt-1 text-small text-ink">
                    {data.organizational_context.chapter}
                  </dd>
                </div>
              )}

              {data.organizational_context.unit && (
                <div>
                  <dt className="text-caption font-medium text-ink-muted">Unit</dt>
                  <dd className="mt-1 text-small text-ink">
                    {data.organizational_context.unit}
                  </dd>
                </div>
              )}

              {data.organizational_context.section && (
                <div>
                  <dt className="text-caption font-medium text-ink-muted">Section</dt>
                  <dd className="mt-1 text-small text-ink">
                    {data.organizational_context.section}
                  </dd>
                </div>
              )}
            </dl>
          </Card>
        </div>
      )}
    </div>
  );
}
