// Verify the blog renders through a real Freenet node, in light and dark mode:
// index lists posts, clicking a post loads it in the sandboxed iframe, the
// chart (if any) draws and shows a hover tooltip, no page errors, no
// horizontal scroll at phone width. Screenshots go to $OUT.
//
// Usage (Playwright from the playwright skill):
//   cd ~/.claude/skills/playwright-skill && \
//   BLOG_URL=http://127.0.0.1:7509/v1/contract/web/<key>/ node run.js ~/code/freenet/blog/scripts/verify-render.js
const { chromium } = require('playwright');
const BLOG_URL = process.env.BLOG_URL;
const OUT = process.env.OUT || require('os').tmpdir();
if (!BLOG_URL) { console.error('set BLOG_URL'); process.exit(2); }

(async () => {
  const browser = await chromium.launch({ headless: true });
  const failures = [];
  const check = (ok, msg) => { console.log((ok ? 'PASS ' : 'FAIL ') + msg); if (!ok) failures.push(msg); };
  for (const scheme of ['light', 'dark']) {
    const ctx = await browser.newContext({ colorScheme: scheme, viewport: { width: 1100, height: 900 } });
    const page = await ctx.newPage();
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    await page.goto(BLOG_URL, { waitUntil: 'networkidle' });
    // Web-container apps render inside a sandboxed iframe; find the content frame.
    const findFrame = () => page.frames().find(f => f.url().includes('__sandbox=1'));
    await page.waitForFunction(() => document.querySelector('iframe'), null, { timeout: 30000 });
    let frame;
    for (let i = 0; i < 60 && !(frame = findFrame()); i++) await page.waitForTimeout(500);
    check(!!frame, `[${scheme}] content iframe present`);
    if (!frame) continue;
    await frame.waitForSelector('.post-list a', { timeout: 30000 });
    const link = frame.locator('.post-list a').first();
    const title = (await link.textContent()).trim();
    check(title.length > 0, `[${scheme}] index lists a post: "${title}"`);
    await page.screenshot({ path: `${OUT}/index-${scheme}.png` });
    await link.click();
    // Navigation moves the iframe; wait for the post page inside it.
    let post;
    for (let i = 0; i < 60; i++) {
      post = page.frames().find(f => f.url().includes('/posts/') && f.url().includes('__sandbox=1'));
      if (post && await post.locator('article h1').count()) break;
      await page.waitForTimeout(500);
    }
    check(!!post, `[${scheme}] clicking the post link loaded the post in the iframe`);
    if (!post) continue;
    console.log('  iframe url: ' + post.url());
    console.log('  shell url:  ' + page.url());
    const h1 = (await post.locator('article h1').textContent()).trim();
    check(h1 === title, `[${scheme}] post h1 matches index link`);
    const svg = post.locator('.viz-root svg[role=img]');
    if (await svg.count()) {
      const marks = await post.locator('.viz-root .viz-plot svg circle, .viz-root .viz-plot svg rect').count();
      check(marks >= 8, `[${scheme}] chart drew ${marks} marks`);
      await svg.scrollIntoViewIfNeeded();
      const box = await svg.boundingBox();
      await page.mouse.move(box.x + box.width * 0.04, box.y + box.height * 0.5);
      await page.mouse.move(box.x + box.width * 0.05, box.y + box.height * 0.5);
      await page.waitForTimeout(300);
      const tip = post.locator('.viz-root .viz-tip');
      const op = await tip.evaluate(e => getComputedStyle(e).opacity);
      const txt = (await tip.textContent()).trim();
      check(op === '1' && /\d/.test(txt), `[${scheme}] hover tooltip shows: "${txt.slice(0, 90)}"`);
      await page.screenshot({ path: `${OUT}/post-hover-${scheme}.png` });
      await post.locator('.viz-tabs button[data-view=table]').click();
      const rows = await post.locator('.viz-root tbody tr').count();
      check(rows >= 8, `[${scheme}] table view has ${rows} rows`);
      await post.locator('.viz-tabs button[data-view=chart]').click();
      const bg = await post.evaluate(() => getComputedStyle(document.body).backgroundColor);
      console.log(`  body background (${scheme}): ${bg}`);
    }
    await post.locator('article').screenshot({ path: `${OUT}/post-${scheme}.png` });
    check(errors.length === 0, `[${scheme}] no page errors ${errors.join('; ')}`);
    // Mobile width: no horizontal overflow.
    await page.setViewportSize({ width: 390, height: 844 });
    await page.waitForTimeout(500);
    const overflow = await post.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    check(overflow <= 0, `[${scheme}] no horizontal scroll at 390px (overflow ${overflow})`);
    await page.screenshot({ path: `${OUT}/post-mobile-${scheme}.png`, fullPage: false });
    await ctx.close();
  }
  await browser.close();
  console.log(failures.length ? `\n${failures.length} FAILED` : '\nALL PASSED');
  process.exit(failures.length ? 1 : 0);
})();
