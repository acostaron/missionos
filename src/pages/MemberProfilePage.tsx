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
import { MemberStatusTimeline } from '../features/members/components/MemberStatusTimeline';
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
    <div className="rounded-xl border border-slate-700 bg-slate-800/60 overflow-hidden">
      <div className="flex items-center justify-between border-b border-slate-700 px-5 py-3.5">
        <div className="flex items-center gap-3">
          <span className="text-slate-400">{icon}</span>
          <h2 className="text-sm font-semibold uppercase tracking-wider text-slate-300">
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
    <p className="flex items-center gap-2 text-xs text-slate-500 italic">
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
      <dt className="shrink-0 text-xs font-medium text-slate-400 w-32">{label}</dt>
      <dd className="text-sm text-slate-200 text-right flex-1">{value ?? <span className="text-slate-500 italic">—</span>}</dd>
    </div>
  );
}

function StatusBadge({ name, isActive }: { name: string; isActive: boolean }) {
  return (
    <span
      className={`inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-medium ${
        isActive
          ? 'border-emerald-700 bg-emerald-900/50 text-emerald-300'
          : 'border-slate-600 bg-slate-800 text-slate-400'
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
      <dl className="divide-y divide-slate-700/50">
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
              <span className="text-slate-500 italic text-xs">restricted</span>
            )
          }
        />
        {profile.is_deceased && (
          <DataRow
            label="Date of death"
            value={
              <div className="flex items-center justify-end gap-2 text-slate-200">
                <span>{profile.deceased_on ?? 'Unknown'}</span>
                {profile.deceased_on_precision && (
                  <span className="text-[10px] text-slate-400 bg-slate-800/80 px-1.5 py-0.5 rounded border border-slate-700">
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
        <p className="text-xs text-slate-500 italic">No identifiers on record.</p>
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
            className="flex items-center justify-between rounded-md border border-slate-700 bg-slate-900/40 px-3 py-2"
          >
            <div>
              <p className="text-xs font-medium text-slate-400 capitalize">
                {id.identifier_type.replace(/_/g, ' ')}
                {id.is_primary && (
                  <span className="ml-2 text-[10px] uppercase tracking-wider text-indigo-400">
                    primary
                  </span>
                )}
              </p>
              <p className="font-mono text-sm text-slate-100">{id.identifier_value}</p>
            </div>
            {id.verification_status && (
              <span className="text-xs text-slate-500 capitalize">
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
        className="inline-flex items-center gap-1 rounded-md border border-slate-700 bg-slate-800/80 px-2.5 py-1 text-xs font-medium text-slate-200 hover:border-indigo-500 hover:text-indigo-300 transition-colors"
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
        className="inline-flex items-center gap-1 rounded-md border border-slate-700 bg-slate-800/80 px-2.5 py-1 text-xs font-medium text-slate-200 hover:border-indigo-500 hover:text-indigo-300 transition-colors"
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
        <p className="text-xs text-slate-500 italic">No contact information on record.</p>
      </Section>
    );
  }

  return (
    <Section title="Contact Information" icon={icon} action={headerActions}>
      <div className="space-y-4">
        {/* Emails Sub-group */}
        <div className="space-y-2">
          <p className="text-xs font-semibold uppercase tracking-wider text-slate-400">
            Email Addresses
          </p>
          {contacts.emails.length === 0 ? (
            <p className="text-xs text-slate-500 italic">No email addresses on record.</p>
          ) : (
            contacts.emails.map((e: MemberEmail) => (
              <div
                key={e.id}
                className="flex items-center justify-between rounded-lg border border-slate-700/60 bg-slate-900/30 px-3.5 py-2.5"
              >
                <div>
                  <div className="flex items-center gap-2">
                    <a
                      href={`mailto:${e.email_address}`}
                      className="text-sm font-medium text-indigo-300 hover:text-indigo-200"
                    >
                      {e.email_address}
                    </a>
                    {e.is_primary && (
                      <span className="rounded-full bg-indigo-950/80 border border-indigo-700/60 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider text-indigo-300">
                        primary
                      </span>
                    )}
                    {e.email_type && (
                      <span className="text-xs text-slate-400">({e.email_type})</span>
                    )}
                  </div>
                  {e.verification_status && (
                    <span className="text-xs text-slate-500 capitalize">{e.verification_status}</span>
                  )}
                </div>

                {canManageContacts && (
                  <div className="flex items-center gap-2">
                    {e.is_primary && (
                      <button
                        type="button"
                        onClick={() => onReplaceEmail(e)}
                        className="rounded px-2 py-1 text-xs font-medium text-slate-300 hover:bg-slate-800 hover:text-indigo-300 transition-colors"
                      >
                        Replace
                      </button>
                    )}
                    <button
                      type="button"
                      onClick={() => onRemoveEmail(e)}
                      className="rounded px-2 py-1 text-xs font-medium text-rose-400 hover:bg-rose-950/40 hover:text-rose-300 transition-colors"
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
        <div className="space-y-2 pt-2 border-t border-slate-700/50">
          <p className="text-xs font-semibold uppercase tracking-wider text-slate-400">
            Phone Numbers
          </p>
          {contacts.phones.length === 0 ? (
            <p className="text-xs text-slate-500 italic">No phone numbers on record.</p>
          ) : (
            contacts.phones.map((p: MemberPhone) => (
              <div
                key={p.id}
                className="flex items-center justify-between rounded-lg border border-slate-700/60 bg-slate-900/30 px-3.5 py-2.5"
              >
                <div>
                  <div className="flex items-center gap-2">
                    <a
                      href={`tel:${p.normalized_e164 ?? p.phone_number}`}
                      className="text-sm font-medium text-slate-100 hover:text-slate-50"
                    >
                      {p.phone_number}
                    </a>
                    {p.is_primary && (
                      <span className="rounded-full bg-indigo-950/80 border border-indigo-700/60 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider text-indigo-300">
                        primary
                      </span>
                    )}
                    {p.phone_type && (
                      <span className="text-xs text-slate-400">({p.phone_type})</span>
                    )}
                  </div>
                  {p.normalized_e164 && p.normalized_e164 !== p.phone_number && (
                    <p className="text-[11px] font-mono text-slate-500">
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
                        className="rounded px-2 py-1 text-xs font-medium text-slate-300 hover:bg-slate-800 hover:text-indigo-300 transition-colors"
                      >
                        Replace
                      </button>
                    )}
                    <button
                      type="button"
                      onClick={() => onRemovePhone(p)}
                      className="rounded px-2 py-1 text-xs font-medium text-rose-400 hover:bg-rose-950/40 hover:text-rose-300 transition-colors"
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
      className="inline-flex items-center gap-1 rounded-md border border-slate-700 bg-slate-800/80 px-2.5 py-1 text-xs font-medium text-slate-200 hover:border-indigo-500 hover:text-indigo-300 transition-colors"
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
        <p className="text-xs text-slate-500 italic">No addresses on record.</p>
      </Section>
    );
  }

  return (
    <Section title="Addresses" icon={icon} action={headerAction}>
      <div className="space-y-4">
        {addresses.map((a: MemberAddress) => (
          <div key={a.id} className="rounded-md border border-slate-700 bg-slate-900/40 px-4 py-3">
            <div className="mb-2 flex items-center justify-between">
              <div className="flex items-center gap-2">
                {a.address_type && (
                  <span className="text-xs font-medium text-slate-400 capitalize">
                    {a.address_type.replace(/_/g, ' ')}
                  </span>
                )}
                {a.is_primary && (
                  <span className="rounded-full bg-indigo-950/80 border border-indigo-700/60 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider text-indigo-300">
                    primary
                  </span>
                )}
                {a.is_mailing_address && (
                  <span className="rounded-full bg-amber-950/80 border border-amber-700/60 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider text-amber-300">
                    mailing
                  </span>
                )}
              </div>

              {canManageAddresses && (
                <div className="flex items-center gap-2">
                  <button
                    type="button"
                    onClick={() => onReplaceAddress(a)}
                    className="rounded px-2 py-1 text-xs font-medium text-slate-300 hover:bg-slate-800 hover:text-indigo-300 transition-colors"
                  >
                    Replace
                  </button>
                  <button
                    type="button"
                    onClick={() => onRemoveAddress(a)}
                    className="rounded px-2 py-1 text-xs font-medium text-rose-400 hover:bg-rose-950/40 hover:text-rose-300 transition-colors"
                  >
                    Remove
                  </button>
                </div>
              )}
            </div>

            <address className="not-italic text-sm text-slate-200 leading-relaxed">
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
        <span className="text-sm text-slate-200">
          {governance.node_name} ({governance.node_code}) · {governance.assignment_type ?? governance.assignment_status}
        </span>
      ) : (
        <span className="text-slate-400 italic text-sm">Unplaced</span>
      )}
      {canManagePlacements && (
        <button
          type="button"
          id="change-placement-button"
          onClick={onChangeGovernancePlacement}
          className="rounded px-2 py-0.5 text-xs font-semibold text-indigo-400 hover:bg-indigo-950/40 hover:text-indigo-300 transition-colors border border-indigo-700/60"
        >
          Change Placement
        </button>
      )}
    </div>
  ) : (
    <span className="text-slate-500 italic text-xs">restricted</span>
  );

  return (
    <Section title="Placements" icon={icon}>
      <dl className="divide-y divide-slate-700/50">
        {section !== null && (
          section ? (
            <DataRow
              label="Section"
              value={`${section.section_name} (${section.section_code}) · ${section.membership_status}`}
            />
          ) : (
            <DataRow label="Section" value={<span className="text-slate-500 italic text-xs">Not placed in a section</span>} />
          )
        )}
        {household !== null && (
          household ? (
            <DataRow
              label="Household"
              value={`${household.household_name} (${household.household_code}) · ${household.membership_role ?? household.membership_status}`}
            />
          ) : (
            <DataRow label="Household" value={<span className="text-slate-500 italic text-xs">No household assignment</span>} />
          )
        )}
        <div className="flex items-start justify-between gap-4 py-1.5">
          <dt className="shrink-0 text-xs font-medium text-slate-400 w-32">Governance</dt>
          <dd className="text-sm text-slate-200 text-right flex-1">{governanceRowValue}</dd>
        </div>
        {section === null && <DataRow label="Section" value={<span className="text-slate-500 italic text-xs">restricted</span>} />}
        {household === null && <DataRow label="Household" value={<span className="text-slate-500 italic text-xs">restricted</span>} />}
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
        <div className="h-4 w-24 animate-pulse rounded bg-slate-800" />
        {/* Header skeleton */}
        <div className="h-16 w-64 animate-pulse rounded-xl bg-slate-800" />
        {/* Section skeletons */}
        {Array.from({ length: 4 }).map((_, i) => (
          <div key={i} className="h-32 animate-pulse rounded-xl bg-slate-800" />
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
          className="inline-flex items-center gap-1.5 text-sm text-slate-400 hover:text-slate-200"
        >
          <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M15 19l-7-7 7-7" />
          </svg>
          Member Directory
        </Link>

        <div className="rounded-xl border border-red-700 bg-red-900/20 p-6">
          <h2 className="mb-2 text-base font-semibold text-red-300">
            {isNotFound ? 'Member Not Found' : 'Error Loading Profile'}
          </h2>
          <p className="text-sm text-red-400">
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
        <div className="flex items-center justify-between rounded-xl border border-emerald-600/40 bg-emerald-950/40 px-4 py-3 text-sm text-emerald-200 shadow-lg">
          <div className="flex items-center gap-2">
            <svg className="h-5 w-5 text-emerald-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
            </svg>
            <span>{successToast}</span>
          </div>
          <button
            onClick={() => setSuccessToast(null)}
            className="text-xs text-emerald-400 hover:text-emerald-200"
          >
            Dismiss
          </button>
        </div>
      )}

      {/* Back */}
      <Link
        to="/app/members"
        id="member-profile-back"
        className="inline-flex items-center gap-1.5 text-sm text-slate-400 hover:text-slate-200"
      >
        <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
          <path strokeLinecap="round" strokeLinejoin="round" d="M15 19l-7-7 7-7" />
        </svg>
        Member Directory
      </Link>

      {/* Hero Header with Actions */}
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div className="flex items-center gap-5">
          <div className="flex h-16 w-16 shrink-0 items-center justify-center rounded-2xl bg-indigo-900 text-xl font-bold text-indigo-200">
            {initials}
          </div>
          <div>
            <h1 className="text-2xl font-bold tracking-tight text-slate-100">
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
                      className="rounded px-2 py-0.5 text-xs font-semibold text-indigo-400 hover:bg-indigo-950/40 hover:text-indigo-300 transition-colors border border-indigo-700/60"
                    >
                      Change Status
                    </button>
                  )}
                </div>
              )}
              <span className="text-xs text-slate-500 capitalize">{profile.record_status}</span>
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
              className="inline-flex items-center gap-1.5 rounded-lg border border-amber-700/60 bg-amber-950/30 px-3.5 py-2 text-xs font-semibold text-amber-300 hover:bg-amber-950/60 hover:border-amber-600 transition-colors shadow-sm"
            >
              <svg className="h-4 w-4 text-amber-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
              </svg>
              Record as Deceased
            </button>
          )}

          {canEditProfile && orgId && (
            <button
              type="button"
              id="edit-profile-button"
              onClick={() => setIsEditModalOpen(true)}
              className="inline-flex items-center gap-1.5 rounded-lg border border-slate-700 bg-slate-800/80 px-4 py-2 text-xs font-semibold text-slate-200 hover:border-indigo-500 hover:text-indigo-300 transition-colors shadow-sm"
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
      <PlacementsSection
        section={profile.section_placement}
        household={profile.household_placement}
        governance={profile.governance_placement}
        canManagePlacements={canManagePlacements}
        onChangeGovernancePlacement={() => setIsChangePlacementModalOpen(true)}
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
        <details className="rounded-xl border border-slate-700 bg-slate-900 p-4 text-xs">
          <summary className="cursor-pointer font-mono text-slate-400 hover:text-slate-200">
            [DEV] Raw profile JSON
          </summary>
          <pre className="mt-3 overflow-auto text-slate-300">
            {JSON.stringify(profile, null, 2)}
          </pre>
        </details>
      )}
    </div>
  );
}
