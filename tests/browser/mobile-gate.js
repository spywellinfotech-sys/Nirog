// Real-Chromium check against a mocked Supabase: a patient who signed in with Google (no mobile on the profile) must add one before using the app.
const { chromium } = require("playwright");
const path = require("path");
const www = path.resolve(__dirname, "../../app/src/main/assets/www/index.html");
(async () => {
  let ok = true; const check = (n, c) => { console.log((c ? "PASS " : "FAIL ") + n); if (!c) ok = false; };
  const b = await chromium.launch({ executablePath: process.env.CHROME || "/opt/pw-browsers/chromium-1194/chrome-linux/chrome" });
  const ctx = await b.newContext({ viewport: { width: 390, height: 900 } });
  await ctx.addInitScript(() => { try { localStorage.setItem("nirog-sb-session-v1", JSON.stringify({ access_token: "tok", refresh_token: "r", expires_at: Math.floor(Date.now() / 1000) + 3600, user: { id: "p1", email: "g@x.in" } })); } catch (e) {} });
  const pg = await ctx.newPage(); const st = { saved: null, phone: null, fail: null };
  await pg.route(/supabase\.co/, (r) => {
    const u = new URL(r.request().url()), m = r.request().method(), p = u.pathname;
    const j = (s, o) => r.fulfill({ status: s, contentType: "application/json", headers: { "access-control-allow-origin": "*" }, body: JSON.stringify(o) });
    if (m === "OPTIONS") return r.fulfill({ status: 204, headers: { "access-control-allow-origin": "*", "access-control-allow-headers": "*", "access-control-allow-methods": "*" } });
    let body = {}; try { body = JSON.parse(r.request().postData() || "{}"); } catch (e) {}
    if (p.endsWith("/rpc/set_my_mobile")) { if (st.fail) return j(400, { message: st.fail }); st.saved = body; st.phone = "+91" + body.p_mobile; return j(200, null); }
    if (p === "/rest/v1/profiles") return j(200, [{ id: "p1", role: "patient", full_name: "Asha", phone: st.phone, email: "g@x.in" }]);
    if (m === "GET") return j(200, []);
    return j(200, {});
  });
  const errs = []; pg.on("pageerror", (e) => errs.push(String(e)));
  await pg.goto("file://" + www); await pg.waitForTimeout(1800);
  const txt = () => pg.evaluate(() => document.body.innerText);
  check("a patient without a mobile sees the Add your mobile number screen", /Add your mobile number/.test(await txt()) && (await pg.locator("#mg-phone").count()) === 1);
  check("the app is not usable behind it", (await pg.locator('button[data-a="tab"]').count()) === 0);
  await pg.fill("#mg-phone", "12345"); await pg.dispatchEvent("#mg-phone", "input");
  await pg.locator('button[data-a="mgsave"]').click(); await pg.waitForTimeout(300);
  check("a short number is refused and nothing is sent", /valid 10-digit/.test(await txt()) && !st.saved);
  await pg.fill("#mg-phone", "5876543210"); await pg.dispatchEvent("#mg-phone", "input");
  await pg.locator('button[data-a="mgsave"]').click(); await pg.waitForTimeout(300);
  check("a number starting with 5 is refused", /valid 10-digit/.test(await txt()) && !st.saved);
  await pg.fill("#mg-phone", "9876543210"); await pg.dispatchEvent("#mg-phone", "input");
  await pg.locator('button[data-a="mgsave"]').click(); await pg.waitForTimeout(900);
  check("a valid number is saved", st.saved && st.saved.p_mobile === "9876543210");
  check("the patient then reaches the app", !/Add your mobile number/.test(await txt()) && (await pg.locator('button[data-a="tab"]').count()) > 0);
  check("no page errors", errs.length === 0);
  await b.close();
  console.log(ok ? "ALL PASSED" : "SOME FAILED"); process.exit(ok ? 0 : 1);
})();
