import { useProfileContextQuery } from '../features/identity/queries';

export function useCurrentProfile() {
  const { data, isLoading, error } = useProfileContextQuery();

  return {
    profile: data?.profile ?? null,
    isLoading,
    error,
  };
}
