import { useState } from 'react';
import { useParams, Link, Navigate } from 'react-router-dom';
import { useOrganizationContext } from '../hooks/use-organization-context';
import { usePermissions } from '../hooks/use-permissions';
import { Permissions } from '../types/permissions';
import { useMemberProfile } from '../features/members/queries';
import { EditMemberProfileModal } from '../features/members/components/EditMemberProfileModal';
import { EditEmailModal } from '../features/members/components/EditEmailModal';
import { EditPhoneModal } from '../features/members/components/EditPhoneModal';
import { EditAddressModal } from '../features/members/components/EditAddressModal';
import { ChangeGovernancePlacementModal } from '../features/members/components/ChangeGovernancePlacementModal';
import { ChangeMemberStatusModal } from '../features/members/components/ChangeMemberStatusModal';
import { RecordMemberDeceasedModal } from '../features/members/components/RecordMemberDeceasedModal';
import { ArchiveMemberRecordModal } from '../features/members/components/ArchiveMemberRecordModal';
import { RevertMemberDeceasedModal } from '../features/members/components/RevertMemberDeceasedModal';
import { RestoreMemberRecordModal } from '../features/members/components/RestoreMemberRecordModal';
import { MemberStatusTimeline } from '../features/members/components/MemberStatusTimeline';
import { MemberFamilyCard } from '../features/members/components/MemberFamilyCard';
import { MemberHouseholdCard } from '../features/households/components/MemberHouseholdCard';
import {
  RemoveContactConfirmModal,
  type RemoveTargetType,
} from '../features/members/components/RemoveContactConfirmModal';
import type {
  MemberProfile,
  MemberIdentifier,
  MemberEmail,
  MemberPhone,
  MemberAddress,
  SectionPlacement,
  HouseholdPlacement,
  GovernancePlacement,
} from '../features/members/queries';


// ---------------------------------------------------------------------------
// Shared UI primitives
// ---------------------------------------------------------------------------

function Section({
  title,
  icon,
  action,
  children,
}: {
  title: string;
  icon: React.ReactNode;
  action?: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <div className="rounded-xl border border-line bg-surface-muted overflow-hidden">
      <div className="flex items-center justify-between border-b border-line px-5 py-3.5">
        <div className="flex items-center gap-3">
          <span className="text-ink-muted">{icon}</span>
          <h2 className="text-sm font-semibold uppercase tracking-wider text-ink-secondary">
            {title}
          </h2>
        </div>
        {action && <div>{action}</div>}
      </div>
      <div className="px-5 py-4">{children}</div>
    </div>
  );
}


function RestrictedSection({ label }: { label: string }) {
  return (
    <p className="flex items-center gap-2 text-xs text-ink-muted italic">
      <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
        <path strokeLinecap="round" strokeLinejoin="round"
          d="M12 15v2m-6 4h12a2 2 0 002-2v-5a2 2 0 00-2-2H6a2 2 0 00-2 2v5a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
      </svg>
      {label} — access restricted for this role
    </p>
  );
}

function DataRow({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="flex items-start justify-between gap-4 py-1.5">
      <dt className="shrink-0 text-xs font-medium text-ink-muted w-32">{label}</dt>
      <dd className="text-sm text-ink text-right flex-1">{value ?? <span className="text-ink-muted italic">—</span>}</dd>
    </div>
  );
}

function StatusBadge({ name, isActive }: { name: string; isActive: boolean }) {
  return (
    <span
      className={`inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-medium ${
        isActive
          ? 'border-success-600 bg-success-50 text-success-700'
          : 'border-line-strong bg-surface-muted text-ink-muted'
      }`}
    >
      {name}
    </span>
  );
}

// ---------------------------------------------------------------------------
// Section-specific components
// ---------------------------------------------------------------------------

function OverviewSection({ profile }: { profile: MemberProfile }) {
  return (
    <Section
      title="Overview"
      icon={
        <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
          <path strokeLinecap="round" strokeLinejoin="round"
            d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
        </svg>
      }
    >
      <dl className="divide-y divide-line">
        <DataRow label="Display name" value={profile.display_name} />
        {profile.preferred_name && profile.preferred_name !== profile.display_name && (
          <DataRow label="Preferred name" value={profile.preferred_name} />
        )}
        <DataRow label="Sort name" value={profile.sort_name} />
        <DataRow label="Record status" value={
          <span className="capitalize">{profile.record_status}</span>
        } />
        <DataRow
          label="Membership"
          value={
            profile.membership_status ? (
              <StatusBadge
                name={profile.membership_status.name}
                isActive={profile.membership_status.is_active_membership}
              />
            ) : null
          }
        />
        <DataRow
          label="Member #"
          value={
            profile.member_number !== null ? (
              <span className="font-mono">{profile.member_number}</span>
            ) : (
              <span className="text-ink-muted italic text-xs">restricted</span>
            )
          }
        />
        {profile.is_deceased && (
          <DataRow
            label="Date of death"
            value={
              <div className="flex items-center justify-end gap-2 text-ink">
                <span>{profile.deceased_on ?? 'Unknown'}</span>
                {profile.deceased_on_precision && (
                  <span className="text-[10px] text-ink-muted bg-surface-muted px-1.5 py-0.5 rounded border border-line">
                    {profile.deceased_on_precision.replace(/_/g, ' ')}
                  </span>
                )}
              </div>
            }
          />
        )}
        {profile.birth_date && (
          <DataRow label="Birth date" value={profile.birth_date} />
        )}
        {profile.sex && (
          <DataRow label="Sex" value={<span className="capitalize">{profile.sex}</span>} />
        )}
        {profile.civil_status && (
          <DataRow label="Civil status" value={<span className="capitalize">{profile.civil_status}</span>} />
        )}
        {profile.home_country_code && (
          <DataRow label="Home country" value={profile.home_country_code} />
        )}
        {profile.preferred_language_code && (
          <DataRow label="Preferred language" value={profile.preferred_language_code} />
        )}
      </dl>
    </Section>
  );
}

