// Attending / Not attending replies (Pass 9.28, Ron 2026-10-21).
import { useQuery, type QueryClient } from '@tanstack/react-query';
import { supabase } from '../../lib/supabase/client';

export type ReplyResponse = 'attending' | 'not_attending';

export interface MyReply {
  event_id: string | null;
  household_meeting_id: string | null;
  response: ReplyResponse;
  responded_at: string;
}

export interface ReplyPerson {
  member_id: string;
  member_number: string | null;
  display_name: string;
  responded_at: string;
}

export interface RepliesSummary {
  attending: ReplyPerson[];
  not_attending: ReplyPerson[];
  counts: { attending: number; not_attending: number };
}

export const replyKeys = {
  all: ['replies'] as const,
  mine: (orgId: string | null) => [...replyKeys.all, 'mine', orgId] as const,
  event: (orgId: string | null, eventId: string) => [...replyKeys.all, 'event', orgId, eventId] as const,
  meeting: (orgId: string | null, meetingId: string) => [...replyKeys.all, 'meeting', orgId, meetingId] as const,
};

export function useMyReplies(orgId: string | null) {
  return useQuery<MyReply[]>({
    queryKey: replyKeys.mine(orgId),
    queryFn: async () => {
      const { data, error } = await supabase.rpc('list_my_replies', { p_organization_id: orgId! });
      if (error) throw error;
      return (data as unknown as MyReply[]) ?? [];
    },
    enabled: !!orgId,
  });
}

export async function setMyReply(
  orgId: string,
  target: { eventId?: string; householdMeetingId?: string },
  response: ReplyResponse | null,
) {
  const { error } = await supabase.rpc('set_my_reply', {
    p_organization_id: orgId,
    p_event_id: target.eventId ?? undefined,
    p_household_meeting_id: target.householdMeetingId ?? undefined,
    p_response: response ?? undefined,
  });
  if (error) throw error;
}

export function useEventReplies(orgId: string | null, eventId: string, enabled: boolean) {
  return useQuery<RepliesSummary>({
    queryKey: replyKeys.event(orgId, eventId),
    queryFn: async () => {
      const { data, error } = await supabase.rpc('get_event_replies', { p_organization_id: orgId!, p_event_id: eventId });
      if (error) throw error;
      return data as unknown as RepliesSummary;
    },
    enabled: !!orgId && enabled,
  });
}

export function useMeetingReplies(orgId: string | null, meetingId: string, enabled: boolean) {
  return useQuery<RepliesSummary>({
    queryKey: replyKeys.meeting(orgId, meetingId),
    queryFn: async () => {
      const { data, error } = await supabase.rpc('get_meeting_replies', {
        p_organization_id: orgId!,
        p_household_meeting_id: meetingId,
      });
      if (error) throw error;
      return data as unknown as RepliesSummary;
    },
    enabled: !!orgId && enabled,
  });
}

export async function invalidateReplies(qc: QueryClient) {
  await qc.invalidateQueries({ queryKey: replyKeys.all });
}
