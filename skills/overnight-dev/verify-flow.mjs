#!/usr/bin/env node
/*
 * Walk the onboarding flow on a deployed build with the v2 redesign FORCED, and
 * report console errors, page errors and failed requests per route.
 *
 *   export QA_EMAIL='...' QA_PASSWORD='...'
 *   node verify-flow.mjs --base https://your-dev-host.example.com
 *   node verify-flow.mjs --base http://localhost:3000 --headed
 *
 * Credentials come from the environment, never from this file.
 *
 * Why v2 must be forced: dev serves v1 by default. Without `?ui=v2` plus the
 * localStorage override you will walk the OLD UI and report a clean run that
 * says nothing about the redesign. That is the most expensive mistake here.
 */
import { chromium } from 'playwright';
import { writeFileSync } from 'node:fs';

const arg = (flag, dflt) => {
  const i = process.argv.indexOf(flag);
  return i > -1 ? process.argv[i + 1] : dflt;
};
const BASE = (arg('--base', process.env.QA_BASE_URL || 'http://localhost:3000')).replace(/\/$/, '');
const HEADED = process.argv.includes('--headed');
const OUT = arg('--out', 'flow-report.json');
const EMAIL = process.env.QA_EMAIL;
const PASSWORD = process.env.QA_PASSWORD;

if (!EMAIL || !PASSWORD) {
  console.error('verify-flow: set QA_EMAIL and QA_PASSWORD in the environment.');
  process.exit(2);
}

/* Onboarding guide steps mapped onto promoted V2_READY_ROUTES. `needsId` steps
 * are skipped unless an id is supplied — a synthetic id would 404 and read as a
 * defect that is really just a bad fixture. */
const STEPS = [
  { key: 'home',        label: 'Home / workspaces',    path: '/' },
  { key: 'datasources', label: 'Connect a datasource', path: '/datasources' },
  // Replace these with your product's real surfaces, or pass --routes.
  { key: 'listing',   label: 'A listing page',     path: '/items' },
  { key: 'editor',    label: 'The main editor',    path: '/items/new' },
  { key: 'browse',    label: 'A browse surface',   path: '/library' },
  { key: 'settings',  label: 'Settings',           path: '/settings' },
  { key: 'members',   label: 'Settings / members', path: '/settings/people' },
  { key: 'security',  label: 'Settings / security',path: '/settings/security' },
];

/* Console noise that is structurally not an app defect - the same list your
 * error tracker already suppresses. Keep this SHORT and justified: every entry
 * is a class of bug you have chosen to stop seeing. */
const NOISE = [
  /dotlottieplayerwasm_/i,
  /^ResizeObserver loop/i,
  /intercom/i,
  /Download the React DevTools/i,
  /\[vite\] connect/i,
];
const isNoise = (t) => NOISE.some((re) => re.test(t));

// Force the UI flag on every navigation. QA_FLAG_PARAM defaults to "ui=v2";
// set it to an empty string if your app has no such flag.
const FLAG_PARAM = process.env.QA_FLAG_PARAM ?? 'ui=v2';
const withV2 = (url) =>
  !FLAG_PARAM ? url : url.includes('?') ? `${url}&${FLAG_PARAM}` : `${url}?${FLAG_PARAM}`;

