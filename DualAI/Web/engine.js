/* Deterministic educational demo. No LLM, no eval, no network. */
(function(root){
  'use strict';
  const examples={mod:'計算 (2^10 + 3^5) mod 7',handshake:'10 人，每兩人握手一次，共幾次？',sqrt:'證明 √2 是無理數'};
  function calculate(source){
    const s=source.replace(/^\s*(?:計算|求值|算出)\s*[:：]?\s*/,'').replace(/[?？。=]\s*$/,'').replace(/\bmod\b/gi,'%').replace(/×/g,'*').replace(/÷/g,'/').trim();
    if(s.length>160||!s||!/^[\d\s.+*/%^()\-]+$/.test(s))throw Error('示範模式支援數學算式、握手問題與 √2 證明。自由問答需連接真實 AI 後端。');
    const tokens=s.match(/\d+(?:\.\d+)?|\.\d+|[()+*/%^\-]/g)||[];
    if(tokens.join('')!==s.replace(/\s/g,''))throw Error('數字或小數點格式不正確。');
    if(tokens.length>100)throw Error('算式太長，請縮短後再試。');
    let pos=0;
    function check(v){if(!Number.isFinite(v)||Math.abs(v)>1e15)throw Error('算式超出示範計算範圍（絕對值 10¹⁵）。');return v;}
    function atom(){const t=tokens[pos++];if(t==='('){const v=expr();if(tokens[pos++]!==')')throw Error('括號沒有成對。');return v;}if(t===undefined||!/^\d*\.?\d+$/.test(t))throw Error('算式不完整，請檢查運算子與數字。');return check(Number(t));}
    function power(){let v=atom();if(tokens[pos]==='^'){pos++;const n=unary();if(Math.abs(n)>100)throw Error('指數範圍需介於 -100 與 100。');v=check(v**n);}return v;}
    function unary(){if(tokens[pos]==='-'){pos++;return -unary();}if(tokens[pos]==='+'){pos++;return unary();}return power();}
    function term(){let v=unary();while(['*','/','%'].includes(tokens[pos])){const op=tokens[pos++],w=unary();if((op==='/'||op==='%')&&w===0)throw Error('不能除以零或對零取餘數。');v=check(op==='*'?v*w:op==='/'?v/w:v%w);}return v;}
    function expr(){let v=term();while(['+','-'].includes(tokens[pos])){const op=tokens[pos++],w=term();v=check(op==='+'?v+w:v-w);}return v;}
    const v=expr();if(pos!==tokens.length)throw Error('算式格式不正確。');return {expression:s.replace(/%/g,' mod '),value:Object.is(v,-0)?0:Number(v.toPrecision(13)),raw:v};
  }
  function makeDemo(question,system){
    if(!['A','B'].includes(system))throw Error('請選擇系統 A 或 B。');
    let answer,reason,evidence;
    const handshake=question.match(/(\d+)\s*人/);
    if(handshake&&/握手/.test(question)){
      const n=Number(handshake[1]);if(n<2||n>1000000)throw Error('握手示範支援 2 至 1,000,000 人。');
      answer=`${n*(n-1)/2} 次`;reason=`每人與 ${n-1} 人握手，計算 ${n} × ${n-1} 後，每一對被計入兩次，所以除以 2。\n前提：任兩人恰好握手一次，且不和自己握手。`;evidence=[`${n} × (${n} − 1) ÷ 2 = ${n*(n-1)/2}`];
    }else if(/(?:√\s*2|sqrt\(2\)|根號\s*2)/i.test(question)&&/證明|無理/.test(question)){
      answer='√2 是無理數。';reason='反證法：假設 √2 = a/b，且 a、b 互質。\na² = 2b²，因此 a 為偶數。令 a = 2k，可得 b² = 2k²，所以 b 也是偶數。\na、b 同為偶數，與互質假設矛盾，因此 √2 不可能是有理數。';evidence=['整數平方為偶數 ⇔ 該整數為偶數。','有理數可寫成互質整數 a/b（b ≠ 0）。'];
    }else{const c=calculate(question);answer=String(c.value);reason=`算式：${c.expression}\n結果：${c.value}\n遵循括號、次方、乘除與餘數、加減的優先順序；同級由左到右。負數餘數採 JavaScript remainder 定義。\n小數使用浮點數，顯示最多 13 位有效數字。`;evidence=[`${c.expression} = ${c.value}`];}
    const alternative=/^-?\d+(?:\.\d+)?$/.test(answer)?String(Number(answer)+1):'省略關鍵前提，直接宣稱結論成立。';
    const steps=system==='A'?[
      {role:'researcher',label:'研究員',text:`【流程示例】提出待驗證結論：${answer}\n${reason}`},
      {role:'opposer',label:'反對者',text:'【流程示例】挑戰三個環節：\n1. 題目的前提是否齊全？\n2. 運算順序或推理步驟是否漏掉？\n3. 是否把猜測當作已驗證事實？'},
      {role:'revision',label:'研究員 · 修正',text:`【流程示例】保留結論 ${answer}，並補充前提與檢查步驟。\n${reason}`},
      {role:'verifier',label:'驗證員',text:`【本機／教學檢查】\n${evidence.join('\n')}\n沒有網路查證，也沒有模型信心分數。`},
      {role:'judge',label:'總判官',text:`【流程示例】根據以上本機計算或教學證明，結論為：${answer}\n這是示範流程，並非四個模型的獨立共識。`}
    ]:[
      {role:'candidate1',label:'示範來源 1',text:`【合成候選答案】${answer}\n${reason}`},
      {role:'candidate2',label:'示範來源 2',text:`【刻意放入的錯誤候選】${alternative}\n此答案僅用來演示錯誤如何被攔下，並非模型輸出。`},
      {role:'cross1',label:'來源 1 · 審查他方',text:`【流程示例】只檢查來源 2：${alternative}\n缺乏正確運算或必要前提，不能採用。`},
      {role:'cross2',label:'來源 2 · 審查他方',text:`【流程示例】只檢查來源 1：${answer}\n${evidence.join('\n')}`},
      {role:'judge',label:'證據仲裁',text:`【本機／教學檢查】依據計算或證明採用 ${answer}，排除刻意放入的錯誤候選。\n實際參與 AI 模型：0。`}
    ];
    return {id:root.crypto?.randomUUID?.()||`demo-${Date.now()}-${Math.random().toString(36).slice(2)}`,timestamp:new Date().toISOString(),question,system,mode:'demo',steps,final:{answer,explanation:reason,consensus:system==='A'?'角色流程示例':'分歧已示範',issues:['示範內容不代表真實 AI 的品質或共識。']},evidence,stats:{models:0,calls:0,inputTokens:0,outputTokens:0,costUsd:0,elapsedMs:0}};
  }
  root.DualEngine={examples,calculate,makeDemo};
  if(typeof module!=='undefined')module.exports=root.DualEngine;
})(typeof globalThis!=='undefined'?globalThis:window);
