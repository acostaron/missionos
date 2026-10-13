import { useState, useMemo } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { Modal } from '../../../components/ui/Modal';
import { Button } from '../../../components/ui/Button';
import { Alert } from '../../../components/ui/Alert';
import { usePlacementNodes } from '../../members/api/get-placement-nodes';
import { usePlaceMembersBulk } from '../queries';
import { placeMembersSchema, type PlaceMembersFormValues } from '../schemas';
import { getPlacementErrorMessage, formatSkipReason } from '../error-message';
import { localToday } from '../../formation/form-schemas';
import type { SelectedMemberInfo, PlaceMembersBulkResponse } from '../types';

interface PlaceMembersModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  selectedMembers: Map<string, SelectedMemberInfo>;
  onPlacementComplete: (placedMemberIds: string[]) => void;
}

export function PlaceMembersModal({
  isOpen,
  onClose,
  organizationId,
  selectedMembers,
  onPlacementComplete,
}: PlaceMembersModalProps) {
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [result, setResult] = useState<PlaceMembersBulkResponse | null>(null);

  const { data: nodes = [], isLoading: isNodesLoading } = usePlacementNodes(
    organizationId,
    isOpen
  );

  const placeMutation = usePlaceMembersBulk(organizationId);

  const today = localToday();

  const {
    register,
    handleSubmit,
    watch,
    reset,
    formState: { errors, isSubmitting },
  } = useForm<PlaceMembersFormValues>({
    resolver: zodResolver(placeMembersSchema),
    defaultValues: {
      targetNodeId: '',
      effectiveFrom: today,
      reason: '',
    },
  });

  const selectedTargetNodeId = watch('targetNodeId');
  const selectedEffectiveFrom = watch('effectiveFrom') || today;

  // Group chapters and units
  const { chapters, unitsByChapter } = useMemo(() => {
    const chs = nodes.filter((n) => n.node_type_code === 'chapter');
    chs.sort((a, b) => a.node_name.localeCompare(b.node_name));

    const unitMap = new Map<string, typeof nodes>();
    for (const u of nodes) {
      if (u.node_type_code === 'unit' && u.parent_governance_node_id) {
        const existing = unitMap.get(u.parent_governance_node_id) || [];
        existing.push(u);
        unitMap.set(u.parent_governance_node_id, existing);
      }
    }
    for (const [, list] of unitMap) {
      list.sort((a, b) => a.node_name.localeCompare(b.node_name));
    }
    return { chapters: chs, unitsByChapter: unitMap };
  }, [nodes]);

  // Selected target label
  const targetLabel = useMemo(() => {
    if (!selectedTargetNodeId) return '';
    const found = nodes.find((n) => n.governance_node_id === selectedTargetNodeId);
    if (!found) return '';
    if (found.node_type_code === 'chapter') {
      return `${found.node_name} (chapter only)`;
    }
    return found.parent_node_name
      ? `${found.node_name} · ${found.parent_node_name}`
      : found.node_name;
  }, [nodes, selectedTargetNodeId]);

  const selectedCount = selectedMembers.size;
  const selectedList = useMemo(() => Array.from(selectedMembers.entries()), [selectedMembers]);
  const placedAlreadyCount = useMemo(
    () => selectedList.filter(([, info]) => info.has_placement).length,
    [selectedList]
  );

  const handleClose = () => {
    setErrorMessage(null);
    setResult(null);
    reset({
      targetNodeId: '',
      effectiveFrom: localToday(),
      reason: '',
    });
    onClose();
  };

  const handleDone = () => {
    if (result) {
      const placedIds = result.placed.map((p) => p.member_id);
      onPlacementComplete(placedIds);
    }
    handleClose();
  };

  const onSubmit = async (values: PlaceMembersFormValues) => {
    setErrorMessage(null);
    try {
      const memberIds = Array.from(selectedMembers.keys());
      const res = await placeMutation.mutateAsync({
        memberIds,
        targetNodeId: values.targetNodeId,
        effectiveFrom: values.effectiveFrom,
        reason: values.reason,
      });
      setResult(res);
    } catch (err) {
      setErrorMessage(getPlacementErrorMessage(err));
    }
  };

  return (
    <Modal
      open={isOpen}
      onClose={handleClose}
      title={result ? 'Placement Results' : 'Place Members'}
      description={
        result
          ? undefined
          : 'Assign selected members to a chapter or unit. Placements are recorded in the member history.'
      }
      size="md"
      closeOnBackdrop={false}
    >
      {result ? (
        <div className="space-y-4">
          <div className="rounded-lg border border-emerald-500/30 bg-emerald-500/10 p-4">
            <p className="text-sm font-medium text-emerald-400">
              Placed {result.placed_count} {result.placed_count === 1 ? 'member' : 'members'}.
            </p>
          </div>

          {result.skipped_count > 0 && (
            <div className="space-y-2">
              <p className="text-sm font-medium text-amber-400">
                Skipped {result.skipped_count}:
              </p>
              <div className="max-h-48 overflow-y-auto space-y-2 rounded-lg border border-border p-3 bg-surface-subtle">
                {result.skipped.map((s) => {
                  const info = selectedMembers.get(s.member_id);
                  const name = info?.display_name || s.member_id;
                  const reason = formatSkipReason(s.reason, s.message);
                  return (
                    <div
                      key={s.member_id}
                      className="flex items-center justify-between text-xs py-1 border-b border-border/50 last:border-b-0"
                    >
                      <span className="font-medium text-ink">{name}</span>
                      <span className="text-ink-muted">{reason}</span>
                    </div>
                  );
                })}
              </div>
            </div>
          )}

          <div className="flex justify-end pt-2">
            <Button variant="primary" onClick={handleDone}>
              Done
            </Button>
          </div>
        </div>
      ) : (
        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
          {errorMessage && <Alert variant="danger">{errorMessage}</Alert>}

          {/* Target Chapter or Unit */}
          <div>
            <label
              htmlFor="target-select"
              className="block text-xs font-semibold text-ink-muted uppercase tracking-wider mb-1"
            >
              Target Chapter or Unit <span className="text-rose-400">*</span>
            </label>
            <select
              id="target-select"
              {...register('targetNodeId')}
              disabled={isNodesLoading || isSubmitting}
              className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm text-ink focus:border-accent focus:outline-none focus:ring-1 focus:ring-accent"
            >
              <option value="">Select chapter or unit...</option>
              {chapters.map((ch) => {
                const childUnits = unitsByChapter.get(ch.governance_node_id) || [];
                return (
                  <optgroup key={ch.governance_node_id} label={ch.node_name}>
                    <option value={ch.governance_node_id}>
                      {ch.node_name} (chapter only)
                    </option>
                    {childUnits.map((u) => (
                      <option key={u.governance_node_id} value={u.governance_node_id}>
                        {u.node_name}
                      </option>
                    ))}
                  </optgroup>
                );
              })}
            </select>
            {errors.targetNodeId && (
              <p className="mt-1 text-xs text-rose-400">{errors.targetNodeId.message}</p>
            )}
          </div>

          {/* Effective Date */}
          <div>
            <label
              htmlFor="effective-date-input"
              className="block text-xs font-semibold text-ink-muted uppercase tracking-wider mb-1"
            >
              Effective Date <span className="text-rose-400">*</span>
            </label>
            <input
              id="effective-date-input"
              type="date"
              max={today}
              {...register('effectiveFrom')}
              disabled={isSubmitting}
              className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm text-ink focus:border-accent focus:outline-none focus:ring-1 focus:ring-accent"
            />
            {errors.effectiveFrom && (
              <p className="mt-1 text-xs text-rose-400">{errors.effectiveFrom.message}</p>
            )}
          </div>

          {/* Reason */}
          <div>
            <label
              htmlFor="reason-textarea"
              className="block text-xs font-semibold text-ink-muted uppercase tracking-wider mb-1"
            >
              Reason <span className="text-rose-400">*</span>
            </label>
            <textarea
              id="reason-textarea"
              rows={3}
              placeholder="e.g., Initial pastoral assignment per chapter plan"
              {...register('reason')}
              disabled={isSubmitting}
              className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm text-ink focus:border-accent focus:outline-none focus:ring-1 focus:ring-accent placeholder:text-ink-muted/50"
            />
            {errors.reason && (
              <p className="mt-1 text-xs text-rose-400">{errors.reason.message}</p>
            )}
          </div>

          {/* Summary before confirming */}
          <div className="rounded-lg border border-border bg-surface-subtle p-3 space-y-2">
            <p className="text-xs font-medium text-ink">
              {targetLabel
                ? `Place ${selectedCount} ${selectedCount === 1 ? 'member' : 'members'} in ${targetLabel}, effective ${selectedEffectiveFrom}.`
                : `Place ${selectedCount} ${selectedCount === 1 ? 'member' : 'members'} effective ${selectedEffectiveFrom}.`}
            </p>

            {placedAlreadyCount > 0 && (
              <p className="text-xs text-amber-400">
                {placedAlreadyCount} of these already {placedAlreadyCount === 1 ? 'has' : 'have'} a placement. They will be moved, and their previous placement stays in their history.
              </p>
            )}

            {/* Scrollable list of selected members */}
            <div className="max-h-48 overflow-y-auto divide-y divide-border/40 rounded border border-border/60 bg-surface px-2 py-1">
              {selectedList.map(([id, info]) => (
                <div key={id} className="py-1 text-xs flex items-center justify-between">
                  <span className="font-medium text-ink">{info.display_name}</span>
                  {info.member_number && (
                    <span className="text-[11px] font-mono text-ink-muted">
                      {info.member_number}
                    </span>
                  )}
                </div>
              ))}
            </div>
          </div>

          {/* Modal Footer / Actions */}
          <div className="flex justify-end gap-3 pt-2">
            <Button
              type="button"
              variant="outline"
              onClick={handleClose}
              disabled={isSubmitting}
            >
              Cancel
            </Button>
            <Button
              type="submit"
              variant="primary"
              disabled={isSubmitting || selectedCount === 0}
            >
              {isSubmitting
                ? 'Placing members...'
                : `Place ${selectedCount} ${selectedCount === 1 ? 'member' : 'members'}`}
            </Button>
          </div>
        </form>
      )}
    </Modal>
  );
}
