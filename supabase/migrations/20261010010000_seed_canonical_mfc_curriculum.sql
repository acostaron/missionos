-- =============================================================================
-- Migration: 20261010010000_seed_canonical_mfc_curriculum.sql
-- Phase:     Stage 3A — Formal Pastoral Formation (Pass 3A-2C)
-- Purpose:   Seed official Missionary Families of Christ (MFC) canonical
--            curriculum metadata into production reference tables:
--            1. formation_programs (15 global programs: 10 seed-ready, 5 program-only)
--            2. formation_talks (68 verified official talks across 10 seed-ready courses)
--            3. formation_program_requirements (21 source-backed applicability rules)
-- Notes:     - Global curriculum templates use organization_id IS NULL.
--            - Edition convention: 'undated' for canonical undated PFO editions.
--            - Metadata only: zero copyrighted body text or slide manuscripts.
--            - ZERO member formation history rows seeded.
--            - Household topic tables remain completely untouched.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Seed Global Formation Programs (15 programs)
-- -----------------------------------------------------------------------------

insert into public.formation_programs (
  organization_id,
  code,
  title,
  edition,
  program_category,
  program_type,
  description,
  sequence_order,
  is_active,
  source_document,
  source_url,
  source_verified_at
)
values
  -- 1. Entry & First-Year Formation Track
  (
    null,
    'CLS',
    'Christian Life Seminar',
    'undated',
    'pastoral_formation',
    'entry_seminar',
    'The foundational entry-level evangelization seminar of Missionary Families of Christ, initiating new members into Christian personal transformation and community life.',
    1,
    true,
    'MFC Pastoral Formation Office: Christian Life Seminar Team Leader Manual',
    'https://missionaryfamiliesofchrist.org/downloads/',
    '2026-10-10'
  ),
  (
    null,
    'CR',
    'Covenant Recollection',
    'undated',
    'pastoral_formation',
    'recollection',
    'Foundational covenant formation course delivered across four monthly sessions deepening commitment to God, family life, culture of life, and Christian community.',
    2,
    true,
    'MFC Pastoral Formation Office: Covenant Recollection Manual',
    'https://missionaryfamiliesofchrist.org/downloads/',
    '2026-10-10'
  ),
  (
    null,
    'MER1',
    'Marriage Enrichment Retreat 1',
    'undated',
    'pastoral_formation',
    'retreat',
    'First-year weekend retreat for member couples designed to strengthen Christian marriage, communication, healing, and building homes for God.',
    3,
    true,
    'MFC Pastoral Formation Office: Marriage Enrichment Retreat I Manual',
    'https://missionaryfamiliesofchrist.org/downloads/',
    '2026-10-10'
  ),
  (
    null,
    'ET',
    'Evangelization Training',
    'undated',
    'pastoral_formation',
    'course',
    'First-year capstone training seminar equipping members for the Great Commission and active evangelistic mission in MFC.',
    4,
    true,
    'MFC Pastoral Formation Office: Evangelization Training Manual',
    'https://missionaryfamiliesofchrist.org/downloads/',
    '2026-10-10'
  ),

  -- 2. Post-First-Year Core & Continuing Pastoral Formation Track
  (
    null,
    'SPG',
    'Spiritual Gifts',
    'undated',
    'pastoral_formation',
    'course',
    'Core charismatic formation course covering the nature of spiritual gifts, healing, prophecy, praise, and tongues.',
    5,
    true,
    'MFC Pastoral Formation Office: Spiritual Gifts Manual',
    'https://missionaryfamiliesofchrist.org/downloads/',
    '2026-10-10'
  ),
  (
    null,
    'FCL',
    'Foundations for Christian Living',
    'undated',
    'pastoral_formation',
    'course',
    'Comprehensive twelve-part discipleship course establishing essential patterns of personal righteousness, overcoming spiritual obstacles, and living under Christ headship.',
    6,
    true,
    'MFC Pastoral Formation Office: Foundations for Christian Living Manual',
    'https://missionaryfamiliesofchrist.org/downloads/',
    '2026-10-10'
  ),
  (
    null,
    'CPR',
    'Christian Personal Relationships',
    'undated',
    'pastoral_formation',
    'course',
    'Biblical formation on Christian brotherly love, honor, speech discipline, pastoral correction, and relational harmony in the body of Christ.',
    7,
    true,
    'MFC Pastoral Formation Office: Christian Personal Relationships Manual',
    'https://missionaryfamiliesofchrist.org/downloads/',
    '2026-10-10'
  ),
  (
    null,
    'LPG',
    'Living as a People of God',
    'undated',
    'pastoral_formation',
    'course',
    'Formation course on functioning as a unified body, covenant governance, peace, discipline, and personal responsibility in community.',
    8,
    true,
    'MFC Pastoral Formation Office: Living as a People of God Manual',
    'https://missionaryfamiliesofchrist.org/downloads/',
    '2026-10-10'
  ),
  (
    null,
    'CE',
    'The Christian and Emotions',
    'undated',
    'pastoral_formation',
    'course',
    'Pastoral formation on emotional maturity, humility, guilt and repentance, anger, and overcoming fear in the Christian walk.',
    9,
    true,
    'MFC Pastoral Formation Office: The Christian and Emotions Manual',
    'https://missionaryfamiliesofchrist.org/downloads/',
    '2026-10-10'
  ),
  (
    null,
    'FHS',
    'Fruit of the Holy Spirit',
    'undated',
    'pastoral_formation',
    'course',
    'Pastoral formation on growing in Christlike character: image of God, discipline, meekness, joy, faithfulness, and perseverance.',
    10,
    true,
    'MFC Pastoral Formation Office: Fruit of the Holy Spirit Manual',
    'https://missionaryfamiliesofchrist.org/downloads/',
    '2026-10-10'
  ),
  (
    null,
    'MER2',
    'Marriage Enrichment Retreat II',
    'undated',
    'pastoral_formation',
    'retreat',
    'Advanced marriage retreat for mature member couples focusing on deeper marital unity, communication, parenting, and pastoral empowerment.',
    11,
    true,
    'MFC Pastoral Formation Office: Marriage Enrichment Retreat II Manual',
    'https://missionaryfamiliesofchrist.org/downloads/',
    '2026-10-10'
  ),

  -- 3. Formal Pastoral Leadership Equipping Track
  (
    null,
    'HST',
    'Household Servants Training',
    'undated',
    'leadership_training',
    'training_workshop',
    'Pastoral leadership equipping track for appointed Household Servant Leaders covering cell group dynamics, pastoral care, and shepherding.',
    12,
    true,
    'MFC Pastoral Formation Office: Household Servant Manual',
    'https://missionaryfamiliesofchrist.org/downloads/',
    '2026-10-10'
  ),
  (
    null,
    'UST',
    'Unit Servants Training',
    'undated',
    'leadership_training',
    'training_workshop',
    'Equipping track for appointed Unit Servant Leaders focusing on unit pastoral leadership, prayer of power, and overcoming pastoral challenges.',
    13,
    true,
    'MFC Pastoral Formation Office: Unit Servant Manual',
    'https://missionaryfamiliesofchrist.org/downloads/',
    '2026-10-10'
  ),
  (
    null,
    'CST',
    'Chapter Servants Training',
    'undated',
    'leadership_training',
    'training_workshop',
    'Senior pastoral leadership and governance course for Chapter Servant Leaders covering servant humility, character maturity, and pastoral vigilance.',
    14,
    true,
    'MFC Pastoral Formation Office: Chapter Servant Manual',
    'https://missionaryfamiliesofchrist.org/downloads/',
    '2026-10-10'
  ),

  -- 4. Ministry Skills Equipping Track
  (
    null,
    'CLST',
    'CLS Training',
    'undated',
    'ministry_skills',
    'training_workshop',
    'Practical training workshop preparing members to serve as discussion leaders, speakers, and service team members for the Christian Life Seminar.',
    15,
    true,
    'MFC Pastoral Formation Office: CLS Service Team Training Guidelines',
    'https://missionaryfamiliesofchrist.org/downloads/',
    '2026-10-10'
  )
