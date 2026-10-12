// Real-Chromium check: force-update screen for an old APK build, and promo fee waiver, against a mocked Supabase.
const { chromium } = require("playwright");
const path = require("path");
const www = path.resolve(__dirname, "../../app/src/main/assets/www/index.html");
async function run(ua, settings) {
  const b = await chromium.launch({ executablePath: process.env.CHROME || "/opt/pw-browsers/chromium-1194/chrome-linux/chrome" });
  const ctx = await b.newContext({ viewport: { width: 390, height: 900 }, userAgent: ua });
  const pg = await ctx.newPage();
  await pg.route(/supabase\.co/, (r) => {
    const u = new URL(r.request().url()), m = r.request().method(), p = u.pathname;
    const j = (s, o) => r.fulfill({ status: s, contentType: "application/json", headers: { "access-control-allow-origin": "*" }, body: JSON.stringify(o) });
    if (m === "OPTIONS") return r.fulfill({ status: 204, headers: { "access-control-allow-origin": "*", "access-control-allow-headers": "*", "access-control-allow-methods": "*" } });
    if (p === "/rest/v1/platform_settings") return j(200, [Object.assign({ id: 1, fee_on: true, fee_type: "flat", fee_value: 49, support_email: "", support_whatsapp: "", promo_until: null, min_build: 0, update_url: "https://example.com/apk" }, settings)]);
    if (m === "GET") return j(200, []);
    return j(200, {});
  });
  const errs = []; pg.on("pageerror", (e) => errs.push(String(e)));
  await pg.goto("file://" + www); await pg.waitForTimeout(1500);
  const txt = await pg.evaluate(() => document.body.innerText);
  const link = await pg.evaluate(() => { const a = document.querySelector("a.btn"); return a && a.href; });
  await b.close();
  return { txt, link, errs };
}
(async () => {
  const base = "Mozilla/5.0 (Linux; Android 14) Chrome/120";
  const old = await run(base + " NirogApp/30", { min_build: 31 });
  console.log("old build blocked:", /Please update the app/.test(old.txt), "link:", old.link, "errs:", old.errs.join(";") || "none");
  const cur = await run(base + " NirogApp/31", { min_build: 31 });
  console.log("current build not blocked:", !/Please update the app/.test(cur.txt));
  const web = await run(base, { min_build: 99 });
  console.log("web (no app build) not blocked:", !/Please update the app/.test(web.txt));
})();
