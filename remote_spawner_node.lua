-- =========================================================
-- REMOTE SPAWNER NODE
-- Central config: spawners.lua from Master Controller.
-- Refreshes are pulse-free: existing outputs are never toggled
-- just because configuration was reloaded.
-- =========================================================

local controlProtocol="spawner_control"
local statusProtocol="spawner_status"
local configControlProtocol="spawner_config_control"
local configStatusProtocol="spawner_config_status"
local masterProtocol="cc_master_update"
local masterHostname="master"
local masterTimeout=2
local configFile="spawners.lua"
local tempConfigFile="spawners_new.lua"
local computerID=os.getComputerID()
local modemSide
local spawners={}
local updateInterval=4
local configUpdateInterval=300
local configSource="NONE"
local maintenanceMode=false
local lastMaintenanceTimestamp=0
local sideOrder={"front","back","left","right","top","bottom"}
local validSides={top=true,bottom=true,left=true,right=true,front=true,back=true}

for _,side in ipairs({"top","bottom","left","right","front","back"}) do if peripheral.isPresent(side) and peripheral.getType(side)=="modem" then modemSide=side;break end end
if not modemSide then error("No modem found") end
rednet.open(modemSide)

local function trim(v) v=tostring(v or "") return (v:gsub("^%s+",""):gsub("%s+$","")) end
local function disabled(v) if v==nil or v==false then return true end if type(v)~="string" then return false end local n=string.upper(trim(v));return n=="" or n=="N/A" or n=="NA" or n=="NONE" or n=="DISABLED" end
local function makeKey(side) return "side_"..side end

