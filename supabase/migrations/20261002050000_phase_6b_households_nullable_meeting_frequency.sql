-- =============================================================================
-- Migration: 20261002050000_phase_6b_households_nullable_meeting_frequency.sql
-- Phase:     Phase 6B-8 — Household Meetings, Attendance & Pastoral Follow-up
-- Purpose:   Allows households.meeting_frequency to be NULL when not configured.
-- =============================================================================

alter table public.households
  alter column meeting_frequency drop not null;

comment on column public.households.meeting_frequency is
  'Cadence for household meetings: weekly, biweekly, monthly, quarterly, seasonal, variable, or NULL (not configured).';
