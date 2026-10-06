-- =============================================================================
-- Migration: 20261002220000_phase_6b_household_formation_topics.sql
-- Description: Phase 6B-10 Household Formation & Topic Tracking
--              - Separates Content Catalog from Household Topic Plan and Meeting Delivery
--              - Tables: public.formation_topics, public.household_topic_assignments
--              - Permissions: households.formation.view, households.formation.manage
--              - Delegated role mappings with Phase 6B-9 direct responsibility guards
--              - RPCs: assign, reschedule, complete, skip, cancel, history, plan, search
--              - Pastoral dashboard & household profile integration
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Permissions
-- -----------------------------------------------------------------------------

insert into public.permissions (
  code,
  name,
  description,
  domain_code,
  action_code,
  scope_type,
  risk_level,
  requires_access_reason,
  requires_access_logging,
  is_active
)
values
  (
    'households.formation.view',
    'View household formation plan and topic history',
    'Allows viewing household formation topics, planned topics, and completed topic history',
    'households',
    'view',
    'governance',
    'standard',
    false,
    false,
    true
  ),
  (
    'households.formation.manage',
    'Manage household formation topics',
    'Allows planning, assigning, rescheduling, completing, and skipping formation topics for authorized households',
    'households',
    'manage',
    'governance',
    'standard',
    false,
    true,
    true
  )
on conflict (code) do update set
  name = excluded.name,
  description = excluded.description,
  domain_code = excluded.domain_code,
  action_code = excluded.action_code,
  scope_type = excluded.scope_type,
  risk_level = excluded.risk_level,
  is_active = excluded.is_active;

-- Map permissions to app roles
insert into public.role_permissions (
  organization_id,
  app_role_id,
  permission_id,
  permission_effect,
  effective_from_at,
  effective_to_at,
  approval_status,
  approved_at,
  created_at,
  updated_at
)
select
  r.organization_id,
  r.id as app_role_id,
  p.id as permission_id,
  'allow',
  now(),
  null,
  'approved',
  now(),
  now(),
  now()
from public.app_roles r
cross join public.permissions p
where r.code in (
    'organization_administrator',
    'household_servant_leader_access',
    'unit_servant_leader_access',
    'chapter_servant_leader_access',
    'area_servant_leader_access'
  )
  and p.code in (
    'households.formation.view',
    'households.formation.manage'
  )
  and not exists (
    select 1
    from public.role_permissions rp
    where rp.app_role_id = r.id
      and rp.permission_id = p.id
      and rp.permission_effect = 'allow'
      and rp.effective_to_at is null
      and rp.approval_status = 'approved'
  );

-- -----------------------------------------------------------------------------
-- 2. Tables: formation_topics & household_topic_assignments
-- -----------------------------------------------------------------------------

create table if not exists public.formation_topics (
  id                           uuid primary key default gen_random_uuid(),
  organization_id              uuid null references public.organizations(id) on delete cascade,
  title                        text not null,
  short_title                  text null,
  topic_code                   text null,
  description                  text null,
  objectives                   text null,
  source_type                  text not null default 'household_topic' check (
    source_type in (
      'official_formation',
      'household_topic',
      'scripture_reflection',
      'assembly_follow_up',
      'mission_topic',
      'special_topic',
      'other'
    )
  ),
  formation_module_id          uuid null,
  formation_talk_id            uuid null,
  scripture_reference          text null,
  recommended_duration_minutes integer null check (recommended_duration_minutes is null or recommended_duration_minutes > 0),
  recommended_pastoral_level   text null check (
    recommended_pastoral_level is null or recommended_pastoral_level in ('member', 'unit', 'chapter', 'area', 'fraternal')
  ),
  is_active                    boolean not null default true,
  sort_order                   integer null,
  effective_from               date null,
  effective_to                 date null,
  created_at                   timestamptz not null default now(),
  updated_at                   timestamptz not null default now(),
  created_by_profile_id        uuid null references public.profiles(id) on delete set null,
  updated_by_profile_id        uuid null references public.profiles(id) on delete set null
);

create index if not exists idx_formation_topics_org_active
  on public.formation_topics (organization_id, is_active);

create index if not exists idx_formation_topics_source_type
  on public.formation_topics (source_type);

alter table public.formation_topics enable row level security;

create policy formation_topics_read_policy
  on public.formation_topics
  for select
  to authenticated
  using (
    organization_id is null
    or private.has_organization_access(organization_id)
  );

create policy formation_topics_write_policy
  on public.formation_topics
  for all
  to authenticated
  using (
    organization_id is not null
    and private.has_organization_access(organization_id)
    and (
      private.is_organization_administrator(private.current_profile_id(), organization_id)
      or private.has_permission('households.formation.manage', organization_id)
    )
  );

-- Household topic assignments / planning table
create table if not exists public.household_topic_assignments (
  id                             uuid primary key default gen_random_uuid(),
  organization_id                uuid not null references public.organizations(id) on delete cascade,
  household_node_id              uuid not null references public.governance_nodes(id) on delete restrict,
  topic_id                       uuid not null references public.formation_topics(id) on delete restrict,
  sequence_number                integer null,
  planned_for_date               date null,
  due_date                       date null,
  assignment_status              text not null default 'planned' check (
    assignment_status in ('planned', 'completed', 'skipped', 'cancelled')
  ),
  assigned_at                    timestamptz not null default now(),
  assigned_by_profile_id         uuid not null references public.profiles(id) on delete restrict,
  rescheduled_at                 timestamptz null,
  rescheduled_by_profile_id      uuid null references public.profiles(id) on delete set null,
  completed_at                   timestamptz null,
  completed_by_profile_id        uuid null references public.profiles(id) on delete set null,
  completed_household_meeting_id uuid null references public.household_meetings(id) on delete set null,
  skipped_at                     timestamptz null,
  skipped_by_profile_id          uuid null references public.profiles(id) on delete set null,
  cancelled_at                   timestamptz null,
  cancelled_by_profile_id        uuid null references public.profiles(id) on delete set null,
  resolution_reason_code         text null check (
    resolution_reason_code is null or resolution_reason_code in ('schedule_change', 'topic_replaced', 'not_applicable', 'other')
  ),
  resolution_notes               text null,
  created_at                     timestamptz not null default now(),
  updated_at                     timestamptz not null default now(),
  created_by_profile_id          uuid null references public.profiles(id) on delete set null,
  updated_by_profile_id          uuid null references public.profiles(id) on delete set null
);

create index if not exists idx_hh_topic_assignments_node_status
  on public.household_topic_assignments (household_node_id, assignment_status);

create index if not exists idx_hh_topic_assignments_org_node
  on public.household_topic_assignments (organization_id, household_node_id);

create index if not exists idx_hh_topic_assignments_meeting
  on public.household_topic_assignments (completed_household_meeting_id);

-- Prevent two identical planned assignments for the exact same household, topic, and date
create unique index if not exists idx_hh_topic_planned_unique
  on public.household_topic_assignments (household_node_id, topic_id, planned_for_date)
  where (assignment_status = 'planned' and planned_for_date is not null);

alter table public.household_topic_assignments enable row level security;

create policy hh_topic_assignments_read_policy
  on public.household_topic_assignments
  for select
  to authenticated
  using (
    private.has_organization_access(organization_id)
    and private.can_access_household('households.formation.view', organization_id, household_node_id)
  );

-- -----------------------------------------------------------------------------
-- 3. Seed Initial Standard Formation Topics (Shared across organizations)
-- -----------------------------------------------------------------------------

