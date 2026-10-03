-- =============================================================================
-- Migration: 20261002150000_phase_6b_dedup_search_households.sql
-- Phase:     Phase 6B-9 — Delegated Servant Leader Access & Scope-Based Operations
-- Purpose:   Drop superseded search_households overload (with p_parent_governance_node_id
--            as 3rd positional argument) to prevent routine duplication and ambiguity.
-- =============================================================================

drop function if exists public.search_households(uuid, text, uuid, text, integer, integer);
