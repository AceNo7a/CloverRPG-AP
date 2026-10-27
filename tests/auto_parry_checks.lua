-- Executes the delivered script against mocks; not an executor compatibility test.
local count = 0
local function check(ok, name) assert(ok, name); count = count + 1; print("PASS " .. name) end
local path = arg[1] or "external-tools/clover-diagnostics/clover_auto_parry.lua"
local file = assert(io.open(path)); local source = file:read("*a"); file:close()
check(loadstring(source) ~= nil, "complete delivered file parses")
local core = assert(source:match("%-%- BEGIN TESTABLE CORE(.-)%-%- END TESTABLE CORE"))
local factory = assert(loadstring(core .. "\nreturn newScheduler"))()
local s, sent = factory(), 0
local track = { position = 0, speed = 1, valid = true, inRange = true }
local function inspect(t) return t.valid, t.position, t.speed, t.inRange end
local function press() sent = sent + 1; return true end
s:add(track, {}, "one", .31, 0, 0); track.position = .3
s:step(.3, .7, inspect, press); check(sent == 0, "no premature press")
track.position = .32; s:step(.32, .7, inspect, press)
check(sent == 1, "press at playback threshold")
s:step(.33, .7, inspect, press); check(sent == 1, "each occurrence is consumed once")
s:add(track, {}, "one", .31, .5, 0); s:step(.5, .7, inspect, press)
check(sent == 1 and next(s.pending) == nil, "cooldown discards attack rather than deferring it")
s:add(track, {}, "one", .31, 1.1, 0); track.inRange = false; s:step(1.1, .7, inspect, press)
check(sent == 1, "out of range at trigger sends no input")
track.inRange = true; track.valid = false
s:add(track, {}, "one", .31, 2, 0); s:step(2, .7, inspect, press)
check(sent == 1 and next(s.pending) == nil, "removed/stopped/dead actor or track cancels")
track.valid = true; track.position = .6
s:add(track, {}, "one", .31, 3, 0); s:step(3, .7, inspect, press)
check(sent == 1, "lagged stale trigger discarded")
check(not s:add(track, {}, "one", .31, 4, .6), "late notification rejected")
track.position = .2; track.speed = 0
s:add(track, {}, "one", .31, 5, 0); s:step(5.4, .7, inspect, press)
check(sent == 1, "paused animation does not use wall-clock delay")
s:step(8.1, .7, inspect, press); check(next(s.pending) == nil, "permanently paused track expires")
track.position = .32; track.speed = 2
s:add(track, {}, "one", .31, 9, 0); s:step(9.16, .7, inspect, press)
check(sent == 2, "accelerated playback triggers by current position")
s:add(track, {}, "one", .31, 10, 0); s:clear()
check(next(s.pending) == nil and s.nextAllowed > 9, "disable clears jobs without erasing cooldown")
s:add(track, {}, "one", .31, 11, 0)
local prior = s.nextAllowed; s:step(11, .7, inspect, function() return false end)
check(s.nextAllowed == prior, "unavailable input not counted as an attempt")
local other = { position = .32, speed = 1, valid = true, inRange = true }
s:add(track, {}, "one", .31, 12, 0); s:add(other, {}, "two", .31, 12, 0)
s:step(12, .7, inspect, press); check(sent == 3, "simultaneous attackers cause one input")

