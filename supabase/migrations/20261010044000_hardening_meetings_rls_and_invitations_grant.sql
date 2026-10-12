-- Pass 4.7: close remaining direct-access gaps.
-- household_meetings / household_meeting_attendance: enable RLS (default deny).
-- All access is through SECURITY DEFINER functions owned by postgres (table owner),
-- which are not subject to RLS because FORCE ROW LEVEL SECURITY is not set.
alter table public.household_meetings enable row level security;
alter table public.household_meeting_attendance enable row level security;

revoke all on table public.household_meetings from anon, authenticated;
revoke all on table public.household_meeting_attendance from anon, authenticated;

-- member_account_invitations: browser never reads this table directly
-- (all flows use RPCs). Remove the leftover SELECT grant and its policies.
revoke all on table public.member_account_invitations from anon, authenticated;
drop policy if exists member_account_invitations_admin_select on public.member_account_invitations;
drop policy if exists member_account_invitations_self_select on public.member_account_invitations;