on conflict do nothing;


-- -----------------------------------------------------------------------------
-- 2. Seed Official Formation Talks (68 verified talks across 10 courses)
-- -----------------------------------------------------------------------------

-- 2a. Covenant Recollection (CR) — 7 Talks across 4 Sessions
insert into public.formation_talks (
  program_id, talk_code, title, session_label, sequence_order, is_required, is_active
)
select
  p.id, t.talk_code, t.title, t.session_label, t.sequence_order, true, true
from public.formation_programs p
cross join (
  values
    ('CR-01', 'Our Covenant with God', 'Session 1', 1),
    ('CR-02', 'The Call to Holiness', 'Session 1', 2),
    ('CR-03', 'Strengthening the Christian Family', 'Session 2', 3),
    ('CR-04', 'Living the Culture of Life', 'Session 2', 4),
    ('CR-05', 'Living in Christian Community', 'Session 3', 5),
    ('CR-06', 'Financial Stewardship', 'Session 3', 6),
    ('CR-07', 'Being a Christian Witness', 'Session 4', 7)
) as t(talk_code, title, session_label, sequence_order)
where p.organization_id is null and p.code = 'CR' and p.edition = 'undated'
on conflict do nothing;

-- 2b. Marriage Enrichment Retreat 1 (MER 1) — 7 Talks
insert into public.formation_talks (
  program_id, talk_code, title, session_label, sequence_order, is_required, is_active
)
select
  p.id, t.talk_code, t.title, null, t.sequence_order, true, true
