import { useState } from 'react';
import { Navigate } from 'react-router-dom';
import { supabase } from '../lib/supabase/client';
import { normalizeError } from '../lib/supabase/errors';
import { useAuth } from '../hooks/use-auth';
import { Alert, Button, Card, FormField, Input } from '../components/ui';

export default function LoginPage() {
  const { user, isLoading: authLoading } = useAuth();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [errorMsg, setErrorMsg] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);

  // Redirect authenticated users away from /login
  if (!authLoading && user) {
    return <Navigate to="/app/dashboard" replace />;
  }

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMsg('');
    setIsSubmitting(true);

    try {
      const { error } = await supabase.auth.signInWithPassword({
        email,
        password,
      });

      if (error) {
        throw error;
      }

      // Successful login will trigger the onAuthStateChange in AuthProvider
      // which updates the user state, causing the Navigate above to trigger.
    } catch (error) {
      const normalized = normalizeError(error);
      setErrorMsg(normalized.message);
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="flex min-h-screen items-center justify-center bg-canvas px-4 py-10">
      <Card className="w-full max-w-md" padding="comfortable">
        <div className="mb-6 text-center">
          <p className="text-small font-semibold tracking-wide text-secondary uppercase">MissionOS</p>
          <h1 className="mt-1 text-page-title font-semibold text-ink">Sign in</h1>
          <p className="mt-1 text-small text-ink-secondary">Welcome back. Sign in to continue.</p>
        </div>

        {errorMsg && (
          <Alert variant="danger" className="mb-4">
            {errorMsg}
          </Alert>
        )}

        <form onSubmit={handleLogin} className="space-y-4">
          <FormField label="Email" required>
            <Input
              type="email"
              autoComplete="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              disabled={isSubmitting}
            />
          </FormField>
          <FormField label="Password" required>
            <Input
              type="password"
              autoComplete="current-password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              disabled={isSubmitting}
            />
          </FormField>
          <Button type="submit" size="lg" className="w-full" loading={isSubmitting}>
            {isSubmitting ? 'Signing in…' : 'Sign In'}
          </Button>
        </form>
      </Card>
    </div>
  );
}