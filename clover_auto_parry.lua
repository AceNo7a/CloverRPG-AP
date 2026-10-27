-- Clover auto parry v6.1: experimental HitWindow/Attack learning for later encounters.
-- Run this entire file. Starts OFF. No remote hooks or packet replay.
-- Automatic reporting sends numeric timing candidates only; no remote code is fetched.
-- Manual F timings are starting estimates, not measured server parry windows.
-- Learned positions take priority. Bundled candidates remain unverified for parry success.

-- BEGIN TESTABLE CORE
local function newScheduler()
    local s = { pending = {}, nextAllowed = 0 }
    function s:clear() self.pending = {} end
    function s:add(track, actor, id, target, now, position)
        -- Ignore already-late playback notifications instead of sending a stale F.
        if position > target + 0.08 then if self.onSkip then self.onSkip({id=id},"late notification") end; return false end
        self.pending[track] = { actor = actor, id = id, target = target, created = now }
        return true
    end
    function s:step(now, cooldown, inspect, press)
        local choice, earliest
        for track, item in pairs(self.pending) do
            local valid, position, speed, inRange = inspect(track, item)
            local function skipped(reason) if self.onSkip then self.onSkip(item,reason) end end
            if not valid or now - item.created > (item.learned and 12 or 3)
                or (item.hitPosition and position >= item.hitPosition)
                or position > item.target + 0.08 * math.max(speed, 1) then
                self.pending[track] = nil; skipped(not valid and "invalid/stopped/profile changed" or "expired/passed timing")
            elseif speed > 0 and position >= item.target then
                self.pending[track] = nil
                if inRange and (not earliest or item.created < earliest) then
                    if choice and self.onSkip then self.onSkip(choice,"simultaneous attack") end
                    choice, earliest = item, item.created
                else skipped(inRange and "simultaneous attack" or "out of range") end
            end
        end
        -- A missed opportunity during cooldown is discarded, never delayed/spammed.
        if choice and now >= self.nextAllowed then
            if press(choice) then
                self.nextAllowed = now + cooldown
                return choice
            elseif self.onSkip then self.onSkip(choice,"input unavailable") end
        elseif choice and self.onSkip then self.onSkip(choice,"cooldown") end
    end
    return s
end
-- END TESTABLE CORE

