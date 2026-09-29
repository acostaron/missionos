import { supabase } from '../../../lib/supabase/client';
import type {
  UpdateMemberBasicProfileInput,
  UpdateMemberBasicProfileResponse,
} from '../types';

export async function updateMemberBasicProfile(
  input: UpdateMemberBasicProfileInput
): Promise<UpdateMemberBasicProfileResponse> {
  const cleanOrNull = (val?: string | null): string | null => {
    if (!val) return null;
    const t = val.trim();
    return t.length > 0 ? t : null;
  };

  const payload = {
    p_organization_id: input.organizationId,
    p_member_id: input.memberId,
    p_given_names: input.givenNames.trim(),
    p_family_name: input.familyName.trim(),
    p_middle_names: cleanOrNull(input.middleNames),
    p_preferred_name: cleanOrNull(input.preferredName),
    p_birth_date: cleanOrNull(input.birthDate),
    p_sex: cleanOrNull(input.sex),
    p_civil_status: cleanOrNull(input.civilStatus),
    p_home_country_code: cleanOrNull(input.homeCountryCode),
    p_preferred_language_code: cleanOrNull(input.preferredLanguageCode),
    p_is_name_change: input.isNameChange,
    p_effective_from: input.isNameChange
      ? (cleanOrNull(input.effectiveFrom) ?? new Date().toISOString().split('T')[0])
      : new Date().toISOString().split('T')[0],
    p_change_reason: input.isNameChange ? cleanOrNull(input.changeReason) : null,
  };

  const { data, error } = await supabase.rpc(
    'update_member_basic_profile',
    payload
  );

  if (error) {
    throw error;
  }

  return data as unknown as UpdateMemberBasicProfileResponse;
}