function IdentifiersSection({ identifiers }: { identifiers: MemberIdentifier[] | null }) {
  if (identifiers === null) {
    return (
      <Section
        title="Identifiers"
        icon={
          <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
            <path strokeLinecap="round" strokeLinejoin="round"
              d="M7 20l4-16m2 16l4-16M6 9h14M4 15h14" />
          </svg>
        }
      >
        <RestrictedSection label="Identifiers" />
      </Section>
    );
  }

  if (identifiers.length === 0) {
    return (
      <Section
        title="Identifiers"
        icon={
          <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
            <path strokeLinecap="round" strokeLinejoin="round"
              d="M7 20l4-16m2 16l4-16M6 9h14M4 15h14" />
          </svg>
        }
      >
        <p className="text-xs text-ink-muted italic">No identifiers on record.</p>
      </Section>
    );
  }

  return (
    <Section
      title="Identifiers"
      icon={
        <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
          <path strokeLinecap="round" strokeLinejoin="round"
            d="M7 20l4-16m2 16l4-16M6 9h14M4 15h14" />
        </svg>
      }
    >
      <div className="space-y-2">
        {identifiers.map((id) => (
          <div
            key={id.id}
            className="flex items-center justify-between rounded-md border border-line bg-surface px-3 py-2"
          >
            <div>
              <p className="text-xs font-medium text-ink-muted capitalize">
                {id.identifier_type.replace(/_/g, ' ')}
                {id.is_primary && (
                  <span className="ml-2 text-[10px] uppercase tracking-wider text-primary-blue">
                    primary
                  </span>
                )}
              </p>
              <p className="font-mono text-sm text-ink">{id.identifier_value}</p>
            </div>
            {id.verification_status && (
              <span className="text-xs text-ink-muted capitalize">
                {id.verification_status}
              </span>
            )}
          </div>
        ))}
      </div>
    </Section>
  );
}

interface ContactsSectionProps {
  contacts: MemberProfile['contacts'];
  canManageContacts: boolean;
  onAddEmail: () => void;
  onReplaceEmail: (email: MemberEmail) => void;
  onRemoveEmail: (email: MemberEmail) => void;
  onAddPhone: () => void;
  onReplacePhone: (phone: MemberPhone) => void;
  onRemovePhone: (phone: MemberPhone) => void;
}

