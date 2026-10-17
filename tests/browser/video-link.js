// Real-Chromium check of video consultation against a mocked Supabase: the doctor adds a call link, the patient gets a Join button.
const { chromium } = require("playwright");
const path = require("path");
const www = path.resolve(__dirname, "../../app/src/main/assets/www/index.html");
const PNG = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==", "base64");
async function run(role, link, startedAt) {
  const b = await chromium.launch({ executablePath: process.env.CHROME || "/opt/pw-browsers/chromium-1194/chrome-linux/chrome" });
  const ctx = await b.newContext({ viewport: { width: 390, height: 900 } });
  await ctx.addInitScript(() => { try { localStorage.setItem("nirog-sb-session-v1", JSON.stringify({ access_token: "tok", refresh_token: "r", expires_at: Math.floor(Date.now() / 1000) + 3600, user: { id: "u1", email: "u@x.in" } })); } catch (e) {} });
  const pg = await ctx.newPage(); let saved = null, uploaded = [], stored = null, linkCalls = [], startCalls = [], endCalls = [];
  const doc = { id: 7, name: "Dr. Rx Writer", spec: "General Physician", qual: "MBBS", exp_years: 8, fee_inr: 600, video_fee_inr: 0, video: false, languages: "Hindi", about: "Hello", clinic: "Mock Clinic", city: "Pune", photo_path: null, wa: null, status: "approved", verified: true, ref: "DR-M" };
  const today = new Date(); const tk = new Date(today.getTime() + 19800000).toISOString().slice(0, 10);
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
    if (p === "/rest/v1/profiles") return j(200, [{ id: "u1", role, full_name: role === "doctor" ? "Dr. Rx Writer" : "Asha Verma", phone: null, email: "u@x.in" }]);
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
  check("patient gets an in-app Join button even without a doctor link", (await pg.getByRole("button", { name: "Join video call" }).count()) === 1 && (await pg.getByRole("link", { name: /doctor.s link/ }).count()) === 0);
  await pg.getByRole("button", { name: "Join video call" }).click(); await pg.waitForTimeout(600);
  const fr = pg.locator("iframe#callfr"); const src = await fr.getAttribute("src");
  check("the call opens inside the app on a private room", /^https:\/\/meet\.jit\.si\/YadaPlus-b1#/.test(src) && /disableDeepLinking=true/.test(src) && /prejoinPageEnabled=false/.test(src));
  check("the call frame may use camera and microphone", /camera/.test(await fr.getAttribute("allow")) && /microphone/.test(await fr.getAttribute("allow")));
  check("patient name is sent to the call", /Asha%20Verma/.test(src));
  await pg.waitForTimeout(500); await pg.evaluate(() => { window.__marker = 1; });
  check("leaving the call returns to appointments", (await pg.getByRole("button", { name: "Leave call" }).count()) === 1);
  await pg.getByRole("button", { name: "Leave call" }).click(); await pg.waitForTimeout(500);
  check("the call frame is gone after leaving", (await pg.locator("iframe#callfr").count()) === 0);
  check("no page errors (patient, no link)", t.errs.length === 0); await t.b.close();
  t = await run("patient", "https://meet.google.com/abc-defg-hij"); pg = t.pg;
  await pg.locator('[data-a="tab"][data-v="appts"]').first().click({ timeout: 8000 }).catch(() => {}); await pg.waitForTimeout(600);
  const jl = pg.getByRole("link", { name: /doctor.s link/ });
  check("patient also gets the doctor's own link", (await jl.count()) === 1 && (await jl.getAttribute("href")) === "https://meet.google.com/abc-defg-hij" && (await jl.getAttribute("target")) === "_blank");
  await t.b.close();
  t = await run("patient", null, new Date().toISOString()); pg = t.pg;
  await pg.locator("#callbn button[aria-label=Dismiss]").click(); await pg.waitForTimeout(300);
  check("the patient can dismiss the banner", (await pg.locator("#callbn").count()) === 0);
  await t.b.close();
  t = await run("patient", null, new Date().toISOString()); pg = t.pg;
  check("patient sees the Your doctor is calling banner", (await pg.locator("#callbn").count()) === 1 && /Your doctor is calling/.test(await pg.locator("#callbn").innerText()));
  await pg.locator("#callbn button.btn").click(); await pg.waitForTimeout(500);
  check("tapping Join opens the call and hides the banner", (await pg.locator("iframe#callfr").count()) === 1 && (await pg.locator("#callbn").count()) === 0);
  await t.b.close();
  t = await run("patient", null, new Date(Date.now() - 900000).toISOString()); pg = t.pg;
  check("a call started a while ago does not show the banner", (await pg.locator("#callbn").count()) === 0);
  await t.b.close();
  t = await run("doctor"); pg = t.pg; tx = await txt();
  const input = pg.locator('input[id^="cl-"]'); await input.first().waitFor({ timeout: 8000 });
  check("doctor sees Start video call and an optional link box", (await input.count()) === 1 && /Use another call link/.test(await txt()) && (await pg.getByRole("button", { name: "Start video call" }).count()) === 1);
  await input.fill("javascript:alert(1)"); await pg.locator('[data-a="clsave"]').click(); await pg.waitForTimeout(600);
  check("a bad link shows a clear error", /starts with https/.test(await txt()));
  await input.fill("https://meet.google.com/abc-defg-hij"); await pg.locator('[data-a="clsave"]').click(); await pg.waitForTimeout(1200);
  await pg.getByRole("button", { name: "Start video call" }).click(); await pg.waitForTimeout(600);
  check("starting the call tells the server so the patient is alerted", t.get().startCalls.indexOf("b-1") >= 0 && (await pg.locator("iframe#callfr").count()) === 1);
  await pg.getByRole("button", { name: "Leave call" }).click(); await pg.waitForTimeout(400);
  check("when the doctor leaves, the server is told the call ended", t.get().endCalls.indexOf("b-1") >= 0);
  check("the link is sent to the server", t.get().linkCalls.some((c) => c.p_link === "https://meet.google.com/abc-defg-hij" && c.p_booking === "b-1"));
  check("after saving the button says Update link", /Update link/.test(await txt()));
  check("no page errors (doctor)", t.errs.length === 0); await t.b.close();
  
  console.log(ok ? "ALL PASSED" : "SOME FAILED"); process.exit(ok ? 0 : 1);
})();
