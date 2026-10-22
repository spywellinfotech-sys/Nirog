// Real-Chromium check of the admin Promote tab (contact list for promotion) against a mocked Supabase.
const { chromium } = require("playwright");
const path = require("path");
const www = path.resolve(__dirname, "../../app/src/main/assets/www/index.html");
const FAC = { id: 61, kind: "lab", sub: "Pathology", name: "Request Lab", city: "Pune", address: "1 Lab Road", pin: "411001", map_url: "", hours: "7 AM to 9 PM", beds: null, emergency: false, ambulance: false, home_service: false, services: [["CBC blood test", 300], ["Thyroid profile", 450]], wa: null, status: "approved", verified: true, ref: "FC-61" };
async function open(role) {
  const b = await chromium.launch({ executablePath: process.env.CHROME || "/opt/pw-browsers/chromium-1194/chrome-linux/chrome" });
  const ctx = await b.newContext({ viewport: { width: 390, height: 900 } });
  await ctx.addInitScript((id) => { try { localStorage.setItem("nirog-sb-session-v1", JSON.stringify({ access_token: "tok", refresh_token: "r", expires_at: Math.floor(Date.now() / 1000) + 3600, user: { id: id, email: "u@x.in" } })); } catch (e) {} }, role === "admin" ? "a1" : role === "facility" ? "f1" : "p1");
  const pg = await ctx.newPage(); const st = { created: null, decided: null, cancelled: null, reqs: [], pros: [] };
  await pg.route(/supabase\.co/, (r) => {
    const u = new URL(r.request().url()), m = r.request().method(), p = u.pathname;
    const j = (s, o) => r.fulfill({ status: s, contentType: "application/json", headers: { "access-control-allow-origin": "*" }, body: JSON.stringify(o) });
    if (m === "OPTIONS") return r.fulfill({ status: 204, headers: { "access-control-allow-origin": "*", "access-control-allow-headers": "*", "access-control-allow-methods": "*" } });
    let body = {}; try { body = JSON.parse(r.request().postData() || "{}"); } catch (e) {}
    if (p.endsWith("/rpc/create_facility_request")) { st.created = body; st.reqs = [{ id: 5, ref: "FR-1", facility_id: 61, patient_name: body.p_name, patient_phone: body.p_phone, item: body.p_item, preferred_date: body.p_date, note: body.p_note, status: "pending", reason: "", facilities: { name: "Request Lab", kind: "lab" } }]; return j(200, "FR-1"); }
    if (p.endsWith("/rpc/decide_facility_request")) { st.decided = body; st.reqs[0].status = body.p_status; return j(200, null); }
    if (p.endsWith("/rpc/mark_facility_attendance")) { st.marked = body; const x = st.reqs.find((q) => q.id === body.p_id); if (x) x.attendance = body.p_attended ? "attended" : "no_show"; return j(200, null); }
    if (p.endsWith("/rpc/cancel_facility_request")) { st.cancelled = body; st.reqs[0].status = "cancelled"; return j(200, null); }
    if (p.endsWith("/rpc/admin_import_prospects")) { st.imp = body.p_rows; body.p_rows.filter((r) => r.phone || r.email).forEach((r, i) => st.pros.push({ id: 100 + i, kind: r.kind, name: r.name, phone: r.phone.replace(/\D/g, "").slice(-10) || null, email: r.email || null, city: r.city, spec: r.spec, status: "new", last_messaged_at: null, msg_count: 0, note: "" })); return j(200, { added: body.p_rows.length, duplicates: 0, invalid: 0 }); }
    if (p.endsWith("/rpc/admin_prospect_messaged")) { st.msgd = body.p_id; return j(200, null); }
    if (p.endsWith("/rpc/admin_set_prospect")) { st.setp = body; const x = st.pros.find((q) => q.id === body.p_id); if (x) x.status = body.p_status; return j(200, null); }
    if (p === "/rest/v1/prospects") return j(200, st.pros);
    if (p.endsWith("/rpc/my_facility_id")) return j(200, 61);
    if (p.endsWith("/rpc/admin_request_stats")) return j(200, { "61": { total: 4, pending: 1, confirmed: 2, rejected: 1, last30: 4 } });
    if (p === "/rest/v1/platform_settings") return j(200, [{ id: 1, fee_on: true, fee_type: "flat", fee_value: 49, support_email: "", support_whatsapp: "", promo_until: null, min_build: 0, update_url: "", test_fee_on: true, test_fee_pct: 10 }]);
    if (p === "/rest/v1/facility_requests") return j(200, st.reqs);
    if (p === "/rest/v1/facilities") return j(200, [FAC]);
    if (p === "/rest/v1/profiles") return j(200, [{ id: "x", role: role, full_name: "Asha", phone: "+919876500001", email: "u@x.in" }]);
    if (m === "GET") return j(200, []);
    return j(200, {});
  });
  const errs = []; pg.on("pageerror", (e) => errs.push(String(e)));
  await pg.goto("file://" + www); await pg.waitForTimeout(1800);
  return { b, pg, st, errs };
}
(async () => {
  let ok = true; const check = (n, c) => { console.log((c ? "PASS " : "FAIL ") + n); if (!c) ok = false; };
  const t = await open("admin"), pg = t.pg; const txt = () => pg.evaluate(() => document.body.innerText);
  await pg.getByRole("button", { name: "Promote", exact: true }).click({ timeout: 8000 }); await pg.waitForTimeout(600);
  check("the Promote tab has a message box and an add-contacts box", (await pg.locator("#pm-tmpl").count()) === 1 && (await pg.locator("#pm-imp").count()) === 1 && /contact list \(0\)/i.test(await txt()));
  await pg.fill("#pm-imp", "Type, Name, Mobile, Email, City, Speciality\nDoctor, Dr Asha Rao, +91 98765-43210, asha@mail.com, Pune, Dentist\nLab, City Path Lab, 9811122233, , Delhi\nPharmacy, Shree Medical, , shree@mail.com, Jaipur\nHospital, No contact");
  await pg.getByRole("button", { name: "Add to list" }).click(); await pg.waitForTimeout(900);
  check("pasted lines are sent (header skipped, a line without a name only is dropped)", t.st.imp && t.st.imp.length === 4 && t.st.imp[0].kind === "doctor" && t.st.imp[1].kind === "lab" && t.st.imp[2].kind === "pharmacy");
  let tx = await txt();
  check("contacts show with WhatsApp, Call and Email choices", /Dr Asha Rao/.test(tx) && /City Path Lab/.test(tx) && (await pg.getByRole("button", { name: "WhatsApp" }).count()) === 2 && (await pg.getByRole("button", { name: "Call", exact: true }).count()) === 2 && (await pg.getByRole("button", { name: "Email" }).count()) === 2);
  await pg.evaluate(() => { window.__opened = []; window.open = (u) => { window.__opened.push(u); return null; }; });
  await pg.locator('[data-a="pmwa"]').first().click(); await pg.waitForTimeout(700);
  const op = await pg.evaluate(() => window.__opened);
  check("WhatsApp opens a chat with the filled message and the contact is marked", op.length === 1 && /^https:\/\/wa\.me\/91\d{10}\?text=/.test(op[0]) && !/%7Bname%7D/.test(op[0]) && /Namaste/.test(decodeURIComponent(op[0])) && t.st.msgd >= 100);
  check("a contacted person leaves today's list", /2 to contact today/.test(await txt()) && /To contact today/.test(await txt()));
  await pg.locator('button[data-a="pmstat"][data-v="all"]').click(); await pg.waitForTimeout(300);
  await pg.locator('[data-a="pmst"]', { hasText: "Interested" }).first().click(); await pg.waitForTimeout(600);
  check("status can be changed", t.st.setp && t.st.setp.p_status === "interested");
  check("no page errors", t.errs.length === 0); await t.b.close();
  console.log(ok ? "ALL PASSED" : "SOME FAILED"); process.exit(ok ? 0 : 1);
})();
