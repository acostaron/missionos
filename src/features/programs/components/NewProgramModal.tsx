import { useState, useEffect, useId, useMemo } from 'react';
import {
  Modal,
  Button,
  FormField,
  Input,
  Select,
  Textarea,
  Alert,
} from '../../../components/ui';
import { PROGRAM_CODE_LABELS } from '../labels';
import { useCreateProgramRun } from '../queries';
import { useEventAudienceOptions } from '../../events/queries';
import { getEventErrorMessage } from '../../events/error-message';
import type { ProgramCode, ProgramRunSummary } from '../types';

interface NewProgramModalProps {
  open: boolean;
  onClose: () => void;
  organizationId: string;
  onSuccess?: (run: ProgramRunSummary) => void;
}

const CLS_SECTION_KINDS = ['couples', 'handmaids', 'servants', 'singles'];

export function NewProgramModal({
  open,
  onClose,
  organizationId,
  onSuccess,
}: NewProgramModalProps) {
  const { data: audienceData } = useEventAudienceOptions(organizationId, open);
  const createMutation = useCreateProgramRun();
  const isSubmitting = createMutation.isPending;

  const [programCode, setProgramCode] = useState<ProgramCode>('youth_camp');
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [chapterCode, setChapterCode] = useState('');
  const [selectedSectionCodes, setSelectedSectionCodes] = useState<string[]>([]);
  const [sessionCount, setSessionCount] = useState<number>(1);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const programId = useId();
  const titleId = useId();
  const descId = useId();
  const chapterId = useId();
  const sectionId = useId();
  const sessionsId = useId();

  // Audience categorization
  const chapterOptions = useMemo(
    () => audienceData?.options.filter((o) => o.type === 'chapter') ?? [],
    [audienceData?.options]
  );

  const sectionOptions = useMemo(
    () => audienceData?.options.filter((o) => o.type === 'section') ?? [],
    [audienceData?.options]
  );

  const youthSections = useMemo(
    () => sectionOptions.filter((s) => s.code.endsWith('sec_youth')),
    [sectionOptions]
  );

  const campusSections = useMemo(
    () => sectionOptions.filter((s) => s.code.endsWith('sec_campus')),
    [sectionOptions]
  );

  // CLS sections: match chosen chapter's sub-area
  const chosenChapter = useMemo(
    () => chapterOptions.find((c) => c.code === chapterCode),
    [chapterOptions, chapterCode]
  );

  const clsAllowedSections = useMemo(() => {
    if (!chosenChapter) return [];
    return sectionOptions.filter((s) => {
      const matchSubArea =
        s.sub_area_code && chosenChapter.sub_area_code
          ? s.sub_area_code === chosenChapter.sub_area_code
          : true;
      const isClsKind = CLS_SECTION_KINDS.some((kind) => s.code.endsWith(`sec_${kind}`));
      return matchSubArea && isClsKind;
    });
  }, [chosenChapter, sectionOptions]);

  // Helper for generating default title
  const generateDefaultTitle = (
    code: ProgramCode,
    sections: string[],
    secOpts: typeof sectionOptions
  ) => {
    const currentYear = new Date().getFullYear();
    const currentMonthYear = new Intl.DateTimeFormat('en-US', {
      month: 'short',
      year: 'numeric',
    }).format(new Date());

    if (code === 'youth_camp') {
      return `Youth Camp ${currentYear}`;
    }
    if (code === 'discovery_camp') {
      return `Discovery Camp ${currentYear}`;
    }
    if (code === 'cls') {
      const names = sections
        .map((sc) => secOpts.find((o) => o.code === sc)?.name)
        .filter(Boolean);
      const secStr = names.length > 0 ? names.join(' / ') : 'Couples';
      return `CLS ${secStr} ${currentMonthYear}`;
    }
    return `Program / Retreat ${currentYear}`;
  };

  // Reset form when modal opens
  useEffect(() => {
    if (!open) {
      setErrorMessage(null);
      return;
    }

    setProgramCode('youth_camp');
    setSessionCount(1);
    setDescription('');
    setErrorMessage(null);

    const firstYouth = youthSections[0]?.code;
    const initialSections = firstYouth ? [firstYouth] : [];
    setSelectedSectionCodes(initialSections);

    const firstChapter = chapterOptions[0]?.code || '';
    setChapterCode(firstChapter);

    setTitle(`Youth Camp ${new Date().getFullYear()}`);
  }, [open, chapterOptions, youthSections]);

  const handleProgramChange = (newCode: ProgramCode) => {
    setProgramCode(newCode);

    if (newCode === 'youth_camp') {
      const ySec = youthSections[0]?.code;
      const secs = ySec ? [ySec] : [];
      setSelectedSectionCodes(secs);
      setSessionCount(1);
      setTitle(generateDefaultTitle(newCode, secs, youthSections));
    } else if (newCode === 'discovery_camp') {
      const cSec = campusSections[0]?.code;
      const secs = cSec ? [cSec] : [];
      setSelectedSectionCodes(secs);
      setSessionCount(1);
      setTitle(generateDefaultTitle(newCode, secs, campusSections));
    } else if (newCode === 'cls') {
      const defaultChap = chapterCode || chapterOptions[0]?.code || '';
      setChapterCode(defaultChap);
      setSessionCount(6);

      // Find first couples section matching chapter
      const chapObj = chapterOptions.find((c) => c.code === defaultChap);
      const matchingSecs = sectionOptions.filter((s) => {
        const matchSub =
          s.sub_area_code && chapObj?.sub_area_code
            ? s.sub_area_code === chapObj.sub_area_code
            : true;
        return matchSub && CLS_SECTION_KINDS.some((kind) => s.code.endsWith(`sec_${kind}`));
      });
      const firstCouples =
        matchingSecs.find((s) => s.code.endsWith('sec_couples'))?.code || matchingSecs[0]?.code;
      const secs = firstCouples ? [firstCouples] : [];
      setSelectedSectionCodes(secs);
      setTitle(generateDefaultTitle(newCode, secs, sectionOptions));
    } else {
      setSelectedSectionCodes([]);
      setSessionCount(1);
      setTitle(`Program / Retreat ${new Date().getFullYear()}`);
    }
  };

  const handleChapterChange = (newChapterCode: string) => {
    setChapterCode(newChapterCode);
    if (programCode === 'cls') {
      const chapObj = chapterOptions.find((c) => c.code === newChapterCode);
      const matchingSecs = sectionOptions.filter((s) => {
        const matchSub =
          s.sub_area_code && chapObj?.sub_area_code
            ? s.sub_area_code === chapObj.sub_area_code
            : true;
        return matchSub && CLS_SECTION_KINDS.some((kind) => s.code.endsWith(`sec_${kind}`));
      });
      const firstCouples =
        matchingSecs.find((s) => s.code.endsWith('sec_couples'))?.code || matchingSecs[0]?.code;
      const secs = firstCouples ? [firstCouples] : [];
      setSelectedSectionCodes(secs);
      setTitle(generateDefaultTitle('cls', secs, sectionOptions));
    }
  };

  const handleClsSectionToggle = (code: string) => {
    setSelectedSectionCodes((prev) => {
      const next = prev.includes(code) ? prev.filter((c) => c !== code) : [...prev, code];
      setTitle(generateDefaultTitle('cls', next, sectionOptions));
      return next;
    });
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);

    const trimmedTitle = title.trim();
    if (trimmedTitle.length < 3) {
      setErrorMessage('Program title must be at least 3 characters.');
      return;
    }

    if (programCode === 'cls') {
      if (!chapterCode) {
        setErrorMessage('Please select a chapter for the Christian Life Seminar.');
        return;
      }
      if (selectedSectionCodes.length === 0) {
        setErrorMessage('Please select at least one section mounting the CLS.');
        return;
      }
    } else if (programCode === 'youth_camp') {
      if (selectedSectionCodes.length !== 1) {
        setErrorMessage('Please select a Youth section.');
        return;
      }
    } else if (programCode === 'discovery_camp') {
      if (selectedSectionCodes.length !== 1) {
        setErrorMessage('Please select a Campus section.');
        return;
      }
    }

    try {
      const res = await createMutation.mutateAsync({
        organizationId,
        programCode,
        title: trimmedTitle,
        description: description.trim() || undefined,
        chapterCode: chapterCode || undefined,
        sectionCodes: selectedSectionCodes,
        sessionCount,
      });

      onSuccess?.(res.run);
      onClose();
    } catch (err) {
      setErrorMessage(getEventErrorMessage(err));
    }
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="New Program"
      size="md"
      footer={
        <div className="flex w-full items-center justify-end gap-3">
          <Button variant="outline" onClick={onClose} disabled={isSubmitting}>
            Cancel
          </Button>
          <Button
            type="submit"
            form="new-program-form"
            loading={isSubmitting}
            variant="primary"
          >
            Create Program
          </Button>
        </div>
      }
    >
      <form id="new-program-form" onSubmit={handleSubmit} className="space-y-4">
        {errorMessage && (
          <Alert variant="danger">
            {errorMessage}
          </Alert>
        )}

        <FormField label="Program" required>
          <Select
            id={programId}
            value={programCode}
            onChange={(e) => handleProgramChange(e.target.value as ProgramCode)}
            disabled={isSubmitting}
          >
            {(Object.keys(PROGRAM_CODE_LABELS) as ProgramCode[]).map((code) => (
              <option key={code} value={code}>
                {PROGRAM_CODE_LABELS[code]}
              </option>
            ))}
          </Select>
        </FormField>

        <FormField label="Title" required>
          <Input
            id={titleId}
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="Program title..."
            disabled={isSubmitting}
            maxLength={200}
            required
          />
        </FormField>

        {/* Program-specific Fields */}
        {programCode === 'youth_camp' && (
          <FormField label="Section" required>
            {youthSections.length === 0 ? (
              <p className="rounded-control border border-line bg-surface-muted p-2.5 text-small text-ink-muted">
                No active Youth sections available.
              </p>
            ) : (
              <Select
                id={sectionId}
                value={selectedSectionCodes[0] || ''}
                onChange={(e) => {
                  const val = e.target.value;
                  const secs = val ? [val] : [];
                  setSelectedSectionCodes(secs);
                  setTitle(generateDefaultTitle('youth_camp', secs, youthSections));
                }}
                disabled={isSubmitting}
                required
              >
                {youthSections.map((s) => (
                  <option key={s.code} value={s.code}>
                    {s.sub_area_name ? `${s.sub_area_name} · ` : ''}{s.name}
                  </option>
                ))}
              </Select>
            )}
          </FormField>
        )}

        {programCode === 'discovery_camp' && (
          <FormField label="Section" required>
            {campusSections.length === 0 ? (
              <p className="rounded-control border border-line bg-surface-muted p-2.5 text-small text-ink-muted">
                No active Campus sections available.
              </p>
            ) : (
              <Select
                id={sectionId}
                value={selectedSectionCodes[0] || ''}
                onChange={(e) => {
                  const val = e.target.value;
                  const secs = val ? [val] : [];
                  setSelectedSectionCodes(secs);
                  setTitle(generateDefaultTitle('discovery_camp', secs, campusSections));
                }}
                disabled={isSubmitting}
                required
              >
                {campusSections.map((s) => (
                  <option key={s.code} value={s.code}>
                    {s.sub_area_name ? `${s.sub_area_name} · ` : ''}{s.name}
                  </option>
                ))}
              </Select>
            )}
          </FormField>
        )}

        {programCode === 'cls' && (
          <>
            <FormField label="Chapter" required>
              <Select
                id={chapterId}
                value={chapterCode}
                onChange={(e) => handleChapterChange(e.target.value)}
                disabled={isSubmitting}
                required
              >
                {chapterOptions.map((c) => (
                  <option key={c.code} value={c.code}>
                    {c.sub_area_name ? `${c.sub_area_name} · ` : ''}{c.name}
                  </option>
                ))}
              </Select>
            </FormField>

            <FormField label="Sections mounting the CLS" required>
              <div>
                <div className="space-y-2 rounded-control border border-line p-3 bg-surface">
                  {clsAllowedSections.length === 0 ? (
                    <p className="text-small text-ink-muted">
                      No sections found in this chapter's sub-area.
                    </p>
                  ) : (
                    clsAllowedSections.map((sec) => (
                      <label key={sec.code} className="flex items-center gap-2.5 text-body text-ink cursor-pointer">
                        <input
                          type="checkbox"
                          checked={selectedSectionCodes.includes(sec.code)}
                          onChange={() => handleClsSectionToggle(sec.code)}
                          className="h-4 w-4 rounded border-line text-primary focus:ring-focus"
                          disabled={isSubmitting}
                        />
                        <span>{sec.name}</span>
                      </label>
                    ))
                  )}
                </div>
                {selectedSectionCodes.length > 1 && (
                  <p className="mt-1 text-caption font-semibold text-warning-700">
                    ⚡ Mega CLS (multiple sections combined)
                  </p>
                )}
              </div>
            </FormField>

            <FormField label="Number of sessions" required>
              <Select
                id={sessionsId}
                value={sessionCount}
                onChange={(e) => setSessionCount(Number(e.target.value))}
                disabled={isSubmitting}
              >
                <option value={6}>6 sessions (standard)</option>
                <option value={9}>9 sessions (extended)</option>
              </Select>
            </FormField>
          </>
        )}

        {programCode === 'other_program' && (
          <>
            <FormField label="Chapter (optional)">
              <Select
                id={chapterId}
                value={chapterCode}
                onChange={(e) => setChapterCode(e.target.value)}
                disabled={isSubmitting}
              >
                <option value="">None (all or section-based)</option>
                {chapterOptions.map((c) => (
                  <option key={c.code} value={c.code}>
                    {c.sub_area_name ? `${c.sub_area_name} · ` : ''}{c.name}
                  </option>
                ))}
              </Select>
            </FormField>

            <FormField label="Number of sessions (1–30)" required>
              <Input
                id={sessionsId}
                type="number"
                min={1}
                max={30}
                value={sessionCount}
                onChange={(e) => setSessionCount(Math.max(1, Math.min(30, parseInt(e.target.value) || 1)))}
                disabled={isSubmitting}
                required
              />
            </FormField>
          </>
        )}

        <FormField label="Description (optional)">
          <Textarea
            id={descId}
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="Program overview, goals, venue details..."
            disabled={isSubmitting}
            maxLength={2000}
            rows={3}
          />
        </FormField>
      </form>
    </Modal>
  );
}
