// Layer 3 — autonomous browser verification of the Lani test container's web UI.
// Deterministic gate (exit 0/1) that complements an agent driving a browser MCP live.
// Run from inside lani-shell (which shares the host network, so it can reach the test
// container's LAN IP printed by request-test.sh / health.sh):
//
//   node tests/browser-check.mjs http://<test-ip> [path] [expected-text]
//
// Defaults (for backward compat when called with just a URL):
//   path = /login, expected-text = nextcloud
//
// Examples:
//   node tests/browser-check.mjs http://<ip>
//   node tests/browser-check.mjs http://<ip> /login nextcloud
//   node tests/browser-check.mjs http://<ip> / "It works"
//
// Requires Playwright + a Chromium. On NixOS the simplest is:
//   nix shell nixpkgs#nodejs nixpkgs#playwright-driver.browsers --command \
//     env PLAYWRIGHT_BROWSERS_PATH="$PLAYWRIGHT_BROWSERS_PATH" \
//     node tests/browser-check.mjs http://<test-ip>
// (or point PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH at a system chromium).
import { chromium } from "playwright";

const base = process.argv[2];
const path = process.argv[3] || "/login";
const expected = process.argv[4] || "nextcloud";

if (!base) {
  console.error(
    "usage: node browser-check.mjs <http://ip> [path] [expected-text]",
  );
  process.exit(2);
}

const serviceName =
  path === "/login" && expected === "nextcloud" ? "nextcloud" : expected;
const shot = `/tmp/lani-${serviceName}-browser.png`;
const browser = await chromium.launch({ headless: true });
try {
  const page = await browser.newPage();
  const url = new URL(path, base).href;
  await page.goto(url, { waitUntil: "networkidle", timeout: 30000 });
  await page.screenshot({ path: shot, fullPage: true });
  const blob =
    (await page.title()) +
    " " +
    (await page.textContent("body").catch(() => ""));
  const regex = new RegExp(expected, "i");
  if (!regex.test(blob)) {
    console.error(
      `FAIL: text "${expected}" not detected at ${url} (screenshot: ${shot})`,
    );
    process.exit(1);
  }
  console.log(`PASS: UI rendered at ${url} (screenshot: ${shot})`);
} finally {
  await browser.close();
}
