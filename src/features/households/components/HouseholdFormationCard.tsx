import { useState } from 'react';
import { useHouseholdFormationPlan } from '../api/get-household-formation-plan';
import { useHouseholdTopicHistory } from '../api/get-household-topic-history';
import { AssignHouseholdTopicModal } from './AssignHouseholdTopicModal';
import { CompleteHouseholdTopicModal } from './CompleteHouseholdTopicModal';
import {
  HouseholdTopicActionModal,
  type HouseholdTopicActionMode,
} from './HouseholdTopicActionModal';
import {
  ASSIGNMENT_STATUS_LABELS,
  FORMATION_STATUS_LABELS,
  REASON_CODE_LABELS,
  formatFormationLabel,
} from './formation-labels';
import type {
  HouseholdFormationPlanTopic,
  HouseholdFormationSummary,
  HouseholdFormationStatus,
  HouseholdTopicHistoryRow,
} from '../types';

const HISTORY_PAGE_SIZE = 10;

const STATUS_STYLES: Record<HouseholdFormationStatus, string> = {
  no_plan: 'border-line-strong bg-surface-muted text-ink-secondary',
  planned: 'border-navy-100 bg-navy-50 text-primary-blue',
  topic_due: 'border-warning-600/30 bg-warning-50 text-warning-700',
  topic_overdue: 'border-danger-600/30 bg-danger-50 text-danger-700',
  up_to_date: 'border-success-600/30 bg-success-50 text-success-700',
};

interface HouseholdFormationCardProps {
  organizationId: string;
  householdId: string;
  householdName: string;
  pastoralLevel?: string | null;
  isHouseholdActive: boolean;
  canView: boolean;
  canManage: boolean;
  /** formation_summary as returned by get_household_profile (source of truth for the header). */
  summary?: HouseholdFormationSummary | null;
  onSuccessToast?: (msg: string) => void;
}

interface TopicActionTarget {
  mode: HouseholdTopicActionMode;
  topic: HouseholdFormationPlanTopic;
}

