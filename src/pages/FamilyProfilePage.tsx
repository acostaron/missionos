import { useState } from 'react';
import { useParams, Link, Navigate } from 'react-router-dom';
import { useOrganizationContext } from '../hooks/use-organization-context';
import { usePermissions } from '../hooks/use-permissions';
import { Permissions } from '../types/permissions';
import { useFamilyProfile } from '../features/families/api/get-family-profile';
import { FamilyMemberRoster } from '../features/families/components/FamilyMemberRoster';
import { FamilyRelationshipList } from '../features/families/components/FamilyRelationshipList';
import { EditFamilyModal } from '../features/families/components/EditFamilyModal';
import { ArchiveFamilyModal } from '../features/families/components/ArchiveFamilyModal';
import { AddFamilyMemberModal } from '../features/families/components/AddFamilyMemberModal';
import { EditFamilyMemberModal } from '../features/families/components/EditFamilyMemberModal';
import { EndFamilyMembershipModal } from '../features/families/components/EndFamilyMembershipModal';
import { AddFamilyRelationshipModal } from '../features/families/components/AddFamilyRelationshipModal';
import { EndFamilyRelationshipModal } from '../features/families/components/EndFamilyRelationshipModal';
import { RepairFamilyRelationshipModal } from '../features/families/components/RepairFamilyRelationshipModal';
import type { FamilyProfileMember, FamilyProfileRelationship } from '../features/families/types';

function formatFamilyType(type: string | null): string {
  if (!type) return 'Family';
  return type
    .replace(/_/g, ' ')
    .replace(/\b\w/g, (c) => c.toUpperCase());
}

