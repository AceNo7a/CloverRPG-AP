local f=assert(io.open(arg[1] or 'clover_auto_parry.lua')); local text=f:read('*a'); f:close()
local core=assert(text:match('%-%- BEGIN TESTABLE ASSET MARKERS(.-)%-%- END TESTABLE ASSET MARKERS'))
local validate,fetch=assert(loadstring(core..'\nreturn validatedAssetMarker,fetchUsableClip'))()
local count=0
local function check(v,label) assert(v,label); count=count+1; print('PASS '..label) end
local function frame(t,names,name)
 return {Time=t,Name=name or 'Keyframe',GetMarkers=function() local a={}; for _,n in ipairs(names or {}) do a[#a+1]={Name=n} end; return a end}
end
local function clip(frames,loop)
 local c={Loop=loop or false};function c:IsA(s) return s=='KeyframeSequence' end
 function c:GetKeyframes() return self.destroyed and {} or frames end
 function c:Destroy() self.destroyed=true end
 function c:Clone() return clip(frames,self.Loop) end;return c
end
local bite=clip({frame(.2354,{'Charge'}),frame(.957916677,{'Attack'}),frame(1.73333,{},'End')})
check(validate(bite)==.957916677,'Bite Pounce asset marker extracted')
check(validate(clip({frame(1.003749967,{'Attack'}),frame(1.6666667)}))==1.003749967,'Tail Sweep asset marker extracted')
check(not validate(clip({})),'empty clip rejected')
check(not validate(clip({frame(.4,{'Attack'}),frame(1)},true)),'looping asset rejected')
check(not validate(clip({frame(.4,{'Attack'}),frame(.6,{'HitWindow'}),frame(1)})),'separated impacts rejected')
check(not validate(clip({frame(.4,{'Attack','Attack'}),frame(1)})),'repeated marker rejected')
check(validate(clip({frame(.4,{'Attack','HitWindow'},'Attack'),frame(1)}))==.4,'same-impact aliases deduplicated')
check(not validate(clip({frame(.4,{'Charge'}),frame(1)})),'unrelated marker rejected')
check(not validate(clip({frame(0/0,{'Attack'}),frame(1)})),'nonfinite time rejected')
check(not validate(clip({frame(.4,{'Attack'})})),'marker without later completion rejected')
local empty=clip({});local fallbackCalls=0
local got,provider=fetch('1',function() return empty end,function() fallbackCalls=fallbackCalls+1;return bite end)
check(got~=bite and validate(got)==.957916677 and provider=='KeyframeSequenceProvider' and not empty.destroyed and fallbackCalls==1,'empty primary uses a private fallback copy without destroying provider data')
got:Destroy()
check(not bite.destroyed and #bite:GetKeyframes()==3,'cleanup leaves shared provider cache intact')
got,provider=fetch('1',function() return bite end,function() error('must not fetch') end)
check(got~=bite and validate(got)==.957916677 and provider=='AnimationClipProvider','populated primary is cloned')
check(validate(fetch('1',function() error('primary failed') end,function() return bite end))==.957916677,'primary error uses fallback')
check(not pcall(fetch,'1',function() error('failed') end,function() error('denied') end),'both provider errors fail closed')
print('PASS: '..count..' asset-marker assertions.')
