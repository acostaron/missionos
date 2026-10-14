import { normalizeError } from '../../lib/supabase/errors';

/**
 * Returns user-facing error message for event operations.
 *
 * Rules:
 * - For SQLSTATE 22023, 42501, P0002, 23505: show the RPC's message text.
 * - Otherwise show generic friendly text.
 */
export function getEventErrorMessage(error: unknown): string {
  const normalized = normalizeError(error);

  const rpcMessageCodes = new Set(['22023', '42501', 'P0002', '23505']);
  if (rpcMessageCodes.has(normalized.code)) {
    const rawMsg =
      typeof error === 'object' &&
      error !== null &&
      'message' in error &&
      typeof (error as { message: unknown }).message === 'string'
        ? (error as { message: string }).message
        : normalized.technicalMessage;

    if (rawMsg) {
      const leaksInternalDetails =
        rawMsg.includes('constraint "') ||
        rawMsg.includes('LINE ') ||
        rawMsg.includes('DETAIL:') ||
        rawMsg.includes('CONTEXT:');

      if (!leaksInternalDetails) {
        return rawMsg;
      }
    }
  }

  return normalized.message || 'An unexpected error occurred. Please try again.';
}
