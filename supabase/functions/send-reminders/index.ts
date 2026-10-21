// =============================================================================
// Supabase Edge Function: send-reminders
// MissionOS Pass 9.33 (written by Claude, 2026-10-21)
//
// Email reminders 3 days and 1 day before household meetings and events (Ron's choices):
//   * "reminder" to members who replied Attending or are registered;
//   * "nudge" (Will you attend?) to members who could attend and have not replied.
//
// Callers:
//   * POST from the scheduled job (pg_cron -> private.run_reminders), header x-reminders-secret checked against
//     Vault with public.verify_reminders_secret. Claims what is due (public.claim_due_reminders), sends it through
//     Resend's batch API (100 per call) and records each result (public.complete_reminders).
//     Body { "dry_run": true } claims nothing and only reports how the function is configured.
//     Body { "test_today": "YYYY-MM-DD" } sends as if today were that day — only for organizations in 'test' mode
//     (enforced in claim_due_reminders), so only the test member is emailed.
//   * GET / POST ?unsubscribe=<token> from the link in every email (and one-click List-Unsubscribe):
//     switches that member's email reminders off (public.reminder_unsubscribe).
// verify_jwt is off for this function (config.toml).
//
// Secrets / settings (Supabase Edge Function secrets):
//   RESEND_API_KEY   (required, never in the repo)
//   REMINDERS_FROM   (optional, default "MFC New York <reminders@auth.mfcny.net>")
//   APP_URL          (optional, default "https://app.mfcny.net")
// The response never contains email addresses or names.
// =============================================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.48.0";

const TZ = "America/New_York";
const MAX_BATCHES_PER_RUN = 5;

type Item = {
  title: string;
  starts_at: string | null;
  meeting_date?: string | null;
  ends_at: string | null;
  location_text: string | null;
  group_name: string | null;
  registration_open: boolean;
  donation_pending: number | null;
};

