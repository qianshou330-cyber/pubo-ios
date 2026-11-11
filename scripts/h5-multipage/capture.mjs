import { chromium } from 'playwright';
import { spawn } from 'node:child_process';
import { mkdir, readFile, writeFile, rm } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const dir = dirname(fileURLToPath(import.meta.url));
const out = resolve(process.env.OUTPUT_DIR || `${dir}/artifacts`);
await mkdir(out, { recursive: true });
const pages = [
  { name: 'channels', path: '/channels' },
  { name: 'drive', path: '/my/drive' },
  { name: 'profile', path: '/settings/profile' },
  { name: 'privacy', path: '/settings/privacy' },
];
// Clear only known outputs so an unsuccessful attempt cannot leave an older success image.
for (const name of [...pages.flatMap(p => [`h5-${p.name}-large-light.png`, `DIAGNOSTIC-NOT-PARITY-${p.name}.png`]), 'report.json', 'server.log', 'fixture-requests.log', ...pages.map(p => `DIAGNOSTIC-DOM-${p.name}.json`)]) await rm(`${out}/${name}`, { force: true });
const port = process.env.PORT || '8767';
if (!/^\d+$/.test(port) || Number(port) < 1024 || Number(port) > 65535) throw Error('Invalid fixture port');
const origin = `http://127.0.0.1:${port}`;
const fixturePath = process.env.FIXTURE_PATH || resolve(dir, '../../App/Resources/TimelineParity.json');
const server = spawn('python3', [`${dir}/server.py`], { cwd: dir, env: { ...process.env, PORT: port, FIXTURE_PATH: fixturePath }, stdio: ['ignore', 'pipe', 'pipe'] });
let log = '';
server.stderr.on('data', x => log += x); server.stdout.on('data', x => log += x);
let serverError; server.on('error', e => serverError = e);
const report = { startedAt: new Date().toISOString(), reference: 'Real public H5 bundles, local synthetic APIs only. No production API, account or credential.', cases: [], success: false };
let browser;
const pause = ms => new Promise(r => setTimeout(r, ms));
const clean = c => {
  if (c.errors.length || c.consoleErrors.length || c.failedResponses.length || c.blocked.length) throw Error('Invalid page evidence: runtime/network/fixture error');
};
async function requireVisible(locator) { await locator.waitFor({ state: 'visible', timeout: 15000 }); }
async function provePage(page, c) {
  if (new URL(page.url()).pathname !== c.path) throw Error('Unexpected route or login redirect');
  if (c.bundles < 2) throw Error('Actual H5 bundle evidence missing');
  const apis = new Set(c.responses.filter(r => r.status < 400).map(r => r.path));
  if (c.name === 'channels') {
    if (!apis.has('/api/channels/featured')) throw Error('Featured channel API was not observed');
    await requireVisible(page.getByText('音乐交流（测试频道）', { exact: true }));
    // Source contract: channels.vue headerTabs uses search/comet/star/eye/edit icons;
    // MkPageHeader.tabs.vue renders five sibling buttons. Scope by that structure,
    // not accessible name (which may include tooltip content), CSS hashes or index.
    const tabRows = page.locator('div').filter({ has: page.locator(':scope > button i.ti-comet') })
      .filter({ has: page.locator(':scope > button i.ti-star') })
      .filter({ has: page.locator(':scope > button i.ti-eye') })
      .filter({ has: page.locator(':scope > button i.ti-edit') });
    if (await tabRows.count() !== 1) throw Error(`Channel header structure count=${await tabRows.count()}`);
    const searchTab = tabRows.locator(':scope > button').filter({ has: page.locator('i.ti-search') })
      .filter({ hasText: /^\s*搜索\s*$/ });
    if (await searchTab.count() !== 1) throw Error(`Channel search tab count=${await searchTab.count()}`);
    await requireVisible(searchTab);
    await searchTab.click();
    const input = page.locator('input[type="search"]');
    await requireVisible(input);
    await requireVisible(page.getByText('名称与描述', { exact: true }));
    await requireVisible(page.getByText('仅名称', { exact: true }));
    await input.fill('音乐');
    const response = page.waitForResponse(r => new URL(r.url()).pathname === '/api/channels/search' && r.request().method() === 'POST' && r.ok());
    await input.press('Enter'); await response;
    await requireVisible(page.getByText('音乐交流（测试频道）', { exact: true }));
    if (await input.inputValue() !== '音乐') throw Error('Channel query not retained');
    c.proofs = ['featured API loaded', 'search tab opened', 'two search modes visible', 'search API success', 'synthetic result visible'];
  } else if (c.name === 'drive') {
    // A sidebar label "Drive" alone is insufficient: require actual file/folder calls and empty-state body.
    if (!apis.has('/api/drive/files') || !apis.has('/api/drive/folders')) throw Error('Drive file/folder APIs were not both observed');
    await requireVisible(page.getByText('网盘中无文件', { exact: true }));
    c.proofs = ['drive/files loaded', 'drive/folders loaded', 'empty Drive body visible'];
  } else if (c.name === 'profile') {
    await requireVisible(page.getByRole('button', { name: '更换头像', exact: true }));
    const birthday = page.locator('input[type="date"]');
    if (await birthday.count() !== 1) throw Error('Profile birthday field missing/ambiguous');
    if (await birthday.inputValue() !== '2000-02-29') throw Error('Synthetic birthday missing');
    if (await page.locator('input').evaluateAll(ns => ns.filter(n => n.value === 'Tokyo (synthetic)').length) !== 1) throw Error('Synthetic profile location missing');
    if (await page.locator('textarea').count() < 1) throw Error('Profile description field missing');
    // Scroll genuine document to new fields, without modifying CSS/DOM or changing values (autosave avoided).
    await birthday.scrollIntoViewIfNeeded(); await requireVisible(birthday);
    c.proofs = ['change-avatar control', 'real profile textarea', 'synthetic location value', 'synthetic date field visible'];
  } else if (c.name === 'privacy') {
    const approval = page.getByText('关注请求需要批准', { exact: true });
    const auto = page.getByText('自动允许我关注的人的关注请求', { exact: true });
    await approval.scrollIntoViewIfNeeded(); await requireVisible(approval); await requireVisible(auto);
    // Read-only proof: labels must live with actual checkbox controls, not in the settings navigation.
    for (const label of [approval, auto]) {
      const section = label.locator('xpath=ancestor::div[.//input[@type="checkbox"]][1]');
      if (await section.locator('input[type="checkbox"]').count() !== 1) throw Error('Privacy label is not paired to an actual switch');
    }
    c.proofs = ['manual-approval label and checkbox', 'auto-accept label and checkbox'];
  }
  c.theme = await page.locator('html').getAttribute('data-color-scheme');
  if (c.theme !== 'light') throw Error('Unexpected H5 theme');
  clean(c);
}
try {
  let ready = false;
  for (let i = 0; i < 45; i++) {
    if (serverError) throw serverError;
    if (server.exitCode !== null) throw Error(`Fixture server exited ${server.exitCode}`);
    try { const r = await fetch(origin + '/__health', { signal: AbortSignal.timeout(1000) }); if (r.ok) { ready = true; break; } } catch {}
    await pause(1000);
  }
  if (!ready) throw Error('Fixture readiness timed out');
  browser = await chromium.launch({ headless: true, ...(process.env.CHROMIUM_PATH ? { executablePath: process.env.CHROMIUM_PATH } : {}) });
  for (const spec of pages) {
    const c = { ...spec, errors: [], consoleErrors: [], blocked: [], failedResponses: [], responses: [], bundles: 0, passed: false };
    report.cases.push(c);
    const ctx = await browser.newContext({ viewport: { width: 430, height: 932 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true, locale: 'zh-CN', timezoneId: 'UTC', colorScheme: 'light', serviceWorkers: 'block' });
    await ctx.route('**/*', async r => {
      const u = new URL(r.request().url());
      if (u.origin === origin) return r.continue();
      c.blocked.push({ url: u.origin + u.pathname, method: r.request().method() }); await r.abort('blockedbyclient');
    });
    const page = await ctx.newPage();
    // MkUserSetupDialog.vue may appear after the initial readiness delay. Handle
    // it at actionability checks, using its real Later -> specific confirmation
    // flow. Never remove overlays, mutate DOM/CSS, or force the blocked action.
    const setupDialog = page.getByTestId('user-setup-dialog');
    c.onboardingDismissals = [];
    const dismissSetup = async () => {
      if (await setupDialog.count() !== 1) throw Error('Ambiguous initial setup dialog');
      const later = setupDialog.getByRole('button', { name: '一会再说', exact: true });
      await later.click({ timeout: 15000 });
      const question = page.getByText('要稍后再进行初始设定吗？', { exact: true });
      await requireVisible(question);
      // MkDialog.vue puts text and modal-dialog-ok under the same root.
      const confirmation = question.locator('xpath=ancestor::div[.//*[@data-testid="modal-dialog-ok"]][1]');
      const ok = confirmation.getByTestId('modal-dialog-ok');
      if (await ok.count() !== 1) throw Error('Ambiguous postpone-setup confirmation');
      await ok.click({ timeout: 15000 });
      await setupDialog.waitFor({ state: 'hidden', timeout: 15000 });
      await question.waitFor({ state: 'hidden', timeout: 15000 });
      c.onboardingDismissals.push({ at: new Date().toISOString(), action: 'Later and specific postpone confirmation clicked' });
    };
    await page.addLocatorHandler(setupDialog, dismissSetup, { times: 2 });
    const dismissVisibleSetup = async () => {
      if (!(await setupDialog.isVisible())) return;
      // Outside the handler, suspend it so Later's own click cannot re-enter it.
      await page.removeLocatorHandler(setupDialog);
      try { await dismissSetup(); }
      finally { await page.addLocatorHandler(setupDialog, dismissSetup, { times: 2 }); }
    };
    page.on('pageerror', e => c.errors.push(e.message));
    page.on('console', m => { if (m.type() === 'error') c.consoleErrors.push(m.text()); });
    page.on('response', r => {
      const u = new URL(r.url());
      if (u.pathname.startsWith('/api/')) c.responses.push({ path: u.pathname, status: r.status(), method: r.request().method() });
      if (r.status() >= 400) c.failedResponses.push({ path: u.pathname, status: r.status() });
      if (r.ok() && u.pathname.endsWith('.js')) c.bundles++;
    });
    try {
      await page.goto(origin + c.path, { waitUntil: 'domcontentloaded', timeout: 60000 });
      await page.waitForTimeout(12000); await page.evaluate(() => document.fonts.ready);
      await dismissVisibleSetup();
      clean(c); await provePage(page, c); await page.waitForTimeout(500); clean(c);
      // Screenshot itself does not run actionability handlers. Dismiss only the
      // known setup flow if it became visible after the last interaction.
      await dismissVisibleSetup();
      if (await setupDialog.isVisible()) throw Error('Initial setup still covers page');
      clean(c);
      await page.screenshot({ path: `${out}/h5-${c.name}-large-light.png` });
      c.passed = true; c.capturedAt = new Date().toISOString();
    } catch (e) {
      c.failure = String(e);
      await page.screenshot({ path: `${out}/DIAGNOSTIC-NOT-PARITY-${c.name}.png` }).catch(() => {});
      c.bodyText = await page.locator('body').innerText().catch(() => 'unavailable');
      // Synthetic page only. Record structure, not input values or request bodies.
      const diagnostic = await page.locator('button, [role=tab], input[type=search]').evaluateAll(nodes =>
        nodes.slice(0, 120).map(n => ({ tag: n.tagName, role: n.getAttribute('role'),
          text: (n.textContent || '').trim().slice(0, 180), ariaLabel: n.getAttribute('aria-label'),
          visible: !!(n.getClientRects().length && getComputedStyle(n).visibility !== 'hidden'),
          icons: [...n.querySelectorAll('i')].map(i => i.className),
          parentTag: n.parentElement?.tagName, siblingButtons: n.parentElement?.querySelectorAll(':scope > button').length
        }))).catch(() => []);
      await writeFile(`${out}/DIAGNOSTIC-DOM-${c.name}.json`, JSON.stringify(diagnostic, null, 2));
    } finally { await ctx.close(); }
  }
  report.success = report.cases.length === pages.length && report.cases.every(c => c.passed);
} catch (e) { report.failure = String(e); }
finally {
  try { report.provenance = await (await fetch(origin + '/__health', { signal: AbortSignal.timeout(2000) })).json(); } catch {}
  await browser?.close().catch(() => {}); server.kill('SIGTERM');
  report.finishedAt = new Date().toISOString();
  await writeFile(`${out}/report.json`, JSON.stringify(report, null, 2));
  await writeFile(`${out}/server.log`, log);
  await writeFile(`${out}/fixture-requests.log`, await readFile(`${dir}/requests.log`).catch(() => ''));
}
console.log(JSON.stringify({ success: report.success, cases: report.cases.map(c => ({ name: c.name, passed: c.passed, failure: c.failure, proofs: c.proofs })), failure: report.failure }));
process.exitCode = report.success ? 0 : 1;
