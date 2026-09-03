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
    <div className="flex min-h-[40vh] items-center justify-center">
      <div className="text-sm text-slate-400">Loading…</div>
    </div>
  );
}
