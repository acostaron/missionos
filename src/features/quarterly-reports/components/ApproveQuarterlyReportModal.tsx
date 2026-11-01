import { Button, Modal } from '../../../components/ui';

interface Props {
  open: boolean;
  periodLabel: string;
  loading: boolean;
  onClose: () => void;
  onConfirm: () => void;
}

export function ApproveQuarterlyReportModal({ open, periodLabel, loading, onClose, onConfirm }: Props) {
  return (
    <Modal
      open={open}
      onClose={onClose}
      title={`Approve Quarterly Report — ${periodLabel}`}
      footer={
        <div className="flex justify-end gap-2">
          <Button variant="ghost" onClick={onClose} disabled={loading}>
            Cancel
          </Button>
          <Button id="confirm-approve-quarterly-report" onClick={onConfirm} loading={loading}>
            Approve report
          </Button>
        </div>
      }
    >
      <p className="text-sm text-slate-700">
        Approval freezes this report as the historical record for this quarter.
      </p>
      <p className="mt-2 text-sm text-slate-600">
        Later edits to Events, Programs, speakers, service teams, or photos will not change the approved report. The Official
        PDF and Excel will always be generated from this approved version.
      </p>
    </Modal>
  );
}