function ContactsSection({
  contacts,
  canManageContacts,
  onAddEmail,
  onReplaceEmail,
  onRemoveEmail,
  onAddPhone,
  onReplacePhone,
  onRemovePhone,
}: ContactsSectionProps) {
  const icon = (
    <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
      <path strokeLinecap="round" strokeLinejoin="round"
        d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
    </svg>
  );

  if (contacts === null) {
    return <Section title="Contact Information" icon={icon}><RestrictedSection label="Contacts" /></Section>;
  }

  const headerActions = canManageContacts ? (
    <div className="flex items-center gap-2">
      <button
        type="button"
        id="add-email-button"
        onClick={onAddEmail}
        className="inline-flex items-center gap-1 rounded-md border border-line bg-surface-muted px-2.5 py-1 text-xs font-medium text-ink hover:border-primary-blue hover:text-primary-blue transition-colors"
      >
        <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
          <path strokeLinecap="round" strokeLinejoin="round" d="M12 4v16m8-8H4" />
        </svg>
        Add Email
      </button>
      <button
        type="button"
        id="add-phone-button"
        onClick={onAddPhone}
        className="inline-flex items-center gap-1 rounded-md border border-line bg-surface-muted px-2.5 py-1 text-xs font-medium text-ink hover:border-primary-blue hover:text-primary-blue transition-colors"
      >
        <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
          <path strokeLinecap="round" strokeLinejoin="round" d="M12 4v16m8-8H4" />
        </svg>
        Add Phone
      </button>
    </div>
  ) : undefined;

  const hasAny = contacts.emails.length > 0 || contacts.phones.length > 0;
  if (!hasAny) {
    return (
      <Section title="Contact Information" icon={icon} action={headerActions}>
        <p className="text-xs text-ink-muted italic">No contact information on record.</p>
      </Section>
    );
  }

  return (
    <Section title="Contact Information" icon={icon} action={headerActions}>
      <div className="space-y-4">
        {/* Emails Sub-group */}
        <div className="space-y-2">
          <p className="text-xs font-semibold uppercase tracking-wider text-ink-muted">
            Email Addresses
          </p>
          {contacts.emails.length === 0 ? (
            <p className="text-xs text-ink-muted italic">No email addresses on record.</p>
          ) : (
            contacts.emails.map((e: MemberEmail) => (
              <div
                key={e.id}
                className="flex items-center justify-between rounded-lg border border-line bg-surface px-3.5 py-2.5"
              >
                <div>
                  <div className="flex items-center gap-2">
                    <a
                      href={`mailto:${e.email_address}`}
                      className="text-sm font-medium text-primary-blue hover:text-primary-blue"
                    >
                      {e.email_address}
                    </a>
                    {e.is_primary && (
                      <span className="rounded-full bg-navy-50 border border-navy-100 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider text-primary-blue">
                        primary
                      </span>
                    )}
                    {e.email_type && (
                      <span className="text-xs text-ink-muted">({e.email_type})</span>
                    )}
                  </div>
                  {e.verification_status && (
                    <span className="text-xs text-ink-muted capitalize">{e.verification_status}</span>
                  )}
                </div>

                {canManageContacts && (
                  <div className="flex items-center gap-2">
                    {e.is_primary && (
                      <button
                        type="button"
                        onClick={() => onReplaceEmail(e)}
                        className="rounded px-2 py-1 text-xs font-medium text-ink-secondary hover:bg-surface-muted hover:text-primary-blue transition-colors"
                      >
                        Replace
                      </button>
                    )}
                    <button
                      type="button"
                      onClick={() => onRemoveEmail(e)}
                      className="rounded px-2 py-1 text-xs font-medium text-danger-700 hover:bg-danger-100 hover:text-danger-700 transition-colors"
                    >
                      Remove
                    </button>
                  </div>
                )}
              </div>
            ))
          )}
        </div>

        {/* Phones Sub-group */}
        <div className="space-y-2 pt-2 border-t border-line">
          <p className="text-xs font-semibold uppercase tracking-wider text-ink-muted">
            Phone Numbers
          </p>
          {contacts.phones.length === 0 ? (
            <p className="text-xs text-ink-muted italic">No phone numbers on record.</p>
          ) : (
            contacts.phones.map((p: MemberPhone) => (
              <div
                key={p.id}
                className="flex items-center justify-between rounded-lg border border-line bg-surface px-3.5 py-2.5"
              >
                <div>
                  <div className="flex items-center gap-2">
                    <a
                      href={`tel:${p.normalized_e164 ?? p.phone_number}`}
                      className="text-sm font-medium text-ink hover:text-ink"
                    >
                      {p.phone_number}
                    </a>
                    {p.is_primary && (
                      <span className="rounded-full bg-navy-50 border border-navy-100 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider text-primary-blue">
                        primary
                      </span>
                    )}
                    {p.phone_type && (
                      <span className="text-xs text-ink-muted">({p.phone_type})</span>
                    )}
                  </div>
                  {p.normalized_e164 && p.normalized_e164 !== p.phone_number && (
                    <p className="text-[11px] font-mono text-ink-muted">
                      E.164: {p.normalized_e164}
                    </p>
                  )}
                </div>

                {canManageContacts && (
                  <div className="flex items-center gap-2">
                    {p.is_primary && (
                      <button
                        type="button"
                        onClick={() => onReplacePhone(p)}
                        className="rounded px-2 py-1 text-xs font-medium text-ink-secondary hover:bg-surface-muted hover:text-primary-blue transition-colors"
                      >
                        Replace
                      </button>
                    )}
                    <button
                      type="button"
                      onClick={() => onRemovePhone(p)}
                      className="rounded px-2 py-1 text-xs font-medium text-danger-700 hover:bg-danger-100 hover:text-danger-700 transition-colors"
                    >
                      Remove
                    </button>
                  </div>
                )}
              </div>
            ))
          )}
        </div>
      </div>
    </Section>
  );
}

interface AddressesSectionProps {
  addresses: MemberProfile['addresses'];
  canManageAddresses: boolean;
  onAddAddress: () => void;
  onReplaceAddress: (address: MemberAddress) => void;
  onRemoveAddress: (address: MemberAddress) => void;
}