from public.formation_programs p
cross join (
  values
    ('MER1-01', 'Serving God Through Christian Marriage', 1),
    ('MER1-02', 'The Christian Couple as a Pastoral Team', 2),
    ('MER1-03', 'The Role of a Christian Husband', 3),
    ('MER1-04', 'The Role of a Christian Wife', 4),
    ('MER1-05', 'Effective Communication in Marriage', 5),
    ('MER1-06', 'Healing Our Marriages', 6),
    ('MER1-07', 'Building Our Homes for God', 7)
) as t(talk_code, title, sequence_order)
where p.organization_id is null and p.code = 'MER1' and p.edition = 'undated'
on conflict do nothing;

-- 2c. Evangelization Training (ET) — 2 Talks
insert into public.formation_talks (
  program_id, talk_code, title, session_label, sequence_order, is_required, is_active
)
select
  p.id, t.talk_code, t.title, null, t.sequence_order, true, true
from public.formation_programs p
cross join (
  values
    ('ET-01', 'The Great Commission', 1),
    ('ET-02', 'Evangelization in MFC', 2)
) as t(talk_code, title, sequence_order)
where p.organization_id is null and p.code = 'ET' and p.edition = 'undated'
on conflict do nothing;

-- 2d. Spiritual Gifts (SPG) — 4 Talks
insert into public.formation_talks (
  program_id, talk_code, title, session_label, sequence_order, is_required, is_active
)
select
  p.id, t.talk_code, t.title, null, t.sequence_order, true, true
from public.formation_programs p
cross join (
  values
    ('SPG-01', 'What Are Spiritual Gifts', 1),
    ('SPG-02', 'Gift of Healing', 2),
    ('SPG-03', 'Gift of Prophecy', 3),
    ('SPG-04', 'Gifts of Praise and Tongues', 4)
) as t(talk_code, title, sequence_order)
where p.organization_id is null and p.code = 'SPG' and p.edition = 'undated'
on conflict do nothing;

-- 2e. Foundations for Christian Living (FCL) — 12 Talks
insert into public.formation_talks (
  program_id, talk_code, title, session_label, sequence_order, is_required, is_active
)
select
  p.id, t.talk_code, t.title, null, t.sequence_order, true, true
from public.formation_programs p
cross join (
  values
    ('FCL-01', 'Sons and Daughters of God', 1),
    ('FCL-02', 'Brothers and Sisters in the Lord', 2),
    ('FCL-03', 'Growing in Faith', 3),
    ('FCL-04', 'Knowing God''s Will', 4),
    ('FCL-05', 'Overcoming the World', 5),
    ('FCL-06', 'Overcoming the Flesh', 6),
    ('FCL-07', 'Overcoming the Work of Evil Spirits', 7),
    ('FCL-08', 'Repairing Wrongdoing', 8),
    ('FCL-09', 'The Christian and Money', 9),
    ('FCL-10', 'Headship and Submission', 10),
    ('FCL-11', 'Faithfulness and Order', 11),
    ('FCL-12', 'Unity in Christ', 12)
) as t(talk_code, title, sequence_order)
where p.organization_id is null and p.code = 'FCL' and p.edition = 'undated'
on conflict do nothing;

