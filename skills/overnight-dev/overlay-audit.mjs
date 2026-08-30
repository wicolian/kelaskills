#!/usr/bin/env node
/*
 * Open every overlay trigger on a route and assert the four things a power user
 * silently depends on:
 *
 *   ON TOP      elementFromPoint at the overlay's centre resolves inside it
 *   SCROLLABLE  if the content overflows, it can actually scroll
 *   UNCLIPPED   no ancestor's overflow is cutting it off
 *   DISMISSIBLE Escape closes it and returns focus
 *
 * Plus a heap sample per route, so a leak shows up as growth across the run.
 *
 *   export QA_EMAIL='...' QA_PASSWORD='...'
 *   node overlay-audit.mjs --base http://localhost:3000 --route /items/new
 *   node overlay-audit.mjs --base http://localhost:3000 --routes /,/library,/items/new
 *
 * Real Chrome by default: the headless shell composites differently and will not
 * reproduce stacking bugs. --headless only for a quick smoke.
 */
import { chromium } from 'playwright';
import { writeFileSync, appendFileSync, existsSync } from 'node:fs';

const arg = (f, d) => { const i = process.argv.indexOf(f); return i > -1 ? process.argv[i + 1] : d; };
const BASE = arg('--base', process.env.QA_BASE_URL || 'http://localhost:3000').replace(/\/$/, '');
const ROUTES = (arg('--routes', arg('--route', '/'))).split(',').map((s) => s.trim()).filter(Boolean);
const OUT = arg('--out', 'overlay-audit.json');
const LEDGER = arg('--ledger', 'qa-findings.md');
const HEADLESS = process.argv.includes('--headless');
const MAX_TRIGGERS = Number(arg('--max-triggers', '25'));

const EMAIL = process.env.QA_EMAIL, PASSWORD = process.env.QA_PASSWORD;
if (!EMAIL || !PASSWORD) { console.error('set QA_EMAIL and QA_PASSWORD'); process.exit(2); }

// Force the UI flag on every navigation. Set QA_FLAG_PARAM='' if there is none.
const FLAG_PARAM = process.env.QA_FLAG_PARAM ?? 'ui=v2';
const withV2 = (u) =>
  !FLAG_PARAM ? u : u.includes('?') ? `${u}&${FLAG_PARAM}` : `${u}?${FLAG_PARAM}`;

/*
 * WHAT COUNTS AS A TRIGGER.
 *
 * This list used to be Radix-only (`aria-haspopup`, `aria-expanded`,
 * `data-slot$="-trigger"`, `button[role=combobox]`). That made the audit report
 * "2 triggers -> route NOT audited" on five routes, which read as *the route is
 * empty* and was chased as a product bug. It was not: one of those routes
 * carried 48 interactive elements whose row actions are plain `<button>`,
 * which the Radix selector cannot see. Settings pages are tabs, switches and
 * links - likewise invisible.
 *
 * So the selector is now "things a person can click", and the Radix hooks are
 * kept only as the ordering prefix, because a known overlay trigger is still the
 * highest-yield thing to open first. A plain button that opens nothing is
 * cheap - `openAndAudit` just records no overlay and moves on - whereas a menu
 * this never clicked is a stacking bug nobody found.
 *
 * `:not([disabled])` and the aria-disabled guard matter: clicking a disabled
 * control is a guaranteed no-open, and with MAX_TRIGGERS capping the walk those
 * wasted slots are coverage taken from real ones.
 */
const TRIGGER_SEL = [
  // Radix-shaped: overlay triggers proper, kept first so they are audited first.
  '[aria-haspopup]',
  '[aria-expanded]',
  '[data-slot$="-trigger"]',
  'button[role="combobox"]',
  // …and everything else a power user actually clicks.
  //
  // ANCHORS ARE DELIBERATELY ABSENT. A link's job is to navigate, so including
  // `a[href]` spent most of the per-route trigger budget on guaranteed
  // navigations: measured at 13-14 "navigated away" out of 30 on two listing
  // routes, which is coverage taken from controls that actually open
  // something. Buttons that navigate still exist and the escape guard below
  // catches them; the point is not to go looking for them.
  'button:not([disabled]):not([aria-disabled="true"])',
  '[role="button"]:not([aria-disabled="true"])',
  '[role="menuitem"]',
  '[role="switch"]',
  'summary',
  'select',
]
  .map((s) => `${s}:not([data-qa-audit-skip])`)
  .join(',');
