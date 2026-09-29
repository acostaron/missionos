import { Link } from 'react-router-dom';
import { useMemberHouseholds } from '../api/get-member-households';
import type { MemberHouseholdAssignment } from '../types';

interface MemberHouseholdCardProps {
  organizationId: string | null;
  memberId: string;
  canViewHouseholds: boolean;
}

function formatRole(role: string | null): string {
  if (!role) return 'Member';
  return role
    .replace(/_/g, ' ')
    .replace(/\b\w/g, (char) => char.toUpperCase());
}

function HouseholdItem({ assignment }: { assignment: MemberHouseholdAssignment }) {
  const isStatusActive = assignment.household_status === 'active';
  const roleLabel = formatRole(assignment.membership_role);

  return (
    <div className="rounded-lg border border-slate-700 bg-slate-900/40 p-3.5 space-y-2.5">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h3 className="text-sm font-semibold text-slate-100">
            <Link
              to={`/app/households/${assignment.household_id}`}
              className="hover:text-indigo-300 hover:underline transition-colors"
            >
              {assignment.household_name}
            </Link>
          </h3>
          <p className="text-xs text-slate-400 mt-0.5">
            Code: <span className="font-mono text-slate-300">{assignment.household_code}</span>
            {assignment.parent_node_name && (
              <>
                <span className="mx-1.5 text-slate-600">•</span>
                <span>{assignment.parent_node_name}</span>
                {assignment.parent_node_type && (
                  <span className="ml-1 text-[10px] uppercase text-slate-500">
                    ({assignment.parent_node_type})
                  </span>
                )}
              </>
            )}
          </p>
        </div>
        <div className="flex items-center gap-1.5 flex-wrap justify-end">
          <span
            className={`inline-flex items-center rounded-full border px-2 py-0.5 text-[10px] font-medium ${
              isStatusActive
                ? 'border-emerald-700/60 bg-emerald-950/40 text-emerald-300'
                : 'border-slate-600 bg-slate-800 text-slate-400'
            }`}
          >
            {assignment.household_status}
          </span>
          {assignment.is_primary && (
            <span className="inline-flex items-center rounded-full border border-indigo-700/60 bg-indigo-950/40 px-2 py-0.5 text-[10px] font-medium text-indigo-300">
              Primary
            </span>
          )}
        </div>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-2 pt-2 border-t border-slate-800/80 text-xs">
        <div className="flex items-center justify-between text-slate-400 pr-2">
          <span>Household role</span>
          <span className="font-medium text-slate-200">{roleLabel}</span>
        </div>
        <div className="flex items-center justify-between text-slate-400">
          <span>Effective date</span>
          <span className="font-medium text-slate-200">{assignment.effective_from}</span>
        </div>
        {assignment.household_servant_name && (
          <div className="flex items-center justify-between text-slate-400 sm:col-span-2 pt-1 border-t border-slate-800/50">
            <span>Household Servant</span>
            <span className="font-medium text-slate-200">{assignment.household_servant_name}</span>
          </div>
        )}
      </div>
    </div>
  );
}

export function MemberHouseholdCard({
  organizationId,
  memberId,
  canViewHouseholds,
}: MemberHouseholdCardProps) {
  const {
    data: households,
    isLoading,
    error,
  } = useMemberHouseholds(organizationId, memberId, canViewHouseholds);

  const icon = (
    <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6"
      />
    </svg>
  );

  return (
    <div className="rounded-xl border border-slate-700 bg-slate-800/60 overflow-hidden">
      <div className="flex items-center justify-between border-b border-slate-700 px-5 py-3.5">
        <div className="flex items-center gap-3">
          <span className="text-slate-400">{icon}</span>
          <h2 className="text-sm font-semibold uppercase tracking-wider text-slate-300">
            Household Assignment
          </h2>
        </div>
      </div>
      <div className="px-5 py-4">
        {!canViewHouseholds ? (
          <p className="flex items-center gap-2 text-xs text-slate-500 italic">
            <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
              <path strokeLinecap="round" strokeLinejoin="round"
                d="M12 15v2m-6 4h12a2 2 0 002-2v-5a2 2 0 00-2-2H6a2 2 0 00-2 2v5a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
            </svg>
            Household assignment — access restricted for this role
          </p>
        ) : isLoading ? (
          <div className="space-y-3 py-1">
            <div className="h-16 animate-pulse rounded-lg bg-slate-900/40 border border-slate-700/60" />
          </div>
        ) : error ? (
          <div className="rounded-lg border border-red-900/40 bg-red-950/20 p-3 text-xs text-red-300">
            Failed to load household assignment.
          </div>
        ) : !households || households.length === 0 ? (
          <p className="text-xs text-slate-500 italic py-1">No household assigned.</p>
        ) : (
          <div className="space-y-3">
            {households.map((h) => (
              <HouseholdItem key={h.household_membership_id} assignment={h} />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
