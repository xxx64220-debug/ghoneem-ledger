// This bridge can reach only ledger resources. The caller secret is stored in Sites;
// only its SHA-256 digest is kept here. Project-wide credentials never leave the runtime.
const SECRET_DIGEST='f2475481101302ceec9ff9d47af18a31c9b99233763efbe6a78b96250ebe8335';
const OWNER='2caeaaaa-ae3c-45b9-8868-8b562d344622';
const TABLES=new Set(['students','groups','enrollments','sessions','attendance','packages','charges','payments','expense_categories','expenses','recurring_expenses','settings','student_balances','package_status']);
const INSERTS=new Set(['students','groups','enrollments','sessions','charges','payments','expense_categories','expenses','recurring_expenses','settings']);
const UPDATES=new Set(['students','groups','enrollments','expense_categories','recurring_expenses','settings']);
const RPCS=new Set(['record_attendance','cancel_session','sell_package','generate_monthly_charges','generate_recurring_expenses']);
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function out(message:string,status=400){return Response.json({message},{status,headers:{'Cache-Control':'no-store'}})}
export async function handler(req:Request){
 const supplied=req.headers.get('x-ledger-key')||'';
 const digest=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(supplied)))).map(n=>n.toString(16).padStart(2,'0')).join('');
 let mismatch=0;for(let i=0;i<SECRET_DIGEST.length;i++)mismatch|=SECRET_DIGEST.charCodeAt(i)^digest.charCodeAt(i);
 if(mismatch||digest.length!==SECRET_DIGEST.length){
  const bearer=req.headers.get('authorization')||'';
  if(!bearer.startsWith('Bearer '))return out('Sign in to access the ledger',401);
  const verification=await fetch(Deno.env.get('SUPABASE_URL')+'/auth/v1/user',{headers:{apikey:Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,Authorization:bearer}});
  if(!verification.ok)return out('Your session has expired. Please sign in again.',401);
  const user=await verification.json();
  if(user.id!=='14867e45-bd39-455a-877b-5ce97ce18766')return out('This ledger is restricted to the instructor account.',403);
 }
 const rawPath=req.headers.get('x-ledger-path')||'';
 if(!rawPath.startsWith('/')||rawPath.includes('..')||rawPath.includes('%')||rawPath.includes('\\')||rawPath.includes('#'))return out('Invalid path');
 const target=new URL('https://ledger.invalid'+rawPath),path=target.pathname;
 let method=req.method,body:any=undefined,contentType='application/json',approved=false;
 const table=path.match(/^\/rest\/v1\/gl_([a-z_]+)$/);
 if(table&&TABLES.has(table[1])){
  const t=table[1];
  for(const [key,value] of target.searchParams){if(!['select','offset','limit','id'].includes(key))return out('Invalid query');if(key==='select'&&value!=='*')return out('Invalid select');if(['offset','limit'].includes(key)&&(!/^\d+$/.test(value)||Number(value)>1000000))return out('Invalid range');if(key==='id'&&(!value.startsWith('eq.')||!UUID.test(value.slice(3))))return out('Invalid ID');}
  if(method==='GET'){target.searchParams.set('limit',String(Math.min(1000,Number(target.searchParams.get('limit')||1000))));approved=true;}
  if((method==='POST'&&INSERTS.has(t))||(method==='PATCH'&&UPDATES.has(t)&&target.searchParams.has('id'))){
   body=await req.json();const rows=Array.isArray(body)?body:[body];if(rows.length>200||rows.some(r=>!r||typeof r!=='object'||Array.isArray(r)||'owner_id'in r||'id'in r))return out('Invalid rows');
   if(method==='POST'&&target.search)return out('Unexpected write query');
   if(t==='charges'&&rows.some(r=>!['adjustment','opening_balance'].includes(r.reason)||!String(r.note||'').trim()||r.attendance_id||r.package_id||r.enrollment_id))return out('Only manual adjustments are accepted here');
   if(t==='expenses'&&rows.some(r=>r.receipt_path&&!new RegExp('^'+OWNER+'/[0-9a-f-]+\\.(jpg|png|webp)$').test(r.receipt_path)))return out('Invalid receipt path');
   if(method==='POST')for(const row of rows)row.owner_id=OWNER;
   approved=true;
  }
 }
 const rpc=path.match(/^\/rest\/v1\/rpc\/gl_([a-z_]+)$/);
 if(rpc&&RPCS.has(rpc[1])&&method==='POST'&&!target.search){body=await req.json();approved=true;}
 const object=path.match(new RegExp('^/storage/v1/object/(sign/)?ghoneem-ledger-receipts/('+OWNER+'/[0-9a-f-]+\\.(jpg|png|webp))$'));
 if(object&&method==='POST'&&!target.search){
  if(object[1])body={expiresIn:120};
  else {contentType=req.headers.get('content-type')||'';if(!['image/jpeg','image/png','image/webp'].includes(contentType))return out('Unsupported photo');const data=await req.arrayBuffer();if(data.byteLength>5242880)return out('Photo too large',413);body=data;}
  approved=true;
 }
 if(path==='/storage/v1/object/ghoneem-ledger-receipts'&&method==='DELETE'){
  body=await req.json();if(!Array.isArray(body.prefixes)||body.prefixes.length>10||body.prefixes.some((p:string)=>!new RegExp('^'+OWNER+'/[0-9a-f-]+\\.(jpg|png|webp)$').test(p)))return out('Invalid receipt cleanup');approved=true;
 }
 if(!approved)return out('Ledger route not allowed',403);
 const base=Deno.env.get('SUPABASE_URL')!,key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
 const response=await fetch(base+target.pathname+target.search,{method,headers:{apikey:key,Authorization:'Bearer '+key,'Content-Type':contentType,Prefer:'return=representation'},body:body===undefined?undefined:body instanceof ArrayBuffer?body:JSON.stringify(body)});
 return new Response(response.body,{status:response.status,headers:{'Content-Type':response.headers.get('content-type')||'application/json','Cache-Control':'no-store'}});
}
const ALLOWED_ORIGINS=new Set(['https://xxx64220-debug.github.io']);
Deno.serve(async req=>{
 const origin=req.headers.get('origin');
 if(origin&&!ALLOWED_ORIGINS.has(origin))return out('Origin not allowed',403);
 const headers:Record<string,string>={'Cache-Control':'no-store','Vary':'Origin'};
 if(origin){headers['Access-Control-Allow-Origin']=origin;headers['Access-Control-Allow-Headers']='authorization, apikey, x-ledger-path, content-type, prefer, x-client-info';headers['Access-Control-Allow-Methods']='GET, POST, PATCH, DELETE, OPTIONS';}
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 let response;try{response=await handler(req)}catch{response=out('Unable to complete ledger request',500)}
 for(const [key,value] of Object.entries(headers))response.headers.set(key,value);
 return response;
});
