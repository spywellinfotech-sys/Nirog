// Real-Chromium check against a mocked Supabase: a patient requests a lab appointment, sees it under Appointments and can cancel;
// the lab owner sees the inbox and confirms; the admin sees per-facility request counts.
const { chromium } = require("playwright");
const path = require("path");
const www = path.resolve(__dirname, "../../app/src/main/assets/www/index.html");
const FAC = { id: 61, kind: "lab", sub: "Pathology", name: "Request Lab", city: "Pune", address: "1 Lab Road", pin: "411001", map_url: "", hours: "7 AM to 9 PM", beds: null, emergency: false, ambulance: false, home_service: false, services: [["CBC blood test", 300], ["Thyroid profile", 450]], wa: null, status: "approved", verified: true, ref: "FC-61" };
async function open(role) {
  const b = await chromium.launch({ executablePath: process.env.CHROME || "/opt/pw-browsers/chromium-1194/chrome-linux/chrome" });
  const ctx = await b.newContext({ viewport: { width: 390, height: 900 } });
  await ctx.addInitScript((id) => { try { localStorage.setItem("nirog-sb-session-v1", JSON.stringify({ access_token: "tok", refresh_token: "r", expires_at: Math.floor(Date.now() / 1000) + 3600, user: { id: id, email: "u@x.in" } })); } catch (e) {} }, role === "admin" ? "a1" : role === "facility" ? "f1" : "p1");
  const pg = await ctx.newPage(); const st = { created: null, decided: null, cancelled: null, reqs: [] };
  await pg.route(/supabase\.co/, (r) => {
    const u = new URL(r.request().url()), m = r.request().method(), p = u.pathname;
    const j = (s, o) => r.fulfill({ status: s, contentType: "application/json", headers: { "access-control-allow-origin": "*" }, body: JSON.stringify(o) });
    if (m === "OPTIONS") return r.fulfill({ status: 204, headers: { "access-control-allow-origin": "*", "access-control-allow-headers": "*", "access-control-allow-methods": "*" } });
    let body = {}; try { body = JSON.parse(r.request().postData() || "{}"); } catch (e) {}
    if (p.endsWith("/rpc/create_facility_request")) { st.created = body; st.reqs = [{ id: 5, ref: "FR-1", facility_id: 61, patient_name: body.p_name, patient_phone: body.p_phone, item: body.p_item, preferred_date: body.p_date, note: body.p_note, status: "pending", reason: "", facilities: { name: "Request Lab", kind: "lab" } }]; return j(200, "FR-1"); }
    if (p.endsWith("/rpc/decide_facility_request")) { st.decided = body; st.reqs[0].status = body.p_status; return j(200, null); }
    if (p.endsWith("/rpc/cancel_facility_request")) { st.cancelled = body; st.reqs[0].status = "cancelled"; return j(200, null); }
    if (p.endsWith("/rpc/my_facility_id")) return j(200, 61);
    if (p.endsWith("/rpc/admin_request_stats")) return j(200, { "61": { total: 4, pending: 1, confirmed: 2, rejected: 1, last30: 4 } });
    if (p === "/rest/v1/facility_requests") return j(200, st.reqs);
    if (p === "/rest/v1/facilities") return j(200, [FAC]);
    if (p === "/rest/v1/profiles") return j(200, [{ id: "x", role: role, full_name: "Asha", phone: null, email: "u@x.in" }]);
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
  await pg.locator('button[data-a="tab"][data-v="labs"]').click(); await pg.waitForTimeout(600);
  check("a lab card has a Request appointment button", (await pg.locator('button[data-a="frqopen"]').count()) === 1);
  await pg.locator('button[data-a="frqopen"]').click(); await pg.waitForTimeout(300);
  await pg.locator('button[data-a="frqsend"]').click(); await pg.waitForTimeout(300);
  check("an empty form is refused", /Choose or type the test/.test(await txt()) && !t.st.created);
  await pg.fill("#frq-item", "CBC blood test"); await pg.dispatchEvent("#frq-item", "input");
  const d = new Date(); d.setDate(d.getDate() + 2); const dk = d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
  await pg.fill("#frq-date", dk); await pg.dispatchEvent("#frq-date", "input");
  await pg.fill("#frq-name", "Asha"); await pg.dispatchEvent("#frq-name", "input");
  await pg.fill("#frq-phone", "12345"); await pg.dispatchEvent("#frq-phone", "input");
  await pg.locator('button[data-a="frqsend"]').click(); await pg.waitForTimeout(300);
  check("a bad mobile number is refused", /10-digit mobile/.test(await txt()) && !t.st.created);
  await pg.fill("#frq-phone", "9876500001"); await pg.dispatchEvent("#frq-phone", "input");
  await pg.locator('button[data-a="frqsend"]').click(); await pg.waitForTimeout(900);
  check("the request is sent with the right details", t.st.created && t.st.created.p_facility === 61 && t.st.created.p_item === "CBC blood test" && t.st.created.p_phone === "9876500001" && t.st.created.p_date === dk);
  check("the patient is told it was sent", /Request FR-1 sent/.test(await txt()));
  await pg.locator('button[data-a="tab"][data-v="appts"]').click(); await pg.waitForTimeout(800);
  let tx = await txt();
  check("the request shows under Appointments as waiting", /Request Lab/.test(tx) && /Waiting for reply/.test(tx) && /CBC blood test/.test(tx));
  await pg.locator('button[data-a="frqcancel"]').click(); await pg.waitForTimeout(900);
  check("the patient can cancel the request", t.st.cancelled && /Cancelled/.test(await txt()));
  check("no page errors (patient)", t.errs.length === 0); await t.b.close();

  t = await open("facility"); pg = t.pg;
  t.st.reqs = [{ id: 5, ref: "FR-1", facility_id: 61, patient_name: "Asha", patient_phone: "9876500001", item: "CBC blood test", preferred_date: dk, note: "Fasting", status: "pending", reason: "", facilities: { name: "Request Lab", kind: "lab" } }];
  await pg.reload(); await pg.waitForTimeout(1800);
  tx = await txt();
  check("the lab owner sees the request with the patient's mobile", /appointment requests/i.test(tx) && /Asha/.test(tx) && /9876500001/.test(tx) && /Fasting/.test(tx));
  check("the owner has no Request appointment button on their own card", (await pg.locator('button[data-a="frqopen"]').count()) === 0);
  await pg.locator('button[data-a="frqyes"]').click(); await pg.waitForTimeout(900);
  check("the owner can confirm", t.st.decided && t.st.decided.p_status === "confirmed" && /Confirmed/.test(await txt()));
  check("no page errors (facility)", t.errs.length === 0); await t.b.close();

  t = await open("admin"); pg = t.pg;
  await pg.getByRole("button", { name: "Facilities", exact: true }).click(); await pg.waitForTimeout(900);
  console.log((await txt()).slice(0,300));
  tx = await txt();
  check("admin sees request counts per facility", /appointment requests 4/i.test(tx) && /confirmed 2/i.test(tx) && /declined 1/i.test(tx) && /waiting 1/i.test(tx));
  check("no page errors (admin)", t.errs.length === 0); await t.b.close();
  console.log(ok ? "ALL PASSED" : "SOME FAILED"); process.exit(ok ? 0 : 1);
})();
