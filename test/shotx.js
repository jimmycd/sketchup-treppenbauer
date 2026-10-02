const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch(); const p = await b.newPage({viewport:{width:1220,height:1000}});
  const errs=[]; p.on('pageerror', e=>errs.push(e.message)); p.on('console', m=>{ if(m.type()==='error') errs.push(m.text())});
  for (const n of process.argv.slice(2)) {
    await p.goto('file:///home/claude/tb/test/dlg_'+n+'.html'); await p.waitForTimeout(600);
    await p.screenshot({path:'out/dlg_'+n+'.png'});
  }
  console.log('errors:', errs);
  await b.close();
})();
