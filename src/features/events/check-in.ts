// QR check-in at the event desk (Pass 9.12, written by Claude 2026-10-16).
import { useQuery } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase/client';
import type { PaymentState } from './payments';

export interface CheckInMember {
  member_id: string;
  display_name: string;
  member_number: string | null;
  photo_path: string | null;
}

export type ScanResult =
  | {
      result: 'checked_in';
      member: CheckInMember;
      checked_in_at: string;
      first_check_in: boolean;
      kit_given_at: string | null;
      multi_day: boolean;
      payment?: PaymentState;
    }
  | { result: 'payment_required'; member: CheckInMember; payment: PaymentState; can_record_payment: boolean }
  | { result: 'already_checked_in'; member: CheckInMember; checked_in_at: string; kit_given_at: string | null }
  | { result: 'invalid'; reason: string; member: CheckInMember | null };

export interface CheckInSummary {
  today: string;
  first_day: string;
  last_day: string;
  event_status: string;
  checked_in_today: number;
  attended_total: number;
  recent: { member_id: string; display_name: string; member_number: string | null; recorded_at: string }[];
}

export const INVALID_REASONS: Record<string, string> = {
  not_a_member_qr: 'This is not a MissionOS member QR code.',
  unknown_qr: 'This QR code is not on file.',
  number_changed: 'This is an old card — the member number has changed. Ask the member to open My Card.',
  tampered: 'This QR code could not be verified.',
  replaced_or_revoked: 'This card was replaced or cancelled. Ask the member to open My Card.',
  member_not_active: 'This member record is not active.',
};

export const checkInKeys = {
  summary: (orgId: string | null, eventId: string | null) => ['events', 'check-in', orgId, eventId] as const,
};

export function useCheckInSummary(orgId: string | null, eventId: string | null) {
  return useQuery<CheckInSummary>({
    queryKey: checkInKeys.summary(orgId, eventId),
    queryFn: async () => {
      const { data, error } = await supabase.rpc('get_event_check_in_summary', {
        p_organization_id: orgId!,
        p_event_id: eventId!,
      });
      if (error) throw error;
      return data as unknown as CheckInSummary;
    },
    enabled: !!orgId && !!eventId,
    refetchInterval: 20_000,
  });
}

export async function scanCheckIn(orgId: string, eventId: string, payload: string): Promise<ScanResult> {
  const { data, error } = await supabase.rpc('scan_event_check_in', {
    p_organization_id: orgId,
    p_event_id: eventId,
    p_payload: payload,
  });
  if (error) throw error;
  return data as unknown as ScanResult;
}
