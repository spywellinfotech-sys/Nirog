// Real-Chromium check against a mocked Supabase: Refer and earn screen (code, balance, rates, apply code, UPI withdrawal),
// the ?ref= link being applied once after sign-in, and the admin Payouts tab (mark paid, reject needs a reason, reward rates).
const { chromium } = require("playwright");
const path = require("path");
const www = path.resolve(__dirname, "../../app/src/main/assets/www/index.html");
async function open(role, url) {
  const b = await chromium.launch({ executablePath: process.env.CHROME || "/opt/pw-browsers/chromium-1194/chrome-linux/chrome" });
  const ctx = await b.newContext({ viewport: { width: 390, height: 900 } });
  await ctx.addInitScript((id) => { try { localStorage.setItem("nirog-sb-session-v1", JSON.stringify({ access_token: "tok", refresh_token: "r", expires_at: Math.floor(Date.now() / 1000) + 3600, user: { id: id, email: "u@x.in" } })); } catch (e) {} }, role === "admin" ? "a1" : "p1");
  const pg = await ctx.newPage();
  const st = { applied: [], wd: null, decided: null, settings: null, balance: 25, appliedFlag: false, pend: [{ id: 5, amount: 40, upi: "ravi@okbank", status: "pending", name: "Ravi", phone: "+919800000001", role: "doctor", at: new Date().toISOString() }] };
  await pg.route(/supabase\.co/, (r) => {
    const u = new URL(r.request().url()), m = r.request().method(), p = u.pathname;
    const j = (s, o) => r.fulfill({ status: s, contentType: "application/json", headers: { "access-control-allow-origin": "*" }, body: JSON.stringify(o) });
    if (m === "OPTIONS") return r.fulfill({ status: 204, headers: { "access-control-allow-origin": "*", "access-control-allow-headers": "*", "access-control-allow-methods": "*" } });
    let body = {}; try { body = JSON.parse(r.request().postData() || "{}"); } catch (e) {}
    if (p.endsWith("/rpc/my_referral")) return j(200, { code: "YDK4M7QP", balance: st.balance, rates: { doctor: 10, facility: 10, patient: 1 }, min_withdraw: 50, applied: st.appliedFlag, counts: { patient: 3, doctor: 1, facility: 0 }, history: [{ amount: 10, kind: "referral", note: "Doctor joined through your invite", at: new Date().toISOString() }], withdrawals: st.wd ? [st.wd] : [] });
    if (p.endsWith("/rpc/apply_referral")) { st.applied.push(body.p_code); if (body.p_code === "BADCODE") return j(400, { code: "P0001", message: "invalid_code" }); st.appliedFlag = true; return j(200, true); }
    if (p.endsWith("/rpc/request_withdrawal")) { st.wd = { id: 1, amount: body.p_amount, upi: body.p_upi, status: "pending", at: new Date().toISOString() }; st.balance -= body.p_amount; return j(200, 1); }
    if (p.endsWith("/rpc/admin_withdrawals")) return j(200, st.decided ? [] : st.pend);
    if (p.endsWith("/rpc/admin_decide_withdrawal")) { st.decided = body; return j(200, true); }
    if (p.endsWith("/rpc/admin_referral_settings")) { if (body.p) st.settings = Object.assign(st.settings || {}, body.p); return j(200, { enabled: st.settings && st.settings.enabled === false ? false : true, doctor_inr: 10, facility_inr: 10, patient_inr: 1, min_withdraw: 50, patient_daily_cap: 50 }); }
    if (p.endsWith("/rpc/admin_dashboard_counts")) return j(200, { patients: 1, doctors: { listed: 0, pending: 0 }, facilities: {} });
    if (p === "/rest/v1/profiles") return j(200, [{ id: role === "admin" ? "a1" : "p1", role: role, full_name: "X", phone: null, email: "u@x.in" }]);
    if (m === "GET") return j(200, []);
    return j(200, {});
  });
  const errs = []; pg.on("pageerror", (e) => errs.push(String(e)));
  await pg.goto("file://" + www + (url || "")); await pg.waitForTimeout(1800);
  return { b, pg, st, errs };
}
(async () => {
  let ok = true; const check = (n, c) => { console.log((c ? "PASS " : "FAIL ") + n); if (!c) ok = false; };
  let t = await open("patient", "?ref=ydab12cd"), pg = t.pg; const txt = () => pg.evaluate(() => document.body.innerText);
  check("the ?ref= code from the invite link is applied once after sign-in", t.st.applied.length === 1 && t.st.applied[0] === "YDAB12CD");
  t.st.appliedFlag = false; // the card for typing a code is tested below
  await pg.locator('[data-a="profile"]').first().click(); await pg.waitForTimeout(500);
  check("profile has a Refer and earn card", /Refer and earn/.test(await txt()));
  await pg.locator('[data-a="ref"]').first().click(); await pg.waitForTimeout(800);
  let tx = await txt();
  check("wallet balance and code are shown", /₹25/.test(tx) && /YDK4M7QP/.test(tx));
  check("rewards use the configured rates", /₹10 when a doctor/.test(tx) && /₹1 for every new patient/.test(tx));
  check("counts are shown", /1 doctors, 0 facilities, 3 patients/.test(tx));
  const href = await pg.locator('a:has-text("Share on WhatsApp")').getAttribute("href");
  check("WhatsApp share carries the code and the invite link", /YDK4M7QP/.test(decodeURIComponent(href)) && /\?ref=YDK4M7QP/.test(decodeURIComponent(href)));
  await pg.fill("#rf-code", "BADCODE"); await pg.locator('[data-a="refapply"]').click(); await pg.waitForTimeout(600);
  check("a wrong code shows a clear error", /That code was not found/.test(await txt()));
  await pg.fill("#rf-code", "friend22"); await pg.locator('[data-a="refapply"]').click(); await pg.waitForTimeout(800);
  tx = await txt();
  check("a good code is accepted and the card goes away", /Code added/.test(tx) && (await pg.locator("#rf-code").count()) === 0);
  await pg.fill("#rf-upi", "bad upi"); await pg.fill("#rf-amt", "20"); await pg.locator('[data-a="refwd"]').click(); await pg.waitForTimeout(300);
  check("a bad UPI id is refused before sending", /valid UPI id/.test(await txt()) && !t.st.wd);
  await pg.fill("#rf-upi", "Asha@okbank"); await pg.locator('[data-a="refwd"]').click(); await pg.waitForTimeout(900);
  tx = await txt();
  check("withdrawal is requested with the amount and UPI id", t.st.wd && t.st.wd.amount === 20 && t.st.wd.upi === "Asha@okbank");
  check("a waiting withdrawal replaces the form", /Withdrawal requested/.test(tx) && (await pg.locator("#rf-upi").count()) === 0 && /Waiting/.test(tx));
  check("no page errors (patient)", t.errs.length === 0); await t.b.close();
  t = await open("admin"); pg = t.pg;
  await pg.getByRole("button", { name: "Payouts", exact: true }).click(); await pg.waitForTimeout(800); tx = await txt();
  check("admin sees the waiting withdrawal with who and where to pay", /₹40 to ravi@okbank/.test(tx) && /Ravi/.test(tx) && /9800000001/.test(tx));
  await pg.locator('[data-a="wdrej"]').click(); await pg.waitForTimeout(300);
  check("reject needs a reason", /Write a short reason/.test(await txt()) && !t.st.decided);
  await pg.fill("#wd-utr-5", "UTR998877"); await pg.locator('[data-a="wdpaid"]').click(); await pg.waitForTimeout(900);
  check("mark paid sends the UTR", t.st.decided && t.st.decided.p_decision === "paid" && t.st.decided.p_utr === "UTR998877");
  check("the paid request leaves the list", /Marked as paid/.test(await txt()) && /No withdrawals waiting/.test(await txt()));
  await pg.locator('[data-a="rson"]').click(); await pg.waitForTimeout(700);
  check("admin can pause the programme", t.st.settings && t.st.settings.enabled === false && /paused/i.test(await txt()));
  await pg.locator('[data-a="rson"]').click(); await pg.waitForTimeout(700);
  check("admin can switch it back on", t.st.settings.enabled === true && /Referral programme is on/.test(await txt()));
  await pg.fill("#rs-doc", "15"); await pg.fill("#rs-pat", "2"); await pg.locator('[data-a="rssave"]').click(); await pg.waitForTimeout(700);
  check("reward rates are saved", t.st.settings && t.st.settings.doctor_inr === 15 && t.st.settings.patient_inr === 2 && /Saved/.test(await txt()));
  await pg.fill("#rs-doc", "x"); await pg.locator('[data-a="rssave"]').click(); await pg.waitForTimeout(300);
  check("rates must be whole rupees", /whole rupee amounts/.test(await txt()));
  check("no page errors (admin)", t.errs.length === 0); await t.b.close();
  console.log(ok ? "ALL PASSED" : "SOME FAILED"); process.exit(ok ? 0 : 1);
})();
