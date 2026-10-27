-- Lifecycle tests for the actual embedded controller, with no live game input.
local f=assert(io.open(arg[1] or "clover_auto_parry.lua")); local source=f:read("*a"); f:close()
local body=assert(source:match("%-%- BEGIN MOVEMENT CONTROLLER(.-)%-%- END MOVEMENT CONTROLLER"))
local factory=assert(loadstring(body.."\nreturn newMovementControl"))()
local count=0
local function check(value,name) assert(value,name); count=count+1; print("PASS "..name) end
local now,focused,char,root=0,true,{}, {Anchored=false}
local h={Health=100,WalkSpeed=16,PlatformStand=false,AutoRotate=true,Sit=false,state="Running"}
function h:GetState() return "Enum.HumanoidStateType."..self.state end
local created,destroyed,updates=0,0,0
local throwCreate,throwUpdate=false,false
local m=factory({now=function() return now end,focused=function() return focused end,
    rig=function() return char,h,root end,velocity=function(speed) return speed end,
    createFlight=function()
        if throwCreate then error("create failed") end
        created=created+1
        return {destroy=function() destroyed=destroyed+1 end,update=function(v)
            if throwUpdate then error("constraint removed") end
            assert(v==32); updates=updates+1
        end}
    end})
local function tick() now=now+.11; m:tick() end
check(m.mode=="off" and created==0,"movement starts off without creating physics objects")
check(m:setMode("speed"),"speed starts on a live character")
tick(); check(h.WalkSpeed==155,"speed is applied on normal movement")
h.WalkSpeed=24; tick(); check(h.WalkSpeed==155 and m.restoreSpeed==24,"sprint replacement is reapplied and remembered")
m:stop("test"); check(h.WalkSpeed==24,"disable restores latest observed game speed")
m:setMode("speed"); tick(); h.state="Climbing"; tick()
check(h.WalkSpeed==24 and m.mode=="speed","climbing suspends boost without losing enabled mode")
h.state="Running"; tick(); check(h.WalkSpeed==155,"boost resumes after climb")
h.WalkSpeed=0; tick(); check(h.WalkSpeed==0,"zero-speed action lock is respected")
h.WalkSpeed=16; tick(); check(h.WalkSpeed==155,"boost resumes after action lock clears")
h.WalkSpeed=31; m:stop("test"); check(h.WalkSpeed==31,"disable does not overwrite a new external value")
m:setMode("speed"); tick(); focused=false; tick()
check(m.mode=="off" and h.WalkSpeed==31,"focus loss stops speed and restores ownership")
check(not m:setMode("fly") and created==0,"unfocused flight is rejected")
focused=true; h.state="Running"; h.WalkSpeed=16
check(m:setMode("fly") and h.PlatformStand and not h.AutoRotate,"flight takes explicit humanoid ownership")
tick(); check(updates==1 and created==1,"flight updates its owned actuator")
m:stop("test"); check(destroyed==1 and not h.PlatformStand and h.AutoRotate,"flight removes actuator and restores flags")
m:stop("again"); check(destroyed==1,"cleanup is idempotent")
m:setMode("fly"); h.PlatformStand=false; tick()
check(m.mode=="off" and destroyed==2,"external movement state ends flight without fighting it")
m:setMode("fly"); m:setMode("speed"); tick()
check(destroyed==3 and h.WalkSpeed==155 and not h.PlatformStand,"speed and flight are mutually exclusive")
m:setMode("fly"); check(h.WalkSpeed==16,"switching to flight restores ground speed")
h.Health=0; tick(); check(m.mode=="off" and destroyed==4,"death removes flight objects")
h.Health=100; m:setMode("speed"); tick(); char={}; tick()
check(m.mode=="off" and h.WalkSpeed==16,"character replacement releases previous controller")
root.Anchored=true; check(not m:setMode("fly"),"anchored flight is rejected"); root.Anchored=false
throwCreate=true; check(not m:setMode("fly") and not h.PlatformStand,"creation errors leave movement off"); throwCreate=false
m:setMode("fly"); throwUpdate=true; tick(); throwUpdate=false
check(m.mode=="off" and destroyed==5 and h.AutoRotate,"actuator errors clean up and restore flags")
for i=1,150 do m:note("event "..i) end
check(#m.events==100 and m:export():find("server acceptance unverified",1,true),"diagnostics are bounded and qualify local evidence")
print("Movement assertions passed: "..count)
