// Real-Chromium check of the broadcast flow against a mocked Supabase: admin composes and sends, a patient sees the popup once.
const { chromium } = require("playwright");
const path = require("path");
const www = path.resolve(__dirname, "../../app/src/main/assets/www/index.html");
const PNG = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==", "base64");
async function open(role, extra) {
  const b = await chromium.launch({ executablePath: process.env.CHROME || "/opt/pw-browsers/chromium-1194/chrome-linux/chrome" });
  const ctx = await b.newContext({ viewport: { width: 390, height: 900 } });
  await ctx.addInitScript((id) => { try { localStorage.setItem("nirog-sb-session-v1", JSON.stringify({ access_token: "tok", refresh_token: "r", expires_at: Math.floor(Date.now() / 1000) + 3600, user: { id: id, email: "u@x.in" } })); } catch (e) {} }, role === "admin" ? "a1" : "p1");
  const pg = await ctx.newPage(); const st = { uploads: [], rpc: null, list: extra.list || [] };
  await pg.route(/supabase\.co/, (r) => {
    const u = new URL(r.request().url()), m = r.request().method(), p = u.pathname;
    const j = (s, o) => r.fulfill({ status: s, contentType: "application/json", headers: { "access-control-allow-origin": "*" }, body: JSON.stringify(o) });
    if (m === "OPTIONS") return r.fulfill({ status: 204, headers: { "access-control-allow-origin": "*", "access-control-allow-headers": "*", "access-control-allow-methods": "*" } });
    let body = {}; try { body = JSON.parse(r.request().postData() || "{}"); } catch (e) {}
    if (p.startsWith("/storage/v1/object/broadcast-media/")) { st.uploads.push({ path: p.replace("/storage/v1/object/broadcast-media/", ""), type: r.request().headers()["content-type"] }); return j(200, { Key: "ok" }); }
    if (p.startsWith("/storage/v1/object/public/broadcast-media/")) return r.fulfill({ status: 200, contentType: "image/png", headers: { "access-control-allow-origin": "*" }, body: PNG });
    if (p.endsWith("/rpc/admin_send_broadcast")) { st.rpc = body; const row = { id: 5, title: body.p.title, body: body.p.body, audience: body.p.audience, image_path: body.p.image, video_path: body.p.video, sent_count: 12, created_at: new Date().toISOString() }; st.list = [row].concat(st.list); return j(200, row); }
    if (p.endsWith("/rpc/admin_broadcast_reach")) { st.reachBody = body; return j(200, 7); }
    if (p === "/rest/v1/patients" && m === "PATCH") { st.cityPatch = { q: u.search, body }; return j(204, {}); }
    if (p.endsWith("/rpc/admin_revoke_broadcast")) { st.del = body; st.list = st.list.map((x) => Object.assign({}, x, { revoked_at: new Date().toISOString() })); return j(200, 2); }
    if (p === "/rest/v1/profiles") return j(200, [{ id: role === "admin" ? "a1" : "p1", role: role, full_name: role === "admin" ? "Admin" : "Asha", phone: "+919876500001", email: "u@x.in" }]);
    if (p === "/rest/v1/broadcasts") return j(200, st.list);
    if (m === "GET") return j(200, []);
    return j(200, {});
  });
  const errs = []; pg.on("pageerror", (e) => errs.push(String(e)));
  await pg.goto("file://" + www); await pg.waitForTimeout(1800);
  return { b, pg, st, errs };
}
(async () => {
  let ok = true; const check = (n, c) => { console.log((c ? "PASS " : "FAIL ") + n); if (!c) ok = false; };
  let t = await open("admin", {}), pg = t.pg;
  await pg.getByRole("button", { name: "Notify" }).click();
  await pg.getByRole("button", { name: "Review and send" }).click();
  check("title is required", /Enter a title/.test(await pg.evaluate(() => document.body.innerText)));
  await pg.fill("#bf-title", "Free health check-up"); await pg.fill("#bf-body", "This Sunday at all partner clinics");
  await pg.selectOption("#bf-aud", "patients"); await pg.fill("#bf-city", "pune"); await pg.waitForTimeout(900);
  check("reach is shown for the city", /About 7 users/.test(await pg.evaluate(() => document.body.innerText)) && t.st.reachBody && t.st.reachBody.p_city === "Pune" && t.st.reachBody.p_audience === "patients");
  await pg.setInputFiles("#bfp-img", { name: "p.png", mimeType: "image/png", buffer: PNG }); await pg.waitForTimeout(800);
  await pg.setInputFiles("#bfp-vid", { name: "clip.mp4", mimeType: "video/mp4", buffer: Buffer.alloc(2048, 1) }); await pg.waitForTimeout(800);
  check("too-big video is refused", await (async () => { await pg.setInputFiles("#bfp-vid", { name: "big.mp4", mimeType: "video/mp4", buffer: Buffer.alloc(21 * 1024 * 1024, 1) }); await pg.waitForTimeout(800); return /larger than 20 MB/.test(await pg.evaluate(() => document.body.innerText)); })());
  await pg.setInputFiles("#bfp-vid", { name: "clip.mp4", mimeType: "video/mp4", buffer: Buffer.alloc(2048, 1) }); await pg.waitForTimeout(800);
  await pg.getByRole("button", { name: "Review and send" }).click();
  check("asks to confirm before sending", /Send this to/.test(await pg.evaluate(() => document.body.innerText)) && t.st.rpc === null);
  await pg.getByRole("button", { name: "Yes, send now" }).click(); await pg.waitForTimeout(1500);
  const p = t.st.rpc && t.st.rpc.p;
  check("RPC body is {p:{...}} with fields", !!p && p.title === "Free health check-up" && p.audience === "patients" && /^i\d+\.jpg$/.test(p.image) && /^v\d+\.mp4$/.test(p.video) && p.city === "Pune");
  check("photo and video uploaded to the broadcast bucket", t.st.uploads.length === 2 && t.st.uploads[0].path === p.image && t.st.uploads[1].path === p.video && t.st.uploads[1].type === "video/mp4");
  const txt = await pg.evaluate(() => document.body.innerText);
  check("history shows it and the sent count", /Sent to 12 users/.test(txt) && /Free health check-up/.test(txt) && /12 notified/.test(txt));
  await pg.getByRole("button", { name: "Revoke", exact: true }).click();
  check("revoke asks first and warns about lock screens", /lock screen/.test(await pg.evaluate(() => document.body.innerText)));
  await pg.getByRole("button", { name: "Yes, revoke" }).click(); await pg.waitForTimeout(1000);
  check("admin can revoke from history", !!t.st.del && t.st.del.p_id === 5 && /Revoked/.test(await pg.evaluate(() => document.body.innerText)) && (await pg.getByRole("button", { name: "Revoke", exact: true }).count()) === 0);
  check("admin: no popup, no page errors", (await pg.locator("#bcpop").count()) === 0 && t.errs.length === 0);
  await t.b.close();
  // patient
  const row = { id: 9, title: "Free health check-up", body: "This Sunday", audience: "patients", image_path: "i1.jpg", video_path: "v1.mp4", sent_count: 3, created_at: "2026-10-13T00:00:00Z" };
  t = await open("patient", { list: [row] }); pg = t.pg;
  await pg.locator("#bcpop").waitFor({ timeout: 8000 });
  check("patient sees the popup with photo, video and text", (await pg.locator("#bcpop img").count()) === 1 && (await pg.locator("#bcpop video").count()) === 1 && /Free health check-up/.test(await pg.locator("#bcpop").innerText()));
  await pg.locator("#bcclose").click();
  check("popup closes", (await pg.locator("#bcpop").count()) === 0);
  await pg.reload(); await pg.waitForTimeout(2500);
  check("not shown again", (await pg.locator("#bcpop").count()) === 0);
  const hasCity = await pg.locator("#city").count();
  if (hasCity) { await pg.evaluate(() => { const e = document.getElementById("city"); const o = document.createElement("option"); o.textContent = "Pune"; e.appendChild(o); e.value = "Pune"; e.dispatchEvent(new Event("input", { bubbles: true })); }); await pg.waitForTimeout(1800);
    check("patient's chosen city is saved", !!t.st.cityPatch && /id=eq\.p1/.test(t.st.cityPatch.q) && t.st.cityPatch.body.city === "Pune"); }
  else console.log("NOTE no #city control on the first screen; not checked");
  check("patient: no page errors", t.errs.length === 0);
  await pg.evaluate(() => { const e = document.getElementById("city"); return !!e; });
  await t.b.close();
  console.log(ok ? "ALL PASSED" : "SOME FAILED"); process.exit(ok ? 0 : 1);
})();
