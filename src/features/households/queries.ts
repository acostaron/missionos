export const householdKeys = {
  all: ['households'] as const,
  lists: () => [...householdKeys.all, 'list'] as const,
  list: (orgId: string, filters?: Record<string, unknown>) =>
    [...householdKeys.lists(), orgId, filters] as const,
  profiles: () => [...householdKeys.all, 'profile'] as const,
  profile: (orgId: string, householdId: string) =>
    [...householdKeys.profiles(), orgId, householdId] as const,
  members: () => [...householdKeys.all, 'member'] as const,
  member: (orgId: string, memberId: string) =>
    [...householdKeys.members(), orgId, memberId] as const,
  membersWithoutHousehold: (orgId: string, search?: string) =>
    [...householdKeys.all, 'members-without-household', orgId, search] as const,
  unassigned: (orgId: string, search?: string) =>
    householdKeys.membersWithoutHousehold(orgId, search),
};
