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
dofile(path)
local ui = environment.CloverAutoParry
click("Targets:") -- Exercise the existing guard-only regression mode explicitly.
check(not ui.enabled and downs == 0, "actual GUI starts OFF")
click("Test F"); beat(.9); check(downs == 0, "test button waits for focus return")
beat(1); check(downs == 1 and ui.held, "test button sends F")
beat(1.13); check(ups == 1 and not ui.held, "heartbeat releases F after configured hold")
click("Auto parry")
local tr=swing(2); tr.TimePosition=.32; beat(2.32)
check(downs == 2 and ui.attempts == 2, "guard animation drives real script scheduler/input")
click("Auto parry"); check(ups == 2 and not ui.held, "OFF releases a held synthetic F")
click("Auto parry"); local heavy=swing(3, "10017994824"); heavy.TimePosition=.32; beat(3.32)
check(downs == 2, "unmapped heavy excluded")
local reaction=swing(4, "10059485766"); reaction.TimePosition=.32; beat(4.32)
check(downs == 2, "reaction animation excluded")
tr=swing(5, nil, ownAnimator); tr.TimePosition=.32; beat(5.32)
check(downs == 2, "own attacks excluded")
tr=swing(6, nil, otherAnimator); tr.TimePosition=.32; beat(6.32)
check(downs == 2, "guard default excludes other players")
click("Targets:"); click("Auto parry")
tr=swing(7, nil, otherAnimator); tr.TimePosition=.32; beat(7.32)
check(downs == 3, "optional any-rig mode still requires mapped ID")
input.WindowFocusReleased:Fire()
check(not ui.enabled and not ui.held and ups == 3, "focus loss switches OFF and releases F")
input.WindowFocused:Fire(); click("Auto parry")
now=8; input.InputBegan:Fire({KeyCode="F"}, false)
tr=swing(8.1); tr.TimePosition=.32; beat(8.42)
check(downs == 3, "manual F also reserves cooldown")
tr=swing(9); tr.TimePosition=.32; input.textFocus={}; beat(9.32); input.textFocus=nil
check(downs == 3, "focused text box suppresses input and clears jobs")
tr=swing(10); tr.TimePosition=.32; throwDown=true; beat(10.32); throwDown=false
check(not ui.enabled and not ui.held and ups == 4, "input exception stops and attempts release")
click("Copy attempt logs")
check(clipboard:find("NOT confirmed successes", 1, true) and clipboard:find("F attempted", 1, true), "copy exports attempts without claiming parry success")
setclipboard=nil; click("Copy attempt logs")
check(ui.export and ui.export.Text:find("CLOVER AUTO PARRY",1,true), "clipboard absence provides selectable export")
ui.export.FocusLost:Fire(); check(ui.export == nil, "manual export closes on focus loss")
click("Auto parry"); tr=swing(11); tr.TimePosition=.32; beat(11.32)
throwUp=true; click("Unload")
check(ui.alive and ui.held, "release failure retains cleanup controls")
local loaded=pcall(dofile,path)
check(not loaded and environment.CloverAutoParry == ui, "rerun cannot stack instance after release failure")
throwUp=false; beat(11.5); click("Unload")
check(not ui.alive and ui.gui.Destroyed and environment.CloverAutoParry == nil, "unload disconnects and removes panel")
local oldDowns=downs; tr=swing(12); tr.TimePosition=.32; beat(12.32)
check(downs == oldDowns, "unloaded subscriptions do not send input")
dofile(path); local priorUI=environment.CloverAutoParry; dofile(path)
check(not priorUI.alive and priorUI.gui.Destroyed, "normal rerun cleans previous instance")
environment.CloverAutoParry:Unload()
keypress=nil; keyrelease=nil; dofile(path); click("Test F"); beat(14)
check(downs == oldDowns and not environment.CloverAutoParry.held, "missing input APIs leave GUI functional without input")
environment.CloverAutoParry:Unload()