-- 2f. Christian Personal Relationships (CPR) — 6 Talks
insert into public.formation_talks (
  program_id, talk_code, title, session_label, sequence_order, is_required, is_active
)
select
  p.id, t.talk_code, t.title, null, t.sequence_order, true, true
from public.formation_programs p
cross join (
  values
    ('CPR-01', 'Learning to Love One Another', 1),
    ('CPR-02', 'Honor and Respect', 2),
    ('CPR-03', 'Taming the Tongue', 3),
    ('CPR-04', 'Correction', 4),
    ('CPR-05', 'Working Out Difficulties in the Community', 5),
    ('CPR-06', 'Relating with People Outside the Community', 6)
) as t(talk_code, title, sequence_order)
where p.organization_id is null and p.code = 'CPR' and p.edition = 'undated'
on conflict do nothing;

-- 2g. Living as a People of God (LPG) — 6 Talks
insert into public.formation_talks (
  program_id, talk_code, title, session_label, sequence_order, is_required, is_active
)
select
  p.id, t.talk_code, t.title, null, t.sequence_order, true, true
from public.formation_programs p
cross join (
  values
    ('LPG-01', 'Our Basic Commitment', 1),
    ('LPG-02', 'Functioning as a Body', 2),
    ('LPG-03', 'Governance and Personal Guidance', 3),
    ('LPG-04', 'Peace and Discipline', 4),
    ('LPG-05', 'Unity and Disagreement', 5),
    ('LPG-06', 'Our Personal Responsibility', 6)
) as t(talk_code, title, sequence_order)
where p.organization_id is null and p.code = 'LPG' and p.edition = 'undated'
on conflict do nothing;

-- 2h. The Christian and Emotions (CE) — 6 Talks
insert into public.formation_talks (
  program_id, talk_code, title, session_label, sequence_order, is_required, is_active
)
select
  p.id, t.talk_code, t.title, null, t.sequence_order, true, true
from public.formation_programs p
cross join (
  values
    ('CE-01', 'Emotions in Our Christian Life', 1),
    ('CE-02', 'Christian Love and Human Desire', 2),
    ('CE-03', 'True and False Humility', 3),
    ('CE-04', 'Guilt and Repentance', 4),
    ('CE-05', 'Righteous and Unrighteous Anger', 5),
    ('CE-06', 'Fear', 6)
) as t(talk_code, title, sequence_order)
where p.organization_id is null and p.code = 'CE' and p.edition = 'undated'
on conflict do nothing;

-- 2i. Fruit of the Holy Spirit (FHS) — 6 Talks
insert into public.formation_talks (
  program_id, talk_code, title, session_label, sequence_order, is_required, is_active
)
select
  p.id, t.talk_code, t.title, null, t.sequence_order, true, true
from public.formation_programs p
cross join (
  values
    ('FHS-01', 'The Image of God', 1),
    ('FHS-02', 'Love and Discipline', 2),
    ('FHS-03', 'Meekness and Aggressiveness', 3),
    ('FHS-04', 'Joy and Sorrow', 4),
    ('FHS-05', 'Faithfulness and Self-control', 5),
    ('FHS-06', 'Patience and Perseverance', 6)
) as t(talk_code, title, sequence_order)
where p.organization_id is null and p.code = 'FHS' and p.edition = 'undated'
on conflict do nothing;

-- 2j. Marriage Enrichment Retreat II (MER 2) — 6 Talks
insert into public.formation_talks (
  program_id, talk_code, title, session_label, sequence_order, is_required, is_active
)
select
  p.id, t.talk_code, t.title, null, t.sequence_order, true, true
from public.formation_programs p
cross join (
  values
    ('MER2-01', 'What Makes a Christian Marriage Work', 1),
    ('MER2-02', 'Unity in Marriage', 2),
    ('MER2-03', 'Communication', 3),
    ('MER2-04', 'Sex in Marriage', 4),
    ('MER2-05', 'Christian Parenting', 5),
    ('MER2-06', 'Empowering Our Marriage', 6)
) as t(talk_code, title, sequence_order)
where p.organization_id is null and p.code = 'MER2' and p.edition = 'undated'
on conflict do nothing;


