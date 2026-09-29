-- =============================================================================
-- Test Script: supabase/tests/phase_5g_member_status_history_security.sql
-- Description: Non-destructive verification of Phase 5G Membership Status
--              History Read RPC inside a BEGIN ... ROLLBACK transaction block.
-- =============================================================================

BEGIN;

DO $$
declare
    v_org_id                    uuid := '22efefb6-2858-4629-ace6-66ea4e20cfdf';
    v_admin_profile_id          uuid := '821fb09c-8396-4549-b120-5674f3cc566a';
    v_test_member_id            uuid;
    v_history_rows_count        bigint;
    v_first_row                 record;
    v_foreign_member_id         uuid := gen_random_uuid();
    v_raised                    boolean;
begin
    -- -------------------------------------------------------------------------
    -- 0. Set execution context to Ron Acosta's profile ID
    -- -------------------------------------------------------------------------
    perform set_config('request.jwt.claims', jsonb_build_object(
        'sub', v_admin_profile_id::text,
        'email', 'ron.acosta@mfcnewyork.org',
        'role', 'authenticated'
    )::text, true);

    -- -------------------------------------------------------------------------
    -- 1. Verify Permission Assignment
    -- -------------------------------------------------------------------------
    if not private.has_permission('members.status.view', v_org_id) then
        raise exception 'FAILED: organization_administrator does not have members.status.view';
    end if;

    -- -------------------------------------------------------------------------
    -- 2. Select a test member
    -- -------------------------------------------------------------------------
    select id into v_test_member_id
    from public.members
    where organization_id = v_org_id
    order by id
    limit 1;

    -- -------------------------------------------------------------------------
    -- 3. Verify public.get_member_status_history returns baseline row
    -- -------------------------------------------------------------------------
    select count(*) into v_history_rows_count
    from public.get_member_status_history(v_org_id, v_test_member_id);

    if v_history_rows_count <> 1 then
        raise exception 'FAILED: expected 1 baseline history row for member, got %', v_history_rows_count;
    end if;

    select * into v_first_row
    from public.get_member_status_history(v_org_id, v_test_member_id)
    limit 1;

    if v_first_row.status_code <> 'active' then
        raise exception 'FAILED: expected status_code active, got %', v_first_row.status_code;
    end if;

    if v_first_row.is_current <> true then
        raise exception 'FAILED: baseline row should be is_current = true';
    end if;

    if v_first_row.source <> 'migration' then
        raise exception 'FAILED: expected source migration, got %', v_first_row.source;
    end if;

    if v_first_row.recorded_by_name <> 'System' then
        raise exception 'FAILED: expected recorded_by_name System for null profile, got %', v_first_row.recorded_by_name;
    end if;

    -- -------------------------------------------------------------------------
    -- 4. Verify P0002 for inaccessible / non-existent member
    -- -------------------------------------------------------------------------
    v_raised := false;
    begin
        perform * from public.get_member_status_history(v_org_id, v_foreign_member_id);
    exception when sqlstate 'P0002' then
        v_raised := true;
    end;

    if not v_raised then
        raise exception 'FAILED: query for non-existent member did not raise P0002';
    end if;

    raise notice 'SUCCESS: All Phase 5G backend security tests passed cleanly.';
end;
$$;

ROLLBACK;
