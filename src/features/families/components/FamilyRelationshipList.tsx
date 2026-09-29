import { useMemo } from 'react';
import type { FamilyProfileRelationship, FamilyProfileMember } from '../types';

interface FamilyRelationshipListProps {
  relationships: FamilyProfileRelationship[] | null;
  members: FamilyProfileMember[];
  canViewRelationships: boolean;
  canAddRelationship?: boolean;
  canEndRelationship?: boolean;
  canCorrectRelationship?: boolean;
  isFamilyOperational?: boolean;
  onAddRelationship?: () => void;
  onEndRelationship?: (relationship: FamilyProfileRelationship) => void;
  onRepairRelationship?: (relationship: FamilyProfileRelationship) => void;
}

interface DisplayRelationshipItem {
  id: string;
  fromMemberId: string;
  toMemberId: string;
  typeName: string;
  typeCode: string;
  verificationStatus: string;
  isReciprocalPair: boolean;
  isReciprocalMissing?: boolean;
  rawRelationship: FamilyProfileRelationship;
}

/**
 * Groups reciprocal asymmetric relationships (e.g. parent_of and child_of)
 * into a single logical display item (preferring parent_of for display).
 * Identifies un-paired asymmetric relationships as missing reciprocals.
 * Symmetric relationships (spouse) display individually.
 */
function groupRelationships(
  relationships: FamilyProfileRelationship[] | null
): DisplayRelationshipItem[] {
  if (!relationships || relationships.length === 0) return [];

  const grouped: DisplayRelationshipItem[] = [];
  const handledIds = new Set<string>();

  for (const rel of relationships) {
    if (handledIds.has(rel.relationship_id)) continue;

    // Check if asymmetric and has reciprocal row in the same set
    if (!rel.relationship_type.is_symmetric && rel.relationship_type.inverse_code) {
      const reciprocalRel = relationships.find(
        (r) =>
          !handledIds.has(r.relationship_id) &&
          r.relationship_id !== rel.relationship_id &&
          r.from_member_id === rel.to_member_id &&
          r.to_member_id === rel.from_member_id &&
          r.relationship_type.code === rel.relationship_type.inverse_code
      );

      if (reciprocalRel) {
        // Both rows exist: group them. Prefer 'parent_of' over 'child_of' for display convention
        const primaryRel = rel.relationship_type.code === 'parent_of' ? rel : reciprocalRel;
        const secondaryRel = primaryRel === rel ? reciprocalRel : rel;

        handledIds.add(primaryRel.relationship_id);
        handledIds.add(secondaryRel.relationship_id);

        grouped.push({
          id: primaryRel.relationship_id,
          fromMemberId: primaryRel.from_member_id,
          toMemberId: primaryRel.to_member_id,
          typeName:
            primaryRel.relationship_type.name ||
            primaryRel.relationship_type.code.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase()),
          typeCode: primaryRel.relationship_type.code,
          verificationStatus: primaryRel.verification_status,
          isReciprocalPair: true,
          isReciprocalMissing: false,
          rawRelationship: primaryRel,
        });
        continue;
      }

      // Asymmetric with inverse, but reciprocal row is absent! Incomplete pair
      handledIds.add(rel.relationship_id);
      grouped.push({
        id: rel.relationship_id,
        fromMemberId: rel.from_member_id,
        toMemberId: rel.to_member_id,
        typeName:
          rel.relationship_type.name ||
          rel.relationship_type.code.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase()),
        typeCode: rel.relationship_type.code,
        verificationStatus: rel.verification_status,
        isReciprocalPair: false,
        isReciprocalMissing: true,
        rawRelationship: rel,
      });
      continue;
    }

    // Single symmetric row (e.g. spouse) or without inverse code
    handledIds.add(rel.relationship_id);
    grouped.push({
      id: rel.relationship_id,
      fromMemberId: rel.from_member_id,
      toMemberId: rel.to_member_id,
      typeName:
        rel.relationship_type.name ||
        rel.relationship_type.code.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase()),
      typeCode: rel.relationship_type.code,
      verificationStatus: rel.verification_status,
      isReciprocalPair: false,
      isReciprocalMissing: false,
      rawRelationship: rel,
    });
  }

  return grouped;
}

