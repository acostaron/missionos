import { useState, useEffect, useCallback } from 'react';
import { useNavigate, useSearchParams, Link } from 'react-router-dom';
import { supabase } from '../lib/supabase/client';
import { useAuth } from '../hooks/use-auth';
import { Alert, Button, Card, FormField, Input } from '../components/ui';

function reasonToMessage(reason?: string): string {
  switch (reason) {
    case 'too_many_attempts':
      return 'Too many wrong codes were tried. Please wait 15 minutes and try again.';
    case 'expired':
      return 'This code has expired. Ask your chapter servant for a new code.';
    case 'already_used':
      return 'This code was already used. If you cannot sign in, ask your chapter servant for help.';
    default:
      return 'This code is not valid. Check it and try again, or ask your chapter servant.';
  }
}

async function extractError(err: unknown): Promise<{ message: string; code?: string }> {
  if (!err) return { message: 'An unexpected error occurred.' };
  try {
    const context = (err as { context?: Response }).context;
    if (context && typeof context.json === 'function') {
      const body = await context.json();
      return {
        message: body.error || body.message || 'An error occurred.',
        code: body.code,
      };
    }
  } catch {
    // fallback
  }
  const errorObj = err as Error;
  return { message: errorObj.message || 'An unexpected error occurred.' };
}