local function signal()
    local handlers = {}
    return { Connect = function(_, fn)
        local h = { fn = fn, live = true }; handlers[#handlers + 1] = h
        return { Disconnect = function() h.live = false end }
    end, Fire = function(_, ...)
        for _, h in ipairs(handlers) do if h.live then h.fn(...) end end
    end }
end
local nodes = {}
local function object(class, name, parent)
    local o = { ClassName = class, Name = name or class, Parent = parent, Visible = true }
    for _, key in ipairs({ "Activated", "InputBegan", "InputEnded", "InputChanged", "FocusLost", "AnimationPlayed" }) do o[key] = signal() end
    function o:IsA(c) return self.ClassName == c end
    function o:IsDescendantOf(ancestor)
        local p = self.Parent; while p do if p == ancestor then return true end; p = p.Parent end
        return false
    end
    function o:FindFirstChild(name)
        for _, n in ipairs(nodes) do if n.Parent == self and n.Name == name and not n.Destroyed then return n end end
    end
    function o:FindFirstChildOfClass(c)
        for _, n in ipairs(nodes) do if n.Parent == self and n.ClassName == c and not n.Destroyed then return n end end
    end
    function o:WaitForChild(name) return assert(self:FindFirstChild(name), name) end
    function o:GetAttributes() return self.attributes or {} end
    function o:GetChildren()
        local children={}; for _, n in ipairs(nodes) do if n.Parent == self and not n.Destroyed then children[#children+1]=n end end
        return children
    end
    function o:GetDescendants()
        local result={}; for _,n in ipairs(nodes) do if not n.Destroyed and n:IsDescendantOf(self) then result[#result+1]=n end end
        return result
    end
    function o:Destroy()
        self.Destroyed = true; self.Parent = nil
        for _, n in ipairs(nodes) do if n.Parent == self then n:Destroy() end end
    end
    function o:CaptureFocus() end
    nodes[#nodes + 1] = o; return o
end
Instance = { new = function(c) return object(c) end }
Color3 = { fromRGB = function(...) return {...} end, new = function(...) return {...} end }
UDim = { new = function(s, o) return {Scale=s, Offset=o} end }
UDim2 = { new = function(a,b,c,d) return { X=UDim.new(a,b), Y=UDim.new(c,d) } end }
Enum = setmetatable({}, { __index = function(_, k) return setmetatable({}, { __index = function(_, v) return v end }) end })
workspace = object("Workspace")
workspace.DescendantAdded, workspace.DescendantRemoving = signal(), signal()
function workspace:GetDescendants() local r = {}; for _, n in ipairs(nodes) do if n:IsDescendantOf(self) then r[#r+1] = n end end; return r end
local player = object("Player")
player.CharacterRemoving = signal()
object("PlayerGui", "PlayerGui", player)
local function position(x) return setmetatable({x=x}, { __sub=function(a,b) return {Magnitude=math.abs(a.x-b.x)} end }) end
local function rig(name, x)
    local m = object("Model", name, workspace)
    local r = object("Part", "HumanoidRootPart", m); r.Position = position(x)
    local h = object("Humanoid", "Humanoid", m); h.Health = 100
    local a = object("Animator", "Animator", h)
    return m, a
end
local own, ownAnimator = rig("Self", 0); player.Character = own
local guard, animator = rig("Kamo Guard Respawnable", 4)
local another, otherAnimator = rig("Other player", 4)
local input = { InputBegan=signal(), InputChanged=signal(), InputEnded=signal(), WindowFocusReleased=signal(), WindowFocused=signal() }
function input:GetFocusedTextBox() return self.textFocus end
function input:IsKeyDown() return self.fDown or false end
local run = { Heartbeat=signal() }
local services = { Players={LocalPlayer=player, GetPlayerFromCharacter=function(_, rig) if rig == another then return {} end end}, UserInputService=input, RunService=run }
game = { PlaceId=8248288152, GetService=function(_, n) return assert(services[n], n) end }
local environment, clipboard, downs, ups, now, throwDown, throwUp = {CloverParryOptions={useBundledProfiles=false}}, nil, 0, 0, 0, false, false
getgenv = function() return environment end
setclipboard = function(v) clipboard = v end
keypress = function(v) assert(v == 0x46); downs=downs+1; if throwDown then error("mock down failure") end end
keyrelease = function(v) assert(v == 0x46); if throwUp then error("mock up failure") end; ups=ups+1 end
os.clock = function() return now end
local function beat(t) now=t; run.Heartbeat:Fire() end
local function click(prefix)
    for _, n in ipairs(nodes) do
        if n.ClassName == "TextButton" and not n.Destroyed and n.Text:sub(1,#prefix) == prefix then n.Activated:Fire(); return end
    end
    error("button missing: " .. prefix)
end
local function animation(id)
    local tr = { Animation={AnimationId="rbxassetid://"..id}, Name="mock animation", Length=.9, Priority="Action",
        TimePosition=0, Speed=1, Looped=false, IsPlaying=true, Stopped=signal(), KeyframeReached=signal(), markers={} }
    function tr:GetMarkerReachedSignal(name) self.markers[name]=self.markers[name] or signal(); return self.markers[name] end
    return tr
end
local function swing(t, id, a)
    now=t; local tr=animation(id or "86722279259826"); (a or animator).AnimationPlayed:Fire(tr); return tr
end

task={spawn=function(fn) fn() end,wait=function() end}
dofile(path)
local ui=environment.CloverAutoParry
local buttons,fields=0,0
for _,o in ipairs(ui.gui:GetDescendants()) do
 if o:IsA("TextButton") then buttons=buttons+1 end
 if o:IsA("TextBox") then fields=fields+1 end
end
check(buttons==4 and fields==0,"GUI has four controls and no configurable fields")
check(not ui.enabled and ui.learning.enabled and ui.discovery.enabled,"auto starts OFF; learning and recording permanently ON")
input.InputBegan:Fire({KeyCode="F6"},false)
check(ui.discovery.enabled,"F6 cannot disable background recording")
click("Test F"); beat(.9); check(downs==0,"test input waits one second")
beat(1); check(downs==1 and ui.held,"test sends one F")
beat(1.13); check(not ui.held and ups==1,"test releases F")
click("Auto parry")
local tr=swing(2); tr.TimePosition=.32; beat(2.32)
check(downs==2 and ui.enabled,"guard input still works with background audit")
check(#ui.audit.lines>0 and not ui.audit.running and ui.audit.nextRun>300,"audit automatically runs once and schedules another bounded scan")
beat(2.5)
tr=swing(3,nil,otherAnimator); tr.TimePosition=.32; beat(3.32)
check(downs==3,"players are eligible without a Targets selector")
beat(3.5)
tr=swing(4,nil,ownAnimator); tr.TimePosition=.32; beat(4.32)
check(downs==3,"own animations remain excluded")
local before=#ui.discovery.order
tr=swing(5,"59999",otherAnimator)
check(#ui.discovery.order==before+1,"unknown nearby player animation automatically recorded")
input.WindowFocusReleased:Fire()
check(not ui.enabled and ui.learning.enabled and ui.discovery.enabled,"focus loss stops input while background capture continues")
input.WindowFocused:Fire()
tr=swing(6,"59998",otherAnimator)
check(#ui.discovery.order==before+2,"recording continues with auto OFF")
click("Copy logs")
check(clipboard:find("CLOVER AUTO PARRY v6",1,true) and clipboard:find("CLOVER DISCOVERY v6",1,true)
 and clipboard:find("CLOVER MARKER LEARNING v6.3",1,true) and clipboard:find("BACKGROUND AUDIT",1,true),"one export includes attempts, learning, discovery and audit")
setclipboard=nil; click("Copy logs")
check(ui.export and ui.export.Text,"clipboard fallback remains available")
ui.export.FocusLost:Fire(); setclipboard=function(v) clipboard=v end
click("Auto parry"); now=7; input.InputBegan:Fire({KeyCode="F"},false)
tr=swing(7.1); tr.TimePosition=.32; beat(7.42)
check(downs==3,"manual F still reserves cooldown")
tr=swing(8); tr.TimePosition=.32; input.textFocus={}; beat(8.32); input.textFocus=nil
check(downs==3,"typing still prevents automatic input")
tr=swing(9); tr.TimePosition=.32; throwDown=true; beat(9.32); throwDown=false
check(not ui.enabled and not ui.held,"backend exception stops input and releases key")
check(ui.discovery.enabled and ui.learning.enabled,"backend exception does not disable passive features")
click("Auto parry"); tr=swing(10); tr.TimePosition=.32; beat(10.32)
throwUp=true; ui:Unload()
check(ui.held and ui.alive,"failed release retains unload controls")
throwUp=false; ui:Unload(); check(not ui.alive and not ui.held,"unload cleans input after backend recovery")

-- Observe real delivered-file callbacks against combat/execution registry mocks.
local rs=object("ReplicatedStorage","ReplicatedStorage"); services.ReplicatedStorage=rs
local folder=object("Folder","Animations",rs)
local combat=object("Folder","Server",folder)
local execution=object("Folder","Executions",folder)
local movement=object("Folder","Movement",folder)
local function asset(parent,name,id)
 local a=object("Animation",name,parent); a.AnimationId="rbxassetid://"..id; return a
end
asset(combat,"Strike","60001"); asset(execution,"Executing","60002")
asset(movement,"ClimbUp","60003"); asset(combat,"Multiple","60004")
asset(combat,"Interrupted","60005"); asset(combat,"Variable","60006")
now=20; dofile(path); ui=environment.CloverAutoParry
local learner=ui.learning
local function trial(id,t,pos,opts)
 opts=opts or {}; local tr=swing(t,id,otherAnimator)
 now=t+pos; tr.TimePosition=pos; tr:GetMarkerReachedSignal("HitWindow"):Fire("")
 if opts.duplicate then tr.KeyframeReached:Fire("HitWindow") end
 if opts.multiple then tr.TimePosition=pos+.1; tr:GetMarkerReachedSignal("HitWindow"):Fire("") end
 now=t+.9; tr.TimePosition=opts.incomplete and .5 or .9; tr.IsPlaying=false; tr.Stopped:Fire()
end
local initial=downs
trial("60001",21,.4)
check(not learner:position("60001") and downs==initial,"first unknown observation learns without sending input")
trial("60001",23,.4,{duplicate=true})
check(learner:position("60001")==.4 and #learner.model.rows["60001"].samples==2,"two complete observations qualify; paired signals deduplicated")
click("Auto parry"); tr=swing(25,"60001",otherAnimator); tr.TimePosition=.29; beat(25.29)
check(downs==initial+1 and ui.status:find("learned combat marker",1,true),"learned player timing produces F without configuring target or delay")
beat(25.5)
tr=swing(27,"60001",otherAnimator); tr.Speed=2; tr.TimePosition=.17; beat(27.085)
check(downs==initial+2,"learned prediction follows playback speed")
beat(27.3)
tr=swing(29,"60001",otherAnimator); tr.TimePosition=.41; beat(29.41)
check(downs==initial+2,"passed marker is discarded")
tr=swing(31,"60001",otherAnimator); tr.TimePosition=.29
another:FindFirstChild("HumanoidRootPart").Position=position(30); beat(31.29)
another:FindFirstChild("HumanoidRootPart").Position=position(4)
check(downs==initial+2,"fixed proximity rechecked at trigger time")
check(ui.status:find("reason=out of range distance=30.00 range=8.00 pos=0.2900 speed=1.000",1,true),"range skip exports actual distance, limit and playback state")
tr=swing(33,"60001",otherAnimator); tr.TimePosition=.3; beat(33.001)
check(downs==initial+2,"seek cancels learned prediction")
click("Auto parry")
trial("60002",35,.4); trial("60003",37,.4)
check(not learner.model.rows["60002"] and not learner.model.rows["60003"],"execution and movement never become attacks")
trial("60004",39,.3,{multiple=true}); check(learner.model.rows["60004"].blocked,"multiple hit windows remain blocked")
trial("60005",41,.3,{incomplete=true}); check(not learner:position("60005"),"interrupted playback cannot qualify")
trial("60006",43,.3); trial("60006",45,.5)
check(not learner:position("60006"),"inconsistent timings remain inactive")
local previous=ui; now=47; dofile(path); ui=environment.CloverAutoParry
check(not previous.alive and ui.learning:position("60001")==.4,"rerun cleans old listeners and retains learned rows")
check(ui.discovery.enabled and ui.learning.enabled,"rerun re-enables permanent background features")
beat(49.1); local generation=ui.audit.generation
beat(350); check(ui.audit.generation==generation+1,"audit repeats automatically after five minutes")
ui:Unload(); local last=downs; tr:GetMarkerReachedSignal("HitWindow"):Fire(""); beat(351)
check(downs==last and not ui.discovery.enabled and ui.learning.activeCount==0,"unload stops all background subscriptions")

-- Current-version bundled candidates remain subordinate to local validation.
environment.CloverParryOptions.useBundledProfiles=true; game.JobId="bundle-test"; game.PlaceVersion=68598
now=400; dofile(path); ui=environment.CloverAutoParry; learner=ui.learning
check(math.abs(learner:position("86722279259826")-.5041664243)<.000001,"bundle is available for the captured game version")
local base=downs; click("Auto parry"); tr=swing(401); tr.TimePosition=.32; beat(401.32)
check(downs==base,"bundle overrides earlier guard preset")
tr.TimePosition=.39; beat(401.39); check(downs==base+1,"bundled marker drives prediction")
beat(401.6); click("Auto parry")
trial("86722279259826",403,.55)
click("Auto parry"); tr=swing(404); tr.TimePosition=.32; beat(404.32)
check(downs==base+1,"collecting local profile blocks old preset fallback")
click("Auto parry"); trial("86722279259826",405,.55)
click("Auto parry"); tr=swing(407); tr.TimePosition=.44; beat(407.44)
check(downs==base+2,"ready local profile overrides bundled timing")
beat(407.6); click("Auto parry"); trial("86722279259826",409,.7)
click("Auto parry"); tr=swing(411); tr.TimePosition=.32; beat(411.32)
check(downs==base+2,"variable local profile cannot fall back to preset")
ui:Unload()
-- Attack markers follow the same classified, complete-playback pipeline as HitWindow.
game.JobId="attack-marker-tests"; environment.CloverParryOptions.useBundledProfiles=false
local npcs=object("Folder","NPCS",folder); local wolves=object("Folder","Wolf",npcs)
asset(wolves,"Bite Pounce","124572427631698")
asset(wolves,"Tail Sweep","73807165586659")
for _,id in ipairs({"61001","61002","61003","61004","61005","61006","61007"}) do asset(combat,"Strike"..id,id) end
now=500; dofile(path); ui=environment.CloverAutoParry; learner=ui.learning
local function attackTrial(id,t,pos,opts)
 opts=opts or {}; local tr=animation(id); tr.Length=opts.length or 1.7; tr.Speed=opts.speed or 1
 tr.Looped=opts.loop or false; now=t; otherAnimator.AnimationPlayed:Fire(tr)
 now=t+pos/tr.Speed; tr.TimePosition=pos
 if opts.keyframe then tr.KeyframeReached:Fire("Attack") else tr:GetMarkerReachedSignal("Attack"):Fire("") end
 if opts.pair then tr.KeyframeReached:Fire("Attack") end
 if opts.alias then tr:GetMarkerReachedSignal("HitWindow"):Fire("") end
 if opts.repeatSignal then tr:GetMarkerReachedSignal("Attack"):Fire("") end
 if opts.separate then tr.TimePosition=pos+.15; tr:GetMarkerReachedSignal("HitWindow"):Fire("") end
 now=t+tr.Length/tr.Speed; tr.TimePosition=opts.incomplete and pos or tr.Length; tr.IsPlaying=false; tr.Stopped:Fire()
 return tr
end
local baseAttack=downs
attackTrial("124572427631698",501,.9583); check(not learner:position("124572427631698"),"first Bite Pounce sample remains collecting")
attackTrial("124572427631698",504,.9625)
check(math.abs(learner:position("124572427631698")-.9583)<.00001,"two Attack-marked Bite Pounces qualify")
attackTrial("73807165586659",507,1.0038,{speed=1.1}); attackTrial("73807165586659",510,1.0038,{speed=1.1})
check(learner:position("73807165586659")==1.0038,"Tail Sweep retains animation position rather than wall-clock time")
click("Auto parry"); tr=swing(513,"124572427631698",otherAnimator); tr.Length=1.7; tr.TimePosition=.83; beat(513.83)
check(downs==baseAttack,"Bite Pounce waits until learned lead threshold")
tr.TimePosition=.85; beat(513.85); check(downs==baseAttack+1,"Bite Pounce sends F on a later Attack-learned playback")
beat(514)
tr=swing(516,"73807165586659",otherAnimator); tr.Length=1.7; tr.Speed=1.1; tr.TimePosition=.88; beat(516.8)
check(downs==baseAttack+2,"Tail Sweep prediction accounts for playback speed")
beat(517); click("Auto parry")
attackTrial("60002",518,.4); attackTrial("60002",521,.4)
attackTrial("60003",524,.4); attackTrial("60003",527,.4)
check(not learner.model.rows["60002"] and not learner.model.rows["60003"],"Attack markers cannot enable executions or movement")
attackTrial("61999",530,.4); check(not learner.model.rows["61999"],"unclassified Attack animation remains excluded")
attackTrial("61001",533,.4,{incomplete=true}); attackTrial("61001",536,.4,{incomplete=true})
check(not learner:position("61001"),"interrupted Attack playback cannot qualify")
attackTrial("61002",539,.4,{loop=true}); check(not learner.model.rows["61002"],"looping Attack playback remains excluded")
attackTrial("61003",542,.4,{pair=true,alias=true}); attackTrial("61003",545,.4,{pair=true,alias=true})
check(learner:position("61003")==.4 and #learner.model.rows["61003"].samples==2,"coincident Attack/HitWindow/keyframe signals count once per playback")
attackTrial("61004",548,.4,{pair=true,repeatSignal=true})
check(learner.model.rows["61004"].blocked,"repeated signal remains ambiguous even after a keyframe pair")
attackTrial("61005",551,.4,{separate=true})
check(learner.model.rows["61005"].blocked,"separated Attack and HitWindow impacts block the profile")
attackTrial("61006",554,.4,{keyframe=true}); attackTrial("61006",557,.4,{keyframe=true})
check(learner:position("61006")==.4,"named Attack keyframes are supported")
attackTrial("61007",560,.4); attackTrial("61007",563,.7)
check(not learner:position("61007"),"variable Attack timing remains inactive")
local payload=ui.storage:batch(learner.model.rows,function(id) return learner:allowed(id) end)
local reported={}; for _,row in ipairs(payload.profiles) do reported[row.id]=true end
check(reported["124572427631698"] and reported["73807165586659"],"ready Attack profiles enter ordinary timing-report queue")
check(learner:export():find("name=Attack",1,true),"learning log identifies the observed Attack marker")
-- Lifecycle diagnostics must explain missing signals without qualifying missing data.
local function logs() return table.concat(learner.logs,"\n") end
local missing=animation("61001"); missing.Length=0; missing.Ended=signal()
now=570; otherAnimator.AnimationPlayed:Fire(missing)
check(logs():find("signal=marker:Attack ok=true",1,true) and logs():find("signal=Ended ok=true",1,true),"signal subscription success is explicit")
missing.TimePosition=.3; beat(570.3)
check(logs():find("TRACK_CHECK",1,true) and logs():find("length=0.0000",1,true),"zero-length track receives bounded delayed snapshot")
missing.Length=1.7; missing.TimePosition=1.3; beat(571.3)
check(logs():find("TRACK_LOADED",1,true),"delayed asset length becoming available is recorded")
missing.IsPlaying=false; beat(571.4)
check(logs():find("TRACK_PLAYING_CHANGED",1,true),"playing transition is visible even without Stopped")
missing.Ended:Fire()
check(logs():find("TRACK_ENDED",1,true),"Ended callback is recorded without fabricating a sample")
beat(583)
check(logs():find("TRACK_EXPIRED",1,true) and logs():find("reason=timeout",1,true) and not learner.active[missing] and not learner:position("61001"),"missing marker and Stopped expire without learning")
local failed=animation("61002"); failed.GetMarkerReachedSignal=function() error("mock marker subscription failure") end
now=585; otherAnimator.AnimationPlayed:Fire(failed)
check(logs():find("signal=marker:Attack ok=false",1,true) and logs():find("mock marker subscription failure",1,true),"subscription failures include signal and error")
failed.TimePosition=.9; failed.IsPlaying=false; failed.Stopped:Fire()
check(logs():find("NO_TIMING_MARKER",1,true) and logs():find("TRACK_STOP",1,true),"completed playback without markers explains rejection")
local reused=swing(587,"61001",otherAnimator); now=587.1; otherAnimator.AnimationPlayed:Fire(reused)
check(logs():find("TRACK_REUSED",1,true),"reused track listener replacement is reported")
check(learner:export():find("TRACK_AT_EXPORT",1,true),"copy logs snapshots active tracks before timeout")
local late=animation("61001"); late.TimePosition=.2; otherAnimator.AnimationPlayed:Fire(late)
check(logs():find("reason=priority_or_late_start",1,true),"late learner attachment rejection is explicit")
for i=1,305 do learner:note("bounded diagnostic "..i) end
check(#learner.logs==300 and learner.overwritten>=5,"diagnostics remain bounded and count overwritten lines")
ui:Unload()
game.JobId="asset-fallback-test"; now=600; dofile(path); ui=environment.CloverAutoParry; learner=ui.learning
learner.assetQueue={}
learner.assets['124572427631698']={status='ready',position=.957916677,length=1.7333333}
learner.assets['73807165586659']={status='ready',position=1.003749967,length=1.6666667}
check(select(2,learner:position('124572427631698'))=='asset marker',"asset marker provenance is separate from live learning")
local oldName=another.Name; another.Name='Wolf'
-- another is a Player's rig: never give it the NPC allowance.
another:FindFirstChild('HumanoidRootPart').Position=position(9.63)
baseAttack=downs; click('Auto parry')
tr=swing(601,'124572427631698',otherAnimator); tr.TimePosition=.85; beat(601.85)
check(downs==baseAttack and ui.status:find('range=8.00',1,true),"players do not inherit wolf range")
another.Name=oldName; another:FindFirstChild('HumanoidRootPart').Position=position(4)
local wolf,wa=rig('Wolf',9.63); workspace.DescendantAdded:Fire(wa)
tr=swing(603,'124572427631698',wa); tr.Length=0; tr.TimePosition=.85; beat(603.85)
check(downs==baseAttack+1 and ui.status:find('source=asset marker',1,true),"zero-length NPC playback can use verified asset marker at captured 9.63-stud distance")
beat(604)
wolf:FindFirstChild('HumanoidRootPart').Position=position(12.1)
tr=swing(605,'73807165586659',wa); tr.Speed=1.1; tr.TimePosition=.88; beat(605.8)
check(downs==baseAttack+1 and ui.status:find('range=12.00',1,true),"wolf allowance remains bounded at twelve studs")
learner.assets['60002']={status='ready',position=.4}; learner.assets['60003']={status='ready',position=.4}
check(not learner:position('60002') and not learner:position('60003'),"asset metadata never bypasses execution or movement filters")
learner:sample('124572427631698',.96,false)
check(not learner:position('124572427631698'),"collecting live samples suppress asset fallback")
check(not learner.model.rows['73807165586659'],"metadata fallback does not fabricate completed-playback samples")
ui:Unload()
print("PASS: "..count.." auto-parry offline assertions. Combat success unverified.")
