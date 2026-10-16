import type { ReactNode } from 'react';

/** Pass 9.19: 4 compact tiles in one row on phones (Home fits one screen), 4 on wide screens. */
export default function DashboardMetricGrid({ children }: { children: ReactNode }) {
  return <div className="grid grid-cols-4 gap-2 sm:gap-4">{children}</div>;
}