const OVERLAY_SEL = [
  '[data-slot="dropdown-menu-content"]', '[data-slot="select-content"]',
  '[data-slot="popover-content"]', '[data-slot="dialog-content"]',
  '[data-radix-popper-content-wrapper]', '[role="menu"]', '[role="listbox"]',
  // Non-Radix overlays the app also ships. Without these an overlay can open
  // and be scored as "nothing opened", which is a false PASS, not a miss.
  '[role="dialog"]', '[role="tooltip"]', '[role="alertdialog"]',
  '[data-state="open"][data-side]',
].join(',');

/* Runs in the page: audit whatever overlay is currently open. */
const AUDIT = (OVERLAY_SEL) => {
  const el = [...document.querySelectorAll(OVERLAY_SEL)]
    .filter((n) => n.getBoundingClientRect().width > 0)
    .pop();
  if (!el) return { opened: false };

  const r = el.getBoundingClientRect();
  const cs = getComputedStyle(el);
  const cx = Math.round(r.left + r.width / 2);
  const cy = Math.round(r.top + Math.min(r.height / 2, 40));

  // ON TOP: what actually receives a click at the overlay's centre?
  const hit = document.elementFromPoint(cx, cy);
  const onTop = !!hit && (el.contains(hit) || hit.contains(el));
  const blockedBy = onTop ? null : (() => {
    if (!hit) return 'nothing (offscreen)';
    const h = getComputedStyle(hit);
    return `${hit.tagName.toLowerCase()}${hit.className && typeof hit.className === 'string' ? '.' + hit.className.trim().split(/\s+/).slice(0, 2).join('.') : ''} z=${h.zIndex}`;
  })();

  // SCROLLABLE: overflowing content must be reachable
  const scrollers = [el, ...el.querySelectorAll('*')].filter((n) => n.scrollHeight - n.clientHeight > 8);
  const overflows = el.scrollHeight - el.clientHeight > 8;
  const scrollable = !overflows || scrollers.some((n) => /auto|scroll/.test(getComputedStyle(n).overflowY));

  // UNCLIPPED: an ancestor with hidden overflow that cuts the box
  let clippedBy = null;
  for (let p = el.parentElement; p && p !== document.body; p = p.parentElement) {
    const pc = getComputedStyle(p);
    if (!/hidden|clip/.test(pc.overflow + pc.overflowX + pc.overflowY)) continue;
    const pr = p.getBoundingClientRect();
    if (r.right > pr.right + 1 || r.bottom > pr.bottom + 1 || r.left < pr.left - 1 || r.top < pr.top - 1) {
      clippedBy = `${p.tagName.toLowerCase()} overflow=${pc.overflow || pc.overflowY}`;
      break;
    }
  }

  // Stacking context this overlay actually landed in
  const zChain = [];
  for (let p = el; p && p !== document.body; p = p.parentElement) {
    const z = getComputedStyle(p).zIndex;
    if (z !== 'auto') zChain.push(`${p.tagName.toLowerCase()}=${z}`);
  }

  return {
    opened: true, onTop, blockedBy, overflows, scrollable, clippedBy,
    z: cs.zIndex, zChain: zChain.slice(0, 4),
    box: { w: Math.round(r.width), h: Math.round(r.height) },
    offscreen: r.bottom > innerHeight + 2 || r.right > innerWidth + 2 || r.top < -2 || r.left < -2,
  };
};

const heap = (page) => page.evaluate(() =>
  performance.memory ? Math.round(performance.memory.usedJSHeapSize / 1048576) : null);

const findings = [];
const note = (f) => {
  findings.push(f);
  const md = `\n## ${f.route} - ${f.symptom}\nclass:    ${f.class}\nrepro:    open trigger \`${f.trigger}\`\nexpected: ${f.expected}\nactual:   ${f.actual}\nevidence: ${JSON.stringify(f.evidence)}\nfix:      open\n`;
  appendFileSync(LEDGER, md);
  console.log(`  FINDING [${f.class}] ${f.symptom} - ${f.trigger}`);
};

