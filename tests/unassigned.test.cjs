const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync('docs/app.js','utf8').replace('\nstart();','').replace("import { URL, KEY, OWNER } from './config.js';","const URL='',KEY='',OWNER='test';");
const node={innerHTML:'',textContent:'',style:{},value:'',addEventListener(){}};
const ctx=vm.createContext({Intl,Date,URL:global.URL,Blob,crypto:global.crypto,document:{querySelector:()=>node,addEventListener(){}},navigator:{},setTimeout,window:{},sessionStorage:{getItem:()=>null}});vm.runInContext(source,ctx);const run=s=>vm.runInContext(s,ctx);
run(`D=Object.fromEntries(tables.map(t=>[t,[]]));let save,fields,payload,called;modal=(t,f,fn)=>{fields=f;save=fn};insert=async(t,row)=>{payload=row;D[t].push({...row,id:'entry'})};rpc=async(t,row)=>{called={t,...row}};`);
(async()=>{
 for(const type of ['payment','refund','charge']){
  await run(`action('${type}')`);assert.ok(run('fields').includes('Add name later'));assert.ok(run('fields').indexOf('f_amount')<run('fields').indexOf('f_student_id'));
  await run("save({student_id:'',amount:'125.50',paid_on:'2026-09-27',charged_on:'2026-09-27',note:''})");
  assert.equal(run('payload.student_id'),null);assert.equal(run('payload.amount'),type==='refund'?-125.5:125.5);
 }
 assert.ok(run('unassignedEntries()').includes('Add name'));
 run("D.students=[{id:'student',full_name:'Ali'}]");await run("action('assign-entry',{dataset:{id:'entry',kind:'payment'}})");
 await assert.rejects(run("save({student_id:''})"));await run("save({student_id:'student'})");
 assert.equal(run('called.t'),'assign_entry');assert.equal(run('called.p_entry'),'entry');assert.equal(run('called.p_student'),'student');assert.equal(run('D.payments.length'),2);
 console.log('PASS: amount-only payment/refund/charge with no students, optional name, unassigned list and assignment uses existing entry.');
})().catch(e=>{console.error(e);process.exitCode=1;});
