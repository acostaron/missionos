import type { ReactNode } from 'react';

/** 2 columns on mobile and tablet, 4 on wide screens. */
export default function DashboardMetricGrid({ children }: { children: ReactNode }) {
  return <div className="grid grid-cols-2 gap-3 sm:gap-4 lg:grid-cols-4">{children}</div>;
}
