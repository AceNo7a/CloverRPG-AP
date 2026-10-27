local n=0
local function check(v,name) assert(v,name); n=n+1; print("PASS "..name) end
local f=assert(io.open(arg[1] or 'external-tools/clover-diagnostics/clover_auto_parry.lua')); local source=f:read('*a'); f:close()
local modelSource=source:match('%-%- BEGIN TESTABLE LEARNING(.-)%-%- END TESTABLE LEARNING')
local support=source:match('%-%- BEGIN TESTABLE PROFILE SUPPORT(.-)%-%- END TESTABLE PROFILE SUPPORT')
local newModel,newStore=assert(loadstring(modelSource..support..'\nreturn newHitWindowModel,newProfileSupport'))()
local now=1000000
local saves,calls,lastPayload=0,0,nil
local code,retry=204,0
local options={place=8248288152,placeVersion=123,time=function() return now end,
 alive=function() return true end,spawn=function(fn) fn() end,
 encode=function(data) return data end,decode=function(data) return data end,
 write=function() saves=saves+1 end,
 send=function(payload) calls=calls+1; lastPayload=payload; return code,retry end}
local model=newModel(); model:sample('10',.4); model:sample('10',.41)
model.rows['10'].updatedAt=now
local p=newStore(options)
p.dirty=true; p:tick(0,model.rows,function() return true end)
check(saves==1 and calls==0,'cache saves without opting into reporting')
p.enabled=true; p:tick(1,model.rows,function() return true end)
check(calls==1 and p.sent['10'] and saves==2,'successful report acknowledged and dedupe persisted')
check(lastPayload.profiles[1].id=='10' and lastPayload.profiles[1].marker==.4 and lastPayload.place==8248288152,'report has numeric timing evidence')
local keys={schema=true,version=true,source=true,place=true,placeVersion=true,evidence=true,profiles=true}
for k in pairs(lastPayload) do assert(keys[k],'unexpected report field') end
check(not lastPayload.player and not lastPayload.logs and not lastPayload.jobId,'no identity or raw-log fields')
p:tick(62,model.rows,function() return true end)
check(calls==1,'unchanged ready timing not resubmitted')
model.rows['10'].position=.404; p:tick(123,model.rows,function() return true end)
check(calls==1,'sub-10ms jitter deduplicated')
model.rows['10'].position=.43; code=429; retry=180
p:tick(184,model.rows,function() return true end)
check(calls==2 and p.nextReport==364 and p.sent['10']=='ready:40','rate limit retains pending revision and honors retry delay')
p:tick(200,model.rows,function() return true end)
check(calls==2,'no early retry')
code=204; p:tick(365,model.rows,function() return true end)
check(calls==3 and p.sent['10']=='ready:43','failed revision retried and acknowledged')
local packed=p:pack(model.rows)
local restored={}; local p2=newStore(options)
check(p2:restore(packed,restored,now) and restored['10'].position==.4,'cache recomputes median from samples, never trusts position/status')
check(p2.sent['10']=='ready:43','report fingerprints survive reload')
local p3=newStore(options); p3:restore(packed,restored,now)
check(p3.sent['10']=='ready:43','rerun restores dedupe even when in-memory rows already exist')
check(not p2:restore(packed,{},now+8*86400) or not next((function() local r={}; p2:restore(packed,r,now+8*86400); return r end)()),'expired rows not imported')
packed.placeVersion=124; check(not p2:restore(packed,{},now),'game update invalidates cache')
packed.placeVersion=123; packed.place=1; check(not p2:restore(packed,{},now),'different place rejected')
packed.place=8248288152; packed.rows['10'].samples={.4,0/0}
restored={}; p2:restore(packed,restored,now); check(not next(restored),'non-finite cache timing rejected')
packed.rows['10'].samples={.4,.4}; packed.rows['10'].blocked=true
restored={}; p2:restore(packed,restored,now); check(restored['10'].blocked,'multiple-marker block persists')
model=newModel(); for i=1,9 do model:sample(tostring(i),.4); model:sample(tostring(i),.4) end
local payload=p2:batch(model.rows,function(id) return id~='1' end)
check(#payload.profiles==6 and payload.profiles[1].id=='2','batch bound and current classification enforced')
model:sample('2',.7); model:sample('3',.4,true)
payload=p2:batch(model.rows,function() return true end)
local ids={}; for _,r in ipairs(payload.profiles) do ids[r.id]=true end
check(not ids['2'] and not ids['3'],'variable and multi-hit candidates not reported as ready')
options.send=function() error('network failure') end
p=newStore(options); p.enabled=true; p:tick(0,model.rows,function() return true end)
check(not p.busy and p.nextReport>=60 and not next(p.sent),'network exception isolated without acknowledging reports')
options.spawn=function(fn) options.pending=fn end
p=newStore(options); p.enabled=true; p:tick(0,model.rows,function() return true end); p:tick(100,model.rows,function() return true end)
check(p.busy,'one outstanding async request')
p.enabled=false; options.pending()
check(not p.busy and not next(p.sent),'turning sharing off cancels queued request before dispatch')
options.spawn=function(fn) fn() end
options.send=function(payload) lastPayload=payload;return 204 end
options.assets={['10']={status='ready',position=.4,length=1.7,provider='AnimationClipProvider',updatedAt=now}}
local assetStore=newStore(options);assetStore.enabled=true
assetStore:tick(0,model.rows,function() return true end)
assetStore:tick(61,model.rows,function() return true end)
check(lastPayload.source=='asset' and lastPayload.profiles[1].samples==nil and lastPayload.profiles[1].spread==nil,'asset reports carry distinct provenance without fabricated samples')
check(assetStore.assetSent['10'] and assetStore.sent['10']==nil,'asset dedupe is separate from live timing dedupe')
local cache=assetStore:pack(model.rows)
local restoreOptions={};for k,v in pairs(options) do restoreOptions[k]=v end;restoreOptions.assets={}
local again=newStore(restoreOptions);again:restore(cache,{},now)
check(again.assets['10'].position==.4 and again.assetSent['10']==assetStore.assetSent['10'],'asset timing and report fingerprint survive reload')
check(#again:batch({},function() return true end,'asset').profiles==0,'restored asset report is not duplicated')
again.assets['10'].position=.43
check(#again:batch({},function() return true end,'asset').profiles==1,'changed asset timing is reportable')
check(#again:batch({},function() return false end,'asset').profiles==0,'asset reports still require current combat classification')
restoreOptions.assets={};local expired=newStore(restoreOptions);expired:restore(cache,{},now+8*86400)
check(next(expired.assets)==nil,'expired asset cache rejected')
cache.assets['10'].position=0/0;restoreOptions.assets={};local invalid=newStore(restoreOptions);invalid:restore(cache,{},now)
check(next(invalid.assets)==nil,'nonfinite cached asset rejected')
cache.assets['10'].position=.4;cache.assets['10'].provider='untrusted';invalid:restore(cache,{},now)
check(next(invalid.assets)==nil,'unknown cached provider rejected')
cache.assets=nil
check(invalid:restore(cache,{},now),'old learned-only cache remains compatible')
options.send=function() return 429,180 end
local retryAssets=newStore(options);retryAssets.enabled=true;retryAssets:tick(0,{},function() return true end)
check(not next(retryAssets.assetSent) and retryAssets.nextReport==180,'failed asset report remains pending with backoff')
options.knownFingerprint=function(kind,id) if id=='10' then return kind=='asset' and 'asset:40:170' or 'ready:40' end end
local known=newStore(options);local knownRows={['10']={status='ready',position=.4,spread=0,samples={.4,.4}}}
check(#known:batch(knownRows,function() return true end).profiles==0 and #known:batch({},function() return true end,'asset').profiles==0,'bundled learned and asset values are not resubmitted as new discoveries')
knownRows['10'].position=.44
check(#known:batch(knownRows,function() return true end).profiles==1,'changed learned timing remains reportable')
known.assets['10'].position=.45
check(#known:batch({},function() return true end,'asset').profiles==1,'changed asset timing remains reportable')
knownRows['99']={status='ready',position=.5,spread=0,samples={.5,.5}}
check(#known:batch(knownRows,function() return true end).profiles==2,'new IDs remain reportable alongside changed bundled IDs')
print('PASS: '..n..' persistence/reporting assertions.')
