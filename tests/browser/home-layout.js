// Real-Chromium check of the patient home (cards, speciality grid, floating nav) and account menu, against a mocked Supabase.
const { chromium } = require("playwright");
const path = require("path");
const www = path.resolve(__dirname, "../../app/src/main/assets/www/index.html");
function day(off) { return new Date(Date.now() + 19800000 + off * 86400000).toISOString().slice(0, 10); }

const SHOT = process.env.SHOT || "";
async function run() {
  const b = await chromium.launch({ executablePath: process.env.CHROME || "/opt/pw-browsers/chromium-1194/chrome-linux/chrome" });
  const ctx = await b.newContext({ viewport: { width: 390, height: 844 } });
  await ctx.addInitScript(() => { try { localStorage.setItem("nirog-sb-session-v1", JSON.stringify({ access_token: "tok", refresh_token: "r", expires_at: Math.floor(Date.now() / 1000) + 3600, user: { id: "u1", email: "u@x.in" } })); } catch (e) {} });
  const pg = await ctx.newPage();
  const mkd = (id, name, spec, video) => ({ id, name, spec, qual: "MBBS", exp_years: 8, fee_inr: 500, video_fee_inr: video ? 300 : 0, video, languages: "Hindi", about: "Hello", clinic: "Clinic " + id, city: "Pune", address: "Road", pin: "411001", status: "approved", rating: 4.5, reviews_count: 3, user_id: "d" + id, verified: false });
  const docs = [mkd(1, "Dr. Clinic Only", "General Physician", false), mkd(2, "Dr. Video Ok", "Dermatologist", true), mkd(3, "Dr. Teeth", "Dentist", false)];
  const dk = (o) => new Date(Date.now() + 19800000 + o * 86400000).toISOString().slice(0, 10);
  const bk = (id, doc, off, st, att) => ({ id, ref: "BK-" + id, doctor_id: doc, slot_date: dk(off), slot_time: "10:00:00", mode: "clinic", patient_name: "Asha Verma", patient_age: 30, patient_sex: "Female", patient_phone: "9876500011", reason: "Fever", doctor_fee: 500, platform_fee: 50, status: st, attendance: att || null, patient_id: "u1" });
  const bookings = [bk("p1", 2, -5, "confirmed", "attended"), bk("p2", 3, 4, "confirmed", null), bk("p3", 1, 6, "pending", null)];
  await pg.route(/supabase\.co/, (r) => {
    const u = new URL(r.request().url()), m = r.request().method(), p = u.pathname;
    const j = (s, o) => r.fulfill({ status: s, contentType: "application/json", headers: { "access-control-allow-origin": "*" }, body: JSON.stringify(o) });
    if (m === "OPTIONS") return r.fulfill({ status: 204, headers: { "access-control-allow-origin": "*", "access-control-allow-headers": "*", "access-control-allow-methods": "*" } });
    if (p === "/rest/v1/profiles") return j(200, [{ id: "u1", role: "patient", full_name: "Asha Verma", phone: "+919876500001", email: "u@x.in" }]);
    if (p === "/rest/v1/doctors") return j(200, docs);
    if (p === "/rest/v1/bookings") return j(200, bookings);
    if (m === "GET") return j(200, []);
    return j(200, {});
  });
  const errs = []; pg.on("pageerror", (e) => errs.push(String(e) + (e.stack||"").split("\n").slice(1,4).join("|")));
  await pg.goto("file://" + www); await pg.waitForTimeout(1800);
  return { b, pg, errs };
}
(async () => {
  let ok = true; const check = (n, c) => { console.log((c ? "PASS " : "FAIL ") + n); if (!c) ok = false; };
  const t = await run(), pg = t.pg; const txt = () => pg.evaluate(() => document.body.innerText);
  await pg.locator(".hcard").first().waitFor({ timeout: 8000 }).catch(async () => console.log((await txt()).slice(0, 500)));
  check("two visit cards (In-clinic, Video)", (await pg.locator(".hcard").count()) === 2);
  check("speciality grid shows icons", (await pg.locator(".sgrid .sc").count()) >= 3);
  check("floating nav has 4 buttons", (await pg.locator("nav.nav button").count()) === 4);
  check("all 3 doctors listed", /3 doctors/.test(await txt()));
  if (SHOT) await pg.screenshot({ path: SHOT + "-home.png" });
  check("no card is preselected", (await pg.locator('.hcard[aria-pressed="true"]').count()) === 0);
  await pg.locator('.hcard[data-v="video"]').click(); await pg.waitForTimeout(500);
  check("Video consult shows only video doctors", /1 doctor /.test(await txt()) && /for video consult/.test(await txt()) && /Dr\. Video Ok/.test(await txt()) && !/Dr\. Clinic Only/.test(await txt()));
  check("the video card shows as selected", (await pg.locator('.hcard[data-v="video"][aria-pressed="true"]').count()) === 1);
  await pg.locator('#docs [data-a="open"]').first().click(); await pg.waitForTimeout(500);

  check("opening a doctor from Video consult starts on Video", (await pg.locator('.seg button[data-v="video"][aria-pressed="true"]').count()) === 1);
  await pg.locator('button.back').click(); await pg.waitForTimeout(400);
  await pg.locator('.hcard[data-v="video"]').click(); await pg.waitForTimeout(300);
  check("tapping the card again clears the filter", /3 doctors/.test(await txt()));
  await pg.locator('.hcard[data-v="clinic"]').click(); await pg.waitForTimeout(300);
  check("In-clinic shows clinic doctors", /for in-clinic visit/.test(await txt()) && /Dr\. Clinic Only/.test(await txt()));
  await pg.locator('#docs [data-a="open"]').first().click(); await pg.waitForTimeout(500);
  check("opening a doctor from In-clinic starts on In-clinic", (await pg.locator('.seg button[data-v="clinic"][aria-pressed="true"]').count()) === 1);
  await pg.locator('button.back').click(); await pg.waitForTimeout(400);
  await pg.locator('.hcard[data-v="clinic"]').click(); await pg.waitForTimeout(300);
  await pg.locator('.sgrid button', { hasText: "Dentist" }).click(); await pg.waitForTimeout(300);
  check("tapping a speciality filters the list", /1 doctor /.test(await txt()) && /Dr\. Teeth/.test(await txt()));
  await pg.locator('.sech button[data-v="All"]').click(); await pg.waitForTimeout(300);
  check("common problems are shown", (await pg.locator('[data-a="prob"]').count()) >= 3);
  await pg.locator('[data-a="prob"]', { hasText: "Skin and acne" }).click(); await pg.waitForTimeout(500);
  check("a common problem lists the matching doctors", /1 doctor /.test(await txt()) && /for skin and acne/.test(await txt()) && /Dr\. Video Ok/.test(await txt()));
  await pg.locator('[data-a="prob"]', { hasText: "Skin and acne" }).click(); await pg.waitForTimeout(300);
  check("tapping the problem again clears it", /3 doctors/.test(await txt()));
  await pg.locator('.sgrid button', { hasText: "Dentist" }).click(); await pg.waitForTimeout(300);
  await pg.locator('.sech button[data-v="All"]').click(); await pg.waitForTimeout(300);
  check("Clear brings every doctor back", /3 doctors/.test(await txt()));
  await pg.locator('nav.nav button[data-v="appts"]').click(); await pg.waitForTimeout(500);
  await pg.locator('nav.nav button[data-a="profile"]').click(); await pg.waitForTimeout(500);
  const tx = await txt();
  check("Account opens the profile from another tab", /My profile/.test(tx) && /My history/.test(tx));
  check("account menu has Appointments, Tests and Help", /Appointments/.test(tx) && /Tests and facility requests/.test(tx) && /Help and support/.test(tx));
  if (SHOT) await pg.screenshot({ path: SHOT + "-account.png" });
  for (const [v, re, label] of [["docs", /Dr\. Teeth|Dr\. Video Ok|Dr\. Clinic Only/, "My doctors"], ["rec", /Medical records[\s\S]*Dr\. Video Ok/, "Medical records"], ["pay", /Total fees[\s\S]*₹1,650/, "Payments"]]) {
    await pg.locator('.menu button[data-v="' + v + '"]').click(); await pg.waitForTimeout(500);
    const tt = await txt(); check(label + " page shows my data", re.test(tt));
    if (SHOT && v === "pay") await pg.screenshot({ path: SHOT + "-pay.png" });
    await pg.locator('button[data-a="subback"]').click(); await pg.waitForTimeout(300);
  }
  await pg.locator('.menu button[data-a="pharm"]').click(); await pg.waitForTimeout(500);
  check("Medicine orders opens facilities on Pharmacies", (await pg.locator('nav.nav button[data-v="labs"][aria-current="page"]').count()) === 1);
  await pg.locator('nav.nav button[data-a="profile"]').click(); await pg.waitForTimeout(400);
  await pg.locator('.menu button[data-v="appts"]').click(); await pg.waitForTimeout(500);
  check("menu item opens the appointments tab", (await pg.locator('nav.nav button[data-v="appts"][aria-current="page"]').count()) === 1);
  await pg.locator('nav.nav button[data-v="find"]').click(); await pg.waitForTimeout(400);
  check("next appointment card shows the nearest upcoming visit", /Your next appointment/.test(await txt()) && /Dr\. Teeth/.test(await txt()));
  await pg.locator('[data-a="sort"][data-v="fee"]').click(); await pg.waitForTimeout(300);
  check("sort chip is selected", (await pg.locator('[data-a="sort"][data-v="fee"][aria-pressed="true"]').count()) === 1);
  await pg.locator('.heart').nth(1).click(); await pg.waitForTimeout(300);
  check("saving a doctor fills the heart", (await pg.locator('.heart[aria-pressed="true"]').count()) === 1);
  await pg.locator('[data-a="onlyfav"]').click(); await pg.waitForTimeout(300);
  check("Saved filter lists only saved doctors", /1 doctor /.test(await txt()));
  await pg.reload(); await pg.waitForTimeout(1800);
  check("saved doctors persist after reload", (await pg.evaluate(() => localStorage.getItem("yada-favs-v1"))).length > 2);
  check("no page errors", t.errs.length === 0); if (t.errs.length) console.log(t.errs);
  await t.b.close(); console.log(ok ? "ALL PASSED" : "SOME FAILED"); process.exit(ok ? 0 : 1);
})();
