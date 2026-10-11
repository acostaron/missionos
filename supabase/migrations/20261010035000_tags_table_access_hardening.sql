-- Migration 103: Tags table access hardening
-- Label: tags_table_access_hardening
-- Contiguous timestamp: 20261010035000

-- A. Revoke all direct client access to tags and entity_tags
REVOKE ALL ON public.tags, public.entity_tags FROM anon, authenticated;

COMMENT ON TABLE public.tags IS 'Direct client access revoked in Migration 103; access only via SECURITY DEFINER RPCs.';
COMMENT ON TABLE public.entity_tags IS 'Direct client access revoked in Migration 103; access only via SECURITY DEFINER RPCs.';

-- D. Record summary audit event in audit.events
DO $$
DECLARE
    v_org_id uuid := '22efefb6-2858-4629-ace6-66ea4e20cfdf'::uuid;
BEGIN
    INSERT INTO audit.events (
        organization_id,
        event_code,
        event_category,
        entity_type,
        entity_id,
        action,
        outcome,
        metadata
    ) VALUES (
        v_org_id,
        'security.table_grants_hardened',
        'security',
        'table',
        v_org_id,
        'revoke_direct_client_access',
        'success',
        jsonb_build_object(
            'migration', '20261010035000_tags_table_access_hardening',
            'tables', jsonb_build_array('public.tags', 'public.entity_tags'),
            'revoked_roles', jsonb_build_array('anon', 'authenticated')
        )
    );
END $$;
