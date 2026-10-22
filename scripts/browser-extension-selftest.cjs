const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const { aggregate, tasks } = require('../BrowserExtension/progress.js');
const active = (received, total, extra = {}) => ({ id: 1, filename: '/test/report.zip', state: 'in_progress', endTime:new Date().toISOString(), paused: false, bytesReceived: received, totalBytes: total, ...extra });
assert.deepEqual(aggregate([active(20,100),active(80,300)]), {receivedBytes:100,totalBytes:400,activeCount:2,unknownCount:0,pausedCount:0});
assert.equal(aggregate([active(50,100,{paused:true}),active(20,100,{state:'complete'})]).activeCount,0);
assert.equal(aggregate([active(50,-1)]).unknownCount,1);
assert.equal(aggregate([active(300,200)]).receivedBytes,200);
assert.equal(aggregate([active(NaN,200)]).unknownCount,1);
assert.equal(aggregate([active(0,Number.MAX_SAFE_INTEGER),active(0,2)]).unknownCount,1);
assert(!JSON.stringify(aggregate([active(50,100,{filename:'PRIVATE',url:'https://private.example',id:123})])).includes('PRIVATE'));
assert.equal(tasks([active(50,100,{filename:'/private/customer/report.zip'})])[0].filename,'report.zip');
assert.equal(tasks([active(50,100,{filename:'C:\\Users\\private\\report.zip'})])[0].filename,'report.zip');
assert.equal(tasks([active(5,-1)])[0].totalBytes,0);
assert.equal(tasks([active(100,100,{state:'complete'})])[0].complete,true);
assert.equal(tasks([active(100,100,{state:'complete',exists:false})]).length,0);
assert.equal(tasks([active(100,100,{state:'complete'})])[0].localPath,'/test/report.zip');
assert.equal(tasks([active(100,100,{state:'interrupted'})]).length,0);
assert.equal(tasks([active(25,100,{id:1,filename:'/a/same.zip'}),active(75,100,{id:2,filename:'/b/same.zip'})]).length,2);
assert(!JSON.stringify(tasks([active(25,100,{filename:'/private/report.zip',url:'https://private.example'})])).includes('/private'));
const boundary=Date.now();
assert.equal(tasks([active(100,100,{state:'complete',endTime:new Date(boundary-1799000).toISOString()})],boundary).length,1);
assert.equal(tasks([active(100,100,{state:'complete',endTime:new Date(boundary-1800000).toISOString()})],boundary).length,0);
assert.equal(tasks([active(100,100,{state:'complete',endTime:undefined})],boundary).length,0);
const extensionPath=path.join(__dirname,'../BrowserExtension');
function event() { return {listeners:[],addListener(fn){this.listeners.push(fn)},emit(...args){this.listeners.forEach(fn=>fn(...args))}}; }
async function worker(isEdge) {
 let now=Date.now(), next=1, timers=new Map(), items=[], messages=[], ports=[], badge='';
 let saved={profileId:'11111111-1111-4111-8111-111111111111'};
 const clockDate=class extends Date { static now(){return now} };
 const chrome={downloads:{search:async query=>structuredClone(items.filter(i=>i.state===query.state)),onCreated:event(),onChanged:event(),onErased:event()},
 storage:{local:{get:async()=>structuredClone(saved),set:async value=>{Object.assign(saved,structuredClone(value))}}},
 action:{setBadgeText:async x=>{badge=x.text},setBadgeBackgroundColor:async()=>{}},
 alarms:{onAlarm:event(),create(){}},runtime:{id:'test-extension',onInstalled:event(),onStartup:event(),onMessage:event(),lastError:undefined}};
 chrome.runtime.connectNative=host=>{
  assert.equal(host,'com.taskdock.browser_progress');
  const port={onMessage:event(),onDisconnect:event(),closed:false,postMessage(m){assert(!this.closed);messages.push(structuredClone(m));queueMicrotask(()=>this.onMessage.emit({ok:true,version:1}));},disconnect(){this.closed=true;this.onDisconnect.emit();}};
  ports.push(port);return port;
 };
 const context=vm.createContext({chrome,navigator:{userAgent:isEdge?'Chrome/141 Edg/141':'Chrome/141'},crypto:{randomUUID:()=> '11111111-1111-4111-8111-111111111111'},Date:clockDate,console,
 setTimeout(fn,delay){const id=next++;timers.set(id,{at:now+delay,fn});return id},clearTimeout(id){timers.delete(id)}});
 context.importScripts=file=>vm.runInContext(fs.readFileSync(path.join(extensionPath,file),'utf8'),context);
 const flush=async()=>{for(let i=0;i<20;i++) await Promise.resolve()};
 async function tick(ms){const end=now+ms;while(true){const entries=[...timers.entries()].filter(([,t])=>t.at<=end).sort((a,b)=>a[1].at-b[1].at);if(!entries.length)break;const [id,t]=entries[0];now=t.at;timers.delete(id);t.fn();await flush()}now=end;await flush()}
 vm.runInContext(fs.readFileSync(path.join(extensionPath,'background.js'),'utf8'),context);await flush();
 assert.equal(ports.length,0,'idle startup must not open a native process');
 items=[active(25,100)];chrome.downloads.onCreated.emit();await tick(110);
 assert.equal(messages.at(-1).receivedBytes,25);assert.equal(messages.at(-1).browser,isEdge?'edge':'chrome');
 const keys=['version','type','browser','profile','receivedBytes','totalBytes','activeCount','unknownCount','downloads'];assert.deepEqual(Object.keys(messages.at(-1)).sort(),keys.sort());
 items=[active(75,100)];await tick(1000);assert.equal(messages.at(-1).receivedBytes,75,'bytes update even without onChanged');
 assert.equal(badge,'75%');
 const old=ports.at(-1);old.closed=true;chrome.runtime.lastError={message:'mock missing host'};old.onDisconnect.emit();chrome.runtime.lastError=undefined;
 const count=ports.length;await tick(1000);assert.equal(ports.length,count,'backoff prevents rapid reconnect');await tick(2000);assert(ports.length>count);
 items=[active(5,-1)];chrome.downloads.onChanged.emit();await tick(110);assert.equal(messages.at(-1).unknownCount,1);assert.equal(badge,'↓');
 items=[active(5,100,{paused:true})];chrome.downloads.onChanged.emit();await tick(110);assert.equal(messages.at(-1).activeCount,0);assert.equal(badge,'');await tick(300);assert(!ports.at(-1).closed);assert.equal(messages.at(-1).downloads[0].paused,true);
 items=[active(30,100)];chrome.downloads.onChanged.emit();await tick(110);assert.equal(messages.at(-1).activeCount,1);
 items=[active(100,100,{state:'complete'})];chrome.downloads.onChanged.emit();await tick(110);
 assert.equal(messages.at(-1).downloads[0].complete,true);assert.equal(messages.at(-1).downloads[0].localPath,'/test/report.zip');
 await tick(300);assert(ports.at(-1).closed,'completed tasks must release native connection');
 const completedPorts=ports.length;await tick(5000);assert.equal(ports.length,completedPorts,'completed tasks do not poll');
 items=[];chrome.downloads.onChanged.emit();await tick(110);assert.equal(messages.at(-1).totalBytes,0);await tick(300);assert(ports.at(-1).closed);
 const before=ports.length;await tick(60000);assert.equal(ports.length,before,'idle must not keep native host alive');
 // A tiny file may finish between onCreated and the first scheduled scan.
 items=[active(100,100,{id:2,state:'complete',filename:'/test/tiny.txt'})];
 chrome.downloads.onCreated.emit(items[0]);await flush();await tick(110);
 assert.equal(messages.at(-1).downloads[0].filename,'tiny.txt');
 assert(saved.trackedDownloadIds.includes(2));
 // Existing historic downloads are not imported without a tracked ID.
 items.push(active(100,100,{id:999,state:'complete',filename:'/test/history.txt'}));
 chrome.downloads.onChanged.emit();await tick(110);
 assert.equal(messages.at(-1).downloads.length,1);
 console.log('WORKER_OK',isEdge?'edge':'chrome','polling pause resume unknown complete disconnect backoff idle privacy');
}
(async()=>{await worker(false);await worker(true);const m=JSON.parse(fs.readFileSync(path.join(extensionPath,'manifest.json')));assert.deepEqual([...m.permissions].sort(),['alarms','downloads','nativeMessaging','storage']);assert(!m.host_permissions&&!m.content_scripts&&!m.externally_connectable);console.log('BROWSER_EXTENSION_OK aggregation lifecycle permissions')})().catch(error=>{console.error(error);process.exit(1)});
