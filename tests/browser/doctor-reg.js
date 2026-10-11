// Real-Chromium check of doctor registration with real image/PDF uploads against a mocked Supabase.
const { chromium } = require("playwright");
const path = require("path");
const KIT = process.env.KIT || "kit";
const www = path.resolve(__dirname, "../../app/src/main/assets/www/index.html");
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROME || "/opt/pw-browsers/chromium-1194/chrome-linux/chrome" });
  const pg = await b.newPage({ viewport: { width: 390, height: 800 } });
  const calls = [];
  await pg.route(/supabase\.co/, (r) => {
    const u = new URL(r.request().url()), m = r.request().method(); calls.push(m + " " + u.pathname);
    const j = (s, o) => r.fulfill({ status: s, contentType: "application/json", headers: { "access-control-allow-origin": "*" }, body: JSON.stringify(o) });
    if (m === "OPTIONS") return r.fulfill({ status: 204, headers: { "access-control-allow-origin": "*", "access-control-allow-headers": "*", "access-control-allow-methods": "*" } });
    if (u.pathname === "/auth/v1/signup") return j(200, { access_token: "t", refresh_token: "r", expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600, user: { id: "11111111-1111-1111-1111-111111111111" } });
    if (u.pathname === "/auth/v1/token") return j(200, { access_token: "t", refresh_token: "r", expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600, user: { id: "11111111-1111-1111-1111-111111111111" } });
    if (u.pathname.startsWith("/storage/")) return j(200, { Key: "x" });
    if (u.pathname.endsWith("/rpc/register_doctor")) {
      // PostgREST: the function is register_doctor(p jsonb), so the body must be {"p": {...}}; anything else is a 404 (PGRST202).
      let body = {}; try { body = JSON.parse(r.request().postData() || "{}"); } catch (e) {}
      if (!body || typeof body.p !== "object" || !/^[6-9]\d{9}$/.test(body.p.phone || "")) return j(404, { code: "PGRST202", message: "Could not find the function public.register_doctor" });
      return j(200, { id: 9, ref: "DR-TEST1" });
    }
    if (u.pathname.endsWith("/rpc/my_doctor_id")) return j(200, null);
    if (m === "GET") return j(200, []);
    return j(200, {});
  });
  const errs = []; pg.on("pageerror", (e) => errs.push(String(e)));
  await pg.goto("file://" + www + "#register");
  await pg.waitForSelector("#rg-addr");
  const fill = async (sel, v) => { await pg.fill(sel, v); };
  const byLabel = async (label, v) => { await pg.getByLabel(label, { exact: false }).first().fill(v); };
  await byLabel("Full name", "Test Sharma"); await byLabel("Qualification", "MBBS, MD"); await fill("#rg-exp", "10");
  await byLabel("Clinic name", "Sample Care Clinic"); await pg.fill("#rg-city", "Pune");
  await fill("#rg-addr", "12 Sample Road, Koregaon Park"); await fill("#rg-pin", "411001"); await fill("#rg-map", "18.5362, 73.8940");
  await byLabel("Council or board", "Sample Medical Council"); await byLabel("Registration number", "TEST-123"); await fill("#rg-ryear", "2012");
  await fill("#rg-fee", "600"); await fill("#rg-phone", "9876543210"); await fill("#rg-email", "t" + Date.now() + "@example.com"); await fill("#rg-pass", "Sample#12345");
  await pg.setInputFiles("#up-photo", path.join(KIT, "doctor-profile-photo.jpg"));
  await pg.waitForTimeout(500);
  if (!process.env.NOGAL) await pg.setInputFiles("#up-gal", [path.join(KIT, "clinic-photo-front.jpg"), path.join(KIT, "clinic-photo-room.jpg")]);
  await pg.waitForTimeout(800);
  const docs = await pg.locator('input[type=file][id^="up-"]').evaluateAll((els) => els.map((e) => e.id));
  console.log("file inputs:", docs.join(","));
  await pg.setInputFiles("#up-reg", path.join(KIT, "doctor-registration-certificate.pdf")); await pg.waitForTimeout(400);
  await pg.setInputFiles("#up-id", path.join(KIT, "photo-id-sample.jpg")); await pg.waitForTimeout(500);
  console.log("gallery thumbs / state:", await pg.evaluate(() => document.querySelectorAll("#app img").length));
  await pg.click("button[type=submit]");
  await pg.waitForTimeout(2500);
  const txt = await pg.evaluate(() => document.querySelector("#app").innerText);
  console.log("ERR:", (txt.match(/Cannot submit[^\n]*|could not[^\n]*|Could not[^\n]*/gi) || []).join(" | "));
  console.log("DONE SCREEN:", /submitted|under review|DR-TEST1/i.test(txt));
  console.log("calls:", calls.join("; "));
  console.log("pageerrors:", errs.join("; ") || "none");
  await pg.screenshot({ path: process.env.SHOT || "reg.png", fullPage: false });
  await b.close();
})();