-- Exercise discovery on the actual delivered script with no input backend.
dofile(path); ui=environment.CloverAutoParry
local recorder=ui.discovery
check(not recorder.enabled, "discovery starts off independently")
swing(20, "99991", otherAnimator)
check(#recorder.order == 0, "discovery OFF collects no animations")
click("Discovery / audit"); click("Recording:")
beat(20.1)
tr=swing(21, "99991", otherAnimator)
check(#recorder.order == 1 and recorder.catalog["PLAYER:99991"].count == 1 and not ui.enabled,
    "unknown player animation captured while auto OFF and guard target mode active")
check(recorder:export():find("UNKNOWN id=99991",1,true) and recorder:export():find("kind=PLAYER",1,true),
    "export distinguishes unknown ID and player actor")
tr.TimePosition=.23; now=21.23; input.InputBegan:Fire({KeyCode="F"}, false)
input.InputEnded:Fire({KeyCode="F"})
check(recorder:export():find("CONTEXT event=OBSERVED_F_DOWN play=1",1,true)
    and recorder:export():find("OBSERVED_F_UP",1,true), "manual F gets occurrence/timing context")
tr.TimePosition=.4; now=21.4; tr.markers.Hit:Fire("weapon"); tr.KeyframeReached:Fire("Contact")
check(recorder:export():find("MARKER:Hit play=1",1,true) and recorder:export():find("KEYFRAME play=1",1,true),
    "optional named marker and keyframe events recorded")
own:FindFirstChildOfClass("Humanoid").Health=90; beat(21.45)
check(recorder:export():find("SELF_HEALTH_DROP amount=10.000",1,true)
    and recorder:export():find("association=unconfirmed",1,true), "sampled health loss is correlated but not attributed")
tr.Stopped:Fire()
check(recorder.activeCount == 0 and recorder:export():find("STOP play=1",1,true), "stop disconnects per-track listeners")
local eventCount=#recorder.events; tr.markers.Hit:Fire("late")
check(#recorder.events == eventCount, "stopped track callbacks no longer record")
tr=swing(22, "99991", otherAnimator)
check(#recorder.order == 1 and recorder.catalog["PLAYER:99991"].count == 2, "repeated player animation grouped automatically")
tr=swing(23, "99991", animator)
check(#recorder.order == 2, "same ID on NPC kept in separate scope")
local twin, twinAnimator=rig("Kamo Guard Respawnable", 5)
workspace.DescendantAdded:Fire(twinAnimator)
tr=swing(24, "99991", twinAnimator)
check(#recorder.order == 2 and recorder.actorIds[twin] ~= recorder.actorIds[guard],
    "streamed identical-name NPCs group by type but retain distinct actor tokens")
tr=swing(25, "86722279259826", animator)
check(recorder.catalog["NPC:Kamo Guard Respawnable:86722279259826"].known, "mapped IDs retained as timing reference")
local before=#recorder.order; swing(26,"11111",ownAnimator)
check(#recorder.order == before, "own animations excluded from discovery")
local far, farAnimator=rig("Far NPC",30); workspace.DescendantAdded:Fire(farAnimator)
swing(27,"22222",farAnimator)
check(#recorder.order == before, "discovery radius excludes distant actors")
click("Capture radius:"); swing(28,"22222",farAnimator)
check(#recorder.order == before+1 and recorder.radius == 40, "capture radius control expands collection")
local loop=animation("33333"); loop.Looped=true; animator.AnimationPlayed:Fire(loop)
check(not recorder.catalog["NPC:Kamo Guard Respawnable:33333"], "loops excluded by default")
click("Loops:"); animator.AnimationPlayed:Fire(loop)
check(recorder.catalog["NPC:Kamo Guard Respawnable:33333"] ~= nil, "optional loops captured when enabled")
local reused=animation("44444"); animator.AnimationPlayed:Fire(reused)
local active=recorder.activeCount; animator.AnimationPlayed:Fire(reused)
check(recorder.activeCount == active, "reused track replaces occurrence listeners")
now=28.1; local countBefore=#recorder.events; reused.markers.Damage:Fire("x")
check(#recorder.events == countBefore+1, "replayed track marker produces one event")
beat(40)
check(recorder.activeCount == 0 and #recorder.recent == 0, "expired observations release track and actor references")
setclipboard=function(v) clipboard=v end; click("Copy discovery logs")
check(clipboard:find("CLOVER DISCOVERY v5",1,true) and clipboard:find("CATALOG",1,true), "discovery copy exports summary and chronology")
input.InputBegan:Fire({KeyCode="F6"}, false)
check(not recorder.enabled and recorder.activeCount == 0, "F6 pauses discovery and disconnects its track listeners")
local pausedCount=#recorder.events; swing(41,"55555",animator)
check(#recorder.events == pausedCount and #recorder.order > 0, "pause retains data without collecting")
click("Clear discovery")
check(#recorder.order == 0 and #recorder.events == 0, "clear resets paused capture")
click("Recording:")
for i=1,301 do swing(42,"8"..i,animator) end
check(#recorder.order == 300 and recorder.catalogSkipped == 1, "catalog bound reports skipped observations")
check(recorder.activeCount == 64 and recorder.tracksSkipped == 237, "track-listener bound reports skipped observers")
for i=1,1600 do recorder:event("CAP_TEST "..i) end
check(#recorder.events == 1500 and recorder.dropped > 0 and recorder:export():find("overwritten_events=",1,true),
    "bounded chronology discloses overwritten events")
click("Clear discovery")
check(recorder.activeCount == 0 and #recorder.order == 0 and recorder.dropped == 0, "clear disconnects live listeners and resets limits")
local noMarkers=animation("66666"); noMarkers.GetMarkerReachedSignal=nil; noMarkers.KeyframeReached=nil
animator.AnimationPlayed:Fire(noMarkers)
check(recorder:export():find("MARKER_API_UNAVAILABLE",1,true) and recorder.catalog["NPC:Kamo Guard Respawnable:66666"],
    "missing optional marker APIs preserves basic capture")
click("Auto parry")
local malformed=animation("88888"); malformed.Length=nil; animator.AnimationPlayed:Fire(malformed)
check(ui.enabled and recorder:export():find("OBSERVE_ERROR",1,true), "capture error does not disable auto-parry processing")
tr=swing(43,"77777",animator); ui:Unload(); local atUnload=#recorder.events
tr.markers.Hit:Fire("after unload")
check(not recorder.enabled and recorder.activeCount == 0 and #recorder.events == atUnload,
    "unload cleans discovery callbacks as well as auto parry")

keypress=function() downs=downs+1 end; keyrelease=function() ups=ups+1 end
dofile(path); ui=environment.CloverAutoParry
click("Guard heavy trial:"); click("Auto parry")
tr=swing(50,"10017994824",animator); tr.TimePosition=.46; local beforeTrial=downs; beat(50.46)
check(downs == beforeTrial+1, "opt-in heavy trial triggers for Kamo Guard")
click("Targets:"); click("Auto parry")
tr=swing(51,"10017994824",otherAnimator); tr.TimePosition=.46; beat(51.46)
check(downs == beforeTrial+1, "heavy trial remains guard-only in any-rig target mode")
tr=swing(52,"9839904022",animator); tr.TimePosition=.3; beat(52.3)
check(downs == beforeTrial+1, "unclassified far-distance action is not enabled by heavy trial")
task={spawn=function(fn) fn() end, wait=function() end}
click("Scan shared timing data")
check(not ui.enabled and not ui.audit.running and #ui.audit.lines>0, "audit button stops automation and completes background scan")
click("Copy timing audit")
check(clipboard:find("ASSET_UNAVAILABLE",1,true) and clipboard:find("CLOVER TIMING AUDIT v5",1,true),
    "audit copy reports unavailable assets rather than claiming no markers")
ui.audit.markerNames["777"]={"StrikeNow"}
click("Recording:"); tr=swing(53,"777",animator); tr.markers.StrikeNow:Fire("test")
check(ui.discovery:export():find("MARKER:StrikeNow",1,true), "audit-discovered names are observed on subsequent playback")
local pendingTask
task.spawn=function(fn) pendingTask=fn end
click("Scan shared timing data"); click("Cancel timing scan"); pendingTask()
check(not ui.audit.running, "cancelled background generation cannot overwrite audit state")
ui:Unload()

-- v4 live-file learning pipeline with replicated animation classification.
local rs=object("ReplicatedStorage","ReplicatedStorage")
services.ReplicatedStorage=rs
local animationFolder=object("Folder","Animations",rs)
local combatFolder=object("Folder","Server",animationFolder)
local executionFolder=object("Folder","Executions",animationFolder)
local movementFolder=object("Folder","Movement",animationFolder)
local function asset(folder,name,id)
    local a=object("Animation",name,folder); a.AnimationId="rbxassetid://"..id; return a
end
asset(combatFolder,"NewStrike","60001")
asset(executionFolder,"SpearExecuting","60002")
asset(movementFolder,"ClimbUp","60003")
asset(combatFolder,"InterruptedStrike","60004")
asset(combatFolder,"SeekingStrike","60005")
asset(combatFolder,"MultiStrike","60006")
asset(combatFolder,"KeyframeStrike","60007")
asset(combatFolder,"LoopStrike","60008")
asset(combatFolder,"MixedAlias","60009"); asset(executionFolder,"Alias","60009")
asset(combatFolder,"UnstableStrike","60010")
now=70; dofile(path); ui=environment.CloverAutoParry
local learner=ui.learning
check(learner.enabled and not ui.enabled and learner.registryComplete,"learner starts ON with auto OFF and loads animation paths")
local function learnTrial(id,t,pos,options)
    options=options or {}
    local track=animation(id); track.Looped=options.loop or false
    now=t; otherAnimator.AnimationPlayed:Fire(track)
    now=t+pos; track.TimePosition=pos
    if options.keyframe then track.KeyframeReached:Fire("HitWindow") else track:GetMarkerReachedSignal("HitWindow"):Fire("") end
    if options.duplicate then track.KeyframeReached:Fire("HitWindow") end
    if options.multiple then track.TimePosition=pos+.15; track:GetMarkerReachedSignal("HitWindow"):Fire("") end
    now=t+.9; track.TimePosition=options.incomplete and .5 or .9; track.IsPlaying=false; track.Stopped:Fire()
    return track
end
local beforeLearning=downs
learnTrial("60001",71,.4)
check(not learner.model:position("60001") and downs==beforeLearning,"first playback observed without immediate F or activation")
learnTrial("60001",73,.4,{duplicate=true})
check(learner.model:position("60001")==.4 and #learner.model.rows["60001"].samples==2,"two full consistent playbacks become ready; marker/keyframe pair deduplicated")
click("Auto parry")
tr=swing(75,"60001",otherAnimator); tr.TimePosition=.27; beat(75.27)
check(downs==beforeLearning,"learned timing waits until lead threshold")
tr.TimePosition=.29; beat(75.29)
check(downs==beforeLearning+1 and ui.status:find("learned HitWindow",1,true),"ready new player attack uses learned timing on later playback")
beat(75.42); check(not ui.held,"learned input is released normally")
tr=swing(77,"60001",otherAnimator); tr.Speed=2; tr.TimePosition=.17; beat(77.085)
check(downs==beforeLearning+2,"learned lead is converted using live playback speed")
beat(77.3)
tr=swing(79,"60001",otherAnimator); tr.TimePosition=.41; beat(79.41)
check(downs==beforeLearning+2,"already-passed hit marker never produces a stale parry")
tr=swing(81,"60001",otherAnimator); tr.TimePosition=.29
another:FindFirstChild("HumanoidRootPart").Position=position(30); beat(81.29)
another:FindFirstChild("HumanoidRootPart").Position=position(4)
check(downs==beforeLearning+2,"learned parry rechecks distance at firing time")
tr=swing(82,"60001",otherAnimator); tr.TimePosition=.3; beat(82.001)
check(downs==beforeLearning+2,"playback seek cancels a queued learned parry")
click("Auto parry")
learnTrial("60002",83,.4); learnTrial("60002",85,.4)
check(not learner.model.rows["60002"],"execution with HitWindow never learned")
learnTrial("60003",87,.4); learnTrial("60003",89,.4)
check(not learner.model.rows["60003"],"movement with HitWindow never learned")
learnTrial("60004",91,.4,{incomplete=true}); learnTrial("60004",93,.4,{incomplete=true})
check(not learner.model:position("60004"),"interrupted playbacks do not establish timing")
tr=swing(95,"60005",otherAnimator); tr.TimePosition=.7; beat(95.01); tr:GetMarkerReachedSignal("HitWindow"):Fire("")
now=95.9; tr.TimePosition=.9; tr.Stopped:Fire()
check(not learner.model:position("60005"),"observed playback seek disqualifies sample")
learnTrial("60006",97,.25,{multiple=true})
check(learner.model.rows["60006"].blocked and not learner.model:position("60006"),"multiple HitWindows block automatic timing")
learnTrial("60007",99,.4,{keyframe=true}); learnTrial("60007",101,.4,{keyframe=true})
check(learner.model:position("60007")==.4,"named HitWindow keyframes can teach a classified combat move")
learnTrial("60008",103,.4,{loop=true})
check(not learner.model.rows["60008"],"looping combat clips excluded")
learnTrial("60009",105,.4)
check(not learner.model.rows["60009"],"execution alias overrides combat classification")
learnTrial("60010",107,.3); learnTrial("60010",109,.5)
check(learner.model.rows["60010"].status=="variable timing" and not learner.model:position("60010"),"inconsistent observations stay inactive")
click("Copy learned timings")
check(clipboard:find("CLOVER HITWINDOW LEARNING v5",1,true) and clipboard:find("NOT confirmed parry success",1,true),"learned export labels confidence without claiming success")
click("Auto parry"); tr=swing(111,"60001",otherAnimator)
click("Learning + learned timings:"); tr.TimePosition=.29; beat(111.29)
check(not ui.enabled and learner.activeCount==0 and downs==beforeLearning+2,"learning OFF stops queued learned attempts and listeners")
click("Learning + learned timings:")
local previous=ui; now=112; dofile(path); ui=environment.CloverAutoParry; learner=ui.learning
check(not previous.alive and learner.model:position("60001")==.4,"ready profiles survive rerun in same server session")
click("Auto parry"); tr=swing(113,"60001",otherAnimator)
asset(executionFolder,"NewAlias","60001"); learner:refresh(); tr.TimePosition=.29; beat(113.29)
check(downs==beforeLearning+2,"new excluded alias cancels a queued learned parry")
click("Clear learned timings")
check(next(learner.model.rows)==nil and not ui.enabled,"clear learned profiles also stops automation")
ui:Unload(); local exported=learner:export(); tr:GetMarkerReachedSignal("HitWindow"):Fire("")
check(learner:export()==exported and learner.activeCount==0,"unload removes learning callbacks")
game.JobId="another-server"; dofile(path); ui=environment.CloverAutoParry
check(next(ui.learning.model.rows)==nil,"server change starts with fresh profiles")
ui:Unload()
-- v5 bundled -> locally learned priority and no unsafe fallback after ambiguity.
environment.CloverParryOptions.useBundledProfiles=true
game.PlaceVersion=68598
now=130; dofile(path); ui=environment.CloverAutoParry; learner=ui.learning
check(math.abs(learner:position("86722279259826")-.5041664243)<.000001,"bundled captured marker available before first observation")
local v5Before=downs
click("Auto parry")
tr=swing(131); tr.TimePosition=.32; beat(131.32)
check(downs==v5Before,"bundled marker overrides old guard .31 preset")
tr.TimePosition=.39; beat(131.39)
check(downs==v5Before+1 and ui.status:find("source=bundled candidate",1,true),"bundled marker drives later prediction and logs source")
beat(131.6); click("Auto parry")
learnTrial("86722279259826",133,.55)
click("Auto parry"); tr=swing(134); tr.TimePosition=.32; beat(134.32)
check(downs==v5Before+1,"collecting local profile does not regress to old preset")
click("Auto parry"); learnTrial("86722279259826",135,.55)
check(learner:position("86722279259826")==.55 and ui.storage.dirty,"live completed observations replace bundled position and dirty cache")
click("Auto parry"); tr=swing(137); tr.TimePosition=.39; beat(137.39)
check(downs==v5Before+1,"new learned threshold replaces bundled threshold")
tr.TimePosition=.44; beat(137.44)
check(downs==v5Before+2 and ui.status:find("source=learned",1,true),"ready learned guard uses updated timing rather than preset")
beat(137.6); click("Auto parry")
learnTrial("86722279259826",139,.7)
click("Auto parry"); tr=swing(141); tr.TimePosition=.32; beat(141.32)
check(downs==v5Before+2 and not learner:position("86722279259826"),"variable learned profile cannot fall back to old preset or bundled timing")
check(not ui.storage.enabled,"distributed reporting defaults OFF")
click("Share timing candidates:"); check(not ui.storage.enabled and ui.storage.status:find("unavailable",1,true),"unconfigured endpoint cannot claim reporting ON")
ui.storage.available=true -- isolate the GUI consent behavior from the HTTP adapter
click("Share timing candidates:"); check(ui.storage.enabled,"explicit share toggle enables candidate reporting")
click("Share timing candidates:"); check(not ui.storage.enabled,"share toggle stops future reporting")
ui:Unload()
print("PASS: " .. count .. " auto-parry offline assertions. Roblox/Madium success unverified.")
