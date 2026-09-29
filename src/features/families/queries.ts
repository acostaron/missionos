export const familyKeys = {
  all: ['families'] as const,
  profiles: () => [...familyKeys.all, 'profile'] as const,
  profile: (orgId: string, familyId: string) =>
    [...familyKeys.profiles(), orgId, familyId] as const,
};
