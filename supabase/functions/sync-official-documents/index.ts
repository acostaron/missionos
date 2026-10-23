// =============================================================================
// Supabase Edge Function: sync-official-documents
// MissionOS Pass 9.36 (written by Claude, 2026-10-21)
//
// Copies the official MFC documents and guidelines from the MFCNY shared Google Drive folder into the private
// storage bucket "official-documents" (Library > Official Documents, Unit Servant Leaders and up).
//
//   * Google access: a service account with read-only Drive scope. Its JSON key is the secret
//     GOOGLE_SERVICE_ACCOUNT_JSON_B64 (base64), set with supabase/seeds/fixes/setup_google_drive_key.mjs.
//     The folder (or the shared drive) must be shared with the service account's email as Viewer.
//     Pass 9.36C (Ron 2026-10-21): the Workspace blocks sharing outside the organization, so the service account
//     can act as one dedicated mfcny.net account (domain-wide delegation, drive.readonly only). That account's email
//     is the secret GOOGLE_DRIVE_AS_USER; the folder is then shared with that account instead.
//   * The folder id is set by an administrator in the app (public.set_official_documents_folder).
//   * Category = name of the top-level subfolder; files directly in the folder are "General". Deeper folders are
//     kept as folder_path. Shortcuts are followed.
//   * PDFs and Word / Excel / PowerPoint files are copied as they are; Google Docs / Sheets / Slides / Drawings are
//     copied as PDF. Other file types are skipped.
//   * Only new or changed files are copied. Files no longer in the folder are removed. An empty listing removes
//     nothing (most likely the folder is no longer shared).
//   * Copies stop after about 100 seconds; the rest are copied by the next run ("pending").
//
// Callers: an administrator (JWT, checked with public.get_official_documents_access), or the daily pg_cron job
// (header x-sync-secret checked against Vault). verify_jwt is off for this function (config.toml).
// Request body: { organization_id: uuid, action?: "sync" | "info" }
//   "info" (administrators): returns the email to share the folder with (the dedicated account, or the service
//   account when GOOGLE_DRIVE_AS_USER is not set).
// The response never contains file contents or secrets.
// =============================================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.48.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-sync-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const DRIVE = "https://www.googleapis.com/drive/v3";
const TIME_BUDGET_MS = 100_000;
const MAX_BYTES = 45 * 1024 * 1024;
const MAX_FOLDERS = 200;

const FOLDER = "application/vnd.google-apps.folder";
const SHORTCUT = "application/vnd.google-apps.shortcut";
const PDF = "application/pdf";

/** Files copied as they are: mime -> extension */
const AS_IS: Record<string, string> = {
  [PDF]: "pdf",
  "application/msword": "doc",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "docx",
  "application/vnd.ms-excel": "xls",
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": "xlsx",
  "application/vnd.ms-powerpoint": "ppt",
  "application/vnd.openxmlformats-officedocument.presentationml.presentation": "pptx",
};
/** Google files exported as PDF */
const EXPORT_PDF = new Set([
  "application/vnd.google-apps.document",
  "application/vnd.google-apps.spreadsheet",
  "application/vnd.google-apps.presentation",
  "application/vnd.google-apps.drawing",
]);

type ServiceAccount = { client_email: string; private_key: string; token_uri?: string };

type DriveFile = {
  id: string;
  name: string;
  mimeType: string;
  modifiedTime: string;
  size?: string;
  md5Checksum?: string;
  shortcutDetails?: { targetId: string; targetMimeType: string };
};

export type ListedItem = {
  drive_file_id: string;
  title: string;
  category: string;
  folder_path: string | null;
  source_mime_type: string;
  stored_mime_type: string;
  file_extension: string;
  drive_modified_at: string;
  drive_md5: string | null;
  size: number | null;
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

function b64url(bytes: Uint8Array | string): string {
  const b = typeof bytes === "string" ? new TextEncoder().encode(bytes) : bytes;
  let s = "";
  for (let i = 0; i < b.length; i++) s += String.fromCharCode(b[i]);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToDer(pem: string): ArrayBuffer {
  const body = pem.replace(/-----BEGIN [^-]+-----/, "").replace(/-----END [^-]+-----/, "").replace(/\s+/g, "");
  const bin = atob(body);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out.buffer;
}

export function readServiceAccount(b64: string | undefined): ServiceAccount | null {
  if (!b64) return null;
  try {
    const sa = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(b64.trim()), (c) => c.charCodeAt(0))));
    if (typeof sa?.client_email !== "string" || typeof sa?.private_key !== "string") return null;
    return sa as ServiceAccount;
  } catch {
    return null;
  }
}