const run = async () => {
  const browser = await chromium.launch(
    HEADED ? { headless: false, channel: 'chrome' } : { headless: true }
  );
  const ctx = await browser.newContext({ viewport: { width: 1600, height: 1000 } });
  // Belt and braces: the query param sets it, this survives client-side navigation.
  await ctx.addInitScript(() => {
    try { localStorage.setItem(process.env.QA_FLAG_KEY || 'app:uiVersion', process.env.QA_FLAG_VALUE || 'v2'); } catch { /* private mode */ }
  });

  const page = await ctx.newPage();
  const bucket = { console: [], pageerror: [], request: [] };
  page.on('console', (m) => {
    if (m.type() !== 'error') return;
    const t = m.text();
    if (!isNoise(t)) bucket.console.push(t.slice(0, 300));
  });
  page.on('pageerror', (e) => {
    if (!isNoise(e.message)) bucket.pageerror.push(e.message.slice(0, 300));
  });
  page.on('requestfailed', (r) => {
    const t = `${r.method()} ${r.url().slice(0, 160)} — ${r.failure()?.errorText}`;
    if (!isNoise(t)) bucket.request.push(t);
  });
  page.on('response', (r) => {
    if (r.status() < 400) return;
    // GraphQL returns 200 with an errors[] body; those surface via console instead.
    bucket.request.push(`HTTP ${r.status()} ${r.url().slice(0, 160)}`);
  });

  const drain = () => {
    const out = {
      console: [...new Set(bucket.console)],
      pageerror: [...new Set(bucket.pageerror)],
      request: [...new Set(bucket.request)],
    };
    bucket.console = []; bucket.pageerror = []; bucket.request = [];
    return out;
  };

  const report = { base: BASE, startedAt: new Date().toISOString(), steps: [] };

  // ---- sign in -------------------------------------------------------------
  console.log(`verify-flow: ${BASE} (v2 forced)`);
  await page.goto(withV2(`${BASE}/users/sign-in`), { waitUntil: 'domcontentloaded', timeout: 90000 });
  await page.waitForTimeout(6000);
  /*
   * The sign-in form differs between the two UIs and `V2_ROUTES.auth` IS
   * promoted, so forcing v2 changes the submit button out from under you:
   * Two UI versions often ship different submit buttons.
   * The email and password inputs are usually common to both. Accept
   * either button rather than pinning one — this is how the first version of
   * this script broke.
   */
  await page.fill('input[name=email]', EMAIL);
  await page.fill(process.env.QA_PASSWORD_SELECTOR || 'input[type=password]', PASSWORD);
  const submit = page.locator(process.env.QA_SUBMIT_SELECTOR || 'button[type=submit], #login-btn, #continue-btn').first();
  await submit.waitFor({ state: 'visible', timeout: 30000 });
  await submit.click();
  await page.waitForTimeout(15000);

  /*
   * "SIGNED IN" IS NOT "NOT ON /sign-in".
   *
   * This was `!/sign-in/.test(page.url())`, and it reported a clean run against
   * a wall. dev answers a correct password with an OTP challenge at
   * `/users/otpVerification` — which contains no "sign-in", so the check passed,
   * every one of the 14 routes then bounced to `/users/sign-in`, and the script
   * printed "0 blocked of 14" about the LOGIN PAGE. The v2 assertion below did
   * not catch it either: `V2_ROUTES.auth` is promoted, so `[data-ui="v2"]` is
   * present on the sign-in page and "redesign active: true" was also true and
   * also meaningless.
   *
   * So the test is now positive rather than negative — we must be on a route
   * that is NOT part of the auth flow — and it names OTP specifically, because
   * "your credentials worked but a human has to type a code" is a different
   * outcome from "your password is wrong" and deserves a different message.
   */
  const AUTH_PATH = /\/users\/(sign-?in|sign-?up|otpVerification|forgot|reset|verify)/i;
  const atOtp = /otpVerification/i.test(page.url());
  const signedIn = !AUTH_PATH.test(page.url());
  report.steps.push({ key: 'signIn', label: 'Sign in', url: page.url(), ok: signedIn, atOtp, ...drain() });
  console.log(`  ${signedIn ? 'ok  ' : 'FAIL'} Sign in -> ${page.url()}`);
  if (!signedIn) {
    report.abortedAt = atOtp ? 'otpChallenge' : 'signIn';
    if (atOtp) {
      console.error('  FAIL: stopped at the OTP challenge. The password was accepted;');
      console.error('        a one-time code is required, and no route past this point');
      console.error('        would be the app. Use an account without OTP, or complete');
      console.error('        the challenge and re-run.');
    }
    writeFileSync(OUT, JSON.stringify(report, null, 2));
    await browser.close();
    process.exit(1);
  }

  // Confirm we are actually on the redesign before believing anything after this.
  const isV2 = await page.evaluate(() => !!document.querySelector('[data-ui="v2"]'));
  report.v2Confirmed = isV2;
  console.log(`  ${isV2 ? 'ok  ' : 'WARN'} redesign active: ${isV2}`);
  if (!isV2) console.log('  WARN: v2 not detected — findings below describe the OLD UI.');

  // ---- walk the flow -------------------------------------------------------
  for (const step of STEPS) {
    const url = withV2(`${BASE}${step.path}`);
    let navOk = true;
    try {
      await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 90000 });
      await page.waitForTimeout(7000);
    } catch (e) {
      navOk = false;
      bucket.pageerror.push(`navigation failed: ${e.message.slice(0, 200)}`);
    }
    /*
     * Re-assert per route. A session can die mid-walk (expiry, a 401, a stray
     * click), and every route after that silently becomes the sign-in page —
     * which renders fine, is not blank, and logs no errors, so it scores as a
     * PASS. That is how this script reported "0 blocked of 14" about a login
     * wall. A bounce to auth is a failed step, not a clean one.
     */
    const bouncedToAuth = AUTH_PATH.test(page.url());
    if (bouncedToAuth) {
      navOk = false;
      bucket.pageerror.push(
        `bounced to auth (${page.url()}) — session lost; this route was NOT verified`
      );
    }

    const blank = await page
      .evaluate(() => (document.body.innerText || '').trim().length < 40)
      .catch(() => true);
    const found = drain();
    const blockers = found.pageerror.length + (blank ? 1 : 0);
    report.steps.push({ ...step, url: page.url(), ok: navOk && !blank, blank, ...found });
    console.log(
      `  ${blockers ? 'FAIL' : found.console.length || found.request.length ? 'warn' : 'ok  '} ` +
      `${step.label.padEnd(24)} err=${found.pageerror.length} console=${found.console.length} req=${found.request.length}${blank ? ' BLANK' : ''}`
    );
  }

  report.finishedAt = new Date().toISOString();
  const blockers = report.steps.filter((s) => !s.ok);
  report.summary = {
    steps: report.steps.length,
    blocked: blockers.length,
    blockedKeys: blockers.map((s) => s.key),
    totalConsole: report.steps.reduce((a, s) => a + (s.console?.length || 0), 0),
  };
  writeFileSync(OUT, JSON.stringify(report, null, 2));
  console.log(`\nverify-flow: ${blockers.length} blocked of ${report.steps.length}; full report -> ${OUT}`);
  await browser.close();
  process.exit(blockers.length ? 1 : 0);
};

run().catch((e) => { console.error('verify-flow: crashed —', e.message); process.exit(2); });
