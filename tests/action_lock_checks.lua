local f=assert(io.open(arg[1] or "clover_auto_parry.lua"));local source=f:read("*a");f:close()
local core=assert(source:match("%-%- BEGIN TESTABLE CORE(.-)%-%- END TESTABLE CORE"))
local scheduler,lock=assert(loadstring(core.."\nreturn newScheduler,combatLock"))()
local count=0
local function check(v,name) assert(v,name);count=count+1;print("PASS "..name) end
local h={state="Running",attrs={}}
function h:GetState() return "Enum.HumanoidStateType."..self.state end
function h:GetAttribute(k) return self.attrs[k] end
local c={attrs={}};function c:GetAttribute(k) return self.attrs[k] end
check(lock(h,c)==nil,"normal combat state is eligible")
c.attrs.State_Attacking=true;check(lock(h,c)=="State_Attacking","character attack lock is recognized")
c.attrs.State_Attacking=false;h.attrs.State_Stunned=true;check(lock(h,c)=="State_Stunned","humanoid stun lock is recognized")
h.attrs.State_Stunned=false;h.attrs.State_ParryCooldown=true
check(lock(h,c)=="State_ParryCooldown" and lock(h,c,true)==nil,"observed cooldown gates parry but not movement")
h.attrs.State_ParryCooldown=false;c.attrs.State_Blocking=true
check(lock(h,c,true)=="State_Blocking" and lock(h,c)==nil,"speed respects block movement restriction")
c.attrs.State_Blocking=false;h.state="Ragdoll";check(lock(h,c)=="humanoid Ragdoll","ragdolled inputs are gated")
h.state="Running"
local s=scheduler();local tr={position=.31,ready=false};local sent,waits=0,0
local function inspect(t) return true,t.position,1,true,t.ready,"State_Attacking" end
local function press() sent=sent+1;return true end
s.onWait=function() waits=waits+1 end
s:add(tr,{},"attack",.31,0,0);s:step(.31,.7,inspect,press)
check(sent==0 and s.pending[tr] and s.nextAllowed==0,"blocked attack stays pending without spending cooldown")
s:step(.32,.7,inspect,press);check(waits==1,"same wait reason does not spam logs")
tr.ready=true;tr.position=.35;s:step(.35,.7,inspect,press)
check(sent==1 and not s.pending[tr],"attack is attempted if action unlocks inside valid window")
local original=s.nextAllowed
s:add(tr,{},"attack",.31,2,0);tr.ready=false;tr.position=.32;s:step(2.32,.7,inspect,press)
tr.position=.41;s:step(2.41,.7,inspect,press)
check(sent==1 and not s.pending[tr] and s.nextAllowed==original,"expired locked attack does not trigger late or consume cooldown")
s:add(tr,{},"attack",.31,3,0);s.pending[tr].hitPosition=.36;tr.position=.36
s:step(3.36,.7,inspect,press);check(not s.pending[tr],"waiting never extends past impact position")
print("Action lock assertions passed: "..count)
