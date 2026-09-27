const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync('docs/app.js','utf8').replace('\nstart();','').replace("import { URL, KEY, OWNER } from './config.js';","const URL='',KEY='',OWNER='test';");
const node={innerHTML:'',textContent:'',style:{},value:'',addEventListener(){}};
const ctx=vm.createContext({Intl,Date,URL:global.URL,Blob,crypto:global.crypto,document:{querySelector:()=>node,addEventListener(){}},navigator:{},setTimeout,window:{},sessionStorage:{getItem:()=>null}});vm.runInContext(source,ctx);const run=s=>vm.runInContext(s,ctx);
run(`D=Object.fromEntries(tables.map(t=>[t,[]]));D.students=[{id:'s',full_name:'Ali',teaching_place:'Centre <script>',status:'active',session_rate:250,session_counter_used:0}];D.payments=[{student_id:'s',amount:1000}];let writes=0,payload,save;render=()=>{};toast=()=>{};load=()=>{throw Error('Unnecessary full reload')};update=async(t,id,row)=>{writes++;payload=row;return [{...D.students[0],...row}]};modal=(title,fields,fn)=>{save=fn};insert=async(t,row)=>{payload=row};`);
(async()=>{
 assert.ok(run('studentList()').includes('data-action="session-count-up"'));
 assert.ok(!run('studentList()').includes('Centre <script>'));
 run("search='centre'");assert.ok(run('studentList()').includes('Ali'));
 run("search='missing'");assert.ok(run('studentList()').includes('No matching students'));
 await run("action('session-count-down',{dataset:{id:'s'}})");assert.equal(run('writes'),0);
 await run("Promise.all([action('session-count-up',{dataset:{id:'s'}}),action('session-count-up',{dataset:{id:'s'}})])");assert.equal(run('writes'),1);assert.equal(run('D.students[0].session_counter_used'),1);
 await run("action('session-count-down',{dataset:{id:'s'}})");assert.equal(run('D.students[0].session_counter_used'),0);
 run("update=async()=>{throw Error('Network unavailable')}");await assert.rejects(run("action('session-count-up',{dataset:{id:'s'}})"));assert.equal(run('D.students[0].session_counter_used'),0);assert.equal(run('busy'),false);
 await run("action('add-student')");await run("save({full_name:' Sara ',teaching_place:' Online ',session_rate:'200'})");assert.equal(run('payload.full_name'),'Sara');assert.equal(run('payload.teaching_place'),'Online');assert.equal(run('payload.session_rate'),200);
 console.log('PASS: list search/escaping, inline increment/decrement, zero limit, rapid-tap protection, failed-save safety and quick-add payload.');
})().catch(e=>{console.error(e);process.exitCode=1;});
