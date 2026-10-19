// Real-Chromium check against a mocked Supabase: the patient sees a sponsored banner for their city; the super admin publishes, hides and deletes ads.
const { chromium } = require("playwright");
const path = require("path");
const www = path.resolve(__dirname, "../../app/src/main/assets/www/index.html");
const PNG = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==", "base64");
async function open(role) {
  const b = await chromium.launch({ executablePath: process.env.CHROME || "/opt/pw-browsers/chromium-1194/chrome-linux/chrome" });
  const ctx = await b.newContext({ viewport: { width: 390, height: 900 } });
  await ctx.addInitScript((id) => { try { localStorage.setItem("nirog-sb-session-v1", JSON.stringify({ access_token: "tok", refresh_token: "r", expires_at: Math.floor(Date.now() / 1000) + 3600, user: { id: id, email: "u@x.in" } })); } catch (e) {} }, role === "admin" ? "a1" : "p1");
  const pg = await ctx.newPage();
  const st = { saved: null, views: [], deleted: null, uploads: [], clicks: [], ads: [{ id: 1, title: "Free eye check-up", advertiser: "Asha Eye Clinic", kind: "image", media_path: "ad1.jpg", images: ["ad1.jpg", "ad1b.jpg", "ad1c.jpg"], link_url: "https://asha-eye.example/offer", clicks: 3, city: "Pune", starts_on: "2020-01-01", ends_on: null, active: true, views: 7, created_at: new Date().toISOString() }], active: [{ id: 1, title: "Free eye check-up", advertiser: "Asha Eye Clinic", kind: "image", media: "ad1.jpg", images: ["ad1.jpg", "ad1b.jpg", "ad1c.jpg"], link: "https://asha-eye.example/offer" }, { id: 2, title: "Lab video offer", advertiser: "City Lab", kind: "video", media: "v2.mp4", images: ["v2.mp4"], link: "https://citylab.example" }], cityAsked: [] };
  await pg.route(/supabase\.co/, (r) => {
    const u = new URL(r.request().url()), m = r.request().method(), p = u.pathname;
    const j = (s, o) => r.fulfill({ status: s, contentType: "application/json", headers: { "access-control-allow-origin": "*" }, body: JSON.stringify(o) });
    if (m === "OPTIONS") return r.fulfill({ status: 204, headers: { "access-control-allow-origin": "*", "access-control-allow-headers": "*", "access-control-allow-methods": "*" } });
    if (p.includes("/storage/v1/object/public/")) return r.fulfill({ status: 200, contentType: "image/png", headers: { "access-control-allow-origin": "*" }, body: PNG });
    if (p.includes("/storage/v1/object/")) { st.uploads.push(p); return j(200, { Key: "x" }); }
    let body = {}; try { body = JSON.parse(r.request().postData() || "{}"); } catch (e) {}
    if (p.endsWith("/rpc/active_ads")) { st.cityAsked.push(body.p_city); return j(200, st.active); }
    if (p.endsWith("/rpc/log_ad_click")) { st.clicks.push(body.p_id); return j(200, null); }
    if (p.endsWith("/rpc/log_ad_view")) { st.views.push(body.p_id); return j(200, null); }
    if (p === "/rest/v1/ads") return j(200, st.ads);
    if (p.endsWith("/rpc/admin_save_ad")) { st.saved = body.p; const row = Object.assign({ id: 9, advertiser: "", views: 0, starts_on: "2020-01-01", ends_on: null, active: true, city: null, media_path: body.p.media_path, created_at: new Date().toISOString() }, body.p); if (body.p.id) st.ads = st.ads.map((a) => (a.id === body.p.id ? Object.assign({}, a, { active: body.p.active, title: body.p.title }) : a)); else st.ads = st.ads.concat([row]); return j(200, row); }
    if (p.endsWith("/rpc/admin_delete_ad")) { st.deleted = body.p_id; st.ads = st.ads.filter((a) => a.id !== body.p_id); return j(200, true); }
    if (p.endsWith("/rpc/admin_dashboard_counts")) return j(200, { patients: 1, doctors: { listed: 0, pending: 0 }, facilities: {}, specialties: [], phones: 0, phone_users: 0 });
    if (p === "/rest/v1/profiles") return j(200, [{ id: role === "admin" ? "a1" : "p1", role: role, full_name: "X", phone: "+919876500001", email: "u@x.in" }]);
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
  await pg.waitForTimeout(800);
  check("the patient sees a sponsored banner with the advertiser", /Sponsored/.test(await txt()) && /Asha Eye Clinic/.test(await txt()) && /Free eye check-up/.test(await txt()));
  check("all photos of the banner are in the slideshow, the first one showing", (await pg.locator("#adshow .adslide").count()) === 4 && (await pg.locator("#adshow .adslide").first().isVisible()) && !(await pg.locator("#adshow .adslide").nth(1).isVisible()));
  check("the banner image comes from the media bucket", (await pg.locator('img[src*="/object/public/broadcast-media/ad1.jpg"]').count()) === 1);
  await pg.waitForTimeout(4400);
  check("the slideshow moves on to the next photo by itself", (await pg.locator("#adshow .adslide").nth(1).isVisible()) && !(await pg.locator("#adshow .adslide").first().isVisible()));
  const lk = pg.locator("#adshow a[data-adclick]").first();
  check("a tap on the banner goes to the sponsor link in a new tab", (await lk.getAttribute("href")) === "https://asha-eye.example/offer" && (await lk.getAttribute("target")) === "_blank");
  await pg.evaluate(() => document.addEventListener("click", (e) => { if (e.target.closest("a")) e.preventDefault(); }, true));
  await pg.locator("#adshow .adslide:visible a").first().click(); await pg.waitForTimeout(400);
  check("the link tap is counted", t.st.clicks.length === 1 && t.st.clicks[0] === 1);
  check("the video ad is part of the top banner, not a separate section", (await pg.locator("#adshow video[src*='v2.mp4']").count()) === 1 && !/sponsored video/i.test(await txt()));
  check("the video ad has a Visit sponsor link", (await pg.locator('#adshow a[data-adclick="2"]').count()) === 1);
  await pg.waitForTimeout(9000);
  check("the banner reaches the video slide and it is the visible one", await pg.evaluate(() => { const v = document.querySelector("#adshow video"); return !!v && v.closest(".adslide").style.display !== "none"; }));
  check("each ad is counted once as shown", t.st.views.indexOf(1) >= 0 && t.st.views.indexOf(2) >= 0 && t.st.views.length === 2);
  check("the app asked for ads for the chosen city", t.st.cityAsked.length >= 1);
  check("no page errors (patient)", t.errs.length === 0); await t.b.close();
  t = await open("admin"); pg = t.pg;
  await pg.getByRole("button", { name: "Ads", exact: true }).click(); await pg.waitForTimeout(800);
  check("the admin sees the ad with its photos, views, link taps and Live status", /Free eye check-up/.test(await txt()) && /3 photos/.test(await txt()) && /Shown 7 times/.test(await txt()) && /Link tapped 3 times/.test(await txt()) && /Live/.test(await txt()));
  await pg.getByRole("button", { name: "Publish ad" }).click(); await pg.waitForTimeout(300);
  check("publishing without a photo asks for one", /Enter a title|Choose at least one photo/.test(await txt()));
  await pg.fill("#ad-title", "Pharmacy discount"); await pg.fill("#ad-adv", "Shree Pharmacy"); await pg.fill("#ad-link", "http://not-secure.example");
  for (const n of ["b1","b2","b3"]) { await pg.setInputFiles("#adp-one", [{ name: n + ".png", mimeType: "image/png", buffer: PNG }]); await pg.waitForTimeout(700); }
  check("several photos can be chosen at once", (await pg.locator('.thumb img[alt^="Photo"]').count()) === 3);
  await pg.getByRole("button", { name: "Publish ad" }).click(); await pg.waitForTimeout(400);
  check("an http sponsor link is refused", /must start with https/.test(await txt()) && t.st.saved === null);
  await pg.fill("#ad-link", "https://shree-pharmacy.example/sale");
  await pg.getByRole("button", { name: "Remove photo 3" }).click(); await pg.waitForTimeout(300);
  await pg.getByRole("button", { name: "Publish ad" }).click(); await pg.waitForTimeout(1500);
  check("every photo is uploaded and the ad is saved with its link", t.st.uploads.length === 2 && t.st.saved && t.st.saved.title === "Pharmacy discount" && t.st.saved.kind === "image" && t.st.saved.images.length === 2 && t.st.saved.images.every((x) => /^ad\d+-\d\.jpg$/.test(x)) && t.st.saved.link_url === "https://shree-pharmacy.example/sale");
  check("the new ad shows in the list", /Pharmacy discount/.test(await txt()) && /Ad published/.test(await txt()));
  await pg.getByRole("button", { name: "Hide" }).first().click(); await pg.waitForTimeout(800);
  check("Hide switches the ad off", t.st.saved.active === false && /Hidden from patients/.test(await txt()));
  await pg.getByRole("button", { name: "Delete" }).first().click(); await pg.waitForTimeout(300);
  await pg.getByRole("button", { name: "Yes, delete" }).click(); await pg.waitForTimeout(800);
  check("an ad can be deleted after confirming", t.st.deleted !== null && /Ad deleted/.test(await txt()));
  check("no page errors (admin)", t.errs.length === 0); await t.b.close();
  console.log(ok ? "ALL PASSED" : "SOME FAILED"); process.exit(ok ? 0 : 1);
})();
