import { supabase } from '../../../lib/supabase/client';
import type {
  SetMemberContactPointInput,
  SetMemberContactPointResponse,
} from '../types';

/**
 * Frontend API wrapper for public.set_member_contact_point RPC.
 *
 * This function handles contact point mutations (add, replace_primary, remove)
 * for email, phone, and address.
 *
 * It enforces:
 * - Explicit nulls for absent optional parameters.
 * - Strict parameter mappings matching the live RPC signature:
 *     p_organization_id: uuid
 *     p_member_id: uuid
 *     p_contact_type: text ('email' | 'phone' | 'address')
 *     p_operation: text ('add' | 'replace_primary' | 'remove')
 *     p_target_id: uuid | null
 *     p_value: text | null
 *     p_phone_country_code: text | null (ISO 2-letter country code)
 *     p_address_data: jsonb | null
 *     p_effective_from: date | null
 *     p_reason: text | null
 *
 * No direct table writes to member_emails, member_phones, addresses, or member_addresses.
 */
export async function setMemberContactPoint(
  input: SetMemberContactPointInput
): Promise<SetMemberContactPointResponse> {
  const cleanOrUndefined = (val?: string | null): string | undefined => {
    if (!val) return undefined;
    const t = val.trim();
    return t.length > 0 ? t : undefined;
  };

  const payload = {
    p_organization_id: input.organizationId,
    p_member_id: input.memberId,
    p_contact_type: input.contactType,
    p_operation: input.operation,
    p_target_id: input.targetId ? input.targetId : undefined,
    p_value: cleanOrUndefined(input.value),
    p_phone_country_code: cleanOrUndefined(input.phoneCountryCode),
    p_address_data: input.addressData
      ? {
          line1: input.addressData.line1.trim(),
          line2: input.addressData.line2?.trim() || null,
          city: input.addressData.city.trim(),
          state: input.addressData.state?.trim() || null,
          postal: input.addressData.postal?.trim() || null,
          country: input.addressData.country?.trim() || null,
        }
      : undefined,
    p_effective_from: cleanOrUndefined(input.effectiveFrom),
    p_reason: cleanOrUndefined(input.reason),
  };

  const { data, error } = await supabase.rpc(
    'set_member_contact_point',
    payload
  );


  if (error) {
    throw error;
  }

  return data as unknown as SetMemberContactPointResponse;
}
