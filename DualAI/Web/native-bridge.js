'use strict';
(function(){
  if(!window.webkit?.messageHandlers?.apiBridge)return;
  const pending=new Map();
  window.DualAIHost={
    request(action,payload={},signal){
      return new Promise((resolve,reject)=>{
        const id=crypto.randomUUID?.()||`${Date.now()}-${Math.random().toString(36).slice(2)}`;
        if(signal?.aborted){reject(new DOMException('Stopped','AbortError'));return;}
        const abort=()=>{window.webkit.messageHandlers.apiBridge.postMessage({id,action:'cancel'});finish();reject(new DOMException('Stopped','AbortError'));};
        const timer=setTimeout(()=>{window.webkit.messageHandlers.apiBridge.postMessage({id,action:'cancel'});finish();reject(Error('API 等待逾時，請檢查連線。'));},action==='analyze'?15*60*1000:10000);
        function finish(){clearTimeout(timer);signal?.removeEventListener('abort',abort);pending.delete(id);}
        pending.set(id,{resolve,reject,finish});
        signal?.addEventListener('abort',abort,{once:true});
        window.webkit.messageHandlers.apiBridge.postMessage({id,action,payload});
      });
    },
    resolve(id,base64){
      const entry=pending.get(id);if(!entry)return;
      try{
        const bytes=Uint8Array.from(atob(base64),c=>c.charCodeAt(0));
        const response=JSON.parse(new TextDecoder().decode(bytes));
        entry.finish();
        if(response.ok)entry.resolve(response.data);else entry.reject(Error(response.error||'API 呼叫失敗。'));
      }catch{entry.finish();entry.reject(Error('原生 API 模組回覆格式不正確。'));}
    }
  };
})();
