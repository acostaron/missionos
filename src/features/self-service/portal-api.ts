import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { z } from 'zod';
import { supabase } from '../../lib/supabase/client';
import type { Json } from '../../types/database';
import { selfServiceKeys } from './api';
import { formatNyTime } from '../../lib/ny-time';

// ---------------------------------------------------------------------------
// Zod Schemas
// ---------------------------------------------------------------------------

export const myProfileDetailsSchema = z.object({
  member_id: z.string(),
  member_number: z.string().nullable(),
  display_name: z.string(),
  given_names: z.string().nullable(),
  middle_names: z.string().nullable(),
  family_name: z.string().nullable(),
  preferred_name: z.string().nullable(),
  birth_date: z.string().nullable(),
  sex: z.string().nullable(),
  civil_status: z.string().nullable(),
  photo_path: z.string().nullable(),
  can_edit: z.boolean(),
  emails: z.array(
    z.object({
      id: z.string(),
      email: z.string(),
      type: z.string().nullable().optional(),
      is_primary: z.boolean(),
    })
  ),
  phones: z.array(
    z.object({
      id: z.string(),
      phone: z.string(),
      type: z.string().nullable().optional(),
      is_primary: z.boolean(),
    })
  ),
  home_address: z
    .object({
      member_address_id: z.string(),
      line1: z.string(),
      line2: z.string().nullable(),
      city: z.string(),
      state: z.string().nullable(),
      postal: z.string().nullable(),
      country: z.string().nullable(),
    })
    .nullable(),
  spouse: z
    .object({
      display_name: z.string(),
      wedding_date: z.string().nullable(),
    })
    .nullable(),
});
export type MyProfileDetails = z.infer<typeof myProfileDetailsSchema>;

export const memberCardSchema = z.object({
  qr_payload: z.string(),
  card_public_id: z.string().nullable(),
  issued_at: z.string(),
  member_id: z.string(),
  member_number: z.string().nullable(),
  display_name: z.string(),
  membership_status: z.string().nullable(),
  photo_path: z.string().nullable(),
  organizational_context: z.object({
    area: z.string().nullable(),
    section: z.string().nullable(),
    chapter: z.string().nullable(),
    unit: z.string().nullable(),
  }),
  household_name: z.string().nullable(),
});
export type MemberCard = z.infer<typeof memberCardSchema>;

export const myEventSchema = z.object({
  event_id: z.string(),
  event_type: z.string(),
  title: z.string(),
  starts_at: z.string(),
  ends_at: z.string().nullable(),
  location_text: z.string().nullable(),
  event_status: z.string(),
  audience_name: z.string().nullable(),
  program_title: z.string().nullable(),
  session_number: z.number().nullable(),
  session_count: z.number().nullable(),
  attended: z.boolean(),
});
export type MyEvent = z.infer<typeof myEventSchema>;

export const myAttendanceSchema = z.object({
  event_id: z.string(),
  event_type: z.string(),
  title: z.string(),
  starts_at: z.string(),
  event_status: z.string(),
  program_title: z.string().nullable(),
  session_number: z.number().nullable(),
  recorded_at: z.string(),
  check_in_method: z.string().nullable(),
});
export type MyAttendance = z.infer<typeof myAttendanceSchema>;

export const myHouseholdMeetingSchema = z.object({
  household_meeting_id: z.string(),
  household_id: z.string(),
  household_name: z.string(),
  meeting_date: z.string(),
  scheduled_start_at: z.string().nullable(),
  scheduled_end_at: z.string().nullable(),
  meeting_status: z.string(),
  meeting_type: z.string(),
  location_type: z.string().nullable(),
  location_text: z.string().nullable(),
  host_name: z.string().nullable(),
  facilitator_name: z.string().nullable(),
  my_attendance_status: z.string().nullable(),
});
export type MyHouseholdMeeting = z.infer<typeof myHouseholdMeetingSchema>;

export const myServiceSchema = z.object({
  role_code: z.string(),
  role_name: z.string(),
  node_id: z.string(),
  node_name: z.string(),
  node_type: z.string().nullable(),
  effective_from: z.string().nullable(),
  basis: z.enum(['appointed', 'with_spouse']),
  partner_name: z.string().nullable(),
  leader_names: z.string().nullable().optional(),
  household: z
    .object({
      household_id: z.string(),
      household_name: z.string(),
      pastoral_level: z.string(),
      meeting_frequency: z.string().nullable(),
      meeting_day_of_week: z.number().nullable(),
      meeting_start_time: z.string().nullable(),
      meeting_timezone_name: z.string().nullable(),
      location_type: z.string().nullable(),
      parent_node_name: z.string().nullable(),
      active_member_count: z.number(),
    })
    .nullable()
    .optional(),
});
export type MyServiceItem = z.infer<typeof myServiceSchema>;

