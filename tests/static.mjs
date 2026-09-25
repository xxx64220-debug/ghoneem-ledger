import {readFileSync,readdirSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import assert from 'node:assert/strict';
for(const f of readdirSync('docs').filter(x=>x.endsWith('.js')))execFileSync(process.execPath,['--check','docs/'+f]);
const config=await import('../docs/config.js');assert.equal(config.URL,'https://lnzirpcsunwajdnwoalc.supabase.co');assert.ok(config.KEY.startsWith('sb_publishable_'));
const html=readFileSync('docs/index.html','utf8');assert.ok(!/(src|href)="\//.test(html),'Assets must support GitHub project subpath');
const app=readFileSync('docs/app.js','utf8');assert.ok(!app.includes('/signin-with-chatgpt'),'No Sites authentication dependency');assert.ok(!app.includes('LEDGER_BRIDGE_KEY'),'No server secret');assert.ok(app.includes('AbortSignal.timeout'),'Loading timeout handled');
console.log('PASS: every JavaScript file parses, config imports, GitHub subpath assets, no Sites login dependency or server secret, timeout handling.');
