// Optional stateless relay. DISCORD_WEBHOOK is a Worker secret, never client code.
const json = (data, status, headers={}) => Response.json(data, {status, headers});
const finite = (v, min, max) => typeof v === 'number' && Number.isFinite(v) && v >= min && v <= max;

export function validate(data) {
  if (!data || data.schema !== 1 || ![5,6].includes(data.version) || data.place !== 8248288152 ||
      !Number.isSafeInteger(data.placeVersion) || data.placeVersion < 0 ||
      !Array.isArray(data.profiles) || data.profiles.length < 1 || data.profiles.length > 6) return null;
  const profiles=[];
  for (const row of data.profiles) {
    if (!row || typeof row.id !== 'string' || !/^\d{1,20}$/.test(row.id) ||
        !finite(row.marker,.03,8) || !finite(row.spread,0,.04) ||
        !Number.isInteger(row.samples) || row.samples<2 || row.samples>5) return null;
    profiles.push({id:row.id,marker:row.marker,spread:row.spread,samples:row.samples});
  }
  // Strictly rebuild the outbound payload: names, logs and arbitrary text cannot pass through.
  return {schema:1,version:data.version,place:data.place,placeVersion:data.placeVersion,
    evidence:'Untrusted client candidate; HitWindow consistency, NOT verified parry success',profiles};
}

export default {
  async fetch(request, env) {
    if (request.method!=='POST' || new URL(request.url).pathname!=='/report') return json({error:'not found'},404);
    if (!env.REPORT_LIMITER || !/^https:\/\/discord\.com\/api\/webhooks\/\d+\/[\w-]+$/.test(env.DISCORD_WEBHOOK || ''))
      return json({error:'reporting not configured'},503);
    try {
      // Shared approximate limit per Cloudflare location; no player/IP identifier is collected.
      if (!(await env.REPORT_LIMITER.limit({key:'clover-report'})).success)
        return json({retry_after:60},429,{'Retry-After':'60'});
      if (!request.body) return json({error:'missing body'},400);
      const reader=request.body.getReader(); const chunks=[]; let length=0;
      while (true) {
        const {value,done}=await reader.read(); if (done) break;
        length+=value.byteLength;
        if (length>4096) { await reader.cancel(); return json({error:'body too large'},413); }
        chunks.push(value);
      }
      const bytes=new Uint8Array(length); let offset=0;
      for (const chunk of chunks) { bytes.set(chunk,offset); offset+=chunk.length; }
      let data;
      try { data=validate(JSON.parse(new TextDecoder().decode(bytes))); } catch { return json({error:'invalid JSON'},400); }
      if (!data) return json({error:'invalid timing candidate'},400);
      const response=await fetch(env.DISCORD_WEBHOOK+'?wait=true',{
        method:'POST', headers:{'Content-Type':'application/json'}, signal:AbortSignal.timeout(10000),
        body:JSON.stringify({content:'Clover timing candidates\n```json\n'+JSON.stringify(data)+'\n```',allowed_mentions:{parse:[]}})
      });
      if (response.status===429) {
        let retry=60;
        try { const body=await response.json(); retry=Math.max(60,Math.min(86400,Number(body.retry_after)||60)); } catch {}
        return json({retry_after:retry},429,{'Retry-After':String(retry)});
      }
      if (!response.ok) return json({error:'delivery failed'},502);
      return new Response(null,{status:204});
    } catch { return json({error:'delivery unavailable'},503); }
  }
};
