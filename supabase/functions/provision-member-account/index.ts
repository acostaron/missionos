// =============================================================================
// Supabase Edge Function: provision-member-account
// MissionOS Stage 2B — Pass 2H-1B: Member Account Invitation Backend Foundation
//
// Responsibilities:
// 1. Authenticate caller JWT (reject anon or missing token).
// 2. Validate request payload (organization_id, member_id, email).
// 3. Perform preflight eligibility check using CALLER client (caller context).
// 4. Resolve Auth user state safely:
//    - Case 1: No existing user -> check SITE_URL, send GoTrue invite, status 'sent'.
//    - Case 2: Usable existing account -> reuse auth_user_id, NO GoTrue invite,
//              status 'existing_account_invitation_pending'.
//    - Case 3: Unusable/ambiguous account -> reject with controlled error.
// 5. Finalize profile & invited membership using ADMIN client (service-role).
// 6. Deterministic failure compensation: clean up newly created Auth user on DB failure.
// =============================================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.48.0";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export interface ProvisionRequest {
  organization_id: string;
  member_id: string;
  email: string;
  acknowledge_shared?: boolean;
}

export interface AuthAdminAdapter {
  lookupUser(organizationId: string, email: string): Promise<any>;
  inviteUser(email: string, redirectTo: string): Promise<{ id: string; isNew: boolean }>;
  deleteUser(userId: string): Promise<void>;
}

export class SupabaseAuthAdminAdapter implements AuthAdminAdapter {
  constructor(private adminClient: any) {}

  async lookupUser(organizationId: string, email: string): Promise<any> {
    const { data, error } = await this.adminClient.rpc("lookup_auth_user_for_invitation", {
      p_organization_id: organizationId,
      p_email: email,
    });
    if (error) {
      throw new Error(`Auth user lookup failed: ${error.message}`);
    }
    return data;
  }

  async inviteUser(email: string, redirectTo: string): Promise<{ id: string; isNew: boolean }> {
    const { data, error } = await this.adminClient.auth.admin.inviteUserByEmail(email, {
      redirectTo,
    });
    if (error) {
      throw new Error(`GoTrue invitation failed: ${error.message}`);
    }
    if (!data?.user?.id) {
      throw new Error("GoTrue invitation succeeded but returned no user ID");
    }
    return { id: data.user.id, isNew: true };
  }

  async deleteUser(userId: string): Promise<void> {
    const { error } = await this.adminClient.auth.admin.deleteUser(userId);
    if (error) {
      console.error(`Compensating cleanup failed to delete auth user ${userId}:`, error.message);
    }
  }
}

/**
 * Validates and derives the application origin redirect URL.
 * Requires SITE_URL (or MISSIONOS_APP_URL) and strictly forbids fallback to SUPABASE_URL.
 */
export function getInvitationRedirectUrl(env: { get(key: string): string | undefined }): string {
  const origin = (env.get("SITE_URL") || env.get("MISSIONOS_APP_URL") || "").trim();
  if (!origin) {
    throw new Error("Server configuration error: Application origin (SITE_URL) is not configured");
  }

  try {
    const parsed = new URL(origin);
    const normalized = `${parsed.origin}${parsed.pathname}`.replace(/\/+$/, "");
    return `${normalized}/invite/accept`;
  } catch {
    throw new Error(`Server configuration error: Application origin (${origin}) is not a valid URL`);
  }
}

