// Advance payment by Zelle / PayPal (Pass 9.29, Ron 2026-10-21): payment details (organization default + per-event
// override), member-reported payments awaiting the treasurer's confirmation.
// Pass 9.30 (Ron 2026-10-21): check and cash — reported as given, or "I'll pay at the event"; check instructions.
import { useQuery } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase/client';
import { paymentKeys } from './payments';

export interface PaymentDetailsFields {
  zelle_recipient: string | null;
  zelle_name: string | null;
  paypal_link: string | null;
  payment_note: string | null;
  check_payable_to: string | null;
  check_mailing_address: string | null;
  cash_check_note: string | null;
}

export interface PaymentDetails extends PaymentDetailsFields {
  organization: PaymentDetailsFields;
  event: PaymentDetailsFields | null;
  can_edit_organization: boolean;
  can_edit_event: boolean;
}

export type ReportStatus = 'pending' | 'confirmed' | 'declined';
export type ReportMethod = 'zelle' | 'paypal' | 'check' | 'cash';
/** sent = already paid (awaiting confirmation); at_event = will pay by cash / check at the event. */
export type ReportKind = 'sent' | 'at_event';

export interface MyPaymentReport {
  report_id: string;
  event_id: string;
  amount: number;
  payment_method: ReportMethod;
  reference: string | null;
  report_status: ReportStatus;
  reported_at: string;
  decline_reason: string | null;
  report_kind: ReportKind;
}

export interface EventPaymentReport extends Omit<MyPaymentReport, 'event_id'> {
  member_id: string;
  display_name: string;
  member_number: string | null;
  reviewed_at: string | null;
}

export const REPORT_METHOD_LABELS: Record<ReportMethod, string> = {
  zelle: 'Zelle',
  paypal: 'PayPal',
  check: 'Check',
  cash: 'Cash',
};

/** PayPal.me links accept the amount at the end (https://paypal.me/name/25). Other links are used as given. */
export function paypalUrl(link: string, amount: number | null): string {
  const base = link.trim().replace(/\/+$/, '');
  if (amount && amount > 0 && /paypal\.me\/[^/]+$/i.test(base)) return `${base}/${amount.toFixed(2)}`;
  return base;
}

export function usePaymentDetails(orgId: string | null, eventId: string | null) {
  return useQuery<PaymentDetails>({
    queryKey: [...paymentKeys.all, 'details', orgId, eventId],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('get_payment_details', {
        p_organization_id: orgId!,
        p_event_id: eventId ?? undefined,
      });
      if (error) throw error;
      return data as unknown as PaymentDetails;
    },
    enabled: !!orgId,
  });
}

export async function setPaymentDetails(orgId: string, eventId: string | null, f: PaymentDetailsFields) {
  const { error } = await supabase.rpc('set_payment_details', {
    p_organization_id: orgId,
    p_event_id: eventId ?? undefined,
    p_zelle_recipient: f.zelle_recipient ?? undefined,
    p_zelle_name: f.zelle_name ?? undefined,
    p_paypal_link: f.paypal_link ?? undefined,
    p_payment_note: f.payment_note ?? undefined,
    p_check_payable_to: f.check_payable_to ?? undefined,
    p_check_mailing_address: f.check_mailing_address ?? undefined,
    p_cash_check_note: f.cash_check_note ?? undefined,
  });
  if (error) throw error;
}

export function useMyPaymentReports(orgId: string | null) {
  return useQuery<MyPaymentReport[]>({
    queryKey: [...paymentKeys.all, 'my-reports', orgId],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('list_my_payment_reports', { p_organization_id: orgId! });
      if (error) throw error;
      return (data as unknown as MyPaymentReport[]) ?? [];
    },
    enabled: !!orgId,
  });
}

export async function reportMyPayment(
  orgId: string,
  eventId: string,
  method: ReportMethod,
  amount: number,
  reference: string,
  kind: ReportKind = 'sent',
) {
  const { error } = await supabase.rpc('report_my_event_payment', {
    p_organization_id: orgId,
    p_event_id: eventId,
    p_payment_method: method,
    p_amount: amount,
    p_reference: reference.trim() || undefined,
    p_report_kind: kind,
  });
  if (error) throw error;
}

export async function withdrawMyPaymentReport(orgId: string, reportId: string) {
  const { error } = await supabase.rpc('withdraw_my_payment_report', { p_organization_id: orgId, p_report_id: reportId });
  if (error) throw error;
}

export function useEventPaymentReports(orgId: string | null, eventId: string | null, enabled: boolean) {
  return useQuery<EventPaymentReport[]>({
    queryKey: [...paymentKeys.all, 'reports', orgId, eventId],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('list_event_payment_reports', {
        p_organization_id: orgId!,
        p_event_id: eventId!,
      });
      if (error) throw error;
      return (data as unknown as EventPaymentReport[]) ?? [];
    },
    enabled: !!orgId && !!eventId && enabled,
  });
}

export async function reviewPaymentReport(orgId: string, reportId: string, confirm: boolean, reason?: string) {
  const { error } = await supabase.rpc('review_event_payment_report', {
    p_organization_id: orgId,
    p_report_id: reportId,
    p_confirm: confirm,
    p_decline_reason: reason?.trim() || undefined,
  });
  if (error) throw error;
}
