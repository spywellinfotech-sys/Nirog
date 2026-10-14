// Real-Chromium check of phone push wiring against a mocked Supabase: the app registers the phone token, and the admin send triggers send-push.
const { chromium } = require("playwright");
const path = require("path");
const www = path.resolve(__dirname, "../../app/src/main/assets/www/index.html");
const TOKEN = "fcm-token-abcdefghijklmnopqrstuvwxyz-0123456789";
async function open(role) {
  const b = await chromium.launch({ executablePath: process.env.CHROME || "/opt/pw-browsers/chromium-1194/chrome-linux/chrome" });
  const ctx = await b.newContext({ viewport: { width: 390, height: 900 } });
  await ctx.addInitScript((a) => {
    try { localStorage.setItem("nirog-sb-session-v1", JSON.stringify({ access_token: "tok", refresh_token: "r", expires_at: Math.floor(Date.now() / 1000) + 3600, user: { id: a.id, email: "u@x.in" } })); } catch (e) {}
    window.NirogNative = { pushToken: function () { return a.tok; } };
  }, { id: role === "admin" ? "a1" : "p1", tok: TOKEN });
  const pg = await ctx.newPage(); const st = { reg: [], push: [] };
  await pg.route(/supabase\.co/, (r) => {
    const u = new URL(r.request().url()), m = r.request().method(), p = u.pathname;
    const j = (s, o) => r.fulfill({ status: s, contentType: "application/json", headers: { "access-control-allow-origin": "*" }, body: JSON.stringify(o) });
    if (m === "OPTIONS") return r.fulfill({ status: 204, headers: { "access-control-allow-origin": "*", "access-control-allow-headers": "*", "access-control-allow-methods": "*" } });
    let body = {}; try { body = JSON.parse(r.request().postData() || "{}"); } catch (e) {}
    if (p.endsWith("/rpc/register_push_token")) { st.reg.push(body); return j(200, true); }
    if (p.endsWith("/functions/v1/send-push")) { st.push.push(body); return j(200, { ok: true, total: 3, sent: 3, failed: 0, removed: 0 }); }
    if (p.endsWith("/rpc/admin_send_broadcast")) return j(200, { id: 9, title: body.p.title, body: body.p.body, audience: body.p.audience, sent_count: 4, created_at: new Date().toISOString() });
    if (p.endsWith("/rpc/admin_broadcast_reach")) return j(200, 4);
    if (p === "/rest/v1/profiles") return j(200, [{ id: role === "admin" ? "a1" : "p1", role: role, full_name: "X", phone: null, email: "u@x.in" }]);
    if (m === "GET") return j(200, []);
    return j(200, {});
  });
  const errs = []; pg.on("pageerror", (e) => errs.push(String(e)));
  await pg.goto("file://" + www); await pg.waitForTimeout(1800);
  return { b, pg, st, errs };
}
(async () => {
  let ok = true; const check = (n, c) => { console.log((c ? "PASS " : "FAIL ") + n); if (!c) ok = false; };
  let t = await open("patient");
  check("patient phone token is registered once", t.st.reg.length === 1 && t.st.reg[0].p_token === TOKEN);
  await t.pg.reload(); await t.pg.waitForTimeout(1500);
  check("same token is not registered again", t.st.reg.length === 1);
  check("no page errors (patient)", t.errs.length === 0); await t.b.close();
  t = await open("admin"); const pg = t.pg;
  await pg.getByRole("button", { name: "Notify" }).click();
  await pg.fill("#bf-title", "Offer"); await pg.fill("#bf-body", "Hello");
  await pg.getByRole("button", { name: "Review and send" }).click();
  await pg.getByRole("button", { name: "Yes, send now" }).click(); await pg.waitForTimeout(1200);
  const txt = await pg.evaluate(() => document.body.innerText);
  check("send-push is called with the broadcast id", t.st.push.length === 1 && t.st.push[0].broadcast_id === 9);
  check("admin sees the phone count", /Push sent to 3 phones/.test(txt));
  check("no page errors (admin)", t.errs.length === 0); await t.b.close();
  process.exit(ok ? 0 : 1);
})();