export async function googleAccessToken(sa: ServiceAccount, asUser?: string | null): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/drive.readonly",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
    ...(asUser ? { sub: asUser } : {}),
  }));
  const key = await crypto.subtle.importKey(
    "pkcs8", pemToDer(sa.private_key), { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"],
  );
  const sig = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claims}`)));
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${header}.${claims}.${b64url(sig)}`,
    }),
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok || typeof body?.access_token !== "string") {
    if (asUser && body?.error === "unauthorized_client") {
      throw new Error("Google has not allowed MissionOS to read Drive as the dedicated account yet " +
        "(Admin console → Security → API controls → Domain-wide delegation: add the Client ID with the " +
        "scope https://www.googleapis.com/auth/drive.readonly). It can take a few minutes to start working.");
    }
    if (asUser && body?.error === "invalid_grant") {
      throw new Error(`Google did not accept the account ${asUser} (check the spelling, and that it is an active mfcny.net account).`);
    }
    throw new Error(`Google sign-in for the service account failed (${res.status} ${body?.error ?? ""}).`);
  }
  return body.access_token;
}

async function driveGet(token: string, path: string, params: Record<string, string>): Promise<Response> {
  const u = new URL(`${DRIVE}${path}`);
  for (const [k, v] of Object.entries(params)) u.searchParams.set(k, v);
  return await fetch(u, { headers: { Authorization: `Bearer ${token}` } });
}

async function listChildren(token: string, folderId: string): Promise<DriveFile[]> {
  const out: DriveFile[] = [];
  let pageToken = "";
  do {
    const params: Record<string, string> = {
      q: `'${folderId}' in parents and trashed = false`,
      fields: "nextPageToken, files(id, name, mimeType, modifiedTime, size, md5Checksum, shortcutDetails)",
      pageSize: "1000",
      supportsAllDrives: "true",
      includeItemsFromAllDrives: "true",
      corpora: "allDrives",
    };
    if (pageToken) params.pageToken = pageToken;
    const res = await driveGet(token, "/files", params);
    if (!res.ok) throw new Error(`Drive listing failed (${res.status}).`);
    const body = await res.json();
    out.push(...((body.files ?? []) as DriveFile[]));
    pageToken = body.nextPageToken ?? "";
  } while (pageToken);
  return out;
}

async function getFile(token: string, id: string): Promise<DriveFile | null> {
  const res = await driveGet(token, `/files/${id}`, {
    fields: "id, name, mimeType, modifiedTime, size, md5Checksum",
    supportsAllDrives: "true",
  });
  if (!res.ok) return null;
  return (await res.json()) as DriveFile;
}

function stripExtension(name: string): string {
  const t = name.replace(/\.(pdf|docx?|xlsx?|pptx?)$/i, "").trim();
  return t || name;
}

/** Walks the folder. Category = top-level subfolder name. */
export async function listFolder(
  token: string,
  rootId: string,
): Promise<{ items: ListedItem[]; skipped: string[] }> {
  const items = new Map<string, ListedItem>();
  const skipped: string[] = [];
  const visited = new Set<string>([rootId]);
  const queue: { id: string; path: string[] }[] = [{ id: rootId, path: [] }];

  const rootRes = await driveGet(token, `/files/${rootId}`, { fields: "id, mimeType", supportsAllDrives: "true" });
  if (rootRes.status === 404 || rootRes.status === 403) {
    throw new Error("NOT_SHARED");
  }
  if (!rootRes.ok) throw new Error(`Drive folder check failed (${rootRes.status}).`);
  const root = await rootRes.json();
  if (root?.mimeType !== FOLDER) throw new Error("NOT_A_FOLDER");

  while (queue.length > 0) {
    const { id, path } = queue.shift()!;
    for (const f0 of await listChildren(token, id)) {
      let f: DriveFile | null = f0;
      if (f0.mimeType === SHORTCUT && f0.shortcutDetails?.targetId) {
        if (f0.shortcutDetails.targetMimeType === FOLDER) {
          f = { ...f0, id: f0.shortcutDetails.targetId, mimeType: FOLDER };
        } else {
          const target = await getFile(token, f0.shortcutDetails.targetId);
          f = target ? { ...target, name: f0.name } : null;
        }
      }
      if (!f) { skipped.push(f0.name); continue; }

      if (f.mimeType === FOLDER) {
        if (!visited.has(f.id) && visited.size < MAX_FOLDERS) {
          visited.add(f.id);
          queue.push({ id: f.id, path: [...path, f.name.trim()] });
        }
        continue;
      }

      let stored: string, ext: string;
      if (AS_IS[f.mimeType]) { stored = f.mimeType; ext = AS_IS[f.mimeType]; }
      else if (EXPORT_PDF.has(f.mimeType)) { stored = PDF; ext = "pdf"; }
      else { skipped.push(f.name); continue; }

      if (items.has(f.id)) continue;
      items.set(f.id, {
        drive_file_id: f.id,
        title: stripExtension(f.name).slice(0, 300),
        category: (path[0] ?? "General").slice(0, 120),
        folder_path: path.length > 1 ? path.slice(1).join(" / ").slice(0, 300) : null,
        source_mime_type: f.mimeType,
        stored_mime_type: stored,
        file_extension: ext,
        drive_modified_at: f.modifiedTime,
        drive_md5: f.md5Checksum ?? null,
        size: f.size ? Number(f.size) : null,
      });
    }
  }
  return { items: Array.from(items.values()), skipped };
}

