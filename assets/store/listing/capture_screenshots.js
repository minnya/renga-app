// Captures real in-app screenshots for the Play Store listing using Playwright's
// device emulation (the programmatic equivalent of Chrome DevTools' "device toolbar"),
// against a `flutter build web --release` build served locally.
//
// One-off tooling, not part of the app's runtime dependencies. Requires:
//   npm install --no-save playwright
//   npx playwright install chromium
//
// Usage:
//   flutter build web --release -t lib/main.dart
//   (cd build/web && python -m http.server 8766) &
//   TEST_EMAIL=you@example.com TEST_PASSWORD=... node assets/store/listing/capture_screenshots.js
//
// Output raw device captures under assets/store/listing/raw/<size>/*.png. Run
// compose_screenshots.py afterwards to turn them into the final listing images
// (background + caption + rounded device frame) under assets/store/screenshots_en/.
const { chromium, devices } = require('playwright');
const fs = require('fs');
const path = require('path');

const BASE_URL = process.env.CAPTURE_BASE_URL || 'http://localhost:8766';
const EMAIL = process.env.TEST_EMAIL;
const PASSWORD = process.env.TEST_PASSWORD;
const OUT_ROOT = path.join(__dirname, 'raw');

if (!EMAIL || !PASSWORD) {
  console.error('Set TEST_EMAIL and TEST_PASSWORD env vars to a logged-in-capable test account.');
  process.exit(1);
}

// Login field coordinates (CSS px) were located by hand per device profile, since the
// Flutter web canvas exposes no DOM to query. Re-probe with a throwaway screenshot if the
// login screen layout changes.
const PROFILES = {
  phone: { descriptor: devices['Pixel 7'], cx: 206, yEmail: 300, yPass: 358, yBtn: 436 },
  tablet_7in: { descriptor: devices['Galaxy Tab S4'], cx: 356, yEmail: 430, yPass: 514, yBtn: 606 },
  tablet_10in: { descriptor: devices['Galaxy Tab S9'], cx: 320, yEmail: 394, yPass: 458, yBtn: 530 },
};

const ROUTES = {
  '01_feed': '/#/',
  '02_discover_truth_vote': '/#/discover',
  '03_profile_scorecard': '/#/profile',
  '04_daily_quiz': '/#/daily-quiz',
};

async function loginAndCapture(browser, sizeName, profile) {
  const outDir = path.join(OUT_ROOT, sizeName);
  fs.mkdirSync(outDir, { recursive: true });
  const context = await browser.newContext({ ...profile.descriptor, locale: 'en-US' });
  const page = await context.newPage();
  await page.goto(BASE_URL, { waitUntil: 'load', timeout: 60000 });
  await page.waitForTimeout(10000); // first Flutter web paint is slow in debug/canvas mode

  await page.mouse.click(profile.cx, profile.yEmail);
  await page.waitForTimeout(400);
  await page.keyboard.type(EMAIL);
  await page.mouse.click(profile.cx, profile.yPass);
  await page.waitForTimeout(400);
  await page.keyboard.type(PASSWORD);
  await page.mouse.click(profile.cx, profile.yBtn);
  await page.waitForTimeout(6000);

  for (const [fname, route] of Object.entries(ROUTES)) {
    await page.goto(`${BASE_URL}${route}`, { waitUntil: 'load' });
    await page.waitForTimeout(3000);
    await page.screenshot({ path: path.join(outDir, `${fname}.png`) });
  }

  await context.close();
}

(async () => {
  const browser = await chromium.launch();
  for (const [name, profile] of Object.entries(PROFILES)) {
    console.log('capturing', name);
    await loginAndCapture(browser, name, profile);
  }
  await browser.close();
  console.log('DONE');
})();
