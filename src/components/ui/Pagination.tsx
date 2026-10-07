import { ChevronLeft, ChevronRight } from 'lucide-react';
import { Button } from './Button';
import { cx } from './cx';

export interface PaginationProps {
  /** Zero-based current page. */
  page: number;
  totalPages: number;
  onPageChange: (page: number) => void;
  className?: string;
}

/** Previous / Next pager with a "Page X of Y" label. Renders nothing for a single page. */
export function Pagination({ page, totalPages, onPageChange, className }: PaginationProps) {
  if (totalPages <= 1) return null;
  return (
    <nav aria-label="Pagination" className={cx('flex items-center justify-between gap-3', className)}>
      <Button
        variant="outline"
        size="sm"
        icon={<ChevronLeft className="h-4 w-4" aria-hidden="true" />}
        disabled={page <= 0}
        onClick={() => onPageChange(Math.max(0, page - 1))}
      >
        Previous
      </Button>
      <span className="text-small text-ink-muted" aria-live="polite">
        Page {page + 1} of {totalPages}
      </span>
      <Button
        variant="outline"
        size="sm"
        disabled={page >= totalPages - 1}
        onClick={() => onPageChange(Math.min(totalPages - 1, page + 1))}
      >
        Next
        <ChevronRight className="h-4 w-4" aria-hidden="true" />
      </Button>
    </nav>
  );
}