insert into public.formation_topics (
  organization_id,
  title,
  short_title,
  topic_code,
  description,
  objectives,
  source_type,
  scripture_reference,
  recommended_duration_minutes,
  recommended_pastoral_level,
  sort_order,
  is_active
)
values
  (
    null,
    'God''s Love and His Plan for Us',
    'God''s Love',
    'PFO-01',
    'Foundational teaching on the infinite, unconditional love of God and His eternal plan of salvation for humanity.',
    'Understand God''s personal love and respond with renewed trust in His divine providence.',
    'official_formation',
    'John 3:16, Jeremiah 29:11',
    45,
    'member',
    1,
    true
  ),
  (
    null,
    'Who is Jesus Christ?',
    'Jesus Christ',
    'PFO-02',
    'Exploration of the person of Jesus Christ as true God and true man, Lord, Savior, and Redeemer.',
    'Proclaim Jesus Christ as personal Lord and Savior in daily life.',
    'official_formation',
    'Philippians 2:5-11, Matthew 16:13-17',
    45,
    'member',
    2,
    true
  ),
  (
    null,
    'Repentance and Faith',
    'Repentance & Faith',
    'PFO-03',
    'Understanding the call to conversion, turning away from sin, and placing unwavering faith in Christ.',
    'Identify areas needing metanoia and embrace the sacrament of reconciliation and grace.',
    'official_formation',
    'Mark 1:14-15, Romans 10:9-10',
    45,
    'member',
    3,
    true
  ),
  (
    null,
    'The Christian Family as a Domestic Church',
    'Domestic Church',
    'HT-FAM-01',
    'Pastoral household reflection on sanctifying the home and establishing Christ at the center of family life.',
    'Equip couples and families to foster prayer, unity, and mutual forgiveness in the home.',
    'household_topic',
    'Joshua 24:15, Colossians 3:18-21',
    40,
    'member',
    4,
    true
  ),
  (
    null,
    'Living as a Covenant Community',
    'Covenant Community',
    'HT-COM-01',
    'Reflection on our call to brotherhood, sisterhood, mutual accountability, and honoring community agreements.',
    'Deepen commitment to household brothers and sisters through joyful fellowship and service.',
    'household_topic',
    'Acts 2:42-47, Hebrews 10:24-25',
    40,
    'member',
    5,
    true
  ),
  (
    null,
    'Serving in the Vineyard: Evangelization and Mission',
    'Evangelization',
    'HT-MIS-01',
    'Focus on the missionary identity of every Christian and proclaiming the Good News to all creation.',
    'Inspire active participation in evangelistic outreaches, ministries, and community mission.',
    'mission_topic',
    'Matthew 28:18-20, Romans 1:16',
    40,
    'member',
    6,
    true
  ),
  (
    null,
    'Scripture Reflection: Walking in the Light',
    'Walking in Light',
    'SR-01',
    'Guided household reflection on Sacred Scripture and abiding in communion with God.',
    'Learn practical approaches to daily Scripture reading and living as children of light.',
    'scripture_reflection',
    '1 John 1:5-7, Psalm 119:105',
    35,
    'member',
    7,
    true
  ),
  (
    null,
    'Shepherd After God''s Heart: Servant Leadership',
    'Shepherd Leaders',
    'HT-LEAD-01',
    'Special formation topic for Household, Unit, and Chapter Servant Leaders on pastoral vigilance and care.',
    'Strengthen leaders in humility, intercessory prayer, and tender pastoral oversight.',
    'household_topic',
    'Jeremiah 3:15, 1 Peter 5:1-4',
    45,
    'unit',
    8,
    true
  )
on conflict do nothing;

-- -----------------------------------------------------------------------------
-- 4. Helper Function: private.compute_household_formation_status
-- -----------------------------------------------------------------------------

create or replace function private.compute_household_formation_status(
  p_household_node_id uuid
)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_overdue_count  integer;
  v_due_count      integer;
  v_planned_count  integer;
  v_last_comp_date date;
begin
  -- 1. Check planned topics
  select
    count(*) filter (where planned_for_date is not null and planned_for_date < current_date),
    count(*) filter (where planned_for_date is not null and planned_for_date = current_date),
    count(*) filter (where planned_for_date is null or planned_for_date > current_date)
  into v_overdue_count, v_due_count, v_planned_count
  from public.household_topic_assignments
  where household_node_id = p_household_node_id
    and assignment_status = 'planned';

  if v_overdue_count > 0 then
    return 'topic_overdue';
  end if;

  if v_due_count > 0 then
    return 'topic_due';
  end if;

  if v_planned_count > 0 then
    return 'planned';
  end if;

  -- 2. No planned topics: check last completed topic
  select max(coalesce(m.meeting_date, a.completed_at::date))
  into v_last_comp_date
  from public.household_topic_assignments a
  left join public.household_meetings m on m.id = a.completed_household_meeting_id
  where a.household_node_id = p_household_node_id
    and a.assignment_status = 'completed';

  if v_last_comp_date is not null and v_last_comp_date >= (current_date - 35) then
    return 'up_to_date';
  end if;

  return 'no_plan';
end;
$$;

-- -----------------------------------------------------------------------------
-- 5. RPC: public.search_formation_topics
-- -----------------------------------------------------------------------------

