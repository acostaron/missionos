-- Migration 106: archive_audit_backfill_2026_10
-- Backfill individual member.record.archived audit events for the 4 archived members from Pass 4.6B batch.
-- Strictly idempotent, no member-id literals, guarded by assertion.

DO $$
DECLARE
    v_total_targets int;
    v_already_backfilled int;
    v_to_backfill int := 0;
    v_r record;
BEGIN
    -- Guard 1: Verify staging batch has exactly 4 archive rows
    SELECT count(*) INTO v_total_targets
    FROM staging.member_placement_import s
    WHERE s.import_batch_code = 'mfcny_placement_2026_10'
      AND s.action = 'archive';

    IF v_total_targets <> 4 THEN
        RAISE EXCEPTION 'Expected exactly 4 archive rows in staging batch mfcny_placement_2026_10, found %', v_total_targets;
    END IF;

    -- Guard 2: Check how many already have the member.record.archived audit event
    SELECT count(*) INTO v_already_backfilled
    FROM staging.member_placement_import s
    JOIN public.member_identifiers mi
      ON mi.identifier_type = 'legacy_member_id'
     AND mi.identifier_value = s.legacy_member_id::text
    JOIN public.members m
      ON m.id = mi.member_id
    WHERE s.import_batch_code = 'mfcny_placement_2026_10'
      AND s.action = 'archive'
      AND EXISTS (
          SELECT 1
          FROM audit.events ae
          WHERE ae.event_code = 'member.record.archived'
            AND ae.entity_id = m.id
      );

    -- Idempotency check: if all 4 are already backfilled, no-op
    IF v_already_backfilled = 4 THEN
        RETURN;
    ELSIF v_already_backfilled > 0 THEN
        RAISE EXCEPTION 'Inconsistent state: % of 4 archive members already have audit events', v_already_backfilled;
    END IF;

    -- Insert individual audit events for each of the 4 archived members
    FOR v_r IN
        SELECT
            m.id AS member_id,
            m.organization_id
        FROM staging.member_placement_import s
        JOIN public.member_identifiers mi
          ON mi.identifier_type = 'legacy_member_id'
         AND mi.identifier_value = s.legacy_member_id::text
        JOIN public.members m
          ON m.id = mi.member_id
        WHERE s.import_batch_code = 'mfcny_placement_2026_10'
          AND s.action = 'archive'
          AND NOT EXISTS (
              SELECT 1
              FROM audit.events ae
              WHERE ae.event_code = 'member.record.archived'
                AND ae.entity_id = m.id
          )
        ORDER BY m.id
    LOOP
        PERFORM private.write_audit_event(
            p_organization_id  => v_r.organization_id,
            p_event_code       => 'member.record.archived',
            p_event_category   => 'member',
            p_actor_profile_id => NULL,
            p_entity_type      => 'member',
            p_entity_id        => v_r.member_id,
            p_action           => 'archive_record',
            p_outcome          => 'success',
            p_access_reason    => NULL,
            p_correlation_id   => NULL,
            p_metadata         => jsonb_build_object(
                'previous_record_status', 'active',
                'new_record_status', 'archived',
                'archive_reason', 'not_an_mfcny_member_or_test_record',
                'source', 'pass_4_6b_bulk_import',
                'backfilled', true
            )
        );
        v_to_backfill := v_to_backfill + 1;
    END LOOP;

    IF v_to_backfill <> 4 THEN
        RAISE EXCEPTION 'Expected to backfill exactly 4 audit events, backfilled %', v_to_backfill;
    END IF;
END $$;
