// =============================================================================
// Supabase Edge Function: sync-topic-library
// MissionOS Pass 9.2 (written by Claude, 2026-10-15)
//
// Copies the MFC monthly topics into the Household Library as PENDING copies
// that a manager approves in the app. Nothing is shown to members until approved.
//
//   1. Caller must be signed in and hold households.formation.manage
//      (checked with the caller's own JWT via public.can_manage_topic_library).
//   2. Reads the MFC downloads page for the series (missionaryfamiliesofchrist.org).
//      Each link's text carries the title, the material label and the month,
//      e.g. "Living The Shared Life Household Topic Oct 2026".
//   3. Opens each linked Google Sites page and turns the main content into
//      plain-text blocks: heading / paragraph / list_item. No HTML is stored.
//   4. Calls public.ingest_topic_library_page (service role) for each page.
//
// Shared pages (Personal Sharing Household Guide, Chapter Assembly Guide) use the
// same URL every month, so they are copied only for the NEWEST month on the page.
// Song Choices are skipped.
//
// Callers: a signed-in manager (JWT), or the scheduled job (pg_cron, header x-sync-secret
// checked against Vault; always "ingest"). verify_jwt is off for this function (config.toml).
// Every ingest run is logged with record_topic_library_sync_run.
//
// Request body:
//   { organization_id: uuid, mode?: "dry_run" | "ingest" (default "dry_run"),
//     months?: ["2026-10", ...], from_month?: "2026-10" (default: current NY month),
//     series_code?, series_title?, downloads_url? }
// Months before from_month are never copied.
// The response lists, per page: month, kind, result, block and heading counts.
// It never returns the copied text.
// =============================================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.48.0";
import { DOMParser, Element } from "https://deno.land/x/deno_dom@v0.1.45/deno-dom-wasm.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const DEFAULT_SERIES_CODE = "2026-rooted-in-christ";
const DEFAULT_SERIES_TITLE = "2026 Rooted in Christ";
const DEFAULT_DOWNLOADS_URL =
  "https://missionaryfamiliesofchrist.org/downloads/2026-rooted-in-christ-topics/";

const ALLOWED_DOWNLOAD_HOSTS = new Set(["missionaryfamiliesofchrist.org", "www.missionaryfamiliesofchrist.org"]);
const ALLOWED_TOPIC_HOST = "sites.google.com";

type Kind =
  | "household_topic"
  | "family_household_topic"
  | "date_night_topic"
  | "chapter_teaching"
  | "chapter_assembly_guide"
  | "personal_sharing_guide";

const SHARED_KINDS: Kind[] = ["chapter_assembly_guide", "personal_sharing_guide"];

// Order matters: longer labels first.
const LABELS: { re: RegExp; kind: Kind | "skip"; titleIsLabel?: boolean }[] = [
  { re: /\s*Family Household Topic$/i, kind: "family_household_topic" },
  { re: /\s*Chapter Teaching Topic$/i, kind: "chapter_teaching" },
  { re: /^Personal Sharing Household Guide$/i, kind: "personal_sharing_guide", titleIsLabel: true },
  { re: /^Chapter Assembly Guide$/i, kind: "chapter_assembly_guide", titleIsLabel: true },
  { re: /\s*Household Topic$/i, kind: "household_topic" },
  { re: /\s*Date Night Topic$/i, kind: "date_night_topic" },
  { re: /Song Choices/i, kind: "skip" },
];

const MONTHS: Record<string, number> = {
  jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6, jul: 7, aug: 8, sep: 9, sept: 9, oct: 10, nov: 11, dec: 12,
};

const CHROME_TEXT = new Set([
  "embedded files", "search this site", "skip to main content", "skip to navigation",
  "report abuse", "page details", "page updated", "google sites", "this site uses cookies from google to deliver its services and to analyze traffic.",
]);

export type Block = { type: "heading" | "paragraph" | "list_item"; text: string; level?: number; ordered?: boolean };

export type Discovered = {
  url: string;
  linkText: string;
  title: string;
  kind: Kind;
  month: string; // YYYY-MM-01
};

