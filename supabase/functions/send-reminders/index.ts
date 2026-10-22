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
//
// Pass 9.34 (Claude, 2026-10-21): push notifications on the same schedule (Web Push, VAPID).
//   * GET ?push_public_key=1 returns the VAPID public key for the app (CORS open; the public key is not secret).
//   * After the emails, claims due push reminders (public.claim_due_push_reminders, push_mode 'test' / 'on'),
//     sends one notification to each of the member's devices, records the delivery (complete_reminders, channel
//     'push') and each device's result (record_push_results; 404 / 410 = device gone, switched off).
//   Secrets: VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY (set by Ron's local script, never in the repo), VAPID_SUBJECT
//   (optional, default https://app.mfcny.net). Without them, push is skipped and email still runs.
//
// Pass 9.35 (Claude, 2026-10-21): opens / clicks for the admin Activity page.
//   * GET ?t=open&d=<delivery_id>  — email tracking image (1x1 GIF) / push shown on the device;
//   * GET ?t=click&d=<delivery_id> — email "Open My Events" button / push tapped; email clicks redirect to My Events.
//   Recorded with public.track_reminder_event (first time only). The delivery id is the only identifier used.
// =============================================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.48.0";
import webpush from "npm:web-push@3.6.7";

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

type PushClaimed = {
  delivery_id: string;
  item_kind: "event" | "meeting";
  item_id: string;
  days_before: 1 | 3;
  reminder_type: "reminder" | "nudge";
  reply: string | null;
  registered: boolean;
  item: Item;
  subscriptions: { subscription_id: string; endpoint: string; p256dh: string; auth: string }[];
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

function buildEmail(c: Claimed, appUrl: string, unsubscribeUrl: string, trackBase: string) {
  const it = c.item;
  const label = c.item_kind === "meeting" ? `${it.title}${it.group_name ? ` — ${it.group_name}` : ""}` : it.title;
  const when = whenText(it);
  const soon = c.days_before === 1 ? "tomorrow" : "in 3 days";
  const myEvents = `${appUrl}/app/my-events`;
  const clickUrl = `${trackBase}?t=click&d=${c.delivery_id}`;
  const openUrl = `${trackBase}?t=open&d=${c.delivery_id}`;
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
<p><a href="${esc(clickUrl)}" style="display:inline-block;background:#1e3a8a;color:#ffffff;text-decoration:none;padding:10px 16px;border-radius:6px">${esc(action)}</a></p>
<p>God bless,<br>MFC New York</p>
<p style="font-size:12px;color:#6b7280;margin-top:24px">You receive this because you are a member of MFC New York.
<a href="${esc(unsubscribeUrl)}" style="color:#6b7280">Stop these reminders</a> (you can turn them back on in My Profile).</p>
<img src="${esc(openUrl)}" width="1" height="1" alt="" style="display:block;border:0;width:1px;height:1px">
</body></html>`;

  return { subject, text, html };
}

function buildPush(c: PushClaimed, trackBase: string) {
  const it = c.item;
  const label = c.item_kind === "meeting" ? `${it.title}${it.group_name ? ` — ${it.group_name}` : ""}` : it.title;
  const soon = c.days_before === 1 ? "Tomorrow" : "In 3 days";
  const when = whenText(it);
  const title = c.reminder_type === "nudge" ? `Will you attend? ${label}` : `Reminder: ${label}`;
  const parts = [`${soon}${when ? ` · ${when}` : ""}`];
  if (it.location_text) parts.push(it.location_text);
  if (it.donation_pending && it.donation_pending > 0) parts.push(`Donation pending ${money(Number(it.donation_pending))}`);
  if (c.reminder_type === "nudge") parts.push("Tap to reply");
  return {
    title: title.slice(0, 120),
    body: parts.join("\n").slice(0, 300),
    url: "/app/my-events",
    track: `${trackBase}?d=${c.delivery_id}`,
    tag: `${c.item_kind}-${c.item_id}-${c.days_before}`,
  };
}

// 1x1 transparent GIF
const GIF = Uint8Array.from(atob("R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"), (ch) => ch.charCodeAt(0));

const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "GET, OPTIONS" };

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

    // 0a. Opens / clicks (Pass 9.35)
    const trackEvent = url.searchParams.get("t");
    if (trackEvent === "open" || trackEvent === "click") {
      const d = url.searchParams.get("d") ?? "";
      if (/^[0-9a-f-]{36}$/i.test(d)) {
        await admin.rpc("track_reminder_event", { p_delivery_id: d, p_event: trackEvent });
      }
      if (trackEvent === "click" && url.searchParams.get("src") !== "push") {
        const appUrl0 = (Deno.env.get("APP_URL") ?? "https://app.mfcny.net").replace(/\/+$/, "");
        return new Response(null, { status: 302, headers: { Location: `${appUrl0}/app/my-events` } });
      }
      return new Response(GIF, {
        headers: { ...CORS, "Content-Type": "image/gif", "Cache-Control": "no-store, max-age=0" },
      });
    }

    // 0. VAPID public key for the app
    if (url.searchParams.has("push_public_key")) {
      if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
      const key = Deno.env.get("VAPID_PUBLIC_KEY") ?? "";
      return new Response(JSON.stringify({ public_key: key || null }), {
        headers: { ...CORS, "Content-Type": "application/json", "Cache-Control": "max-age=300" },
      });
    }

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
    const vapidPublic = Deno.env.get("VAPID_PUBLIC_KEY") ?? "";
    const vapidPrivate = Deno.env.get("VAPID_PRIVATE_KEY") ?? "";
    const vapidSubject = Deno.env.get("VAPID_SUBJECT") ?? "https://app.mfcny.net";
    if (body.dry_run) {
      return json({ dry_run: true, resend_key_set: apiKey.length > 0, vapid_set: !!(vapidPublic && vapidPrivate),
                    from_domain: from.split("@")[1]?.replace(">", "") });
    }
    const testToday = typeof body.test_today === "string" && /^20\d\d-\d\d-\d\d$/.test(body.test_today) ? body.test_today : null;

    let sent = 0;
    let failed = 0;
    let batches = 0;
    for (; apiKey && batches < MAX_BATCHES_PER_RUN; batches++) {
      const { data: claimedData, error: claimErr } = await admin.rpc("claim_due_reminders", testToday ? { p_limit: 100, p_today: testToday } : { p_limit: 100 });
      if (claimErr) return json({ error: `claim failed: ${claimErr.message}`, sent, failed }, 500);
      const claimed = (claimedData ?? []) as Claimed[];
      if (claimed.length === 0) break;

      const payload = claimed.map((c) => {
        const unsubscribeUrl = `${supabaseUrl}/functions/v1/send-reminders?unsubscribe=${c.unsubscribe_token}`;
        const m = buildEmail(c, appUrl, unsubscribeUrl, `${supabaseUrl}/functions/v1/send-reminders`);
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

    // 3. Push notifications (Pass 9.34)
    let pushSent = 0;
    let pushFailed = 0;
    let pushDevices = 0;
    if (vapidPublic && vapidPrivate) {
      webpush.setVapidDetails(vapidSubject, vapidPublic, vapidPrivate);
      for (let round = 0; round < MAX_BATCHES_PER_RUN; round++) {
        const { data: pData, error: pErr } = await admin.rpc(
          "claim_due_push_reminders",
          testToday ? { p_limit: 200, p_today: testToday } : { p_limit: 200 },
        );
        if (pErr) return json({ error: `push claim failed: ${pErr.message}`, sent, failed, pushSent, pushFailed }, 500);
        const claimed = (pData ?? []) as PushClaimed[];
        if (claimed.length === 0) break;

        const deliveryResults: { delivery_id: string; status: "sent" | "failed"; error?: string }[] = [];
        const deviceResults: { subscription_id: string; ok: boolean; gone: boolean }[] = [];
        for (const c of claimed) {
          const payload = JSON.stringify(buildPush(c, `${supabaseUrl}/functions/v1/send-reminders`));
          const outcomes = await Promise.allSettled(c.subscriptions.map((s) =>
            webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, payload,
                                     { TTL: 86400, urgency: "normal" })));
          let anyOk = false;
          let lastErr = "";
          outcomes.forEach((o, i) => {
            pushDevices++;
            const sub = c.subscriptions[i];
            if (o.status === "fulfilled") {
              anyOk = true;
              deviceResults.push({ subscription_id: sub.subscription_id, ok: true, gone: false });
            } else {
              const code = Number((o.reason as { statusCode?: number })?.statusCode ?? 0);
              lastErr = `push ${code || "error"}: ${String((o.reason as Error)?.message ?? o.reason)}`.slice(0, 300);
              deviceResults.push({ subscription_id: sub.subscription_id, ok: false, gone: code === 404 || code === 410 });
            }
          });
          deliveryResults.push(anyOk
            ? { delivery_id: c.delivery_id, status: "sent" }
            : { delivery_id: c.delivery_id, status: "failed", error: lastErr || "no device" });
        }
        await admin.rpc("complete_reminders", { p_results: deliveryResults });
        await admin.rpc("record_push_results", { p_results: deviceResults });
        pushSent += deliveryResults.filter((r) => r.status === "sent").length;
        pushFailed += deliveryResults.filter((r) => r.status === "failed").length;
        if (claimed.length < 200) break;
      }
    }

    return json({ sent, failed, batches, test: !!testToday, email_skipped: !apiKey,
                  push: { sent: pushSent, failed: pushFailed, devices: pushDevices, skipped: !(vapidPublic && vapidPrivate) } });
  });
}