export default function FamilyProfilePage() {
  const { familyId } = useParams<{ familyId: string }>();
  const { activeOrganization, isLoading: isOrgLoading } = useOrganizationContext();
  const { hasPermission, isLoading: isPermLoading } = usePermissions();

  const [isEditOpen, setIsEditOpen] = useState(false);
  const [isArchiveOpen, setIsArchiveOpen] = useState(false);
  const [isAddMemberOpen, setIsAddMemberOpen] = useState(false);
  const [editingMember, setEditingMember] = useState<FamilyProfileMember | null>(null);
  const [endingMember, setEndingMember] = useState<FamilyProfileMember | null>(null);
  const [isAddRelationshipOpen, setIsAddRelationshipOpen] = useState(false);
  const [endingRelationship, setEndingRelationship] = useState<FamilyProfileRelationship | null>(null);
  const [repairingRelationship, setRepairingRelationship] = useState<FamilyProfileRelationship | null>(null);

  const orgId = activeOrganization?.id ?? null;

  const canViewFamilies = !isPermLoading && hasPermission(Permissions.FamiliesRecordsView);
  const canViewRelationships = !isPermLoading && hasPermission(Permissions.FamiliesRelationshipsView);
  const canUpdateFamily = !isPermLoading && hasPermission(Permissions.FamiliesRecordsUpdate);
  const canArchiveFamily = !isPermLoading && hasPermission(Permissions.FamiliesRecordsArchive);
  const canAddMember = !isPermLoading && hasPermission(Permissions.FamiliesMembersAdd);
  const canUpdateMember = !isPermLoading && hasPermission(Permissions.FamiliesMembersUpdate);
  const canEndMember = !isPermLoading && hasPermission(Permissions.FamiliesMembersEnd);
  const canAddRelationship = !isPermLoading && hasPermission(Permissions.FamiliesRelationshipsAdd);
  const canEndRelationship = !isPermLoading && hasPermission(Permissions.FamiliesRelationshipsEnd);
  const canCorrectRelationship = !isPermLoading && hasPermission(Permissions.FamiliesRelationshipsCorrect);

  const {
    data: profile,
    isLoading,
    error,
  } = useFamilyProfile(orgId, familyId ?? null, canViewFamilies);

  if (!familyId) {
    return <Navigate to="/app/members" replace />;
  }

  // Loading skeleton
  if (isOrgLoading || isLoading || isPermLoading) {
    return (
      <div className="space-y-6">
        <div className="h-4 w-32 animate-pulse rounded bg-slate-800" />
        <div className="h-20 w-80 animate-pulse rounded-xl bg-slate-800" />
        <div className="h-48 animate-pulse rounded-xl bg-slate-800" />
        <div className="h-48 animate-pulse rounded-xl bg-slate-800" />
      </div>
    );
  }

  // Access denied on page level
  if (!canViewFamilies) {
    return (
      <div className="space-y-6">
        <Link
          to="/app/members"
          id="family-profile-back"
          className="inline-flex items-center gap-1.5 text-sm text-slate-400 hover:text-slate-200"
        >
          <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M15 19l-7-7 7-7" />
          </svg>
          Member Directory
        </Link>

        <div className="rounded-xl border border-red-700 bg-red-900/20 p-6">
          <h2 className="mb-2 text-base font-semibold text-red-300">
            Access Denied
          </h2>
          <p className="text-sm text-red-400">
            You do not have permission to view family records.
          </p>
        </div>
      </div>
    );
  }

  // Not found or error loading profile
  if (error || !profile) {
    return (
      <div className="space-y-6">
        <Link
          to="/app/members"
          id="family-profile-back"
          className="inline-flex items-center gap-1.5 text-sm text-slate-400 hover:text-slate-200"
        >
          <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M15 19l-7-7 7-7" />
          </svg>
          Member Directory
        </Link>

        <div className="rounded-xl border border-red-700 bg-red-900/20 p-6">
          <h2 className="mb-2 text-base font-semibold text-red-300">
            Family Record Unavailable
          </h2>
          <p className="text-sm text-red-400">
            Family record not found or unavailable.
          </p>
        </div>
      </div>
    );
  }

  const { family, members, relationships } = profile;

  const familyName =
    family.display_name?.trim() ||
    family.family_name?.trim() ||
    'Family record';

  const familyTypeLabel = formatFamilyType(family.family_type);
  const isStatusActive = family.family_status === 'active';
  const statusLabel = family.family_status
    ? family.family_status.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase())
    : 'Active';

  // Lifecycle gating: only active and changed are operational/editable/archivable
  const isEditable = family.family_status === 'active' || family.family_status === 'changed';
  const isArchiveable = family.family_status === 'active' || family.family_status === 'changed';

  const showEdit = canUpdateFamily && isEditable;
  const showArchive = canArchiveFamily && isArchiveable;

  const initials = familyName
    .split(' ')
    .map((w: string) => w[0])
    .slice(0, 2)
    .join('')
    .toUpperCase() || 'FA';

  return (
    <div className="space-y-6">
      {/* Navigation / Breadcrumb */}
      <nav className="flex items-center gap-2 text-sm text-slate-400">
        <Link
          to="/app/members"
          id="family-profile-back"
          className="hover:text-slate-200 transition-colors"
        >
          Members
        </Link>
        <span className="text-slate-600">/</span>
        <span className="text-slate-200 font-medium">{familyName}</span>
      </nav>

      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 rounded-xl border border-slate-700 bg-slate-800/80 p-5 shadow-sm">
        <div className="flex items-center gap-5">
          <div className="flex h-16 w-16 shrink-0 items-center justify-center rounded-2xl bg-indigo-900 text-xl font-bold text-indigo-200">
            {initials}
          </div>
          <div>
            <h1 className="text-2xl font-bold tracking-tight text-slate-100">
              {familyName}
            </h1>
            <div className="mt-1.5 flex items-center gap-2.5 flex-wrap">
              <span
                className={`inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-medium ${
                  isStatusActive
                    ? 'border-emerald-700/60 bg-emerald-950/40 text-emerald-300'
                    : 'border-slate-600 bg-slate-800 text-slate-400'
                }`}
              >
                {statusLabel}
              </span>
              <span className="inline-flex items-center rounded-full border border-slate-600 bg-slate-800/80 px-2.5 py-0.5 text-xs font-medium text-slate-300">
                {familyTypeLabel}
              </span>
              <span className="text-xs text-slate-400">
                {members.length} {members.length === 1 ? 'member' : 'members'}
              </span>
            </div>
          </div>
        </div>

        {/* Action Buttons */}
        {(showEdit || showArchive) && (
          <div className="flex items-center gap-2.5 sm:self-center">
            {showEdit && (
              <button
                type="button"
                onClick={() => setIsEditOpen(true)}
                id="edit-family-button"
                className="inline-flex items-center gap-1.5 rounded-lg border border-slate-700 bg-slate-800 px-3.5 py-2 text-xs font-medium text-slate-200 shadow-sm hover:bg-slate-700 hover:text-white transition-colors"
              >
                <svg className="h-3.5 w-3.5 text-slate-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                </svg>
                Edit Family
              </button>
            )}
            {showArchive && (
              <button
                type="button"
                onClick={() => setIsArchiveOpen(true)}
                id="archive-family-button"
                className="inline-flex items-center gap-1.5 rounded-lg border border-rose-900/60 bg-rose-950/20 px-3.5 py-2 text-xs font-medium text-rose-300 shadow-sm hover:bg-rose-900/40 hover:text-rose-200 transition-colors"
              >
                <svg className="h-3.5 w-3.5 text-rose-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M5 8h14M5 8a2 2 0 110-4h14a2 2 0 110 4M5 8v10a2 2 0 002 2h10a2 2 0 002-2V8m-9 4h4" />
                </svg>
                Archive Family
              </button>
            )}
          </div>
        )}
      </div>

      {/* Family Member Roster */}
      <FamilyMemberRoster
        members={members}
        canAddMember={canAddMember}
        canUpdateMember={canUpdateMember}
        canEndMember={canEndMember}
        isFamilyOperational={isEditable}
        onAddMember={() => setIsAddMemberOpen(true)}
        onEditMember={(member) => setEditingMember(member)}
        onEndMember={(member) => setEndingMember(member)}
      />

      {/* Family Relationships */}
      <FamilyRelationshipList
        relationships={relationships}
        members={members}
        canViewRelationships={canViewRelationships}
        canAddRelationship={canAddRelationship}
        canEndRelationship={canEndRelationship}
        canCorrectRelationship={canCorrectRelationship}
        isFamilyOperational={isEditable}
        onAddRelationship={() => setIsAddRelationshipOpen(true)}
        onEndRelationship={(rel) => setEndingRelationship(rel)}
        onRepairRelationship={(rel) => setRepairingRelationship(rel)}
      />

      {/* Identity Modals */}
      {showEdit && orgId && (
        <EditFamilyModal
          isOpen={isEditOpen}
          onClose={() => setIsEditOpen(false)}
          organizationId={orgId}
          family={family}
        />
      )}

      {showArchive && orgId && (
        <ArchiveFamilyModal
          isOpen={isArchiveOpen}
          onClose={() => setIsArchiveOpen(false)}
          organizationId={orgId}
          familyId={family.id}
          familyName={familyName}
        />
      )}

      {/* Membership Management Modals */}
      {canAddMember && orgId && isEditable && (
        <AddFamilyMemberModal
          isOpen={isAddMemberOpen}
          onClose={() => setIsAddMemberOpen(false)}
          organizationId={orgId}
          familyId={family.id}
          familyName={familyName}
        />
      )}

      {canUpdateMember && orgId && editingMember && (
        <EditFamilyMemberModal
          isOpen={editingMember !== null}
          onClose={() => setEditingMember(null)}
          organizationId={orgId}
          familyId={family.id}
          member={editingMember}
        />
      )}

      {canEndMember && orgId && endingMember && (
        <EndFamilyMembershipModal
          isOpen={endingMember !== null}
          onClose={() => setEndingMember(null)}
          organizationId={orgId}
          familyId={family.id}
          member={endingMember}
        />
      )}

      {/* Relationship Management Modals */}
      {canAddRelationship && orgId && isEditable && (
        <AddFamilyRelationshipModal
          isOpen={isAddRelationshipOpen}
          onClose={() => setIsAddRelationshipOpen(false)}
          organizationId={orgId}
          familyId={family.id}
          familyName={familyName}
          members={members}
        />
      )}

      {canEndRelationship && orgId && endingRelationship && (
        <EndFamilyRelationshipModal
          isOpen={endingRelationship !== null}
          onClose={() => setEndingRelationship(null)}
          organizationId={orgId}
          familyId={family.id}
          relationship={endingRelationship}
          members={members}
        />
      )}

      {canCorrectRelationship && orgId && isEditable && repairingRelationship && (
        <RepairFamilyRelationshipModal
          isOpen={repairingRelationship !== null}
          onClose={() => setRepairingRelationship(null)}
          organizationId={orgId}
          familyId={family.id}
          relationship={repairingRelationship}
          members={members}
        />
      )}
    </div>
  );
}