async function downloadFile(token: string, id: string, sourceMime: string): Promise<Uint8Array> {
  const res = EXPORT_PDF.has(sourceMime)
    ? await driveGet(token, `/files/${id}/export`, { mimeType: PDF })
    : await driveGet(token, `/files/${id}`, { alt: "media", supportsAllDrives: "true" });
  if (!res.ok) {
    if (res.status === 403 && EXPORT_PDF.has(sourceMime)) throw new Error("Google could not convert it to PDF (too large?).");
    throw new Error(`download failed (${res.status})`);
  }
  const len = Number(res.headers.get("content-length") ?? "0");
  if (len > MAX_BYTES) throw new Error("larger than 45 MB");
  const bytes = new Uint8Array(await res.arrayBuffer());
  if (bytes.length > MAX_BYTES) throw new Error("larger than 45 MB");
  return bytes;
}

if (import.meta.main) {
  serve(async (req: Request) => {
    if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
    if (req.method !== "POST") return json({ error: "Method not allowed." }, 405);
    const started = Date.now();

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const authHeader = req.headers.get("Authorization") ?? "";
    const syncSecret = req.headers.get("x-sync-secret") ?? "";
    if (!syncSecret && !authHeader.startsWith("Bearer ")) return json({ error: "Authentication is required." }, 401);
    const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });

    // deno-lint-ignore no-explicit-any
    let body: any;
    try { body = await req.json(); } catch { return json({ error: "Invalid JSON body." }, 400); }
    const orgId = String(body?.organization_id ?? "");
    if (!/^[0-9a-f-]{36}$/i.test(orgId)) return json({ error: "organization_id is required." }, 400);
    const action = body?.action === "info" ? "info" : "sync";

    const library = body?.library === "support" ? "support" : "official";
    const bucket = library === "support" ? "support-documents" : "official-documents";

    // 1. Who is calling?
    let triggerSource: "scheduled" | "manual" = "manual";
    if (syncSecret) {
      const { data: ok, error } = await admin.rpc("verify_docs_sync_secret", { p_secret: syncSecret });
      if (error || ok !== true) return json({ error: "Not authorised." }, 401);
      triggerSource = "scheduled";
      if (action === "info") return json({ error: "Not available." }, 400);
    } else {
      const caller = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authHeader } } });
      const accessRpc = library === "support" ? "get_support_documents_access" : "get_official_documents_access";
      const { data: access, error } = await caller.rpc(accessRpc, { p_organization_id: orgId });
      if (error) return json({ error: `Permission check failed: ${error.message}` }, 403);
      if (access?.can_manage !== true) {
        return json({
          error: library === "support"
            ? "Only administrators can sync Support documents."
            : "Only administrators can sync the Official Documents.",
        }, 403);
      }
    }

    const sa = readServiceAccount(Deno.env.get("GOOGLE_SERVICE_ACCOUNT_JSON_B64"));
    const asUserRaw = (Deno.env.get("GOOGLE_DRIVE_AS_USER") ?? "").trim();
    const asUser = /^[^@\s]+@[^@\s]+\.[a-z]{2,}$/i.test(asUserRaw) ? asUserRaw : null;
    const shareWith = asUser ?? sa?.client_email ?? null;
    if (action === "info") {
      return json({ service_account_email: shareWith, acting_as_user: asUser !== null, key_set: sa !== null });
    }

    const record = async (r: { listed?: number; new_?: number; updated?: number; removed?: number; skipped?: number;
                                failed?: number; pending?: number; error?: string | null }) => {
      const recordRpc = library === "support" ? "record_support_documents_sync_run" : "record_official_documents_sync_run";
      const { error } = await admin.rpc(recordRpc, {
        p_organization_id: orgId, p_trigger_source: triggerSource, p_listed: r.listed ?? 0, p_new: r.new_ ?? 0,
        p_updated: r.updated ?? 0, p_removed: r.removed ?? 0, p_skipped: r.skipped ?? 0, p_failed: r.failed ?? 0,
        p_pending: r.pending ?? 0, p_error: r.error ?? null,
      });
      if (error) console.error(`${recordRpc} failed:`, error.message);
    };

    if (!sa) {
      const msg = "The Google service account key is not set (GOOGLE_SERVICE_ACCOUNT_JSON_B64).";
      await record({ error: msg });
      return json({ error: msg }, 500);
    }
    const getFolderRpc = library === "support" ? "get_support_documents_folder" : "get_official_documents_folder";
    const { data: folderId, error: folderErr } = await admin.rpc(getFolderRpc, { p_organization_id: orgId });
    if (folderErr) return json({ error: `Could not read the folder setting: ${folderErr.message}` }, 500);
    if (!folderId) return json({ error: "No Drive folder is set yet." }, 400);

    // 2. List the folder
    let token: string;
    let listed: { items: ListedItem[]; skipped: string[] };
    try {
      token = await googleAccessToken(sa, asUser);
      listed = await listFolder(token, String(folderId));
    } catch (e) {
      const m = (e as Error).message;
      const msg = m === "NOT_SHARED"
        ? `MissionOS cannot see this folder. Share it (or the shared drive) with ${shareWith} as Viewer.`
        : m === "NOT_A_FOLDER" ? "The link is not a Google Drive folder." : m;
      await record({ error: msg });
      return json({ error: msg }, 502);
    }
    if (listed.items.length === 0) {
      const msg = "No documents were found in the folder. Nothing was changed.";
      await record({ skipped: listed.skipped.length, error: msg });
      return json({ error: msg, skipped: listed.skipped }, 502);
    }

    // 3. Save the listing; remove documents no longer in the folder
    const applyRpc = library === "support" ? "apply_support_documents_listing" : "apply_official_documents_listing";
    const { data: applied, error: applyErr } = await admin.rpc(applyRpc, {
      p_organization_id: orgId,
      p_items: listed.items.map(({ size: _s, ...rest }) => rest),
    });
    if (applyErr) {
      await record({ listed: listed.items.length, error: applyErr.message });
      return json({ error: `Could not save the list: ${applyErr.message}` }, 500);
    }
    const removedPaths: string[] = (applied?.removed_paths ?? []).filter((p: unknown) => typeof p === "string");
    if (removedPaths.length > 0) {
      const { error } = await admin.storage.from(bucket).remove(removedPaths);
      if (error) console.error("remove failed:", error.message);
    }

    // 4. Copy new / changed files
    const toCopyRpc = library === "support" ? "support_documents_to_copy" : "official_documents_to_copy";
    const { data: toCopy, error: copyErr } = await admin.rpc(toCopyRpc, { p_organization_id: orgId });
    if (copyErr) {
      await record({ listed: listed.items.length, error: copyErr.message });
      return json({ error: copyErr.message }, 500);
    }
    // deno-lint-ignore no-explicit-any
    const work: any[] = Array.isArray(toCopy) ? toCopy : [];
    let copied = 0, updated = 0, pending = 0;
    const failed: { title: string; error: string }[] = [];
    for (const w of work) {
      if (Date.now() - started > TIME_BUDGET_MS) { pending++; continue; }
      try {
        const bytes = await downloadFile(token, w.drive_file_id, w.source_mime_type);
        const path = `${orgId}/${w.drive_file_id}.${w.file_extension}`;
        const { error: upErr } = await admin.storage.from(bucket).upload(path, bytes, {
          contentType: w.stored_mime_type, upsert: true, cacheControl: "300",
        });
        if (upErr) throw new Error(`storage: ${upErr.message}`);
        const markRpc = library === "support" ? "mark_support_document_copied" : "mark_official_document_copied";
        const { data: res, error: markErr } = await admin.rpc(markRpc, {
          p_organization_id: orgId, p_drive_file_id: w.drive_file_id, p_storage_path: path,
          p_file_size: bytes.length, p_copied_modified_at: w.drive_modified_at, p_copied_md5: w.drive_md5 ?? "",
        });
        if (markErr) throw new Error(markErr.message);
        if (res === "updated") updated++; else if (res === "copied") copied++;
        if (w.old_storage_path && w.old_storage_path !== path) {
          await admin.storage.from(bucket).remove([w.old_storage_path]);
        }
      } catch (e) {
        failed.push({ title: String(w.title ?? ""), error: (e as Error).message.slice(0, 200) });
      }
    }

    await record({
      listed: listed.items.length, new_: copied, updated, removed: removedPaths.length,
      skipped: listed.skipped.length, failed: failed.length, pending,
    });
    return json({
      trigger_source: triggerSource,
      listed_count: listed.items.length,
      copied_count: copied,
      updated_count: updated,
      unchanged_count: listed.items.length - work.length,
      removed_count: removedPaths.length,
      pending_count: pending,
      skipped: listed.skipped.slice(0, 50),
      failed,
    });
  });
}