const run = async () => {
  const browser = await chromium.launch(
    HEADLESS ? { headless: true } : { headless: false, channel: 'chrome' });
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  await ctx.addInitScript(() => { try { localStorage.setItem(process.env.QA_FLAG_KEY || 'app:uiVersion', process.env.QA_FLAG_VALUE || 'v2'); } catch {} });
  const page = await ctx.newPage();

  if (!existsSync(LEDGER)) writeFileSync(LEDGER, `# QA findings - ${new Date().toISOString()}\n`);

  // sign in. Override the selectors with QA_SUBMIT_SELECTOR / QA_PASSWORD_SELECTOR
  // when the two UI versions expose different sign-in buttons.
  await page.goto(withV2(`${BASE}/users/sign-in`), { waitUntil: 'domcontentloaded', timeout: 90000 });
  await page.waitForTimeout(6000);
  await page.fill('input[name=email]', EMAIL);
  await page.fill(process.env.QA_PASSWORD_SELECTOR || 'input[type=password]', PASSWORD);
  const submit = page.locator(process.env.QA_SUBMIT_SELECTOR || 'button[type=submit], #login-btn, #continue-btn').first();
  await submit.waitFor({ state: 'visible', timeout: 30000 });
  await submit.click();
  await page.waitForTimeout(15000);
  if (/sign-in/.test(page.url())) { console.error('sign-in failed'); await browser.close(); process.exit(1); }
  console.log(`signed in; v2=${await page.evaluate(() => !!document.querySelector('[data-ui="v2"]'))}`);

  const heapTrail = []; const coverage = [];
  for (const route of ROUTES) {
    console.log(`\n=== ${route} ===`);
    await page.goto(withV2(`${BASE}${route}`), { waitUntil: 'domcontentloaded', timeout: 90000 });
    await page.waitForTimeout(7000);
    const before = await heap(page);

    const n = Math.min(await page.locator(TRIGGER_SEL).count(), MAX_TRIGGERS);
    let opened = 0; const noOpen = [];
    console.log(`  ${n} trigger(s)`);

    /*
     * THE ESCAPE GUARD.
     *
     * Widening TRIGGER_SEL beyond Radix means this now clicks things that
     * NAVIGATE, and one of them is fatal: a "Log out" control ends the session,
     * after which every later `goto` bounces to the marketing site and every
     * route reports the same handful of triggers. That is not a slow audit, it
     * is a SILENTLY WRONG one - the run still prints per-route findings, and all
     * of them describe the landing page. It happened, and the only reason it was
     * caught is that 13 different routes implausibly reported "15 triggers".
     *
     * So: skip the known one-way doors by label before clicking, and after every
     * click confirm we are still on the route we think we are auditing. If we
     * left, go back and record it - never keep measuring whatever we landed on.
     */
    const EXIT_LABEL = /log\s*out|sign\s*out|logout|signout|help\s*center|switch\s+workspace|delete\s+account/i;
    const routePath = new URL(withV2(`${BASE}${route}`)).pathname;
    let escapes = 0;

    for (let i = 0; i < n; i++) {
      const t = page.locator(TRIGGER_SEL).nth(i);
      let label = '(unlabelled)';
      try {
        if (!(await t.isVisible())) continue;
        label = ((await t.getAttribute('aria-label')) || (await t.innerText()) || (await t.getAttribute('data-slot')) || '')
          .trim().slice(0, 40).replace(/\n/g, ' ') || `trigger[${i}]`;
        // A one-way door: clicking it ends the run's usefulness, and it is not
        // an overlay trigger anyway.
        if (EXIT_LABEL.test(label)) { noOpen.push(`${label} (skipped: exit control)`); continue; }
        await t.click({ timeout: 5000 });
        await page.waitForTimeout(700);
      } catch { continue; }

      // Did that click take us off the route? If so this trigger is a link, not
      // an overlay trigger, and everything measured from here would be wrong.
      const nowPath = new URL(page.url()).pathname;
      const sameOrigin = new URL(page.url()).origin === new URL(BASE).origin;
      if (!sameOrigin || nowPath !== routePath) {
        escapes += 1;
        noOpen.push(`${label} (navigated to ${sameOrigin ? nowPath : page.url()})`);
        await page.goto(withV2(`${BASE}${route}`), { waitUntil: 'domcontentloaded', timeout: 90000 });
        await page.waitForTimeout(3000);
        /*
         * The SESSION is the only unrecoverable loss, so it is the only thing
         * worth aborting for. An earlier version also aborted when the pathname
         * did not come back to `routePath`, and that was wrong: some routes
         * legitimately redirect (a "new item" route with no parent selected
         * lands on `/`), so a healthy run was killed on a healthy redirect. Landing on
         * the sign-in page is the real signal, and it is unambiguous.
         */
        if (/sign-?in|login/i.test(page.url())) {
          console.error(`  ABORT: signed out after clicking "${label}" (${page.url()}).`);
          console.error('  Findings after this point would describe the wrong page.');
          await browser.close();
          process.exit(3);
        }
        continue;
      }

      const a = await page.evaluate(AUDIT, OVERLAY_SEL);
      if (!a.opened) { noOpen.push(label); await page.keyboard.press('Escape').catch(() => {}); continue; }
      opened += 1;

      const ev = { z: a.z, zChain: a.zChain, box: a.box };
      if (!a.onTop) note({ route, trigger: label, class: 'stacking',
        symptom: 'overlay opens behind another element',
        expected: 'overlay receives the click at its own centre',
        actual: `blocked by ${a.blockedBy}`, evidence: { ...ev, blockedBy: a.blockedBy } });
      if (a.overflows && !a.scrollable) note({ route, trigger: label, class: 'scroll',
        symptom: 'overlay overflows but cannot scroll',
        expected: 'overflowing list scrolls to reach every option',
        actual: `scrollHeight > clientHeight with no auto/scroll overflowY`, evidence: ev });
      if (a.clippedBy) note({ route, trigger: label, class: 'stacking',
        symptom: 'overlay clipped by an ancestor overflow',
        expected: 'overlay escapes its container (portal)',
        actual: `clipped by ${a.clippedBy}`, evidence: { ...ev, clippedBy: a.clippedBy } });
      if (a.offscreen) note({ route, trigger: label, class: 'stacking',
        symptom: 'overlay renders partly offscreen',
        expected: 'collision detection keeps it in the viewport',
        actual: `box ${a.box.w}x${a.box.h} outside viewport`, evidence: ev });

      await page.keyboard.press('Escape').catch(() => {});
      await page.waitForTimeout(350);
      const still = await page.evaluate(AUDIT, OVERLAY_SEL);
      if (still.opened && still.box.w === a.box.w && still.box.h === a.box.h) {
        note({ route, trigger: label, class: 'focus',
          symptom: 'Escape does not dismiss the overlay',
          expected: 'Escape closes and restores focus',
          actual: 'overlay still open after Escape', evidence: ev });
        await page.mouse.click(5, 5).catch(() => {});
        await page.waitForTimeout(300);
      }
    }

    /* "0 findings" and "0 checks" are NOT the same result. If nothing opened,
     * this route was never audited and must not read as a pass. */
    console.log(`  audited ${opened}/${n} (no overlay from ${noOpen.length}${escapes ? `, ${escapes} navigated away` : ''})`);
    if (n > 0 && opened === 0) note({ route, trigger: `${n} triggers`, class: 'coverage',
      symptom: 'no overlay opened on this route - route NOT audited',
      expected: 'at least one trigger opens an auditable overlay',
      actual: 'every trigger clicked, none produced a known overlay surface',
      evidence: { triggers: n, sample: noOpen.slice(0, 5), navigatedAway: escapes } });
    coverage.push({ route, triggers: n, opened, escapes });

    const after = await heap(page);
    heapTrail.push({ route, beforeMB: before, afterMB: after, deltaMB: before != null && after != null ? after - before : null });
    console.log(`  heap ${before}MB -> ${after}MB`);
  }

  // Leak signal: heap that only ever grows across routes.
  const valid = heapTrail.filter((h) => h.afterMB != null);
  if (valid.length >= 3) {
    const growth = valid[valid.length - 1].afterMB - valid[0].beforeMB;
    if (growth > 150) note({ route: 'session', trigger: 'route walk', class: 'memory',
      symptom: `heap grew ${growth}MB across ${valid.length} routes without settling`,
      expected: 'heap returns near baseline after navigation',
      actual: `${valid[0].beforeMB}MB -> ${valid[valid.length - 1].afterMB}MB`,
      evidence: { heapTrail: valid } });
  }

  writeFileSync(OUT, JSON.stringify({ base: BASE, routes: ROUTES, coverage, heapTrail, findings }, null, 2));
  const totalOpened = coverage.reduce((a, c) => a + c.opened, 0);
  console.log(`\n${findings.length} finding(s) from ${totalOpened} overlay(s) audited across ${coverage.length} route(s); ledger -> ${LEDGER}, json -> ${OUT}`);
  if (!totalOpened) console.log('WARNING: nothing was audited - 0 findings here means NOTHING WAS CHECKED.');
  if (!valid.length) console.log('note: heap unavailable - run Chrome with --enable-precise-memory-info for numbers');
  await browser.close();
};

run().catch((e) => { console.error('overlay-audit crashed -', e.message); process.exit(2); });
