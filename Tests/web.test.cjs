const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
test('independent judge gates analysis; manual Meta review is clearly recorded without extra API calls',async()=>{
 class E{constructor(){this.children=[];this.dataset={};this.listeners={};this.value='';}append(...x){this.children.push(...x);}replaceChildren(...x){this.children=x;}get firstElementChild(){return this.children[0]||(this.children[0]=new E());}addEventListener(n,f){this.listeners[n]=f;}setAttribute(){}focus(){}scrollIntoView(){}remove(){} }
 const html=fs.readFileSync('DualAI/Web/index.html','utf8'),els=Object.fromEntries([...html.matchAll(/id="([^"]+)"/g)].map(m=>[m[1],new E()]));
 const status=new E(),stored=[],requests=[];
 const doc={getElementById:id=>{assert.ok(els[id],id);return els[id];},createElement:()=>new E(),createTextNode:text=>({textContent:text}),querySelectorAll:()=>[],querySelector:()=>status};
 const ctx=vm.createContext({document:doc,window:{addEventListener(){},DualAIHost:{request:async(a,p)=>{requests.push({a,p});return {enabled:false,models:[]};}}},localStorage:{getItem:()=>null,setItem:(...x)=>stored.push(x)},setTimeout:()=>0,clearTimeout(){},console,matchMedia:()=>({matches:true})});
 vm.runInContext(fs.readFileSync('DualAI/Web/app.js','utf8'),ctx);
 vm.runInContext(`applyAPIStatus({enabled:true,selectedA:'a',models:[{id:'a',hasKey:true,tested:true}],judgeReady:false})`,ctx);assert.equal(els.run.disabled,true);
 vm.runInContext(`applyAPIStatus({enabled:true,selectedA:'a',models:[{id:'a',hasKey:true,tested:true}],judgeReady:true,judgeModel:'gemini-fixture'})`,ctx);assert.equal(els.run.disabled,false);
 vm.runInContext(`renderResult({id:'report',system:'A',question:'問題',mode:'live',timestamp:'2026-10-11',steps:[{role:'judge',label:'判官',text:'待查'}],final:{answer:'答案',issues:[]},stats:{models:2,calls:5,costUsd:null}})`,ctx);
 const panel=els.result.children.at(-1);const copy=panel.children[2];await copy.listeners.click();assert.equal(requests.at(-1).a,'copyReview');assert.ok(requests.at(-1).p.text.includes('問題'));
 const input=panel.children[5];input.value='<script>untrusted Meta text</script>';const button=panel.children[6];button.listeners.click();
 const report=JSON.parse(stored.at(-1)[1])[0];assert.equal(report.manualReview.verified,false);assert.equal(report.manualReview.source,'user-pasted');assert.equal(report.stats.calls,5);assert.equal(report.manualReview.text,input.value);
});