create or replace function public.search_formation_topics(
  p_organization_id       uuid,
  p_search                text    default null,
  p_source_type           text    default null,
  p_pastoral_level        text    default null,
  p_limit                 integer default 50,
  p_offset                integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id   uuid;
  v_limit        integer;
  v_offset       integer;
  v_search_clean text;
  v_total        integer;
  v_topics       jsonb;
begin
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  if not (
    private.has_permission('households.formation.view', p_organization_id)
    or private.has_permission('households.formation.manage', p_organization_id)
  ) then
    raise exception using errcode = '42501', message = 'You do not have permission to view formation topics.';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_offset := greatest(coalesce(p_offset, 0), 0);
  v_search_clean := nullif(trim(p_search), '');

  select count(*)::integer into v_total
  from public.formation_topics ft
  where (ft.organization_id is null or ft.organization_id = p_organization_id)
    and ft.is_active = true
    and (p_source_type is null or ft.source_type = p_source_type)
    and (p_pastoral_level is null or ft.recommended_pastoral_level is null or ft.recommended_pastoral_level = p_pastoral_level)
    and (
      v_search_clean is null
      or ft.title ilike '%' || v_search_clean || '%'
      or ft.topic_code ilike '%' || v_search_clean || '%'
      or ft.short_title ilike '%' || v_search_clean || '%'
      or ft.scripture_reference ilike '%' || v_search_clean || '%'
    );

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',                           ft.id,
        'organization_id',              ft.organization_id,
        'title',                        ft.title,
        'short_title',                  ft.short_title,
        'topic_code',                   ft.topic_code,
        'description',                  ft.description,
        'objectives',                   ft.objectives,
        'source_type',                  ft.source_type,
        'scripture_reference',          ft.scripture_reference,
        'recommended_duration_minutes', ft.recommended_duration_minutes,
        'recommended_pastoral_level',   ft.recommended_pastoral_level,
        'sort_order',                   ft.sort_order,
        'is_active',                    ft.is_active
      )
      order by ft.sort_order asc nulls last, ft.title asc
    ),
    '[]'::jsonb
  ) into v_topics
  from (
    select *
    from public.formation_topics ft
    where (ft.organization_id is null or ft.organization_id = p_organization_id)
      and ft.is_active = true
      and (p_source_type is null or ft.source_type = p_source_type)
      and (p_pastoral_level is null or ft.recommended_pastoral_level is null or ft.recommended_pastoral_level = p_pastoral_level)
      and (
        v_search_clean is null
        or ft.title ilike '%' || v_search_clean || '%'
        or ft.topic_code ilike '%' || v_search_clean || '%'
        or ft.short_title ilike '%' || v_search_clean || '%'
        or ft.scripture_reference ilike '%' || v_search_clean || '%'
      )
    order by ft.sort_order asc nulls last, ft.title asc
    limit v_limit
    offset v_offset
  ) ft;

  return jsonb_build_object(
    'total_count', v_total,
    'limit',       v_limit,
    'offset',      v_offset,
    'topics',      v_topics
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 6. RPC: public.create_formation_topic (Catalog Management)
-- -----------------------------------------------------------------------------

create or replace function public.create_formation_topic(
  p_organization_id            uuid,
  p_title                      text,
  p_source_type                text    default 'household_topic',
  p_short_title                text    default null,
  p_topic_code                 text    default null,
  p_description                text    default null,
  p_objectives                 text    default null,
  p_scripture_reference        text    default null,
  p_recommended_duration_minutes integer default null,
  p_recommended_pastoral_level text    default null,
  p_sort_order                 integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id uuid;
  v_topic_id   uuid;
  v_title      text;
  v_topic      public.formation_topics%rowtype;
begin
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  -- Catalog management requires organization administrator or dedicated manage permission
  if not (
    private.is_organization_administrator(v_profile_id, p_organization_id)
    or private.has_permission('households.formation.manage', p_organization_id)
  ) then
    raise exception using errcode = '42501', message = 'You do not have permission to create formation topics.';
  end if;

  v_title := trim(coalesce(p_title, ''));
  if v_title = '' then
    raise exception using errcode = '22023', message = 'Topic title is required.';
  end if;

  if p_source_type not in (
    'official_formation',
    'household_topic',
    'scripture_reflection',
    'assembly_follow_up',
    'mission_topic',
    'special_topic',
    'other'
  ) then
    raise exception using errcode = '22023', message = 'Invalid topic source type.';
  end if;

  if p_recommended_pastoral_level is not null and p_recommended_pastoral_level not in (
    'member', 'unit', 'chapter', 'area', 'fraternal'
  ) then
    raise exception using errcode = '22023', message = 'Invalid recommended pastoral level.';
  end if;

  insert into public.formation_topics (
    organization_id,
    title,
    short_title,
    topic_code,
    description,
    objectives,
    source_type,
    scripture_reference,
    recommended_duration_minutes,
    recommended_pastoral_level,
    sort_order,
    is_active,
    created_at,
    updated_at,
    created_by_profile_id,
    updated_by_profile_id
  )
  values (
    p_organization_id,
    v_title,
    nullif(trim(p_short_title), ''),
    nullif(trim(p_topic_code), ''),
    nullif(trim(p_description), ''),
    nullif(trim(p_objectives), ''),
    p_source_type,
    nullif(trim(p_scripture_reference), ''),
    p_recommended_duration_minutes,
    p_recommended_pastoral_level,
    p_sort_order,
    true,
    now(),
    now(),
    v_profile_id,
    v_profile_id
  )
  returning * into v_topic;

  -- Audit event
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'formation_topic.created',
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'formation_topic',
    p_entity_id        => v_topic.id,
    p_action           => 'create',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'topic_id',    v_topic.id,
      'title',       v_topic.title,
      'source_type', v_topic.source_type,
      'topic_code',  v_topic.topic_code
    )
  );

  return jsonb_build_object(
    'id',                           v_topic.id,
    'organization_id',              v_topic.organization_id,
    'title',                        v_topic.title,
    'short_title',                  v_topic.short_title,
    'topic_code',                   v_topic.topic_code,
    'description',                  v_topic.description,
    'objectives',                   v_topic.objectives,
    'source_type',                  v_topic.source_type,
    'scripture_reference',          v_topic.scripture_reference,
    'recommended_duration_minutes', v_topic.recommended_duration_minutes,
    'recommended_pastoral_level',   v_topic.recommended_pastoral_level,
    'sort_order',                   v_topic.sort_order,
    'is_active',                    v_topic.is_active,
    'created_at',                   v_topic.created_at
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 7. RPC: public.assign_household_topic
-- -----------------------------------------------------------------------------

create or replace function public.assign_household_topic(
  p_organization_id   uuid,
  p_household_node_id uuid,
  p_topic_id          uuid,
  p_planned_for_date  date    default null,
  p_sequence_number   integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id      uuid;
  v_household_node  public.governance_nodes%rowtype;
  v_topic           public.formation_topics%rowtype;
  v_assignment      public.household_topic_assignments%rowtype;
begin
  -- 1. Authentication check
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  -- 2. Organization access check
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  -- 3. Permission check
  if not private.has_permission('households.formation.manage', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to manage household formation topics.';
  end if;

  -- 4. Household existence and active status
  select * into v_household_node
  from public.governance_nodes
  where id = p_household_node_id
    and organization_id = p_organization_id;

  if not found or v_household_node.lifecycle_status != 'active' then
    raise exception using errcode = 'P0002', message = 'Household not found or not active.';
  end if;

  -- 5. Scope check
  if not private.can_access_household('households.formation.manage', p_organization_id, p_household_node_id) then
    raise exception using errcode = 'P0002', message = 'Household is not within your authorized pastoral scope.';
  end if;

  -- 6. DIRECT SERVANT-LEADER RESPONSIBILITY GUARD (Phase 6B-9 rule)
  if not private.is_organization_administrator(v_profile_id, p_organization_id) then
    if not private.profile_has_direct_servant_leader_responsibility(v_profile_id, p_organization_id, p_household_node_id) then
      raise exception using errcode = '42501',
        message = 'You do not have direct servant leader responsibility for this household.';
    end if;
  end if;

  -- 7. Topic existence and active status
  select * into v_topic
  from public.formation_topics
  where id = p_topic_id
    and (organization_id is null or organization_id = p_organization_id);

  if not found or not v_topic.is_active then
    raise exception using errcode = '22023', message = 'Formation topic not found or is inactive.';
  end if;

  -- 8. Duplicate check: prevent duplicate planned assignment for same date if date is provided
  if p_planned_for_date is not null and exists (
    select 1
    from public.household_topic_assignments
    where household_node_id = p_household_node_id
      and topic_id = p_topic_id
      and planned_for_date = p_planned_for_date
      and assignment_status = 'planned'
  ) then
    raise exception using errcode = '23505',
      message = 'This topic is already planned for the specified date.';
  end if;

  -- 9. Insert assignment
  insert into public.household_topic_assignments (
    organization_id,
    household_node_id,
    topic_id,
    sequence_number,
    planned_for_date,
    assignment_status,
    assigned_at,
    assigned_by_profile_id,
    created_at,
    updated_at,
    created_by_profile_id,
    updated_by_profile_id
  )
  values (
    p_organization_id,
    p_household_node_id,
    p_topic_id,
    p_sequence_number,
    p_planned_for_date,
    'planned',
    now(),
    v_profile_id,
    now(),
    now(),
    v_profile_id,
    v_profile_id
  )
  returning * into v_assignment;

  -- 10. Audit event
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'household_topic.assigned',
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'household_topic_assignment',
    p_entity_id        => v_assignment.id,
    p_action           => 'assign',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'assignment_id',      v_assignment.id,
      'household_node_id',  p_household_node_id,
      'topic_id',           p_topic_id,
      'topic_title',        v_topic.title,
      'planned_for_date',   p_planned_for_date,
      'sequence_number',    p_sequence_number
    )
  );

  return jsonb_build_object(
    'assignment_id',      v_assignment.id,
    'household_node_id',  v_assignment.household_node_id,
    'topic_id',           v_assignment.topic_id,
    'topic_title',        v_topic.title,
    'topic_code',         v_topic.topic_code,
    'source_type',        v_topic.source_type,
    'assignment_status',  v_assignment.assignment_status,
    'planned_for_date',   v_assignment.planned_for_date,
    'sequence_number',    v_assignment.sequence_number,
    'assigned_at',        v_assignment.assigned_at
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 8. RPC: public.reschedule_household_topic
-- -----------------------------------------------------------------------------

create or replace function public.reschedule_household_topic(
  p_organization_id                uuid,
  p_household_topic_assignment_id  uuid,
  p_planned_for_date               date,
  p_reason                         text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id uuid;
  v_assignment public.household_topic_assignments%rowtype;
  v_old_date   date;
begin
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  if not private.has_permission('households.formation.manage', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to manage household formation topics.';
  end if;

  if p_planned_for_date is null then
    raise exception using errcode = '22023', message = 'New planned date is required.';
  end if;

  select * into v_assignment
  from public.household_topic_assignments
  where id = p_household_topic_assignment_id
    and organization_id = p_organization_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Topic assignment not found.';
  end if;

  if v_assignment.assignment_status != 'planned' then
    raise exception using errcode = '22023', message = 'Only planned topic assignments can be rescheduled.';
  end if;

  -- Direct write guard
  if not private.is_organization_administrator(v_profile_id, p_organization_id) then
    if not private.profile_has_direct_servant_leader_responsibility(v_profile_id, p_organization_id, v_assignment.household_node_id) then
      raise exception using errcode = '42501',
        message = 'You do not have direct servant leader responsibility for this household.';
    end if;
  end if;

  v_old_date := v_assignment.planned_for_date;

  update public.household_topic_assignments
  set planned_for_date          = p_planned_for_date,
      rescheduled_at            = now(),
      rescheduled_by_profile_id = v_profile_id,
      resolution_reason_code    = 'schedule_change',
      resolution_notes          = nullif(trim(p_reason), ''),
      updated_at                = now(),
      updated_by_profile_id     = v_profile_id
  where id = v_assignment.id
  returning * into v_assignment;

  -- Audit event
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'household_topic.rescheduled',
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'household_topic_assignment',
    p_entity_id        => v_assignment.id,
    p_action           => 'update',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'assignment_id',        v_assignment.id,
      'household_node_id',    v_assignment.household_node_id,
      'previous_planned_date', v_old_date,
      'new_planned_date',     p_planned_for_date,
      'reason',               p_reason
    )
  );

  return jsonb_build_object(
    'assignment_id',        v_assignment.id,
    'household_node_id',    v_assignment.household_node_id,
    'topic_id',             v_assignment.topic_id,
    'assignment_status',    v_assignment.assignment_status,
    'previous_planned_date', v_old_date,
    'planned_for_date',     v_assignment.planned_for_date,
    'rescheduled_at',       v_assignment.rescheduled_at
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 9. RPC: public.complete_household_topic
-- -----------------------------------------------------------------------------

create or replace function public.complete_household_topic(
  p_organization_id               uuid,
  p_household_topic_assignment_id uuid,
  p_household_meeting_id          uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id uuid;
  v_assignment public.household_topic_assignments%rowtype;
  v_meeting    public.household_meetings%rowtype;
begin
  -- 1. Authentication check
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  -- 2. Organization access check
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  -- 3. Permission check
  if not private.has_permission('households.formation.manage', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to manage household formation topics.';
  end if;

  if p_household_meeting_id is null then
    raise exception using errcode = '22023', message = 'Household meeting ID is required to record topic completion.';
  end if;

  -- 4. Assignment lookup
  select * into v_assignment
  from public.household_topic_assignments
  where id = p_household_topic_assignment_id
    and organization_id = p_organization_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Topic assignment not found.';
  end if;

  if v_assignment.assignment_status = 'completed' then
    raise exception using errcode = '22023', message = 'Topic assignment is already completed.';
  end if;

  if v_assignment.assignment_status in ('skipped', 'cancelled') then
    raise exception using errcode = '22023', message = 'Cannot complete a skipped or cancelled topic assignment.';
  end if;

  -- 5. Direct write guard
  if not private.is_organization_administrator(v_profile_id, p_organization_id) then
    if not private.profile_has_direct_servant_leader_responsibility(v_profile_id, p_organization_id, v_assignment.household_node_id) then
      raise exception using errcode = '42501',
        message = 'You do not have direct servant leader responsibility for this household.';
    end if;
  end if;

  -- 6. Meeting verification
  select * into v_meeting
  from public.household_meetings
  where id = p_household_meeting_id
    and organization_id = p_organization_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Household meeting not found.';
  end if;

  -- Cross-household meeting linkage forbidden
  if v_meeting.household_node_id != v_assignment.household_node_id then
    raise exception using errcode = '22023',
      message = 'Household meeting does not belong to the household assigned to this topic.';
  end if;

  if v_meeting.meeting_status = 'cancelled' then
    raise exception using errcode = '22023', message = 'Cannot link a cancelled household meeting.';
  end if;

  -- 7. Update assignment to completed
  update public.household_topic_assignments
  set assignment_status              = 'completed',
      completed_at                   = now(),
      completed_by_profile_id        = v_profile_id,
      completed_household_meeting_id = v_meeting.id,
      updated_at                     = now(),
      updated_by_profile_id          = v_profile_id
  where id = v_assignment.id
  returning * into v_assignment;

  -- 8. Audit event
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'household_topic.completed',
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'household_topic_assignment',
    p_entity_id        => v_assignment.id,
    p_action           => 'complete',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'assignment_id',                 v_assignment.id,
      'household_node_id',             v_assignment.household_node_id,
      'topic_id',                      v_assignment.topic_id,
      'completed_household_meeting_id', v_meeting.id,
      'meeting_date',                  v_meeting.meeting_date
    )
  );

  return jsonb_build_object(
    'assignment_id',                 v_assignment.id,
    'household_node_id',             v_assignment.household_node_id,
    'topic_id',                      v_assignment.topic_id,
    'assignment_status',             v_assignment.assignment_status,
    'completed_at',                  v_assignment.completed_at,
    'completed_household_meeting_id', v_assignment.completed_household_meeting_id,
    'meeting_date',                  v_meeting.meeting_date
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 10. RPC: public.skip_household_topic
-- -----------------------------------------------------------------------------

create or replace function public.skip_household_topic(
  p_organization_id               uuid,
  p_household_topic_assignment_id uuid,
  p_reason_code                   text default 'not_applicable',
  p_notes                         text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id  uuid;
  v_assignment  public.household_topic_assignments%rowtype;
  v_reason_code text;
begin
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  if not private.has_permission('households.formation.manage', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to manage household formation topics.';
  end if;

  v_reason_code := coalesce(p_reason_code, 'not_applicable');
  if v_reason_code not in ('schedule_change', 'topic_replaced', 'not_applicable', 'other') then
    raise exception using errcode = '22023', message = 'Invalid resolution reason code.';
  end if;

  select * into v_assignment
  from public.household_topic_assignments
  where id = p_household_topic_assignment_id
    and organization_id = p_organization_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Topic assignment not found.';
  end if;

  if v_assignment.assignment_status != 'planned' then
    raise exception using errcode = '22023', message = 'Only planned topic assignments can be skipped.';
  end if;

  -- Direct write guard
  if not private.is_organization_administrator(v_profile_id, p_organization_id) then
    if not private.profile_has_direct_servant_leader_responsibility(v_profile_id, p_organization_id, v_assignment.household_node_id) then
      raise exception using errcode = '42501',
        message = 'You do not have direct servant leader responsibility for this household.';
    end if;
  end if;

  update public.household_topic_assignments
  set assignment_status      = 'skipped',
      skipped_at             = now(),
      skipped_by_profile_id  = v_profile_id,
      resolution_reason_code = v_reason_code,
      resolution_notes       = nullif(trim(p_notes), ''),
      updated_at             = now(),
      updated_by_profile_id  = v_profile_id
  where id = v_assignment.id
  returning * into v_assignment;

  -- Audit event
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'household_topic.skipped',
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'household_topic_assignment',
    p_entity_id        => v_assignment.id,
    p_action           => 'skip',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'assignment_id',        v_assignment.id,
      'household_node_id',    v_assignment.household_node_id,
      'topic_id',             v_assignment.topic_id,
      'resolution_reason_code', v_reason_code
    )
  );

  return jsonb_build_object(
    'assignment_id',        v_assignment.id,
    'household_node_id',    v_assignment.household_node_id,
    'topic_id',             v_assignment.topic_id,
    'assignment_status',    v_assignment.assignment_status,
    'skipped_at',           v_assignment.skipped_at,
    'resolution_reason_code', v_assignment.resolution_reason_code
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 11. RPC: public.cancel_household_topic_assignment
-- -----------------------------------------------------------------------------

create or replace function public.cancel_household_topic_assignment(
  p_organization_id               uuid,
  p_household_topic_assignment_id uuid,
  p_reason_code                   text default 'schedule_change',
  p_notes                         text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id  uuid;
  v_assignment  public.household_topic_assignments%rowtype;
  v_reason_code text;
begin
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  if not private.has_permission('households.formation.manage', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to manage household formation topics.';
  end if;

  v_reason_code := coalesce(p_reason_code, 'schedule_change');
  if v_reason_code not in ('schedule_change', 'topic_replaced', 'not_applicable', 'other') then
    raise exception using errcode = '22023', message = 'Invalid resolution reason code.';
  end if;

  select * into v_assignment
  from public.household_topic_assignments
  where id = p_household_topic_assignment_id
    and organization_id = p_organization_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Topic assignment not found.';
  end if;

  if v_assignment.assignment_status != 'planned' then
    raise exception using errcode = '22023', message = 'Only planned topic assignments can be cancelled.';
  end if;

  -- Direct write guard
  if not private.is_organization_administrator(v_profile_id, p_organization_id) then
    if not private.profile_has_direct_servant_leader_responsibility(v_profile_id, p_organization_id, v_assignment.household_node_id) then
      raise exception using errcode = '42501',
        message = 'You do not have direct servant leader responsibility for this household.';
    end if;
  end if;

  update public.household_topic_assignments
  set assignment_status      = 'cancelled',
      cancelled_at           = now(),
      cancelled_by_profile_id = v_profile_id,
      resolution_reason_code = v_reason_code,
      resolution_notes       = nullif(trim(p_notes), ''),
      updated_at             = now(),
      updated_by_profile_id  = v_profile_id
  where id = v_assignment.id
  returning * into v_assignment;

  -- Audit event
  perform private.write_audit_event(
    p_organization_id  => p_organization_id,
    p_event_code       => 'household_topic.cancelled',
    p_event_category   => 'governance',
    p_actor_profile_id => v_profile_id,
    p_entity_type      => 'household_topic_assignment',
    p_entity_id        => v_assignment.id,
    p_action           => 'cancel',
    p_outcome          => 'success',
    p_access_reason    => null,
    p_correlation_id   => null,
    p_metadata         => jsonb_build_object(
      'assignment_id',        v_assignment.id,
      'household_node_id',    v_assignment.household_node_id,
      'topic_id',             v_assignment.topic_id,
      'resolution_reason_code', v_reason_code
    )
  );

  return jsonb_build_object(
    'assignment_id',        v_assignment.id,
    'household_node_id',    v_assignment.household_node_id,
    'topic_id',             v_assignment.topic_id,
    'assignment_status',    v_assignment.assignment_status,
    'cancelled_at',         v_assignment.cancelled_at,
    'resolution_reason_code', v_assignment.resolution_reason_code
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 12. RPC: public.get_household_formation_plan
-- -----------------------------------------------------------------------------

create or replace function public.get_household_formation_plan(
  p_organization_id   uuid,
  p_household_node_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id        uuid;
  v_status            text;
  v_next_topic        jsonb;
  v_upcoming_topics   jsonb;
  v_last_topic        jsonb;
  v_last_date         date;
  v_planned_count     integer;
  v_completed_count   integer;
begin
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  if not (
    private.has_permission('households.formation.view', p_organization_id)
    or private.has_permission('households.formation.manage', p_organization_id)
  ) then
    raise exception using errcode = '42501', message = 'You do not have permission to view household formation.';
  end if;

  if not private.can_access_household('households.formation.view', p_organization_id, p_household_node_id) then
    raise exception using errcode = 'P0002', message = 'Household is not within your authorized pastoral scope.';
  end if;

  -- Compute factual formation status
  v_status := private.compute_household_formation_status(p_household_node_id);

  -- Counts
  select
    count(*) filter (where assignment_status = 'planned'),
    count(*) filter (where assignment_status = 'completed')
  into v_planned_count, v_completed_count
  from public.household_topic_assignments
  where household_node_id = p_household_node_id;

  -- Next planned topic (closest planned date or lowest sequence)
  select jsonb_build_object(
    'assignment_id',               a.id,
    'topic_id',                    ft.id,
    'title',                       ft.title,
    'short_title',                 ft.short_title,
    'topic_code',                  ft.topic_code,
    'source_type',                 ft.source_type,
    'scripture_reference',         ft.scripture_reference,
    'planned_for_date',            a.planned_for_date,
    'sequence_number',             a.sequence_number,
    'recommended_duration_minutes', ft.recommended_duration_minutes
  ) into v_next_topic
  from public.household_topic_assignments a
  join public.formation_topics ft on ft.id = a.topic_id
  where a.household_node_id = p_household_node_id
    and a.assignment_status = 'planned'
  order by a.planned_for_date asc nulls last, a.sequence_number asc nulls last, a.created_at asc
  limit 1;

  -- Upcoming planned topics (up to 5)
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'assignment_id',               a.id,
        'topic_id',                    ft.id,
        'title',                       ft.title,
        'short_title',                 ft.short_title,
        'topic_code',                  ft.topic_code,
        'source_type',                 ft.source_type,
        'scripture_reference',         ft.scripture_reference,
        'planned_for_date',            a.planned_for_date,
        'sequence_number',             a.sequence_number,
        'recommended_duration_minutes', ft.recommended_duration_minutes
      )
      order by a.planned_for_date asc nulls last, a.sequence_number asc nulls last, a.created_at asc
    ),
    '[]'::jsonb
  ) into v_upcoming_topics
  from (
    select a.*, ft.title, ft.short_title, ft.topic_code, ft.source_type, ft.scripture_reference, ft.recommended_duration_minutes
    from public.household_topic_assignments a
    join public.formation_topics ft on ft.id = a.topic_id
    where a.household_node_id = p_household_node_id
      and a.assignment_status = 'planned'
    order by a.planned_for_date asc nulls last, a.sequence_number asc nulls last, a.created_at asc
    limit 5
  ) a
  join public.formation_topics ft on ft.id = a.topic_id;

  -- Last completed topic
  select
    jsonb_build_object(
      'assignment_id',                 a.id,
      'topic_id',                      ft.id,
      'title',                         ft.title,
      'short_title',                   ft.short_title,
      'topic_code',                    ft.topic_code,
      'source_type',                   ft.source_type,
      'completed_at',                  a.completed_at,
      'completed_household_meeting_id', a.completed_household_meeting_id,
      'meeting_date',                  m.meeting_date
    ),
    coalesce(m.meeting_date, a.completed_at::date)
  into v_last_topic, v_last_date
  from public.household_topic_assignments a
  join public.formation_topics ft on ft.id = a.topic_id
  left join public.household_meetings m on m.id = a.completed_household_meeting_id
  where a.household_node_id = p_household_node_id
    and a.assignment_status = 'completed'
  order by a.completed_at desc
  limit 1;

  return jsonb_build_object(
    'household_id',        p_household_node_id,
    'formation_status',    v_status,
    'next_topic',          v_next_topic,
    'upcoming_topics',     v_upcoming_topics,
    'last_completed_topic', v_last_topic,
    'last_completed_date', v_last_date,
    'planned_count',       coalesce(v_planned_count, 0),
    'completed_count',     coalesce(v_completed_count, 0)
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 13. RPC: public.get_household_topic_history
-- -----------------------------------------------------------------------------

create or replace function public.get_household_topic_history(
  p_organization_id   uuid,
  p_household_node_id uuid,
  p_limit             integer default 20,
  p_offset            integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id uuid;
  v_limit      integer;
  v_offset     integer;
  v_total      integer;
  v_history    jsonb;
begin
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  if not (
    private.has_permission('households.formation.view', p_organization_id)
    or private.has_permission('households.formation.manage', p_organization_id)
  ) then
    raise exception using errcode = '42501', message = 'You do not have permission to view household formation history.';
  end if;

  if not private.can_access_household('households.formation.view', p_organization_id, p_household_node_id) then
    raise exception using errcode = 'P0002', message = 'Household is not within your authorized pastoral scope.';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 20), 1), 100);
  v_offset := greatest(coalesce(p_offset, 0), 0);

  select count(*)::integer into v_total
  from public.household_topic_assignments a
  where a.household_node_id = p_household_node_id
    and a.organization_id = p_organization_id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'assignment_id',                 a.id,
        'topic_id',                      ft.id,
        'topic_title',                   ft.title,
        'topic_code',                    ft.topic_code,
        'source_type',                   ft.source_type,
        'scripture_reference',           ft.scripture_reference,
        'sequence_number',               a.sequence_number,
        'planned_for_date',              a.planned_for_date,
        'assignment_status',             a.assignment_status,
        'assigned_at',                   a.assigned_at,
        'completed_at',                  a.completed_at,
        'completed_household_meeting_id', a.completed_household_meeting_id,
        'meeting_date',                  m.meeting_date,
        'meeting_type',                  m.meeting_type,
        'resolution_reason_code',        a.resolution_reason_code
      )
      order by
        case a.assignment_status
          when 'planned' then 1
          when 'completed' then 2
          when 'skipped' then 3
          when 'cancelled' then 4
          else 5
        end asc,
        coalesce(a.completed_at, a.planned_for_date::timestamptz, a.created_at) desc
    ),
    '[]'::jsonb
  ) into v_history
  from (
    select *
    from public.household_topic_assignments
    where household_node_id = p_household_node_id
      and organization_id = p_organization_id
    order by
      case assignment_status
        when 'planned' then 1
        when 'completed' then 2
        when 'skipped' then 3
        when 'cancelled' then 4
        else 5
      end asc,
      coalesce(completed_at, planned_for_date::timestamptz, created_at) desc
    limit v_limit
    offset v_offset
  ) a
  join public.formation_topics ft on ft.id = a.topic_id
  left join public.household_meetings m on m.id = a.completed_household_meeting_id;

  return jsonb_build_object(
    'total_count', v_total,
    'limit',       v_limit,
    'offset',      v_offset,
    'history',     v_history
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 14. Update public.get_household_profile (Add formation_summary)
-- -----------------------------------------------------------------------------

create or replace function public.get_household_profile(
  p_organization_id uuid,
  p_household_id    uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id   uuid;
  v_has_id_perm  boolean;
  v_profile_data jsonb;
begin
  -- 1. Authentication check
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  -- 2. Organization access check
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  -- 3. Permission check
  if not private.has_permission('households.records.view', p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have permission to view household records.';
  end if;

  -- NON-ADMIN DELEGATED SERVANT LEADER DOUBLE-LOCK REQUIREMENT (Phase 6B-9)
  if not private.is_organization_administrator(v_profile_id, p_organization_id) then
    if exists (
      select 1
      from public.profile_role_assignments pra
      join public.app_roles ar on ar.id = pra.app_role_id
      where pra.organization_id = p_organization_id
        and pra.profile_id = v_profile_id
        and pra.assignment_status = 'active'
        and ar.code in (
          'household_servant_leader_access',
          'unit_servant_leader_access',
          'chapter_servant_leader_access',
          'area_servant_leader_access'
        )
    ) or exists (
      select 1
      from public.servant_leader_access_grants g
      where g.organization_id = p_organization_id
        and g.profile_id = v_profile_id
    ) then
      if not exists (
        select 1
        from public.servant_leader_access_grants g
        join public.leadership_assignments la on la.id = g.leadership_assignment_id
        where g.organization_id = p_organization_id
          and g.profile_id = v_profile_id
          and g.access_status = 'active'
          and g.effective_from <= current_date
          and (g.effective_to is null or g.effective_to >= current_date)
          and la.organization_id = p_organization_id
          and la.assignment_status = 'active'
          and la.effective_from <= current_date
          and (la.effective_to is null or la.effective_to >= current_date)
      ) then
        raise exception using errcode = '42501',
          message = 'Delegated servant leader application access requires an active, formally appointed leadership assignment.';
      end if;
    end if;
  end if;

  -- 4. Pastoral scope access check
  if not private.can_access_household('households.records.view', p_organization_id, p_household_id) then
    raise exception using errcode = 'P0002', message = 'Household not found or not accessible.';
  end if;

  v_has_id_perm := private.has_permission('members.identifiers.view', p_organization_id);

  with household_identity as (
    select
      gn.id,
      gn.name,
      gn.code,
      gn.lifecycle_status,
      h.household_category,
      h.pastoral_level,
      h.pastoral_level_label,
      h.leadership_source,
      h.effective_from,
      h.effective_to,
      h.meeting_frequency,
      h.meeting_day_of_week,
      h.meeting_start_time,
      h.meeting_timezone_name,
      h.meeting_location_type,
      h.target_member_count,
      h.maximum_member_count,
      h.accepts_new_members,
      h.language_code,
      h.is_couple_household
    from public.governance_nodes gn
    join public.households h
      on h.id = gn.id
     and h.organization_id = gn.organization_id
    where gn.id = p_household_id
      and gn.organization_id = p_organization_id
  ),
  parent_gov as (
    select
      gn_p.id as parent_node_id,
      gn_p.name as parent_node_name,
      gn_p.code as parent_node_code,
      gnt_p.code as parent_node_type
    from public.governance_node_relationships r
    join public.governance_nodes gn_p
      on gn_p.id = r.parent_node_id
     and gn_p.organization_id = r.organization_id
    join public.governance_node_types gnt_p
      on gnt_p.id = gn_p.governance_node_type_id
     and gnt_p.organization_id = gn_p.organization_id
    where r.organization_id = p_organization_id
      and r.child_node_id = p_household_id
      and r.relationship_type = 'primary_parent'
      and r.relationship_status = 'active'
      and r.effective_from <= current_date
      and (r.effective_to is null or r.effective_to >= current_date)
    order by r.created_at desc
    limit 1
  ),
  active_members as (
    select
      hm.id as household_membership_id,
      m.id as member_id,
      case when v_has_id_perm then m.member_number else null end as member_number,
      m.display_name,
      hm.membership_status,
      hm.membership_role,
      hm.is_primary,
      hm.effective_from,
      hm.effective_to
    from public.household_memberships hm
    join public.members m
      on m.id = hm.member_id
     and m.organization_id = hm.organization_id
    where hm.household_node_id = p_household_id
      and hm.organization_id = p_organization_id
      and hm.membership_status in ('active', 'temporary')
      and hm.effective_from <= current_date
      and (hm.effective_to is null or hm.effective_to >= current_date)
      and m.record_status = 'active'
    order by m.display_name asc
  ),
  direct_assignments as (
    select
      la.id as leadership_assignment_id,
      la.member_id,
      m.display_name,
      lrd.code as leadership_role_code,
      lrd.name as leadership_role_name,
      la.assignment_status,
      la.effective_from,
      la.effective_to,
      la.governance_node_id,
      1 as priority
    from public.leadership_assignments la
    join public.leadership_role_definitions lrd
      on lrd.id = la.leadership_role_definition_id
    join public.members m
      on m.id = la.member_id
     and m.organization_id = la.organization_id
    where la.organization_id = p_organization_id
      and la.governance_node_id = p_household_id
      and la.assignment_status = 'active'
      and la.effective_from <= current_date
      and (la.effective_to is null or la.effective_to >= current_date)
      and m.record_status = 'active'
  ),
  parent_assignments as (
    select
      la.id as leadership_assignment_id,
      la.member_id,
      m.display_name,
      lrd.code as leadership_role_code,
      lrd.name as leadership_role_name,
      la.assignment_status,
      la.effective_from,
      la.effective_to,
      la.governance_node_id,
      2 as priority
    from public.leadership_assignments la
    join public.leadership_role_definitions lrd
      on lrd.id = la.leadership_role_definition_id
    join public.members m
      on m.id = la.member_id
     and m.organization_id = la.organization_id
    cross join parent_gov pg
    cross join household_identity hi
    where la.organization_id = p_organization_id
      and la.governance_node_id = pg.parent_node_id
      and la.assignment_status = 'active'
      and la.effective_from <= current_date
      and (la.effective_to is null or la.effective_to >= current_date)
      and m.record_status = 'active'
      and (
        (hi.pastoral_level = 'unit' and lrd.code = 'unit_servant_leader')
        or (hi.pastoral_level = 'chapter' and lrd.code = 'chapter_servant_leader')
        or (hi.pastoral_level = 'area' and lrd.code = 'area_servant_leader')
      )
  ),
  derived_leaders as (
    select * from direct_assignments
    union all
    select * from parent_assignments
    where not exists (select 1 from direct_assignments)
  ),
  couple_leaders as (
    select
      lead.member_id as servant_member_id,
      lead.display_name as servant_display_name,
      target_spouse.member_id as spouse_member_id,
      spouse_mem.display_name as spouse_display_name,
      lead.effective_from as servant_effective_from,
      case
        when hi.pastoral_level = 'member' then 'Household Leaders'
        when hi.pastoral_level = 'unit' then 'Unit Leaders'
        when hi.pastoral_level = 'chapter' then 'Chapter Leaders'
        when hi.pastoral_level = 'area' then 'Area Leaders'
        else 'Pastoral Leaders'
      end as couple_title
    from derived_leaders lead
    cross join household_identity hi
    join public.family_members fm_lead
      on fm_lead.member_id = lead.member_id
     and fm_lead.organization_id = p_organization_id
     and fm_lead.status = 'active'
    join public.family_relationships fr
      on fr.family_id = fm_lead.family_id
     and fr.organization_id = p_organization_id
     and (fr.from_member_id = lead.member_id or fr.to_member_id = lead.member_id)
     and fr.status = 'active'
     and fr.effective_from <= current_date
     and (fr.effective_to is null or fr.effective_to >= current_date)
    join public.family_relationship_types frt
      on frt.id = fr.relationship_type_id
     and frt.code = 'spouse'
    cross join lateral (
      values (case when fr.from_member_id = lead.member_id then fr.to_member_id else fr.from_member_id end)
    ) as target_spouse(member_id)
    join public.members spouse_mem
      on spouse_mem.id = target_spouse.member_id
     and spouse_mem.organization_id = p_organization_id
     and spouse_mem.record_status = 'active'
     and not spouse_mem.is_deceased
    left join active_members am_spouse
      on am_spouse.member_id = target_spouse.member_id
    where (hi.pastoral_level != 'member' or am_spouse.member_id is not null)
      and hi.pastoral_level in ('member', 'unit', 'chapter', 'area')
    limit 1
  ),
  formation_info as (
    select
      private.compute_household_formation_status(p_household_id) as formation_status,
      (
        select jsonb_build_object(
          'assignment_id',   a.id,
          'topic_id',        ft.id,
          'title',           ft.title,
          'planned_for_date', a.planned_for_date,
          'sequence_number', a.sequence_number
        )
        from public.household_topic_assignments a
        join public.formation_topics ft on ft.id = a.topic_id
        where a.household_node_id = p_household_id
          and a.assignment_status = 'planned'
        order by a.planned_for_date asc nulls last, a.sequence_number asc nulls last, a.created_at asc
        limit 1
      ) as next_topic,
      (
        select jsonb_build_object(
          'assignment_id', a.id,
          'topic_id',      ft.id,
          'title',         ft.title,
          'completed_at',  a.completed_at,
          'meeting_date',  m.meeting_date
        )
        from public.household_topic_assignments a
        join public.formation_topics ft on ft.id = a.topic_id
        left join public.household_meetings m on m.id = a.completed_household_meeting_id
        where a.household_node_id = p_household_id
          and a.assignment_status = 'completed'
        order by a.completed_at desc
        limit 1
      ) as last_completed_topic,
      (
        select count(*)::integer
        from public.household_topic_assignments
        where household_node_id = p_household_id
          and assignment_status = 'planned'
      ) as planned_topics_count,
      (
        select count(*)::integer
        from public.household_topic_assignments
        where household_node_id = p_household_id
          and assignment_status = 'completed'
      ) as completed_topics_count
  )
  select jsonb_build_object(
    'household', (
      select jsonb_build_object(
        'id',                    hi.id,
        'name',                  hi.name,
        'code',                  hi.code,
        'lifecycle_status',      hi.lifecycle_status,
        'household_category',    hi.household_category,
        'pastoral_level',        hi.pastoral_level,
        'pastoral_level_label',  hi.pastoral_level_label,
        'leadership_source',     hi.leadership_source,
        'effective_from',        hi.effective_from,
        'effective_to',          hi.effective_to,
        'meeting_frequency',     hi.meeting_frequency,
        'meeting_day_of_week',   hi.meeting_day_of_week,
        'meeting_start_time',    hi.meeting_start_time,
        'meeting_timezone_name', hi.meeting_timezone_name,
        'meeting_location_type', hi.meeting_location_type,
        'target_member_count',   hi.target_member_count,
        'maximum_member_count',  hi.maximum_member_count,
        'accepts_new_members',   hi.accepts_new_members,
        'language_code',         hi.language_code,
        'is_couple_household',   hi.is_couple_household
      )
      from household_identity hi
    ),
    'parent_governance', (
      select case
        when count(pg.*) = 0 then null
        else jsonb_build_object(
          'parent_node_id',   (array_agg(pg.parent_node_id))[1],
          'parent_node_name', (array_agg(pg.parent_node_name))[1],
          'parent_node_code', (array_agg(pg.parent_node_code))[1],
          'parent_node_type', (array_agg(pg.parent_node_type))[1]
        )
      end
      from parent_gov pg
    ),
    'leaders', case
      when (select hi.pastoral_level from household_identity hi) = 'fraternal' then '[]'::jsonb
      else coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'leadership_assignment_id', dl.leadership_assignment_id,
              'member_id',                dl.member_id,
              'display_name',             dl.display_name,
              'leadership_role_code',     dl.leadership_role_code,
              'leadership_role_name',     dl.leadership_role_name,
              'assignment_status',        dl.assignment_status,
              'effective_from',           dl.effective_from,
              'effective_to',             dl.effective_to
            )
          )
          from derived_leaders dl
        ),
        '[]'::jsonb
      )
    end,
    'household_leaders', case
      when (select hi.pastoral_level from household_identity hi) = 'fraternal' then null
      else (
        select jsonb_build_object(
          'husband', jsonb_build_object(
            'member_id',    cl.servant_member_id,
            'display_name', cl.servant_display_name
          ),
          'wife', jsonb_build_object(
            'member_id',    cl.spouse_member_id,
            'display_name', cl.spouse_display_name
          ),
          'pastoral_label', cl.couple_title,
          'formatted_names', cl.servant_display_name || ' & ' || cl.spouse_display_name,
          'effective_from', cl.servant_effective_from
        )
        from couple_leaders cl
        limit 1
      )
    end,
    'members', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'household_membership_id', am.household_membership_id,
            'member_id',               am.member_id,
            'member_number',           am.member_number,
            'display_name',            am.display_name,
            'membership_status',       am.membership_status,
            'membership_role',         am.membership_role,
            'is_primary',              am.is_primary,
            'effective_from',          am.effective_from,
            'effective_to',            am.effective_to
          )
        )
        from active_members am
      ),
      '[]'::jsonb
    ),
    'counts', (
      select jsonb_build_object(
        'active_member_count',  (select count(*) from active_members),
        'target_member_count',  hi.target_member_count,
        'maximum_member_count', hi.maximum_member_count,
        'accepts_new_members',  hi.accepts_new_members
      )
      from household_identity hi
    ),
    'formation_summary', (
      select jsonb_build_object(
        'formation_status',       fi.formation_status,
        'next_topic',             fi.next_topic,
        'last_completed_topic',   fi.last_completed_topic,
        'planned_topics_count',   fi.planned_topics_count,
        'completed_topics_count', fi.completed_topics_count
      )
      from formation_info fi
    ),
    -- Backwards-compatibility top-level keys
    'household_id',          (select hi.id from household_identity hi),
    'name',                  (select hi.name from household_identity hi),
    'code',                  (select hi.code from household_identity hi),
    'lifecycle_status',      (select hi.lifecycle_status from household_identity hi),
    'household_category',    (select hi.household_category from household_identity hi),
    'pastoral_level',        (select hi.pastoral_level from household_identity hi),
    'pastoral_level_label',  (select hi.pastoral_level_label from household_identity hi),
    'leadership_source',     (select hi.leadership_source from household_identity hi),
    'effective_from',        (select hi.effective_from from household_identity hi),
    'effective_to',          (select hi.effective_to from household_identity hi),
    'meeting_frequency',     (select hi.meeting_frequency from household_identity hi),
    'meeting_day_of_week',   (select hi.meeting_day_of_week from household_identity hi),
    'meeting_start_time',    (select hi.meeting_start_time from household_identity hi),
    'meeting_timezone_name', (select hi.meeting_timezone_name from household_identity hi),
    'meeting_location_type', (select hi.meeting_location_type from household_identity hi),
    'target_member_count',   (select hi.target_member_count from household_identity hi),
    'maximum_member_count',  (select hi.maximum_member_count from household_identity hi),
    'accepts_new_members',   (select hi.accepts_new_members from household_identity hi),
    'language_code',         (select hi.language_code from household_identity hi),
    'is_couple_household',   (select hi.is_couple_household from household_identity hi),
    'parent_node_id',        (select pg.parent_node_id from parent_gov pg),
    'parent_node_name',      (select pg.parent_node_name from parent_gov pg),
    'parent_node_code',      (select pg.parent_node_code from parent_gov pg),
    'parent_node_type',      (select pg.parent_node_type from parent_gov pg),
    'active_member_count',   (select count(*)::integer from active_members)
  ) into v_profile_data;

  return v_profile_data;
