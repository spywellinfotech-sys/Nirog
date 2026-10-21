// Real-Chromium check of the patient rating flow against a mocked Supabase.
const { chromium } = require("playwright");
const path = require("path");
const www = path.resolve(__dirname, "../../app/src/main/assets/www/index.html");
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROME || "/opt/pw-browsers/chromium-1194/chrome-linux/chrome" });
  const ctx = await b.newContext({ viewport: { width: 390, height: 900 } });
  await ctx.addInitScript(() => { try { localStorage.setItem("nirog-sb-session-v1", JSON.stringify({ access_token: "tok", refresh_token: "r", expires_at: Math.floor(Date.now() / 1000) + 3600, user: { id: "p1", email: "pat@x.in" } })); } catch (e) {} });
  const pg = await ctx.newPage(); let sent = null, reviewed = false;
  const doc = { id: 7, name: "Dr. Review Me", spec: "Cardiologist", qual: "MBBS", exp_years: 8, fee_inr: 600, video_fee_inr: 0, video: false, languages: "Hindi", about: "Hello", clinic: "Mock Clinic", city: "Pune", photo_path: null, wa: null, status: "approved", verified: true, ref: "DR-M" };
  const past = new Date(Date.now() - 3 * 86400000).toISOString().slice(0, 10);
  const booking = { id: "b-1", ref: "BK-1", doctor_id: 7, slot_date: past, slot_time: "10:00:00", mode: "clinic", patient_name: "Asha Verma", patient_age: 30, patient_sex: "Female", patient_phone: "9876500011", reason: "", doctor_fee: 600, platform_fee: 0, status: "confirmed", decision_reason: null, retimed: false };
  await pg.route(/supabase\.co/, (r) => {
    const u = new URL(r.request().url()), m = r.request().method(), p = u.pathname;
    const j = (s, o) => r.fulfill({ status: s, contentType: "application/json", headers: { "access-control-allow-origin": "*" }, body: JSON.stringify(o) });
    if (m === "OPTIONS") return r.fulfill({ status: 204, headers: { "access-control-allow-origin": "*", "access-control-allow-headers": "*", "access-control-allow-methods": "*" } });
    let body = {}; try { body = JSON.parse(r.request().postData() || "{}"); } catch (e) {}
    if (p.endsWith("/rpc/submit_review")) { sent = body; reviewed = true; return j(200, { id: 1 }); }
    if (p === "/rest/v1/profiles") return j(200, [{ id: "p1", role: "patient", full_name: "Asha Verma", phone: "+919876500001", email: "pat@x.in" }]);
    if (p === "/rest/v1/doctors") return j(200, [doc]);
    if (p === "/rest/v1/bookings") return j(200, [booking]);
    if (p === "/rest/v1/reviews") return j(200, reviewed ? [{ booking_id: "b-1", rating: 4, comment: "Great" }] : []);
    if (p === "/rest/v1/doctor_ratings") return j(200, reviewed ? [{ doctor_id: 7, avg_rating: 4, n: 1 }] : []);
    if (p === "/rest/v1/doctor_reviews") return j(200, reviewed ? [{ id: 1, doctor_id: 7, rating: 4, comment: "Great", patient_name: "Asha", created_at: "2026-10-12T00:00:00Z" }] : []);
    if (m === "GET") return j(200, []);
    return j(200, {});
  });
  const errs = []; pg.on("pageerror", (e) => errs.push(String(e)));
  await pg.goto("file://" + www); await pg.waitForTimeout(1500);
  await pg.locator('[data-a="tab"][data-v="appts"]').first().click().catch(async () => { await pg.getByText(/Appointments/i).first().click(); });
  await pg.locator('[data-a="aflt"][data-v="p:mark"]').click({ timeout: 8000 }); await pg.waitForTimeout(300);
  await pg.getByRole("button", { name: "Rate this visit" }).click();
  await pg.getByRole("button", { name: "4 ★" }).click();
  await pg.fill("#rv-comment", "Great");
  await pg.getByRole("button", { name: "Submit review" }).click(); await pg.waitForTimeout(800);
  console.log("RPC body:", JSON.stringify(sent));
  console.log("shows my rating:", /Your rating/.test(await pg.evaluate(() => document.body.innerText)));
  console.log("confirmed clinic visit shows Google Maps links:", /Open in Google Maps/.test(await pg.evaluate(() => document.body.innerText)) && /Directions/.test(await pg.evaluate(() => document.body.innerText)));
  console.log("pageerrors:", errs.join("; ") || "none");
  await b.close();
})();
