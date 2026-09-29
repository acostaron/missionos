import type { UseFormRegister, UseFormWatch } from 'react-hook-form';
import type { CreateMemberFormData } from '../schema';
import { usePlacementNodes } from '../../api/get-placement-nodes';

interface StepProps {
  register: UseFormRegister<CreateMemberFormData>;
  watch: UseFormWatch<CreateMemberFormData>;
  organizationId: string | null;
  canManagePlacements: boolean;
  canViewStructure: boolean;
}

export function Step3Placement({
  register,
  watch,
  organizationId,
  canManagePlacements,
  canViewStructure,
}: StepProps) {
  const isPermitted = canManagePlacements && canViewStructure;
  const { data: nodes, isLoading, error } = usePlacementNodes(organizationId, isPermitted);

  const selectedNodeId = watch('governanceNodeId');

  if (!isPermitted) {
    return (
      <div className="space-y-4">
        <div>
          <h2 className="text-lg font-semibold text-slate-100">Governance Placement</h2>
          <p className="text-sm text-slate-400">
            Initial Chapter or Unit assignment for the new member.
          </p>
        </div>
        <div className="rounded-xl border border-slate-800 bg-slate-900/50 p-6 text-center text-sm text-slate-400">
          <p className="italic">
            Governance placement management is restricted for your role. The member will be onboarded as unplaced.
          </p>
        </div>
      </div>
    );
  }

  // Separate chapters and units
  const chapters = nodes?.filter((n) => n.node_type_code === 'chapter') || [];
  const units = nodes?.filter((n) => n.node_type_code === 'unit') || [];

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-lg font-semibold text-slate-100">Governance Placement</h2>
        <p className="text-sm text-slate-400">
          Assign the member to an active Chapter or Unit, or leave unplaced for now.
        </p>
      </div>

      {isLoading && (
        <div className="space-y-3">
          <div className="h-10 animate-pulse rounded-lg bg-slate-800" />
          <div className="h-24 animate-pulse rounded-lg bg-slate-800" />
        </div>
      )}

      {error && (
        <div className="rounded-lg border border-red-700 bg-red-900/20 p-4 text-sm text-red-300">
          Failed to load placement hierarchy. You may continue with member unplaced.
        </div>
      )}

      {!isLoading && (
        <div className="space-y-3">
          {/* Option: Unplaced */}
          <label
            className={`flex items-center justify-between rounded-xl border p-4 cursor-pointer transition-colors ${
              !selectedNodeId
                ? 'border-indigo-500 bg-indigo-950/20 text-indigo-100'
                : 'border-slate-700/80 bg-slate-800/40 hover:bg-slate-800 text-slate-200'
            }`}
          >
            <div className="flex items-center gap-3">
              <input
                type="radio"
                value=""
                {...register('governanceNodeId')}
                className="h-4 w-4 border-slate-700 bg-slate-900 text-indigo-600 focus:ring-indigo-500"
              />
              <div>
                <p className="text-sm font-medium">Unplaced for now</p>
                <p className="text-xs text-slate-400">
                  Member will be created without an active primary governance node assignment.
                </p>
              </div>
            </div>
            <span className="text-xs font-mono text-slate-500 uppercase">Default</span>
          </label>

          {/* Grouped Chapters & Units */}
          {chapters.map((ch) => {
            const childUnits = units.filter((u) => u.parent_governance_node_id === ch.governance_node_id);
            const isChapterSelected = selectedNodeId === ch.governance_node_id;

            return (
              <div
                key={ch.governance_node_id}
                className="rounded-xl border border-slate-700/80 bg-slate-800/30 overflow-hidden"
              >
                {/* Chapter Row */}
                <label
                  className={`flex items-center justify-between p-3.5 cursor-pointer transition-colors ${
                    isChapterSelected
                      ? 'border-indigo-500 bg-indigo-950/30 text-indigo-100'
                      : 'hover:bg-slate-800/60 text-slate-200'
                  }`}
                >
                  <div className="flex items-center gap-3">
                    <input
                      type="radio"
                      value={ch.governance_node_id}
                      {...register('governanceNodeId')}
                      className="h-4 w-4 border-slate-700 bg-slate-900 text-indigo-600 focus:ring-indigo-500"
                    />
                    <div>
                      <p className="text-sm font-semibold">{ch.node_name}</p>
                      <p className="text-xs text-slate-400">Chapter</p>
                    </div>
                  </div>
                  <span className="rounded bg-slate-800 px-2 py-0.5 text-[10px] font-mono uppercase text-slate-400">
                    {ch.node_code}
                  </span>
                </label>

                {/* Sub-Units */}
                {childUnits.length > 0 && (
                  <div className="border-t border-slate-700/50 bg-slate-900/30 pl-8 pr-3 py-2 space-y-1">
                    {childUnits.map((u) => {
                      const isUnitSelected = selectedNodeId === u.governance_node_id;

                      return (
                        <label
                          key={u.governance_node_id}
                          className={`flex items-center justify-between rounded-lg p-2.5 cursor-pointer transition-colors ${
                            isUnitSelected
                              ? 'bg-indigo-950/40 text-indigo-100'
                              : 'hover:bg-slate-800/50 text-slate-300'
                          }`}
                        >
                          <div className="flex items-center gap-2.5">
                            <span className="text-slate-600">└</span>
                            <input
                              type="radio"
                              value={u.governance_node_id}
                              {...register('governanceNodeId')}
                              className="h-3.5 w-3.5 border-slate-700 bg-slate-900 text-indigo-600 focus:ring-indigo-500"
                            />
                            <div>
                              <p className="text-xs font-medium">{u.node_name}</p>
                              <p className="text-[10px] text-slate-400">Unit under {ch.node_name}</p>
                            </div>
                          </div>
                          <span className="text-[10px] font-mono text-slate-500 uppercase">
                            {u.node_code}
                          </span>
                        </label>
                      );
                    })}
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
