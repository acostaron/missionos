// =============================================================================
// Supabase Edge Function: claim-member-account
// MissionOS Pass 8.1 — Member login by one-time personal claim code (written by Claude, 2026-10-14)
//
// Public endpoint (no login needed). Actions:
//   { action: "check", code }                      -> { valid, masked_name, expires_at } | { valid:false, reason }
//   { action: "claim", code, email, password }     -> creates the login, links it to the member,
//                                                    returns { status:"success" } (the app then signs in)
//   { action: "claim_signed_in", code } + Bearer   -> links an EXISTING signed-in login to the member
//
// Security:
//   * Only the hash of the code is stored; the database functions validate it.
//   * Wrong codes are counted per client address; 10 wrong tries in 15 minutes block that address for 15 minutes.
//   * If linking fails after a NEW login was created, that new login is deleted again (no orphan logins).
//   * The service-role key never leaves this function.
// =============================================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.48.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function clientKey(req: Request): string {
  const fwd = req.headers.get("x-forwarded-for") ?? "";
  const first = fwd.split(",")[0]?.trim();
  return first || req.headers.get("cf-connecting-ip") || "unknown";
}

const emailRegex = /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/;

serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return json({ error: "Server configuration is incomplete." }, 500);
  }
  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  let body: { action?: string; code?: string; email?: string; password?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Malformed request." }, 400);
  }

  const action = body.action ?? "";
  const code = (body.code ?? "").toString().trim();
  const key = clientKey(req);
  if (!code || code.length > 40) return json({ error: "Enter your code." }, 400);

  // ---- check -----------------------------------------------------------------
  if (action === "check") {
    const { data, error } = await admin.rpc("check_member_claim_code", { p_code: code, p_client_key: key });
    if (error) return json({ error: "Could not check the code right now. Please try again." }, 500);
    return json(data);
  }

  // ---- claim with a NEW login --------------------------------------------------
  if (action === "claim") {
    const email = (body.email ?? "").toString().trim().toLowerCase();
    const password = (body.password ?? "").toString();
    if (!emailRegex.test(email)) return json({ error: "Enter a valid email address." }, 400);
    if (password.length < 8) return json({ error: "Choose a password of at least 8 characters." }, 400);

    const { data: check, error: checkErr } = await admin.rpc("check_member_claim_code", { p_code: code, p_client_key: key });
    if (checkErr) return json({ error: "Could not check the code right now. Please try again." }, 500);
    if (!check?.valid) return json({ error: reasonText(check?.reason) }, 400);

    const { data: exists, error: existsErr } = await admin.rpc("claim_email_has_login", { p_email: email });
    if (existsErr) return json({ error: "Could not check the email right now. Please try again." }, 500);
    if (exists === true) {
      return json({
        error: "This email already has a MissionOS login. Sign in first, then enter your code on the claim page.",
        code: "email_has_login",
      }, 409);
    }

    const { data: created, error: createErr } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });
    if (createErr || !created?.user) {
      return json({ error: "Could not create the login. Please check the email and try again." }, 400);
    }

    const { data: redeemed, error: redeemErr } = await admin.rpc("redeem_member_claim_code", {
      p_code: code,
      p_auth_user_id: created.user.id,
      p_email: email,
      p_client_key: key,
    });
    if (redeemErr) {
      await admin.auth.admin.deleteUser(created.user.id).catch(() => undefined);
      return json({ error: redeemErr.message || "Could not link your login. Please contact your chapter servant." }, 400);
    }
    return json({ status: "success", member_id: redeemed?.member_id ?? null });
  }

  // ---- claim with an EXISTING signed-in login ------------------------------------
  if (action === "claim_signed_in") {
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) return json({ error: "Please sign in first." }, 401);
    const caller = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { data: { user }, error: userErr } = await caller.auth.getUser();
    if (userErr || !user || !user.email) return json({ error: "Please sign in again." }, 401);

    const { data: redeemed, error: redeemErr } = await admin.rpc("redeem_member_claim_code", {
      p_code: code,
      p_auth_user_id: user.id,
      p_email: user.email,
      p_client_key: key,
    });
    if (redeemErr) return json({ error: redeemErr.message || "Could not link your login." }, 400);
    return json({ status: "success", member_id: redeemed?.member_id ?? null });
  }

  return json({ error: "Unknown action." }, 400);
});

function reasonText(reason?: string): string {
  switch (reason) {
    case "too_many_attempts":
      return "Too many wrong codes were tried. Please wait 15 minutes and try again.";
    case "expired":
      return "This code has expired. Ask your chapter servant for a new code.";
    case "already_used":
      return "This code was already used. If you can't sign in, ask your chapter servant for help.";
    default:
      return "This code is not valid. Check it and try again, or ask your chapter servant.";
  }
}