export async function handleProvisionMemberAccount(
  req: Request,
  authAdapterOverride?: AuthAdminAdapter,
  envOverride?: { get(key: string): string | undefined },
): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ error: "Method not allowed" }),
      { status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  // 1. Authenticate caller JWT
  const authHeader = req.headers.get("Authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return new Response(
      JSON.stringify({ error: "Missing or invalid Authorization header" }),
      { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  const token = authHeader.replace("Bearer ", "").trim();
  if (!token) {
    return new Response(
      JSON.stringify({ error: "Missing access token" }),
      { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  const env = envOverride ?? Deno.env;
  const supabaseUrl = env.get("SUPABASE_URL") ?? "";
  const supabaseAnonKey = env.get("SUPABASE_ANON_KEY") ?? "";
  const supabaseServiceRoleKey = env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

  if (!supabaseUrl || !supabaseAnonKey || !supabaseServiceRoleKey) {
    return new Response(
      JSON.stringify({ error: "Server configuration missing required Supabase environment keys" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  // 2. Client separation: CALLER client
  const callerClient = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: { user: callerUser }, error: userError } = await callerClient.auth.getUser();
  if (userError || !callerUser) {
    return new Response(
      JSON.stringify({ error: "Invalid or expired session token" }),
      { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  // Parse and validate request body
  let body: ProvisionRequest;
  try {
    body = await req.json();
  } catch {
    return new Response(
      JSON.stringify({ error: "Malformed JSON payload" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  const { organization_id, member_id, email, acknowledge_shared } = body;
  if (!organization_id || !member_id || !email || typeof email !== "string") {
    return new Response(
      JSON.stringify({ error: "organization_id, member_id, and email are required" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  const normalizedEmail = email.trim().toLowerCase();
  const emailRegex = /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/;
  if (!emailRegex.test(normalizedEmail)) {
    return new Response(
      JSON.stringify({ error: "Invalid email format" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  // 3. Preflight check via CALLER client (enforces caller permissions & data checks)
  const { data: preflight, error: preflightError } = await callerClient.rpc(
    "prepare_member_account_invitation",
    {
      p_organization_id: organization_id,
      p_member_id: member_id,
      p_email: normalizedEmail,
      p_acknowledge_shared: !!acknowledge_shared,
    },
  );

  if (preflightError) {
    const isForbidden = preflightError.message?.toLowerCase().includes("not authorized");
    return new Response(
      JSON.stringify({ error: preflightError.message, code: preflightError.code }),
      { status: isForbidden ? 403 : 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  if (preflight?.status === "requires_shared_acknowledgment" || preflight?.eligible === false) {
    return new Response(
      JSON.stringify({
        error: preflight.warning || "Shared email requires explicit administrator acknowledgment",
        status: "requires_shared_acknowledgment",
        preflight,
      }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  // 4. ADMIN client (server-side only with service role key)
  const adminClient = createClient(supabaseUrl, supabaseServiceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const authAdapter = authAdapterOverride ?? new SupabaseAuthAdminAdapter(adminClient);

  // 5. Existing Auth user handling
  let authUserId: string;
  let newlyCreatedAuthUser = false;
  let targetInvitationStatus: string = "sent";

  try {
    const authLookup = await authAdapter.lookupUser(organization_id, normalizedEmail);

    if (authLookup?.user_exists) {
      // Check if already linked to a member
      if (authLookup.is_linked_to_member) {
        if (authLookup.linked_member_id !== member_id) {
          return new Response(
            JSON.stringify({
              error: "An account with this email is already linked to a different member",
              code: "23505",
            }),
            { status: 409, headers: { ...corsHeaders, "Content-Type": "application/json" } },
          );
        } else {
          return new Response(
            JSON.stringify({
              error: "Member is already linked to this account",
              code: "23505",
            }),
            { status: 409, headers: { ...corsHeaders, "Content-Type": "application/json" } },
          );
        }
      }

      // CASE 2: Usable existing account
      if (authLookup.is_usable) {
        authUserId = authLookup.auth_user_id;
        newlyCreatedAuthUser = false;
        targetInvitationStatus = "existing_account_invitation_pending";
        // Do NOT call GoTrue inviteUserByEmail for an existing usable account
      } else {
        // CASE 3: Unusable or ambiguous account state -> reject
        return new Response(
          JSON.stringify({
            error: `Existing account cannot be invited: ${authLookup.unusable_reason || "Account state is ambiguous or inactive"}`,
            code: "ACCOUNT_UNUSABLE",
          }),
          { status: 409, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }
    } else {
      // CASE 1: No auth user exists -> invite via GoTrue admin
      // Application origin redirect check must pass BEFORE calling GoTrue
      let redirectUrl: string;
      try {
        redirectUrl = getInvitationRedirectUrl(env);
      } catch (redirectErr: any) {
        return new Response(
          JSON.stringify({ error: redirectErr.message }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      const inviteResult = await authAdapter.inviteUser(normalizedEmail, redirectUrl);
      authUserId = inviteResult.id;
      newlyCreatedAuthUser = inviteResult.isNew;
      targetInvitationStatus = "sent";
    }
  } catch (authError: any) {
    return new Response(
      JSON.stringify({ error: authError.message || "Failed to resolve or invite auth user" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  // 6. Finalize in Database transactionally using service role
  try {
    const { data: finalizeData, error: finalizeError } = await adminClient.rpc(
      "finalize_member_account_invitation",
      {
        p_organization_id: organization_id,
        p_member_id: member_id,
        p_auth_user_id: authUserId,
        p_email: normalizedEmail,
        p_actor_profile_id: callerUser.id,
        p_invitation_status: targetInvitationStatus,
      },
    );

    if (finalizeError) {
      throw new Error(finalizeError.message);
    }

    // 7. Safe JSON response
    return new Response(
      JSON.stringify({
        invitation_id: finalizeData.invitation_id,
        member_id: finalizeData.member_id,
        profile_id: finalizeData.profile_id,
        organization_id: finalizeData.organization_id,
        status: finalizeData.status,
        email: finalizeData.email,
        invited_at: finalizeData.invited_at,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (finalizationError: any) {
    console.error("Database finalization error:", finalizationError.message);

    // Compensation Strategy (Option 1):
    // Delete newly created Auth user if created during this invocation
    if (newlyCreatedAuthUser && authUserId) {
      try {
        await authAdapter.deleteUser(authUserId);
      } catch (cleanupErr: any) {
        console.error(`Compensating Auth cleanup failed for ${authUserId}:`, cleanupErr.message);
      }
    }

    // Record auditable failure record (Option 2 recovery)
    try {
      await adminClient.rpc("record_member_account_invitation_failure", {
        p_organization_id: organization_id,
        p_member_id: member_id,
        p_email: normalizedEmail,
        p_actor_profile_id: callerUser.id,
        p_failure_reason: finalizationError.message,
      });
    } catch (failureRecordErr: any) {
      console.error("Failed to record invitation failure state:", failureRecordErr.message);
    }

    return new Response(
      JSON.stringify({
        error: `Database finalization failed: ${finalizationError.message}`,
      }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
}

// Start HTTP server in Deno environment
if (import.meta.main) {
  serve((req: Request) => handleProvisionMemberAccount(req));
}
