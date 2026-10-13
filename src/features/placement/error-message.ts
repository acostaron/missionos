import { normalizeError } from '../../lib/supabase/errors';

/**
 * Returns a clean, user-facing error message for placement operations.
 *
 * Rules:
 * - For business-rule errors (SQLSTATE 22023, 23505, P0001, P0002) show the server's message text.
 * - For 42501 show "You don't have permission to place members."
 * - Otherwise show the normalizer's friendly message.
 * - Never show SQL, constraint names, stack traces, or raw technicalMessage.
 */
export function getPlacementErrorMessage(error: unknown): string {
  const normalized = normalizeError(error);

  if (normalized.code === '42501') {
    return "You don't have permission to place members.";
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

/**
 * Returns a clean, user-facing error message for section change operations.
 */
export function getSectionChangeErrorMessage(error: unknown): string {
  const normalized = normalizeError(error);

  if (normalized.code === '42501') {
    return "You don't have permission to change member sections.";
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

/**
 * Converts a skip reason code from place_members_bulk or change_members_section_bulk into plain-words text.
 */
export function formatSkipReason(reason: string, serverMessage?: string): string {
  switch (reason) {
    case 'not_found':
      return 'Member not found';
    case 'record_not_active':
      return 'Record is archived';
    case 'deceased':
      return 'Marked as deceased';
    case 'already_in_target':
      return 'Already in this chapter/unit';
    case 'already_in_section':
      return 'Already in this section';
    case 'error':
      return serverMessage || 'Error processing request';
    default:
      return reason;
  }
}
