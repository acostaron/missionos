// Event fees and payments (Pass 9.13, written by Claude 2026-10-16).
// Organizers and the Treasurer / Finance Coordinator set the fee and record Paid / Partial / Waived.
import { useQuery, type QueryClient } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase/client';

export type PaymentStatus = 'free' | 'waived' | 'paid' | 'partial' | 'unpaid';
export interface PaymentState {
  status: PaymentStatus;
  fee: number;
  paid: number;
  balance: number;
}

export const PAYMENT_METHODS = [
  { value: 'cash', label: 'Cash' },
  { value: 'check', label: 'Check' },
  { value: 'zelle', label: 'Zelle' },
  { value: 'card', label: 'Card' },
  { value: 'other', label: 'Other' },
] as const;
export type PaymentMethod = (typeof PAYMENT_METHODS)[number]['value'];

export const PAYMENT_STATUS_LABELS: Record<PaymentStatus, string> = {
  free: 'Free',
  waived: 'Waived',
  paid: 'Paid',
  partial: 'Partial',
  unpaid: 'Not paid',
};

export function money(n: number | string | null | undefined): string {
  const v = Number(n ?? 0);
  return v.toLocaleString('en-US', { style: 'currency', currency: 'USD' });
}

export interface EventPaymentRow {
  member_id: string;
  display_name: string;
  member_number: string | null;
  payment: PaymentState;
  payments: { payment_id: string; amount: number; payment_method: PaymentMethod; recorded_at: string }[];
}
export interface EventPaymentsResponse {
  fee_amount: number | null;
  totals: { paid: number; partial: number; waived: number; collected: number };
  members: EventPaymentRow[];
}
export interface PaymentSearchRow {
  member_id: string;
  display_name: string;
  member_number: string | null;
  payment: PaymentState;
}

export const paymentKeys = {
  all: ['events', 'payments'] as const,
  access: (orgId: string | null, eventId: string | null) => [...paymentKeys.all, 'access', orgId, eventId] as const,
  list: (orgId: string | null, eventId: string | null) => [...paymentKeys.all, 'list', orgId, eventId] as const,
  search: (orgId: string | null, eventId: string | null, q: string) => [...paymentKeys.all, 'search', orgId, eventId, q] as const,
};

export function useEventPaymentAccess(orgId: string | null, eventId: string | null) {
  return useQuery<{ fee_amount: number | null; can_manage_payments: boolean }>({
    queryKey: paymentKeys.access(orgId, eventId),
    queryFn: async () => {
      const { data, error } = await supabase.rpc('get_event_payment_access', {
        p_organization_id: orgId!,
        p_event_id: eventId!,
      });
      if (error) throw error;
      return data as unknown as { fee_amount: number | null; can_manage_payments: boolean };
    },
    enabled: !!orgId && !!eventId,
  });
}

export function useEventPayments(orgId: string | null, eventId: string | null, enabled: boolean) {
  return useQuery<EventPaymentsResponse>({
    queryKey: paymentKeys.list(orgId, eventId),
    queryFn: async () => {
      const { data, error } = await supabase.rpc('get_event_payments', {
        p_organization_id: orgId!,
        p_event_id: eventId!,
      });
      if (error) throw error;
      return data as unknown as EventPaymentsResponse;
    },
    enabled: !!orgId && !!eventId && enabled,
  });
}

export function usePaymentMemberSearch(orgId: string | null, eventId: string | null, q: string) {
  const query = q.trim();
  return useQuery<PaymentSearchRow[]>({
    queryKey: paymentKeys.search(orgId, eventId, query),
    queryFn: async () => {
      const { data, error } = await supabase.rpc('search_members_for_event_payment', {
        p_organization_id: orgId!,
        p_event_id: eventId!,
        p_query: query,
      });
      if (error) throw error;
      return (data ?? []) as unknown as PaymentSearchRow[];
    },
    enabled: !!orgId && !!eventId && query.length >= 2,
    staleTime: 10_000,
  });
}

export async function setEventFee(orgId: string, eventId: string, fee: number | null) {
  const { error } = await supabase.rpc('set_event_fee', {
    p_organization_id: orgId,
    p_event_id: eventId,
    p_fee_amount: fee ?? undefined,
  });
  if (error) throw error;
}

export async function recordEventPayment(
  orgId: string,
  eventId: string,
  memberId: string,
  amount: number,
  method: PaymentMethod,
): Promise<PaymentState> {
  const { data, error } = await supabase.rpc('record_event_payment', {
    p_organization_id: orgId,
    p_event_id: eventId,
    p_member_id: memberId,
    p_amount: amount,
    p_payment_method: method,
  });
  if (error) throw error;
  return (data as unknown as { payment: PaymentState }).payment;
}

export async function voidEventPayment(orgId: string, paymentId: string) {
  const { error } = await supabase.rpc('void_event_payment', { p_organization_id: orgId, p_payment_id: paymentId });
  if (error) throw error;
}

export async function setFeeWaiver(orgId: string, eventId: string, memberId: string, waived: boolean) {
  const { error } = await supabase.rpc('set_event_fee_waiver', {
    p_organization_id: orgId,
    p_event_id: eventId,
    p_member_id: memberId,
    p_waived: waived,
  });
  if (error) throw error;
}

export async function invalidatePayments(qc: QueryClient) {
  await qc.invalidateQueries({ queryKey: paymentKeys.all });
}