local function profileToList(profile)
    local list={}
    profile=type(profile)=="table" and profile or {}
    if type(profile.spawners)=="table" then
        for _,e in ipairs(profile.spawners) do
            local name=trim(e.name or e.displayName)
            if e.enabled~=false and not disabled(name) then list[#list+1]={key=tostring(e.key or makeKey(e.outputSide)),name=name,outputSide=e.outputSide} end
        end
    else
        for _,side in ipairs(sideOrder) do
            local v=profile[side]
            local name=type(v)=="table" and trim(v.name or v.displayName) or trim(v)
            if not disabled(v) and name~="" then list[#list+1]={key=makeKey(side),name=name,outputSide=side} end
        end
    end
    local keys,sides={},{}
    for _,s in ipairs(list) do
        if not validSides[s.outputSide] then return nil,"Bad output side: "..tostring(s.outputSide) end
        if s.outputSide==modemSide then return nil,"Spawner cannot use modem side "..modemSide end
        if keys[s.key] then return nil,"Duplicate key "..s.key end
        if sides[s.outputSide] then return nil,"Duplicate side "..s.outputSide end
        keys[s.key]=true;sides[s.outputSide]=true
    end
    return list
end

local function selectConfig(config)
    if type(config)~="table" then return nil,"Config must return a table" end
    local profile=config.computers and config.computers[computerID] or nil
    local profileName=profile and ("COMPUTER "..computerID) or "DEFAULT"
    profile=profile or config.default or {}
    local list,err=profileToList(profile);if not list then return nil,err end
    return {list=list,profileName=profileName,status=tonumber(config.statusUpdateInterval) or 4,refresh=tonumber(config.configUpdateInterval) or 300}
end

local function applyConfig(config,source)
    local selected,err=selectConfig(config);if not selected then return false,err end

    -- Preserve state by physical side. This is the important part: we do NOT
    -- shut every output off and turn it back on during refresh, which caused
    -- visible split-second pulses in the mob farm.
    local oldBySide={}
    for _,s in ipairs(spawners) do oldBySide[s.outputSide]=s.state==true end
    local newSides={}
    for _,s in ipairs(selected.list) do newSides[s.outputSide]=true end

    -- Only turn OFF outputs that were actually removed from the config.
    for side,state in pairs(oldBySide) do if state and not newSides[side] then redstone.setOutput(side,false) end end

    spawners=selected.list
    updateInterval=selected.status
    configUpdateInterval=selected.refresh
    configSource=source.." / "..selected.profileName

    for _,s in ipairs(spawners) do
        s.state=(not maintenanceMode) and oldBySide[s.outputSide]==true or false
        -- Writing the same state is safe and avoids any OFF->ON refresh pulse.
        redstone.setOutput(s.outputSide,s.state)
    end
    return true
end

local function installConfig(contents,source)
    if fs.exists(tempConfigFile) then fs.delete(tempConfigFile) end
    local f=fs.open(tempConfigFile,"w");if not f then return false,"Could not write temp config" end
    f.write(contents);f.close()
    local ok,cfg=pcall(dofile,tempConfigFile);if not ok then fs.delete(tempConfigFile);return false,"CONFIG ERROR: "..tostring(cfg) end
    local applied,err=applyConfig(cfg,source);if not applied then fs.delete(tempConfigFile);return false,err end
    if fs.exists(configFile) then fs.delete(configFile) end;fs.move(tempConfigFile,configFile);return true
end

local function getMasterFile(name,fresh)
    local masterID=rednet.lookup(masterProtocol,masterHostname);if not masterID then return false,"MASTER CONTROLLER NOT FOUND" end
    local requestID=computerID..":"..os.epoch("utc")..":"..name
    rednet.send(masterID,{type="get_file",file=name,requestID=requestID,fresh=fresh==true},masterProtocol)
    local deadline=os.epoch("utc")+masterTimeout*1000
    while true do
        local remain=(deadline-os.epoch("utc"))/1000;if remain<=0 then return false,"MASTER TIMEOUT" end
        local id,msg=rednet.receive(masterProtocol,remain);if not id then return false,"MASTER TIMEOUT" end
        if id==masterID and type(msg)=="table" and msg.type=="file_response" and msg.requestID==requestID then
            if not msg.success then return false,msg.error or "MASTER FILE ERROR" end
            return true,msg.contents,masterID
        end
    end
end

local function downloadConfig(fresh) local ok,data,id=getMasterFile("spawners.lua",fresh);if not ok then return false,data end;return installConfig(data,"MASTER "..id) end
local function loadLocalConfig() if not fs.exists(configFile) then return false,"No local spawners.lua" end local ok,cfg=pcall(dofile,configFile);if not ok then return false,cfg end;return applyConfig(cfg,"LOCAL CACHE") end
local function findSpawner(key) for _,s in ipairs(spawners) do if s.key==key then return s end end end
local function setSpawner(s,state) if not s then return false end;if maintenanceMode and state then state=false end;s.state=state==true;redstone.setOutput(s.outputSide,s.state);return true end
local function allOff() for _,s in ipairs(spawners) do setSpawner(s,false) end end
local function allOn() if maintenanceMode then allOff();return false end;for _,s in ipairs(spawners) do setSpawner(s,true) end;return true end

local function sendManifest() local keys={} for _,s in ipairs(spawners) do keys[#keys+1]=s.key end;rednet.broadcast({messageType="spawner_manifest",enabledKeys=keys,role="REMOTE_SPAWNER",computerID=computerID,configSource=configSource,maintenance=maintenanceMode,timestamp=os.epoch("utc")},statusProtocol) end
local function sendStatus(s) rednet.broadcast({messageType="spawner_status",spawnerKey=s.key,displayName=s.name,state=s.state==true,outputSide=s.outputSide,role="REMOTE_SPAWNER",computerID=computerID,configSource=configSource,maintenance=maintenanceMode,timestamp=os.epoch("utc")},statusProtocol) end
local function sendAll() sendManifest();for _,s in ipairs(spawners) do sendStatus(s) end end
local function sendRefresh(ok,err) rednet.broadcast({command="spawners_refresh_status",success=ok==true,error=err,role="REMOTE_SPAWNER",computerID=computerID,configSource=configSource,maintenance=maintenanceMode,timestamp=os.epoch("utc")},configStatusProtocol) end

local function draw()
    term.setBackgroundColor(colors.black);term.setTextColor(colors.white);term.clear();term.setCursorPos(1,1)
    print("REMOTE SPAWNER NODE");print("===================");term.setTextColor(colors.cyan);print("COMPUTER ID: "..computerID);term.setTextColor(colors.white);print("Config: "..configSource);print("Maintenance: "..(maintenanceMode and "ON" or "OFF"));print("")
    if #spawners==0 then print("NO ACTIVE SPAWNERS") end
    for _,s in ipairs(spawners) do print(s.name.."  ["..string.upper(s.outputSide).."]  "..(s.state and "ON" or "OFF")) end
end

local ok,err=downloadConfig(false);if not ok then print("Master config failed: "..tostring(err));local lok,lerr=loadLocalConfig();if not lok then error("Could not load spawner config: "..tostring(lerr)) end end
-- Startup is intentionally OFF. A refresh later will preserve that OFF state.
allOff();sendAll();draw()

local function maintenance(msg)
    local ts=tonumber(msg.timestamp) or 0;if ts<lastMaintenanceTimestamp then return end
    lastMaintenanceTimestamp=ts;maintenanceMode=msg.state==true;if maintenanceMode then allOff() end;sendAll();draw()
end

local function networkLoop()
    while true do
        local _,msg,protocol=rednet.receive()
        if type(msg)=="table" then
            if protocol==controlProtocol then
                if msg.command=="discover" then sendAll()
                elseif msg.command=="maintenance" then maintenance(msg)
                elseif msg.command=="all_off" then allOff();sendAll();draw()
                elseif msg.command=="all_on" then allOn();sendAll();draw()
                elseif msg.command=="spawn" and type(msg.spawnerKey)=="string" and type(msg.state)=="boolean" then local s=findSpawner(msg.spawnerKey);if s then setSpawner(s,msg.state);sendStatus(s);draw() end end
            elseif protocol==configControlProtocol and msg.command=="force_spawners_refresh" then
                local success,e=downloadConfig(true);if maintenanceMode then allOff() end;if success then sendAll();sendRefresh(true) else sendRefresh(false,e) end;draw()
            end
        end
    end
end

local function statusLoop() while true do if maintenanceMode then allOff() end;sendAll();draw();sleep(updateInterval) end end
local function configLoop() while true do sleep(configUpdateInterval);local success,e=downloadConfig(false);if maintenanceMode then allOff() end;if success then sendAll();draw() else print("Spawner config update failed: "..tostring(e)) end end end
parallel.waitForAll(networkLoop,statusLoop,configLoop)
