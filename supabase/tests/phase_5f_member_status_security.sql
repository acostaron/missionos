-- =============================================================================
-- Test Script: supabase/tests/phase_5f_member_status_security.sql
-- Description: Non-destructive verification of Phase 5F-0 Membership Status
--              Foundation inside a BEGIN ... ROLLBACK transaction block.
-- =============================================================================

BEGIN;

DO $$
declare
    v_org_id                    uuid := '22efefb6-2858-4629-ace6-66ea4e20cfdf';
    v_admin_profile_id          uuid := '821fb09c-8396-4549-b120-5674f3cc566a';
    v_test_member_id            uuid;
    v_initial_status_id         uuid;
    v_target_status_id          uuid;
    v_deceased_status_id        uuid;
    v_archived_status_id        uuid;
    v_history_count_before      bigint;
    v_history_count_after       bigint;
    v_open_history_count        bigint;
    v_status_options_count      bigint;
    v_res                       jsonb;
    v_cur_member_status_id      uuid;
    v_cur_open_history_row      record;
    v_audit_count               bigint;
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
    if not private.has_permission('members.status.manage', v_org_id) then
        raise exception 'FAILED: organization_administrator does not have members.status.manage';
    end if;

    -- -------------------------------------------------------------------------
    -- 2. Verify Baseline History Count
    -- -------------------------------------------------------------------------
    select count(*) into v_history_count_before from public.member_status_history;
    select count(*) into v_open_history_count from public.member_status_history where effective_to_at is null;

    if v_history_count_before <> 315 then
        raise exception 'FAILED: expected 315 baseline history rows, found %', v_history_count_before;
    end if;

    if v_open_history_count <> 315 then
        raise exception 'FAILED: expected 315 open history rows, found %', v_open_history_count;
    end if;

    -- -------------------------------------------------------------------------
    -- 3. Verify public.get_member_statuses options
    -- -------------------------------------------------------------------------
    select count(*) into v_status_options_count
    from public.get_member_statuses(v_org_id);

    -- 7 total minus 2 reserved (deceased, archived) = 5 selectable
    if v_status_options_count <> 5 then
        raise exception 'FAILED: expected 5 selectable status options, got %', v_status_options_count;
    end if;

    -- Verify deceased & archived are excluded from options
    if exists (
        select 1 from public.get_member_statuses(v_org_id)
        where code in ('deceased', 'archived')
    ) then
        raise exception 'FAILED: reserved status codes (deceased, archived) found in options RPC';
    end if;

    -- -------------------------------------------------------------------------
    -- 4. Select a test member and statuses
    -- -------------------------------------------------------------------------
    select id, membership_status_id into v_test_member_id, v_initial_status_id
    from public.members
    where organization_id = v_org_id
    order by id
    limit 1;

    select id into v_target_status_id
    from public.member_statuses
    where organization_id = v_org_id
      and code = 'temporarily_inactive';

    select id into v_deceased_status_id
    from public.member_statuses
    where organization_id = v_org_id
      and code = 'deceased';

    select id into v_archived_status_id
    from public.member_statuses
    where organization_id = v_org_id
      and code = 'archived';

    -- -------------------------------------------------------------------------
    -- 5. Test Transition: active -> temporarily_inactive
    -- -------------------------------------------------------------------------
    v_res := public.change_member_membership_status(
        p_organization_id => v_org_id,
        p_member_id => v_test_member_id,
        p_target_status_id => v_target_status_id,
        p_effective_from => CURRENT_DATE,
        p_reason => 'Taking sabbatical for 3 months'
    );

    if (v_res->>'status') <> 'success' then
        raise exception 'FAILED: change_member_membership_status did not return success: %', v_res;
    end if;

    -- Verify member row cache updated
    select membership_status_id into v_cur_member_status_id
    from public.members
    where id = v_test_member_id;

    if v_cur_member_status_id <> v_target_status_id then
        raise exception 'FAILED: public.members.membership_status_id was not updated';
    end if;

    -- Verify previous history row closed and new row open
    select count(*) into v_history_count_after
    from public.member_status_history
    where member_id = v_test_member_id;

    if v_history_count_after <> 2 then
        raise exception 'FAILED: expected 2 history rows for test member, found %', v_history_count_after;
    end if;

    select * into v_cur_open_history_row
    from public.member_status_history
    where member_id = v_test_member_id
      and effective_to_at is null;

    if v_cur_open_history_row.member_status_id <> v_target_status_id then
        raise exception 'FAILED: open history row does not match target status';
    end if;

    if v_cur_open_history_row.change_summary <> 'Taking sabbatical for 3 months' then
        raise exception 'FAILED: open history row change_summary mismatch';
    end if;

    if v_cur_open_history_row.recorded_by_profile_id <> v_admin_profile_id then
        raise exception 'FAILED: recorded_by_profile_id is not actor profile';
    end if;

    -- Verify audit event created
    select count(*) into v_audit_count
    from audit.events
    where entity_id = v_test_member_id
      and event_code = 'member.status.changed'
      and actor_profile_id = v_admin_profile_id;

    if v_audit_count = 0 then
        raise exception 'FAILED: expected audit event for member.status.changed';
    end if;

    -- -------------------------------------------------------------------------
    -- 6. Test Error Condition: Same status rejection (22023)
    -- -------------------------------------------------------------------------
    v_raised := false;
    begin
        perform public.change_member_membership_status(
            p_organization_id => v_org_id,
            p_member_id => v_test_member_id,
            p_target_status_id => v_target_status_id,
            p_effective_from => CURRENT_DATE,
            p_reason => 'Redundant change'
        );
    exception when sqlstate '22023' then
        v_raised := true;
    end;

    if not v_raised then
        raise exception 'FAILED: same-status change did not raise SQLSTATE 22023';
    end if;

    -- -------------------------------------------------------------------------
    -- 7. Test Error Condition: Future-dated transition rejection (22023)
    -- -------------------------------------------------------------------------
    v_raised := false;
    begin
        perform public.change_member_membership_status(
            p_organization_id => v_org_id,
            p_member_id => v_test_member_id,
            p_target_status_id => v_initial_status_id,
            p_effective_from => CURRENT_DATE + 1,
            p_reason => 'Future date'
        );
    exception when sqlstate '22023' then
        v_raised := true;
    end;

    if not v_raised then
        raise exception 'FAILED: future-dated change did not raise SQLSTATE 22023';
    end if;

    -- -------------------------------------------------------------------------
    -- 8. Test Error Condition: Reserved status 'deceased' rejection (22023)
    -- -------------------------------------------------------------------------
    v_raised := false;
    begin
        perform public.change_member_membership_status(
            p_organization_id => v_org_id,
            p_member_id => v_test_member_id,
            p_target_status_id => v_deceased_status_id,
            p_effective_from => CURRENT_DATE,
            p_reason => 'Reserved status test'
        );
    exception when sqlstate '22023' then
        v_raised := true;
    end;

    if not v_raised then
        raise exception 'FAILED: transition to deceased did not raise SQLSTATE 22023';
    end if;

    -- -------------------------------------------------------------------------
    -- 9. Test Error Condition: Reserved status 'archived' rejection (22023)
    -- -------------------------------------------------------------------------
    v_raised := false;
    begin
        perform public.change_member_membership_status(
            p_organization_id => v_org_id,
            p_member_id => v_test_member_id,
            p_target_status_id => v_archived_status_id,
            p_effective_from => CURRENT_DATE,
            p_reason => 'Reserved status test'
        );
    exception when sqlstate '22023' then
        v_raised := true;
    end;

    if not v_raised then
        raise exception 'FAILED: transition to archived did not raise SQLSTATE 22023';
    end if;

    raise notice 'SUCCESS: All Phase 5F-0 backend tests passed cleanly inside transaction.';
end;
$$;

ROLLBACK;
