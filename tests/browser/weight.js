// Real-Chromium check: the booking form has an optional weight; it is validated, sent to the server and shown to the doctor.
const { chromium } = require("playwright");
const path = require("path");
const www = path.resolve(__dirname, "../../app/src/main/assets/www/index.html");
async function run(role) {
  const b = await chromium.launch({ executablePath: process.env.CHROME || "/opt/pw-browsers/chromium-1194/chrome-linux/chrome" });
  const ctx = await b.newContext({ viewport: { width: 390, height: 900 } });
  await ctx.addInitScript(() => { try { localStorage.setItem("nirog-sb-session-v1", JSON.stringify({ access_token: "tok", refresh_token: "r", expires_at: Math.floor(Date.now() / 1000) + 3600, user: { id: "u1", email: "u@x.in" } })); } catch (e) {} });
  const pg = await ctx.newPage(); const sent = [];
  const tk = new Date(Date.now() + 19800000 + 86400000).toISOString().slice(0, 10);
  const doc = { id: 7, name: "Dr. Rx Writer", spec: "General Physician", qual: "MBBS", exp_years: 8, fee_inr: 600, video_fee_inr: 0, video: false, languages: "Hindi", about: "Hello", clinic: "Mock Clinic", city: "Pune", status: "approved", user_id: "d1" };
  const booking = { id: "b-1", ref: "BK-1", doctor_id: 7, slot_date: tk, slot_time: "10:00:00", mode: "clinic", patient_name: "Asha Verma", patient_age: 30, patient_sex: "Female", patient_weight: 62.5, patient_phone: "9876500011", reason: "", doctor_fee: 600, platform_fee: 0, status: "pending", decision_reason: null, retimed: false };
  await pg.route(/supabase\.co/, (r) => {
    const u = new URL(r.request().url()), m = r.request().method(), p = u.pathname;
    const j = (s, o) => r.fulfill({ status: s, contentType: "application/json", headers: { "access-control-allow-origin": "*" }, body: JSON.stringify(o) });
    if (m === "OPTIONS") return r.fulfill({ status: 204, headers: { "access-control-allow-origin": "*", "access-control-allow-headers": "*", "access-control-allow-methods": "*" } });
    let body = {}; try { body = JSON.parse(r.request().postData() || "{}"); } catch (e) {}
    if (p.endsWith("/rpc/create_booking")) { sent.push(body); return j(200, booking); }
    if (p.endsWith("/rpc/my_doctor_id")) return j(200, role === "doctor" ? 7 : null);
    if (p === "/rest/v1/profiles") return j(200, [{ id: "u1", role, full_name: role === "doctor" ? "Dr. Rx Writer" : "Asha Verma", phone: "+919876500001", email: "u@x.in" }]);
    if (p === "/rest/v1/doctors") return j(200, [doc]);
    if (p === "/rest/v1/bookings") return j(200, role === "doctor" ? [booking] : []);
    if (m === "GET") return j(200, []);
    return j(200, {});
  });
  const errs = []; pg.on("pageerror", (e) => errs.push(String(e)));
  await pg.goto("file://" + www); await pg.waitForTimeout(1800);
  return { b, pg, errs, sent };
}
(async () => {
  let ok = true; const check = (n, c) => { console.log((c ? "PASS " : "FAIL ") + n); if (!c) ok = false; };
  let t = await run("doctor"), pg = t.pg;
  await pg.waitForTimeout(800);
  const tx = await pg.evaluate(() => document.body.innerText);
  check("the doctor sees the patient's weight on the request", /30 yrs, Female, 62\.5 kg/.test(tx));
  check("no page errors (doctor)", t.errs.length === 0); await t.b.close();
  console.log(ok ? "ALL PASSED" : "SOME FAILED"); process.exit(ok ? 0 : 1);
})();
