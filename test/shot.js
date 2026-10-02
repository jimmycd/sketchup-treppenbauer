const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch(); const p = await b.newPage({viewport:{width:1220,height:860}});
  const errs=[]; p.on('pageerror', e=>errs.push(e.message)); p.on('console', m=>{ if(m.type()==='error') errs.push(m.text())});
  await p.goto('file:///home/claude/tb/test/dlg_test.html'); await p.waitForTimeout(500);
  await p.screenshot({path:'dlg1.png'});
  await p.selectOption('#f_variant','spindel'); await p.waitForTimeout(500);
  await p.screenshot({path:'dlg2.png'});
  console.log('errors:', errs);
  await b.close();
})();
