import { useEffect, useState } from 'react';
import { OrganizationProvider } from './organization-context';
import type { ReactNode } from 'react';
import type { Session, User } from '@supabase/supabase-js';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { supabase } from '../lib/supabase/client';
import { normalizeError } from '../lib/supabase/errors';
import type { AppError } from '../lib/supabase/errors';
import { AuthContext } from '../hooks/use-auth';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: 1,
      refetchOnWindowFocus: false,
    },
  },
});

export function AppProviders({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [user, setUser] = useState<User | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<AppError | null>(null);

  useEffect(() => {
    let mounted = true;

    async function getInitialSession() {
      try {
        const { data: { session }, error } = await supabase.auth.getSession();
        if (error) throw error;
        
        if (mounted) {
          setSession(session);
          setUser(session?.user ?? null);
        }
      } catch (e) {
        if (mounted) {
          setError(normalizeError(e));
        }
      } finally {
        if (mounted) {
          setIsLoading(false);
        }
      }
    }

    getInitialSession();

    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, newSession) => {
      if (mounted) {
        setSession(newSession);
        setUser(newSession?.user ?? null);
        setIsLoading(false);
      }
    });

    return () => {
      mounted = false;
      subscription.unsubscribe();
    };
  }, []);

  const signOut = async () => {
    try {
      const { error } = await supabase.auth.signOut();
      if (error) throw error;
    } catch (e) {
      setError(normalizeError(e));
    }
  };

  const value = {
    session,
    user,
    isLoading,
    error,
    signOut,
  };

  return (
    <QueryClientProvider client={queryClient}>
      <AuthContext.Provider value={value}>
        <OrganizationProvider>
          {children}
        </OrganizationProvider>
      </AuthContext.Provider>
    </QueryClientProvider>
  );
}

