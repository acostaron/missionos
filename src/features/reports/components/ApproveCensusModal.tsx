import { AlertTriangle } from 'lucide-react';
import { Modal } from '../../../components/ui/Modal';
import { Button } from '../../../components/ui/Button';

interface ApproveCensusModalProps {
  open: boolean;
  onClose: () => void;
  onConfirm: () => void;
  isSubmitting?: boolean;
  periodYear: number;
  periodQuarter: number;
  totalMembers: number;
}

export function ApproveCensusModal({
  open,
  onClose,
  onConfirm,
  isSubmitting = false,
  periodYear,
  periodQuarter,
  totalMembers,
}: ApproveCensusModalProps) {
  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Approve Quarterly Census"
      size="md"
      footer={
        <div className="flex w-full items-center justify-end gap-3">
          <Button
            type="button"
            variant="ghost"
            onClick={onClose}
            disabled={isSubmitting}
          >
            Cancel
          </Button>
          <Button
            type="button"
            variant="primary"
            onClick={onConfirm}
            loading={isSubmitting}
          >
            Approve Census
          </Button>
        </div>
      }
    >
      <div className="space-y-4">
        <div className="flex items-start gap-3 rounded-lg border border-warning-200 bg-warning-50 p-3.5 text-sm text-warning-800">
          <AlertTriangle className="mt-0.5 h-5 w-5 shrink-0 text-warning-600" />
          <div className="space-y-1">
            <p className="font-semibold text-ink">
              Approve {periodYear} Q{periodQuarter} Quarterly Census?
            </p>
            <p className="text-ink-muted">
              Once approved, this census snapshot will be <strong>frozen</strong> and will not
              automatically change when underlying membership records are updated or transferred.
            </p>
          </div>
        </div>

        <div className="rounded-lg border border-border-subtle bg-surface-muted/50 p-3 text-sm">
          <div className="flex justify-between py-1">
            <span className="text-ink-muted">Reporting Period:</span>
            <span className="font-medium text-ink">
              {periodYear} — Quarter {periodQuarter}
            </span>
          </div>
          <div className="flex justify-between py-1">
            <span className="text-ink-muted">Total Active Members:</span>
            <span className="font-bold text-ink">{totalMembers}</span>
          </div>
        </div>

        <p className="text-caption text-ink-muted">
          This official census snapshot will serve as the historical baseline for all subsequent
          quarterly comparisons and national ministry reporting.
        </p>
      </div>
    </Modal>
  );
}
