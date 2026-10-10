import { supabase } from '../../lib/supabase/client';
import {
  formationCatalogResponseSchema,
  formationProgramDetailSchema,
} from './schemas';
import type {
  FormationCatalogFilters,
  FormationProgramDetail,
  FormationProgramSummary,
} from './types';

/**
 * Retrieves the formation curriculum catalog accessible in the requested organization context.
 * Returns global programs (organization_id IS NULL) plus any local programs for the organization.
 * Inactive programs are omitted unless includeInactive is explicitly true (requires formation.catalog.manage).
 */
export async function getFormationCatalog(
  organizationId: string,
  filters?: FormationCatalogFilters
): Promise<FormationProgramSummary[]> {
  const { data, error } = await supabase.rpc('get_formation_catalog', {
    p_organization_id: organizationId,
    p_program_category: filters?.programCategory ?? undefined,
    p_include_inactive: filters?.includeInactive ?? false,
  });

  if (error) {
    throw error;
  }

  return formationCatalogResponseSchema.parse(data);
}

/**
 * Retrieves the complete detail of a specific formation program by ID,
 * including structured talk sessions and canonical requirements.
 */
export async function getFormationProgram(
  organizationId: string,
  programId: string
): Promise<FormationProgramDetail> {
  const { data, error } = await supabase.rpc('get_formation_program', {
    p_organization_id: organizationId,
    p_program_id: programId,
  });

  if (error) {
    throw error;
  }

  return formationProgramDetailSchema.parse(data);
}
