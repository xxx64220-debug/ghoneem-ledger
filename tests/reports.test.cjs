const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const src=fs.readFileSync(__dirname+'/../docs/app.js','utf8').replace('\nstart();','').replace("import { URL, KEY, OWNER } from './config.js';","const URL='',KEY='',OWNER='test';");
const node={innerHTML:'',textContent:'',style:{},value:'2026-09',addEventListener(){},focus(){},setSelectionRange(){}};
const context=vm.createContext({console,Intl,Date,URL:global.URL,Blob,crypto:global.crypto,document:{querySelector:()=>node,addEventListener(){}},navigator:{},setTimeout,window:{},sessionStorage:{getItem:()=>null}});
vm.runInContext(src,context);
vm.runInContext(`
D=Object.fromEntries(tables.map(t=>[t,[]]));
D.students=[{id:'s',full_name:'علي <script>bad</script>',track:'SAT',status:'active'}];
D.groups=[{id:'g',name:'SAT Saturday',track:'SAT',default_price:200,active:true}];
D.enrollments=[{id:'e',student_id:'s',group_id:'g',billing_model:'package',price:1600,active:true}];
D.package_status=[{enrollment_id:'e',student_id:'s',sessions_remaining:-2}];
D.student_balances=[{student_id:'s',balance:-400}];
D.payments=[{student_id:'s',amount:1600,paid_on:'2026-09-02',method:'cash'},{student_id:'s',amount:-100,paid_on:'2026-09-03',method:'cash'}];
D.charges=[{student_id:'s',enrollment_id:'e',amount:1900,charged_on:'2026-09-01',reason:'package'}];
D.expense_categories=[{id:'c1',name:'Rent',scope:'business'},{id:'c2',name:'Food',scope:'personal'}];
D.expenses=[{category_id:'c1',amount:300,scope:'business',spent_on:'2026-09-02',method:'cash'},{category_id:'c2',amount:500,scope:'personal',spent_on:'2026-09-03',method:'cash'}];
D.sessions=[{id:'se',held_on:'2026-09-25',starts_at:'17:00',topic:'Quadratics',group_id:'g',status:'held',duration_min:90}];
month='2026-09';selected='s';
`,context);
const run=s=>vm.runInContext(s,context);
assert.equal(run("metrics('2026-09').collected"),1500,'Refunds reduce collections');
assert.equal(run("metrics('2026-09').collected-metrics('2026-09').business"),1200,'Personal spending excluded from business net');
assert.equal(run("metrics('2026-09').expected"),1900);
assert.equal(run("metrics('2026-08').collected"),0);
assert.equal(run("credits('s')"),-2);
assert.equal(run("bal('s')"),-400);
assert.equal(run('reportMonths().length'),12);
assert.ok(run("statement(D.students[0],'2026-09-02','2026-09-30')").includes('Opening balance: -1,900'));
assert.ok(run("statement(D.students[0],'2026-09-02','2026-09-30')").includes('Amount owed: 400'));
for(const fn of ['home','studentList','studentPage','groups','sessionsPage','expensesPage','reports','settings']){let html=run(fn+'()');assert.ok(html.length>100,fn+' renders');assert.ok(!html.includes('<script>bad</script>'),'Escapes user text in '+fn)}
run("selected='g'");assert.ok(run('groupPage()').includes('SAT Saturday'));
assert.ok(run("statement(D.students[0],'2026-10-01','2026-09-01')").includes('valid date range'));
console.log('PASS: report totals, refunds, separate spending, negative credits, date-range statements, Arabic/injection escaping and all main renderers.');
assert.equal(run("positiveAmount('0.10')"),0.1);
for(const amount of ['0','-1','1.234','Infinity','1e3',''])assert.throws(()=>run(`positiveAmount(${JSON.stringify(amount)})`));
run(`D.payments=[{id:'p1',student_id:'s',amount:1000,paid_on:'2026-09-01',method:'cash'},{id:'p2',student_id:'s',amount:400,paid_on:'2026-09-05',method:'cash'},{id:'p3',student_id:'s',amount:-100,paid_on:'2026-09-06',method:'cash'}];D.charges=[{id:'c1',student_id:'s',amount:600,charged_on:'2026-09-02',reason:'adjustment',note:'Lesson'},{id:'c2',student_id:'s',amount:700,charged_on:'2026-09-03',reason:'adjustment',note:'Lessons'}];`);
assert.deepEqual(JSON.parse(run("JSON.stringify(studentHistory('s').map(r=>r.balance))")),[1000,400,-300,100,0],'Advance consumed, debt carried forward, later payment and refund');
assert.equal(run("metrics('2026-09').collected"),1300,'Charges do not count as collected money');
assert.ok(run('quickMoney()').includes('Recorded money left'));
assert.ok(run("studentTransactions('s')").includes('Settled'));
// Exercise the actual save handlers without touching real financial records.
run(`let captured,writes=[];modal=(title,fields,save)=>{captured={title,fields,save}};insert=async(table,row)=>writes.push({table,row});`);
(async()=>{
 for(const [kind,expectedTable,expectedAmount] of [['payment','payments',250],['refund','payments',-250],['charge','charges',250]]){
  await run(`action('${kind}',{dataset:{id:'s'}})`);
  await run(`captured.save({student_id:'s',amount:'250',note:'Test',paid_on:'2026-09-26'})`);
  assert.equal(run('writes.at(-1).table'),expectedTable);assert.equal(run('writes.at(-1).row.amount'),expectedAmount);
 }
 assert.equal(run('writes.at(-1).row.reason'),'adjustment');
 console.log('PASS: advance → lesson → debt → partial/later payment → refund; positive input validation; actual payment/refund/charge save handlers.');
})().catch(e=>{console.error(e);process.exitCode=1;});
