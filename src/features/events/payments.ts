// Event fees, registrations and payments (Pass 9.13 / 9.14, written by Claude 2026-10-16).
// Pass 9.32 (Ron 2026-10-21): shown to people as donations; child (under 18) rate.
// Organizers and the Treasurer / Finance Coordinator set prices (early-bird, regular, walk-in), register members
// and record Paid / Partial / Waived. Members can register themselves in My Events when registration is open.
import { useQuery, type QueryClient } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase/client';

export type PaymentStatus = 'free' | 'waived' | 'paid' | 'partial' | 'unpaid' | 'not_registered';
export type PriceTier = 'free' | 'early_bird' | 'regular' | 'walk_in' | 'child';
export interface PaymentState {
  status: PaymentStatus;
  /** amount due for this member (registration price), or today's price when not registered */
  fee: number;
  paid: number;
  balance: number;
  registered?: boolean;
  registration_type?: 'reserved' | 'walk_in' | null;
  price_tier?: PriceTier;
  walk_in_fee?: number;
  registered_at?: string;
}

export const PRICE_TIER_LABELS: Record<PriceTier, string> = {
  free: 'Free',
  early_bird: 'Early-bird',
  regular: 'Regular',
  walk_in: 'Walk-in',
  child: 'Child (under 18)',
};

export interface EventPricing {
  fee_amount: number | null;
  early_bird_fee: number | null;
  early_bird_until: string | null;
  walk_in_fee: number | null;
  registration_open: boolean;
  /** Pass 9.32: fixed child (under 18) donation; null = no child rate */
  child_fee: number | null;
}

export const PAYMENT_METHODS = [
  { value: 'cash', label: 'Cash' },
  { value: 'check', label: 'Check' },
  { value: 'zelle', label: 'Zelle' },
  { value: 'paypal', label: 'PayPal' },
  { value: 'card', label: 'Card' },
  { value: 'other', label: 'Other' },
] as const;
export type PaymentMethod = (typeof PAYMENT_METHODS)[number]['value'];