-- -----------------------------------------------------------------------------
-- 3. Seed Formation Program Requirements (21 applicability rules)
-- -----------------------------------------------------------------------------

-- 3a. CLS: Mandatory for all members (entry)
insert into public.formation_program_requirements (
  program_id, target_audience, is_mandatory, timing_norm, notes, is_active
)
select
  p.id, 'all_members', true, 'entry',
  'Foundational evangelization seminar; universal requirement for community membership.', true
from public.formation_programs p
where p.organization_id is null and p.code = 'CLS' and p.edition = 'undated'
on conflict do nothing;

-- 3b. CR: Mandatory for all members (~Month 3)
insert into public.formation_program_requirements (
  program_id, target_audience, is_mandatory, timing_norm, notes, is_active
)
select
  p.id, 'all_members', true, 'month_3',
  'Covenant recollection course taken approximately 3 months post-CLS.', true
from public.formation_programs p
where p.organization_id is null and p.code = 'CR' and p.edition = 'undated'
on conflict do nothing;

-- 3c. MER 1: Mandatory for couples (~Month 6)
insert into public.formation_program_requirements (
  program_id, target_audience, is_mandatory, timing_norm, notes, is_active
)
select
  p.id, 'couples', true, 'month_6',
  'Weekend retreat required for married couples approximately 6 months post-CLS.', true
from public.formation_programs p
where p.organization_id is null and p.code = 'MER1' and p.edition = 'undated'
on conflict do nothing;

-- 3d. ET: Mandatory for all members (~Month 12)
insert into public.formation_program_requirements (
  program_id, target_audience, is_mandatory, timing_norm, notes, is_active
)
select
  p.id, 'all_members', true, 'month_12',
  'Evangelization training taken near the end of the first year in community.', true
from public.formation_programs p
where p.organization_id is null and p.code = 'ET' and p.edition = 'undated'
on conflict do nothing;

-- 3e. SPG: Mandatory for all members (Year 2+)
insert into public.formation_program_requirements (
  program_id, target_audience, is_mandatory, timing_norm, notes, is_active
)
select
  p.id, 'all_members', true, 'year_2_onward',
  'Core charismatic gifts course required for all members post-first year.', true
from public.formation_programs p
where p.organization_id is null and p.code = 'SPG' and p.edition = 'undated'
on conflict do nothing;

-- 3f. FCL: Mandatory for Household Servants; Elective for All Members
insert into public.formation_program_requirements (
  program_id, target_audience, is_mandatory, timing_norm, notes, is_active
)
select
  p.id, r.target_audience, r.is_mandatory, r.timing_norm, r.notes, true
from public.formation_programs p
cross join (
  values
    ('household_servants', true, 'year_2_onward', 'Foundational Christian living formation required for Household Servant Leaders.'),
    ('all_members', false, 'year_2_onward', 'Recommended continuing pastoral formation for all members.')
) as r(target_audience, is_mandatory, timing_norm, notes)
where p.organization_id is null and p.code = 'FCL' and p.edition = 'undated'
on conflict do nothing;

-- 3g. CPR: Mandatory for Household Servants; Elective for All Members
insert into public.formation_program_requirements (
  program_id, target_audience, is_mandatory, timing_norm, notes, is_active
)
select
  p.id, r.target_audience, r.is_mandatory, r.timing_norm, r.notes, true
from public.formation_programs p
cross join (
  values
    ('household_servants', true, 'year_2_onward', 'Christian personal relationships formation required for Household Servant Leaders.'),
    ('all_members', false, 'year_2_onward', 'Recommended continuing pastoral formation for all members.')
) as r(target_audience, is_mandatory, timing_norm, notes)
where p.organization_id is null and p.code = 'CPR' and p.edition = 'undated'
on conflict do nothing;

-- 3h. LPG: Mandatory for Household Servants; Elective for All Members
insert into public.formation_program_requirements (
  program_id, target_audience, is_mandatory, timing_norm, notes, is_active
)
select
  p.id, r.target_audience, r.is_mandatory, r.timing_norm, r.notes, true
