/**
 * Lazy-loaded page components for code-split routes.
 *
 * Isolated in their own module so that router.tsx remains a pure
 * non-component file and satisfies the react/only-export-components
 * lint rule. Each export here is a React.LazyExoticComponent, which
 * Vite/Rolldown treats as a separate async chunk.
 */
import { lazy } from 'react';

export const MembersPage = lazy(() => import('../pages/MembersPage'));
export const MemberProfilePage = lazy(() => import('../pages/MemberProfilePage'));
export const NewMemberPage = lazy(() => import('../pages/NewMemberPage'));
export const FamilyProfilePage = lazy(() => import('../pages/FamilyProfilePage'));
export const HouseholdsPage = lazy(() => import('../pages/HouseholdsPage'));
export const HouseholdProfilePage = lazy(() => import('../pages/HouseholdProfilePage'));
export const MembersWithoutHouseholdPage = lazy(
  () => import('../pages/MembersWithoutHouseholdPage')
);
export const PastoralOperationsDashboardPage = lazy(
  () => import('../pages/PastoralOperationsDashboardPage')
);
export const MyProfilePage = lazy(() => import('../pages/MyProfilePage'));
export const FormationCatalogPage = lazy(() => import('../pages/FormationCatalogPage'));
export const FormationProgramDetailPage = lazy(
  () => import('../pages/FormationProgramDetailPage')
);
export const SectionsPage = lazy(() => import('../pages/SectionsPage'));
export const PlaceMembersPage = lazy(() => import('../pages/PlaceMembersPage'));
export const CalendarPage = lazy(() => import('../pages/CalendarPage'));
export const EventPage = lazy(() => import('../pages/EventPage'));
export const EventAttendancePage = lazy(() => import('../pages/EventAttendancePage'));
export const EventCheckInPage = lazy(() => import('../pages/EventCheckInPage'));
export const EventPaymentsPage = lazy(() => import('../pages/EventPaymentsPage'));
export const LeadersPage = lazy(() => import('../pages/LeadersPage'));
export const ProgramPage = lazy(() => import('../pages/ProgramPage'));
export const MemberLoginsPage = lazy(() => import('../pages/MemberLoginsPage'));
export const ActivityPage = lazy(() => import('../pages/ActivityPage'));
export const ClaimAccountPage = lazy(() => import('../pages/ClaimAccountPage'));
export const EditMyProfilePage = lazy(() => import('../pages/EditMyProfilePage'));
export const MyCardPage = lazy(() => import('../pages/MyCardPage'));
export const MyEventsPage = lazy(() => import('../pages/MyEventsPage'));
export const LibraryPage = lazy(() => import('../pages/LibraryPage'));
export const LibraryTopicPage = lazy(() => import('../pages/LibraryTopicPage'));
