// Admin Activity page (Pass 9.35, Ron 2026-10-21): reminders sent on a day, opens / clicks, app opens, sign-ins.
import { useQuery } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase/client';

export interface ActivityDelivery {
  delivery_id: string;
  member_id: string;
  display_name: string;
  member_number: string | null;
  channel: 'email' | 'push' | 'sms';
  reminder_type: 'reminder' | 'nudge';
  item_kind: 'event' | 'meeting';
  item_title: string | null;
  group_name: string | null;
  days_before: 1 | 3;
  status: 'claimed' | 'sent' | 'failed';
  attempts: number;
  sent_at: string | null;
  opened_at: string | null;
  clicked_at: string | null;
  error: string | null;
}

export interface ActivityAppOpen {
  profile_id: string;
  member_id: string | null;
  display_name: string;
  member_number: string | null;
  first_at: string;
  last_at: string;
  opens: number;
}

export interface ActivityAccount {
  member_id: string;
  display_name: string;
  member_number: string | null;
  last_sign_in_at: string | null;
  last_active_at: string | null;
  push_devices: number;
}

export interface ActivityReport {
  day: string;
  settings: { email_mode: string; push_mode: string; daily_email_limit: number } | null;
  deliveries: ActivityDelivery[];
  app_opens: ActivityAppOpen[];
  accounts: ActivityAccount[];
  members_active: number;
}

export function useActivityReport(orgId: string | null, day: string) {
  return useQuery<ActivityReport>({
    queryKey: ['activity', orgId, day],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('get_activity_report', { p_organization_id: orgId!, p_day: day });
      if (error) throw error;
      return data as unknown as ActivityReport;
    },
    enabled: !!orgId,
    staleTime: 60_000,
  });
}

const OPEN_KEY = 'missionos.app_open_at';

/** Records that this person opened MissionOS (at most every 15 minutes per browser). Never throws. */
export async function recordAppOpen(orgId: string) {
  try {
    const last = Number(sessionStorage.getItem(OPEN_KEY) ?? 0);
    if (Date.now() - last < 15 * 60_000) return;
    sessionStorage.setItem(OPEN_KEY, String(Date.now()));
  } catch {
    /* storage unavailable: still record */
  }
  try {
    await supabase.rpc('record_my_app_open', { p_organization_id: orgId });
  } catch {
    /* ignore */
  }
}
