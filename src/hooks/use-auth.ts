import { createContext, useContext } from 'react';
import type { Session, User } from '@supabase/supabase-js';
import type { AppError } from '../lib/supabase/errors';

export type AuthContextValue = {
  session: Session | null;
  user: User | null;
  isLoading: boolean;
  error: AppError | null;
  signOut: () => Promise<void>;
};

export const AuthContext = createContext<AuthContextValue | undefined>(undefined);

export function useAuth() {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
}