// ---------------------------------------------------------------------------
// Query Keys
// ---------------------------------------------------------------------------

export const portalKeys = {
  details: (orgId: string | null) => [...selfServiceKeys.all, 'details', orgId] as const,
  card: (orgId: string | null) => [...selfServiceKeys.all, 'card', orgId] as const,
  service: (orgId: string | null) => [...selfServiceKeys.all, 'service', orgId] as const,
  events: (orgId: string | null, from: string, to: string) =>
    [...selfServiceKeys.all, 'events', orgId, from, to] as const,
  householdMeetings: (orgId: string | null, from: string, to: string) =>
    [...selfServiceKeys.all, 'household-meetings', orgId, from, to] as const,
  attendance: (orgId: string | null, from: string | null, to: string | null) =>
    [...selfServiceKeys.all, 'attendance', orgId, from, to] as const,
};

// ---------------------------------------------------------------------------
// Hooks
// ---------------------------------------------------------------------------

export function useMyProfileDetails(
  organizationId: string | null,
  enabled: boolean = true
) {
  return useQuery<MyProfileDetails>({
    queryKey: portalKeys.details(organizationId),
    queryFn: async () => {
      if (!organizationId) throw new Error('Organization ID is required');
      const { data, error } = await supabase.rpc('get_my_profile_details', {
        p_organization_id: organizationId,
      });
      if (error) throw error;
      return myProfileDetailsSchema.parse(data);
    },
    enabled: !!organizationId && enabled,
    staleTime: 60_000,
  });
}

export function useMyMemberCard(organizationId: string | null) {
  return useQuery<MemberCard>({
    queryKey: portalKeys.card(organizationId),
    queryFn: async () => {
      if (!organizationId) throw new Error('Organization ID is required');
      const { data, error } = await supabase.rpc('get_my_member_card', {
        p_organization_id: organizationId,
      });
      if (error) throw error;
      return memberCardSchema.parse(data);
    },
    enabled: !!organizationId,
    retry: false,
    staleTime: 5 * 60 * 1000,
    refetchOnWindowFocus: false,
  });
}

export function useListMyEvents(organizationId: string | null, from: string, to: string) {
  return useQuery<MyEvent[]>({
    queryKey: portalKeys.events(organizationId, from, to),
    queryFn: async () => {
      if (!organizationId) throw new Error('Organization ID is required');
      const { data, error } = await supabase.rpc('list_my_events', {
        p_organization_id: organizationId,
        p_from: from,
        p_to: to,
      });
      if (error) throw error;
      return z.array(myEventSchema).parse(data || []);
    },
    enabled: !!organizationId && !!from && !!to,
    staleTime: 30_000,
  });
}

export function useListMyHouseholdMeetings(
  organizationId: string | null,
  from: string,
  to: string,
  enabled: boolean = true
) {
  return useQuery<MyHouseholdMeeting[]>({
    queryKey: portalKeys.householdMeetings(organizationId, from, to),
    queryFn: async () => {
      if (!organizationId) throw new Error('Organization ID is required');
      const { data, error } = await supabase.rpc('list_my_household_meetings', {
        p_organization_id: organizationId,
        p_from: from,
        p_to: to,
      });
      if (error) throw error;
      return z.array(myHouseholdMeetingSchema).parse(data || []);
    },
    enabled: !!organizationId && !!from && !!to && enabled,
    staleTime: 30_000,
  });
}

export function useMyService(
  organizationId: string | null,
  enabled: boolean = true
) {
  return useQuery<MyServiceItem[]>({
    queryKey: portalKeys.service(organizationId),
    queryFn: async () => {
      if (!organizationId) throw new Error('Organization ID is required');
      const { data, error } = await supabase.rpc('get_my_service', {
        p_organization_id: organizationId,
      });
      if (error) throw error;
      return z.array(myServiceSchema).parse(data || []);
    },
    enabled: !!organizationId && enabled,
    staleTime: 30_000,
  });
}

