import { lazy, Suspense } from 'react';
import { createBrowserRouter, Navigate } from 'react-router-dom';
import LoginPage from '../pages/LoginPage';
import InviteAcceptPage from '../pages/InviteAcceptPage';
import DashboardPage from '../pages/DashboardPage';
import AppLayout from '../components/layout/AppLayout';
import { ProtectedRoute } from '../components/auth/ProtectedRoute';
import PageLoadingFallback from '../components/ui/PageLoadingFallback';
import {
  MembersPage,
  MemberProfilePage,
  NewMemberPage,
  FamilyProfilePage,
  HouseholdsPage,
  HouseholdProfilePage,
  MembersWithoutHouseholdPage,
  PastoralOperationsDashboardPage,
  LeadersPage,
  MyProfilePage,
  FormationCatalogPage,
  FormationProgramDetailPage,
  SectionsPage,
  PlaceMembersPage,
  CalendarPage,
  EventPage,
  EventAttendancePage,
  EventCheckInPage,
  EventPaymentsPage,
  ProgramPage,
  MemberLoginsPage,
  ActivityPage,
  ClaimAccountPage,
  EditMyProfilePage,
  MyCardPage,
  MyEventsPage,
  LibraryPage,
  LibraryTopicPage,
  OfficialDocumentsPage,
} from './lazy-pages';


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
    path: '/claim',
    element: (
      <Suspense fallback={<PageLoadingFallback />}>
        <ClaimAccountPage />
      </Suspense>
    ),
  },
  {
    path: '/invite/accept',
    element: <InviteAcceptPage />,
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
            path: 'members/new',
            element: (
              <Suspense fallback={<PageLoadingFallback />}>
                <NewMemberPage />
              </Suspense>
            ),
          },
          {
            path: 'members/logins',
            element: (
              <Suspense fallback={<PageLoadingFallback />}>
                <MemberLoginsPage />
              </Suspense>
            ),
          },
          {
            // Pass 9.35: admin Activity page
            path: 'activity',
            element: (
              <Suspense fallback={<PageLoadingFallback />}>
                <ActivityPage />
              </Suspense>
            ),
          },
          {
            path: 'members/place',
            element: (
              <Suspense fallback={<PageLoadingFallback />}>
                <PlaceMembersPage />
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
            path: 'families/:familyId',
            element: (
              <Suspense fallback={<PageLoadingFallback />}>
                <FamilyProfilePage />
              </Suspense>
            ),
          },
          {
            path: 'sections',
            element: (
              <Suspense fallback={<PageLoadingFallback />}>
                <SectionsPage />
              </Suspense>
            ),
          },
          {
            path: 'calendar',
            element: (
              <Suspense fallback={<PageLoadingFallback />}>
                <CalendarPage />
              </Suspense>
            ),
          },
          {
            path: 'calendar/:eventId',
            element: (
              <Suspense fallback={<PageLoadingFallback />}>
                <EventPage />
              </Suspense>
            ),
          },
          {
            path: 'calendar/:eventId/attendance',
            element: (
              <Suspense fallback={<PageLoadingFallback />}>
                <EventAttendancePage />
              </Suspense>
            ),
          },
          {
            path: 'calendar/:eventId/payments',
            element: (
              <Suspense fallback={<PageLoadingFallback />}>
                <EventPaymentsPage />
              </Suspense>
            ),
          },
          {
            path: 'calendar/:eventId/scan',
            element: (
              <Suspense fallback={<PageLoadingFallback />}>
                <EventCheckInPage />
              </Suspense>
            ),
          },
          {
            path: 'programs',
            element: <Navigate to="/app/calendar?tab=programs" replace />,
          },
          {
            path: 'programs/:runId',
            element: (
              <Suspense fallback={<PageLoadingFallback />}>
                <ProgramPage />
              </Suspense>
            ),
          },
          {
            path: 'households',
            element: (
              <Suspense fallback={<PageLoadingFallback />}>
                <HouseholdsPage />
              </Suspense>
            ),
          },
          {
            path: 'households/unassigned',
            element: (
              <Suspense fallback={<PageLoadingFallback />}>
                <MembersWithoutHouseholdPage />
              </Suspense>
            ),
          },
          {
            path: 'households/:householdId',
            element: (
              <Suspense fallback={<PageLoadingFallback />}>
                <HouseholdProfilePage />
              </Suspense>
            ),
          },
          {
            path: 'pastoral-operations',
            element: (
              <Suspense fallback={<PageLoadingFallback />}>
                <PastoralOperationsDashboardPage />
              </Suspense>
            ),
          },
          {
            path: 'leaders',
            element: (
              <Suspense fallback={<PageLoadingFallback />}>
                <LeadersPage />
              </Suspense>
            ),
          },
          {
            path: 'formation',
            element: (
              <Suspense fallback={<PageLoadingFallback />}>
                <FormationCatalogPage />
              </Suspense>
            ),
          },
          {
            path: 'formation/:programId',
            element: (
              <Suspense fallback={<PageLoadingFallback />}>
                <FormationProgramDetailPage />
              </Suspense>
            ),
          },
          {
            path: 'profile',
            element: (
              <Suspense fallback={<PageLoadingFallback />}>
                <MyProfilePage />
              </Suspense>
            ),
          },
          {
            path: 'profile/edit',
            element: (
              <Suspense fallback={<PageLoadingFallback />}>
                <EditMyProfilePage />
              </Suspense>
            ),
          },
          {
            path: 'my-card',
            element: (
              <Suspense fallback={<PageLoadingFallback />}>
                <MyCardPage />
              </Suspense>
            ),
          },
          {
            path: 'library',
            element: (
              <Suspense fallback={<PageLoadingFallback />}>
                <LibraryPage />
              </Suspense>
            ),
          },
          {
            // Pass 9.36: Library > Official Documents (Unit Servant Leaders and up; the server checks)
            path: 'official-documents',
            element: (
              <Suspense fallback={<PageLoadingFallback />}>
                <OfficialDocumentsPage />
              </Suspense>
            ),
          },
          {
            path: 'library/:topicId',
            element: (
              <Suspense fallback={<PageLoadingFallback />}>
                <LibraryTopicPage />
              </Suspense>
            ),
          },
          {
            path: 'my-events',
            element: (
              <Suspense fallback={<PageLoadingFallback />}>
                <MyEventsPage />
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
