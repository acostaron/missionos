// Household topics tied to scheduled meetings (Pass 9.4, written by Claude 2026-10-15)
import { useQuery, type QueryClient } from '@tanstack/react-query';
import { supabase } from '../../../lib/supabase/client';
import { searchFormationTopics } from './search-formation-topics';
import { meetingKeys } from './get-household-meeting-history';
import type { FormationTopicSearchResult } from '../types';

export interface MeetingTopic {
  assignment_id: string;
  household_meeting_id: string;
  topic_id: string;
  title: string;
  topic_code: string | null;
  material_kind: string | null;
  is_library_topic: boolean;
  assignment_status: 'planned' | 'completed' | 'skipped';
  resolution_reason_code: string | null;
  change_reason_code: ChangeReasonCode | null;
  replaced_by_title: string | null;
  replaces_title: string | null;
  planned_for_date: string | null;
}

export const CHANGE_REASONS = [
  { code: 'pastoral_need', label: 'Pastoral need in the household' },
  { code: 'leader_decision', label: "Leader's decision" },
  { code: 'material_unavailable', label: 'Material not available' },
  { code: 'time_constraint', label: 'Time ran short' },
  { code: 'other', label: 'Other' },
] as const;
export type ChangeReasonCode = (typeof CHANGE_REASONS)[number]['code'];

export function changeReasonLabel(code: string | null | undefined): string {
  return CHANGE_REASONS.find((r) => r.code === code)?.label ?? '';
}

export const meetingTopicKeys = {
  all: ['household-meeting-topics'] as const,
  forHousehold: (orgId: string, householdId: string) =>
    [...meetingTopicKeys.all, orgId, householdId] as const,
  topicChoices: (orgId: string, level: string | null) =>
    [...meetingTopicKeys.all, 'choices', orgId, level ?? 'any'] as const,
};

export function useHouseholdMeetingTopics(
  organizationId: string | null,
  householdId: string | null,
  enabled = true,
) {
  return useQuery<MeetingTopic[]>({
    queryKey:
      organizationId && householdId
        ? meetingTopicKeys.forHousehold(organizationId, householdId)
        : [...meetingTopicKeys.all, 'disabled'],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('get_household_meeting_topics', {
        p_organization_id: organizationId!,
        p_household_node_id: householdId!,
      });
      if (error) throw error;
      return (data ?? []) as unknown as MeetingTopic[];
    },
    enabled: !!organizationId && !!householdId && enabled,
    staleTime: 30_000,
  });
}

/** Library topic codes look like "2026-10 HT". */
const LIBRARY_CODE = /^(\d{4})-(\d{2}) /;

export type TopicChoice = FormationTopicSearchResult['topics'][number];

/** Topics for the pickers: Household Library topics first (newest month first), then the rest. */
export function useTopicChoices(organizationId: string | null, pastoralLevel: string | null, enabled = true) {
  return useQuery({
    queryKey: organizationId
      ? meetingTopicKeys.topicChoices(organizationId, pastoralLevel)
      : [...meetingTopicKeys.all, 'choices-disabled'],
    queryFn: async () => {
      const res = await searchFormationTopics(organizationId!, null, pastoralLevel, 100, 0);
      const topics = [...(res.topics ?? [])];
      const groups = new Map<string, TopicChoice[]>();
      const other: TopicChoice[] = [];
      for (const t of topics) {
        const m = t.topic_code ? LIBRARY_CODE.exec(t.topic_code) : null;
        if (m) {
          const key = `${m[1]}-${m[2]}`;
          if (!groups.has(key)) groups.set(key, []);
          groups.get(key)!.push(t);
        } else {
          other.push(t);
        }
      }
      const library = Array.from(groups.entries())
        .sort((a, b) => b[0].localeCompare(a[0]))
        .map(([month, list]) => ({
          label: `Household Library — ${new Intl.DateTimeFormat('en-US', { month: 'long', year: 'numeric', timeZone: 'UTC' }).format(new Date(`${month}-15T12:00:00Z`))}`,
          topics: list.sort((a, b) => (a.topic_code ?? '').localeCompare(b.topic_code ?? '')),
        }));
      return { library, other };
    },
    enabled: !!organizationId && enabled,
    staleTime: 60_000,
  });
}

export async function assignTopicToMeeting(
  organizationId: string,
  householdId: string,
  topicId: string,
  meetingId: string,
): Promise<{ topic_title: string; meeting_date: string }> {
  const { data, error } = await supabase.rpc('assign_household_topic_to_meeting', {
    p_organization_id: organizationId,
    p_household_node_id: householdId,
    p_topic_id: topicId,
    p_meeting_id: meetingId,
  });
  if (error) throw error;
  return data as unknown as { topic_title: string; meeting_date: string };
}

export async function changeMeetingTopic(args: {
  organizationId: string;
  meetingId: string;
  replacedAssignmentId: string | null;
  newTopicId: string | null;
  otherTitle: string | null;
  reasonCode: ChangeReasonCode;
}): Promise<{ used_title: string }> {
  const { data, error } = await supabase.rpc('change_meeting_topic', {
    p_organization_id: args.organizationId,
    p_meeting_id: args.meetingId,
    p_replaced_assignment_id: args.replacedAssignmentId ?? undefined,
    p_new_topic_id: args.newTopicId ?? undefined,
    p_other_title: args.otherTitle ?? undefined,
    p_reason_code: args.reasonCode,
  });
  if (error) throw error;
  return data as unknown as { used_title: string };
}

export async function invalidateMeetingTopicQueries(queryClient: QueryClient) {
  await Promise.all([
    queryClient.invalidateQueries({ queryKey: meetingTopicKeys.all }),
    queryClient.invalidateQueries({ queryKey: meetingKeys.all }),
  ]);
}