type Claimed = {
  delivery_id: string;
  item_kind: "event" | "meeting";
  item_id: string;
  days_before: 1 | 3;
  reminder_type: "reminder" | "nudge";
  reply: string | null;
  registered: boolean;
  email: string;
  name: string;
  unsubscribe_token: string;
  item: Item;
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

function esc(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

function whenText(item: Item): string {
  if (item.starts_at) {
    const d = new Date(item.starts_at);
    const day = new Intl.DateTimeFormat("en-US", { timeZone: TZ, weekday: "long", month: "long", day: "numeric" }).format(d);
    const time = new Intl.DateTimeFormat("en-US", { timeZone: TZ, hour: "numeric", minute: "2-digit" }).format(d);
    return `${day} at ${time}`;
  }
  if (item.meeting_date) {
    const d = new Date(`${item.meeting_date}T12:00:00Z`);
    return new Intl.DateTimeFormat("en-US", { timeZone: "UTC", weekday: "long", month: "long", day: "numeric" }).format(d);
  }
  return "";
}

function money(n: number): string {
  return n.toLocaleString("en-US", { style: "currency", currency: "USD" });
}

function buildEmail(c: Claimed, appUrl: string, unsubscribeUrl: string) {
  const it = c.item;
  const label = c.item_kind === "meeting" ? `${it.title}${it.group_name ? ` — ${it.group_name}` : ""}` : it.title;
  const when = whenText(it);
  const soon = c.days_before === 1 ? "tomorrow" : "in 3 days";
  const myEvents = `${appUrl}/app/my-events`;
  const mapUrl = it.location_text
    ? `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(it.location_text)}`
    : null;

  const subject = c.reminder_type === "nudge"
    ? `Will you attend? ${label} — ${soon}`
    : `Reminder: ${label} — ${soon}`;

  const lead = c.reminder_type === "nudge"
    ? `${label} is ${soon}. Please let us know if you will attend.`
    : c.registered && c.reply !== "attending"
      ? `You are registered for ${label}, ${soon}.`
      : `Thank you for replying Attending. ${label} is ${soon}.`;

  const lines: string[] = [];
  if (when) lines.push(`When: ${when}`);
  if (it.location_text) lines.push(`Where: ${it.location_text}`);
  if (it.donation_pending && it.donation_pending > 0) {
    lines.push(`Suggested donation pending: ${money(Number(it.donation_pending))} — you can donate by Zelle, PayPal, check or cash (see My Events).`);
  }
  const action = c.reminder_type === "nudge" ? "Reply Attending / Not attending in My Events" : "Open My Events";

  const text = [
    `Dear ${c.name},`,
    "",
    lead,
    "",
    ...lines,
    "",
    `${action}: ${myEvents}`,
    mapUrl ? `Map: ${mapUrl}` : "",
    "",
    "God bless,",
    "MFC New York",
    "",
    `To stop these reminders: ${unsubscribeUrl}`,
  ].filter((l, i, a) => !(l === "" && a[i - 1] === "")).join("\n");

  const html = `<!doctype html><html><body style="font-family:Arial,Helvetica,sans-serif;color:#1f2937;line-height:1.5;max-width:560px;margin:0 auto;padding:16px">
<p>Dear ${esc(c.name)},</p>
<p>${esc(lead)}</p>
<table style="border-collapse:collapse;margin:8px 0 16px">
${when ? `<tr><td style="padding:2px 12px 2px 0;color:#6b7280">When</td><td style="padding:2px 0"><strong>${esc(when)}</strong></td></tr>` : ""}
${it.location_text ? `<tr><td style="padding:2px 12px 2px 0;color:#6b7280">Where</td><td style="padding:2px 0">${esc(it.location_text)}${mapUrl ? ` &middot; <a href="${esc(mapUrl)}">Map</a>` : ""}</td></tr>` : ""}
${it.donation_pending && it.donation_pending > 0 ? `<tr><td style="padding:2px 12px 2px 0;color:#6b7280">Donation</td><td style="padding:2px 0">Suggested donation pending: <strong>${esc(money(Number(it.donation_pending)))}</strong> — Zelle, PayPal, check or cash (see My Events)</td></tr>` : ""}
</table>
<p><a href="${esc(myEvents)}" style="display:inline-block;background:#1e3a8a;color:#ffffff;text-decoration:none;padding:10px 16px;border-radius:6px">${esc(action)}</a></p>
<p>God bless,<br>MFC New York</p>
<p style="font-size:12px;color:#6b7280;margin-top:24px">You receive this because you are a member of MFC New York.
<a href="${esc(unsubscribeUrl)}" style="color:#6b7280">Stop these reminders</a> (you can turn them back on in My Profile).</p>
</body></html>`;

  return { subject, text, html };
}

function page(message: string, status = 200): Response {
  return new Response(
    `<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>MFC New York</title></head>` +
      `<body style="font-family:Arial,Helvetica,sans-serif;max-width:480px;margin:48px auto;padding:16px;color:#1f2937">` +
      `<h1 style="font-size:20px">MFC New York</h1><p>${esc(message)}</p></body></html>`,
    { status, headers: { "Content-Type": "text/html; charset=utf-8" } },
  );
}

if (import.meta.main) {
  serve(async (req: Request) => {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });
    const url = new URL(req.url);

    // 1. Unsubscribe link (GET) or one-click unsubscribe (POST with ?unsubscribe=)
    const token = url.searchParams.get("unsubscribe");
    if (token !== null) {
      if (!/^[0-9a-f-]{36}$/i.test(token)) return page("This link is not valid.", 400);
      const { data, error } = await admin.rpc("reminder_unsubscribe", { p_token: token });
      if (error) return page("Something went wrong. Please try again later.", 500);
      return (data as { unsubscribed?: boolean })?.unsubscribed
        ? page("You will no longer receive email reminders. You can turn them back on in My Profile in MissionOS.")
        : page("This link is not valid.", 404);
    }

    // 2. Scheduled run
    if (req.method !== "POST") return json({ error: "Method not allowed." }, 405);
    const secret = req.headers.get("x-reminders-secret") ?? "";
    const { data: ok, error: secretErr } = await admin.rpc("verify_reminders_secret", { p_secret: secret });
    if (secretErr || ok !== true) return json({ error: "Not authorised." }, 401);

    let body: { dry_run?: boolean; test_today?: string } = {};
    try { body = await req.json(); } catch { body = {}; }

    const apiKey = Deno.env.get("RESEND_API_KEY") ?? "";
    const from = Deno.env.get("REMINDERS_FROM") ?? "MFC New York <reminders@auth.mfcny.net>";
    const appUrl = (Deno.env.get("APP_URL") ?? "https://app.mfcny.net").replace(/\/+$/, "");
    if (body.dry_run) return json({ dry_run: true, resend_key_set: apiKey.length > 0, from_domain: from.split("@")[1]?.replace(">", "") });
    if (!apiKey) return json({ error: "RESEND_API_KEY is not set." }, 500);
    const testToday = typeof body.test_today === "string" && /^20\d\d-\d\d-\d\d$/.test(body.test_today) ? body.test_today : null;

    let sent = 0;
    let failed = 0;
    let batches = 0;
    for (; batches < MAX_BATCHES_PER_RUN; batches++) {
      const { data: claimedData, error: claimErr } = await admin.rpc("claim_due_reminders", testToday ? { p_limit: 100, p_today: testToday } : { p_limit: 100 });
      if (claimErr) return json({ error: `claim failed: ${claimErr.message}`, sent, failed }, 500);
      const claimed = (claimedData ?? []) as Claimed[];
      if (claimed.length === 0) break;

      const payload = claimed.map((c) => {
        const unsubscribeUrl = `${supabaseUrl}/functions/v1/send-reminders?unsubscribe=${c.unsubscribe_token}`;
        const m = buildEmail(c, appUrl, unsubscribeUrl);
        return {
          from,
          to: [c.email],
          subject: m.subject,
          html: m.html,
          text: m.text,
          headers: {
            "List-Unsubscribe": `<${unsubscribeUrl}>`,
            "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
          },
        };
      });

      let results: { delivery_id: string; status: "sent" | "failed"; provider_message_id?: string; error?: string }[];
      try {
        const res = await fetch("https://api.resend.com/emails/batch", {
          method: "POST",
          headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
          body: JSON.stringify(payload),
        });
        const out = await res.json().catch(() => ({}));
        if (res.ok && Array.isArray(out?.data)) {
          results = claimed.map((c, i) => ({
            delivery_id: c.delivery_id,
            status: out.data[i]?.id ? "sent" : "failed",
            provider_message_id: out.data[i]?.id,
            error: out.data[i]?.id ? undefined : "no id returned",
          }));
        } else {
          const msg = `Resend ${res.status}: ${String(out?.message ?? out?.error?.message ?? "error")}`.slice(0, 300);
          results = claimed.map((c) => ({ delivery_id: c.delivery_id, status: "failed", error: msg }));
        }
      } catch (e) {
        const msg = `send failed: ${String((e as Error)?.message ?? e)}`.slice(0, 300);
        results = claimed.map((c) => ({ delivery_id: c.delivery_id, status: "failed", error: msg }));
      }

      await admin.rpc("complete_reminders", { p_results: results });
      sent += results.filter((r) => r.status === "sent").length;
      failed += results.filter((r) => r.status === "failed").length;
      if (results.every((r) => r.status === "failed")) break; // stop on a provider error; next hour retries
      if (claimed.length < 100) { batches++; break; }
    }
    return json({ sent, failed, batches, test: !!testToday });
  });
}
