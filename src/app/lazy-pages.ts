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