function AddressesSection({
  addresses,
  canManageAddresses,
  onAddAddress,
  onReplaceAddress,
  onRemoveAddress,
}: AddressesSectionProps) {
  const icon = (
    <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
      <path strokeLinecap="round" strokeLinejoin="round"
        d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
      <path strokeLinecap="round" strokeLinejoin="round" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
    </svg>
  );

  if (addresses === null) {
    return <Section title="Addresses" icon={icon}><RestrictedSection label="Addresses" /></Section>;
  }

  // Phase 5D manages the single current PRIMARY HOME address
  const currentPrimaryHomeAddress =
    addresses.find((a) => a.is_primary && (a.address_type === 'home' || !a.address_type)) ??
    addresses.find((a) => a.is_primary) ??
    null;

  const headerAction = canManageAddresses && (
    <button
      type="button"
      id="address-action-button"
      onClick={
        currentPrimaryHomeAddress
          ? () => onReplaceAddress(currentPrimaryHomeAddress)
          : onAddAddress
      }
      className="inline-flex items-center gap-1 rounded-md border border-line bg-surface-muted px-2.5 py-1 text-xs font-medium text-ink hover:border-primary-blue hover:text-primary-blue transition-colors"
    >
      <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
        <path strokeLinecap="round" strokeLinejoin="round" d="M12 4v16m8-8H4" />
      </svg>
      {currentPrimaryHomeAddress ? 'Replace Address' : 'Add Address'}
    </button>
  );


  if (addresses.length === 0) {
    return (
      <Section title="Addresses" icon={icon} action={headerAction}>
        <p className="text-xs text-ink-muted italic">No addresses on record.</p>
      </Section>
    );
  }

  return (
    <Section title="Addresses" icon={icon} action={headerAction}>
      <div className="space-y-4">
        {addresses.map((a: MemberAddress) => (
          <div key={a.id} className="rounded-md border border-line bg-surface px-4 py-3">
            <div className="mb-2 flex items-center justify-between">
              <div className="flex items-center gap-2">
                {a.address_type && (
                  <span className="text-xs font-medium text-ink-muted capitalize">
                    {a.address_type.replace(/_/g, ' ')}
                  </span>
                )}
                {a.is_primary && (
                  <span className="rounded-full bg-navy-50 border border-navy-100 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider text-primary-blue">
                    primary
                  </span>
                )}
                {a.is_mailing_address && (
                  <span className="rounded-full bg-warning-50 border border-warning-600/30 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider text-warning-700">
                    mailing
                  </span>
                )}
              </div>

              {canManageAddresses && (
                <div className="flex items-center gap-2">
                  <button
                    type="button"
                    onClick={() => onReplaceAddress(a)}
                    className="rounded px-2 py-1 text-xs font-medium text-ink-secondary hover:bg-surface-muted hover:text-primary-blue transition-colors"
                  >
                    Replace
                  </button>
                  <button
                    type="button"
                    onClick={() => onRemoveAddress(a)}
                    className="rounded px-2 py-1 text-xs font-medium text-danger-700 hover:bg-danger-100 hover:text-danger-700 transition-colors"
                  >
                    Remove
                  </button>
                </div>
              )}
            </div>

            <address className="not-italic text-sm text-ink leading-relaxed">
              {a.address.formatted_address ? (
                a.address.formatted_address
              ) : (
                <>
                  {a.address.address_line_1 && <div>{a.address.address_line_1}</div>}
                  {a.address.address_line_2 && <div>{a.address.address_line_2}</div>}
                  {a.address.address_line_3 && <div>{a.address.address_line_3}</div>}
                  <div>
                    {[a.address.city_name, a.address.state_province_name, a.address.postal_code]
                      .filter(Boolean)
                      .join(', ')}
                  </div>
                  {a.address.country_code && <div>{a.address.country_code}</div>}
                </>
              )}
            </address>
          </div>
        ))}
      </div>
    </Section>
  );
}


interface PlacementsSectionProps {
  section: SectionPlacement | null;
  household: HouseholdPlacement | null;
  governance: GovernancePlacement | null;
  canManagePlacements: boolean;
  onChangeGovernancePlacement: () => void;
}

function PlacementsSection({
  section,
  household,
  governance,
  canManagePlacements,
  onChangeGovernancePlacement,
}: PlacementsSectionProps) {
  const allRestricted = section === null && household === null && governance === null;
  const icon = (
    <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
      <path strokeLinecap="round" strokeLinejoin="round"
        d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-2 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4" />
    </svg>
  );

  if (allRestricted) {
    return <Section title="Placements" icon={icon}><RestrictedSection label="Placements" /></Section>;
  }

  const governanceRowValue = governance !== null ? (
    <div className="flex items-center justify-end gap-3 flex-1">
      {governance ? (
        <span className="text-sm text-ink">
          {governance.node_name} ({governance.node_code}) · {governance.assignment_type ?? governance.assignment_status}
        </span>
      ) : (
        <span className="text-ink-muted italic text-sm">Unplaced</span>
      )}
      {canManagePlacements && (
        <button
          type="button"
          id="change-placement-button"
          onClick={onChangeGovernancePlacement}
          className="rounded px-2 py-0.5 text-xs font-semibold text-primary-blue hover:bg-navy-100 hover:text-primary-blue transition-colors border border-navy-100"
        >
          Change Placement
        </button>
      )}
    </div>
  ) : (
    <span className="text-ink-muted italic text-xs">restricted</span>
  );

  return (
    <Section title="Placements" icon={icon}>
      <dl className="divide-y divide-line">
        {section !== null && (
          section ? (
            <DataRow
              label="Section"
              value={`${section.section_name} (${section.section_code}) · ${section.membership_status}`}
            />
          ) : (
            <DataRow label="Section" value={<span className="text-ink-muted italic text-xs">Not placed in a section</span>} />
          )
        )}
        {household !== null && (
          household ? (
            <DataRow
              label="Household"
              value={`${household.household_name} (${household.household_code}) · ${household.membership_role ?? household.membership_status}`}
            />
          ) : (
            <DataRow label="Household" value={<span className="text-ink-muted italic text-xs">No household assignment</span>} />
          )
        )}
        <div className="flex items-start justify-between gap-4 py-1.5">
          <dt className="shrink-0 text-xs font-medium text-ink-muted w-32">Governance</dt>
          <dd className="text-sm text-ink text-right flex-1">{governanceRowValue}</dd>
        </div>
        {section === null && <DataRow label="Section" value={<span className="text-ink-muted italic text-xs">restricted</span>} />}
        {household === null && <DataRow label="Household" value={<span className="text-ink-muted italic text-xs">restricted</span>} />}
      </dl>
    </Section>
  );
}


// ---------------------------------------------------------------------------
// Main page
// ---------------------------------------------------------------------------

