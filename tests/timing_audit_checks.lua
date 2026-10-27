local count=0
local function check(ok,name) assert(ok,name); count=count+1; print("PASS "..name) end
local f=assert(io.open(arg[1] or "external-tools/clover-diagnostics/clover_auto_parry.lua"))
local source=f:read("*a"); f:close()
local core=assert(source:match("%-%- BEGIN TESTABLE AUDIT(.-)%-%- END TESTABLE AUDIT"))
local audit=assert(loadstring(core.."\nreturn runTimingAudit"))()
local function node(name,class,children,attrs)
    local n={Name=name,ClassName=class,children=children or {},attributes=attrs or {}}
    function n:GetAttributes() return self.attributes end
    function n:GetChildren() return self.children end
    for _, child in ipairs(n.children) do child.Parent=n end
    return n
end
local ordinary=node("SkyColor","StringValue"); ordinary.Value="unrelated"
local value=node("WindupSeconds","NumberValue"); value.Value=.4
local module=node("CombatConfig","ModuleScript")
setmetatable(module,{__index=function(_,key) if key=="Source" then error("Source must not be read") end end})
local root=node("ReplicatedStorage","ReplicatedStorage",{ordinary,module,value},{AttackDelay=.2,Unrelated=5})
local function clip(markers)
    local c={ClassName="KeyframeSequence",destroyed=false}
    function c:IsA(name) return name==self.ClassName end
    function c:GetKeyframes() return {
        {Name="Keyframe",Time=.5,GetMarkers=function() return markers end},
        {Name="Windup",Time=.1,GetMarkers=function() return {} end},
    } end
    function c:Destroy() self.destroyed=true end
    return c
end
local loaded={}
local r=audit({roots={root},ids={"1","2"},alive=function() return true end,pause=function() end,
    fetch=function(id) loaded[id]=clip({{Name="StrikeNow",Value="blade"}}); return loaded[id] end})
local out=table.concat(r.lines,"\n")
check(out:find("ATTRIBUTE path=ReplicatedStorage key=AttackDelay value=0.2",1,true),"reads relevant replicated attributes")
check(out:find("VALUE path=ReplicatedStorage.WindupSeconds value=0.4",1,true),"reads named numeric timing values")
check(out:find("MODULE_PATH_ONLY ReplicatedStorage.CombatConfig",1,true) and r.errors==0,"reports module path without reading or executing Source")
check(not out:find("SkyColor",1,true) and not out:find("Unrelated=",1,true),"does not dump unrelated values")
check(out:find("ASSET_MARKER id=1 time=0.5 name=StrikeNow",1,true),"enumerates exact marker names and clip times")
check(out:find("ASSET_KEYFRAME id=1 time=0.1 name=Windup",1,true),"records named keyframe timing")
check(out:find("SHARED_MARKER_CANDIDATE name=StrikeNow ids=1,2",1,true),"identifies marker shared across distinct assets as candidate")
check(r.markerNames["1"][1]=="StrikeNow", "returns discovered names for later passive observation")
check(loaded["1"].destroyed and loaded["2"].destroyed,"disposes fetched animation copies")
local calls=0
r=audit({roots={},ids={"3"},alive=function() return true end,pause=function() end,fetch=function() error("permission denied") end})
out=table.concat(r.lines,"\n")
check(r.errors==1 and out:find("ASSET_UNAVAILABLE id=3",1,true) and not out:find("ASSET_OK",1,true),"permission failure is not an empty-marker result")
r=audit({roots={},ids={"4"},alive=function() return true end,pause=function() end,fetch=function() local c=clip({}); c.ClassName="CurveAnimation"; return c end})
check(table.concat(r.lines,"\n"):find("ASSET_UNINSPECTED id=4 type=CurveAnimation",1,true),"unsupported clip format explicitly reported")
r=audit({roots={root},ids={"1"},alive=function() return false end,pause=function() end,fetch=function() calls=calls+1 end})
check(calls==0 and r.visited==0 and table.concat(r.lines,"\n"):find("cancelled=true",1,true),"cancel prevents traversal and fetching")
local ids={}; for i=1,30 do ids[#ids+1]=tostring(i) end
r=audit({roots={},ids=ids,alive=function() return true end,pause=function() end,fetch=function() calls=calls+1; return clip({}) end})
check(calls==24 and table.concat(r.lines,"\n"):find("asset_limit_skipped=6",1,true),"asset retrieval bounded with skipped count")
local a=node("AttackA","Folder"); local b=node("AttackB","Folder"); a.children={b}; b.children={a}
r=audit({roots={a},ids={},alive=function() return true end,pause=function() end,fetch=function() error("unexpected") end})
check(r.visited==2,"duplicate or cyclic traversal input does not loop")
local empty=clip({}); empty.GetKeyframes=function() return {} end
r=audit({roots={},ids={"99"},alive=function() return true end,pause=function() end,fetch=function() return empty end})
out=table.concat(r.lines,"\n")
check(out:find("ASSET_INCONCLUSIVE id=99 reason=empty_keyframes",1,true) and not out:find("ASSET_OK",1,true),
    "zero-frame assets reported inconclusive rather than successful empty marker scan")
print("PASS: "..count.." timing-audit assertions. Live asset availability unverified.")
