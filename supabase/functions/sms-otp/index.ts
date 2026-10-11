// Sends and verifies SMS OTPs through apitxt.com and returns a Supabase session.
// Secrets: APITXT_AUTH_KEY (required), APITXT_TEMPLATE_ID (optional). SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are provided by Supabase.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const URL_ = Deno.env.get("SUPABASE_URL")!;
const SRV = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const db = createClient(URL_, SRV, { auth: { persistSession: false } });
const cors = { "access-control-allow-origin": "*", "access-control-allow-headers": "authorization, apikey, content-type, x-client-info", "access-control-allow-methods": "POST, OPTIONS" };
const out = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { ...cors, "content-type": "application/json" } });
const hex = (b: ArrayBuffer) => [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, "0")).join("");
const hash = async (m: string, c: string) => hex(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`${m}:${c}:${SRV}`)));

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method !== "POST") return out({ error: "method" }, 405);
  let b: any; try { b = await req.json(); } catch { return out({ error: "bad_request" }, 400); }
  const mobile = String(b.mobile || "");
  if (!/^[6-9]\d{9}$/.test(mobile)) return out({ error: "bad_mobile" }, 400);

  if (b.action === "send") {
    const since = new Date(Date.now() - 10 * 60_000).toISOString();
    const { count } = await db.from("sms_otps").select("id", { count: "exact", head: true }).eq("mobile", mobile).gte("created_at", since);
    if ((count ?? 0) >= 3) return out({ error: "rate_limited" }, 429);
    const code = String(100000 + (crypto.getRandomValues(new Uint32Array(1))[0] % 900000));
    const key = Deno.env.get("APITXT_AUTH_KEY");
    if (!key) return out({ error: "sms_not_configured" }, 503);
    const form = new URLSearchParams({ authkey: key, mobile: "91" + mobile, otp: code });
    const tpl = Deno.env.get("APITXT_TEMPLATE_ID"); if (tpl) form.set("template_id", tpl);
    let ok = false;
    try {
      const r = await fetch("https://apitxt.com/api/sendOTP", { method: "POST", body: form });
      const j = await r.json().catch(() => ({}));
      ok = r.ok && j.status === "success";
      if (!ok) console.error("apitxt", r.status, JSON.stringify(j).slice(0, 300));
    } catch (e) { console.error("apitxt fetch", String(e)); }
    if (!ok) return out({ error: "sms_failed" }, 502);
    await db.from("sms_otps").insert({ mobile, code_hash: await hash(mobile, code), expires_at: new Date(Date.now() + 5 * 60_000).toISOString() });
    return out({ ok: true });
  }

  if (b.action === "verify") {
    const code = String(b.code || "");
    if (!/^\d{6}$/.test(code)) return out({ error: "invalid_otp" }, 400);
    const { data: row } = await db.from("sms_otps").select("*").eq("mobile", mobile).eq("consumed", false)
      .gte("expires_at", new Date().toISOString()).order("created_at", { ascending: false }).limit(1).maybeSingle();
    if (!row || row.attempts >= 5) return out({ error: "invalid_otp" }, 400);
    if (row.code_hash !== await hash(mobile, code)) {
      await db.from("sms_otps").update({ attempts: row.attempts + 1 }).eq("id", row.id);
      return out({ error: "invalid_otp" }, 400);
    }
    await db.from("sms_otps").update({ consumed: true }).eq("id", row.id);
    const email = `p${mobile}@sms.nirog.invalid`;
    const cu = await db.auth.admin.createUser({ email, email_confirm: true, user_metadata: { phone: "+91" + mobile } });
    if (cu.error && !/already|exists|registered/i.test(cu.error.message)) return out({ error: "user_failed" }, 500);
    const gl = await db.auth.admin.generateLink({ type: "magiclink", email });
    const th = gl.data?.properties?.hashed_token;
    if (gl.error || !th) return out({ error: "session_failed" }, 500);
    const r = await fetch(`${URL_}/auth/v1/verify`, { method: "POST", headers: { apikey: ANON, "content-type": "application/json" }, body: JSON.stringify({ type: "magiclink", token_hash: th }) });
    const sess = await r.json();
    if (!r.ok || !sess.access_token) return out({ error: "session_failed" }, 500);
    await db.from("profiles").update({ phone: "+91" + mobile }).eq("id", sess.user.id);
    return out(sess);
  }
  return out({ error: "bad_action" }, 400);
});
