import { useParams, Link, Navigate } from 'react-router-dom';
import { useOrganizationContext } from '../hooks/use-organization-context';
import { useMemberProfile } from '../features/members/queries';
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
  children,
}: {
  title: string;
  icon: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <div className="rounded-xl border border-slate-700 bg-slate-800/60 overflow-hidden">
      <div className="flex items-center gap-3 border-b border-slate-700 px-5 py-3.5">
        <span className="text-slate-400">{icon}</span>
        <h2 className="text-sm font-semibold uppercase tracking-wider text-slate-300">
          {title}
        </h2>
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

function ContactsSection({ contacts }: { contacts: MemberProfile['contacts'] }) {
  const icon = (
    <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
      <path strokeLinecap="round" strokeLinejoin="round"
        d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
    </svg>
  );

  if (contacts === null) {
    return <Section title="Contact Information" icon={icon}><RestrictedSection label="Contacts" /></Section>;
  }

  const hasAny = contacts.emails.length > 0 || contacts.phones.length > 0;
  if (!hasAny) {
    return <Section title="Contact Information" icon={icon}><p className="text-xs text-slate-500 italic">No contact information on record.</p></Section>;
  }

  return (
    <Section title="Contact Information" icon={icon}>
      <div className="space-y-3">
        {/* Emails */}
        {contacts.emails.map((e: MemberEmail) => (
          <div key={e.id} className="flex items-center justify-between">
            <div>
              <p className="text-xs text-slate-400">
                Email{e.email_type ? ` (${e.email_type})` : ''}
                {e.is_primary && (
                  <span className="ml-2 text-[10px] uppercase text-indigo-400">primary</span>
                )}
              </p>
              <a
                href={`mailto:${e.email_address}`}
                className="text-sm text-indigo-300 hover:text-indigo-200"
              >
                {e.email_address}
              </a>
            </div>
            {e.verification_status && (
              <span className="text-xs text-slate-500 capitalize">{e.verification_status}</span>
            )}
          </div>
        ))}

        {/* Phones */}
        {contacts.phones.map((p: MemberPhone) => (
          <div key={p.id} className="flex items-center justify-between">
            <div>
              <p className="text-xs text-slate-400">
                Phone{p.phone_type ? ` (${p.phone_type})` : ''}
                {p.is_primary && (
                  <span className="ml-2 text-[10px] uppercase text-indigo-400">primary</span>
                )}
              </p>
              <a
                href={`tel:${p.normalized_e164 ?? p.phone_number}`}
                className="text-sm text-slate-100 hover:text-slate-50"
              >
                {p.phone_number}
              </a>
            </div>
          </div>
        ))}
      </div>
    </Section>
  );
}

function AddressesSection({ addresses }: { addresses: MemberProfile['addresses'] }) {
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
  if (addresses.length === 0) {
    return <Section title="Addresses" icon={icon}><p className="text-xs text-slate-500 italic">No addresses on record.</p></Section>;
  }

  return (
    <Section title="Addresses" icon={icon}>
      <div className="space-y-4">
        {addresses.map((a: MemberAddress) => (
          <div key={a.id} className="rounded-md border border-slate-700 bg-slate-900/40 px-4 py-3">
            <div className="mb-1 flex items-center gap-2">
              {a.address_type && (
                <span className="text-xs font-medium text-slate-400 capitalize">
                  {a.address_type.replace(/_/g, ' ')}
                </span>
              )}
              {a.is_primary && (
                <span className="text-[10px] uppercase tracking-wider text-indigo-400">primary</span>
              )}
              {a.is_mailing_address && (
                <span className="text-[10px] uppercase tracking-wider text-amber-400">mailing</span>
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

function PlacementsSection({
  section,
  household,
  governance,
}: {
  section: SectionPlacement | null;
  household: HouseholdPlacement | null;
  governance: GovernancePlacement | null;
}) {
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
        {governance !== null && (
          governance ? (
            <DataRow
              label="Governance"
              value={`${governance.node_name} (${governance.node_code}) · ${governance.assignment_type ?? governance.assignment_status}`}
            />
          ) : (
            <DataRow label="Governance" value={<span className="text-slate-500 italic text-xs">No governance assignment</span>} />
          )
        )}
        {section === null && <DataRow label="Section" value={<span className="text-slate-500 italic text-xs">restricted</span>} />}
        {household === null && <DataRow label="Household" value={<span className="text-slate-500 italic text-xs">restricted</span>} />}
        {governance === null && <DataRow label="Governance" value={<span className="text-slate-500 italic text-xs">restricted</span>} />}
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
  const orgId = activeOrganization?.id ?? null;

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

  return (
    <div className="space-y-6">
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

      {/* Hero */}
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
              <StatusBadge
                name={profile.membership_status.name}
                isActive={profile.membership_status.is_active_membership}
              />
            )}
            <span className="text-xs text-slate-500 capitalize">{profile.record_status}</span>
          </div>
        </div>
      </div>

      {/* Sections */}
      <OverviewSection profile={profile} />
      <IdentifiersSection identifiers={profile.identifiers} />
      <ContactsSection contacts={profile.contacts} />
      <AddressesSection addresses={profile.addresses} />
      <PlacementsSection
        section={profile.section_placement}
        household={profile.household_placement}
        governance={profile.governance_placement}
      />

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
