import { useState, useId, useMemo, useEffect } from 'react';
import { Modal } from '../../../components/ui/Modal';
import { Button } from '../../../components/ui/Button';
import { Alert } from '../../../components/ui/Alert';
import { localToday } from '../schemas';
import { getSectionErrorMessage } from '../error-message';
import {
  useSectionsOverview,
  useSubAreaPlacementTargets,
  useMoveMemberToSubArea,
} from '../queries';

interface MoveToSubAreaModalProps {
  isOpen: boolean;
  onClose: () => void;
  organizationId: string;
  memberId: string;
  currentSubAreaCode?: string | null;
  currentSectionKind?: string | null;
  onSuccessToast?: (msg: string) => void;
}

export function MoveToSubAreaModal({
  isOpen,
  onClose,
  organizationId,
  memberId,
  currentSubAreaCode,
  currentSectionKind,
  onSuccessToast,
}: MoveToSubAreaModalProps) {
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const titleId = useId();
  const today = localToday();

  const { data: sectionsOverview } = useSectionsOverview(organizationId);
  const moveMutation = useMoveMemberToSubArea();

  const availableSubAreas = useMemo(() => {
    if (!sectionsOverview?.sub_areas) return [];
    return sectionsOverview.sub_areas.filter((sa) => sa.code !== currentSubAreaCode);
  }, [sectionsOverview?.sub_areas, currentSubAreaCode]);

  const [selectedSubAreaNodeId, setSelectedSubAreaNodeId] = useState<string>('');
  const [selectedSectionCode, setSelectedSectionCode] = useState<string>('');
  const [selectedTargetNodeId, setSelectedTargetNodeId] = useState<string>('');
  const [effectiveFrom, setEffectiveFrom] = useState<string>(today);
  const [reason, setReason] = useState<string>('');

  // Set default sub-area when availableSubAreas load
  useEffect(() => {
    if (availableSubAreas.length > 0 && !selectedSubAreaNodeId) {
      setSelectedSubAreaNodeId(availableSubAreas[0].node_id);
    }
  }, [availableSubAreas, selectedSubAreaNodeId]);

  const selectedSubArea = useMemo(() => {
    return availableSubAreas.find((sa) => sa.node_id === selectedSubAreaNodeId);
  }, [availableSubAreas, selectedSubAreaNodeId]);

  // Set default section when chosen sub-area changes
  useEffect(() => {
    if (!selectedSubArea) {
      setSelectedSectionCode('');
      return;
    }
    const matchingKindSection = currentSectionKind
      ? selectedSubArea.sections.find((s) => s.kind === currentSectionKind)
      : null;
    if (matchingKindSection) {
      setSelectedSectionCode(matchingKindSection.code);
    } else if (selectedSubArea.sections.length > 0) {
      setSelectedSectionCode(selectedSubArea.sections[0].code);
    } else {
      setSelectedSectionCode('');
    }
  }, [selectedSubArea, currentSectionKind]);

  // Targets query for the chosen sub-area
  const { data: placementTargets, isLoading: isTargetsLoading } = useSubAreaPlacementTargets(
    organizationId,
    selectedSubAreaNodeId || null
  );

  const { areaTargets, chapterTargets, unitTargets } = useMemo(() => {
    const list = placementTargets ?? [];
    return {
      areaTargets: list.filter((t) => t.node_type === 'area_state'),
      chapterTargets: list.filter((t) => t.node_type === 'chapter'),
      unitTargets: list.filter((t) => t.node_type === 'unit'),
    };
  }, [placementTargets]);

  const handleClose = () => {
    setErrorMessage(null);
    setSelectedSubAreaNodeId('');
    setSelectedSectionCode('');
    setSelectedTargetNodeId('');
    setEffectiveFrom(localToday());
    setReason('');
    onClose();
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);

    if (!selectedSubAreaNodeId) {
      setErrorMessage('Choose a sub-area.');
      return;
    }
    if (!selectedSectionCode) {
      setErrorMessage('Choose a valid section.');
      return;
    }
    if (!selectedTargetNodeId) {
      setErrorMessage('Choose where to place the member.');
      return;
    }
    if (!effectiveFrom || effectiveFrom > today) {
      setErrorMessage('Effective date cannot be in the future.');
      return;
    }
    if (!reason || reason.trim().length < 5) {
      setErrorMessage('A reason of at least 5 characters is required.');
      return;
    }

    try {
      const res = await moveMutation.mutateAsync({
        organizationId,
        memberId,
        sectionCode: selectedSectionCode,
        targetGovernanceNodeId: selectedTargetNodeId,
        effectiveFrom,
        reason: reason.trim(),
      });

      const targetSubAreaName = selectedSubArea?.name ?? 'new sub-area';
      let msg = `Moved to ${targetSubAreaName}.`;
      if (res.paired_member_id) {
        msg += ' Paired with their spouse in Couples.';
      }
      if (onSuccessToast) {
        onSuccessToast(msg);
      }
      handleClose();
    } catch (err) {
      setErrorMessage(getSectionErrorMessage(err));
    }
  };

  const isSubmitting = moveMutation.isPending;

  return (
    <Modal
      open={isOpen}
      onClose={handleClose}
      title={<span id={titleId}>Move to Sub-area</span>}
      description="Move this member's section and governance placement to another sub-area in a single step."
      footer={
        <div className="flex w-full justify-end gap-3">
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
            form="move-to-sub-area-form"
            loading={isSubmitting}
          >
            Move to Sub-area
          </Button>
        </div>
      }
    >
      <form
        id="move-to-sub-area-form"
        onSubmit={handleSubmit}
        className="space-y-4"
        noValidate
      >
        {errorMessage && (
          <Alert variant="danger" title="Unable to move sub-area">
            {errorMessage}
          </Alert>
        )}

        {/* 1. Sub-area */}
        <div>
          <label
            htmlFor="target-sub-area-select"
            className="block text-xs font-medium text-ink"
          >
            Sub-area <span className="text-danger-600">*</span>
          </label>
          <select
            id="target-sub-area-select"
            value={selectedSubAreaNodeId}
            onChange={(e) => {
              setSelectedSubAreaNodeId(e.target.value);
              setSelectedTargetNodeId('');
            }}
            disabled={isSubmitting}
            className="mt-1 block w-full rounded-control border border-line bg-surface px-3 py-2 text-sm text-ink focus:border-focus focus:outline-none focus:ring-1 focus:ring-focus disabled:bg-surface-muted"
          >
            {availableSubAreas.length === 0 && (
              <option value="">No other sub-areas available</option>
            )}
            {availableSubAreas.map((sa) => (
              <option key={sa.node_id} value={sa.node_id}>
                {sa.name}
              </option>
            ))}
          </select>
        </div>

        {/* 2. Section */}
        <div>
          <label
            htmlFor="target-section-select"
            className="block text-xs font-medium text-ink"
          >
            Section <span className="text-danger-600">*</span>
          </label>
          <select
            id="target-section-select"
            value={selectedSectionCode}
            onChange={(e) => setSelectedSectionCode(e.target.value)}
            disabled={isSubmitting || !selectedSubArea}
            className="mt-1 block w-full rounded-control border border-line bg-surface px-3 py-2 text-sm text-ink focus:border-focus focus:outline-none focus:ring-1 focus:ring-focus disabled:bg-surface-muted"
          >
            <option value="">Select a section...</option>
            {selectedSubArea?.sections.map((sec) => (
              <option key={sec.code} value={sec.code}>
                {sec.name}
              </option>
            ))}
          </select>
        </div>

        {/* 3. Place in */}
        <div>
          <label
            htmlFor="target-placement-select"
            className="block text-xs font-medium text-ink"
          >
            Place in <span className="text-danger-600">*</span>
          </label>
          <select
            id="target-placement-select"
            value={selectedTargetNodeId}
            onChange={(e) => setSelectedTargetNodeId(e.target.value)}
            disabled={isSubmitting || isTargetsLoading || !selectedSubAreaNodeId}
            className="mt-1 block w-full rounded-control border border-line bg-surface px-3 py-2 text-sm text-ink focus:border-focus focus:outline-none focus:ring-1 focus:ring-focus disabled:bg-surface-muted"
          >
            <option value="">Select where to place...</option>
            {areaTargets.length > 0 && (
              <optgroup label="Area">
                {areaTargets.map((t) => (
                  <option key={t.node_id} value={t.node_id}>
                    {t.name}
                  </option>
                ))}
              </optgroup>
            )}
            {chapterTargets.length > 0 && (
              <optgroup label="Chapters">
                {chapterTargets.map((t) => (
                  <option key={t.node_id} value={t.node_id}>
                    {t.name}
                  </option>
                ))}
              </optgroup>
            )}
            {unitTargets.length > 0 && (
              <optgroup label="Units">
                {unitTargets.map((t) => (
                  <option key={t.node_id} value={t.node_id}>
                    {t.parent_name ? `${t.name} (${t.parent_name})` : t.name}
                  </option>
                ))}
              </optgroup>
            )}
          </select>
        </div>

        {/* 4. Effective date */}
        <div>
          <label
            htmlFor="move-effective-from-input"
            className="block text-xs font-medium text-ink"
          >
            Effective Date <span className="text-danger-600">*</span>
          </label>
          <input
            type="date"
            id="move-effective-from-input"
            max={today}
            value={effectiveFrom}
            onChange={(e) => setEffectiveFrom(e.target.value)}
            disabled={isSubmitting}
            className="mt-1 block w-full rounded-control border border-line bg-surface px-3 py-2 text-sm text-ink focus:border-focus focus:outline-none focus:ring-1 focus:ring-focus disabled:bg-surface-muted"
          />
        </div>

        {/* 5. Reason */}
        <div>
          <label
            htmlFor="move-reason-textarea"
            className="block text-xs font-medium text-ink"
          >
            Reason <span className="text-danger-600">*</span>
          </label>
          <textarea
            id="move-reason-textarea"
            rows={3}
            placeholder="e.g. Relocated to Spanish-speaking FMC community"
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            disabled={isSubmitting}
            className="mt-1 block w-full rounded-control border border-line bg-surface px-3 py-2 text-sm text-ink focus:border-focus focus:outline-none focus:ring-1 focus:ring-focus disabled:bg-surface-muted"
          />
        </div>
      </form>
    </Modal>
  );
}
