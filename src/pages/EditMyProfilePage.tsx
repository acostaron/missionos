import { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { useQueryClient } from '@tanstack/react-query';
import { ArrowLeft, User, Mail, Phone, Home, Heart, ShieldAlert } from 'lucide-react';
import { useOrganizationContext } from '../hooks/use-organization-context';
import {
  useMyProfileDetails,
  useUpdateMyBasicProfile,
  useSetMyContactPoint,
  useSetMyWeddingDate,
} from '../features/self-service/portal-api';
import { MemberPhotoUploader } from '../features/self-service/components/MemberPhotoUploader';
import { getEventErrorMessage } from '../features/events/error-message';
import { getTodayNyDate } from '../lib/ny-time';
import {
  Alert,
  Badge,
  Button,
  Card,
  EmptyState,
  FormField,
  Input,
  Modal,
  PageHeader,
  Select,
} from '../components/ui';

export default function EditMyProfilePage() {
  const queryClient = useQueryClient();
  const { activeOrganization, isLoading: isOrgLoading } = useOrganizationContext();
  const orgId = activeOrganization?.id ?? null;

  const { data: details, isLoading, error } = useMyProfileDetails(orgId);
  const updateProfileMutation = useUpdateMyBasicProfile();
  const contactPointMutation = useSetMyContactPoint();
  const weddingDateMutation = useSetMyWeddingDate();

  const todayStr = getTodayNyDate();

  // -------------------------------------------------------------------------
  // Basic Info Form State
  // -------------------------------------------------------------------------
  const [givenNames, setGivenNames] = useState('');
  const [middleNames, setMiddleNames] = useState('');
  const [familyName, setFamilyName] = useState('');
  const [preferredName, setPreferredName] = useState('');
  const [birthDate, setBirthDate] = useState('');
  const [sex, setSex] = useState<'male' | 'female' | ''>('');
  const [basicSuccess, setBasicSuccess] = useState<string | null>(null);
  const [basicError, setBasicError] = useState<string | null>(null);

  // -------------------------------------------------------------------------
  // Email Form State
  // -------------------------------------------------------------------------
  const [newPrimaryEmail, setNewPrimaryEmail] = useState('');
  const [newSecondaryEmail, setNewSecondaryEmail] = useState('');
  const [emailSuccess, setEmailSuccess] = useState<string | null>(null);
  const [emailError, setEmailError] = useState<string | null>(null);
  const [emailToRemove, setEmailToRemove] = useState<{ id: string; email: string } | null>(null);

  // -------------------------------------------------------------------------
  // Phone Form State
  // -------------------------------------------------------------------------
  const [newPrimaryPhone, setNewPrimaryPhone] = useState('');
  const [newSecondaryPhone, setNewSecondaryPhone] = useState('');
  const [phoneSuccess, setPhoneSuccess] = useState<string | null>(null);
  const [phoneError, setPhoneError] = useState<string | null>(null);
  const [phoneToRemove, setPhoneToRemove] = useState<{ id: string; phone: string } | null>(null);

  // -------------------------------------------------------------------------
  // Address Form State
  // -------------------------------------------------------------------------
  const [addrLine1, setAddrLine1] = useState('');
  const [addrLine2, setAddrLine2] = useState('');
  const [addrCity, setAddrCity] = useState('');
  const [addrState, setAddrState] = useState('NY');
  const [addrPostal, setAddrPostal] = useState('');
  const [addressSuccess, setAddressSuccess] = useState<string | null>(null);
  const [addressError, setAddressError] = useState<string | null>(null);

  // -------------------------------------------------------------------------
  // Wedding Date State
  // -------------------------------------------------------------------------
  const [weddingDate, setWeddingDate] = useState('');
  const [weddingSuccess, setWeddingSuccess] = useState<string | null>(null);
  const [weddingError, setWeddingError] = useState<string | null>(null);

  // Sync initial state when details load
  useEffect(() => {
    if (details) {
      setGivenNames(details.given_names ?? '');
      setMiddleNames(details.middle_names ?? '');
      setFamilyName(details.family_name ?? '');
      setPreferredName(details.preferred_name ?? '');
      setBirthDate(details.birth_date ?? '');
      setSex(details.sex === 'male' || details.sex === 'female' ? details.sex : '');

      if (details.home_address) {
        setAddrLine1(details.home_address.line1);
        setAddrLine2(details.home_address.line2 ?? '');
        setAddrCity(details.home_address.city);
        setAddrState(details.home_address.state ?? 'NY');
        setAddrPostal(details.home_address.postal ?? '');
      }

      if (details.spouse?.wedding_date) {
        setWeddingDate(details.spouse.wedding_date);
      }
    }
  }, [details]);

  if (isOrgLoading || isLoading) {
    return (
      <div className="flex min-h-[40vh] items-center justify-center">
        <div className="text-sm text-ink-muted">Loading profile…</div>
      </div>
    );
  }

  const errObj = error as { code?: string; message?: string } | null;
  const isNotLinked = errObj?.code === 'P0002' || (errObj?.message && errObj.message.toLowerCase().includes('not linked'));

  if (isNotLinked) {
    return (
      <div className="mx-auto max-w-3xl px-4 py-8">
        <Card padding="comfortable">
          <EmptyState
            icon={<User />}
            title="Account Not Linked"
            message="Your MissionOS account is not currently linked to a member record. Once your servant leader or administrator connects your profile, your information will appear here."
            action={
              <Link
                to="/app/dashboard"
                className="inline-flex h-9 items-center rounded-control border border-line-strong bg-surface px-4 text-small font-medium text-ink hover:bg-surface-muted"
              >
                Return to Home
              </Link>
            }
          />
        </Card>
      </div>
    );
  }

  if (error || !details || !orgId) {
    return (
      <div className="mx-auto max-w-3xl px-4 py-8">
        <Card padding="comfortable">
          <EmptyState
            icon={<ShieldAlert />}
            title="Unable to load profile"
            message={error ? getEventErrorMessage(error) : 'Please select an active organization.'}
            action={
              <Link
                to="/app/profile"
                className="inline-flex h-9 items-center rounded-control border border-line-strong bg-surface px-4 text-small font-medium text-ink hover:bg-surface-muted"
              >
                Back to My Profile
              </Link>
            }
          />
        </Card>
      </div>
    );
  }

  const canEdit = details.can_edit;

  // -------------------------------------------------------------------------
  // Handlers
  // -------------------------------------------------------------------------

  const handleSaveBasic = async (e: React.FormEvent) => {
    e.preventDefault();
    setBasicSuccess(null);
    setBasicError(null);

    try {
      await updateProfileMutation.mutateAsync({
        organizationId: orgId,
        givenNames: givenNames.trim(),
        familyName: familyName.trim(),
        middleNames: middleNames.trim() || null,
        preferredName: preferredName.trim() || null,
        birthDate: birthDate || null,
        sex: sex || null,
      });
      setBasicSuccess('Personal details updated successfully.');
    } catch (err) {
      setBasicError(getEventErrorMessage(err));
    }
  };

  const handleReplacePrimaryEmail = async (e: React.FormEvent) => {
    e.preventDefault();
    setEmailSuccess(null);
    setEmailError(null);
    if (!newPrimaryEmail.trim()) return;

    try {
      await contactPointMutation.mutateAsync({
        organizationId: orgId,
        contactType: 'email',
        operation: 'replace_primary',
        value: newPrimaryEmail.trim().toLowerCase(),
      });
      setNewPrimaryEmail('');
      setEmailSuccess('Main email updated.');
    } catch (err) {
      setEmailError(getEventErrorMessage(err));
    }
  };

  const handleAddSecondaryEmail = async (e: React.FormEvent) => {
    e.preventDefault();
    setEmailSuccess(null);
    setEmailError(null);
    if (!newSecondaryEmail.trim()) return;

    try {
      await contactPointMutation.mutateAsync({
        organizationId: orgId,
        contactType: 'email',
        operation: 'add',
        value: newSecondaryEmail.trim().toLowerCase(),
      });
      setNewSecondaryEmail('');
      setEmailSuccess('Secondary email added.');
    } catch (err) {
      setEmailError(getEventErrorMessage(err));
    }
  };

  const handleRemoveEmailConfirm = async () => {
    if (!emailToRemove) return;
    setEmailSuccess(null);
    setEmailError(null);

    try {
      await contactPointMutation.mutateAsync({
        organizationId: orgId,
        contactType: 'email',
        operation: 'remove',
        targetId: emailToRemove.id,
      });
      setEmailSuccess('Email removed.');
      setEmailToRemove(null);
    } catch (err) {
      setEmailError(getEventErrorMessage(err));
    }
  };

  const handleReplacePrimaryPhone = async (e: React.FormEvent) => {
    e.preventDefault();
    setPhoneSuccess(null);
    setPhoneError(null);
    if (!newPrimaryPhone.trim()) return;

    try {
      await contactPointMutation.mutateAsync({
        organizationId: orgId,
        contactType: 'phone',
        operation: 'replace_primary',
        value: newPrimaryPhone.trim(),
      });
      setNewPrimaryPhone('');
      setPhoneSuccess('Main phone updated.');
    } catch (err) {
      setPhoneError(getEventErrorMessage(err));
    }
  };

  const handleAddSecondaryPhone = async (e: React.FormEvent) => {
    e.preventDefault();
    setPhoneSuccess(null);
    setPhoneError(null);
    if (!newSecondaryPhone.trim()) return;

    try {
      await contactPointMutation.mutateAsync({
        organizationId: orgId,
        contactType: 'phone',
        operation: 'add',
        value: newSecondaryPhone.trim(),
      });
      setNewSecondaryPhone('');
      setPhoneSuccess('Secondary phone added.');
    } catch (err) {
      setPhoneError(getEventErrorMessage(err));
    }
  };

  const handleRemovePhoneConfirm = async () => {
    if (!phoneToRemove) return;
    setPhoneSuccess(null);
    setPhoneError(null);

    try {
      await contactPointMutation.mutateAsync({
        organizationId: orgId,
        contactType: 'phone',
        operation: 'remove',
        targetId: phoneToRemove.id,
      });
      setPhoneSuccess('Phone removed.');
      setPhoneToRemove(null);
    } catch (err) {
      setPhoneError(getEventErrorMessage(err));
    }
  };

  const handleSaveAddress = async (e: React.FormEvent) => {
    e.preventDefault();
    setAddressSuccess(null);
    setAddressError(null);

    if (!addrLine1.trim() || !addrCity.trim()) {
      setAddressError('Street and city are required.');
      return;
    }

    try {
      await contactPointMutation.mutateAsync({
        organizationId: orgId,
        contactType: 'address',
        operation: 'replace_primary',
        addressData: {
          line1: addrLine1.trim(),
          line2: addrLine2.trim() || null,
          city: addrCity.trim(),
          state: addrState.trim() || null,
          postal: addrPostal.trim() || null,
          country: 'US',
        },
      });
      setAddressSuccess('Home address updated.');
    } catch (err) {
      setAddressError(getEventErrorMessage(err));
    }
  };

  const handleSaveWeddingDate = async (e: React.FormEvent) => {
    e.preventDefault();
    setWeddingSuccess(null);
    setWeddingError(null);

    try {
      await weddingDateMutation.mutateAsync({
        organizationId: orgId,
        weddingDate: weddingDate || null,
      });
      setWeddingSuccess('Wedding date updated.');
    } catch (err) {
      setWeddingError(getEventErrorMessage(err));
    }
  };

  return (
    <div className="mx-auto max-w-3xl space-y-6 px-4 py-8 sm:px-6">
      <PageHeader
        title="Edit My Profile"
        description="Update your personal details, contact points, and photo."
        breadcrumb={
          <nav aria-label="Breadcrumb" className="flex items-center gap-2 text-xs text-ink-muted">
            <Link
              to="/app/profile"
              className="inline-flex items-center gap-1 hover:text-ink transition-colors"
            >
              <ArrowLeft className="h-3.5 w-3.5" aria-hidden="true" />
              My Profile
            </Link>
            <span aria-hidden="true">/</span>
            <span className="font-medium text-ink">Edit</span>
          </nav>
        }
      />

      {!canEdit && (
        <Alert variant="warning" title="Editing Restricted">
          Your profile cannot be edited right now. Please contact your chapter servant.
        </Alert>
      )}

      {/* 1. Photo Card */}
      <Card padding="comfortable" className="space-y-4">
        <h2 className="text-section-title font-semibold text-ink">Profile Photo</h2>
        <MemberPhotoUploader
          organizationId={orgId}
          memberId={null}
          effectiveMemberId={details.member_id}
          currentPath={details.photo_path}
          memberName={details.display_name}
          onPhotoChanged={() => {
            queryClient.invalidateQueries({ queryKey: ['members', 'photo-urls'] });
          }}
        />
      </Card>

      {/* 2. Personal Details Card */}
      <Card padding="comfortable" className="space-y-4">
        <div className="flex items-center gap-2">
          <User className="h-5 w-5 text-primary" />
          <h2 className="text-section-title font-semibold text-ink">Name & Personal Details</h2>
        </div>

        {basicSuccess && <Alert variant="success">{basicSuccess}</Alert>}
        {basicError && <Alert variant="danger">{basicError}</Alert>}

        <form onSubmit={handleSaveBasic} className="space-y-4">
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <FormField label="First Name" required>
              <Input
                type="text"
                value={givenNames}
                onChange={(e) => setGivenNames(e.target.value)}
                disabled={!canEdit || updateProfileMutation.isPending}
                required
              />
            </FormField>
            <FormField label="Middle Name">
              <Input
                type="text"
                value={middleNames}
                onChange={(e) => setMiddleNames(e.target.value)}
                disabled={!canEdit || updateProfileMutation.isPending}
              />
            </FormField>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <FormField label="Last Name" required>
              <Input
                type="text"
                value={familyName}
                onChange={(e) => setFamilyName(e.target.value)}
                disabled={!canEdit || updateProfileMutation.isPending}
                required
              />
            </FormField>
            <FormField label="Preferred Name" hint="What people call you">
              <Input
                type="text"
                value={preferredName}
                onChange={(e) => setPreferredName(e.target.value)}
                disabled={!canEdit || updateProfileMutation.isPending}
              />
            </FormField>
          </div>

          <p className="text-caption text-ink-muted">
            Use this to fix spelling. For a legal name change, please contact your chapter servant.
          </p>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 pt-2">
            <FormField label="Birth Date">
              <Input
                type="date"
                value={birthDate}
                max={todayStr}
                onChange={(e) => setBirthDate(e.target.value)}
                disabled={!canEdit || updateProfileMutation.isPending}
              />
            </FormField>
            <FormField label="Sex">
              <Select
                value={sex}
                onChange={(e) => setSex(e.target.value as 'male' | 'female' | '')}
                disabled={!canEdit || updateProfileMutation.isPending}
              >
                <option value="">Select…</option>
                <option value="male">Male</option>
                <option value="female">Female</option>
              </Select>
            </FormField>
          </div>

          {canEdit && (
            <div className="pt-2 flex justify-end">
              <Button type="submit" variant="primary" loading={updateProfileMutation.isPending}>
                Save personal details
              </Button>
            </div>
          )}
        </form>
      </Card>

      {/* 3. Email Card */}
      <Card padding="comfortable" className="space-y-4">
        <div className="flex items-center gap-2">
          <Mail className="h-5 w-5 text-primary" />
          <h2 className="text-section-title font-semibold text-ink">Email Addresses</h2>
        </div>

        {emailSuccess && <Alert variant="success">{emailSuccess}</Alert>}
        {emailError && <Alert variant="danger">{emailError}</Alert>}

        {details.emails.length > 0 ? (
          <div className="divide-y divide-line rounded-card border border-line bg-surface">
            {details.emails.map((e) => (
              <div key={e.id} className="flex items-center justify-between p-3 text-small">
                <div className="flex items-center gap-2">
                  <span className="font-medium text-ink">{e.email}</span>
                  {e.is_primary && <Badge variant="success">Main</Badge>}
                </div>
                {canEdit && !e.is_primary && (
                  <button
                    type="button"
                    onClick={() => setEmailToRemove({ id: e.id, email: e.email })}
                    className="text-xs font-medium text-danger-700 hover:underline"
                  >
                    Remove
                  </button>
                )}
              </div>
            ))}
          </div>
        ) : (
          <p className="text-small text-ink-muted">No emails on file.</p>
        )}

        {canEdit && (
          <div className="space-y-4 pt-2">
            <form onSubmit={handleReplacePrimaryEmail} className="flex flex-col sm:flex-row gap-2 items-end">
              <div className="flex-1 w-full">
                <FormField label="Change main email">
                  <Input
                    type="email"
                    value={newPrimaryEmail}
                    onChange={(e) => setNewPrimaryEmail(e.target.value)}
                    placeholder="newprimary@example.com"
                  />
                </FormField>
              </div>
              <Button
                type="submit"
                variant="outline"
                disabled={!newPrimaryEmail.trim() || contactPointMutation.isPending}
              >
                Update main email
              </Button>
            </form>

            <form onSubmit={handleAddSecondaryEmail} className="flex flex-col sm:flex-row gap-2 items-end">
              <div className="flex-1 w-full">
                <FormField label="Add another email">
                  <Input
                    type="email"
                    value={newSecondaryEmail}
                    onChange={(e) => setNewSecondaryEmail(e.target.value)}
                    placeholder="secondary@example.com"
                  />
                </FormField>
              </div>
              <Button
                type="submit"
                variant="outline"
                disabled={!newSecondaryEmail.trim() || contactPointMutation.isPending}
              >
                Add email
              </Button>
            </form>
          </div>
        )}

        <p className="text-caption text-ink-muted">
          Changing your email here does not change the email you use to sign in.
        </p>
      </Card>

      {/* 4. Mobile Phone Card */}
      <Card padding="comfortable" className="space-y-4">
        <div className="flex items-center gap-2">
          <Phone className="h-5 w-5 text-primary" />
          <h2 className="text-section-title font-semibold text-ink">Mobile Phones</h2>
        </div>

        {phoneSuccess && <Alert variant="success">{phoneSuccess}</Alert>}
        {phoneError && <Alert variant="danger">{phoneError}</Alert>}

        {details.phones.length > 0 ? (
          <div className="divide-y divide-line rounded-card border border-line bg-surface">
            {details.phones.map((p) => (
              <div key={p.id} className="flex items-center justify-between p-3 text-small">
                <div className="flex items-center gap-2">
                  <span className="font-medium text-ink">{p.phone}</span>
                  {p.is_primary && <Badge variant="success">Main</Badge>}
                </div>
                {canEdit && !p.is_primary && (
                  <button
                    type="button"
                    onClick={() => setPhoneToRemove({ id: p.id, phone: p.phone })}
                    className="text-xs font-medium text-danger-700 hover:underline"
                  >
                    Remove
                  </button>
                )}
              </div>
            ))}
          </div>
        ) : (
          <p className="text-small text-ink-muted">No phone numbers on file.</p>
        )}

        {canEdit && (
          <div className="space-y-4 pt-2">
            <form onSubmit={handleReplacePrimaryPhone} className="flex flex-col sm:flex-row gap-2 items-end">
              <div className="flex-1 w-full">
                <FormField label="Change main phone">
                  <Input
                    type="tel"
                    value={newPrimaryPhone}
                    onChange={(e) => setNewPrimaryPhone(e.target.value)}
                    placeholder="(516) 555-0123"
                  />
                </FormField>
              </div>
              <Button
                type="submit"
                variant="outline"
                disabled={!newPrimaryPhone.trim() || contactPointMutation.isPending}
              >
                Update main phone
              </Button>
            </form>

            <form onSubmit={handleAddSecondaryPhone} className="flex flex-col sm:flex-row gap-2 items-end">
              <div className="flex-1 w-full">
                <FormField label="Add another phone">
                  <Input
                    type="tel"
                    value={newSecondaryPhone}
                    onChange={(e) => setNewSecondaryPhone(e.target.value)}
                    placeholder="(516) 555-0123"
                  />
                </FormField>
              </div>
              <Button
                type="submit"
                variant="outline"
                disabled={!newSecondaryPhone.trim() || contactPointMutation.isPending}
              >
                Add phone
              </Button>
            </form>
          </div>
        )}
      </Card>

      {/* 5. Home Address Card */}
      <Card padding="comfortable" className="space-y-4">
        <div className="flex items-center gap-2">
          <Home className="h-5 w-5 text-primary" />
          <h2 className="text-section-title font-semibold text-ink">Home Address</h2>
        </div>

        {addressSuccess && <Alert variant="success">{addressSuccess}</Alert>}
        {addressError && <Alert variant="danger">{addressError}</Alert>}

        <form onSubmit={handleSaveAddress} className="space-y-4">
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
            <div className="sm:col-span-2">
              <FormField label="Street Address" required>
                <Input
                  type="text"
                  value={addrLine1}
                  onChange={(e) => setAddrLine1(e.target.value)}
                  disabled={!canEdit || contactPointMutation.isPending}
                  required
                />
              </FormField>
            </div>
            <div>
              <FormField label="Apt / Unit">
                <Input
                  type="text"
                  value={addrLine2}
                  onChange={(e) => setAddrLine2(e.target.value)}
                  disabled={!canEdit || contactPointMutation.isPending}
                />
              </FormField>
            </div>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
            <div>
              <FormField label="City" required>
                <Input
                  type="text"
                  value={addrCity}
                  onChange={(e) => setAddrCity(e.target.value)}
                  disabled={!canEdit || contactPointMutation.isPending}
                  required
                />
              </FormField>
            </div>
            <div>
              <FormField label="State" required>
                <Input
                  type="text"
                  value={addrState}
                  onChange={(e) => setAddrState(e.target.value)}
                  disabled={!canEdit || contactPointMutation.isPending}
                  maxLength={2}
                  required
                />
              </FormField>
            </div>
            <div>
              <FormField label="ZIP Code">
                <Input
                  type="text"
                  value={addrPostal}
                  onChange={(e) => setAddrPostal(e.target.value)}
                  disabled={!canEdit || contactPointMutation.isPending}
                />
              </FormField>
            </div>
          </div>

          {canEdit && (
            <div className="pt-2 flex justify-end">
              <Button type="submit" variant="primary" loading={contactPointMutation.isPending}>
                Save address
              </Button>
            </div>
          )}
        </form>
      </Card>

      {/* 6. Wedding Date Card */}
      <Card padding="comfortable" className="space-y-4">
        <div className="flex items-center gap-2">
          <Heart className="h-5 w-5 text-primary" />
          <h2 className="text-section-title font-semibold text-ink">Wedding Date</h2>
        </div>

        {weddingSuccess && <Alert variant="success">{weddingSuccess}</Alert>}
        {weddingError && <Alert variant="danger">{weddingError}</Alert>}

        {details.spouse ? (
          <form onSubmit={handleSaveWeddingDate} className="space-y-4">
            <p className="text-small text-ink">
              Married to <strong className="text-ink font-semibold">{details.spouse.display_name}</strong>
            </p>

            <FormField label="Wedding Date">
              <Input
                type="date"
                value={weddingDate}
                max={todayStr}
                onChange={(e) => setWeddingDate(e.target.value)}
                disabled={!canEdit || weddingDateMutation.isPending}
              />
            </FormField>

            {canEdit && (
              <div className="flex justify-end">
                <Button type="submit" variant="primary" loading={weddingDateMutation.isPending}>
                  Save wedding date
                </Button>
              </div>
            )}
          </form>
        ) : (
          <p className="text-small text-ink-muted">
            If you are married, ask your chapter servant to link your spouse so you can add your wedding date.
          </p>
        )}
      </Card>

      {/* Confirmation Modal: Remove Email */}
      <Modal
        open={!!emailToRemove}
        onClose={() => setEmailToRemove(null)}
        title="Remove Email?"
        size="sm"
        footer={
          <>
            <Button type="button" variant="outline" onClick={() => setEmailToRemove(null)}>
              Cancel
            </Button>
            <Button
              type="button"
              variant="danger"
              onClick={handleRemoveEmailConfirm}
              loading={contactPointMutation.isPending}
            >
              Remove Email
            </Button>
          </>
        }
      >
        <p className="text-small text-ink-secondary">
          Are you sure you want to remove <strong className="text-ink">{emailToRemove?.email}</strong>?
        </p>
      </Modal>

      {/* Confirmation Modal: Remove Phone */}
      <Modal
        open={!!phoneToRemove}
        onClose={() => setPhoneToRemove(null)}
        title="Remove Phone?"
        size="sm"
        footer={
          <>
            <Button type="button" variant="outline" onClick={() => setPhoneToRemove(null)}>
              Cancel
            </Button>
            <Button
              type="button"
              variant="danger"
              onClick={handleRemovePhoneConfirm}
              loading={contactPointMutation.isPending}
            >
              Remove Phone
            </Button>
          </>
        }
      >
        <p className="text-small text-ink-secondary">
          Are you sure you want to remove <strong className="text-ink">{phoneToRemove?.phone}</strong>?
        </p>
      </Modal>
    </div>
  );
}
