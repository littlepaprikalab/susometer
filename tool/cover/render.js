// Renders tool/cover/cover.html to docs/cover.png at 2000x840 (DEV's 1000:420 cover ratio, 2x).
// Run from the repo root: node tool/cover/render.js
const path = require("path");
const { chromium } = require("playwright");

(async () => {
  const root = path.join(__dirname, "..", "..");
  const out = process.argv[2] || path.join(root, "docs", "cover.png");
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1000, height: 420 }, deviceScaleFactor: 2 });
  await page.goto("file://" + path.join(__dirname, "cover.html"));
  await page.evaluate(() => document.fonts.ready);
  await page.screenshot({ path: out });
  await browser.close();
  console.log("wrote " + out);
})();
