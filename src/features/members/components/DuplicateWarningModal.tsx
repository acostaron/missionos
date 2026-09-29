import { Link } from 'react-router-dom';
import type { DuplicateCandidateMatch } from '../types';

interface ModalProps {
  isOpen: boolean;
  candidateMatches: DuplicateCandidateMatch[];
  warningCount: number;
  onCancel: () => void;
  onCreateAnyway: () => void;
  isSubmitting: boolean;
}

const REASON_LABELS: Record<string, string> = {
  normalized_email_match: 'Same email',
  phone_match: 'Same phone',
  exact_name_and_birth_date: 'Same name and birth date',
  similar_name: 'Similar name',
};

export function DuplicateWarningModal({
  isOpen,
  candidateMatches,
  warningCount,
  onCancel,
  onCreateAnyway,
  isSubmitting,
}: ModalProps) {
  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/80 p-4 backdrop-blur-sm">
      <div className="w-full max-w-lg rounded-2xl border border-amber-600/40 bg-slate-900 p-6 shadow-2xl space-y-6">
        {/* Header */}
        <div className="flex items-start gap-4">
          <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-amber-500/20 text-amber-400">
            <svg
              className="h-6 w-6"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
              strokeWidth={2}
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
              />
            </svg>
          </div>
          <div>
            <h3 className="text-lg font-semibold text-slate-100">
              Potential Duplicate Member Detected
            </h3>
            <p className="mt-1 text-sm text-slate-400">
              Found {warningCount} existing member{warningCount > 1 ? 's' : ''} with similar details. Please review to avoid creating duplicate records.
            </p>
          </div>
        </div>

        {/* Candidate List */}
        <div className="max-h-60 overflow-y-auto space-y-2 pr-1">
          {candidateMatches.map((cand) => (
            <div
              key={cand.member_id}
              className="flex items-center justify-between rounded-xl border border-slate-800 bg-slate-800/60 p-3.5"
            >
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-semibold text-slate-100">
                  {cand.display_name}
                </p>
                <div className="mt-1 flex flex-wrap gap-1.5">
                  {cand.member_number && (
                    <span className="font-mono text-xs text-slate-300 bg-slate-800 px-2 py-0.5 rounded border border-slate-700">
                      {cand.member_number}
                    </span>
                  )}
                  {cand.match_reasons.map((r, i) => (
                    <span
                      key={i}
                      className="rounded bg-amber-500/10 px-2 py-0.5 text-[11px] font-medium text-amber-300 border border-amber-500/20"
                    >
                      {REASON_LABELS[r] || r}
                    </span>
                  ))}
                </div>
              </div>

              <Link
                to={`/app/members/${cand.member_id}`}
                target="_blank"
                rel="noopener noreferrer"
                className="ml-3 shrink-0 rounded-lg border border-slate-700 px-3 py-1.5 text-xs font-medium text-slate-300 hover:border-indigo-500 hover:text-indigo-300 transition-colors"
              >
                View Member ↗
              </Link>
            </div>
          ))}
        </div>

        {/* Actions */}
        <div className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end sm:gap-3">
          <button
            type="button"
            onClick={onCancel}
            disabled={isSubmitting}
            className="rounded-lg border border-slate-700 px-4 py-2 text-sm font-medium text-slate-300 hover:bg-slate-800 transition-colors disabled:opacity-50"
          >
            Back to Form
          </button>
          <button
            type="button"
            onClick={onCreateAnyway}
            disabled={isSubmitting}
            className="inline-flex items-center justify-center rounded-lg bg-amber-600 px-4 py-2 text-sm font-medium text-white hover:bg-amber-500 transition-colors disabled:opacity-50"
          >
            {isSubmitting ? 'Creating…' : 'Create Anyway'}
          </button>
        </div>
      </div>
    </div>
  );
}
