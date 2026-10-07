import { Loader2 } from 'lucide-react';

/**
 * Lightweight Suspense fallback for lazily loaded app pages.
 *
 * Renders inside AppLayout (which is already mounted), so it only needs to
 * fill the content area, not the full viewport. Kept in its own module so
 * that router.tsx remains a non-component file and satisfies the
 * react/only-export-components lint rule.
 */
export default function PageLoadingFallback() {
  return (
    <div
      role="status"
      aria-live="polite"
      className="flex min-h-[40vh] items-center justify-center gap-2 text-small text-ink-muted"
    >
      <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />
      <span>Loading…</span>
    </div>
  );
}