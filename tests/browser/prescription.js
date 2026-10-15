// Real-Chromium check of the prescription flow against a mocked Supabase: doctor writes (typed + photo), patient views.
const { chromium } = require("playwright");
const path = require("path");
const www = path.resolve(__dirname, "../../app/src/main/assets/www/index.html");
const PNG = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==", "base64");
async function run(role) {
  const b = await chromium.launch({ executablePath: process.env.CHROME || "/opt/pw-browsers/chromium-1194/chrome-linux/chrome" });
  const ctx = await b.newContext({ viewport: { width: 390, height: 900 } });
  await ctx.addInitScript(() => { try { localStorage.setItem("nirog-sb-session-v1", JSON.stringify({ access_token: "tok", refresh_token: "r", expires_at: Math.floor(Date.now() / 1000) + 3600, user: { id: "u1", email: "u@x.in" } })); } catch (e) {} });
  const pg = await ctx.newPage(); let saved = null, uploaded = [], stored = null;
  const doc = { id: 7, name: "Dr. Rx Writer", spec: "General Physician", qual: "MBBS", exp_years: 8, fee_inr: 600, video_fee_inr: 0, video: false, languages: "Hindi", about: "Hello", clinic: "Mock Clinic", city: "Pune", photo_path: null, wa: null, status: "approved", verified: true, ref: "DR-M" };
  const today = new Date(); const tk = new Date(today.getTime() + 19800000).toISOString().slice(0, 10);
  const booking = { id: "b-1", ref: "BK-1", doctor_id: 7, slot_date: tk, slot_time: "00:05:00", mode: "clinic", patient_name: "Asha Verma", patient_age: 30, patient_sex: "Female", patient_phone: "9876500011", reason: "", doctor_fee: 600, platform_fee: 0, status: "confirmed", decision_reason: null, retimed: false };
  await pg.route(/supabase\.co/, (r) => {
    const u = new URL(r.request().url()), m = r.request().method(), p = u.pathname;
    const j = (s, o) => r.fulfill({ status: s, contentType: "application/json", headers: { "access-control-allow-origin": "*" }, body: JSON.stringify(o) });
    if (m === "OPTIONS") return r.fulfill({ status: 204, headers: { "access-control-allow-origin": "*", "access-control-allow-headers": "*", "access-control-allow-methods": "*" } });
    let body = {}; try { body = JSON.parse(r.request().postData() || "{}"); } catch (e) {}
    if (p.startsWith("/storage/v1/object/prescriptions/")) { uploaded.push(p.replace("/storage/v1/object/prescriptions/", "")); return j(200, { Key: "ok" }); }
    if (p.startsWith("/storage/v1/object/sign/prescriptions/")) return j(200, { signedURL: "/object/sign/x?token=t" });
    if (p === "/storage/v1/object/sign/x") return r.fulfill({ status: 200, contentType: "image/png", headers: { "access-control-allow-origin": "*" }, body: PNG });
    if (p.endsWith("/rpc/save_prescription")) { saved = body; stored = { id: 1, booking_id: "b-1", doctor_id: 7, patient_id: "u1", diagnosis: body.p.diagnosis, medicines: body.p.medicines, advice: body.p.advice, follow_up: body.p.follow_up || null, files: body.p.files, updated_at: new Date().toISOString() }; return j(200, stored); }
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
  return { b, pg, errs, get: () => ({ saved, uploaded, stored }), setStored: (s) => { stored = s; } };
}
(async () => {
  let ok = true; const check = (n, c) => { console.log((c ? "PASS " : "FAIL ") + n); if (!c) ok = false; };
  // Doctor
  let t = await run("doctor"), pg = t.pg;
  await pg.getByRole("button", { name: "Write prescription" }).click({ timeout: 8000 });
  await pg.fill("#rx-diagnosis", "Viral fever");
  await pg.fill("#rx-m-0-name", "Paracetamol 500 mg"); await pg.fill("#rx-m-0-dose", "1 tablet"); await pg.fill("#rx-m-0-freq", "Twice a day"); await pg.fill("#rx-m-0-days", "3x");
  await pg.getByRole("button", { name: "+ Add medicine" }).click();
  await pg.fill("#rx-m-1-name", "ORS");
  await pg.fill("#rx-advice", "Rest and fluids");
  await pg.setInputFiles("#rxp-add", { name: "p.png", mimeType: "image/png", buffer: PNG }); await pg.waitForTimeout(800);
  await pg.getByRole("button", { name: "Save and share with patient" }).click(); await pg.waitForTimeout(1200);
  const g = t.get(), p = g.saved && g.saved.p;
  check("RPC body is {p:{...}}", !!p && p.booking_id === "b-1");
  check("typed fields sent", p && p.diagnosis === "Viral fever" && p.advice === "Rest and fluids" && p.medicines.length === 2 && p.medicines[0].days === "3");
  check("photo uploaded under the booking folder and listed", g.uploaded.length === 1 && /^b-1\/rx\d+-0\.jpg$/.test(g.uploaded[0]) && p.files[0] === g.uploaded[0]);
  check("button now offers Edit", await pg.getByRole("button", { name: "Edit prescription" }).count() === 1);
  // WhatsApp share, web path: a wa.me message for the patient's number with a text summary
  await pg.evaluate(() => { window.__opened = []; window.open = (u) => { window.__opened.push(u); return null; }; });
  await pg.getByRole("button", { name: "Share on WhatsApp" }).click(); await pg.waitForTimeout(1500);
  const op = await pg.evaluate(() => window.__opened);
  check("web: opens wa.me with the patient's number and a summary", op.length === 1 && op[0].startsWith("https://wa.me/919876500011?text=") && /Paracetamol/.test(decodeURIComponent(op[0])) && /Rest%20and%20fluids/.test(op[0]));
  // WhatsApp share, Android app path: the PDF goes through the native bridge with the number
  await pg.evaluate(() => { window.__native = null; window.NirogNative = { sharePdf: (b64, name, phone, text) => { window.__native = { b64: b64.slice(0, 12), len: b64.length, name, phone, text }; return true; } }; });
  await pg.getByRole("button", { name: "Share on WhatsApp" }).click(); await pg.waitForTimeout(1500);
  const nat = await pg.evaluate(() => window.__native);
  check("app: PDF passed to the native share with number and text", !!nat && nat.b64.startsWith("JVBERi0") && nat.phone === "919876500011" && /Paracetamol/.test(nat.text) && /^Yada-prescription-BK-1\.pdf$/.test(nat.name));
  check("doctor: no page errors", t.errs.length === 0);
  const stored = g.stored; await t.b.close();
  // Patient
  t = await run("patient"); t.setStored(stored); pg = t.pg;
  await pg.reload(); await pg.waitForTimeout(1800);
  await pg.locator('[data-a="tab"][data-v="appts"]').first().click().catch(async () => { await pg.getByText(/Appointments/i).first().click(); });
  await pg.getByRole("button", { name: "View prescription" }).click({ timeout: 8000 });
  const txt = await pg.evaluate(() => document.body.innerText);
  check("patient sees diagnosis, medicines and advice", /Viral fever/.test(txt) && /Paracetamol 500 mg/.test(txt) && /ORS/.test(txt) && /Rest and fluids/.test(txt));
  await pg.getByRole("button", { name: "View photo 1" }).click(); await pg.waitForTimeout(600);
  check("patient can open the photo", await pg.locator(".lb img").count() === 1);
  await pg.locator(".lb").click(); await pg.waitForTimeout(300);
  const [dl] = await Promise.all([pg.waitForEvent("download", { timeout: 15000 }), pg.getByRole("button", { name: "Download PDF" }).click()]);
  const out = process.env.PDF_OUT || "/tmp/rx-test.pdf"; await dl.saveAs(out);
  const buf = require("fs").readFileSync(out);
  check("PDF download has a name and valid header/trailer", /^Yada-prescription-BK-1\.pdf$/.test(dl.suggestedFilename()) && buf.slice(0, 5).toString() === "%PDF-" && buf.slice(-6).toString().includes("%%EOF"));
  check("patient has no write button", await pg.getByRole("button", { name: /Write prescription/ }).count() === 0);
  check("patient: no page errors", t.errs.length === 0);
  await t.b.close();
  console.log(ok ? "ALL PASSED" : "SOME FAILED"); process.exit(ok ? 0 : 1);
})();