export default function MemberProfilePage() {
  const { memberId } = useParams<{ memberId: string }>();
  const { activeOrganization, isLoading: isOrgLoading } = useOrganizationContext();
  const { hasPermission, isLoading: isPermLoading } = usePermissions();
  const orgId = activeOrganization?.id ?? null;

  const [isEditModalOpen, setIsEditModalOpen] = useState(false);
  const [successToast, setSuccessToast] = useState<string | null>(null);

  // Email modal state
  const [emailModalState, setEmailModalState] = useState<{
    isOpen: boolean;
    mode: 'add' | 'replace';
    existingEmail?: string | null;
  }>({ isOpen: false, mode: 'add' });

  // Phone modal state
  const [phoneModalState, setPhoneModalState] = useState<{
    isOpen: boolean;
    mode: 'add' | 'replace';
    existingRawPhone?: string | null;
  }>({ isOpen: false, mode: 'add' });

  // Address modal state
  const [addressModalState, setAddressModalState] = useState<{
    isOpen: boolean;
    existingPrimaryAddress?: MemberAddress | null;
  }>({ isOpen: false });

  // Placement modal state
  const [isChangePlacementModalOpen, setIsChangePlacementModalOpen] = useState(false);

  // Status change modal state
  const [isChangeStatusModalOpen, setIsChangeStatusModalOpen] = useState(false);

  // Record deceased modal state
  const [isRecordDeceasedModalOpen, setIsRecordDeceasedModalOpen] = useState(false);

  // Archive record modal state
  const [isArchiveModalOpen, setIsArchiveModalOpen] = useState(false);

  // Revert deceased modal state
  const [isRevertDeceasedModalOpen, setIsRevertDeceasedModalOpen] = useState(false);

  // Restore archived record modal state
  const [isRestoreRecordModalOpen, setIsRestoreRecordModalOpen] = useState(false);

  // Remove confirmation modal state
  const [removeModalState, setRemoveModalState] = useState<{
    isOpen: boolean;
    contactType: RemoveTargetType;
    targetId: string;
    label: string;
    isPrimary: boolean;
    hasSecondaryContacts: boolean;
  }>({
    isOpen: false,
    contactType: 'email',
    targetId: '',
    label: '',
    isPrimary: false,
    hasSecondaryContacts: false,
  });

  const canEditProfile = !isPermLoading && hasPermission(Permissions.MembersRecordsUpdate);
  const canManageContacts = !isPermLoading && hasPermission(Permissions.MembersContactsManage);
  const canManageAddresses = !isPermLoading && hasPermission(Permissions.MembersAddressesManage);
  const canManagePlacements = !isPermLoading && hasPermission(Permissions.MembersPlacementsManage);
  const canManageStatus = !isPermLoading && hasPermission(Permissions.MembersStatusManage);
  const canViewStatus = !isPermLoading && hasPermission(Permissions.MembersStatusView);
  const canManageDeceased = !isPermLoading && hasPermission(Permissions.MembersDeceasedManage);
  const canArchiveRecord = !isPermLoading && hasPermission(Permissions.MembersRecordsArchive);
  const canRevertDeceased = !isPermLoading && hasPermission(Permissions.MembersDeceasedRevert);
  const canRestoreRecord = !isPermLoading && hasPermission(Permissions.MembersRecordsRestore);
  const canViewFamilies = !isPermLoading && hasPermission(Permissions.FamiliesRecordsView);
  const canViewHouseholds = !isPermLoading && hasPermission(Permissions.MembersHouseholdsView);
  const canAssignHousehold = !isPermLoading && hasPermission(Permissions.HouseholdsMembersAssign);
  const canTransferHousehold = !isPermLoading && hasPermission(Permissions.HouseholdsMembersTransfer);
  const canEndHousehold = !isPermLoading && hasPermission(Permissions.HouseholdsMembersEnd);

  const {
    data: profile,
    isLoading,

    error,
  } = useMemberProfile(orgId, memberId ?? null);

  // -------------------------------------------------------------------------
  // Loading
  // -------------------------------------------------------------------------
  if (isOrgLoading || isLoading) {
    return (
      <div className="space-y-4">
        {/* Back link skeleton */}
        <div className="h-4 w-24 animate-pulse rounded bg-surface-muted" />
        {/* Header skeleton */}
        <div className="h-16 w-64 animate-pulse rounded-xl bg-surface-muted" />
        {/* Section skeletons */}
        {Array.from({ length: 4 }).map((_, i) => (
          <div key={i} className="h-32 animate-pulse rounded-xl bg-surface-muted" />
        ))}
      </div>
    );
  }

  // -------------------------------------------------------------------------
  // Not found / access denied
  // -------------------------------------------------------------------------
  if (error) {
    const supabaseError = error as { code?: string; message?: string };
    const isNotFound = supabaseError?.code === 'P0002';

    return (
      <div className="space-y-6">
        <Link
          to="/app/members"
          className="inline-flex items-center gap-1.5 text-sm text-ink-muted hover:text-ink"
        >
          <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M15 19l-7-7 7-7" />
          </svg>
          Member Directory
        </Link>

        <div className="rounded-xl border border-danger-600 bg-danger-50 p-6">
          <h2 className="mb-2 text-base font-semibold text-danger-700">
            {isNotFound ? 'Member Not Found' : 'Error Loading Profile'}
          </h2>
          <p className="text-sm text-danger-700">
            {isNotFound
              ? 'This member does not exist or is not accessible to your account.'
              : supabaseError?.message ?? 'An unexpected error occurred.'}
          </p>
        </div>
      </div>
    );
  }

  if (!memberId) {
    return <Navigate to="/app/members" replace />;
  }

  if (!profile) return null;

  // -------------------------------------------------------------------------
  // Render profile
  // -------------------------------------------------------------------------
  const initials = profile.display_name
    .split(' ')
    .map((w: string) => w[0])
    .slice(0, 2)
    .join('')
    .toUpperCase();

  const hasPrimaryEmail = profile.contacts?.emails.some((e) => e.is_primary) ?? false;
  const hasPrimaryPhone = profile.contacts?.phones.some((p) => p.is_primary) ?? false;

  const triggerToast = (msg: string) => {
    setSuccessToast(msg);
    setTimeout(() => setSuccessToast(null), 5000);
  };

  return (
    <div className="space-y-6">
      {/* Toast Notification */}
      {successToast && (
        <div className="flex items-center justify-between rounded-xl border border-success-600/30 bg-success-50 px-4 py-3 text-sm text-success-700 shadow-lg">
          <div className="flex items-center gap-2">
            <svg className="h-5 w-5 text-success-700" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
            </svg>
            <span>{successToast}</span>
          </div>
          <button
            onClick={() => setSuccessToast(null)}
            className="text-xs text-success-700 hover:text-success-700"
          >
            Dismiss
          </button>
        </div>
      )}

      {/* Back */}
      <Link
        to="/app/members"
        id="member-profile-back"
        className="inline-flex items-center gap-1.5 text-sm text-ink-muted hover:text-ink"
      >
        <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
          <path strokeLinecap="round" strokeLinejoin="round" d="M15 19l-7-7 7-7" />
        </svg>
        Member Directory
      </Link>

      {/* Archived Record Banner */}
      {profile.record_status === 'archived' && (
        <div className="rounded-xl border border-line bg-surface-muted p-4 space-y-2 shadow-sm">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2 text-sm font-semibold text-ink">
              <svg className="h-5 w-5 text-ink-muted" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M5 8h14M5 8a2 2 0 110-4h14a2 2 0 110 4M5 8v10a2 2 0 002 2h10a2 2 0 002-2V8m-9 4h4" />
              </svg>
              <span>Archived Member Record</span>
            </div>
            {canRestoreRecord && orgId && (
              <button
                type="button"
                id="restore-record-button"
                onClick={() => setIsRestoreRecordModalOpen(true)}
                className="inline-flex items-center gap-1.5 rounded-lg border border-success-600/30 bg-success-50 px-3 py-1.5 text-xs font-semibold text-success-700 hover:bg-success-100 hover:border-success-600 transition-colors"
              >
                <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
                </svg>
                Restore Record
              </button>
            )}
          </div>
          <p className="text-xs text-ink-muted leading-relaxed">
            This record is archived and excluded from standard active directory searches.
            {profile.archived_at && (
              <span className="ml-1 text-ink-secondary">
                Archived on {new Date(profile.archived_at).toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric', timeZone: 'UTC' })}.
              </span>
            )}
          </p>
          {profile.archive_reason && (
            <p className="text-xs text-ink-muted pt-1 border-t border-line">
              <span className="font-medium text-ink-secondary">Reason:</span> {profile.archive_reason}
            </p>
          )}
        </div>
      )}

      {/* Hero Header with Actions */}
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div className="flex items-center gap-5">
          <div className="flex h-16 w-16 shrink-0 items-center justify-center rounded-2xl bg-navy-50 text-xl font-bold text-primary-blue">
            {initials}
          </div>
          <div>
            <h1 className="text-2xl font-bold tracking-tight text-ink">
              {profile.display_name}
            </h1>
            <div className="mt-1 flex items-center gap-3">
              {profile.membership_status && (
                <div className="flex items-center gap-2">
                  <StatusBadge
                    name={profile.membership_status.name}
                    isActive={profile.membership_status.is_active_membership}
                  />
                  {canManageStatus && orgId && (
                    <button
                      type="button"
                      id="change-status-button"
                      onClick={() => setIsChangeStatusModalOpen(true)}
                      className="rounded px-2 py-0.5 text-xs font-semibold text-primary-blue hover:bg-navy-100 hover:text-primary-blue transition-colors border border-navy-100"
                    >
                      Change Status
                    </button>
                  )}
                </div>
              )}
              <span className="text-xs text-ink-muted capitalize">{profile.record_status}</span>
            </div>
          </div>
        </div>

        {/* Action Controls */}
        <div className="flex items-center gap-3">
          {canManageDeceased && orgId && !profile.is_deceased && profile.membership_status?.code !== 'deceased' && (
            <button
              type="button"
              id="record-deceased-button"
              onClick={() => setIsRecordDeceasedModalOpen(true)}
              className="inline-flex items-center gap-1.5 rounded-lg border border-warning-600/30 bg-warning-50 px-3.5 py-2 text-xs font-semibold text-warning-700 hover:bg-warning-100 hover:border-warning-600 transition-colors shadow-sm"
            >
              <svg className="h-4 w-4 text-warning-700" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
              </svg>
              Record as Deceased
            </button>
          )}

          {/* Correct Deceased Status (correction workflow) */}
          {canRevertDeceased && orgId && profile.is_deceased && profile.membership_status?.code === 'deceased' && (
            <button
              type="button"
              id="revert-deceased-button"
              onClick={() => setIsRevertDeceasedModalOpen(true)}
              className="inline-flex items-center gap-1.5 rounded-lg border border-warning-600/30 bg-warning-50 px-3.5 py-2 text-xs font-semibold text-warning-700 hover:bg-warning-100 hover:border-warning-600 transition-colors shadow-sm"
            >
              <svg className="h-4 w-4 text-warning-700" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              Correct Deceased Status
            </button>
          )}

          {canArchiveRecord && orgId && profile.record_status === 'active' && (
            <button
              type="button"
              id="archive-record-button"
              onClick={() => setIsArchiveModalOpen(true)}
              className="inline-flex items-center gap-1.5 rounded-lg border border-danger-600/30 bg-danger-50 px-3.5 py-2 text-xs font-semibold text-danger-700 hover:bg-danger-100 hover:border-danger-600 transition-colors shadow-sm"
            >
              <svg className="h-4 w-4 text-danger-700" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M5 8h14M5 8a2 2 0 110-4h14a2 2 0 110 4M5 8v10a2 2 0 002 2h10a2 2 0 002-2V8m-9 4h4" />
              </svg>
              Archive Record
            </button>
          )}

          {canEditProfile && orgId && (
            <button
              type="button"
              id="edit-profile-button"
              onClick={() => setIsEditModalOpen(true)}
              className="inline-flex items-center gap-1.5 rounded-lg border border-line bg-surface-muted px-4 py-2 text-xs font-semibold text-ink hover:border-primary-blue hover:text-primary-blue transition-colors shadow-sm"
            >
              <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
              </svg>
              Edit Profile
            </button>
          )}
        </div>
      </div>

      {/* Sections */}
      <OverviewSection profile={profile} />
      <IdentifiersSection identifiers={profile.identifiers} />
      <ContactsSection
        contacts={profile.contacts}
        canManageContacts={canManageContacts}
        onAddEmail={() =>
          setEmailModalState({ isOpen: true, mode: 'add', existingEmail: null })
        }
        onReplaceEmail={(e) =>
          setEmailModalState({
            isOpen: true,
            mode: 'replace',
            existingEmail: e.email_address,
          })
        }
        onRemoveEmail={(e) =>
          setRemoveModalState({
            isOpen: true,
            contactType: 'email',
            targetId: e.id,
            label: e.email_address,
            isPrimary: e.is_primary,
            hasSecondaryContacts: (profile.contacts?.emails.length ?? 0) > 1,
          })
        }
        onAddPhone={() =>
          setPhoneModalState({ isOpen: true, mode: 'add', existingRawPhone: null })
        }
        onReplacePhone={(p) =>
          setPhoneModalState({
            isOpen: true,
            mode: 'replace',
            existingRawPhone: p.phone_number,
          })
        }
        onRemovePhone={(p) =>
          setRemoveModalState({
            isOpen: true,
            contactType: 'phone',
            targetId: p.id,
            label: p.phone_number,
            isPrimary: p.is_primary,
            hasSecondaryContacts: (profile.contacts?.phones.length ?? 0) > 1,
          })
        }
      />
      <AddressesSection
        addresses={profile.addresses}
        canManageAddresses={canManageAddresses}
        onAddAddress={() =>
          setAddressModalState({ isOpen: true, existingPrimaryAddress: null })
        }
        onReplaceAddress={(addr) =>
          setAddressModalState({ isOpen: true, existingPrimaryAddress: addr })
        }
        onRemoveAddress={(addr) =>
          setRemoveModalState({
            isOpen: true,
            contactType: 'address',
            targetId: addr.id,
            label:
              addr.address.formatted_address ||
              [addr.address.address_line_1, addr.address.city_name]
                .filter(Boolean)
                .join(', '),
            isPrimary: addr.is_primary,
            hasSecondaryContacts: false,
          })
        }
      />
      <MemberFamilyCard
        organizationId={orgId}
        memberId={profile.id}
        canViewFamilies={canViewFamilies}
      />
      <PlacementsSection
        section={profile.section_placement}
        household={profile.household_placement}
        governance={profile.governance_placement}
        canManagePlacements={canManagePlacements}
        onChangeGovernancePlacement={() => setIsChangePlacementModalOpen(true)}
      />
      <MemberHouseholdCard
        organizationId={orgId}
        memberId={profile.id}
        memberName={profile.display_name}
        canViewHouseholds={canViewHouseholds}
        canAssignHousehold={canAssignHousehold}
        canTransferHousehold={canTransferHousehold}
        canEndHousehold={canEndHousehold}
      />

      {/* Membership Lifecycle Section */}
      <Section
        title="Membership Lifecycle"
        icon={
          <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
        }
      >
        {canViewStatus && orgId ? (
          <MemberStatusTimeline
            organizationId={orgId}
            memberId={profile.id}
          />
        ) : (
          <RestrictedSection label="Membership Lifecycle" />
        )}
      </Section>

      {/* Edit Profile Modal */}
      {canEditProfile && orgId && isEditModalOpen && (
        <EditMemberProfileModal
          isOpen={isEditModalOpen}
          onClose={() => setIsEditModalOpen(false)}
          organizationId={orgId}
          profile={profile}
          onSuccessToast={triggerToast}
        />
      )}

      {/* Change Governance Placement Modal */}
      {canManagePlacements && orgId && isChangePlacementModalOpen && (
        <ChangeGovernancePlacementModal
          isOpen={isChangePlacementModalOpen}
          onClose={() => setIsChangePlacementModalOpen(false)}
          organizationId={orgId}
          memberId={profile.id}
          currentPlacement={profile.governance_placement}
          onSuccessToast={triggerToast}
        />
      )}

      {/* Change Membership Status Modal */}
      {canManageStatus && orgId && isChangeStatusModalOpen && (
        <ChangeMemberStatusModal
          isOpen={isChangeStatusModalOpen}
          onClose={() => setIsChangeStatusModalOpen(false)}
          organizationId={orgId}
          memberId={profile.id}
          currentStatus={profile.membership_status}
          onSuccessToast={triggerToast}
        />
      )}

      {/* Record Member Deceased Modal */}
      {canManageDeceased && orgId && isRecordDeceasedModalOpen && (
        <RecordMemberDeceasedModal
          isOpen={isRecordDeceasedModalOpen}
          onClose={() => setIsRecordDeceasedModalOpen(false)}
          organizationId={orgId}
          memberId={profile.id}
          displayName={profile.display_name}
          onSuccessToast={triggerToast}
        />
      )}

      {/* Archive Member Record Modal */}
      {canArchiveRecord && orgId && isArchiveModalOpen && (
        <ArchiveMemberRecordModal
          isOpen={isArchiveModalOpen}
          onClose={() => setIsArchiveModalOpen(false)}
          organizationId={orgId}
          memberId={profile.id}
          displayName={profile.display_name}
          governancePlacement={profile.governance_placement}
          onSuccessToast={triggerToast}
        />
      )}

      {/* Correct Deceased Status Modal */}
      {canRevertDeceased && orgId && isRevertDeceasedModalOpen && (
        <RevertMemberDeceasedModal
          isOpen={isRevertDeceasedModalOpen}
          onClose={() => setIsRevertDeceasedModalOpen(false)}
          organizationId={orgId}
          memberId={profile.id}
          displayName={profile.display_name}
          onSuccessToast={triggerToast}
        />
      )}

      {/* Restore Archived Record Modal */}
      {canRestoreRecord && orgId && isRestoreRecordModalOpen && (
        <RestoreMemberRecordModal
          isOpen={isRestoreRecordModalOpen}
          onClose={() => setIsRestoreRecordModalOpen(false)}
          organizationId={orgId}
          memberId={profile.id}
          displayName={profile.display_name}
          onSuccessToast={triggerToast}
        />
      )}

      {/* Edit / Add Email Modal */}

      {canManageContacts && orgId && emailModalState.isOpen && (
        <EditEmailModal
          isOpen={emailModalState.isOpen}
          onClose={() => setEmailModalState({ isOpen: false, mode: 'add' })}
          organizationId={orgId}
          memberId={profile.id}
          mode={emailModalState.mode}
          existingEmail={emailModalState.existingEmail}
          hasExistingPrimary={hasPrimaryEmail}
          onSuccessToast={triggerToast}
        />
      )}

      {/* Edit / Add Phone Modal */}
      {canManageContacts && orgId && phoneModalState.isOpen && (
        <EditPhoneModal
          isOpen={phoneModalState.isOpen}
          onClose={() => setPhoneModalState({ isOpen: false, mode: 'add' })}
          organizationId={orgId}
          memberId={profile.id}
          mode={phoneModalState.mode}
          existingRawPhone={phoneModalState.existingRawPhone}
          hasExistingPrimary={hasPrimaryPhone}
          onSuccessToast={triggerToast}
        />
      )}

      {/* Edit / Add Address Modal */}
      {canManageAddresses && orgId && addressModalState.isOpen && (
        <EditAddressModal
          isOpen={addressModalState.isOpen}
          onClose={() => setAddressModalState({ isOpen: false })}
          organizationId={orgId}
          memberId={profile.id}
          existingPrimaryAddress={addressModalState.existingPrimaryAddress}
          onSuccessToast={triggerToast}
        />
      )}

      {/* Remove Confirmation Modal */}
      {orgId && removeModalState.isOpen && (
        <RemoveContactConfirmModal
          isOpen={removeModalState.isOpen}
          onClose={() => setRemoveModalState((prev) => ({ ...prev, isOpen: false }))}
          organizationId={orgId}
          memberId={profile.id}

          contactType={removeModalState.contactType}
          targetId={removeModalState.targetId}
          label={removeModalState.label}
          isPrimary={removeModalState.isPrimary}
          hasSecondaryContacts={removeModalState.hasSecondaryContacts}
          onSuccessToast={triggerToast}
        />
      )}

      {/* Dev: raw JSON (DEV only) */}
      {import.meta.env.DEV && (
        <details className="rounded-xl border border-line bg-surface p-4 text-xs">
          <summary className="cursor-pointer font-mono text-ink-muted hover:text-ink">
            [DEV] Raw profile JSON
          </summary>
          <pre className="mt-3 overflow-auto text-ink-secondary">
            {JSON.stringify(profile, null, 2)}
          </pre>
        </details>
      )}
    </div>
  );
}
