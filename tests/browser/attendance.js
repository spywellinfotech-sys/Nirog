// Real-Chromium check of the appointment lists (Upcoming / To mark / Attended / Not attended / Cancelled) and the WhatsApp video fallback, against a mocked Supabase.
const { chromium } = require("playwright");
const path = require("path");
const www = path.resolve(__dirname, "../../app/src/main/assets/www/index.html");
function day(off) { return new Date(Date.now() + 19800000 + off * 86400000).toISOString().slice(0, 10); }
async function run(role) {
  const b = await chromium.launch({ executablePath: process.env.CHROME || "/opt/pw-browsers/chromium-1194/chrome-linux/chrome" });
  const ctx = await b.newContext({ viewport: { width: 390, height: 900 } });
  await ctx.addInitScript(() => { try { localStorage.setItem("nirog-sb-session-v1", JSON.stringify({ access_token: "tok", refresh_token: "r", expires_at: Math.floor(Date.now() / 1000) + 3600, user: { id: "u1", email: "u@x.in" } })); } catch (e) {} });
  const pg = await ctx.newPage(); const marks = [];
  const doc = { id: 7, name: "Dr. Rx Writer", spec: "General Physician", qual: "MBBS", exp_years: 8, fee_inr: 600, video_fee_inr: 0, video: false, languages: "Hindi", about: "Hello", clinic: "Mock Clinic", city: "Pune", photo_path: null, wa: null, status: "approved", verified: true, ref: "DR-M" };
  const mk = (id, off, time, status, att, mode, name) => ({ id, ref: "BK-" + id, doctor_id: 7, slot_date: day(off), slot_time: time, mode: mode || "clinic", patient_name: name, patient_age: 30, patient_sex: "Female", patient_phone: "9876500011", reason: "", doctor_fee: 600, platform_fee: 0, status, attendance: att, decision_reason: null, retimed: false });
  const rows = [mk("b-up", 3, "10:00:00", "confirmed", null, "clinic", "Future Fiona"), mk("b-pend", 4, "11:00:00", "pending", null, "clinic", "Pending Pia"),
    mk("b-mark", -2, "10:00:00", "confirmed", null, "clinic", "Unmarked Uma"), mk("b-att", -3, "10:00:00", "confirmed", "attended", "clinic", "Came Chitra"),
    mk("b-no", -4, "10:00:00", "confirmed", "no_show", "clinic", "Missed Meera"), mk("b-cx", -5, "10:00:00", "cancelled", null, "clinic", "Cancelled Cara"),
    mk("b-vid", -0, "00:05:00", "confirmed", null, "video", "Video Vani")];
  await pg.route(/supabase\.co/, (r) => {
    const u = new URL(r.request().url()), m = r.request().method(), p = u.pathname;
    const j = (s, o) => r.fulfill({ status: s, contentType: "application/json", headers: { "access-control-allow-origin": "*" }, body: JSON.stringify(o) });
    if (m === "OPTIONS") return r.fulfill({ status: 204, headers: { "access-control-allow-origin": "*", "access-control-allow-headers": "*", "access-control-allow-methods": "*" } });
    let body = {}; try { body = JSON.parse(r.request().postData() || "{}"); } catch (e) {}
    if (p.endsWith("/rpc/mark_attendance")) { marks.push(body); const x = rows.find((q) => q.id === body.p_booking); if (x) x.attendance = body.p_attended ? "attended" : "no_show"; return j(200, null); }
    if (p.endsWith("/rpc/my_doctor_id")) return j(200, 7);
    if (p === "/rest/v1/profiles") return j(200, [{ id: "u1", role, full_name: role === "doctor" ? "Dr. Rx Writer" : "Asha Verma", phone: "+919876500001", email: "u@x.in" }]);
    if (p === "/rest/v1/doctors") return j(200, [doc]);
    if (p === "/rest/v1/bookings") return j(200, rows);
    if (m === "GET") return j(200, []);
    return j(200, {});
  });
  const errs = []; pg.on("pageerror", (e) => errs.push(String(e)));
  await pg.goto("file://" + www); await pg.waitForTimeout(1800);
  return { b, pg, errs, marks };
}
(async () => {
  let ok = true; const check = (n, c) => { console.log((c ? "PASS " : "FAIL ") + n); if (!c) ok = false; };
  let t = await run("doctor"), pg = t.pg; const txt = () => pg.evaluate(() => document.body.innerText);
  const K = { "Upcoming": "up", "To mark": "mark", "Past": "mark", "Attended": "att", "Not attended": "no", "Cancelled": "cx" };
  const chip = (n) => pg.locator('button.chip[data-a="aflt"][data-v$=":' + K[n] + '"]');
  await chip("Upcoming").waitFor({ timeout: 8000 }).catch(async () => { console.log((await txt()).slice(0, 600)); });
  let tx = await txt();
  check("doctor sees list tabs with counts", /Upcoming \(3\)/.test(tx) && /To mark \(1\)/.test(tx) && /Attended \(1\)/.test(tx) && /Not attended \(1\)/.test(tx) && /Cancelled \(1\)/.test(tx));
  check("Upcoming holds the future and pending bookings only", /Future Fiona/.test(tx) && /Pending Pia/.test(tx) && !/Unmarked Uma/.test(tx) && !/Came Chitra/.test(tx));
  await chip("To mark").click(); await pg.waitForTimeout(300); tx = await txt();
  check("To mark shows the past unmarked visit with Attended and Not attended buttons", /Unmarked Uma/.test(tx) && (await pg.getByRole("button", { name: "Attended", exact: true }).count()) >= 1 && (await pg.getByRole("button", { name: "Not attended", exact: true }).count()) >= 1);
  await pg.locator('[data-a="attmark"][data-v="b-mark|0"]').click(); await pg.waitForTimeout(900);
  check("marking not attended calls the server", t.marks.length === 1 && t.marks[0].p_booking === "b-mark" && t.marks[0].p_attended === false);
  await chip("Not attended").click(); await pg.waitForTimeout(300); tx = await txt();
  check("the visit moves to Not attended", /Unmarked Uma/.test(tx) && /Missed Meera/.test(tx));
  await chip("Attended").click(); await pg.waitForTimeout(300);
  check("Attended lists the attended visit", /Came Chitra/.test(await txt()));
  await chip("Cancelled").click(); await pg.waitForTimeout(300);
  check("Cancelled lists cancelled bookings", /Cancelled Cara/.test(await txt()));
  await chip("Upcoming").click(); await pg.waitForTimeout(300);
  check("a video visit in its call window offers a WhatsApp video call fallback", (await pg.getByRole("button", { name: "Video call on WhatsApp" }).count()) === 1);
  check("no page errors (doctor)", t.errs.length === 0); await t.b.close();
  t = await run("patient"); pg = t.pg;
  await pg.locator('[data-a="tab"][data-v="appts"]').first().click({ timeout: 8000 }).catch(() => {}); await pg.waitForTimeout(700); tx = await txt();
  check("patient sees the same tabs with Past instead of To mark", /Upcoming \(3\)/.test(tx) && /Past \(1\)/.test(tx) && /Attended \(1\)/.test(tx) && /Not attended \(1\)/.test(tx));
  await pg.locator('button.chip[data-a="aflt"][data-v="p:att"]').click(); await pg.waitForTimeout(300);
  check("patient Attended tab lists the attended visit and shows the pill", /Attended/.test(await pg.locator(".appt .pill").first().innerText()));
  await pg.locator('button.chip[data-a="aflt"][data-v="p:no"]').click(); await pg.waitForTimeout(300);
  check("patient Not attended tab has no cancel button", (await pg.getByRole("button", { name: "Cancel", exact: true }).count()) === 0);
  check("no page errors (patient)", t.errs.length === 0); await t.b.close();
  console.log(ok ? "ALL PASSED" : "SOME FAILED"); process.exit(ok ? 0 : 1);
})();