export function formatNextMeeting(meeting: MyHouseholdMeeting | null | undefined): string {
  if (!meeting) return 'No meeting scheduled';
  const parts: string[] = [];
  if (meeting.meeting_date) {
    const d = meeting.meeting_date.includes('T')
      ? new Date(meeting.meeting_date)
      : new Date(`${meeting.meeting_date}T12:00:00Z`);
    const dateStr = new Intl.DateTimeFormat('en-US', {
      timeZone: 'America/New_York',
      weekday: 'short',
      month: 'short',
      day: 'numeric',
    }).format(d);
    parts.push(dateStr);
  }
  if (meeting.scheduled_start_at) {
    parts.push(formatNyTime(meeting.scheduled_start_at));
  }
  if (meeting.location_text && meeting.location_text.trim()) {
    parts.push(meeting.location_text.trim());
  }
  return parts.length > 0 ? parts.join(' · ') : 'No meeting scheduled';
}

export function useListMyAttendance(
  organizationId: string | null,
  from: string | null = null,
  to: string | null = null
) {
  return useQuery<MyAttendance[]>({
    queryKey: portalKeys.attendance(organizationId, from, to),
    queryFn: async () => {
      if (!organizationId) throw new Error('Organization ID is required');
      const { data, error } = await supabase.rpc('list_my_attendance', {
        p_organization_id: organizationId,
        p_from: from ?? undefined,
        p_to: to ?? undefined,
      });
      if (error) throw error;
      return z.array(myAttendanceSchema).parse(data || []);
    },
    enabled: !!organizationId,
    staleTime: 30_000,
  });
}

// ---------------------------------------------------------------------------
// Mutations
// ---------------------------------------------------------------------------

export function useUpdateMyBasicProfile() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({
      organizationId,
      givenNames,
      familyName,
      middleNames,
      preferredName,
      birthDate,
      sex,
    }: {
      organizationId: string;
      givenNames: string;
      familyName: string;
      middleNames?: string | null;
      preferredName?: string | null;
      birthDate?: string | null;
      sex?: 'male' | 'female' | null;
    }) => {
      const { data, error } = await supabase.rpc('update_my_basic_profile', {
        p_organization_id: organizationId,
        p_given_names: givenNames,
        p_family_name: familyName,
        p_middle_names: middleNames ?? undefined,
        p_preferred_name: preferredName ?? undefined,
        p_birth_date: birthDate ?? undefined,
        p_sex: sex ?? undefined,
      });
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: selfServiceKeys.all });
    },
  });
}

export function useSetMyContactPoint() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({
      organizationId,
      contactType,
      operation,
      targetId,
      value,
      addressData,
    }: {
      organizationId: string;
      contactType: 'email' | 'phone' | 'address';
      operation: 'add' | 'replace_primary' | 'remove';
      targetId?: string | null;
      value?: string | null;
      addressData?: {
        line1: string;
        line2?: string | null;
        city: string;
        state?: string | null;
        postal?: string | null;
        country?: string | null;
      } | null;
    }) => {
      const { data, error } = await supabase.rpc('set_my_contact_point', {
        p_organization_id: organizationId,
        p_contact_type: contactType,
        p_operation: operation,
        p_target_id: targetId ?? undefined,
        p_value: value ?? undefined,
        p_address_data: (addressData as unknown as Json) ?? undefined,
      });
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: selfServiceKeys.all });
    },
  });
}

export function useSetMyWeddingDate() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({
      organizationId,
      weddingDate,
    }: {
      organizationId: string;
      weddingDate: string | null;
    }) => {
      const { data, error } = await supabase.rpc('set_my_wedding_date', {
        p_organization_id: organizationId,
        p_wedding_date: weddingDate as unknown as string,
      });
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: selfServiceKeys.all });
    },
  });
}

export function useSetMemberPhoto() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({
      organizationId,
      memberId,
      storagePath,
    }: {
      organizationId: string;
      memberId: string | null;
      storagePath: string | null;
    }) => {
      const { data, error } = await supabase.rpc('set_member_photo', {
        p_organization_id: organizationId,
        p_member_id: memberId ?? undefined,
        p_storage_path: storagePath ?? undefined,
      });
      if (error) throw error;
      return data as {
        status: string;
        member_id: string;
        photo_path: string | null;
        previous_photo_path: string | null;
      };
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: selfServiceKeys.all });
      queryClient.invalidateQueries({ queryKey: ['members'] });
    },
  });
}

export function useReissueMemberCard() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({
      organizationId,
      memberId,
      reason,
    }: {
      organizationId: string;
      memberId: string | null;
      reason: string;
    }) => {
      const { data, error } = await supabase.rpc('reissue_member_card', {
        p_organization_id: organizationId,
        p_member_id: memberId ?? undefined,
        p_reason: reason,
      });
      if (error) throw error;
      return memberCardSchema.parse(data);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: selfServiceKeys.all });
      queryClient.invalidateQueries({ queryKey: ['members'] });
    },
  });
}
