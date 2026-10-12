import { normalizeError } from '../../lib/supabase/errors';

/**
 * Returns a clean, user-facing error message for section operations.
 *
 * Rules:
 * - For business-rule errors (SQLSTATE 22023, 23505, P0001, P0002) show the server's message text.
 * - For 42501 show "You don't have permission to do this."
 * - Otherwise show the normalizer's friendly message.
 * - Never show SQL, constraint names, stack traces, or raw technicalMessage.
 */
export function getSectionErrorMessage(error: unknown): string {
  const normalized = normalizeError(error);

  if (normalized.code === '42501') {
    return "You don't have permission to do this.";
  }

  const businessRuleCodes = new Set(['22023', '23505', 'P0001', 'P0002']);
  if (businessRuleCodes.has(normalized.code)) {
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
        rawMsg.includes('CONTEXT:') ||
        rawMsg.startsWith('duplicate key value violates');

      if (!leaksInternalDetails) {
        return rawMsg;
      }
    }
  }

  return normalized.message;
}
