// Real-Chromium check against a mocked Supabase: floating ambulance button, national numbers on top, local and all-location services,
// small professional links, announcements in the bell, and the admin overview counts and ambulance tab.
const { chromium } = require("playwright");
const path = require("path");
const www = path.resolve(__dirname, "../../app/src/main/assets/www/index.html");
const AMB = [
  { id: 1, name: "City Care Ambulance", phone: "9876543210", city: "Pune", kind: "private", note: "24x7", active: true },
  { id: 2, name: "Anywhere Ambulance", phone: "9123456789", city: null, kind: "private", note: "", active: true },
  { id: 3, name: "Delhi Rapid Ambulance", phone: "9000011111", city: "Delhi", kind: "govt", note: "", active: true },
];
const BC = [{ id: 7, title: "Free eye camp", body: "Sunday at the town hall", audience: "all", image_path: null, video_path: null, created_at: new Date().toISOString(), revoked_at: null }];
async function open(role) {
  const b = await chromium.launch({ executablePath: process.env.CHROME || "/opt/pw-browsers/chromium-1194/chrome-linux/chrome" });
  const ctx = await b.newContext({ viewport: { width: 390, height: 900 } });
  await ctx.addInitScript((id) => { try { localStorage.setItem("nirog-sb-session-v1", JSON.stringify({ access_token: "tok", refresh_token: "r", expires_at: Math.floor(Date.now() / 1000) + 3600, user: { id: id, email: "u@x.in" } })); } catch (e) {} }, role === "admin" ? "a1" : "p1");
  const pg = await ctx.newPage(); const st = { saved: null, amb: AMB.slice() };
  await pg.route(/supabase\.co/, (r) => {
    const u = new URL(r.request().url()), m = r.request().method(), p = u.pathname;
    const j = (s, o) => r.fulfill({ status: s, contentType: "application/json", headers: { "access-control-allow-origin": "*" }, body: JSON.stringify(o) });
    if (m === "OPTIONS") return r.fulfill({ status: 204, headers: { "access-control-allow-origin": "*", "access-control-allow-headers": "*", "access-control-allow-methods": "*" } });
    let body = {}; try { body = JSON.parse(r.request().postData() || "{}"); } catch (e) {}
    if (m === "POST" && p === "/rest/v1/leads") { st.lead = body; return j(201, {}); }
    if (p === "/rest/v1/ambulance_services") return j(200, st.amb);
    if (p.endsWith("/rpc/admin_save_ambulance")) { st.saved = body; const row = Object.assign({ id: 9, active: true }, body.p); st.amb = st.amb.concat([row]); return j(200, row); }
    if (p.endsWith("/rpc/admin_dashboard_counts")) return j(200, { patients: 41, doctors: { listed: 12, pending: 2 }, facilities: { lab: { listed: 3, pending: 1 }, centre: { listed: 2, pending: 0 }, hospital: { listed: 4, pending: 0 }, pharmacy: { listed: 6, pending: 3 }, other: { listed: 1, pending: 0 } }, specialties: [{ spec: "Cardiologist", n: 5 }, { spec: "Dentist", n: 3 }], phones: 57, phone_users: 49 });
    if (p === "/rest/v1/facilities") return j(200, [{ id: 51, kind: "ambulance", sub: "", name: "Self Listed Ambulance", city: "Pune", address: "Depot", pin: "411001", map_url: "", hours: "24x7", beds: null, emergency: true, ambulance: false, home_service: false, services: [["Basic life support"]], wa: "9811122233", status: "approved", verified: true, ref: "FC-1" }]);
    if (p === "/rest/v1/broadcasts") return j(200, BC);
    if (p === "/rest/v1/notifications") return j(200, [{ id: 1, body: "Free eye camp: Sunday at the town hall", created_at: new Date().toISOString(), read_at: null, broadcast_id: 7 }, { id: 2, body: "Your booking is confirmed", created_at: new Date().toISOString(), read_at: null, broadcast_id: null }]);
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
  let t = await open("patient"), pg = t.pg; const txt = () => pg.evaluate(() => document.body.innerText);
  check("a new broadcast pops up once", (await pg.locator("#bcpop").count()) === 1); await pg.locator("#bcclose").click(); await pg.waitForTimeout(300);
  check("floating ambulance button is on the home screen", (await pg.locator("button.fab").count()) === 1);
  await pg.getByRole("button", { name: "Labs", exact: false }).first().click().catch(() => {});
  check("doctors, labs and hospitals links are small and at the bottom", /For doctors, labs, hospitals, pharmacies and ambulances/.test(await txt()) && !/Own a lab, diagnostic centre or hospital\?/.test(await txt()));
  const fs = await pg.evaluate(() => { const b = [...document.querySelectorAll("button")].find((x) => /List a lab, hospital, pharmacy or ambulance/.test(x.textContent)); return b ? parseFloat(getComputedStyle(b).fontSize) : 99; });
  check("registration link font is small", fs <= 13);
  await pg.locator("button.fab").click(); await pg.waitForTimeout(800);
  let tx = await txt();
  check("national numbers 112, 108 and 102 are shown", /112/.test(tx) && /108/.test(tx) && /102/.test(tx) && /Free/.test(tx));
  check("national numbers are tap-to-call links", (await pg.locator('a[href="tel:112"]').count()) === 1 && (await pg.locator('a[href="tel:108"]').count()) === 1);
  check("national numbers come before local services", tx.indexOf("112") < tx.indexOf("Anywhere Ambulance"));
  check("services for all locations are listed", /Available in all locations/i.test(tx) && /Anywhere Ambulance/.test(tx));
  check("city services show under their city when All cities", /City Care Ambulance/.test(tx) && /Delhi Rapid Ambulance/.test(tx));
  check("an approved self-registered ambulance facility is listed with a call link", /Self Listed Ambulance/.test(tx) && (await pg.locator('a[href="tel:+919811122233"]').count()) === 1);
  check("a private service links to its number", (await pg.locator('a[href="tel:9876543210"]').count()) === 1);
  await pg.selectOption("#city", "Pune"); await pg.dispatchEvent("#city", "input"); await pg.waitForTimeout(500);
  tx = await txt();
  check("choosing Pune keeps Pune and all-location services, hides Delhi", /City Care Ambulance/.test(tx) && /Anywhere Ambulance/.test(tx) && !/Delhi Rapid Ambulance/.test(tx));
  // After calling an ambulance, offer to send the patient's location.
  await pg.context().grantPermissions(["geolocation"]); await pg.context().setGeolocation({ latitude: 18.5204, longitude: 73.8567 });
  await pg.evaluate(() => { window.__opened = []; document.addEventListener("click", (e) => { const a = e.target.closest && e.target.closest("a"); if (a && /^tel:/.test(a.href)) e.preventDefault(); if (a && /^(https:\/\/wa\.me|sms:)/.test(a.href)) { window.__opened.push(a.href); e.preventDefault(); } }, true); });
  check("no location prompt before a call", !/Send your location/.test(await txt()));
  await pg.locator('a[href="tel:9876543210"]').click().catch(() => {}); await pg.waitForTimeout(900);
  tx = await txt();
  check("after tapping Call the patient is offered to send their location", /Called City Care Ambulance\?/.test(tx) && /Send on WhatsApp/.test(tx) && /Send by SMS/.test(tx));
  await pg.getByRole("button", { name: "Send on WhatsApp" }).click(); await pg.waitForTimeout(1200);
  const op = await pg.evaluate(() => window.__opened);
  check("WhatsApp opens to that number with a map link of the location", op.length === 1 && /wa\.me\/919876543210\?text=/.test(op[0]) && decodeURIComponent(op[0]).indexOf("https://maps.google.com/?q=18.520400,73.856700") > 0);
  await pg.getByRole("button", { name: "Send by SMS" }).click(); await pg.waitForTimeout(1200);
  const op2 = await pg.evaluate(() => window.__opened);
  check("SMS opens to that number with the same map link", op2.length === 2 && /^sms:9876543210\?body=/.test(op2[1]) && decodeURIComponent(op2[1]).indexOf("18.520400,73.856700") > 0);
  await pg.getByRole("button", { name: "Not needed" }).click(); await pg.waitForTimeout(300);
  check("the location offer can be dismissed", !/Send your location/.test(await txt()));
  await pg.getByRole("button", { name: "Close" }).click(); await pg.waitForTimeout(400);
  check("closing returns to the app", (await pg.locator("button.fab").count()) === 1);
  await pg.locator("button.bell").click(); await pg.waitForTimeout(600); tx = await txt();
  check("bell shows announcements with the broadcast", /Announcements/i.test(tx) && /Free eye camp/.test(tx));
  check("bell still shows booking updates", /Your booking is confirmed/.test(tx));
  check("a broadcast is not repeated as plain text", (tx.match(/Free eye camp/g) || []).length === 1);
  await pg.reload(); await pg.waitForTimeout(1500); if (await pg.locator("#bcclose").count()) await pg.locator("#bcclose").click(); await pg.locator('[data-a="tab"][data-v="labs"]').first().click(); await pg.waitForTimeout(500);
  await pg.evaluate(() => { const b = document.querySelector('[data-a="fregstart"]'); if (b) b.click(); }); await pg.waitForTimeout(400);
  await pg.selectOption("#fr-kind", "ambulance"); await pg.dispatchEvent("#fr-kind", "input"); await pg.dispatchEvent("#fr-kind", "change"); await pg.waitForTimeout(300);
  tx = await txt();
  check("ambulance registration asks for the call number and 24x7, not home delivery", /Ambulance number patients will call/.test(tx) && /Available 24x7/.test(tx) && !/Home delivery available/.test(tx));
  await pg.evaluate(() => document.getElementById("fregForm").requestSubmit()); await pg.waitForTimeout(300);
  check("ambulance registration requires the call number", /Enter the number patients should call/.test(await txt()));
  check("no page errors (patient)", t.errs.length === 0); await t.b.close();
  t = await open("admin"); pg = t.pg;
  tx = await pg.evaluate(() => document.body.innerText);
  check("admin lands on the overview with counts", /Listed on Yada+/i.test(tx) && /Patients/.test(tx) && /41/.test(tx));
  check("category counts are shown", /Labs/.test(tx) && /Diagnostic centres/.test(tx) && /Hospitals/.test(tx) && /Pharmacies/.test(tx) && /Other facilities/.test(tx) && /Doctors and clinics/.test(tx));
  check("pending reviews and installs are shown", /3 waiting for review/.test(tx) && /57/.test(tx) && /49 signed-in users/.test(tx));
  check("doctors by speciality are listed", /Doctors by speciality/i.test(tx) && /Cardiologist/.test(tx));
  await pg.getByRole("button", { name: "Ambulance", exact: true }).click(); await pg.waitForTimeout(600);
  await pg.fill("#ca-name", "Night Rider Ambulance"); await pg.fill("#ca-phone", "98765 11122"); await pg.fill("#ca-note", "Oxygen");
  await pg.getByRole("button", { name: "Add service" }).click(); await pg.waitForTimeout(900);
  const sp = t.st.saved && t.st.saved.p;
  check("admin can add a service for all locations", !!sp && sp.name === "Night Rider Ambulance" && sp.phone === "98765 11122" && sp.city === "" && sp.kind === "private");
  check("the new service appears in the admin list", /Night Rider Ambulance/.test(await pg.evaluate(() => document.body.innerText)));
  await pg.getByRole("button", { name: "Leads", exact: true }).click(); await pg.waitForTimeout(600);
  check("lead form has a location field", (await pg.locator("#cl-city").count()) === 1);
  await pg.fill("#cl-name", "Ravi Kumar"); await pg.fill("#cl-phone", "9876500011"); await pg.fill("#cl-city", "Pune"); await pg.dispatchEvent("#cl-city", "change"); await pg.waitForTimeout(300);
  await pg.getByRole("button", { name: "Add lead" }).click(); await pg.waitForTimeout(700);
  check("lead is saved with its city", !!t.st.lead && t.st.lead.city === "Pune" && t.st.lead.name === "Ravi Kumar");
  check("no page errors (admin)", t.errs.length === 0); await t.b.close();
  process.exit(ok ? 0 : 1);
})();