export default function ClaimAccountPage() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const { user, isLoading: isAuthLoading } = useAuth();

  const codeParam = searchParams.get('code') || '';

  // Step 1 state
  const [code, setCode] = useState(codeParam);
  const [isChecking, setIsChecking] = useState(false);
  const [checkError, setCheckError] = useState('');
  const [maskedName, setMaskedName] = useState<string | null>(null);
  const [step, setStep] = useState<1 | 2>(1);

  // Step 2 state
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [isClaiming, setIsClaiming] = useState(false);
  const [claimError, setClaimError] = useState('');
  const [emailHasLogin, setEmailHasLogin] = useState(false);

  // Signed in linking state
  const [isLinking, setIsLinking] = useState(false);
  const [linkError, setLinkError] = useState('');

  const performCheck = useCallback(async (codeToCheck: string) => {
    const trimmed = codeToCheck.trim();
    if (!trimmed) {
      setCheckError('Please enter your code.');
      return;
    }
    setCheckError('');
    setIsChecking(true);
    setMaskedName(null);

    try {
      const { data, error } = await supabase.functions.invoke('claim-member-account', {
        body: { action: 'check', code: trimmed },
      });

      if (error) {
        const parsed = await extractError(error);
        setCheckError(parsed.message);
        return;
      }

      if (data && data.valid) {
        setMaskedName(data.masked_name);
      } else {
        setCheckError(reasonToMessage(data?.reason));
      }
    } catch (err) {
      const parsed = await extractError(err);
      setCheckError(parsed.message);
    } finally {
      setIsChecking(false);
    }
  }, []);

  // If code is in URL on mount, auto-check it
  useEffect(() => {
    if (codeParam) {
      performCheck(codeParam);
    }
  }, [codeParam, performCheck]);

  // Handle Step 1 submit
  const handleCheckSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    performCheck(code);
  };

  // Handle Step 2 submit (New login)
  const handleClaimSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setClaimError('');
    setEmailHasLogin(false);

    const trimmedEmail = email.trim().toLowerCase();
    if (!trimmedEmail) {
      setClaimError('Please enter your email.');
      return;
    }
    if (password.length < 8) {
      setClaimError('Password must be at least 8 characters.');
      return;
    }
    if (password !== confirmPassword) {
      setClaimError('Passwords do not match.');
      return;
    }

    setIsClaiming(true);

    try {
      const { error } = await supabase.functions.invoke('claim-member-account', {
        body: {
          action: 'claim',
          code: code.trim(),
          email: trimmedEmail,
          password,
        },
      });

      if (error) {
        const parsed = await extractError(error);
        if (parsed.code === 'email_has_login') {
          setEmailHasLogin(true);
        } else {
          setClaimError(parsed.message);
        }
        setIsClaiming(false);
        return;
      }

      // Claim succeeded -> Sign in
      const { error: signInErr } = await supabase.auth.signInWithPassword({
        email: trimmedEmail,
        password,
      });

      if (signInErr) {
        // Fallback to login page if immediate auto-sign-in fails
        navigate('/login', { state: { welcome: true } });
        return;
      }

      navigate('/app/profile', { state: { welcome: true } });
    } catch (err) {
      const parsed = await extractError(err);
      setClaimError(parsed.message);
      setIsClaiming(false);
    }
  };

  // Handle linking for already signed in user
  const handleLinkSignedIn = async () => {
    setIsLinking(true);
    setLinkError('');

    try {
      const { error } = await supabase.functions.invoke('claim-member-account', {
        body: {
          action: 'claim_signed_in',
          code: code.trim(),
        },
      });

      if (error) {
        const parsed = await extractError(error);
        setLinkError(parsed.message);
        setIsLinking(false);
        return;
      }

      navigate('/app/profile', { state: { welcome: true } });
    } catch (err) {
      const parsed = await extractError(err);
      setLinkError(parsed.message);
      setIsLinking(false);
    }
  };

  return (
    <div className="flex min-h-screen items-center justify-center bg-canvas px-4 py-10">
      <Card className="w-full max-w-md" padding="comfortable">
        <div className="mb-6 text-center">
          <p className="text-small font-semibold tracking-wide text-secondary uppercase">MissionOS</p>
          <h1 className="mt-1 text-page-title font-semibold text-ink">Member Portal</h1>
          <p className="mt-1 text-small text-ink-secondary">
            Claim your personal member account using your one-time code.
          </p>
        </div>

        {/* --- Step 1: Enter your code --- */}
        {step === 1 && (
          <div className="space-y-4">
            {checkError && (
              <Alert variant="danger" className="mb-4">
                {checkError}
              </Alert>
            )}

            {!maskedName ? (
              <form onSubmit={handleCheckSubmit} className="space-y-4">
                <FormField
                  label="Enter your code"
                  hint="Accepts letters, numbers, spaces, or dashes (e.g. MFC-ABCD-2345)"
                  required
                >
                  <Input
                    type="text"
                    value={code}
                    onChange={(e) => setCode(e.target.value)}
                    placeholder="MFC-XXXX-XXXX"
                    disabled={isChecking}
                    className="font-mono uppercase tracking-wider"
                    autoFocus
                  />
                </FormField>
                <Button type="submit" size="lg" className="w-full" loading={isChecking}>
                  {isChecking ? 'Checking code…' : 'Continue'}
                </Button>
              </form>
            ) : (
              <div className="space-y-5">
                <div className="rounded-lg border border-line bg-surface-muted p-4 text-center">
                  <p className="text-small text-ink-secondary">This code is for</p>
                  <p className="mt-1 text-lg font-bold text-ink">{maskedName}</p>
                  <p className="mt-2 text-sm font-medium text-ink">Is this you?</p>
                </div>

                {linkError && (
                  <Alert variant="danger">
                    {linkError}
                  </Alert>
                )}

                {user && !isAuthLoading ? (
                  <div className="space-y-3">
                    <p className="text-xs text-ink-muted text-center">
                      You are currently signed in as <span className="font-semibold">{user.email}</span>.
                    </p>
                    <Button
                      type="button"
                      size="lg"
                      className="w-full"
                      onClick={handleLinkSignedIn}
                      loading={isLinking}
                    >
                      Link my login
                    </Button>
                    <div className="flex justify-between text-xs text-ink-muted pt-1">
                      <button
                        type="button"
                        onClick={() => {
                          setMaskedName(null);
                          setCode('');
                        }}
                        className="hover:text-ink underline"
                      >
                        Try a different code
                      </button>
                      <button
                        type="button"
                        onClick={async () => {
                          await supabase.auth.signOut();
                          window.location.reload();
                        }}
                        className="hover:text-ink underline"
                      >
                        Sign out
                      </button>
                    </div>
                  </div>
                ) : (
                  <div className="space-y-3">
                    <Button
                      type="button"
                      size="lg"
                      className="w-full"
                      onClick={() => setStep(2)}
                    >
                      Continue
                    </Button>
                    <div className="text-center">
                      <button
                        type="button"
                        onClick={() => {
                          setMaskedName(null);
                        }}
                        className="text-xs text-ink-muted hover:text-ink underline"
                      >
                        Not you? Enter a different code
                      </button>
                    </div>
                  </div>
                )}
              </div>
            )}

            <div className="mt-6 border-t border-line pt-4 text-center">
              <p className="text-small text-ink-secondary">
                Already have a password?{' '}
                <Link to="/login" className="font-medium text-primary hover:underline">
                  Sign in
                </Link>
              </p>
            </div>
          </div>
        )}

        {/* --- Step 2: Create your login --- */}
        {step === 2 && (
          <div className="space-y-4">
            <div className="rounded-lg border border-line bg-surface-muted px-4 py-3 flex items-center justify-between">
              <div>
                <p className="text-xs text-ink-muted">Account for</p>
                <p className="text-sm font-semibold text-ink">{maskedName}</p>
              </div>
              <button
                type="button"
                onClick={() => setStep(1)}
                className="text-xs text-primary hover:underline font-medium"
              >
                Change code
              </button>
            </div>

            {claimError && (
              <Alert variant="danger">
                {claimError}
              </Alert>
            )}

            {emailHasLogin ? (
              <div className="space-y-4 rounded-lg border border-warning-200 bg-warning-50 p-4 text-center">
                <p className="text-sm font-medium text-warning-800">
                  This email already has a login
                </p>
                <p className="text-xs text-warning-700">
                  You already have an existing MissionOS account with this email. Sign in to link your personal claim code to it.
                </p>
                <Link
                  to={`/login?next=${encodeURIComponent(`/claim?code=${code.trim()}`)}`}
                  className="inline-flex w-full items-center justify-center rounded-control bg-primary px-4 py-2 text-sm font-medium text-white hover:bg-primary-hover shadow-sm"
                >
                  Sign in and use my code
                </Link>
              </div>
            ) : (
              <form onSubmit={handleClaimSubmit} className="space-y-4">
                <FormField label="Email" hint="This will become your sign-in email" required>
                  <Input
                    type="email"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    disabled={isClaiming}
                    required
                    autoComplete="email"
                  />
                </FormField>

                <FormField label="Password" hint="At least 8 characters" required>
                  <Input
                    type="password"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    disabled={isClaiming}
                    required
                    minLength={8}
                    autoComplete="new-password"
                  />
                </FormField>

                <FormField label="Confirm password" required>
                  <Input
                    type="password"
                    value={confirmPassword}
                    onChange={(e) => setConfirmPassword(e.target.value)}
                    disabled={isClaiming}
                    required
                    minLength={8}
                    autoComplete="new-password"
                  />
                </FormField>

                <Button type="submit" size="lg" className="w-full" loading={isClaiming}>
                  {isClaiming ? 'Creating login…' : 'Create login'}
                </Button>
              </form>
            )}
          </div>
        )}
      </Card>
    </div>
  );
}