function clean(s: string | null | undefined): string {
  return (s ?? "").replace(/ /g, " ").replace(/\s+/g, " ").trim();
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/** "Living The Shared Life Household Topic Oct 2026" -> { title, kind, month } */
export function classifyLinkText(text: string): { title: string; kind: Kind | "skip"; month: string } | null {
  const t = clean(text);
  const m = t.match(/\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*\.?\s+(20\d\d)\s*$/i);
  if (!m) return null;
  const key = m[1].toLowerCase();
  const monthNum = MONTHS[key] ?? MONTHS[key.slice(0, 3)];
  if (!monthNum) return null;
  const month = `${m[2]}-${String(monthNum).padStart(2, "0")}-01`;
  const head = clean(t.slice(0, m.index));
  for (const l of LABELS) {
    if (l.kind === "skip" && l.re.test(head)) return { title: head, kind: "skip", month };
    if (l.kind !== "skip" && l.re.test(head)) {
      const title = l.titleIsLabel ? head : clean(head.replace(l.re, ""));
      if (!title) return null;
      return { title, kind: l.kind, month };
    }
  }
  return null;
}

export function discoverFromDownloadsHtml(html: string): { found: Discovered[]; unclassified: string[] } {
  const doc = new DOMParser().parseFromString(html, "text/html");
  if (!doc) throw new Error("Could not read the downloads page.");
  const found: Discovered[] = [];
  const unclassified: string[] = [];
  const seen = new Set<string>();
  for (const node of Array.from(doc.querySelectorAll("a[href]"))) {
    const a = node as Element;
    const href = a.getAttribute("href") ?? "";
    let u: URL;
    try { u = new URL(href); } catch { continue; }
    if (u.protocol !== "https:" || u.hostname !== ALLOWED_TOPIC_HOST || !u.pathname.startsWith("/view/")) continue;
    u.hash = ""; u.search = "";
    const text = clean(a.textContent);
    if (!text) continue;
    const c = classifyLinkText(text);
    if (!c) { unclassified.push(text.slice(0, 120)); continue; }
    if (c.kind === "skip") continue;
    const key = `${c.month}|${c.kind}|${u.toString()}`;
    if (seen.has(key)) continue;
    seen.add(key);
    found.push({ url: u.toString(), linkText: text, title: c.title, kind: c.kind, month: c.month });
  }
  return { found, unclassified };
}

/**
 * Google Sites section labels ("Goal", "Grab", "Grace", "Go Forth" …) are styled
 * paragraphs, not <h*> tags. A paragraph counts as a section heading when it is a
 * short label: 1–4 words, starts with a capital letter, no digits, no closing
 * punctuation, and is not a quotation.
 */
export function looksLikeSectionLabel(text: string): boolean {
  const t = text.trim();
  if (t.length === 0 || t.length > 32) return false;
  const words = t.split(/\s+/);
  if (words.length > 4) return false;
  if (!/^[A-Z]/.test(t)) return false;
  if (/\d/.test(t)) return false;
  if (/[.,;:!?"'\u201c\u201d\u2018\u2019)\]]$/.test(t)) return false;
  if (/^[-\u2013\u2014("\u201c]/.test(t)) return false;
  return true;
}

/** Turn a Google Sites page into plain-text blocks from its main content. */
export function extractBlocks(html: string): Block[] {
  const doc = new DOMParser().parseFromString(html, "text/html");
  if (!doc) throw new Error("Could not read the topic page.");
  const body = doc.body as Element | null;
  if (!body) return [];
  for (const sel of ["nav", "header", "footer", "script", "style", "noscript", "[role='navigation']"]) {
    for (const n of Array.from(body.querySelectorAll(sel))) (n as Element).remove();
  }
  // Google Sites puts the page title in [role=main] and each text box of the page body in a
  // div.tyJCtd OUTSIDE [role=main]. Read every top-level text box in page order; fall back to
  // [role=main] / <body> if the site layout changes.
  const boxes = (Array.from(body.querySelectorAll(".tyJCtd")) as Element[])
    .filter((b) => !b.parentElement?.closest(".tyJCtd"));
  const roots: Element[] = boxes.length > 0
    ? boxes
    : [((body.querySelector('[role="main"]') as Element | null) ?? body)];
  const nodes: Element[] = roots.flatMap((r) => Array.from(r.querySelectorAll("h1,h2,h3,h4,h5,h6,p,li")) as Element[]);
  const blocks: Block[] = [];
  for (const node of nodes) {
    const el = node as Element;
    const tag = el.tagName.toLowerCase();
    // text inside a list item is taken with the list item
    if (tag !== "li" && el.closest("li")) continue;
    // a list item that contains another list item: take only the inner ones
    if (tag === "li" && el.querySelector("li")) continue;
    const text = clean(el.textContent);
    if (!text || CHROME_TEXT.has(text.toLowerCase())) continue;
    if (tag.startsWith("h")) {
      blocks.push({ type: "heading", text, level: Math.min(Number(tag.slice(1)), 4) });
    } else if (tag === "li") {
      const ordered = el.parentElement?.tagName.toLowerCase() === "ol";
      blocks.push(ordered ? { type: "list_item", text, ordered: true } : { type: "list_item", text });
    } else if (looksLikeSectionLabel(text)) {
      blocks.push({ type: "heading", text, level: 3 });
    } else {
      blocks.push({ type: "paragraph", text });
    }
  }
  // drop consecutive duplicates (Google Sites sometimes repeats a text box)
  return blocks.filter((b, i) => i === 0 || b.text !== blocks[i - 1].text || b.type !== blocks[i - 1].type);
}

async function fetchText(url: string): Promise<string> {
  const res = await fetch(url, {
    headers: { "User-Agent": "MissionOS-TopicLibrary/1.0 (+https://app.mfcny.net)" },
    redirect: "follow",
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const final = new URL(res.url);
  if (final.hostname !== ALLOWED_TOPIC_HOST && !ALLOWED_DOWNLOAD_HOSTS.has(final.hostname)) {
    throw new Error("Redirected to an unexpected site.");
  }
  return await res.text();
}

if (import.meta.main) {
  serve(async (req: Request) => {
    if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
    if (req.method !== "POST") return json({ error: "Method not allowed." }, 405);

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const authHeader = req.headers.get("Authorization") ?? "";
    const syncSecret = req.headers.get("x-sync-secret") ?? "";
    if (!syncSecret && !authHeader.startsWith("Bearer ")) return json({ error: "Authentication is required." }, 401);
    const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });

    let body: any;
    try { body = await req.json(); } catch { return json({ error: "Invalid JSON body." }, 400); }

    const orgId = String(body?.organization_id ?? "");
    if (!/^[0-9a-f-]{36}$/i.test(orgId)) return json({ error: "organization_id is required." }, 400);
    let mode: "ingest" | "dry_run" = body?.mode === "ingest" ? "ingest" : "dry_run";
    // Only this month and later are copied (New York time), unless from_month says otherwise.
    const nyMonth = new Intl.DateTimeFormat("en-CA", { timeZone: "America/New_York", year: "numeric", month: "2-digit" })
      .format(new Date()).slice(0, 7);
    const fromMonth: string = typeof body?.from_month === "string" && /^20\d\d-(0[1-9]|1[0-2])$/.test(body.from_month)
      ? body.from_month : nyMonth;
    const monthsFilter: string[] | null = Array.isArray(body?.months)
      ? body.months.filter((m: unknown) => typeof m === "string" && /^20\d\d-(0[1-9]|1[0-2])$/.test(m))
      : null;
    const seriesCode = typeof body?.series_code === "string" && /^[a-z0-9-]{3,60}$/.test(body.series_code)
      ? body.series_code : DEFAULT_SERIES_CODE;
    const seriesTitle = typeof body?.series_title === "string" && body.series_title.trim().length > 0
      ? clean(body.series_title).slice(0, 120) : DEFAULT_SERIES_TITLE;
    let downloadsUrl = DEFAULT_DOWNLOADS_URL;
    if (typeof body?.downloads_url === "string") {
      try {
        const u = new URL(body.downloads_url);
        if (u.protocol !== "https:" || !ALLOWED_DOWNLOAD_HOSTS.has(u.hostname)) {
          return json({ error: "downloads_url must be on missionaryfamiliesofchrist.org." }, 400);
        }
        downloadsUrl = u.toString();
      } catch {
        return json({ error: "Invalid downloads_url." }, 400);
      }
    }

    // 1. Who is calling?
    //    a) the scheduled job (pg_cron) with the Vault secret -> always "ingest"
    //    b) a signed-in manager (households.formation.manage), checked with their own JWT
    let triggerSource: "scheduled" | "manual" = "manual";
    if (syncSecret) {
      const { data: ok, error: secretErr } = await admin.rpc("verify_topic_sync_secret", { p_secret: syncSecret });
      if (secretErr || ok !== true) return json({ error: "Not authorised." }, 401);
      triggerSource = "scheduled";
      mode = "ingest";
    } else {
      const caller = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authHeader } } });
      const { data: canManage, error: permErr } = await caller.rpc("can_manage_topic_library", {
        p_organization_id: orgId,
      });
      if (permErr) return json({ error: `Permission check failed: ${permErr.message}` }, 403);
      if (canManage !== true) return json({ error: "You do not have permission to update the Household Library." }, 403);
    }

    // 2. discover
    let discovered: Discovered[];
    let unclassified: string[];
    try {
      const r = discoverFromDownloadsHtml(await fetchText(downloadsUrl));
      discovered = r.found;
      unclassified = r.unclassified;
    } catch (e) {
      if (mode === "ingest") {
        await admin.rpc("record_topic_library_sync_run", {
          p_organization_id: orgId, p_trigger_source: triggerSource, p_newest_month: null,
          p_new_count: 0, p_changed_count: 0, p_unchanged_count: 0, p_failed_count: 1,
        });
      }
      return json({ error: `Could not read the MFC downloads page: ${(e as Error).message}` }, 502);
    }
    if (discovered.length === 0) return json({ error: "No topics were found on the MFC downloads page." }, 502);

    const newestMonth = discovered.map((d) => d.month).sort().at(-1)!;
    const work = discovered.filter((d) =>
      (!SHARED_KINDS.includes(d.kind) || d.month === newestMonth) &&
      d.month.slice(0, 7) >= fromMonth &&
      (!monthsFilter || monthsFilter.includes(d.month.slice(0, 7)))
    );

    // 3 + 4. copy each page
    const results: Record<string, unknown>[] = [];
    for (const d of work) {
      const row: Record<string, unknown> = { month: d.month.slice(0, 7), kind: d.kind, url: d.url };
      try {
        const fetchedAt = new Date().toISOString();
        const blocks = extractBlocks(await fetchText(d.url));
        const headings = blocks.filter((b) => b.type === "heading").length;
        row.block_count = blocks.length;
        row.heading_count = headings;
        if (blocks.length < 3) {
          row.result = "parse_failed";
        } else if (mode === "dry_run") {
          row.result = "dry_run";
          row.headings = blocks.filter((b) => b.type === "heading").slice(0, 12).map((b) => b.text.slice(0, 80));
        } else {
          const { data, error } = await admin.rpc("ingest_topic_library_page", {
            p_organization_id: orgId,
            p_series_code: seriesCode,
            p_series_title: seriesTitle,
            p_topic_month: d.month,
            p_material_kind: d.kind,
            p_title: d.title,
            p_source_url: d.url,
            p_content_blocks: blocks,
            p_fetched_at: fetchedAt,
          });
          if (error) row.result = `error: ${error.message}`;
          else row.result = (data as any)?.result ?? "unknown";
        }
      } catch (e) {
        row.result = `fetch_failed: ${(e as Error).message}`;
      }
      results.push(row);
      await new Promise((r) => setTimeout(r, 300));
    }

    if (mode === "ingest") {
      const count = (k: string) => results.filter((r) => r.result === k).length;
      const failed = results.filter((r) => !["new_topic", "changed", "unchanged"].includes(String(r.result))).length;
      const { error: logErr } = await admin.rpc("record_topic_library_sync_run", {
        p_organization_id: orgId,
        p_trigger_source: triggerSource,
        p_newest_month: newestMonth.slice(0, 7),
        p_new_count: count("new_topic"),
        p_changed_count: count("changed"),
        p_unchanged_count: count("unchanged"),
        p_failed_count: failed,
      });
      if (logErr) console.error("record_topic_library_sync_run failed:", logErr.message);
    }

    return json({
      mode,
      trigger_source: triggerSource,
      series_code: seriesCode,
      newest_month: newestMonth.slice(0, 7),
      from_month: fromMonth,
      discovered_count: discovered.length,
      processed_count: results.length,
      unclassified_links: unclassified,
      results,
    });
  });
}
