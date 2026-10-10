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
  MembersSelfServiceView: 'members.self_service.view',
  MembersAccountLinksManage: 'members.account_links.manage',
  MembersAccountsProvision: 'members.accounts.provision',

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

  HouseholdsMembersAssign: 'households.members.assign',
  HouseholdsMembersTransfer: 'households.members.transfer',
  HouseholdsMembersEnd: 'households.members.end',

  LeadershipServantLeadersAppoint: 'leadership.servant_leaders.appoint',
  LeadershipServantLeadersConclude: 'leadership.servant_leaders.conclude',
  LeadershipServantLeadersReplace: 'leadership.servant_leaders.replace',

  LeadershipPastoralPlacementReview: 'leadership.pastoral_placement.review',
  LeadershipPastoralPlacementExecute: 'leadership.pastoral_placement.execute',

  LeadershipPastoralDashboardView: 'leadership.pastoral_dashboard.view',

  // Phase 6B-8: Household Meetings & Attendance
  HouseholdsMeetingsView: 'households.meetings.view',
  HouseholdsMeetingsManage: 'households.meetings.manage',
  HouseholdsAttendanceRecord: 'households.attendance.record',

  // Phase 6B-10: Household Formation
  HouseholdsFormationView: 'households.formation.view',
  HouseholdsFormationManage: 'households.formation.manage',

  // Phase 6B-9: Delegated Servant Leader Access
  LeadershipDelegatedAccessManage: 'leadership.delegated_access.manage',
  LeadershipDelegatedAccessView: 'leadership.delegated_access.view',

  // Stage 3A: Formal Pastoral Formation
  FormationCatalogView: 'formation.catalog.view',
  FormationCatalogManage: 'formation.catalog.manage',
  FormationRecordsView: 'formation.records.view',
  FormationRecordsRecord: 'formation.records.record',
  FormationRecordsCorrect: 'formation.records.correct',
} as const;

export type PermissionCode = typeof Permissions[keyof typeof Permissions];
