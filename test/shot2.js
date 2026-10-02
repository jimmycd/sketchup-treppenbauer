const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch(); const p = await b.newPage({viewport:{width:1280,height:880}});
  const errs=[]; p.on('pageerror', e=>errs.push(e.message));
  await p.goto('file:///home/claude/tb/test/cnc_test.html'); await p.waitForTimeout(800);
  await p.screenshot({path:'cnc1.png'});
  console.log('errors:', errs); await b.close();
})();