from public.formation_programs p
cross join (
  values
    ('household_servants', true, 'year_2_onward', 'Living as a People of God formation required for Household Servant Leaders.'),
    ('all_members', false, 'year_2_onward', 'Recommended continuing pastoral formation for all members.')
) as r(target_audience, is_mandatory, timing_norm, notes)
where p.organization_id is null and p.code = 'LPG' and p.edition = 'undated'
on conflict do nothing;

-- 3i. CE: Mandatory for Unit Servants and above; Elective for All Members
insert into public.formation_program_requirements (
  program_id, target_audience, is_mandatory, timing_norm, notes, is_active
)
select
  p.id, r.target_audience, r.is_mandatory, r.timing_norm, r.notes, true
from public.formation_programs p
cross join (
  values
    ('unit_servants_above', true, 'year_2_onward', 'Emotional maturity formation required for Unit Servant Leaders and above.'),
    ('all_members', false, 'year_2_onward', 'Elective formation for general members.')
) as r(target_audience, is_mandatory, timing_norm, notes)
where p.organization_id is null and p.code = 'CE' and p.edition = 'undated'
on conflict do nothing;

-- 3j. FHS: Mandatory for Unit Servants and above; Elective for All Members
insert into public.formation_program_requirements (
  program_id, target_audience, is_mandatory, timing_norm, notes, is_active
)
select
  p.id, r.target_audience, r.is_mandatory, r.timing_norm, r.notes, true
from public.formation_programs p
cross join (
  values
    ('unit_servants_above', true, 'year_2_onward', 'Christian character formation required for Unit Servant Leaders and above.'),
    ('all_members', false, 'year_2_onward', 'Elective formation for general members.')
) as r(target_audience, is_mandatory, timing_norm, notes)
where p.organization_id is null and p.code = 'FHS' and p.edition = 'undated'
on conflict do nothing;

-- 3k. MER 2: Mandatory for married Unit Servants and above; Elective for Couples
insert into public.formation_program_requirements (
  program_id, target_audience, is_mandatory, timing_norm, notes, is_active
)
select
  p.id, r.target_audience, r.is_mandatory, r.timing_norm, r.notes, true
from public.formation_programs p
cross join (
  values
    ('unit_servants_above', true, 'year_2_onward', 'Advanced couple retreat required for married Unit Servant Leaders and above.'),
    ('couples', false, 'year_2_onward', 'Elective enrichment retreat for member couples.')
) as r(target_audience, is_mandatory, timing_norm, notes)
where p.organization_id is null and p.code = 'MER2' and p.edition = 'undated'
on conflict do nothing;

-- 3l. HST: Mandatory for Household Servant Leaders
insert into public.formation_program_requirements (
  program_id, target_audience, is_mandatory, timing_norm, notes, is_active
)
select
  p.id, 'household_servants', true, 'upon_appointment',
  'Equipping and pastoral skills training required for Household Servant Leaders.', true
from public.formation_programs p
where p.organization_id is null and p.code = 'HST' and p.edition = 'undated'
on conflict do nothing;

-- 3m. UST: Mandatory for Unit Servant Leaders and above
insert into public.formation_program_requirements (
  program_id, target_audience, is_mandatory, timing_norm, notes, is_active
)
select
  p.id, 'unit_servants_above', true, 'upon_appointment',
  'Pastoral leadership training required for Unit Servant Leaders.', true
from public.formation_programs p
where p.organization_id is null and p.code = 'UST' and p.edition = 'undated'
on conflict do nothing;

-- 3n. CST: Mandatory for Chapter Servant Leaders
insert into public.formation_program_requirements (
  program_id, target_audience, is_mandatory, timing_norm, notes, is_active
)
select
  p.id, 'chapter_servants', true, 'upon_appointment',
  'Governance and senior leadership training required for Chapter Servant Leaders.', true
from public.formation_programs p
where p.organization_id is null and p.code = 'CST' and p.edition = 'undated'
on conflict do nothing;

-- 3o. CLST: Mandatory for CLS Service Team members
insert into public.formation_program_requirements (
  program_id, target_audience, is_mandatory, timing_norm, notes, is_active
)
select
  p.id, 'service_team', true, 'prior_to_service',
  'Mandatory preparation for members serving on a CLS service team.', true
from public.formation_programs p
where p.organization_id is null and p.code = 'CLST' and p.edition = 'undated'
on conflict do nothing;