export const PAYMENT_STATUS_LABELS: Record<PaymentStatus, string> = {
  free: 'Free',
  waived: 'Waived',
  paid: 'Donated',
  partial: 'Partial',
  unpaid: 'Not yet donated',
  not_registered: 'Not registered',
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
export interface EventPaymentsResponse extends EventPricing {
  totals: {
    registered: number;
    reserved: number;
    walk_in: number;
    checked_in: number;
    paid: number;
    partial: number;
    unpaid: number;
    waived: number;
    expected: number;
    collected: number;
  };
  members: (EventPaymentRow & { checked_in: boolean })[];
}
export interface PaymentSearchRow {
  member_id: string;
  display_name: string;
  member_number: string | null;
  payment: PaymentState;
}

export interface PaymentAccess extends Partial<EventPricing> {
  fee_amount: number | null;
  can_manage_payments: boolean;
  /** false on paid events for anyone but the organizers and administrators (use Scan QR instead) */
  can_tick_attendance?: boolean;
}

export const paymentKeys = {
  all: ['events', 'payments'] as const,
  access: (orgId: string | null, eventId: string | null) => [...paymentKeys.all, 'access', orgId, eventId] as const,
  list: (orgId: string | null, eventId: string | null) => [...paymentKeys.all, 'list', orgId, eventId] as const,
  search: (orgId: string | null, eventId: string | null, q: string) => [...paymentKeys.all, 'search', orgId, eventId, q] as const,
};

export function useEventPaymentAccess(orgId: string | null, eventId: string | null) {
  return useQuery<PaymentAccess>({
    queryKey: paymentKeys.access(orgId, eventId),
    queryFn: async () => {
      const { data, error } = await supabase.rpc('get_event_payment_access', {
        p_organization_id: orgId!,
        p_event_id: eventId!,
      });
      if (error) throw error;
      return data as unknown as PaymentAccess;
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

export async function setEventPricing(orgId: string, eventId: string, p: EventPricing) {
  const { error } = await supabase.rpc('set_event_pricing', {
    p_organization_id: orgId,
    p_event_id: eventId,
    p_fee_amount: p.fee_amount ?? undefined,
    p_early_bird_fee: p.early_bird_fee ?? undefined,
    p_early_bird_until: p.early_bird_until ?? undefined,
    p_walk_in_fee: p.walk_in_fee ?? undefined,
    p_registration_open: p.registration_open,
    p_child_fee: p.child_fee ?? undefined,
  });
  if (error) throw error;
}

/** memberId null = register myself (My Events) */
export async function registerForEvent(orgId: string, eventId: string, memberId: string | null, walkIn = false) {
  const { data, error } = await supabase.rpc('register_for_event', {
    p_organization_id: orgId,
    p_event_id: eventId,
    p_member_id: memberId ?? undefined,
    p_walk_in: walkIn,
  });
  if (error) throw error;
  return data as unknown as { registration_id: string; already_registered: boolean; payment: PaymentState };
}

/** memberId null = cancel my own registration */
export async function cancelEventRegistration(orgId: string, eventId: string, memberId: string | null) {
  const { error } = await supabase.rpc('cancel_event_registration', {
    p_organization_id: orgId,
    p_event_id: eventId,
    p_member_id: memberId ?? undefined,
  });
  if (error) throw error;
}

export interface MyEventRegistration extends EventPricing {
  event_id: string;
  title: string;
  event_type: string;
  starts_at: string;
  ends_at: string | null;
  location_text: string | null;
  price_now: { tier: PriceTier; amount: number };
  my: PaymentState;
  checked_in: boolean;
}

export function useMyEventRegistrations(orgId: string | null) {
  return useQuery<MyEventRegistration[]>({
    queryKey: [...paymentKeys.all, 'mine', orgId],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('list_my_event_registrations', { p_organization_id: orgId! });
      if (error) throw error;
      return (data ?? []) as unknown as MyEventRegistration[];
    },
    enabled: !!orgId,
    staleTime: 30_000,
  });
}

// ---------------------------------------------------------------------------------------------------------------
// Guests (non-members), Pass 9.15 (Claude 2026-10-16). Recorded by name (+ optional phone / email) under the member
// who brings them; organizers can also add guests with or without a host. Guests show an on-screen guest pass.
// ---------------------------------------------------------------------------------------------------------------
export type GuestPriceTier = PriceTier | 'guest';
export interface GuestPaymentState {
  status: Exclude<PaymentStatus, 'not_registered'>;
  fee: number;
  paid: number;
  balance: number;
  registration_type: 'reserved' | 'walk_in';
  price_tier: GuestPriceTier;
}
export interface EventGuest {
  guest_id: string;
  event_id: string;
  first_name: string;
  last_name: string;
  display_name: string;
  phone: string | null;
  email: string | null;
  host_member_id: string | null;
  host_name: string | null;
  guest_code: string;
  is_child?: boolean;
  registered_at: string;
  payment: GuestPaymentState;
  checked_in_today: boolean;
  checked_in_ever: boolean;
  payments?: { payment_id: string; amount: number; payment_method: PaymentMethod; recorded_at: string }[];
}
export interface EventGuestsResponse {
  guest_fee: number | null;
  child_fee?: number | null;
  guest_price_now: { tier: GuestPriceTier; amount: number };
  guest_walk_in_price: { tier: GuestPriceTier; amount: number };
  can_manage: boolean;
  guests: EventGuest[];
}
export interface GuestFields {
  firstName: string;
  lastName: string;
  phone: string;
  email: string;
  /** Pass 9.32: child (under 18) gets the event's child rate */
  isChild?: boolean;
}

export const GUEST_PASS_PREFIX = 'MFCNYG1:';
export const guestPassPayload = (code: string) => `${GUEST_PASS_PREFIX}${code}`;

export function useEventGuests(orgId: string | null, eventId: string | null, enabled: boolean) {
  return useQuery<EventGuestsResponse>({
    queryKey: [...paymentKeys.all, 'guests', orgId, eventId],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('get_event_guests', { p_organization_id: orgId!, p_event_id: eventId! });
      if (error) throw error;
      return data as unknown as EventGuestsResponse;
    },
    enabled: !!orgId && !!eventId && enabled,
  });
}

export function useMyEventGuests(orgId: string | null) {
  return useQuery<EventGuest[]>({
    queryKey: [...paymentKeys.all, 'my-guests', orgId],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('list_my_event_guests', { p_organization_id: orgId! });
      if (error) throw error;
      return (data ?? []) as unknown as EventGuest[];
    },
    enabled: !!orgId,
    staleTime: 30_000,
  });
}

/** asStaff false = I am adding my own guest (My Events). */
export async function addEventGuest(
  orgId: string,
  eventId: string,
  f: GuestFields,
  opts: { asStaff: boolean; hostMemberId?: string | null; walkIn?: boolean },
) {
  const { data, error } = await supabase.rpc('add_event_guest', {
    p_organization_id: orgId,
    p_event_id: eventId,
    p_first_name: f.firstName.trim(),
    p_last_name: f.lastName.trim(),
    p_phone: f.phone.trim() || undefined,
    p_email: f.email.trim() || undefined,
    p_as_staff: opts.asStaff,
    p_host_member_id: opts.hostMemberId ?? undefined,
    p_walk_in: !!opts.walkIn,
    p_is_child: !!f.isChild,
  });
  if (error) throw error;
  return data as unknown as EventGuest;
}

export async function cancelEventGuest(orgId: string, guestId: string) {
  const { error } = await supabase.rpc('cancel_event_guest', { p_organization_id: orgId, p_guest_id: guestId });
  if (error) throw error;
}

export async function recordEventGuestPayment(orgId: string, guestId: string, amount: number, method: PaymentMethod) {
  const { error } = await supabase.rpc('record_event_guest_payment', {
    p_organization_id: orgId,
    p_guest_id: guestId,
    p_amount: amount,
    p_payment_method: method,
  });
  if (error) throw error;
}

export async function voidEventGuestPayment(orgId: string, paymentId: string) {
  const { error } = await supabase.rpc('void_event_guest_payment', { p_organization_id: orgId, p_payment_id: paymentId });
  if (error) throw error;
}

export async function setEventGuestWaiver(orgId: string, guestId: string, waived: boolean) {
  const { error } = await supabase.rpc('set_event_guest_waiver', {
    p_organization_id: orgId,
    p_guest_id: guestId,
    p_waived: waived,
  });
  if (error) throw error;
}

export async function setEventGuestFee(orgId: string, eventId: string, fee: number | null) {
  const { error } = await supabase.rpc('set_event_guest_fee', {
    p_organization_id: orgId,
    p_event_id: eventId,
    p_guest_fee: fee ?? undefined,
  });
  if (error) throw error;
}

export async function checkInEventGuest(orgId: string, guestId: string) {
  const { data, error } = await supabase.rpc('check_in_event_guest', { p_organization_id: orgId, p_guest_id: guestId });
  if (error) throw error;
  return data as unknown as { result: string };
}
