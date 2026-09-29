import type { FamilyProfileRelationship, FamilyProfileMember } from '../types';

interface FamilyRelationshipListProps {
  relationships: FamilyProfileRelationship[] | null;
  members: FamilyProfileMember[];
  canViewRelationships: boolean;
}

export function FamilyRelationshipList({
  relationships,
  members,
  canViewRelationships,
}: FamilyRelationshipListProps) {
  const icon = (
    <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
      <path strokeLinecap="round" strokeLinejoin="round"
        d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1" />
    </svg>
  );

  return (
    <div className="rounded-xl border border-slate-700 bg-slate-800/60 overflow-hidden">
      <div className="flex items-center justify-between border-b border-slate-700 px-5 py-3.5">
        <div className="flex items-center gap-3">
          <span className="text-slate-400">{icon}</span>
          <h2 className="text-sm font-semibold uppercase tracking-wider text-slate-300">
            Family Relationships
          </h2>
        </div>
        {canViewRelationships && relationships && (
          <span className="text-xs text-slate-400">
            {relationships.length} {relationships.length === 1 ? 'relationship' : 'relationships'}
          </span>
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
        ) : relationships.length === 0 ? (
          <p className="text-xs text-slate-500 italic py-1">
            No family relationships are recorded.
          </p>
        ) : (
          <div className="space-y-2.5">
            {relationships.map((rel) => {
              const fromMember = members.find((m) => m.member_id === rel.from_member_id);
              const toMember = members.find((m) => m.member_id === rel.to_member_id);
              const fromName = fromMember?.display_name || 'Unknown member';
              const toName = toMember?.display_name || 'Unknown member';

              const relLabel =
                rel.relationship_type.name ||
                rel.relationship_type.code
                  .replace(/_/g, ' ')
                  .replace(/\b\w/g, (c) => c.toUpperCase());

              return (
                <div
                  key={rel.relationship_id}
                  className="flex flex-col sm:flex-row sm:items-center justify-between gap-2.5 rounded-lg border border-slate-700 bg-slate-900/40 px-4 py-3"
                >
                  <div className="flex items-center gap-2.5 flex-wrap text-sm">
                    <span className="font-semibold text-slate-100">{fromName}</span>
                    <span className="inline-flex items-center rounded-full border border-indigo-700/60 bg-indigo-950/40 px-2.5 py-0.5 text-xs font-medium text-indigo-300">
                      {relLabel}
                    </span>
                    <span className="font-semibold text-slate-100">{toName}</span>
                  </div>

                  <div className="flex items-center gap-2 text-xs text-slate-500">
                    {rel.verification_status && rel.verification_status !== 'unverified' && (
                      <span className="capitalize">
                        {rel.verification_status.replace(/_/g, ' ')}
                      </span>
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
