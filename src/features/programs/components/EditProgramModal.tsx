import { useState, useEffect, useId } from 'react';
import {
  Modal,
  Button,
  FormField,
  Input,
  Select,
  Textarea,
  Alert,
} from '../../../components/ui';
import { useUpdateProgramRun } from '../queries';
import { getEventErrorMessage } from '../../events/error-message';
import type { ProgramReportPriority, ProgramRunSummary } from '../types';

interface EditProgramModalProps {
  open: boolean;
  onClose: () => void;
  organizationId: string;
  run: ProgramRunSummary;
  onSuccess?: () => void;
}

export function EditProgramModal({
  open,
  onClose,
  organizationId,
  run,
  onSuccess,
}: EditProgramModalProps) {
  const updateMutation = useUpdateProgramRun();
  const isSubmitting = updateMutation.isPending;

  const [title, setTitle] = useState(run.title);
  const [description, setDescription] = useState(run.description || '');
  const [includeInQuarterlyReport, setIncludeInQuarterlyReport] = useState(run.include_in_quarterly_report ?? false);
  const [reportPriority, setReportPriority] = useState<ProgramReportPriority>(run.report_priority ?? 'routine');
  const [reportHighlight, setReportHighlight] = useState(run.report_highlight || '');
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const titleId = useId();
  const descId = useId();

  useEffect(() => {
    if (open) {
      setTitle(run.title);
      setDescription(run.description || '');
      setIncludeInQuarterlyReport(run.include_in_quarterly_report ?? false);
      setReportPriority(run.report_priority ?? 'routine');
      setReportHighlight(run.report_highlight || '');
      setErrorMessage(null);
    }
  }, [open, run]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);

    const trimmed = title.trim();
    if (trimmed.length < 3) {
      setErrorMessage('Program title must be at least 3 characters.');
      return;
    }

    try {
      await updateMutation.mutateAsync({
        organizationId,
        runId: run.id,
        title: trimmed,
        description: description.trim() || undefined,
        includeInQuarterlyReport,
        reportPriority,
        reportHighlight: reportHighlight.trim() || undefined,
      });
      onSuccess?.();
      onClose();
    } catch (err) {
      setErrorMessage(getEventErrorMessage(err));
    }
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Edit Program"
      size="md"
      footer={
        <div className="flex w-full items-center justify-end gap-3">
          <Button variant="outline" onClick={onClose} disabled={isSubmitting}>
            Cancel
          </Button>
          <Button
            type="submit"
            form="edit-program-form"
            loading={isSubmitting}
            variant="primary"
          >
            Save Changes
          </Button>
        </div>
      }
    >
      <form id="edit-program-form" onSubmit={handleSubmit} className="space-y-4">
        {errorMessage && (
          <Alert variant="danger">
            {errorMessage}
          </Alert>
        )}

        <FormField label="Title" required>
          <Input
            id={titleId}
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            disabled={isSubmitting}
            maxLength={200}
            required
          />
        </FormField>

        <FormField label="Description (optional)">
          <Textarea
            id={descId}
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            disabled={isSubmitting}
            maxLength={2000}
            rows={3}
          />
        </FormField>

        {/* Quarterly Ministry Reporting */}
        <div className="border-t border-mist pt-4 space-y-4">
          <div className="flex items-start gap-2">
            <input
              type="checkbox"
              id="edit-program-quarterly-report"
              checked={includeInQuarterlyReport}
              onChange={(e) => setIncludeInQuarterlyReport(e.target.checked)}
              disabled={isSubmitting}
              className="mt-1 h-4 w-4 rounded border-mist text-primary focus:ring-primary"
            />
            <div>
              <label
                htmlFor="edit-program-quarterly-report"
                className="text-small font-medium text-ink cursor-pointer"
              >
                Include in Quarterly Report
              </label>
              <p className="text-caption text-ink-muted">
                Mark this program to be included in national and area quarterly ministry reporting.
              </p>
            </div>
          </div>

          {includeInQuarterlyReport && (
            <div className="space-y-4 pl-6 border-l-2 border-primary/20">
              <FormField label="Report Priority">
                <Select
                  value={reportPriority}
                  onChange={(e) => setReportPriority(e.target.value as ProgramReportPriority)}
                  disabled={isSubmitting}
                >
                  <option value="routine">Routine</option>
                  <option value="ministry_activity">Ministry Activity</option>
                  <option value="major_highlight">Major Highlight</option>
                </Select>
              </FormField>

              <FormField
                label="Program Highlight / Accomplishment"
                hint="Briefly describe the main outcome, accomplishment, or ministry highlight from this program."
              >
                <Textarea
                  value={reportHighlight}
                  onChange={(e) => setReportHighlight(e.target.value)}
                  placeholder="Key milestones, attendance highlights, spiritual fruits, or breakthrough stories..."
                  disabled={isSubmitting}
                  maxLength={2000}
                  rows={3}
                />
              </FormField>
            </div>
          )}
        </div>
      </form>
    </Modal>
  );
}