export function FamilyRelationshipList({
  relationships,
  members,
  canViewRelationships,
  canAddRelationship = false,
  canEndRelationship = false,
  canCorrectRelationship = false,
  isFamilyOperational = false,
  onAddRelationship,
  onEndRelationship,
  onRepairRelationship,
}: FamilyRelationshipListProps) {
  const icon = (
    <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
      <path strokeLinecap="round" strokeLinejoin="round"
        d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1" />
    </svg>
  );

  const displayItems = useMemo(() => groupRelationships(relationships), [relationships]);
  const canShowAddButton =
    canAddRelationship && isFamilyOperational && members.length >= 2 && !!onAddRelationship;

  return (
    <div className="rounded-xl border border-slate-700 bg-slate-800/60 overflow-hidden">
      <div className="flex items-center justify-between border-b border-slate-700 px-5 py-3.5">
        <div className="flex items-center gap-3">
          <span className="text-slate-400">{icon}</span>
          <h2 className="text-sm font-semibold uppercase tracking-wider text-slate-300">
            Family Relationships
          </h2>
          {canViewRelationships && relationships && (
            <span className="text-xs text-slate-400">
              ({displayItems.length})
            </span>
          )}
        </div>
        {canShowAddButton && (
          <button
            type="button"
            id="add-family-relationship-button"
            onClick={onAddRelationship}
            className="inline-flex items-center gap-1.5 rounded-lg border border-indigo-700/60 bg-indigo-950/40 px-3 py-1.5 text-xs font-medium text-indigo-300 shadow-sm hover:bg-indigo-900/60 hover:text-indigo-200 transition-colors"
          >
            <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M12 4v16m8-8H4" />
            </svg>
            Add relationship
          </button>
        )}
      </div>

      <div className="px-5 py-4">
        {!canViewRelationships || relationships === null ? (
          <p className="flex items-center gap-2 text-xs text-slate-500 italic py-1">
            <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
              <path strokeLinecap="round" strokeLinejoin="round"
                d="M12 15v2m-6 4h12a2 2 0 002-2v-5a2 2 0 00-2-2H6a2 2 0 00-2 2v5a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
            </svg>
            Family relationships — access restricted for this role
          </p>
        ) : displayItems.length === 0 ? (
          <p className="text-xs text-slate-500 italic py-1">
            No family relationships are recorded.
          </p>
        ) : (
          <div className="space-y-2.5">
            {displayItems.map((item) => {
              const fromMember = members.find((m) => m.member_id === item.fromMemberId);
              const toMember = members.find((m) => m.member_id === item.toMemberId);
              const fromName = fromMember?.display_name || 'Unknown member';
              const toName = toMember?.display_name || 'Unknown member';

              return (
                <div
                  key={item.id}
                  className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 rounded-lg border border-slate-700 bg-slate-900/40 px-4 py-3"
                >
                  <div className="flex items-center gap-2.5 flex-wrap text-sm">
                    <span className="font-semibold text-slate-100">{fromName}</span>
                    <span className="inline-flex items-center rounded-full border border-indigo-700/60 bg-indigo-950/40 px-2.5 py-0.5 text-xs font-medium text-indigo-300">
                      {item.typeName}
                    </span>
                    <span className="font-semibold text-slate-100">{toName}</span>

                    {item.isReciprocalMissing && canCorrectRelationship && (
                      <span className="inline-flex items-center gap-1 rounded-md border border-amber-800/60 bg-amber-950/40 px-2 py-0.5 text-[11px] font-medium text-amber-300">
                        <svg className="h-3 w-3 text-amber-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                          <path strokeLinecap="round" strokeLinejoin="round" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                        </svg>
                        Reciprocal relationship missing
                      </span>
                    )}
                  </div>

                  <div className="flex items-center gap-3 self-end sm:self-center">
                    {item.verificationStatus && item.verificationStatus !== 'unverified' && (
                      <span className="capitalize text-xs text-slate-500">
                        {item.verificationStatus.replace(/_/g, ' ')}
                      </span>
                    )}

                    {item.isReciprocalMissing && canCorrectRelationship && isFamilyOperational && onRepairRelationship && (
                      <button
                        type="button"
                        id={`repair-relationship-btn-${item.id}`}
                        onClick={() => onRepairRelationship(item.rawRelationship)}
                        className="inline-flex items-center gap-1 rounded border border-amber-700/60 bg-amber-950/40 px-2.5 py-1 text-xs font-medium text-amber-300 hover:bg-amber-900/60 hover:text-amber-200 transition-colors"
                      >
                        <svg className="h-3.5 w-3.5 text-amber-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                          <path strokeLinecap="round" strokeLinejoin="round" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                        </svg>
                        Repair relationship
                      </button>
                    )}

                    {canEndRelationship && isFamilyOperational && onEndRelationship && (
                      <button
                        type="button"
                        id={`end-relationship-btn-${item.id}`}
                        onClick={() => onEndRelationship(item.rawRelationship)}
                        className="inline-flex items-center gap-1 rounded px-2.5 py-1 text-xs font-medium text-rose-400 hover:bg-rose-950/40 hover:text-rose-300 transition-colors"
                      >
                        <svg className="h-3.5 w-3.5 text-rose-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                          <path strokeLinecap="round" strokeLinejoin="round" d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" />
                        </svg>
                        End
                      </button>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