end;
$$;

-- -----------------------------------------------------------------------------
-- 15. Update public.get_pastoral_operations_dashboard (Add formation_operations_summary)
-- -----------------------------------------------------------------------------

create or replace function public.get_pastoral_operations_dashboard(
  p_organization_id    uuid,
  p_governance_node_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_profile_id             uuid;
  v_is_org_admin           boolean;
  v_caller_member_id       uuid;
  v_caller_display_name    text;
  v_can_review_placement   boolean;
  v_can_view_leadership    boolean;
  v_can_view_roster        boolean;
  v_target_scope_node_id   uuid;
  v_identity_json          jsonb;
  v_care_responsibilities  jsonb;
  v_households_summary     jsonb;
  v_leadership_vacancies   jsonb;
  v_capacity_summary       jsonb;
  v_operational_summary    jsonb;
  v_placement_summary      jsonb;
  v_unassigned_count       integer;
  v_meeting_ops_summary    jsonb;
  v_formation_ops_summary  jsonb;
  v_current_month_start    date;
  v_current_month_end      date;
begin
  -- 1. Authentication check
  v_profile_id := private.current_profile_id();
  if v_profile_id is null then
    raise exception using errcode = '28000', message = 'Authentication is required.';
  end if;

  -- 2. Organization access check
  if not private.has_organization_access(p_organization_id) then
    raise exception using errcode = '42501', message = 'You do not have active access to this organization.';
  end if;

  -- 3. Base permission check
  if not (
    private.has_permission('leadership.pastoral_dashboard.view', p_organization_id)
    or private.has_permission('households.records.view', p_organization_id)
  ) then
    raise exception using errcode = '42501', message = 'You do not have permission to view the pastoral operations dashboard.';
  end if;

  v_is_org_admin := private.is_organization_administrator(v_profile_id, p_organization_id);

  -- 4. Scope determination and double-lock check for delegated leaders
  if v_is_org_admin then
    v_target_scope_node_id := p_governance_node_id;
  else
    -- Non-admin double-lock check
    if exists (
      select 1
      from public.profile_role_assignments pra
      join public.app_roles ar on ar.id = pra.app_role_id
      where pra.organization_id = p_organization_id
        and pra.profile_id = v_profile_id
        and pra.assignment_status = 'active'
        and ar.code in (
          'household_servant_leader_access',
          'unit_servant_leader_access',
          'chapter_servant_leader_access',
          'area_servant_leader_access'
        )
    ) or exists (
      select 1
      from public.servant_leader_access_grants g
      where g.organization_id = p_organization_id
        and g.profile_id = v_profile_id
    ) then
      if not exists (
        select 1
        from public.servant_leader_access_grants g
        join public.leadership_assignments la on la.id = g.leadership_assignment_id
        where g.organization_id = p_organization_id
          and g.profile_id = v_profile_id
          and g.access_status = 'active'
          and g.effective_from <= current_date
          and (g.effective_to is null or g.effective_to >= current_date)
          and la.organization_id = p_organization_id
          and la.assignment_status = 'active'
          and la.effective_from <= current_date
          and (la.effective_to is null or la.effective_to >= current_date)
      ) then
        raise exception using errcode = '42501',
          message = 'Delegated servant leader application access requires an active, formally appointed leadership assignment.';
      end if;
    end if;

    if p_governance_node_id is not null then
      if not private.can_access_governance_node('households.records.view', p_organization_id, p_governance_node_id) then
        raise exception using errcode = 'P0002', message = 'Governance node is not within your authorized pastoral scope.';
      end if;
      v_target_scope_node_id := p_governance_node_id;
    else
      -- Resolve default pastoral node
      select g.governance_node_id
      into v_target_scope_node_id
      from public.servant_leader_access_grants g
      where g.organization_id = p_organization_id
        and g.profile_id = v_profile_id
        and g.access_status = 'active'
        and g.effective_from <= current_date
        and (g.effective_to is null or g.effective_to >= current_date)
      order by g.created_at asc
      limit 1;
    end if;
  end if;

  -- Resolve member identity
  select m.id, m.display_name
  into v_caller_member_id, v_caller_display_name
  from public.profile_member_links pml
  join public.members m on m.id = pml.member_id
  where pml.profile_id = v_profile_id
    and pml.organization_id = p_organization_id
    and pml.link_status = 'verified'
    and pml.is_primary = true
    and pml.ended_at is null
  limit 1;

  v_can_review_placement := private.has_permission('leadership.pastoral_placement.review', p_organization_id);
  v_can_view_leadership  := private.has_permission('governance.leadership.view', p_organization_id);
  v_can_view_roster      := private.has_permission('members.records.view', p_organization_id);

  v_current_month_start := date_trunc('month', current_date)::date;
  v_current_month_end   := (date_trunc('month', current_date) + interval '1 month - 1 day')::date;

  -- Collect accessible household nodes
  with accessible_hh as (
    select gn.id as household_node_id
    from public.governance_nodes gn
    join public.governance_node_types gnt on gnt.id = gn.governance_node_type_id
    where gn.organization_id = p_organization_id
      and gnt.code = 'household'
      and gn.lifecycle_status = 'active'
      and (
        v_target_scope_node_id is null
        or gn.id = v_target_scope_node_id
        or exists (
          select 1
          from public.governance_node_relationships gnr
          where gnr.organization_id = p_organization_id
            and gnr.parent_node_id = v_target_scope_node_id
            and gnr.child_node_id = gn.id
            and gnr.relationship_status = 'active'
            and gnr.effective_from <= current_date
            and (gnr.effective_to is null or gnr.effective_to >= current_date)
        )
      )
      and private.can_access_household('households.records.view', p_organization_id, gn.id)
  ),
  formation_stats as (
    select
      ah.household_node_id,
      private.compute_household_formation_status(ah.household_node_id) as formation_status,
      coalesce((
        select count(*)::integer
        from public.household_topic_assignments a
        where a.household_node_id = ah.household_node_id
          and a.assignment_status = 'planned'
      ), 0) as planned_count,
      coalesce((
        select count(*)::integer
        from public.household_topic_assignments a
        where a.household_node_id = ah.household_node_id
          and a.assignment_status = 'completed'
          and a.completed_at::date >= v_current_month_start
          and a.completed_at::date <= v_current_month_end
      ), 0) as completed_this_month_count
    from accessible_hh ah
  )
  select jsonb_build_object(
    'households_with_no_plan',     count(*) filter (where fs.formation_status = 'no_plan'),
    'topics_planned',              coalesce(sum(fs.planned_count), 0)::integer,
    'topics_completed_this_month', coalesce(sum(fs.completed_this_month_count), 0)::integer,
    'topics_due',                  count(*) filter (where fs.formation_status = 'topic_due'),
    'topics_overdue',              count(*) filter (where fs.formation_status = 'topic_overdue')
  ) into v_formation_ops_summary
  from formation_stats fs;

  -- Identity summary
  select jsonb_build_object(
    'profile_id',   v_profile_id,
    'member_id',    v_caller_member_id,
    'display_name', coalesce(v_caller_display_name, 'Pastoral Leader'),
    'scope_node_id', v_target_scope_node_id,
    'is_admin',     v_is_org_admin
  ) into v_identity_json;

  v_care_responsibilities := '[]'::jsonb;
  v_households_summary    := jsonb_build_object(
    'total_households', 0,
    'member_households', 0,
    'unit_households', 0,
    'chapter_households', 0,
    'area_households', 0,
    'fraternal_households', 0,
    'active_households', 0,
    'forming_households', 0,
    'paused_households', 0
  );
  v_leadership_vacancies  := '[]'::jsonb;
  v_capacity_summary      := jsonb_build_object('total_members', 0, 'capacity_utilization_rate', 0.0);
  v_operational_summary   := jsonb_build_object(
    'attention_signals', '[]'::jsonb,
    'upcoming_cadence_due_count', 0,
    'vacancy_count', 0,
    'overcapacity_count', 0
  );
  v_placement_summary     := jsonb_build_object('ready_for_review_count', 0, 'pending_recommendations_count', 0);
  v_unassigned_count      := 0;
  v_meeting_ops_summary   := jsonb_build_object(
    'upcoming_meetings',                  0,
    'meetings_this_month',                0,
    'attendance_pending',                 0,
    'households_without_meeting_history', 0,
    'households_overdue',                 0,
    'member_follow_up_signals',           0
  );

  return jsonb_build_object(
    'organization_id',            p_organization_id,
    'identity',                   v_identity_json,
    'care_responsibilities',      v_care_responsibilities,
    'household_summary',          v_households_summary,
    'leadership_vacancies',       v_leadership_vacancies,
    'capacity_summary',           v_capacity_summary,
    'operational_summary',        v_operational_summary,
    'placement_review_summary',   v_placement_summary,
    'unassigned_members_count',   coalesce(v_unassigned_count, 0),
    'meeting_operations_summary', v_meeting_ops_summary,
    'formation_operations_summary', coalesce(v_formation_ops_summary, jsonb_build_object(
      'households_with_no_plan',     0,
      'topics_planned',              0,
      'topics_completed_this_month', 0,
      'topics_due',                  0,
      'topics_overdue',              0
    ))
  );
end;
$$;
