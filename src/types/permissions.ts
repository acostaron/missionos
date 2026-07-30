export const Permissions = {
  GovernanceStructureView: 'governance.structure.view',
  GovernanceStructureManage: 'governance.structure.manage',

  MembersRecordsView: 'members.records.view',
  MembersRecordsUpdate: 'members.records.update',
  MembersContactsView: 'members.contacts.view',
  MembersContactsManage: 'members.contacts.manage',
  MembersAddressesView: 'members.addresses.view',
  MembersPlacementsView: 'members.placements.view',
  MembersPlacementsManage: 'members.placements.manage',
  MembersQrView: 'members.qr.view',
  MembersQrManage: 'members.qr.manage',

  GovernanceLeadershipView: 'governance.leadership.view',
  GovernanceLeadershipManage: 'governance.leadership.manage',

  SecurityRoleAssignmentsManage: 'security.role_assignments.manage',
  SecurityScopeAssignmentsManage: 'security.scope_assignments.manage',
} as const;

export type PermissionCode = typeof Permissions[keyof typeof Permissions];
