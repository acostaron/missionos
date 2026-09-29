import { Link } from 'react-router-dom';
import { useMemberFamilies } from '../api/get-member-families';
import type { MemberFamilySummary } from '../types';

interface MemberFamilyCardProps {
  organizationId: string | null;
  memberId: string;
  canViewFamilies: boolean;
}

function formatRole(role: string | null): string | null {
  if (!role) return null;
  return role
    .replace(/_/g, ' ')
    .replace(/\b\w/g, (char) => char.toUpperCase());
}

function FamilyItem({ family }: { family: MemberFamilySummary }) {
  const familyLabel =
    family.display_name?.trim() ||
    family.family_name?.trim() ||
    'Family record';

  const roleLabel = formatRole(family.family_role);
  const memberCount = family.active_member_count ?? 0;
  const countLabel = `${memberCount} ${
    memberCount === 1 ? 'family member' : 'family members'
  }`;

  const isStatusActive = family.family_status === 'active';
  const statusLabel = family.family_status
    ? family.family_status.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase())
    : 'Active';

  return (
    <div className="rounded-lg border border-slate-700 bg-slate-900/40 p-3.5 space-y-2">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h3 className="text-sm font-semibold text-slate-100">
            <Link
              to={`/app/families/${family.family_id}`}
              className="hover:text-indigo-300 hover:underline transition-colors"
            >
              {familyLabel}
            </Link>
          </h3>
          <p className="text-xs text-slate-400 mt-0.5">{countLabel}</p>
        </div>
        <div className="flex items-center gap-1.5 flex-wrap justify-end">
          <span
            className={`inline-flex items-center rounded-full border px-2 py-0.5 text-[10px] font-medium ${
              isStatusActive
                ? 'border-emerald-700/60 bg-emerald-950/40 text-emerald-300'
                : 'border-slate-600 bg-slate-800 text-slate-400'
            }`}
          >
            {statusLabel}
          </span>
          {family.is_primary_contact && (
            <span className="inline-flex items-center rounded-full border border-sky-700/60 bg-sky-950/40 px-2 py-0.5 text-[10px] font-medium text-sky-300">
              Primary contact
            </span>
          )}
          {family.is_dependent && (
            <span className="inline-flex items-center rounded-full border border-amber-700/60 bg-amber-950/40 px-2 py-0.5 text-[10px] font-medium text-amber-300">
              Dependent
            </span>
          )}
        </div>
      </div>

      {roleLabel && (
        <div className="pt-1 border-t border-slate-800/80 flex items-center justify-between text-xs text-slate-400">
          <span>Family role</span>
          <span className="font-medium text-slate-200">{roleLabel}</span>
        </div>
      )}
    </div>
  );
}

export function MemberFamilyCard({
  organizationId,
  memberId,
  canViewFamilies,
}: MemberFamilyCardProps) {
  const {
    data: families,
    isLoading,
    error,
  } = useMemberFamilies(organizationId, memberId, canViewFamilies);

  const icon = (
    <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z"
      />
    </svg>
  );

  return (
    <div className="rounded-xl border border-slate-700 bg-slate-800/60 overflow-hidden">
      <div className="flex items-center justify-between border-b border-slate-700 px-5 py-3.5">
        <div className="flex items-center gap-3">
          <span className="text-slate-400">{icon}</span>
          <h2 className="text-sm font-semibold uppercase tracking-wider text-slate-300">
            Family
          </h2>
        </div>
      </div>
      <div className="px-5 py-4">
        {!canViewFamilies ? (
          <p className="flex items-center gap-2 text-xs text-slate-500 italic">
            <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
              <path strokeLinecap="round" strokeLinejoin="round"
                d="M12 15v2m-6 4h12a2 2 0 002-2v-5a2 2 0 00-2-2H6a2 2 0 00-2 2v5a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
            </svg>
            Family — access restricted for this role
          </p>
        ) : isLoading ? (
          <div className="space-y-3 py-1">
            <div className="h-16 animate-pulse rounded-lg bg-slate-900/40 border border-slate-700/60" />
          </div>
        ) : error ? (
          <div className="rounded-lg border border-red-900/40 bg-red-950/20 p-3 text-xs text-red-300">
            Failed to load family information.
          </div>
        ) : !families || families.length === 0 ? (
          <p className="text-xs text-slate-500 italic py-1">No family record linked.</p>
        ) : (
          <div className="space-y-3">
            {families.map((fam) => (
              <FamilyItem key={fam.family_member_id} family={fam} />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
