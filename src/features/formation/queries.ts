import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import {
  getFormationCatalog,
  getFormationProgram,
  getMemberFormationTranscript,
  getMyFormationTranscript,
  recordFormationProgram,
  recordFormationTalk,
  voidFormationProgramRecord,
  voidFormationTalkRecord,
} from './api';
import type {
  FormationCatalogFilters,
  FormationProgramDetail,
  FormationProgramSummary,
  FormationTranscript,
  RecordFormationProgramInput,
  RecordFormationTalkInput,
} from './types';

export const formationKeys = {
  all: ['formation'] as const,
  catalogs: () => [...formationKeys.all, 'catalog'] as const,
  catalog: (orgId: string, filters?: FormationCatalogFilters) =>
    [...formationKeys.catalogs(), orgId, filters] as const,
  programs: () => [...formationKeys.all, 'program'] as const,
  program: (orgId: string, programId: string) =>
    [...formationKeys.programs(), orgId, programId] as const,
  transcripts: () => [...formationKeys.all, 'transcript'] as const,
  memberTranscript: (orgId: string, memberId: string) =>
    [...formationKeys.transcripts(), 'member', orgId, memberId] as const,
  myTranscript: (orgId?: string) =>
    [...formationKeys.transcripts(), 'my', orgId ?? 'default'] as const,
};

/**
 * Hook to retrieve the formation curriculum catalog for the given organization context.
 */
export function useFormationCatalog(
  organizationId: string | null,
  filters?: FormationCatalogFilters,
  enabled: boolean = true
) {
  return useQuery<FormationProgramSummary[]>({
    queryKey: organizationId
      ? formationKeys.catalog(organizationId, filters)
      : formationKeys.catalogs(),
    queryFn: () => {
      if (!organizationId) throw new Error('organizationId is required');
      return getFormationCatalog(organizationId, filters);
    },
    enabled: !!organizationId && enabled,
    staleTime: 60 * 1000,
  });
}

/**
 * Hook to retrieve full detail for a formation program, including talks and requirements.
 */
export function useFormationProgram(
  organizationId: string | null,
  programId: string | null,
  enabled: boolean = true
) {
  return useQuery<FormationProgramDetail>({
    queryKey:
      organizationId && programId
        ? formationKeys.program(organizationId, programId)
        : formationKeys.programs(),
    queryFn: () => {
      if (!organizationId || !programId) {
        throw new Error('organizationId and programId are required');
      }
      return getFormationProgram(organizationId, programId);
    },
    enabled: !!organizationId && !!programId && enabled,
    staleTime: 60 * 1000,
  });
}

/**
 * Hook to retrieve a member's formation transcript.
 */
export function useMemberFormationTranscript(
  organizationId: string | null,
  memberId: string | null,
  enabled: boolean = true
) {
  return useQuery<FormationTranscript>({
    queryKey:
      organizationId && memberId
        ? formationKeys.memberTranscript(organizationId, memberId)
        : formationKeys.transcripts(),
    queryFn: () => {
      if (!organizationId || !memberId) {
        throw new Error('organizationId and memberId are required');
      }
      return getMemberFormationTranscript(organizationId, memberId);
    },
    enabled: !!organizationId && !!memberId && enabled,
    staleTime: 60 * 1000,
  });
}

/**
 * Hook to retrieve the authenticated caller's own formation transcript.
 */
export function useMyFormationTranscript(
  organizationId?: string | null,
  enabled: boolean = true
) {
  return useQuery<FormationTranscript>({
    queryKey: formationKeys.myTranscript(organizationId ?? undefined),
    queryFn: () => getMyFormationTranscript(organizationId ?? undefined),
    enabled,
    staleTime: 60 * 1000,
    retry: false,
  });
}

/**
 * Mutation hook to record a formation program completion or participation.
 */
export function useRecordFormationProgram() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (input: RecordFormationProgramInput) => recordFormationProgram(input),
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({
        queryKey: formationKeys.memberTranscript(variables.organizationId, variables.memberId),
      });
    },
  });
}

/**
 * Mutation hook to record a formation talk participation.
 */
export function useRecordFormationTalk(memberId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (input: RecordFormationTalkInput) => recordFormationTalk(input),
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({
        queryKey: formationKeys.memberTranscript(variables.organizationId, memberId),
      });
    },
  });
}

/**
 * Mutation hook to void an erroneous program record and its talks.
 */
export function useVoidFormationProgramRecord(memberId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({
      organizationId,
      recordId,
      voidReason,
    }: {
      organizationId: string;
      recordId: string;
      voidReason: string;
    }) => voidFormationProgramRecord(organizationId, recordId, voidReason),
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({
        queryKey: formationKeys.memberTranscript(variables.organizationId, memberId),
      });
    },
  });
}

/**
 * Mutation hook to void an erroneous talk record.
 */
export function useVoidFormationTalkRecord(memberId: string) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({
      organizationId,
      talkRecordId,
      voidReason,
    }: {
      organizationId: string;
      talkRecordId: string;
      voidReason: string;
    }) => voidFormationTalkRecord(organizationId, talkRecordId, voidReason),
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({
        queryKey: formationKeys.memberTranscript(variables.organizationId, memberId),
      });
    },
  });
}
