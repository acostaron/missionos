import { useState, useEffect, useCallback } from 'react';
import { useNavigate, useSearchParams, Link } from 'react-router-dom';
import { useQueryClient } from '@tanstack/react-query';
import { CheckCircle2, AlertTriangle, XCircle, Loader2 } from 'lucide-react';
import { supabase } from '../lib/supabase/client';
import { normalizeError } from '../lib/supabase/errors';
import { useAuth } from '../hooks/use-auth';
import { useOrganizationContext } from '../hooks/use-organization-context';
import { Alert, Button, Card, FormField, Input } from '../components/ui';
import { fetchInvitationDetails, acceptMemberAccountInvitation } from '../features/auth/invitation/api';
import type { InvitationDetails } from '../features/auth/invitation/api';
import { identityKeys } from '../features/identity/queries';
import { authorizationKeys } from '../features/authorization/queries';
import { selfServiceKeys } from '../features/self-service/api';

type PageState =
  | 'processing'
  | 'unauthenticated'
  | 'password_setup'
  | 'ready'
  | 'accepting'
  | 'success'
  | 'expired'
  | 'already_accepted'
  | 'unusable'
  | 'invalid'
  | 'error';

export default function InviteAcceptPage() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const queryClient = useQueryClient();
  const { session, isLoading: authLoading } = useAuth();
  const { setActiveOrganizationId } = useOrganizationContext();

  const [pageState, setPageState] = useState<PageState>('processing');
  const [details, setDetails] = useState<InvitationDetails | null>(null);
  const [errorMessage, setErrorMessage] = useState<string>('');
  
  // Password setup state
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [passwordError, setPasswordError] = useState('');
  const [isSettingPassword, setIsSettingPassword] = useState(false);
  const [passwordSet, setPasswordSet] = useState(false);

  // Check URL parameters for explicit invitation ID
  const invitationIdParam = searchParams.get('invitation') ?? undefined;

  // Process and load invitation details
  const loadInvitation = useCallback(async () => {
    try {
      setPageState('processing');
      setErrorMessage('');

      // Check for error parameters in the URL hash or query params
      const searchError = searchParams.get('error') || searchParams.get('error_description');
      const hashParams = new URLSearchParams(window.location.hash.replace(/^#/, ''));
      const hashError = hashParams.get('error') || hashParams.get('error_description');

      if (searchError || hashError) {
        setErrorMessage(
          hashParams.get('error_description') ||
          searchParams.get('error_description') ||
          'The invitation link is invalid or has expired.'
        );
        setPageState('invalid');
        return;
      }

      // Check for PKCE code in query parameters if session is not yet active
      const codeParam = searchParams.get('code');
      if (codeParam && !session) {
        const { error: exchangeError } = await supabase.auth.exchangeCodeForSession(codeParam);
        if (exchangeError) {
          setErrorMessage('Could not establish a secure session from the invitation link. Please request a new invite.');
          setPageState('invalid');
          return;
        }
      }

      // If still loading auth, wait
      if (authLoading) {
        return;
      }

      // Check if user is authenticated
      const { data: { session: activeSession } } = await supabase.auth.getSession();
      if (!activeSession || !activeSession.user) {
        if (invitationIdParam) {
          setPageState('unauthenticated');
        } else {
          setErrorMessage('No active session found. Please sign in or use the invitation link from your email.');
          setPageState('unauthenticated');
        }
        return;
      }

      // User is authenticated. Fetch invitation details.
      const invDetails = await fetchInvitationDetails(invitationIdParam);
      setDetails(invDetails);

      if (invDetails.status === 'already_accepted') {
        setPageState('already_accepted');
        return;
      }

      if (invDetails.is_expired || invDetails.status === 'expired') {
        setPageState('expired');
        return;
      }

      if (invDetails.status === 'cancelled' || invDetails.status === 'failed') {
        setErrorMessage(`This invitation is no longer valid (${invDetails.status}).`);
        setPageState('invalid');
        return;
      }

      if (!invDetails.can_accept) {
        setErrorMessage(invDetails.unusable_reason || 'This invitation cannot be accepted at this time.');
        setPageState('unusable');
        return;
      }

      // If user came via invite email and hasn't set a password yet, offer password setup
      // We check if this is a newly invited account (status === 'sent')
      if (invDetails.status === 'sent' && !passwordSet) {
        setPageState('password_setup');
      } else {
        setPageState('ready');
      }
    } catch (err) {
      const normalized = normalizeError(err);
      if (
        normalized.code === 'P0002' ||
        normalized.technicalMessage?.includes('No invitation found') ||
        normalized.technicalMessage?.includes('Invitation not found')
      ) {
        setErrorMessage('No active invitation was found for your account. Please verify your invitation link or contact your organization administrator.');
        setPageState('invalid');
      } else {
        setErrorMessage(normalized.message);
        setPageState('error');
      }
    }
  }, [authLoading, invitationIdParam, passwordSet, searchParams, session]);

  useEffect(() => {
    loadInvitation();
  }, [loadInvitation]);

  // Handle password setup submission
  const handlePasswordSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setPasswordError('');

    if (password.length < 8) {
      setPasswordError('Password must be at least 8 characters in length.');
      return;
    }

    if (password !== confirmPassword) {
      setPasswordError('Passwords do not match. Please re-enter.');
      return;
    }

    setIsSettingPassword(true);
    try {
      const { error } = await supabase.auth.updateUser({ password });
      if (error) throw error;
      setPasswordSet(true);
      setPageState('ready');
    } catch (err) {
      const normalized = normalizeError(err);
      // Display calm human-readable error message without raw Auth error internals
      setPasswordError(
        normalized.message || 'Unable to update password. Please ensure it meets security requirements and try again.'
      );
    } finally {
      setIsSettingPassword(false);
    }
  };

  // Handle invitation acceptance
  const handleAccept = async () => {
    if (!details) return;

    // Enforce mandatory password setup for newly invited accounts (status === 'sent')
    if (details.status === 'sent' && !passwordSet) {
      setPageState('password_setup');
      setPasswordError('Please establish a password for your account before completing acceptance.');
      return;
    }

    setPageState('accepting');
    setErrorMessage('');

    try {
      const result = await acceptMemberAccountInvitation(details.invitation_id);
      
      // Deterministically set active organization first
      if (result.organization_id) {
        setActiveOrganizationId(result.organization_id);
      }

      // Explicitly invalidate and refetch all relevant authorization and member context queries
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: identityKeys.profileContext }),
        queryClient.invalidateQueries({ queryKey: authorizationKeys.all }),
        queryClient.invalidateQueries({ queryKey: authorizationKeys.context(result.organization_id) }),
        queryClient.invalidateQueries({ queryKey: selfServiceKeys.all }),
        queryClient.invalidateQueries({ queryKey: selfServiceKeys.context(result.organization_id) }),
        queryClient.invalidateQueries({ queryKey: selfServiceKeys.profile(result.organization_id) }),
        queryClient.invalidateQueries({ queryKey: ['my-pending-account-invitations'] }),
      ]);

      setPageState('success');

      // Auto-navigate after brief pause for confirmation
      setTimeout(() => {
        navigate('/app/dashboard', { replace: true });
      }, 1500);
    } catch (err) {
      const normalized = normalizeError(err);
      setErrorMessage(normalized.message);
      setPageState('error');
    }
  };

  return (
    <div className="flex min-h-screen items-center justify-center bg-canvas px-4 py-10">
      <Card className="w-full max-w-md" padding="comfortable">
        <div className="mb-6 text-center">
          <p className="text-small font-semibold tracking-wide text-secondary uppercase">MissionOS</p>
          <h1 className="mt-1 text-page-title font-semibold text-ink">Invitation Acceptance</h1>
        </div>

        {/* STATE: PROCESSING */}
        {pageState === 'processing' && (
          <div className="flex flex-col items-center justify-center py-8 text-center">
            <Loader2 className="h-8 w-8 animate-spin text-primary" />
            <p className="mt-4 text-small text-ink-secondary">Verifying your invitation details…</p>
          </div>
        )}

        {/* STATE: UNAUTHENTICATED */}
        {pageState === 'unauthenticated' && (
          <div className="space-y-4">
            <Alert variant="info">
              Please sign in to accept your MissionOS account invitation.
            </Alert>
            <p className="text-small text-ink-secondary">
              If this invitation was sent to an existing account, sign in with your credentials to link your membership.
            </p>
            <Button
              size="lg"
              className="w-full"
              onClick={() => {
                const target = invitationIdParam
                  ? `/login?returnTo=${encodeURIComponent(`/invite/accept?invitation=${invitationIdParam}`)}`
                  : '/login';
                navigate(target);
              }}
            >
              Sign In to Continue
            </Button>
          </div>
        )}

        {/* STATE: PASSWORD SETUP */}
        {pageState === 'password_setup' && (
          <div className="space-y-4">
            <div className="rounded-md bg-canvas-subtle p-3 text-small text-ink-secondary">
              Welcome, <span className="font-semibold text-ink">{details?.member_name}</span>. Please choose a secure password to complete your account activation.
            </div>

            {passwordError && (
              <Alert variant="danger">
                {passwordError}
              </Alert>
            )}

            <form onSubmit={handlePasswordSubmit} className="space-y-4">
              <FormField label="New Password" required hint="Minimum 8 characters">
                <Input
                  type="password"
                  autoComplete="new-password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  disabled={isSettingPassword}
                />
              </FormField>
              <FormField label="Confirm Password" required>
                <Input
                  type="password"
                  autoComplete="new-password"
                  value={confirmPassword}
                  onChange={(e) => setConfirmPassword(e.target.value)}
                  disabled={isSettingPassword}
                />
              </FormField>
              <div className="pt-2">
                <Button type="submit" size="lg" className="w-full" loading={isSettingPassword}>
                  {isSettingPassword ? 'Saving Password…' : 'Save Password & Continue'}
                </Button>
              </div>
            </form>
          </div>
        )}

        {/* STATE: READY TO ACCEPT */}
        {pageState === 'ready' && details && (
          <div className="space-y-5">
            <div className="rounded-lg border border-border bg-canvas-subtle p-4">
              <p className="text-caption text-ink-muted uppercase">Organization</p>
              <p className="text-body font-semibold text-ink">{details.organization_name}</p>

              <div className="mt-3 border-t border-border pt-3">
                <p className="text-caption text-ink-muted uppercase">Member</p>
                <p className="text-body font-semibold text-ink">{details.member_name}</p>
                <p className="text-caption text-ink-secondary">{details.email}</p>
              </div>
            </div>

            <p className="text-small text-ink-secondary">
              Accepting this invitation will activate your member access to MissionOS and link your account to your member profile.
            </p>

            <Button
              size="lg"
              className="w-full"
              onClick={handleAccept}
            >
              Accept Invitation
            </Button>
          </div>
        )}

        {/* STATE: ACCEPTING */}
        {pageState === 'accepting' && (
          <div className="flex flex-col items-center justify-center py-8 text-center">
            <Loader2 className="h-8 w-8 animate-spin text-primary" />
            <p className="mt-4 text-small font-medium text-ink">Activating your account and membership…</p>
            <p className="mt-1 text-caption text-ink-secondary">Setting up your profile and self-service access.</p>
          </div>
        )}

        {/* STATE: SUCCESS */}
        {pageState === 'success' && (
          <div className="flex flex-col items-center justify-center py-6 text-center">
            <div className="flex h-12 w-12 items-center justify-center rounded-full bg-emerald-100 text-emerald-600 dark:bg-emerald-950/50 dark:text-emerald-400">
              <CheckCircle2 className="h-6 w-6" />
            </div>
            <h2 className="mt-4 text-section-title font-semibold text-ink">Welcome to MissionOS!</h2>
            <p className="mt-2 text-small text-ink-secondary">
              Your invitation has been accepted. You are now connected to <span className="font-semibold text-ink">{details?.organization_name}</span>.
            </p>
            <Button
              size="lg"
              className="mt-6 w-full"
              onClick={() => navigate('/app/dashboard', { replace: true })}
            >
              Go to Dashboard
            </Button>
          </div>
        )}

        {/* STATE: ALREADY ACCEPTED */}
        {pageState === 'already_accepted' && (
          <div className="space-y-4 text-center">
            <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-blue-100 text-blue-600 dark:bg-blue-950/50 dark:text-blue-400">
              <CheckCircle2 className="h-6 w-6" />
            </div>
            <h2 className="text-section-title font-semibold text-ink">Already Accepted</h2>
            <p className="text-small text-ink-secondary">
              This invitation has already been accepted and your account is active.
            </p>
            <Button
              size="lg"
              className="w-full"
              onClick={() => navigate('/app/dashboard', { replace: true })}
            >
              Go to Dashboard
            </Button>
          </div>
        )}

        {/* STATE: EXPIRED */}
        {pageState === 'expired' && (
          <div className="space-y-4 text-center">
            <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-amber-100 text-amber-600 dark:bg-amber-950/50 dark:text-amber-400">
              <AlertTriangle className="h-6 w-6" />
            </div>
            <h2 className="text-section-title font-semibold text-ink">Invitation Expired</h2>
            <p className="text-small text-ink-secondary">
              This invitation has expired. Please contact your organization administrator to receive a new invitation.
            </p>
            <Link to="/login" className="inline-block text-small font-medium text-primary hover:underline">
              Return to Sign In
            </Link>
          </div>
        )}

        {/* STATE: UNUSABLE */}
        {pageState === 'unusable' && (
          <div className="space-y-4 text-center">
            <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-amber-100 text-amber-600 dark:bg-amber-950/50 dark:text-amber-400">
              <AlertTriangle className="h-6 w-6" />
            </div>
            <h2 className="text-section-title font-semibold text-ink">Account Status Notice</h2>
            <p className="text-small text-ink-secondary">
              {errorMessage || 'Your account cannot accept invitations at this time. Please contact your administrator.'}
            </p>
            <Link to="/login" className="inline-block text-small font-medium text-primary hover:underline">
              Return to Sign In
            </Link>
          </div>
        )}

        {/* STATE: INVALID OR GENERIC ERROR */}
        {(pageState === 'invalid' || pageState === 'error') && (
          <div className="space-y-4 text-center">
            <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-red-100 text-red-600 dark:bg-red-950/50 dark:text-red-400">
              <XCircle className="h-6 w-6" />
            </div>
            <h2 className="text-section-title font-semibold text-ink">Invitation Problem</h2>
            <p className="text-small text-ink-secondary">
              {errorMessage || 'We were unable to process this invitation. Please check the link or contact your administrator.'}
            </p>
            <div className="flex flex-col gap-2 pt-2">
              <Button
                variant="outline"
                size="md"
                onClick={loadInvitation}
              >
                Try Again
              </Button>
              <Link to="/login" className="text-small font-medium text-primary hover:underline">
                Return to Sign In
              </Link>
            </div>
          </div>
        )}
      </Card>
    </div>
  );
}
