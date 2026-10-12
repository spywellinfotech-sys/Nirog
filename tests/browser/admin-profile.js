// Real-Chromium check of the admin Full profile / Edit / Delete flow against a mocked Supabase.
const { chromium } = require("playwright");
const path = require("path");
const www = path.resolve(__dirname, "../../app/src/main/assets/www/index.html");
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROME || "/opt/pw-browsers/chromium-1194/chrome-linux/chrome" });
  const ctx = await b.newContext({ viewport: { width: 390, height: 900 } });
  await ctx.addInitScript(() => { try { localStorage.setItem("nirog-sb-session-v1", JSON.stringify({ access_token: "tok", refresh_token: "r", expires_at: Math.floor(Date.now() / 1000) + 3600, user: { id: "a1", email: "admin@x.in" } })); } catch (e) {} });
  const pg = await ctx.newPage(); const calls = [], bodies = {}; let deleted = false;
  const doc = { id: 5, name: "Dr. Mock Doc", spec: "Cardiologist", qual: "MBBS", exp_years: 8, fee_inr: 600, video_fee_inr: 0, video: false, languages: "Hindi", about: "Hello", clinic: "Mock Clinic", city: "Pune", photo_path: null, wa: null, status: "pending", verified: false, review_reason: null, ref: "DR-MOCK1" };
  await pg.route(/supabase\.co/, (r) => {
    const u = new URL(r.request().url()), m = r.request().method(), p = u.pathname; calls.push(m + " " + p);
    const j = (s, o) => r.fulfill({ status: s, contentType: "application/json", headers: { "access-control-allow-origin": "*" }, body: JSON.stringify(o) });
    if (m === "OPTIONS") return r.fulfill({ status: 204, headers: { "access-control-allow-origin": "*", "access-control-allow-headers": "*", "access-control-allow-methods": "*" } });
    let body = {}; try { body = JSON.parse(r.request().postData() || "{}"); } catch (e) {}
    if (p.endsWith("/rpc/admin_profile")) return j(200, { kind: "doctor", row: doc, email: "mock@x.in", phone: "+919876500000", verification: { council: "MC", reg_no: "R-1", reg_year: 2010 }, locations: [{ address: "1 Mock Road", pin: "411001", map_url: null }], availability: [{ weekday: 1, start_min: 600, end_min: 780, step_min: 20 }], docs: [], bookings: 0 });
    if (p.endsWith("/rpc/admin_update_doctor")) { bodies.upd = body; return j(200, true); }
    if (p.endsWith("/rpc/admin_delete_doctor")) { bodies.del = body; deleted = true; return j(200, true); }
    if (p === "/rest/v1/profiles") return j(200, [{ id: "a1", role: "admin", full_name: "Admin", phone: null, email: "admin@x.in" }]);
    if (p === "/rest/v1/doctors") return j(200, deleted ? [] : [doc]);
    if (m === "GET") return j(200, []);
    return j(200, {});
  });
  const errs = []; pg.on("pageerror", (e) => errs.push(String(e)));
  await pg.goto("file://" + www); await pg.waitForTimeout(1500);
  await pg.getByText("Mock Doc").first().waitFor({ timeout: 8000 });
  await pg.getByRole("button", { name: "Full profile" }).first().click(); await pg.waitForSelector("text=Registration no");
  const t1 = await pg.evaluate(() => document.body.innerText);
  console.log("PROFILE shows phone/council/slots:", /9876500000/.test(t1), /MC/.test(t1), /Mon/.test(t1));
  await pg.getByRole("button", { name: "Edit", exact: true }).first().click(); await pg.waitForSelector("#ce-fee_inr");
  await pg.fill("#ce-fee_inr", "750"); await pg.fill("#ce-city", "pune"); await pg.fill("#ce-about", "Edited");
  await pg.getByRole("button", { name: "Save changes" }).click(); await pg.waitForTimeout(600);
  console.log("UPDATE body:", JSON.stringify(bodies.upd && { id: bodies.upd.p_doctor, fee: bodies.upd.p.fee_inr, city: bodies.upd.p.city, about: bodies.upd.p.about }));
  await pg.getByRole("button", { name: "Delete", exact: true }).first().click();
  console.log("first tap asks again:", await pg.getByText("Tap again to delete").count() === 1, "deleted yet:", deleted);
  await pg.getByRole("button", { name: "Tap again to delete" }).click(); await pg.waitForTimeout(800);
  console.log("DELETE called:", !!bodies.del, "gone from list:", (await pg.evaluate(() => document.body.innerText)).indexOf("Mock Doc") < 0);
  console.log("pageerrors:", errs.join("; ") || "none");
  await b.close();
})();
