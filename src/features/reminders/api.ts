// Email reminders — my setting (Pass 9.33, Ron 2026-10-21).
import { useQuery, type QueryClient } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase/client';

export interface MyReminderPreferences {
  email_enabled: boolean;
  has_email: boolean;
  reminders_active: boolean;
}

export const reminderKeys = { mine: (orgId: string | null) => ['reminders', 'mine', orgId] as const };

export function useMyReminderPreferences(orgId: string | null, enabled: boolean) {
  return useQuery<MyReminderPreferences>({
    queryKey: reminderKeys.mine(orgId),
    queryFn: async () => {
      const { data, error } = await supabase.rpc('get_my_reminder_preferences', { p_organization_id: orgId! });
      if (error) throw error;
      return data as unknown as MyReminderPreferences;
    },
    enabled: !!orgId && enabled,
  });
}

export async function setMyReminderPreferences(qc: QueryClient, orgId: string, emailEnabled: boolean) {
  const { error } = await supabase.rpc('set_my_reminder_preferences', {
    p_organization_id: orgId,
    p_email_enabled: emailEnabled,
  });
  if (error) throw error;
  await qc.invalidateQueries({ queryKey: reminderKeys.mine(orgId) });
}
