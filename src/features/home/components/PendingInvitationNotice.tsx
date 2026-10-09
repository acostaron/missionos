import { Link } from 'react-router-dom';
import { Building2, ArrowRight } from 'lucide-react';
import { Button } from '../../../components/ui';
import { useMyPendingAccountInvitations } from '../../auth/invitation/queries';

export interface PendingInvitationNoticeProps {
  className?: string;
}

function formatDate(dateStr: string): string {
  try {
    return new Date(dateStr).toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
    });
  } catch {
    return dateStr;
  }
}

export default function PendingInvitationNotice({ className = '' }: PendingInvitationNoticeProps) {
  const { data: invitations, isLoading } = useMyPendingAccountInvitations();

  if (isLoading || !invitations || invitations.length === 0) {
    return null;
  }

  const isMultiple = invitations.length > 1;

  return (
    <section
      aria-labelledby="pending-invitations-heading"
      className={`rounded-xl border border-line bg-surface p-4 sm:p-5 shadow-sm ${className}`}
    >
      <div className="flex items-start gap-3.5">
        <div className="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-navy-50 text-primary-blue dark:bg-navy-900/30">
          <Building2 className="h-5 w-5" aria-hidden="true" />
        </div>

        <div className="min-w-0 flex-1 space-y-3">
          <div>
            <h2
              id="pending-invitations-heading"
              className="text-sm font-semibold tracking-tight text-ink"
            >
              {isMultiple ? 'Organization Invitations' : 'Organization Invitation'}
            </h2>
            <p className="mt-0.5 text-xs text-ink-muted">
              {isMultiple
                ? `You have ${invitations.length} pending organization invitations.`
                : `You have been invited to join ${invitations[0].organization_name} in MissionOS.`}
            </p>
          </div>

          {!isMultiple ? (
            <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 pt-1">
              <div className="text-xs text-ink-secondary">
                {invitations[0].invited_at && (
                  <span>Invited {formatDate(invitations[0].invited_at)}</span>
                )}
              </div>
              <Link
                to={`/invite/accept?invitation=${invitations[0].invitation_id}`}
                className="w-full sm:w-auto"
              >
                <Button size="sm" className="w-full sm:w-auto gap-1.5">
                  <span>Review Invitation</span>
                  <ArrowRight className="h-3.5 w-3.5" aria-hidden="true" />
                </Button>
              </Link>
            </div>
          ) : (
            <div className="divide-y divide-line rounded-lg border border-line bg-surface-elevated/40">
              {invitations.map((inv) => (
                <div
                  key={inv.invitation_id}
                  className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 p-3"
                >
                  <div className="min-w-0 space-y-0.5">
                    <p className="text-sm font-medium text-ink break-words">
                      {inv.organization_name}
                    </p>
                    {inv.invited_at && (
                      <p className="text-xs text-ink-muted">
                        Invited {formatDate(inv.invited_at)}
                      </p>
                    )}
                  </div>
                  <Link
                    to={`/invite/accept?invitation=${inv.invitation_id}`}
                    className="w-full sm:w-auto shrink-0"
                  >
                    <Button size="sm" variant="secondary" className="w-full sm:w-auto gap-1.5">
                      <span>Review Invitation</span>
                      <ArrowRight className="h-3.5 w-3.5" aria-hidden="true" />
                    </Button>
                  </Link>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </section>
  );
}
