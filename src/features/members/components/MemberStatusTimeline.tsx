import { useMemberStatusHistory } from '../api/get-member-status-history';

interface MemberStatusTimelineProps {
  organizationId: string;
  memberId: string;
  canViewStatusHistory?: boolean;
}

function formatDate(dateStr: string): string {
  try {
    const d = new Date(dateStr);
    if (isNaN(d.getTime())) return dateStr;
    return d.toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      timeZone: 'UTC',
    });
  } catch {
    return dateStr;
  }
}

export function MemberStatusTimeline({
  organizationId,
  memberId,
  canViewStatusHistory = true,
}: MemberStatusTimelineProps) {
  const {
    data: history,
    isLoading,
    error,
  } = useMemberStatusHistory(organizationId, memberId, canViewStatusHistory);

  if (!canViewStatusHistory) {
    return null;
  }

  if (isLoading) {
    return (
      <div className="space-y-4 py-2">
        <div className="h-14 animate-pulse rounded-lg bg-surface-muted" />
        <div className="h-14 animate-pulse rounded-lg bg-surface-muted" />
      </div>
    );
  }

  if (error) {
    return (
      <div className="rounded-lg border border-danger-600/30 bg-danger-50 p-3 text-xs text-danger-700">
        Failed to load membership lifecycle history.
      </div>
    );
  }

  if (!history || history.length === 0) {
    return (
      <p className="text-xs text-ink-muted italic py-2">
        No membership lifecycle history is available.
      </p>
    );
  }

  return (
    <div className="relative pl-6 space-y-6 before:absolute before:bottom-2 before:left-[11px] before:top-2 before:w-[2px] before:bg-line">
      {history.map((item) => {
        const isBaseline =
          item.source === 'migration' ||
          item.change_summary === 'Initial MissionOS membership-status baseline';

        const startDate = formatDate(item.effective_from_at);
        const endDate = item.effective_to_at ? formatDate(item.effective_to_at) : 'Present';

        return (
          <div key={item.history_id} className="relative group">
            {/* Timeline node dot */}
            <div
              className={`absolute -left-[19px] top-1.5 h-2.5 w-2.5 rounded-full border-2 border-line ${
                item.is_current
                  ? 'bg-emerald-400 ring-2 ring-focus'
                  : 'bg-slate-500'
              }`}
            />

            <div className="rounded-xl border border-line bg-surface-muted p-4 transition-colors hover:border-line-strong">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <div className="flex items-center gap-2.5">
                  <span className="font-semibold text-sm text-ink">
                    {item.status_name}
                  </span>
                  {item.is_current && (
                    <span className="inline-flex items-center rounded-full bg-success-50 px-2 py-0.5 text-[11px] font-semibold text-success-700 border border-success-600/30">
                      Current
                    </span>
                  )}
                  {isBaseline && (
                    <span className="inline-flex items-center rounded-full bg-surface-muted px-2 py-0.5 text-[11px] font-medium text-ink-secondary border border-line">
                      MissionOS baseline
                    </span>
                  )}
                </div>

                <div className="text-xs text-ink-muted font-medium">
                  {isBaseline ? (
                    <span>Baseline established {startDate}</span>
                  ) : (
                    <span>
                      Effective {startDate} – {endDate}
                    </span>
                  )}
                </div>
              </div>

              {/* Baseline explanatory subtext */}
              {isBaseline && (
                <p className="mt-2 text-xs text-ink-muted">
                  Current membership status when lifecycle tracking began.
                </p>
              )}

              {/* Administrative Reason (only if present and not the default baseline text) */}
              {!isBaseline && item.change_summary && (
                <div className="mt-2.5 rounded-lg border border-line bg-surface px-3 py-2 text-xs text-ink-secondary">
                  <span className="font-semibold text-ink-muted">Reason: </span>
                  <span>{item.change_summary}</span>
                </div>
              )}

              {/* Footer metadata: Recorded by */}
              <div className="mt-3 flex items-center justify-between text-[11px] text-ink-muted border-t border-line pt-2">
                <span>
                  Recorded by: <span className="text-ink-muted">{item.recorded_by_name ?? 'System'}</span>
                </span>
                <span>
                  Source: <span className="capitalize text-ink-muted">{item.source}</span>
                </span>
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
}
