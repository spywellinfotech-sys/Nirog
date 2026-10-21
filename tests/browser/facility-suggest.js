// Real-Chromium check: the facility registration form for a new lab/centre/hospital offers suggestions and a quick-add for tests and specialities.
const { chromium } = require("playwright");
const path = require("path");
const www = path.resolve(__dirname, "../../app/src/main/assets/www/index.html");
(async () => {
  let ok = true; const check = (n, c) => { console.log((c ? "PASS " : "FAIL ") + n); if (!c) ok = false; };
  const b = await chromium.launch({ executablePath: process.env.CHROME || "/opt/pw-browsers/chromium-1194/chrome-linux/chrome" });
  const ctx = await b.newContext({ viewport: { width: 390, height: 900 } });
  const pg = await ctx.newPage();
  await pg.route(/supabase\.co/, (r) => {
    const u = new URL(r.request().url()), m = r.request().method(), p = u.pathname;
    const j = (s, o) => r.fulfill({ status: s, contentType: "application/json", headers: { "access-control-allow-origin": "*" }, body: JSON.stringify(o) });
    if (m === "OPTIONS") return r.fulfill({ status: 204, headers: { "access-control-allow-origin": "*", "access-control-allow-headers": "*", "access-control-allow-methods": "*" } });
    if (p === "/rest/v1/profiles") return j(200, [{ id: "a1", role: "admin", full_name: "Admin", phone: null, email: "admin@x.in" }]);
    if (m === "GET") return j(200, []);
    return j(200, {});
  });
  const errs = []; pg.on("pageerror", (e) => errs.push(String(e)));
  await pg.goto("file://" + www + "#facility"); await pg.waitForTimeout(1500);
  check("lab form offers a test suggestion list", (await pg.locator("#sg-fr-list option").count()) > 30 && (await pg.locator("#sg-fr-name").getAttribute("list")) === "sg-fr-list");
  await pg.fill("#sg-fr-name", "HbA1c"); await pg.fill("#sg-fr-price", "400"); await pg.getByRole("button", { name: "Add to list" }).click(); await pg.waitForTimeout(300);
  check("Add puts 'name - price' into the list", (await pg.inputValue("#fr-tests")) === "HbA1c - 400");
  await pg.locator('[data-a="sgchip"]').filter({ hasText: "Lipid profile" }).click(); await pg.waitForTimeout(200);
  check("tapping a suggestion fills the name and waits for the price", (await pg.inputValue("#sg-fr-name")) === "Lipid profile");
  await pg.fill("#sg-fr-price", "600"); await pg.getByRole("button", { name: "Add to list" }).click(); await pg.waitForTimeout(300);
  check("second test is added on a new line", (await pg.inputValue("#fr-tests")) === "HbA1c - 400\nLipid profile - 600");
  await pg.fill("#sg-fr-name", "hba1c"); await pg.fill("#sg-fr-price", "999"); await pg.getByRole("button", { name: "Add to list" }).click(); await pg.waitForTimeout(300);
  check("the same test is not added twice", (await pg.inputValue("#fr-tests")) === "HbA1c - 400\nLipid profile - 600");
  await pg.selectOption("#fr-kind", "hospital"); await pg.waitForTimeout(400);
  check("hospital gets specialities and no price box", (await pg.locator("#sg-fr-list option[value='Cardiology']").count()) === 1 && (await pg.locator("#sg-fr-price").count()) === 0);
  await pg.locator('[data-a="sgchip"]').filter({ hasText: "Cardiology" }).first().click(); await pg.waitForTimeout(300);
  check("tapping a speciality adds it straight away", /Cardiology/.test(await pg.inputValue("#fr-tests")));
  await pg.selectOption("#fr-kind", "centre"); await pg.waitForTimeout(400);
  check("centre list includes scans and tests", (await pg.locator("#sg-fr-list option[value='MRI brain']").count()) === 1 && (await pg.locator("#sg-fr-list option[value='HbA1c']").count()) === 1);
  check("no page errors", errs.length === 0);
  console.log(ok ? "ALL PASSED" : "SOME FAILED"); await b.close(); process.exit(ok ? 0 : 1);
})();
