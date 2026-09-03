import { lazy, Suspense } from 'react';
import { createBrowserRouter, Navigate } from 'react-router-dom';
import LoginPage from '../pages/LoginPage';
import DashboardPage from '../pages/DashboardPage';
import AppLayout from '../components/layout/AppLayout';
import { ProtectedRoute } from '../components/auth/ProtectedRoute';
import PageLoadingFallback from '../components/ui/PageLoadingFallback';
import { MembersPage, MemberProfilePage } from './lazy-pages';

/**
 * Development-only RLS diagnostics page.
 *
 * Loaded via dynamic import so the module is tree-shaken in production builds.
 * The route registration itself is also conditional on import.meta.env.DEV,
 * meaning it will never appear in the production route table.
 */
const RlsDiagnosticsPage = import.meta.env.DEV
  ? lazy(() => import('../features/diagnostics/RlsDiagnosticsPage'))
  : null;

const DiagnosticsLoadingFallback = (
  <div
    style={{
      minHeight: '100vh',
      background: '#020617',
      color: '#64748b',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      fontFamily: 'monospace',
    }}
  >
    Loading diagnostics…
  </div>
);

/**
 * Routes that only exist in development.
 *
 * Uses ProtectedRoute as the parent layout (which renders <Outlet />),
 * and the lazy-loaded diagnostics page as the child element.
 * Empty array in production builds.
 */
const devRoutes = import.meta.env.DEV && RlsDiagnosticsPage
  ? [
      {
        path: '/dev',
        element: <ProtectedRoute />,
        children: [
          {
            path: 'rls-tests',
            element: (
              <Suspense fallback={DiagnosticsLoadingFallback}>
                <RlsDiagnosticsPage />
              </Suspense>
            ),
          },
        ],
      },
    ]
  : [];

export const router = createBrowserRouter([
  {
    path: '/login',
    element: <LoginPage />,
  },
  {
    path: '/app',
    element: <ProtectedRoute />,
    children: [
      {
        element: <AppLayout />,
        children: [
          {
            path: 'dashboard',
            element: <DashboardPage />,
          },
          {
            path: 'members',
            element: (
              <Suspense fallback={<PageLoadingFallback />}>
                <MembersPage />
              </Suspense>
            ),
          },
          {
            path: 'members/:memberId',
            element: (
              <Suspense fallback={<PageLoadingFallback />}>
                <MemberProfilePage />
              </Suspense>
            ),
          },
          {
            index: true,
            element: <Navigate to="/app/dashboard" replace />,
          }
        ],
      },
    ],
  },
  // Development-only routes (empty array in production)
  ...devRoutes,
  {
    path: '*',
    element: <Navigate to="/app/dashboard" replace />,
  },
]);