-- BEGIN TESTABLE LEARNING
local function classifyAnimationPaths(paths)
    local combat = false
    local denied = { executions=true, execution=true, movement=true, hit=true, blocks=true,
        misc=true, emotes=true, items=true, grimoireanimations=true, rigs=true,
        parrys=true, idles=true, stagger=true, broom=true }
    for _, path in ipairs(paths or {}) do
        local parts = {}; for part in string.lower(path):gmatch("[^/]+") do parts[#parts+1] = part end
        for _, part in ipairs(parts) do
            if denied[part] then return false, "excluded path: " .. path end
        end
        local leaf = parts[#parts] or ""
        for _, word in ipairs({"idle", "walk", "execut", "climb", "victim"}) do
            if leaf:find(word,1,true) then return false, "excluded name: " .. path end
        end
        for _, word in ipairs({"execut", "climb", "idle", "walk", "run", "swim", "crouch", "block", "parr", "equip", "sheathe", "roll", "dodge", "carry", "carried", "flinch", "downed", "stun", "landing", "jump", "stagger", "gravstep"}) do
            -- Avoid treating words embedded in attacks (e.g. Rushing) as locomotion.
            if leaf:sub(1,#word) == word then return false, "excluded name: " .. path end
        end
        if leaf == "mode" then return false, "excluded mode animation" end
        local roots={server=true,combat=true,skills=true,npcs=true,crit=true,aerials=true,uppercuts=true,magic=true}
        if roots[parts[1]] then combat = true end
    end
    return combat, combat and "combat path" or "no recognized combat path"
end
local function newHitWindowModel(rows)
    local model = { rows = rows or {} }
    function model:sample(id, position, multiple)
        local row = self.rows[id]
        if not row then
            local n=0; for _ in pairs(self.rows) do n=n+1 end
            if n >= 256 then return "profile limit" end
            row = { samples = {}, status = "collecting" }; self.rows[id] = row
        end
        if multiple then row.status = "multiple timing markers"; row.blocked = true; return row.status end
        if row.blocked then return row.status end
        if type(position) ~= "number" or position ~= position or position < .03 or position > 8 then return "invalid position" end
        row.samples[#row.samples+1] = position
        if #row.samples > 5 then table.remove(row.samples,1) end
        local sorted = {}; for _, v in ipairs(row.samples) do sorted[#sorted+1]=v end; table.sort(sorted)
        row.position = sorted[math.ceil(#sorted/2)]
        row.spread = sorted[#sorted] - sorted[1]
        row.status = #sorted < 2 and "collecting" or (row.spread <= .04 and "ready" or "variable timing")
        return row.status
    end
    function model:position(id)
        local row = self.rows[id]
        if row and row.status == "ready" and not row.blocked then return row.position end
    end
    return model
end
-- END TESTABLE LEARNING

-- BEGIN TESTABLE PROFILE SUPPORT
-- JSON data only. Never loads code from the cache or reporting endpoint.
local function newProfileSupport(options)
    local p = { dirty=false, busy=false, nextSave=0, nextReport=0, failures=0,
        sent={}, enabled=false, available=type(options.send)=="function",
        status="Reporting OFF", diskStatus="Session only" }
    local function finite(v, lo, hi)
        return type(v)=="number" and v==v and v>=lo and v<=hi
    end
    local function validId(id) return type(id)=="string" and #id<=20 and id:match("^%d+$") end
    function p:restore(data, rows, now)
        if type(data)~="table" or data.schema~=1 or data.place~=options.place
            or data.placeVersion~=options.placeVersion or type(data.rows)~="table" then return false end
        local count=0
        for id, saved in pairs(data.rows) do
            count=count+1; if count>256 then break end
            if validId(id) and type(saved)=="table" and type(saved.samples)=="table"
                and finite(saved.updatedAt,now-7*86400,now+60) and #saved.samples<=5 then
                local valid=true
                for _,v in ipairs(saved.samples) do if not finite(v,.03,8) then valid=false end end
                if valid then
                    if not rows[id] then
                        local model=newHitWindowModel()
                        for _,v in ipairs(saved.samples) do model:sample(id,v,false) end
                        if saved.blocked==true then model:sample(id,.1,true) end
                        if model.rows[id] then rows[id]=model.rows[id]; rows[id].updatedAt=saved.updatedAt end
                    end
                    if type(saved.sent)=="string" and #saved.sent<100 then self.sent[id]=saved.sent end
                end
            end
        end
        return true
    end
    function p:pack(rows)
        local out={schema=1,place=options.place,placeVersion=options.placeVersion,rows={}}
        local count=0
        for id,row in pairs(rows) do
            if count>=256 then break end
            if validId(id) then
                local samples={}; for _,v in ipairs(row.samples or {}) do samples[#samples+1]=v end
                out.rows[id]={samples=samples,blocked=row.blocked==true,
                    updatedAt=row.updatedAt or options.time(),sent=self.sent[id]}
                count=count+1
            end
        end
        return out
    end
    function p:load(rows)
        if not options.read or not options.decode then return end
        local ok,data=pcall(function()
            local raw=options.read(); assert(type(raw)=="string" and #raw<=262144)
            return options.decode(raw)
        end)
        if ok and self:restore(data,rows,options.time()) then self.diskStatus="Local cache loaded"
        else self.diskStatus="No valid cache; learning locally" end
    end
    function p:save(rows)
        if not options.write or not options.encode then self.diskStatus="Session only: file API unavailable"; return false end
        local ok=pcall(function() options.write(options.encode(self:pack(rows))) end)
        self.diskStatus=ok and "Saved locally" or "Cache save failed; session retained"
        if ok then self.dirty=false end
        return ok
    end
    function p:fingerprint(row)
        -- Repeated observations/jitter within 10 ms do not generate new reports.
        return row.status..":"..math.floor((row.position or 0)*100+.5)
    end
    function p:batch(rows, allowed)
        local ids={}; for id in pairs(rows) do ids[#ids+1]=id end; table.sort(ids)
        local out,keys={},{}
        for _,id in ipairs(ids) do
            local row=rows[id]
            if allowed(id) and #row.samples>=2 and row.status=="ready" and not row.blocked then
                local key=self:fingerprint(row)
                if self.sent[id]~=key then
                    out[#out+1]={id=id,marker=row.position,spread=row.spread,samples=#row.samples}
                    keys[id]=key
                    if #out>=6 then break end
                end
            end
        end
        return {schema=1,version=6,place=options.place,placeVersion=options.placeVersion,
            evidence="consistent combat marker; parry success unverified",profiles=out},keys
    end
    function p:tick(now, rows, allowed)
        if self.busy then return end
        if not options.spawn then return end
        local saveDue=self.dirty and now>=self.nextSave
        local reportDue=self.enabled and now>=self.nextReport
        if not saveDue and not reportDue then return end
        self.busy=true
        options.spawn(function()
            local ok=pcall(function()
                if self.dirty and now>=self.nextSave then self.nextSave=now+5; self:save(rows) end
                if not self.enabled or now<self.nextReport or not options.alive() then return end
                self.nextReport=now+60
                local payload,keys=self:batch(rows,allowed)
                if #payload.profiles==0 then self.status="Reporting ON: no new ready timings"; return end
                if not options.send then self.status="No reporting endpoint/request API"; return end
                local success,code,retry=pcall(options.send,payload)
                if success and type(code)=="number" and code>=200 and code<300 then
                    for id,key in pairs(keys) do self.sent[id]=key end
                    self.failures=0; self.dirty=true; self.status="Sent "..#payload.profiles.." timing candidates"
                    self:save(rows)
                else
                    self.failures=math.min(self.failures+1,5)
                    local delay=math.max(60,math.min(86400,tonumber(retry) or 0),30*2^self.failures)
                    self.nextReport=now+delay
                    self.status="Report failed; retry in "..math.ceil(delay).."s"
                end
            end)
            if not ok then self.status="Reporting/cache error; learning continues"; self.nextReport=now+60 end
            self.busy=false
        end)
    end
    return p
end
-- END TESTABLE PROFILE SUPPORT


-- BEGIN TESTABLE AUDIT
-- Reads replicated metadata only; never requires modules, calls remotes or reads Source.
local function runTimingAudit(options)
    local result = { lines = {}, markerNames = {}, assets = {}, visited = 0, clipped = 0, errors = 0 }
    local seenAssets, seenObjects, markerAssets = {}, {}, {}
    local function safe(v) return tostring(v):gsub("[%c]", " "):sub(1, 160) end
    local function emit(line)
        if #result.lines < 1800 then result.lines[#result.lines + 1] = line else result.clipped = result.clipped + 1 end
    end
    local words = { "attack", "combat", "weapon", "parry", "block", "hitbox", "windup", "swing", "timing", "damage", "recovery", "startup", "activeframe", "animation" }
    local function relevant(name)
        name = string.lower(name)
        for _, word in ipairs(words) do if string.find(name, word, 1, true) then return true end end
        return false
    end
    local function asset(id)
        id = tostring(id):match("%d+")
        if id and not seenAssets[id] then seenAssets[id] = true; result.assets[#result.assets + 1] = id end
    end
    local function path(object)
        local parts, steps = {}, 0
        while object and steps < 30 do
            table.insert(parts, 1, safe(object.Name)); object = object.Parent; steps = steps + 1
        end
        return table.concat(parts, ".")
    end
    emit("CLOVER TIMING AUDIT v6 | metadata clues, NOT verified combat timings")
    emit("Module paths are names only; module code was not executed or inspected. Attribute units/semantics are unknown.")
    for _, id in ipairs(options.ids or {}) do asset(id) end
    local queue = {}; for _, root in ipairs(options.roots or {}) do queue[#queue + 1] = root end
    local index, rejectedChildren = 1, 0
    while index <= #queue and result.visited < 15000 and options.alive() do
        local object = queue[index]; index = index + 1
        if not seenObjects[object] then
            seenObjects[object] = true; result.visited = result.visited + 1
            local ok, err = pcall(function()
                local location = path(object)
                local context = relevant(location)
                local class = object.ClassName
                if class == "Animation" then
                    asset(object.AnimationId); emit("ANIMATION path=" .. location .. " id=" .. safe(object.AnimationId))
                elseif class == "ModuleScript" and context then
                    emit("MODULE_PATH_ONLY " .. location)
                elseif (class == "NumberValue" or class == "IntValue" or class == "BoolValue" or class == "StringValue") and context then
                    emit("VALUE path=" .. location .. " value=" .. safe(object.Value))
                end
                local count = 0
                for key, value in pairs(object:GetAttributes()) do
                    local valueType = type(value)
                    if (context or relevant(tostring(key))) and (valueType == "number" or valueType == "boolean" or valueType == "string") then
                        count = count + 1
                        if count <= 32 then emit("ATTRIBUTE path=" .. location .. " key=" .. safe(key) .. " value=" .. safe(value))
                        else result.clipped = result.clipped + 1 end
                    end
                end
                for _, child in ipairs(object:GetChildren()) do
                    if #queue < 15000 then queue[#queue + 1] = child else rejectedChildren = rejectedChildren + 1 end
                end
            end)
            if not ok then result.errors = result.errors + 1; emit("OBJECT_READ_ERROR " .. safe(err)) end
            if result.visited % 100 == 0 then options.pause() end
        end
    end
    emit(string.format("OBJECTS visited=%d unvisited_queue=%d children_not_queued=%d", result.visited, #queue - index + 1, rejectedChildren))
    for i, id in ipairs(result.assets) do
        if i > 24 or not options.alive() then break end
        options.pause()
        local clip
        local ok, err = pcall(function()
            clip = options.fetch(id)
            if not options.alive() then return end
            if not clip:IsA("KeyframeSequence") then
                emit("ASSET_UNINSPECTED id=" .. id .. " type=" .. safe(clip.ClassName)); return
            end
            local frames = clip:GetKeyframes()
            if #frames == 0 then
                emit("ASSET_INCONCLUSIVE id=" .. id .. " reason=empty_keyframes"); return
            end
            table.sort(frames, function(a, b) return a.Time < b.Time end)
            local markerCount, namedFrames, names = 0, 0, {}
            result.markerNames[id] = {}
            for n, frame in ipairs(frames) do
                if n > 500 then result.clipped = result.clipped + #frames - 500; break end
                if frame.Name ~= "Keyframe" and frame.Name ~= "" then
                    namedFrames = namedFrames + 1
                    emit("ASSET_KEYFRAME id=" .. id .. " time=" .. tostring(frame.Time) .. " name=" .. safe(frame.Name))
                end
                for m, marker in ipairs(frame:GetMarkers()) do
                    if m > 64 then result.clipped = result.clipped + 1; break end
                    markerCount = markerCount + 1
                    emit("ASSET_MARKER id=" .. id .. " time=" .. tostring(frame.Time) .. " name=" .. safe(marker.Name) .. " value=" .. safe(marker.Value))
                    if not names[marker.Name] and #result.markerNames[id] < 64 then
                        names[marker.Name] = true; table.insert(result.markerNames[id], marker.Name)
                    end
                    markerAssets[marker.Name] = markerAssets[marker.Name] or {}
                    markerAssets[marker.Name][id] = true
                end
            end
            emit("ASSET_OK id=" .. id .. " frames=" .. #frames .. " inspected_markers=" .. markerCount .. " named_frames=" .. namedFrames)
        end)
        if clip then pcall(function() clip:Destroy() end) end
        if not ok then result.errors = result.errors + 1; emit("ASSET_UNAVAILABLE id=" .. id .. " error=" .. safe(err)) end
    end
    for name, ids in pairs(markerAssets) do
        local list = {}; for id in pairs(ids) do list[#list + 1] = id end; table.sort(list)
        if #list >= 2 then emit("SHARED_MARKER_CANDIDATE name=" .. safe(name) .. " ids=" .. table.concat(list, ",")) end
    end
    -- Always preserve the limitation summary, even when the detail limit is hit.
    result.lines[#result.lines + 1] = string.format("END cancelled=%s asset_limit_skipped=%d errors=%d clipped=%d", tostring(not options.alive()), math.max(0, #result.assets - 24), result.errors, result.clipped)
    return result
end
-- END TESTABLE AUDIT

local env = (getgenv and getgenv()) or _G
local options = type(env.CloverParryOptions)=="table" and env.CloverParryOptions or {}
-- Reviewed from the supplied 2026-10-27 capture. Marker positions, not parry windows.
-- Maintainers add reviewed Discord candidates here and release a new GitHub revision.
local bundledProfiles = {
    ["10017994824"] = .5874996781,
    ["107811934597910"] = .4208331704,
    ["122307357536158"] = .4541664422,
    ["74594683886829"] = .4374997914,
    ["85853530330509"] = .4170830846,
    ["86722279259826"] = .5041664243,
    ["99787918237880"] = .3874998391,
}
-- No webhook token belongs in this distributed file.
local PUBLIC_REPORT_URL = "https://clover-timing-relay.indigoamber16384.chatgpt.site/report"

if env.CloverAutoParry then
    env.CloverAutoParry:Unload()
    assert(not env.CloverAutoParry, "Previous instance could not release F; retry Unload before rerunning.")
end
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
assert(player, "Join Clover RPG before running this file.")
local playerGui = player:WaitForChild("PlayerGui", 10)
assert(playerGui, "PlayerGui unavailable; wait for loading to finish.")

local attacks = {
    ["86722279259826"] = { name = "Guard swing 1", delay = 0.31 },
    ["107811934597910"] = { name = "Guard swing 2", delay = 0.31 },
    ["122307357536158"] = { name = "Guard swing 3", delay = 0.32 },
    ["99787918237880"] = { name = "Guard swing 4", delay = 0.24 },
    -- Trial only: .585 s observed health-drop offset minus .135 s chosen lead.
    ["10017994824"] = { name = "Guard heavy trial", delay = 0.45, trial = true },
}
local reviewed = {
    ["10017151218"] = "looping Idle-priority; not an attack trigger",
    ["10036138066"] = "looping locomotion/idle with footstep keyframes",
    ["10028752861"] = "looping Movement-priority with footstep keyframes",
    ["10059485766"] = "reaction candidate; not an attack trigger",
    ["9839904022"] = "Movement.ClimbUp; excluded",
    ["10067329531"] = "Executions.Blade.SpearExecuting/TridentExecuting; excluded",
}
local auditSeeds = { "86722279259826", "107811934597910", "122307357536158", "99787918237880",
    "10017994824", "9839904022", "10017151218", "10036138066", "10028752861", "10059485766" }
local order = { "86722279259826", "107811934597910", "122307357536158", "99787918237880" }
local config = { radius = 8, cooldown = 0.7, hold = 0.12, offset = 0, guardsOnly = false, heavyTrial = false }
local state = { version = 6, release = "6.1", alive = true, enabled = false, focused = true, connections = {}, animators = {},
    logs = {}, attempts = 0, detected = 0, held = false, releaseAt = 0, testAt = nil }
env.CloverAutoParry = state
local scheduler = newScheduler()
local discovery = { enabled = true, radius = 40, includeLoops = false, events = {},
    catalog = {}, order = {}, active = {}, activeCount = 0, serial = 0, dropped = 0,
    catalogSkipped = 0, tracksSkipped = 0, recent = {}, actorSerial = 0,
    actorIds = setmetatable({}, { __mode = "k" }) }
state.discovery = discovery
local audit = { running = false, generation = 0, lines = {}, markerNames = {}, nextRun = os.clock()+2 }
state.audit = audit
local sessionKey = tostring(game.PlaceId) .. ":" .. tostring(game.JobId) .. ":" .. tostring(game.PlaceVersion)
if not env.__CloverHitWindowV4 or env.__CloverHitWindowV4.session ~= sessionKey then
    env.__CloverHitWindowV4 = { session = sessionKey, rows = {} }
end
local learning = { enabled = true, lead = .12, radius = 40, active = {}, activeCount = 0,
    paths = {}, registryComplete = false, nextRefresh = 0, logs = {}, skipped = 0,
    model = newHitWindowModel(env.__CloverHitWindowV4.rows) }
state.learning = learning
local httpOK,http=pcall(function() return game:GetService("HttpService") end)
if not httpOK then http=nil end
local read=readfile or env.readfile
local write=writefile or env.writefile
local requestFn=request or http_request or env.request or env.http_request or (syn and syn.request)
local reportUrl=type(options.reportUrl)=="string" and options.reportUrl or PUBLIC_REPORT_URL
local privateEnabled=false
if reportUrl=="" and http and type(read)=="function" then
    local ok,data=pcall(function()
        local raw=read("clover_private_reporting.json"); assert(#raw<4096)
        return http:JSONDecode(raw)
    end)
    if ok and type(data)=="table" and type(data.webhookUrl)=="string"
        and data.webhookUrl:match("^https://discord%.com/api/webhooks/%d+/[%w_%-]+$") then
        reportUrl=data.webhookUrl; privateEnabled=data.enabled==true
    end
end
local cachePath="clover_timings_v5_"..tostring(game.PlaceId)..".json"
local storage=newProfileSupport({place=game.PlaceId,placeVersion=game.PlaceVersion or 0,time=os.time,
    alive=function() return state.alive end,
    spawn=task and task.spawn,
    read=type(read)=="function" and function() return read(cachePath) end or nil,
    write=type(write)=="function" and function(data) write(cachePath,data) end or nil,
    encode=http and function(data) return http:JSONEncode(data) end or nil,
    decode=http and function(data) return http:JSONDecode(data) end or nil,
    send=http and type(requestFn)=="function" and reportUrl:match("^https://") and function(payload)
        local direct=reportUrl:match("^https://discord%.com/api/webhooks/")
        local body=payload
        if direct then
            body={content="Clover timing candidates (NOT verified parry success)\n```json\n"..
                http:JSONEncode(payload).."\n```",allowed_mentions={parse={}}}
        end
        local url=direct and (reportUrl.."?wait=true") or reportUrl
        local response=requestFn({Url=url,Method="POST",Headers={["Content-Type"]="application/json"},Body=http:JSONEncode(body)})
        local code=tonumber(response.StatusCode or response.Status)
        local retry=0
        if code==429 then
            local ok,data=pcall(function() return http:JSONDecode(response.Body or "") end)
            if ok and type(data)=="table" then retry=tonumber(data.retry_after) or 0 end
            local h=response.Headers or {}; retry=math.max(retry,tonumber(h["Retry-After"] or h["retry-after"]) or 0)
        end
        return code,retry
    end or nil})
storage.enabled=storage.available
storage.status=storage.enabled and "Automatic timing reporting ON" or "Reporting unavailable"
storage:load(learning.model.rows)
state.storage=storage

local function clean(value) return tostring(value):gsub("[%c]", " "):sub(1, 160) end
function discovery:event(message)
    if not self.enabled then return end
    self.events[#self.events + 1] = string.format("[%.6f] %s", os.clock(), message)
    if #self.events > 1500 then table.remove(self.events, 1); self.dropped = self.dropped + 1 end
end
function discovery:disconnectTrack(track)
    local item = self.active[track]
    if not item then return end
    for _, c in ipairs(item.connections) do c:Disconnect() end
    self.active[track] = nil; self.activeCount = self.activeCount - 1
end
function discovery:closeTracks()
    local keys = {}; for track in pairs(self.active) do keys[#keys + 1] = track end
    for _, track in ipairs(keys) do self:disconnectTrack(track) end
end
function discovery:setEnabled(value)
    if self.enabled then self:event("CAPTURE_STOP") end
    self:closeTracks(); self.recent = {}; self.enabled = value
    if value then self:event("CAPTURE_START radius=" .. self.radius .. " loops=" .. tostring(self.includeLoops)) end
end
function discovery:clear()
    self:closeTracks(); self.events = {}; self.catalog = {}; self.order = {}; self.recent = {}
    self.dropped = 0; self.catalogSkipped = 0; self.tracksSkipped = 0
    self:event("CLEARED")
end
function discovery:mark(kind)
    if not self.enabled then return end
    self:event(kind)
    -- Associations are temporal candidates, never an assertion about the attacker.
    for _, item in ipairs(self.recent) do
        local age = os.clock() - item.started
        if age >= 0 and age <= 1.5 then
            local ok, position, speed = pcall(function() return item.track.TimePosition, item.track.Speed end)
            self:event(string.format("CONTEXT event=%s play=%d age=%.4f pos=%s speed=%s association=unconfirmed",
                kind, item.token, age, ok and tostring(position) or "unavailable", ok and tostring(speed) or "unavailable"))
        end
    end
end
function discovery:export()
    local lines = { "CLOVER DISCOVERY v6 | place=" .. tostring(game.PlaceId),
        "Unknown means unmapped animation, NOT confirmed attack. Known means ID in prototype; timing not universally validated.",
        "Health/F/marker correlations are NOT authoritative hit or parry-success events.",
        string.format("radius=%s loops=%s recording=%s overwritten_events=%d skipped_catalog_observations=%d skipped_track_observers=%d",
            self.radius, tostring(self.includeLoops), tostring(self.enabled), self.dropped, self.catalogSkipped, self.tracksSkipped),
        "CATALOG (grouped by NPC name or PLAYER, plus animation ID)" }
    for _, key in ipairs(self.order) do
        local row = self.catalog[key]
        lines[#lines + 1] = string.format("%s id=%s scope=%q name=%q count=%d first=%.6f last=%.6f",
            row.known and "KNOWN_ID" or "UNKNOWN", row.id, row.scope, row.name, row.count, row.first, row.last)
        if reviewed[row.id] then lines[#lines + 1] = "REVIEW id=" .. row.id .. " " .. reviewed[row.id] end
        if attacks[row.id] and attacks[row.id].trial then lines[#lines + 1] = "TRIAL_ONLY id=" .. row.id .. " enabled=" .. tostring(config.heavyTrial) end
    end
    lines[#lines + 1] = "EVENTS (client clock; playback position also recorded)"
    for _, entry in ipairs(self.events) do lines[#lines + 1] = entry end
    return table.concat(lines, "\n")
end
local statusLabel
local function log(message)
    state.logs[#state.logs + 1] = string.format("[%.6f] %s", os.clock(), message)
    if #state.logs > 500 then table.remove(state.logs, 1) end
    state.status = message
    if statusLabel then statusLabel.Text = message end
end
scheduler.onSkip=function(item,reason) log("SKIP id="..item.id.." reason="..reason) end
local function connect(signal, callback)
    local c = signal:Connect(callback)
    state.connections[#state.connections + 1] = c
    return c
end

local methods = {}
local down, up = keypress or env.keypress, keyrelease or env.keyrelease
if type(down) == "function" and type(up) == "function" then
    methods[#methods + 1] = { name = "Executor keys", send = function(pressed)
        if pressed then down(0x46) else up(0x46) end
    end }
end
local okVIM, vim = pcall(function() return game:GetService("VirtualInputManager") end)
if okVIM and vim then
    methods[#methods + 1] = { name = "VirtualInputManager", send = function(pressed)
        vim:SendKeyEvent(pressed, Enum.KeyCode.F, false, game)
    end }
end
local methodIndex = 1
local function release()
    if not state.held then return true end
    local ok, err = pcall(state.heldMethod.send, false)
    if ok then state.held = false; state.heldMethod = nil; discovery:mark("AUTO_F_UP")
    else log("F release failed: " .. tostring(err)) end
    return ok
end
local function inputAllowed()
    if not state.focused or UIS:GetFocusedTextBox() then return false end
    local active = isrbxactive or isgameactive or env.isrbxactive or env.isgameactive
    if type(active) == "function" then
        local ok, result = pcall(active)
        if ok and not result then return false end
    end
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    return humanoid and humanoid.Health > 0
end
local function press(item)
    if state.held or not inputAllowed() or UIS:IsKeyDown(Enum.KeyCode.F) then return false end
    local method = methods[methodIndex]
    if not method then log("No supported input API available."); return false end
    -- Retain release ownership even if a backend throws after partly sending input.
    state.held, state.heldMethod = true, method
    state.releaseAt = os.clock() + config.hold
    local ok, err = pcall(method.send, true)
    if not ok then
        release(); state.enabled = false
        log("Input failed. OFF. Try another input method: " .. tostring(err))
        return false
    end
    state.attempts = state.attempts + 1
    discovery:mark("AUTO_F_DOWN_ATTEMPT id=" .. item.id)
    log("F attempted: " .. item.id .. " / " .. (item.actor and item.actor.Name or "manual test") ..
        (item.learned and (" / learned combat marker / source="..(item.source or "learned").." / marker="..item.hitPosition.." / lead="..learning.lead) or " / preset or test"))
    return true
end
local function stop(reason)
    state.enabled = false; state.testAt = nil; scheduler:clear(); release()
    log(reason or "OFF")
end
local function root(model)
    return model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
end
local function actorFor(animator)
    local object = animator.Parent
    while object and object ~= workspace do
        if object:IsA("Model") and root(object) then return object end
        object = object.Parent
    end
end
local function eligible(actor)
    if not actor or actor == player.Character or not actor:IsDescendantOf(workspace) then return false end
    local humanoid = actor:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.Health <= 0 then return false end
    return true
end
local function distance(actor)
    local a, b = root(actor), root(player.Character)
    if not a or not b then return math.huge end
    return (a.Position - b.Position).Magnitude
end
function learning:note(message)
    self.logs[#self.logs+1] = string.format("[%.6f] %s", os.clock(), message)
    if #self.logs > 300 then table.remove(self.logs,1) end
end
function learning:refresh()
    self.nextRefresh = os.clock() + 5
    local paths, complete = {}, false
    local ok, err = pcall(function()
        local rs = game:GetService("ReplicatedStorage")
        local folder = rs:FindFirstChild("Animations")
        if not folder then return end
        local objects = folder:GetDescendants()
        if #objects > 6000 then return end
        for _, object in ipairs(objects) do
            if object:IsA("Animation") then
                local id = tostring(object.AnimationId):match("%d+")
                local parts, current = {}, object
                while current and current ~= folder do table.insert(parts,1,current.Name); current=current.Parent end
                if id and current == folder then
                    paths[id] = paths[id] or {}; table.insert(paths[id], table.concat(parts,"/"))
                end
            end
        end
        complete = true
    end)
    self.paths, self.registryComplete = paths, ok and complete
    self.registryStatus = self.registryComplete and "Animation paths loaded" or "Animation paths unavailable; new IDs skipped"
    if not ok then self.registryStatus = "Animation path read failed: " .. clean(err) end
end
function learning:allowed(id)
    if reviewed[id] then return false, reviewed[id] end
    if self.paths[id] then return classifyAnimationPaths(self.paths[id]) end
    -- Existing guard presets have supplied evidence even when the registry is unavailable.
    if attacks[id] then return true, "existing guard mapping" end
    return false, "no recognized combat path"
end
function learning:position(id)
    if not self.enabled or not self:allowed(id) then return nil end
    local row=self.model.rows[id]
    if row then return self.model:position(id),"learned" end
    if options.useBundledProfiles~=false and game.PlaceId==8248288152 and game.PlaceVersion==68598 then
        return bundledProfiles[id],"bundled candidate"
    end
end
function learning:sample(id,position,multiple)
    local result=self.model:sample(id,position,multiple)
    local row=self.model.rows[id]
    if row then row.updatedAt=os.time(); storage.dirty=true end
    return result
end
function learning:disconnect(track)
    local item=self.active[track]; if not item then return end
    for _, c in ipairs(item.connections) do c:Disconnect() end
    self.active[track]=nil; self.activeCount=self.activeCount-1
end
function learning:close()
    local keys={}; for track in pairs(self.active) do keys[#keys+1]=track end
    for _, track in ipairs(keys) do self:disconnect(track) end
end
function learning:observe(actor, track, id)
    if not self.enabled or not actor or actor == player.Character or not id then return end
    self:disconnect(track)
    if not actor:IsDescendantOf(workspace) or distance(actor) > self.radius or track.Looped then return end
    local humanoid=actor:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.Health <= 0 then return end
    if not self:allowed(id) then return end
    if not tostring(track.Priority):find("Action",1,true) or track.TimePosition > .05 then return end
    if self.activeCount >= 64 then self.skipped=self.skipped+1; return end
    local item={ id=id, actor=actor, started=os.clock(), connections={}, seenSignals={}, maximum=track.TimePosition,
        previous=track.TimePosition, lastTime=os.clock(), lastSpeed=track.Speed }
    self.active[track]=item; self.activeCount=self.activeCount+1
    local function reached(source, name)
        if self.active[track] ~= item or not self.enabled then return end
        local ok, err=pcall(function()
            local position=track.TimePosition
            if track.Looped or track.Speed <= 0 or position < .03 or position > 8 then item.invalid=true; return end
            item.maximum=math.max(item.maximum,position)
            local signalKey=source..":"..name
            if item.position then
                -- Distinct signals at the same impact count once, including marker/keyframe pairs.
                -- A repeated signal or a separated impact remains ambiguous and blocks the profile.
                if not item.seenSignals[signalKey] and math.abs(position-item.position) <= .025 then
                    item.seenSignals[signalKey]=true; return
                end
                item.multiple=true
                self:sample(id,position,true)
                self:note("BLOCKED id="..id.." multiple timing markers")
            else
                item.position=position; item.source=source; item.seenSignals[signalKey]=true
                self:note(string.format("TIMING_MARKER id=%s name=%s pos=%.5f source=%s",id,name,position,source))
            end
        end)
        if not ok then item.invalid=true; self:note("MARKER_ERROR "..clean(err)) end
    end
    local function finish()
        if self.active[track] ~= item then return end
        local ok, err=pcall(function()
            local length=track.Length
            local complete=length > 0 and math.max(item.maximum,track.TimePosition) >= length-.04
            if item.position and not item.multiple and not item.invalid and complete and not track.Looped and self:allowed(id) then
                self:note("PROFILE id="..id.." "..self:sample(id,item.position,false))
            elseif item.position then self:note("DISCARDED id="..id.." incomplete, excluded or ambiguous playback") end
        end)
        if not ok then self:note("FINISH_ERROR "..clean(err)) end
        self:disconnect(track)
    end
    local function listen(getSignal, callback)
        local ok, c=pcall(function() return getSignal():Connect(callback) end)
        if ok then item.connections[#item.connections+1]=c end
        return ok
    end
    local markerOK=false
    for _,name in ipairs({"HitWindow","Attack"}) do
        local markerName=name
        local available=listen(function() return track:GetMarkerReachedSignal(markerName) end,
            function() reached("marker",markerName) end)
        markerOK=available or markerOK
    end
    local keyframeOK=listen(function() return track.KeyframeReached end,function(name)
        if name=="HitWindow" or name=="Attack" then reached("keyframe",name) end
    end)
    local stopOK=listen(function() return track.Stopped end,finish)
    if not stopOK or (not markerOK and not keyframeOK) then
        self:note("UNSUPPORTED_TRACK id="..id); self:disconnect(track)
    end
end
function learning:tick(now)
    if now >= self.nextRefresh then self:refresh() end
    local remove={}
    for track,item in pairs(self.active) do
        local ok, expired=pcall(function()
            local pos, speed=track.TimePosition, track.Speed
            local expected=(now-item.lastTime)*math.max(math.abs(speed),math.abs(item.lastSpeed))
            if pos < item.previous-.03 or pos-item.previous > expected+.12 then item.invalid=true end
            item.maximum=math.max(item.maximum,pos); item.previous=pos; item.lastTime=now; item.lastSpeed=speed
            return now-item.started>12 or not item.actor:IsDescendantOf(workspace)
        end)
        if not ok or expired then remove[#remove+1]=track end
    end
    for _,track in ipairs(remove) do self:disconnect(track) end
end
function learning:export()
    local lines={"CLOVER MARKER LEARNING v6.1 | place="..game.PlaceId,
        "Accepted names: HitWindow, Attack. Movement and executions remain excluded.",
        "Ready = consistent marker position; NOT confirmed parry success. First encounters are not protected by learning.",
        "lead_seconds="..self.lead.." enabled="..tostring(self.enabled).." skipped_tracks="..self.skipped,
        self.registryStatus or "Registry not checked",storage.diskStatus.." | "..storage.status}
    for id,position in pairs(bundledProfiles) do
        local active,origin=self:position(id)
        if active and origin=="bundled candidate" then
            lines[#lines+1]="BUNDLED id="..id.." marker="..position.." source=2026-10-27 capture; success unverified"
        end
    end
    local ids={}; for id in pairs(self.model.rows) do ids[#ids+1]=id end; table.sort(ids)
    for _,id in ipairs(ids) do
        local row=self.model.rows[id]; local allowed, reason=self:allowed(id)
        lines[#lines+1]=string.format("id=%s status=%s samples=%d marker=%s spread=%s eligible=%s reason=%s",
            id,row.status,#row.samples,tostring(row.position),tostring(row.spread),tostring(allowed),reason)
    end
    for _,line in ipairs(self.logs) do lines[#lines+1]=line end
    return table.concat(lines,"\n")
end
learning:refresh()
local markerProbes = { "HitWindow", "AnimationEnd", "Hit", "hit", "Damage", "damage", "Hitbox", "Attack", "Impact", "Parry" }
function discovery:observe(actor, track, id)
    if not self.enabled or not actor or actor == player.Character or not id then return end
    if not actor:IsDescendantOf(workspace) or distance(actor) > self.radius then return end
    if track.Looped and not self.includeLoops then return end
    local now = os.clock()
    local isPlayer = Players:GetPlayerFromCharacter(actor) ~= nil
    local scope = isPlayer and "PLAYER" or "NPC:" .. clean(actor.Name)
    local key = scope .. ":" .. id
    local row = self.catalog[key]
    if not row and #self.order < 300 then
        row = { id = id, scope = scope, name = clean(track.Name), known = attacks[id] ~= nil, count = 0, first = now }
        self.catalog[key] = row; self.order[#self.order + 1] = key
    end
    if row then row.count = row.count + 1; row.last = now
    else self.catalogSkipped = self.catalogSkipped + 1 end
    self.actorIds[actor] = self.actorIds[actor] or (self.actorSerial + 1)
    self.actorSerial = math.max(self.actorSerial, self.actorIds[actor])
    self.serial = self.serial + 1
    local token = self.serial
    self:event(string.format("PLAY play=%d %s id=%s actor_token=%d actor=%q kind=%s name=%q distance=%.2f pos=%.4f length=%.4f speed=%.3f priority=%s loop=%s",
        token, attacks[id] and "KNOWN_ID" or "UNKNOWN", id, self.actorIds[actor], clean(actor.Name), isPlayer and "PLAYER" or "NPC",
        clean(track.Name), distance(actor), track.TimePosition, track.Length, track.Speed, clean(track.Priority), tostring(track.Looped)))
    self:disconnectTrack(track) -- Reused tracks get a new occurrence token, not duplicate listeners.
    local item = { token = token, actor = actor, track = track, started = now, connections = {} }
    self.recent[#self.recent + 1] = item
    if #self.recent > 16 then table.remove(self.recent, 1) end
    if self.activeCount >= 64 then self.tracksSkipped = self.tracksSkipped + 1; return end
    self.active[track] = item; self.activeCount = self.activeCount + 1
    local function sample(kind, value)
        if not self.enabled or self.active[track] ~= item then return end
        local ok, err = pcall(function()
            self:event(string.format("%s play=%d value=%q age=%.4f pos=%.4f length=%.4f speed=%.3f", kind,
                token, clean(value or ""), os.clock() - now, track.TimePosition, track.Length, track.Speed))
        end)
        if not ok then self:event("SAMPLE_ERROR play=" .. token .. " " .. clean(err)) end
    end
    local function listen(getSignal, callback)
        local ok, connection = pcall(function() return getSignal():Connect(callback) end)
        if ok then item.connections[#item.connections + 1] = connection end
        return ok
    end
    listen(function() return track.Stopped end, function() sample("STOP"); self:disconnectTrack(track) end)
    -- Named keyframes and these optional marker probes are clues only. No generic hit event exists here.
    listen(function() return track.KeyframeReached end, function(name) sample("KEYFRAME", name) end)
    local available = 0
    local probes, added = {}, {}
    for _, marker in ipairs(markerProbes) do probes[#probes + 1] = marker; added[marker] = true end
    for _, marker in ipairs(audit.markerNames[id] or {}) do
        if not added[marker] then probes[#probes + 1] = marker; added[marker] = true end
    end
    for _, marker in ipairs(probes) do
        if listen(function() return track:GetMarkerReachedSignal(marker) end,
            function(value) sample("MARKER:" .. marker, value) end) then available = available + 1 end
    end
    if available == 0 then self:event("MARKER_API_UNAVAILABLE play=" .. token) end
end
function discovery:tick(now)
    local expired = {}
    for track, item in pairs(self.active) do
        if now - item.started > 8 or not item.actor:IsDescendantOf(workspace) then expired[#expired + 1] = track end
    end
    for _, track in ipairs(expired) do
        self:event("OBSERVER_EXPIRED play=" .. self.active[track].token)
        self:disconnectTrack(track)
    end
    local retained = {}
    for _, item in ipairs(self.recent) do if now - item.started <= 1.5 then retained[#retained + 1] = item end end
    self.recent = retained
    local char = player.Character
    local human = char and char:FindFirstChildOfClass("Humanoid")
    if human ~= self.humanoid then
        self.humanoid = human; self.lastHealth = human and human.Health
        self:event("SELF_HEALTH_BASELINE value=" .. tostring(self.lastHealth))
    elseif human then
        local health = human.Health
        if self.lastHealth and health < self.lastHealth then
            self:mark(string.format("SELF_HEALTH_DROP amount=%.3f health=%.3f", self.lastHealth - health, health))
        end
        self.lastHealth = health
    end
end
local function attach(animator)
    if not animator:IsA("Animator") or state.animators[animator] then return end
    state.animators[animator] = animator.AnimationPlayed:Connect(function(track)
        if not state.alive or (not state.enabled and not discovery.enabled and not learning.enabled) then return end
        local ok, err = pcall(function()
            local actor = actorFor(animator)
            local id = tostring(track.Animation.AnimationId):match("%d+")
            local learnedOK, learnedError=pcall(function() learning:observe(actor,track,id) end)
            if not learnedOK then learning:note("OBSERVE_ERROR "..clean(learnedError)) end
            local observed, observeError = pcall(function() discovery:observe(actor, track, id) end)
            if not observed then discovery:event("OBSERVE_ERROR " .. clean(observeError)) end
            if not state.enabled or not eligible(actor) or distance(actor) > config.radius + 15 then return end
            local attack = attacks[id]
            if track.Looped or not learning:allowed(id) then return end
            local preset = attack and (not attack.trial or (config.heavyTrial and not Players:GetPlayerFromCharacter(actor)
                and string.find(actor.Name,"Kamo Guard",1,true)))
            local hitPosition,profileSource = learning:position(id)
            if hitPosition then preset=false end
            -- Never revert to an old preset while a local profile needs validation.
            local row=learning.model.rows[id]
            if learning.enabled and row and not hitPosition then
                log("SKIP id="..id.." profile="..row.status); return
            end
            if not preset and not hitPosition then return end
            if not preset and not tostring(track.Priority):find("Action",1,true) then return end
            state.detected = state.detected + 1
            local target = preset and math.max(0,attack.delay+config.offset) or (hitPosition-track.Speed*(learning.lead-config.offset))
            if target <= 0 then return end
            if scheduler:add(track, actor, id, target, os.clock(), track.TimePosition) and not preset then
                scheduler.pending[track].learned=true; scheduler.pending[track].hitPosition=hitPosition; scheduler.pending[track].source=profileSource
            end
            log("Detected " .. (preset and attack.name or ((profileSource or "learned").." "..id)) .. " at " .. string.format("%.1f", distance(actor)) .. " studs")
        end)
        if not ok then stop("Observation error: " .. tostring(err)) end
    end)
end
function state:Unload()
    stop("Unloaded")
    -- Keep the panel available for another release attempt if a backend fails.
    if self.held then log("Release failed; press/release F, then retry Unload."); return end
    storage:save(learning.model.rows)
    discovery:setEnabled(false)
    learning:close()
    audit.generation = audit.generation + 1; audit.running = false
    self.alive = false
    for _, c in ipairs(self.connections) do c:Disconnect() end
    for _, c in pairs(self.animators) do c:Disconnect() end
    if self.gui then self.gui:Destroy() end
    if env.CloverAutoParry == self then env.CloverAutoParry = nil end
end

local function make(class, parent, props)
    local obj = Instance.new(class)
    for k, v in pairs(props) do obj[k] = v end
    obj.Parent = parent
    return obj
end
local gui = make("ScreenGui", playerGui, { Name = "CloverAutoParry", ResetOnSpawn = false, DisplayOrder = 110 })
state.gui = gui
local panel = make("Frame", gui, { Size = UDim2.new(0, 390, 0, 340), Position = UDim2.new(0, 24, 0.5, -170),
    BackgroundColor3 = Color3.fromRGB(22, 26, 35), BorderSizePixel = 0 })
make("UICorner", panel, { CornerRadius = UDim.new(0, 10) })
local function text(y, h, value)
    return make("TextLabel", panel, { Position = UDim2.new(0, 14, 0, y), Size = UDim2.new(1, -28, 0, h),
        BackgroundTransparency = 1, Text = value, TextColor3 = Color3.fromRGB(226, 232, 245),
        Font = Enum.Font.Gotham, TextSize = 13, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left })
end
local title=text(10,26,"Clover Auto Parry v6.1")
title.Active=true
text(40,36,"NPCs + players · automatic learning and recording\nF7 toggles auto parry; F8 hides this panel.")
local function button(x,y,w,caption,callback)
    local b=make("TextButton",panel,{Position=UDim2.new(0,x,0,y),Size=UDim2.new(0,w,0,32),Text=caption,
        BackgroundColor3=Color3.fromRGB(52,65,89),TextColor3=Color3.new(1,1,1),Font=Enum.Font.Gotham,TextSize=13,BorderSizePixel=0})
    make("UICorner",b,{CornerRadius=UDim.new(0,6)}); connect(b.Activated,callback); return b
end
local toggle
local function switch()
    if state.enabled then stop("OFF")
    elseif not state.held then state.enabled=true; scheduler:clear(); log("ON · waiting for mapped attacks") end
end
toggle=button(14,88,174,"Auto parry: OFF",switch)
button(202,88,174,"Test F (1 second)",function()
    stop("Test scheduled: return focus to the game")
    state.testAt=math.max(os.clock()+1,scheduler.nextAllowed)
end)
statusLabel=text(166,38,"OFF · use Test F first")
local stats=text(205,22,"Detected 0 · attempted 0 · success unverified")
stats.TextSize=11
local learningStats=text(230,22,"Learning and discovery running")
learningStats.TextSize=11
local storageStats=text(255,34,storage.status)
storageStats.TextSize=11
text(291,40,"Learned timing summaries are automatically sent to Discord. No player names, user IDs or raw logs are sent.")
local function copyText(body)
    local clipboard = setclipboard or toclipboard or env.setclipboard or env.toclipboard
    local ok = type(clipboard) == "function" and pcall(clipboard, body)
    if ok then log("Logs copied")
    else
        if state.export then state.export:Destroy() end
        local box = make("TextBox", panel, { Position = UDim2.new(0, 14, 0, 74), Size = UDim2.new(1, -28, 0, 220),
            Text = body, MultiLine = true, ClearTextOnFocus = false, TextEditable = true, TextSize = 12,
            Font = Enum.Font.Code, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
            TextColor3 = Color3.new(1, 1, 1), BackgroundColor3 = Color3.fromRGB(25, 31, 42), ZIndex = 5 })
        state.export = box; box:CaptureFocus(); box.SelectionStart = 1; box.CursorPosition = #body + 1
        connect(box.FocusLost, function() box:Destroy(); state.export = nil end)
    end
end
button(14,128,174,"Copy logs",function()
    copyText("CLOVER AUTO PARRY v6 | place="..tostring(game.PlaceId).." | attempts are NOT confirmed successes\n"..
        table.concat(state.logs,"\n").."\n\n"..learning:export().."\n\n"..discovery:export()..
        "\n\nBACKGROUND AUDIT\n"..table.concat(audit.lines,"\n"))
end)
button(202,128,174,"Unload",function() state:Unload() end)
local function startAudit()
    if audit.running or not state.alive then return end
    audit.nextRun=os.clock()+300
    if not task or type(task.spawn)~="function" then return end
    audit.generation = audit.generation + 1; audit.running = true
    local generation = audit.generation
    local function current() return state.alive and audit.generation == generation end
    task.spawn(function()
        local roots, ids = {}, {}
        for _, id in ipairs(auditSeeds) do ids[#ids + 1] = id end
        for _, key in ipairs(discovery.order) do ids[#ids + 1] = discovery.catalog[key].id end
        if player.Character then roots[#roots + 1] = player.Character end
        for actor in pairs(discovery.actorIds) do if actor:IsDescendantOf(workspace) then roots[#roots + 1] = actor end end
        local rsOK, rs = pcall(function() return game:GetService("ReplicatedStorage") end)
        if rsOK then roots[#roots + 1] = rs end
        local fetched, result = pcall(function()
            return runTimingAudit({ roots = roots, ids = ids, alive = current,
                pause = function() task.wait() end,
                fetch = function(id)
                    local ok, clip = pcall(function() return game:GetService("AnimationClipProvider"):GetAnimationClipAsync("rbxassetid://" .. id) end)
                    if ok then return clip end
                    local fallback, sequence = pcall(function() return game:GetService("KeyframeSequenceProvider"):GetKeyframeSequenceAsync("rbxassetid://" .. id) end)
                    if fallback then return sequence end
                    error("ClipProvider: " .. tostring(clip) .. " | SequenceProvider: " .. tostring(sequence))
                end })
        end)
        if not current() then return end
        audit.running = false
        if fetched then
            audit.lines = result.lines; audit.markerNames = result.markerNames
            audit.status="Background audit finished"
        else audit.lines = { "AUDIT_ERROR " .. clean(result) }; audit.status="Background audit unavailable" end
    end)
end

local dragStart, panelStart
connect(title.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then dragStart = input.Position; panelStart = panel.Position end
end)
connect(UIS.InputChanged, function(input)
    if dragStart and input.UserInputType == Enum.UserInputType.MouseMovement then
        local d = input.Position - dragStart
        panel.Position = UDim2.new(panelStart.X.Scale, panelStart.X.Offset + d.X, panelStart.Y.Scale, panelStart.Y.Offset + d.Y)
    end
end)
connect(UIS.InputEnded, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then dragStart = nil end
    if input.KeyCode == Enum.KeyCode.F and not state.held then discovery:mark("OBSERVED_F_UP") end
end)
connect(UIS.InputBegan, function(input, processed)
    if processed or UIS:GetFocusedTextBox() then return end
    if input.KeyCode == Enum.KeyCode.F and not state.held then
        discovery:mark("OBSERVED_F_DOWN")
        scheduler.nextAllowed = os.clock() + config.cooldown
    elseif input.KeyCode == Enum.KeyCode.F7 then switch()
    elseif input.KeyCode == Enum.KeyCode.F8 then panel.Visible = not panel.Visible end
end)
connect(UIS.WindowFocusReleased, function() state.focused = false; stop("OFF · game lost focus") end)
connect(UIS.WindowFocused, function() state.focused = true end)
connect(player.CharacterRemoving, function() stop("OFF · character removed") end)
connect(workspace.DescendantAdded, attach)
connect(workspace.DescendantRemoving, function(object)
    local c = state.animators[object]
    if c then c:Disconnect(); state.animators[object] = nil end
end)
for _, object in ipairs(workspace:GetDescendants()) do attach(object) end
connect(RunService.Heartbeat, function()
    local now = os.clock()
    local ok, err = pcall(function()
        if now>=audit.nextRun and not audit.running then startAudit() end
        local learningOK,learningError=pcall(function() learning:tick(now) end)
        if not learningOK then learning:note("TICK_ERROR "..clean(learningError)) end
        storage:tick(now,learning.model.rows,function(id) return learning:allowed(id) end)
        storageStats.Text=storage.diskStatus.."\n"..storage.status
        if discovery.enabled then
            local recorded, recordError = pcall(function() discovery:tick(now) end)
            if not recorded then discovery:event("RECORDER_ERROR " .. clean(recordError)) end
        end
        if state.held and (now >= state.releaseAt or not inputAllowed()) then release() end
        if state.testAt and now >= state.testAt then
            state.testAt = nil
            if press({ id = "TEST" }) then scheduler.nextAllowed = now + config.cooldown
            else log("Test skipped: check game focus, character and F key") end
        end
        if state.enabled and inputAllowed() then
            scheduler:step(now, config.cooldown, function(track, item)
                local good, valid, position, speed, inRange = pcall(function()
                    local validLearning=true
                    if item.learned then
                        item.target=item.hitPosition-track.Speed*(learning.lead-config.offset)
                        validLearning=learning.enabled and learning:position(item.id)==item.hitPosition and item.target>0
                        local observation=learning.active[track]
                        if observation and (observation.invalid or observation.multiple) then validLearning=false end
                    end
                    return validLearning and learning:allowed(item.id) and eligible(item.actor) and track.IsPlaying and not track.Looped,
                        track.TimePosition, track.Speed, distance(item.actor) <= config.radius
                end)
                if not good then return false, 0, 0, false end
                return valid, position, speed, inRange
            end, press)
        else scheduler:clear() end
        toggle.Text = state.enabled and "Auto parry: ON" or "Auto parry: OFF"
        stats.Text = "Detected " .. state.detected .. " · attempted " .. state.attempts .. " · success unverified"
        local ready, collecting, blocked, bundled=0,0,0,0
        for id,row in pairs(learning.model.rows) do
            if row.status=="ready" and learning:allowed(id) then ready=ready+1
            elseif row.status=="collecting" then collecting=collecting+1 else blocked=blocked+1 end
        end
        for id in pairs(bundledProfiles) do
            local position,origin=learning:position(id)
            if position and origin=="bundled candidate" then bundled=bundled+1 end
        end
        learningStats.Text=string.format("Learned %d · bundled %d · collecting %d · recorded %d",
            ready,bundled,collecting,#discovery.events)
    end)
    if not ok then stop("Runtime error: " .. tostring(err)) end
end)
discovery:event("CAPTURE_START automatic=true radius="..discovery.radius)
log("Ready OFF · learning, capture and reporting are automatic")
if game.PlaceId ~= 8248288152 then log("OFF · different place from capture; mappings may not apply") end
