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
    <div className="rounded-lg border border-line bg-surface p-3.5 space-y-2">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h3 className="text-sm font-semibold text-ink">
            <Link
              to={`/app/families/${family.family_id}`}
              className="hover:text-primary-blue hover:underline transition-colors"
            >
              {familyLabel}
            </Link>
          </h3>
          <p className="text-xs text-ink-muted mt-0.5">{countLabel}</p>
        </div>
        <div className="flex items-center gap-1.5 flex-wrap justify-end">
          <span
            className={`inline-flex items-center rounded-full border px-2 py-0.5 text-[10px] font-medium ${
              isStatusActive
                ? 'border-success-600/30 bg-success-50 text-success-700'
                : 'border-line-strong bg-surface-muted text-ink-muted'
            }`}
          >
            {statusLabel}
          </span>
          {family.is_primary_contact && (
            <span className="inline-flex items-center rounded-full border border-navy-100 bg-navy-50 px-2 py-0.5 text-[10px] font-medium text-primary-blue">
              Primary contact
            </span>
          )}
          {family.is_dependent && (
            <span className="inline-flex items-center rounded-full border border-warning-600/30 bg-warning-50 px-2 py-0.5 text-[10px] font-medium text-warning-700">
              Dependent
            </span>
          )}
        </div>
      </div>

      {roleLabel && (
        <div className="pt-1 border-t border-line flex items-center justify-between text-xs text-ink-muted">
          <span>Family role</span>
          <span className="font-medium text-ink">{roleLabel}</span>
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
    <div className="rounded-xl border border-line bg-surface-muted overflow-hidden">
      <div className="flex items-center justify-between border-b border-line px-5 py-3.5">
        <div className="flex items-center gap-3">
          <span className="text-ink-muted">{icon}</span>
          <h2 className="text-sm font-semibold uppercase tracking-wider text-ink-secondary">
            Family
          </h2>
        </div>
      </div>
      <div className="px-5 py-4">
        {!canViewFamilies ? (
          <p className="flex items-center gap-2 text-xs text-ink-muted italic">
            <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
              <path strokeLinecap="round" strokeLinejoin="round"
                d="M12 15v2m-6 4h12a2 2 0 002-2v-5a2 2 0 00-2-2H6a2 2 0 00-2 2v5a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
            </svg>
            Family — access restricted for this role
          </p>
        ) : isLoading ? (
          <div className="space-y-3 py-1">
            <div className="h-16 animate-pulse rounded-lg bg-surface border border-line" />
          </div>
        ) : error ? (
          <div className="rounded-lg border border-danger-600/30 bg-danger-50 p-3 text-xs text-danger-700">
            Failed to load family information.
          </div>
        ) : !families || families.length === 0 ? (
          <p className="text-xs text-ink-muted italic py-1">No family record linked.</p>
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