export function HouseholdFormationCard({
  organizationId,
  householdId,
  householdName,
  pastoralLevel,
  isHouseholdActive,
  canView,
  canManage,
  summary,
  onSuccessToast,
}: HouseholdFormationCardProps) {
  const [isAssignOpen, setIsAssignOpen] = useState(false);
  const [completeTarget, setCompleteTarget] = useState<HouseholdFormationPlanTopic | null>(null);
  const [actionTarget, setActionTarget] = useState<TopicActionTarget | null>(null);
  const [showHistory, setShowHistory] = useState(false);
  const [page, setPage] = useState(0);

  const { data: plan, isLoading, error } = useHouseholdFormationPlan(
    organizationId,
    householdId,
    canView
  );
  const {
    data: history,
    isLoading: isHistoryLoading,
    error: historyError,
  } = useHouseholdTopicHistory(organizationId, householdId, page, HISTORY_PAGE_SIZE, canView && showHistory);

  if (!canView) {
    return (
      <div className="rounded-xl border border-line bg-surface-muted p-6">
        <p className="text-xs text-ink-muted">
          You do not have permission to view formation for this household.
        </p>
      </div>
    );
  }

  // Backend remains authoritative; this only hides controls that cannot apply.
  // Fraternal households have no delegated write authority.
  const isFraternal = pastoralLevel === 'fraternal';
  const canWrite = canManage && !isFraternal;
  const canAssign = canWrite && isHouseholdActive;

  const status: HouseholdFormationStatus | undefined =
    summary?.formation_status ?? plan?.formation_status;
  const nextTopic = summary?.next_topic ?? plan?.next_topic ?? null;
  const lastCompleted = summary?.last_completed_topic ?? plan?.last_completed_topic ?? null;
  const plannedCount = summary?.planned_topics_count ?? plan?.planned_count ?? 0;
  const completedCount = summary?.completed_topics_count ?? plan?.completed_count ?? 0;
  const upcoming = plan?.upcoming_topics ?? [];
  const noPlan = status === 'no_plan' && plannedCount === 0 && completedCount === 0;

  const totalPages = history ? Math.ceil(history.total_count / HISTORY_PAGE_SIZE) : 0;

  const renderRowActions = (topic: HouseholdFormationPlanTopic) => {
    if (!canWrite) return null;
    const btn =
      'rounded-md border border-line-strong px-2 py-1 text-[10px] font-medium text-ink-secondary hover:bg-line transition-colors';
    return (
      <div className="flex flex-wrap gap-1.5">
        {isHouseholdActive && (
          <>
            <button type="button" className={btn} onClick={() => setActionTarget({ mode: 'reschedule', topic })}>
              Reschedule
            </button>
            <button type="button" className={btn} onClick={() => setCompleteTarget(topic)}>
              Mark Completed
            </button>
          </>
        )}
        <button type="button" className={btn} onClick={() => setActionTarget({ mode: 'skip', topic })}>
          Skip
        </button>
        <button type="button" className={btn} onClick={() => setActionTarget({ mode: 'cancel', topic })}>
          Cancel
        </button>
      </div>
    );
  };

  const nextAsPlanTopic: HouseholdFormationPlanTopic | null = nextTopic
    ? (upcoming.find((t) => t.assignment_id === nextTopic.assignment_id) ??
      (nextTopic as HouseholdFormationPlanTopic))
    : null;
  const otherUpcoming = upcoming.filter((t) => t.assignment_id !== nextTopic?.assignment_id);

  return (
    <>
      <div className="rounded-xl border border-line bg-surface-muted">
        <div className="flex items-center justify-between border-b border-line px-5 py-4">
          <div className="flex items-center gap-3">
            <h3 className="text-sm font-semibold text-ink">Household Formation</h3>
            {status && (
              <span
                className={`inline-flex items-center rounded-full border px-2 py-0.5 text-[10px] font-medium ${STATUS_STYLES[status] ?? STATUS_STYLES.no_plan}`}
              >
                {formatFormationLabel(FORMATION_STATUS_LABELS, status)}
              </span>
            )}
          </div>
          {canAssign && (
            <button
              type="button"
              onClick={() => setIsAssignOpen(true)}
              className="inline-flex items-center gap-1.5 rounded-lg border border-navy-100 bg-navy-50 px-3 py-1.5 text-xs font-medium text-primary-blue hover:bg-navy-100 transition-colors"
            >
              Assign Topic
            </button>
          )}
        </div>

        <div className="space-y-4 px-5 py-4">
          {isLoading && !summary && (
            <div className="space-y-2">
              {[1, 2].map((i) => (
                <div key={i} className="h-10 animate-pulse rounded-lg bg-surface-muted" />
              ))}
            </div>
          )}

          {error && <p className="text-xs text-danger-700">Failed to load household formation.</p>}

          {!error && noPlan && (
            <p className="text-xs text-ink-muted">No formation topics have been planned yet.</p>
          )}

          {!error && !noPlan && (status || summary) && (
            <dl className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <div className="rounded-lg border border-line bg-surface-muted p-3">
                <dt className="text-[10px] uppercase tracking-wider text-ink-muted">Next Topic</dt>
                <dd className="mt-1 text-xs text-ink">
                  {nextTopic ? nextTopic.title : 'No upcoming household topic.'}
                </dd>
                <dd className="mt-0.5 text-[11px] text-ink-muted">
                  {nextTopic
                    ? `Planned: ${nextTopic.planned_for_date ?? 'No date set'}`
                    : ''}
                </dd>
                {nextAsPlanTopic && <div className="mt-2">{renderRowActions(nextAsPlanTopic)}</div>}
              </div>

              <div className="rounded-lg border border-line bg-surface-muted p-3">
                <dt className="text-[10px] uppercase tracking-wider text-ink-muted">
                  Last Completed Topic
                </dt>
                <dd className="mt-1 text-xs text-ink">
                  {lastCompleted ? lastCompleted.title : 'No completed topics yet.'}
                </dd>
                {lastCompleted && (
                  <dd className="mt-0.5 text-[11px] text-ink-muted">
                    {lastCompleted.meeting_date
                      ? `Meeting: ${lastCompleted.meeting_date}`
                      : lastCompleted.completed_at
                        ? `Completed: ${lastCompleted.completed_at.slice(0, 10)}`
                        : ''}
                  </dd>
                )}
              </div>

              <div className="rounded-lg border border-line bg-surface-muted p-3">
                <dt className="text-[10px] uppercase tracking-wider text-ink-muted">Planned Topics</dt>
                <dd className="mt-1 text-lg font-semibold text-ink">{plannedCount}</dd>
              </div>

              <div className="rounded-lg border border-line bg-surface-muted p-3">
                <dt className="text-[10px] uppercase tracking-wider text-ink-muted">Completed Topics</dt>
                <dd className="mt-1 text-lg font-semibold text-ink">{completedCount}</dd>
              </div>
            </dl>
          )}

          {otherUpcoming.length > 0 && (
            <div className="space-y-1.5">
              <p className="text-[10px] uppercase tracking-wider text-ink-muted">Upcoming</p>
              {otherUpcoming.map((t) => (
                <div
                  key={t.assignment_id}
                  className="rounded-lg border border-line bg-surface-muted px-3 py-2"
                >
                  <div className="flex items-center justify-between gap-3">
                    <span className="text-xs text-ink">{t.title}</span>
                    <span className="text-[11px] text-ink-muted tabular-nums">
                      {t.planned_for_date ?? 'No date set'}
                    </span>
                  </div>
                  <div className="mt-1.5">{renderRowActions(t)}</div>
                </div>
              ))}
            </div>
          )}

          <div>
            <button
              type="button"
              onClick={() => setShowHistory((v) => !v)}
              className="text-xs text-primary-blue hover:text-primary-blue underline underline-offset-2"
            >
              {showHistory ? 'Hide topic history' : 'View topic history'}
            </button>
          </div>

          {showHistory && (
            <div className="space-y-2">
              {isHistoryLoading && <div className="h-10 animate-pulse rounded-lg bg-surface-muted" />}
              {historyError && <p className="text-xs text-danger-700">Failed to load topic history.</p>}
              {!isHistoryLoading && !historyError && history && history.history.length === 0 && (
                <p className="text-xs text-ink-muted">No formation topics have been planned yet.</p>
              )}
              {history?.history.map((row: HouseholdTopicHistoryRow) => (
                <div
                  key={row.assignment_id}
                  className="rounded-lg border border-line bg-surface-muted px-3 py-2"
                >
                  <div className="flex items-center justify-between gap-3">
                    <span className="text-xs font-medium text-ink">{row.topic_title}</span>
                    <span className="text-[10px] text-ink-muted">
                      {formatFormationLabel(ASSIGNMENT_STATUS_LABELS, row.assignment_status)}
                    </span>
                  </div>
                  <div className="mt-1 flex flex-wrap gap-x-4 gap-y-0.5 text-[11px] text-ink-muted">
                    <span>Planned: {row.planned_for_date ?? '—'}</span>
                    <span>Completed: {row.completed_at ? row.completed_at.slice(0, 10) : '—'}</span>
                    <span>Meeting: {row.meeting_date ?? '—'}</span>
                    {row.resolution_reason_code && (
                      <span>
                        Reason: {formatFormationLabel(REASON_CODE_LABELS, row.resolution_reason_code)}
                      </span>
                    )}
                  </div>
                </div>
              ))}
              {totalPages > 1 && (
                <div className="flex items-center justify-between pt-1">
                  <button
                    type="button"
                    onClick={() => setPage((p) => Math.max(0, p - 1))}
                    disabled={page === 0}
                    className="rounded-lg border border-line-strong px-3 py-1.5 text-xs text-ink-secondary hover:bg-surface-muted transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
                  >
                    ← Previous
                  </button>
                  <span className="text-[10px] text-ink-muted">
                    Page {page + 1} of {totalPages}
                  </span>
                  <button
                    type="button"
                    onClick={() => setPage((p) => Math.min(totalPages - 1, p + 1))}
                    disabled={page >= totalPages - 1}
                    className="rounded-lg border border-line-strong px-3 py-1.5 text-xs text-ink-secondary hover:bg-surface-muted transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
                  >
                    Next →
                  </button>
                </div>
              )}
            </div>
          )}
        </div>
      </div>

      {canAssign && (
        <AssignHouseholdTopicModal
          isOpen={isAssignOpen}
          onClose={() => setIsAssignOpen(false)}
          organizationId={organizationId}
          householdId={householdId}
          householdName={householdName}
          pastoralLevel={pastoralLevel}
          onSuccessToast={onSuccessToast}
        />
      )}

      {completeTarget && (
        <CompleteHouseholdTopicModal
          isOpen
          onClose={() => setCompleteTarget(null)}
          organizationId={organizationId}
          householdId={householdId}
          householdName={householdName}
          assignmentId={completeTarget.assignment_id}
          topicTitle={completeTarget.title}
          onSuccessToast={onSuccessToast}
        />
      )}

      {actionTarget && (
        <HouseholdTopicActionModal
          isOpen
          onClose={() => setActionTarget(null)}
          mode={actionTarget.mode}
          organizationId={organizationId}
          householdName={householdName}
          assignmentId={actionTarget.topic.assignment_id}
          topicTitle={actionTarget.topic.title}
          currentPlannedDate={actionTarget.topic.planned_for_date}
          onSuccessToast={onSuccessToast}
        />
      )}
    </>
  );
}