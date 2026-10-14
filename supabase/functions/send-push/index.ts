// Sends a broadcast as a phone push notification (Firebase Cloud Messaging, HTTP v1). Only a super admin may call it.
// Secrets: FIREBASE_SERVICE_ACCOUNT (the service account JSON, required). SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are provided by Supabase.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const URL_ = Deno.env.get("SUPABASE_URL")!;
const SRV = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const db = createClient(URL_, SRV, { auth: { persistSession: false } });
const cors = { "access-control-allow-origin": "*", "access-control-allow-headers": "authorization, apikey, content-type, x-client-info", "access-control-allow-methods": "POST, OPTIONS" };
const out = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { ...cors, "content-type": "application/json" } });

// <jwt>
function b64url(data: any) {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : new Uint8Array(data);
  let s = ""; for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
function pemToDer(pem: string) {
  const b = atob(pem.replace(/-----[A-Z ]+-----/g, "").replace(/\s+/g, ""));
  const u = new Uint8Array(b.length); for (let i = 0; i < b.length; i++) u[i] = b.charCodeAt(i);
  return u.buffer;
}
async function signJwt(sa: any, now: number) {
  const head = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = b64url(JSON.stringify({ iss: sa.client_email, scope: "https://www.googleapis.com/auth/firebase.messaging", aud: sa.token_uri || "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600 }));
  const key = await crypto.subtle.importKey("pkcs8", pemToDer(sa.private_key), { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(head + "." + claim));
  return head + "." + claim + "." + b64url(sig);
}
// </jwt>

async function accessToken(sa: any) {
  const jwt = await signJwt(sa, Math.floor(Date.now() / 1000));
  const r = await fetch(sa.token_uri || "https://oauth2.googleapis.com/token", {
    method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: jwt }),
  });
  const j = await r.json().catch(() => ({}));
  if (!r.ok || !j.access_token) { console.error("oauth", r.status, JSON.stringify(j).slice(0, 300)); throw new Error("push_auth_failed"); }
  return j.access_token as string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method !== "POST") return out({ error: "method" }, 405);
  const jwt = (req.headers.get("authorization") || "").replace(/^Bearer\s+/i, "");
  if (!jwt) return out({ error: "not_authenticated" }, 401);
  const { data: u } = await db.auth.getUser(jwt);
  if (!u?.user) return out({ error: "not_authenticated" }, 401);
  const { data: staff } = await db.from("staff_members").select("role,active").eq("user_id", u.user.id).maybeSingle();
  if (!staff || staff.role !== "admin" || !staff.active) return out({ error: "admins_only" }, 403);

  let b: any; try { b = await req.json(); } catch { return out({ error: "bad_request" }, 400); }
  const id = Number(b.broadcast_id);
  if (!Number.isInteger(id) || id < 1) return out({ error: "bad_request" }, 400);
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
  if (!raw) return out({ error: "push_not_configured" }, 503);
  let sa: any; try { sa = JSON.parse(raw); } catch { return out({ error: "push_not_configured" }, 503); }
  if (!sa.project_id || !sa.client_email || !sa.private_key) return out({ error: "push_not_configured" }, 503);

  const { data: bc } = await db.from("broadcasts").select("id,title,body,image_path").eq("id", id).maybeSingle();
  if (!bc) return out({ error: "not_found" }, 404);
  const { data: rows, error } = await db.rpc("broadcast_tokens", { p_broadcast: id });
  if (error) { console.error("tokens", error.message); return out({ error: "server_error" }, 500); }
  const tokens: string[] = [...new Set((rows || []).map((r: any) => r.token as string))];
  if (!tokens.length) return out({ ok: true, total: 0, sent: 0, failed: 0, removed: 0 });

  let at: string; try { at = await accessToken(sa); } catch { return out({ error: "push_auth_failed" }, 502); }
  const image = bc.image_path ? `${URL_}/storage/v1/object/public/broadcast-media/${bc.image_path}` : undefined;
  const notification: any = { title: bc.title, body: bc.body || bc.title };
  if (image) notification.image = image;
  const dead: string[] = []; let sent = 0, failed = 0;
  const send = async (token: string) => {
    const r = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
      method: "POST", headers: { authorization: `Bearer ${at}`, "content-type": "application/json" },
      body: JSON.stringify({ message: { token, notification, android: { priority: "HIGH", notification: { channel_id: "nirog_broadcasts" } }, data: { broadcast_id: String(id) } } }),
    });
    if (r.ok) { sent++; return; }
    failed++;
    const j = await r.json().catch(() => ({}));
    const code = JSON.stringify(j).includes("UNREGISTERED") || r.status === 404;
    if (code) dead.push(token); else console.error("fcm", r.status, JSON.stringify(j).slice(0, 200));
  };
  for (let i = 0; i < tokens.length; i += 25) await Promise.all(tokens.slice(i, i + 25).map(send));
  let removed = 0;
  if (dead.length) { const { data: n } = await db.rpc("remove_push_tokens", { p_tokens: dead }); removed = Number(n) || 0; }
  return out({ ok: true, total: tokens.length, sent, failed, removed });
});
