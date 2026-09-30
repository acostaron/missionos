export const Permissions = {
  GovernanceStructureView: 'governance.structure.view',
  GovernanceStructureManage: 'governance.structure.manage',

  MembersRecordsCreate: 'members.records.create',
  MembersRecordsView: 'members.records.view',
  MembersRecordsUpdate: 'members.records.update',
  MembersRecordsArchive: 'members.records.archive',

  // Identifier visibility & management
  MembersIdentifiersView: 'members.identifiers.view',
  MembersIdentifiersManage: 'members.identifiers.manage',

  MembersContactsView: 'members.contacts.view',
  MembersContactsManage: 'members.contacts.manage',

  MembersAddressesView: 'members.addresses.view',
  MembersAddressesManage: 'members.addresses.manage',

  MembersSectionsView: 'members.sections.view',
  MembersHouseholdsView: 'members.households.view',

  MembersPlacementsView: 'members.placements.view',
  MembersPlacementsManage: 'members.placements.manage',

  MembersStatusView: 'members.status.view',
  MembersStatusManage: 'members.status.manage',
  MembersDeceasedManage: 'members.deceased.manage',
  MembersDeceasedRevert: 'members.deceased.revert',

  MembersRecordsRestore: 'members.records.restore',

  MembersQrView: 'members.qr.view',
  MembersQrManage: 'members.qr.manage',

  GovernanceLeadershipView: 'governance.leadership.view',
  GovernanceLeadershipManage: 'governance.leadership.manage',

  SecurityRoleAssignmentsManage: 'security.role_assignments.manage',
  SecurityScopeAssignmentsManage: 'security.scope_assignments.manage',

  FamiliesRecordsView: 'families.records.view',
  FamiliesRecordsCreate: 'families.records.create',
  FamiliesRecordsUpdate: 'families.records.update',
  FamiliesRecordsArchive: 'families.records.archive',
  FamiliesRelationshipsView: 'families.relationships.view',

  FamiliesMembersAdd: 'families.members.add',
  FamiliesMembersUpdate: 'families.members.update',
  FamiliesMembersEnd: 'families.members.end',

  FamiliesRelationshipsAdd: 'families.relationships.add',
  FamiliesRelationshipsEnd: 'families.relationships.end',
  FamiliesRelationshipsCorrect: 'families.relationships.correct',

  HouseholdsRecordsView: 'households.records.view',
  HouseholdsRecordsCreate: 'households.records.create',
  HouseholdsRecordsUpdate: 'households.records.update',
  HouseholdsRecordsArchive: 'households.records.archive',
} as const;

export type PermissionCode = typeof Permissions[keyof typeof Permissions];
