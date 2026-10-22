'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const {webcrypto}=require('node:crypto');
const sources={
  user:fs.readFileSync(path.resolve(__dirname,'../../app/web/withdrawal.js'),'utf8'),
  admin:fs.readFileSync(path.resolve(__dirname,'../../app/web/withdrawal_admin.js'),'utf8'),
};
const orderId='1'.repeat(32), declarationId='2'.repeat(32);
const flush=async()=>{for(let i=0;i<25;i++)await Promise.resolve();await new Promise(setImmediate);};
const deferred=()=>{let resolve,reject;const promise=new Promise((r,e)=>{resolve=r;reject=e;});return{promise,resolve,reject};};
const response=(value,status=200)=>({ok:status<400,status,async json(){return structuredClone(value);}});
const receipt=(overrides={})=>({
  receipt_text:'Künstlicher Eingangsbeleg <img src=x onerror=alert(1)>',
  received_at_iso:'2026-10-22T12:00:00+00:00',refund_executed:false,mail_status:'failed',
  notice:'Erklärung eingegangen; keine Rückzahlung bestätigt.',...overrides,
});
const item=(overrides={})=>({
  id:declarationId,status:'received_unverified',source:'public',mail_status:'failed',
  received_at_iso:'2026-10-22T12:00:00+00:00',receipt_text:'Künstlicher Beleg <script>alert(1)</script>',
  declaration:{buyer_name:'Künstlicher Käufer',contact_email:'synthetic@example.invalid',order_reference:'SYNTHETIC-ORDER'},
  ...overrides,
});
class Element{
  constructor(tag='div'){
    this.tagName=tag.toLowerCase();this.children=[];this.parent=null;this.events={};this.attributes={};
    this._text='';this.value='';this.checked=false;this.disabled=false;this.hidden=false;this.required=false;this.connected=false;
  }
  set textContent(value){this._text=String(value??'');for(const child of this.children)child.parent=null;this.children=[];}
  get textContent(){return this._text+this.children.map(c=>c.textContent).join('');}
  set innerHTML(_){throw Error('Unsafe HTML sink');}
  get isConnected(){return this.connected||Boolean(this.parent?.isConnected);}
  addEventListener(name,handler){this.events[name]=handler;}
  setAttribute(name,value){this.attributes[name]=value;}
  append(...children){for(const child of children){child.parent=this;this.children.push(child);}}
  appendChild(child){this.append(child);return child;}
  replaceChildren(...children){for(const child of this.children)child.parent=null;this.children=[];this._text='';this.append(...children);}
  remove(){if(this.parent){this.parent.children=this.parent.children.filter(c=>c!==this);this.parent=null;}}
  focus(){this.focused=true;}
  descendants(tag){return this.children.flatMap(child=>[...(child.tagName===tag?[child]:[]),...child.descendants(tag)]);}
  reportValidity(){return this.valid!==false&&this.descendants('input').every(i=>!i.required||i.disabled||(i.type==='checkbox'?i.checked:Boolean(i.value)));}
  async trigger(name){if(this.disabled)return;await this.events[name]?.({preventDefault(){},target:this});await flush();}
  click(){return this.trigger('click');}
}
function harness(kind='user',options={}){
  const ids=kind==='admin'?['status-filter','refresh','next','message','declarations']:
    ['buyer-name','contact-email','order-reference','confirm','submit','withdrawal-form','scope','result','receipt','result-notice','mail-status','message','result-heading','download'];
  const nodes=new Map(ids.map(id=>[id,new Element()]));
  const body=new Element('body');body.connected=true;
  for(const node of nodes.values())body.append(node);
  const owner=options.mode==='owner';
  if(kind==='user'){
    const form=nodes.get('withdrawal-form');
    for(const id of ['buyer-name','contact-email','order-reference','confirm','submit']){
      const node=nodes.get(id);node.remove();form.append(node);
      node.tagName=id==='submit'?'button':'input';node.required=id!=='submit';
    }
    nodes.get('buyer-name').value='Künstlicher Käufer';
    nodes.get('contact-email').value='synthetic@example.invalid';
    nodes.get('order-reference').value='SYNTHETIC-ORDER';
    nodes.get('confirm').type='checkbox';nodes.get('confirm').checked=true;
    nodes.get('result').hidden=true;
  }
  const storage=options.storage||new Map(),calls=[],hooks={},timers=new Map(),blobs=[],downloads=[];
  let timerId=0,reloads=0;
  const document={
    documentElement:{dataset:{mode:options.mode||'public',orderId:options.orderId??(owner?orderId:'')}},
    body,getElementById:id=>nodes.get(id),
    createElement(tag){const node=new Element(tag);if(tag==='a')node.click=()=>downloads.push({href:node.href,name:node.download});return node;},
  };
  class LocalURL extends URL{
    static createObjectURL(blob){blobs.push(blob);return 'blob:synthetic-'+blobs.length;}
    static revokeObjectURL(){}
  }
  const context=vm.createContext({
    document,window:{addEventListener:(event,callback)=>{hooks[event]=callback;}},
    location:{reload(){reloads++;}},URL:LocalURL,URLSearchParams,Blob,AbortController,crypto:webcrypto,
    sessionStorage:{getItem:key=>storage.get(key)||null,setItem:(key,value)=>storage.set(key,value),removeItem:key=>storage.delete(key)},
    setTimeout(callback,delay){const id=++timerId;timers.set(id,{callback,delay});return id;},
    clearTimeout:id=>timers.delete(id),
    fetch(url,request){
      calls.push({url,method:request.method||'GET',body:request.body?JSON.parse(request.body):undefined,request});
      const result=Promise.resolve(options.reply?options.reply(url,request,calls.length):
        kind==='admin'?response({items:[item()],next_before:null}):
        request.method==='POST'?response(receipt()):response({withdrawal:null}));
      return new Promise((resolve,reject)=>{
        request.signal?.addEventListener('abort',()=>reject(Error('Aborted')),{once:true});
        result.then(resolve,reject);
      });
    },
  });
  vm.runInContext(sources[kind],context);
  return{
    nodes,calls,hooks,timers,storage,blobs,downloads,body,
    get reloads(){return reloads;},
    async ready(){await flush();},
    async fire(delay){for(const [id,timer]of [...timers])if(timer.delay===delay){timers.delete(id);timer.callback();}await flush();},
    async submit(){await nodes.get('withdrawal-form').trigger('submit');},
    forms(){return nodes.get('declarations').descendants('form');},
  };
}
test('public opening and a fresh reload make no API call and cache only an opaque request key',async()=>{
  const h=harness();await h.ready();assert.equal(h.calls.length,0);assert.equal(h.storage.size,1);
  const key=[...h.storage.values()][0];assert.match(key,/^[A-Za-z0-9_-]{16,60}$/);
  const reloaded=harness('user',{storage:h.storage});await reloaded.ready();
  assert.equal(reloaded.calls.length,0);assert.equal([...h.storage.values()][0],key);
  assert.ok(!JSON.stringify([...h.storage]).includes('synthetic@example.invalid'));
});
test('owner opening reads an existing receipt without resubmission and renders malicious text literally',async()=>{
  const r=receipt();
  const h=harness('user',{mode:'owner',reply:()=>response({withdrawal:r})});await h.ready();
  assert.equal(h.calls.length,1);assert.equal(h.calls[0].method,'GET');
  assert.equal(h.nodes.get('receipt').textContent,r.receipt_text);assert.equal(h.nodes.get('withdrawal-form').hidden,true);
  assert.equal(h.nodes.get('result-heading').focused,true);assert.match(h.nodes.get('mail-status').textContent,/nicht bestätigt/);
});
test('invalid document scope has no submission handler or API operation',async()=>{
  const h=harness('user',{mode:'owner',orderId:'not-a-private-order'});await h.ready();
  assert.equal(h.calls.length,0);assert.equal(h.nodes.get('withdrawal-form').hidden,true);
  assert.equal(h.nodes.get('withdrawal-form').events.submit,undefined);
});
test('explicit public submission freezes fields and a failed retry keeps the exact key and body',async()=>{
  const pending=deferred();let fail=true;
  const h=harness('user',{reply:()=>fail?pending.promise:response(receipt())});await h.ready();
  const first=h.submit();await flush();
  for(const id of ['buyer-name','contact-email','order-reference','confirm','submit'])assert.equal(h.nodes.get(id).disabled,true);
  await h.submit();assert.equal(h.calls.length,1);
  pending.resolve(response({detail:'Synthetisch unklarer Eingang'},503));await first;
  for(const id of ['buyer-name','contact-email','order-reference','confirm','submit'])assert.equal(h.nodes.get(id).disabled,false);
  fail=false;await h.submit();
  assert.equal(h.calls.length,2);assert.deepEqual(h.calls[1].body,h.calls[0].body);
  assert.equal(h.calls[0].request.headers['X-Schulpilot-Request'],'1');
  assert.equal(h.calls[0].request.credentials,'same-origin');
  assert.equal(h.storage.size,0);assert.equal(h.nodes.get('result').hidden,false);
});
test('owner declaration uses the owned URL and cannot retarget a typed reference',async()=>{
  const h=harness('user',{mode:'owner'});await h.ready();
  h.nodes.get('order-reference').value='DIFFERENT-REFERENCE';await h.submit();
  const write=h.calls.find(c=>c.method==='POST');
  assert.equal(write.url,'/api/orders/'+orderId+'/withdrawals');
  assert.equal(Object.hasOwn(write.body,'order_reference'),false);
  assert.equal(h.nodes.get('contact-email').readOnly,true);assert.equal(h.nodes.get('order-reference').readOnly,true);
});
test('unchecked declaration fails native validity and makes no POST',async()=>{
  const h=harness();await h.ready();h.nodes.get('confirm').checked=false;await h.submit();
  assert.equal(h.calls.length,0);
});
test('a hung public POST aborts at twenty seconds and offers an explicit same-key retry only',async()=>{
  const pending=deferred();
  const h=harness('user',{reply:()=>pending.promise});await h.ready();
  const submission=h.submit();await flush();await h.fire(20000);await submission;
  assert.equal(h.calls.length,1);assert.equal(h.calls[0].request.signal.aborted,true);
  assert.equal(h.nodes.get('submit').disabled,false);assert.match(h.nodes.get('message').textContent,/noch nicht sicher bestätigt/);
  assert.equal([...h.storage.values()][0],h.calls[0].body.request_key);
});
test('failed mail still leaves the exact downloadable receipt without a second declaration',async()=>{
  const h=harness();await h.ready();await h.submit();await h.nodes.get('download').click();
  assert.equal(h.downloads.length,1);assert.equal(await h.blobs[0].text(),receipt().receipt_text);
  assert.equal(h.calls.length,1);assert.equal(h.nodes.get('withdrawal-form').hidden,true);
  assert.match(h.nodes.get('mail-status').textContent,/nicht bestätigt/);
});
test('an incomplete or refund-claiming response never becomes a valid receipt',async()=>{
  const h=harness('user',{reply:()=>response(receipt({refund_executed:true}))});await h.ready();await h.submit();
  assert.equal(h.nodes.get('result').hidden,true);assert.equal(h.nodes.get('submit').disabled,false);
  assert.match(h.nodes.get('message').textContent,/unvollständig/);
});
test('public BFCache restores the receipt download without a POST or invented refund',async()=>{
  const h=harness();await h.ready();await h.submit();
  h.hooks.pagehide();await h.nodes.get('download').click();assert.equal(h.downloads.length,0);
  h.hooks.pageshow({persisted:true});await h.nodes.get('download').click();
  assert.equal(h.downloads.length,1);assert.equal(h.calls.length,1);
  assert.equal(await h.blobs[0].text(),receipt().receipt_text);
});
test('public BFCache after an interrupted send preserves key and re-enables its inputs',async()=>{
  const pending=deferred();const h=harness('user',{reply:()=>pending.promise});await h.ready();
  const submission=h.submit();await flush();h.hooks.pagehide();await submission;
  assert.equal(h.calls[0].request.signal.aborted,true);
  h.hooks.pageshow({persisted:true});await flush();
  for(const id of ['buyer-name','contact-email','order-reference','confirm','submit'])assert.equal(h.nodes.get(id).disabled,false);
  assert.equal(h.calls.length,1);assert.equal([...h.storage.values()][0],h.calls[0].body.request_key);
});
test('owner BFCache requests a fresh authenticated document instead of replaying a declaration',async()=>{
  const h=harness('user',{mode:'owner'});await h.ready();h.hooks.pagehide();h.hooks.pageshow({persisted:true});await flush();
  assert.equal(h.reloads,1);assert.ok(h.calls.every(c=>c.method==='GET'));
});
test('admin initial load is bounded GET-only and never turns declaration strings into HTML',async()=>{
  const unsafe='<img src=x onerror=alert(1)>';
  const h=harness('admin',{reply:()=>response({items:[item({receipt_text:unsafe,declaration:{buyer_name:unsafe,contact_email:unsafe,order_reference:unsafe}})],next_before:null})});await h.ready();
  assert.equal(h.calls.length,1);assert.equal(h.calls[0].method,'GET');
  assert.equal(new URL(h.calls[0].url,'https://example.invalid').searchParams.get('limit'),'25');
  assert.ok(h.nodes.get('declarations').textContent.includes(unsafe));assert.equal(h.nodes.get('declarations').descendants('img').length,0);
});
test('late successful old filter responses cannot replace newer admin rows',async()=>{
  const old=deferred();const h=harness('admin',{reply:(_,__,n)=>n===1?old.promise:response({items:[item({declaration:{order_reference:'CURRENT-ROW'}})],next_before:null})});
  h.nodes.get('status-filter').value='received_verified';await h.nodes.get('status-filter').trigger('change');
  old.resolve(response({items:[item({declaration:{order_reference:'OLD-ROW'}})],next_before:null}));await h.ready();
  assert.match(h.nodes.get('declarations').textContent,/CURRENT-ROW/);assert.doesNotMatch(h.nodes.get('declarations').textContent,/OLD-ROW/);
  assert.ok(h.calls.every(c=>c.method==='GET'));
});
test('late failed old filter responses cannot erase a newer successful admin result',async()=>{
  const old=deferred();const h=harness('admin',{reply:(_,__,n)=>n===1?old.promise:response({items:[item({declaration:{order_reference:'CURRENT-ROW'}})],next_before:null})});
  h.nodes.get('status-filter').value='received_verified';await h.nodes.get('status-filter').trigger('change');
  old.resolve(response({detail:'OLD-FAILURE'},503));await h.ready();
  assert.match(h.nodes.get('declarations').textContent,/CURRENT-ROW/);assert.doesNotMatch(h.nodes.get('message').textContent,/OLD-FAILURE/);
});
test('admin linking requires explicit identity confirmation and deduplicates a pending submit',async()=>{
  const pending=deferred();const h=harness('admin',{reply:(url,request)=>request.method==='POST'?pending.promise:response({items:[item()],next_before:null})});await h.ready();
  const form=h.forms()[0],inputs=form.descendants('input'),submit=form.descendants('button')[0];
  await form.trigger('submit');assert.equal(h.calls.filter(c=>c.method==='POST').length,0);
  inputs[1].checked=true;const sending=form.trigger('submit');await flush();
  assert.equal(submit.disabled,true);assert.ok(inputs.every(i=>i.disabled));
  await form.trigger('submit');assert.equal(h.calls.filter(c=>c.method==='POST').length,1);
  const write=h.calls.find(c=>c.method==='POST');assert.equal(write.url,'/api/admin/withdrawals/'+declarationId+'/link');
  assert.deepEqual(write.body,{order_reference:'SYNTHETIC-ORDER',identity_verified:true});
  pending.resolve(response({notice:'Künstlich zugeordnet. Keine Rückzahlung.'}));await sending;
  assert.equal(form.descendants('input').length,0);assert.match(form.textContent,/Keine Rückzahlung/);
});
test('a captured old admin card cannot link after a filter starts or removes its row',async()=>{
  const newer=deferred();const h=harness('admin',{reply:(_,__,n)=>n===1?response({items:[item()],next_before:null}):newer.promise});await h.ready();
  const form=h.forms()[0];form.descendants('input')[1].checked=true;const callback=form.events.submit;
  h.nodes.get('status-filter').value='linked_verified';const load=h.nodes.get('status-filter').trigger('change');await flush();
  await callback({preventDefault(){}});assert.equal(h.calls.filter(c=>c.method==='POST').length,0);
  newer.resolve(response({items:[],next_before:null}));await load;
  assert.equal(form.isConnected,false);await callback({preventDefault(){}});
  assert.equal(h.calls.filter(c=>c.method==='POST').length,0);
});
test('append preserves earlier rows and their explicit link action with an exact read cursor',async()=>{
  const cursor='1792670400:'+declarationId;let reads=0;
  const h=harness('admin',{reply:(url,request)=>{
    if(request.method==='POST')return response({notice:'Erste Karte bewusst zugeordnet.'});
    reads++;return response(reads===1?{items:[item()],next_before:cursor}:{items:[item({id:'3'.repeat(32),declaration:{order_reference:'SECOND-ROW'}})],next_before:null});
  }});await h.ready();
  const first=h.forms()[0];first.descendants('input')[1].checked=true;
  await h.nodes.get('next').click();assert.equal(h.nodes.get('declarations').children.length,2);
  assert.equal(new URL(h.calls[1].url,'https://example.invalid').searchParams.get('before'),cursor);
  await first.trigger('submit');assert.equal(h.calls.filter(c=>c.method==='POST').length,1);
});
test('verified owner records and malformed public IDs never expose an admin link form',async()=>{
  const h=harness('admin',{reply:()=>response({items:[item({source:'owner'}),item({id:'invalid-id'}),item({status:'linked_verified'})],next_before:null})});
  await h.ready();assert.equal(h.forms().length,0);assert.ok(h.calls.every(c=>c.method==='GET'));
});
test('hung admin reads abort and restore an explicit read-only retry',async()=>{
  const pending=deferred();const h=harness('admin',{reply:()=>pending.promise});await h.ready();
  await h.fire(20000);
  assert.equal(h.calls[0].request.signal.aborted,true);assert.equal(h.nodes.get('refresh').disabled,false);
  assert.equal(h.calls.length,1);assert.equal(h.nodes.get('declarations').children.length,0);
});
test('admin page exit aborts pending linking, clears rows and BFCache reauthenticates',async()=>{
  const pending=deferred();const h=harness('admin',{reply:(_,request)=>request.method==='POST'?pending.promise:response({items:[item()],next_before:null})});await h.ready();
  const form=h.forms()[0];form.descendants('input')[1].checked=true;const sending=form.trigger('submit');await flush();
  h.hooks.pagehide();await sending;
  const write=h.calls.find(c=>c.method==='POST');assert.equal(write.request.signal.aborted,true);
  assert.equal(h.nodes.get('declarations').children.length,0);h.hooks.pageshow({persisted:true});assert.equal(h.reloads,1);
  assert.equal(h.calls.filter(c=>c.method==='POST').length,1);
});
