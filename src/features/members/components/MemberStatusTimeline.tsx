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
        <div className="h-14 animate-pulse rounded-lg bg-slate-800/60" />
        <div className="h-14 animate-pulse rounded-lg bg-slate-800/60" />
      </div>
    );
  }

  if (error) {
    return (
      <div className="rounded-lg border border-red-900/40 bg-red-950/20 p-3 text-xs text-red-300">
        Failed to load membership lifecycle history.
      </div>
    );
  }

  if (!history || history.length === 0) {
    return (
      <p className="text-xs text-slate-500 italic py-2">
        No membership lifecycle history is available.
      </p>
    );
  }

  return (
    <div className="relative pl-6 space-y-6 before:absolute before:bottom-2 before:left-[11px] before:top-2 before:w-[2px] before:bg-slate-700/60">
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
              className={`absolute -left-[19px] top-1.5 h-2.5 w-2.5 rounded-full border-2 border-slate-900 ${
                item.is_current
                  ? 'bg-emerald-400 ring-2 ring-emerald-400/30'
                  : 'bg-slate-500'
              }`}
            />

            <div className="rounded-xl border border-slate-700/60 bg-slate-800/40 p-4 transition-colors hover:border-slate-600/70">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <div className="flex items-center gap-2.5">
                  <span className="font-semibold text-sm text-slate-100">
                    {item.status_name}
                  </span>
                  {item.is_current && (
                    <span className="inline-flex items-center rounded-full bg-emerald-950/80 px-2 py-0.5 text-[11px] font-semibold text-emerald-300 border border-emerald-800/60">
                      Current
                    </span>
                  )}
                  {isBaseline && (
                    <span className="inline-flex items-center rounded-full bg-slate-800 px-2 py-0.5 text-[11px] font-medium text-slate-300 border border-slate-700">
                      MissionOS baseline
                    </span>
                  )}
                </div>

                <div className="text-xs text-slate-400 font-medium">
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
                <p className="mt-2 text-xs text-slate-400">
                  Current membership status when lifecycle tracking began.
                </p>
              )}

              {/* Administrative Reason (only if present and not the default baseline text) */}
              {!isBaseline && item.change_summary && (
                <div className="mt-2.5 rounded-lg border border-slate-700/50 bg-slate-900/50 px-3 py-2 text-xs text-slate-300">
                  <span className="font-semibold text-slate-400">Reason: </span>
                  <span>{item.change_summary}</span>
                </div>
              )}

              {/* Footer metadata: Recorded by */}
              <div className="mt-3 flex items-center justify-between text-[11px] text-slate-500 border-t border-slate-700/40 pt-2">
                <span>
                  Recorded by: <span className="text-slate-400">{item.recorded_by_name ?? 'System'}</span>
                </span>
                <span>
                  Source: <span className="capitalize text-slate-400">{item.source}</span>
                </span>
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
}
