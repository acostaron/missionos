import UserMenu from './UserMenu';

type Props = {
  email?: string | null;
  organizationName?: string | null;
  onSignOut: () => void;
};

export default function AppHeader({ email, organizationName, onSignOut }: Props) {
  return (
    <header className="sticky top-0 z-20 flex h-16 items-center justify-between gap-3 border-b border-line bg-surface/90 px-4 backdrop-blur sm:px-6 lg:px-8">
      <div className="min-w-0 md:hidden">
        <span className="text-base font-bold text-primary">MissionOS</span>
      </div>
      <div className="hidden min-w-0 md:block" />
      <div className="flex min-w-0 items-center gap-3">
        {organizationName && (
          <span className="hidden max-w-[16rem] truncate text-sm text-ink-muted md:inline">
            {organizationName}
          </span>
        )}
        <div className="md:hidden">
          <UserMenu email={email} organizationName={organizationName} onSignOut={onSignOut} />
        </div>
      </div>
    </header>
  );
}
