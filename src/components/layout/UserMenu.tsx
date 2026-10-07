import { useEffect, useRef, useState } from 'react';
import { CircleUser, LogOut } from 'lucide-react';

type Props = {
  email?: string | null;
  organizationName?: string | null;
  onSignOut: () => void;
};

/** Compact account menu used in the mobile header. */
export default function UserMenu({ email, organizationName, onSignOut }: Props) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setOpen(false);
    };
    document.addEventListener('mousedown', onDown);
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('mousedown', onDown);
      document.removeEventListener('keydown', onKey);
    };
  }, [open]);

  return (
    <div ref={ref} className="relative">
      <button
        type="button"
        aria-label="Account menu"
        aria-expanded={open}
        aria-haspopup="menu"
        onClick={() => setOpen((v) => !v)}
        className="rounded-full p-1.5 text-ink-muted hover:bg-canvas focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus"
      >
        <CircleUser size={26} />
      </button>
      {open && (
        <div
          role="menu"
          className="absolute right-0 top-full z-40 mt-2 w-64 max-w-[calc(100vw-2rem)] rounded-xl border border-line bg-surface p-2 shadow-lg"
        >
          <div className="px-3 py-2">
            <div className="truncate text-sm font-medium text-ink">{email}</div>
            {organizationName && (
              <div className="truncate text-xs text-ink-muted">{organizationName}</div>
            )}
          </div>
          <button
            type="button"
            role="menuitem"
            id="nav-sign-out-mobile"
            onClick={onSignOut}
            className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm font-medium text-ink hover:bg-canvas focus-visible:outline-2 focus-visible:outline-focus"
          >
            <LogOut size={16} aria-hidden="true" /> Sign out
          </button>
        </div>
      )}
    </div>
  );
}
