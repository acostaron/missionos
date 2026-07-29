import { AuthError } from '@supabase/supabase-js';

export type AppError = {
  code: string;
  message: string;
  technicalMessage?: string;
  isPermissionDenied: boolean;
  isAuthenticationError: boolean;
  isValidationError: boolean;
  retryable: boolean;
};

export function normalizeError(error: unknown): AppError {
  // Default fallback
  const normalized: AppError = {
    code: 'UNKNOWN_ERROR',
    message: 'An unexpected error occurred. Please try again.',
    isPermissionDenied: false,
    isAuthenticationError: false,
    isValidationError: false,
    retryable: true,
  };

  if (error instanceof AuthError) {
    normalized.code = error.name || 'AUTH_ERROR';
    normalized.technicalMessage = error.message;
    normalized.isAuthenticationError = true;

    // Map common auth messages
    if (error.message.includes('Invalid login credentials')) {
      normalized.message = 'The email or password you entered is incorrect.';
      normalized.code = '28000'; // Common auth code
    } else if (error.message.includes('session has expired') || error.message.includes('JWT')) {
      normalized.message = 'Your session has expired. Please sign in again.';
      normalized.code = 'SESSION_EXPIRED';
      normalized.retryable = false;
    } else {
      normalized.message = 'There was a problem signing you in. Please check your credentials.';
    }
    return normalized;
  }

  // Check for Supabase Postgrest errors (typically objects with a code and message)
  if (typeof error === 'object' && error !== null && 'code' in error && 'message' in error) {
    const pgError = error as { code: string; message: string; details?: string };
    normalized.code = pgError.code;
    normalized.technicalMessage = pgError.message;

    switch (pgError.code) {
      case '42501': // insufficient_privilege
        normalized.message = 'You do not have permission to view or modify this record.';
        normalized.isPermissionDenied = true;
        normalized.retryable = false;
        break;
      case '23505': // unique_violation
        normalized.message = 'A record with this information already exists.';
        normalized.isValidationError = true;
        break;
      case '23503': // foreign_key_violation
        normalized.message = 'This record refers to information that cannot be found or is not valid for this organization.';
        normalized.isValidationError = true;
        break;
      case '23514': // check_violation
        normalized.message = 'The information provided does not meet the required format or constraints.';
        normalized.isValidationError = true;
        break;
      case 'P0002': // no_data_found
        normalized.message = 'The requested information could not be found.';
        normalized.retryable = false;
        break;
      default:
        normalized.message = 'A database error occurred. Please try again or contact support if the issue persists.';
    }
    return normalized;
  }

  if (error instanceof Error) {
    normalized.technicalMessage = error.message;
    if (error.message.toLowerCase().includes('network') || error.message.toLowerCase().includes('fetch')) {
      normalized.message = 'A network error occurred. Please check your connection and try again.';
      normalized.code = 'NETWORK_ERROR';
    }
  }

  return normalized;
}
