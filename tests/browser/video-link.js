// Real-Chromium check of video consultation on WhatsApp against a mocked Supabase: the doctor taps a WhatsApp video call button, the patient is told to expect the call.
const { chromium } = require("playwright");
const path = require("path");
const www = path.resolve(__dirname, "../../app/src/main/assets/www/index.html");
const PNG = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==", "base64");
async function run(role, link, startedAt, dayOff) {
  const b = await chromium.launch({ executablePath: process.env.CHROME || "/opt/pw-browsers/chromium-1194/chrome-linux/chrome" });
  const ctx = await b.newContext({ viewport: { width: 390, height: 900 } });
  await ctx.addInitScript(() => { try { localStorage.setItem("nirog-sb-session-v1", JSON.stringify({ access_token: "tok", refresh_token: "r", expires_at: Math.floor(Date.now() / 1000) + 3600, user: { id: "u1", email: "u@x.in" } })); } catch (e) {} });
  const pg = await ctx.newPage(); let saved = null, uploaded = [], stored = null, linkCalls = [], startCalls = [], endCalls = [];
  const doc = { id: 7, name: "Dr. Rx Writer", spec: "General Physician", qual: "MBBS", exp_years: 8, fee_inr: 600, video_fee_inr: 0, video: false, languages: "Hindi", about: "Hello", clinic: "Mock Clinic", city: "Pune", photo_path: null, wa: null, status: "approved", verified: true, ref: "DR-M" };
  const today = new Date(); const tk = new Date(today.getTime() + 19800000 + (dayOff || 0) * 86400000).toISOString().slice(0, 10);
  const booking = { id: "b-1", ref: "BK-1", doctor_id: 7, slot_date: tk, slot_time: "00:05:00", mode: "video", patient_name: "Asha Verma", patient_age: 30, patient_sex: "Female", patient_phone: "9876500011", reason: "", doctor_fee: 600, platform_fee: 0, status: "confirmed", decision_reason: null, retimed: false };
  if (link) booking.call_link = link;
  if (startedAt) booking.call_started_at = startedAt;
  await pg.route(/supabase\.co/, (r) => {
    const u = new URL(r.request().url()), m = r.request().method(), p = u.pathname;
    const j = (s, o) => r.fulfill({ status: s, contentType: "application/json", headers: { "access-control-allow-origin": "*" }, body: JSON.stringify(o) });
    if (m === "OPTIONS") return r.fulfill({ status: 204, headers: { "access-control-allow-origin": "*", "access-control-allow-headers": "*", "access-control-allow-methods": "*" } });
    let body = {}; try { body = JSON.parse(r.request().postData() || "{}"); } catch (e) {}
    if (p.startsWith("/storage/v1/object/prescriptions/")) { uploaded.push(p.replace("/storage/v1/object/prescriptions/", "")); return j(200, { Key: "ok" }); }
    if (p.startsWith("/storage/v1/object/sign/prescriptions/")) return j(200, { signedURL: "/object/sign/x?token=t" });
    if (p === "/storage/v1/object/sign/x") return r.fulfill({ status: 200, contentType: "image/png", headers: { "access-control-allow-origin": "*" }, body: PNG });
    if (p.endsWith("/rpc/save_prescription")) { saved = body; stored = { id: 1, booking_id: "b-1", doctor_id: 7, patient_id: "u1", diagnosis: body.p.diagnosis, medicines: body.p.medicines, advice: body.p.advice, follow_up: body.p.follow_up || null, files: body.p.files, updated_at: new Date().toISOString() }; return j(200, stored); }
    if (p.endsWith("/rpc/end_call")) { endCalls.push(body.p_booking); return j(200, true); }
    if (p.endsWith("/rpc/start_call")) { startCalls.push(body.p_booking); return j(200, true); }
    if (p.endsWith("/rpc/set_call_link")) { linkCalls.push(body); if (body.p_link && !/^https:/.test(body.p_link) && !/^\d{10}$/.test(body.p_link)) return j(400, { code: "P0001", message: "invalid_link" }); booking.call_link = body.p_link; return j(200, true); }
    if (p.endsWith("/rpc/my_doctor_id")) return j(200, 7);
    if (p === "/rest/v1/profiles") return j(200, [{ id: "u1", role, full_name: role === "doctor" ? "Dr. Rx Writer" : "Asha Verma", phone: "+919876500001", email: "u@x.in" }]);
    if (p === "/rest/v1/doctors") return j(200, [doc]);
    if (p === "/rest/v1/bookings") return j(200, [booking]);
    if (p === "/rest/v1/prescriptions") return j(200, stored ? [stored] : []);
    if (m === "GET") return j(200, []);
    return j(200, {});
  });
  const errs = []; pg.on("pageerror", (e) => errs.push(String(e)));
  await pg.goto("file://" + www); await pg.waitForTimeout(1800);
  return { b, pg, errs, get: () => ({ saved, uploaded, stored, linkCalls, startCalls, endCalls }), setStored: (s) => { stored = s; } };
}
(async () => {
  let ok = true; const check = (n, c) => { console.log((c ? "PASS " : "FAIL ") + n); if (!c) ok = false; };
  let t = await run("patient"), pg = t.pg; const txt = () => pg.evaluate(() => document.body.innerText);
  await pg.locator('[data-a="tab"][data-v="appts"]').first().click({ timeout: 8000 }).catch(() => {}); await pg.waitForTimeout(600);
  let tx = await txt();
  check("patient has no Join button and no Jitsi frame", (await pg.getByRole("button", { name: "Join video call" }).count()) === 0 && (await pg.locator("iframe").count()) === 0 && !/meet\.jit\.si/.test(await pg.content()));
  check("patient is told the doctor will call on WhatsApp on their number", /video call you on WhatsApp on 9876500011/.test(tx));
  check("no page errors (patient)", t.errs.length === 0); await t.b.close();
  t = await run("patient", null, new Date().toISOString()); pg = t.pg;
  check("patient sees the doctor is calling on WhatsApp banner", (await pg.locator("#callbn").count()) === 1 && /calling you on WhatsApp/.test(await pg.locator("#callbn").innerText()));
  await pg.locator("#callbn button[aria-label=Dismiss]").click(); await pg.waitForTimeout(300);
  check("the patient can dismiss the banner", (await pg.locator("#callbn").count()) === 0);
  await t.b.close();
  t = await run("patient", null, new Date(Date.now() - 900000).toISOString()); pg = t.pg;
  check("a call started a while ago does not show the banner", (await pg.locator("#callbn").count()) === 0);
  await t.b.close();
  t = await run("doctor"); pg = t.pg;
  const wb = pg.getByRole("button", { name: "Video call on WhatsApp" }).first(); await wb.waitFor({ timeout: 8000 });
  await pg.evaluate(() => { window.__opened = []; window.open = (u) => { window.__opened.push(u); return null; }; });
  await wb.click(); await pg.waitForTimeout(600);
  const op = await pg.evaluate(() => window.__opened);
  check("tapping opens WhatsApp for the patient's number", op.length === 1 && /^https:\/\/wa\.me\/919876500011\?text=/.test(op[0]));
  check("the server is told so the patient is alerted", t.get().startCalls.indexOf("b-1") >= 0);
  check("no Jitsi frame and no outside link box", (await pg.locator("iframe").count()) === 0 && (await pg.locator('input[id^="cl-"]').count()) === 0);
  check("no page errors (doctor)", t.errs.length === 0); await t.b.close();
  t = await run("doctor", null, null, 2); pg = t.pg;
  const dbtn = pg.getByRole("button", { name: "Video call on WhatsApp" }).first(); await dbtn.waitFor({ timeout: 8000 });
  check("before the slot the doctor's button is disabled and says when it opens", (await dbtn.isDisabled()) && /video call opens at/i.test(await txt()));
  await t.b.close();
  t = await run("doctor", null, null, -2); pg = t.pg; await pg.waitForTimeout(800);
  await pg.locator('[data-a="aflt"][data-v="d:mark"]').click(); await pg.waitForTimeout(300);
  check("more than 24 hours after the slot the doctor has no call button", (await pg.getByRole("button", { name: "Video call on WhatsApp" }).count()) === 0 && /window for this visit has ended/.test(await txt()));
  await t.b.close();
  console.log(ok ? "ALL PASSED" : "SOME FAILED"); process.exit(ok ? 0 : 1);
})();
