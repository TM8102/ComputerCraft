-- =========================================================
-- REMOTE SPAWNER NODE
-- Central config: spawners.lua from Master Controller.
-- "N/A", blank, false, or missing side = DISABLED.
-- =========================================================

local controlProtocol = "spawner_control"
local statusProtocol = "spawner_status"
local configControlProtocol = "spawner_config_control"
local configStatusProtocol = "spawner_config_status"
local masterProtocol = "cc_master_update"
local masterHostname = "master"
local masterTimeout = 2

local configFile = "spawners.lua"
local tempConfigFile = "spawners_new.lua"

local computerID = os.getComputerID()
local modemSide
local spawners = {}
local updateInterval = 4
local configUpdateInterval = 300
local configSource = "NONE"
local maintenanceMode = false
local lastMaintenanceTimestamp = 0

local sideOrder = {"front","back","left","right","top","bottom"}
local validSides = {top=true,bottom=true,left=true,right=true,front=true,back=true}

for _,side in ipairs({"top","bottom","left","right","front","back"}) do
    if peripheral.isPresent(side) and peripheral.getType(side)=="modem" then modemSide=side; break end
end
if not modemSide then error("No modem found") end
rednet.open(modemSide)

local function trim(value)
    value=tostring(value or "")
    return (value:gsub("^%s+",""):gsub("%s+$",""))
end

local function isDisabledName(value)
    if value==nil or value==false then return true end
    if type(value)~="string" then return false end
    local name=trim(value)
    if name=="" then return true end
    local upper=string.upper(name)
    return upper=="N/A" or upper=="NA" or upper=="NONE" or upper=="DISABLED"
end

local function copyTable(source)
    local result={}
    for key,value in pairs(source or {}) do result[key]=type(value)=="table" and copyTable(value) or value end
    return result
end

local function makeKey(side) return "side_"..tostring(side) end

local function simpleProfileToList(profile)
    local list={}
    for _,side in ipairs(sideOrder) do
        local value=profile[side]; local name; local enabled=true
        if type(value)=="string" then name=trim(value); enabled=not isDisabledName(name)
        elseif type(value)=="table" then name=trim(value.name or value.displayName); enabled=value.enabled~=false and not isDisabledName(name)
        elseif value==false or value==nil then enabled=false end
        if enabled and name and name~="" then list[#list+1]={key=makeKey(side),name=name,outputSide=side,enabled=true} end
    end
    return list
end

local function normalizeProfile(profile)
    if type(profile)~="table" then return nil,"Spawner profile must be a table" end
    if type(profile.spawners)=="table" then
        local result={}
        for _,entry in ipairs(copyTable(profile.spawners)) do
            local name=trim(entry.name or entry.displayName)
            if entry.enabled~=false and not isDisabledName(name) then entry.name=name; result[#result+1]=entry end
        end
        return result
    end
    return simpleProfileToList(profile)
end

local function validateSpawnerList(list)
    if type(list)~="table" then return false,"Spawner list must be a table" end
    local usedKeys,usedSides={},{}
    for index,spawner in ipairs(list) do
        if type(spawner)~="table" then return false,"Bad spawner entry "..tostring(index) end
        if type(spawner.key)~="string" or spawner.key=="" then return false,"Spawner "..tostring(index).." needs a key" end
        if usedKeys[spawner.key] then return false,"Duplicate key: "..spawner.key end; usedKeys[spawner.key]=true
        if type(spawner.name)~="string" or spawner.name=="" then return false,"Spawner "..spawner.key.." needs a name" end
        if not validSides[spawner.outputSide] then return false,"Bad output side for "..spawner.key end
        if spawner.outputSide==modemSide then return false,spawner.key.." cannot use modem side "..modemSide end
        if usedSides[spawner.outputSide] then return false,"Two enabled spawners use "..spawner.outputSide end
        usedSides[spawner.outputSide]=true
    end
    return true
end

local function selectComputerConfig(config)
    if type(config)~="table" then return nil,"Config must return a table" end
    local profile,profileName
    if type(config.computers)=="table" then profile=config.computers[computerID]; if profile then profileName="COMPUTER "..computerID end end
    if not profile then profile=config.default or {}; profileName="DEFAULT" end
    local configured,normalizeError=normalizeProfile(profile)
    if not configured then return nil,normalizeError end
    local valid,validationError=validateSpawnerList(configured)
    if not valid then return nil,validationError end
    return {spawners=configured,updateInterval=tonumber(config.statusUpdateInterval) or 4,configUpdateInterval=tonumber(config.configUpdateInterval) or 300,profileName=profileName}
end

local function allPhysicalOff(list)
    for _,spawner in ipairs(list or {}) do
        if validSides[spawner.outputSide] and spawner.outputSide~=modemSide then redstone.setOutput(spawner.outputSide,false) end
    end
end

local function applyConfig(config,source)
    local selected,selectionError=selectComputerConfig(config)
    if not selected then return false,selectionError end
    local oldStates={}
    for _,spawner in ipairs(spawners) do oldStates[spawner.key]=spawner.state==true end
    allPhysicalOff(spawners)
    spawners=selected.spawners; updateInterval=selected.updateInterval; configUpdateInterval=selected.configUpdateInterval; configSource=source.." / "..selected.profileName
    for _,spawner in ipairs(spawners) do
        spawner.state=not maintenanceMode and oldStates[spawner.key]==true or false
        redstone.setOutput(spawner.outputSide,spawner.state)
    end
    return true
end

local function installConfig(contents,source)
    if fs.exists(tempConfigFile) then fs.delete(tempConfigFile) end
    local file=fs.open(tempConfigFile,"w")
    if not file then return false,"Could not write temporary config" end
    file.write(contents); file.close()
    local ok,config=pcall(dofile,tempConfigFile)
    if not ok then fs.delete(tempConfigFile); return false,"CONFIG ERROR: "..tostring(config) end
    local applied,applyError=applyConfig(config,source)
    if not applied then fs.delete(tempConfigFile); return false,applyError end
    if fs.exists(configFile) then fs.delete(configFile) end
    fs.move(tempConfigFile,configFile)
    return true
end

local function getMasterFile(fileName,fresh)
    local masterID=rednet.lookup(masterProtocol,masterHostname)
    if not masterID then return false,"MASTER CONTROLLER NOT FOUND" end
    local requestID=tostring(computerID)..":"..tostring(os.epoch("utc"))..":"..fileName
    rednet.send(masterID,{type="get_file",file=fileName,requestID=requestID,fresh=fresh==true},masterProtocol)
    local deadline=os.epoch("utc")+masterTimeout*1000
    while true do
        local remaining=(deadline-os.epoch("utc"))/1000
        if remaining<=0 then return false,"MASTER TIMEOUT" end
        local senderID,message=rednet.receive(masterProtocol,remaining)
        if not senderID then return false,"MASTER TIMEOUT" end
        if senderID==masterID and type(message)=="table" and message.type=="file_response" and message.requestID==requestID then
            if not message.success then return false,message.error or "MASTER FILE ERROR" end
            if type(message.contents)~="string" or message.contents=="" then return false,"MASTER RETURNED EMPTY FILE" end
            return true,message.contents,masterID
        end
    end
end

local function downloadConfig(fresh)
    local ok,contents,masterID=getMasterFile("spawners.lua",fresh)
    if not ok then return false,contents end
    return installConfig(contents,"MASTER "..tostring(masterID))
end

local function loadLocalConfig()
    if not fs.exists(configFile) then return false,"No local spawners.lua" end
    local ok,config=pcall(dofile,configFile)
    if not ok then return false,tostring(config) end
    return applyConfig(config,"LOCAL CACHE")
end

local function findSpawner(key)
    for _,spawner in ipairs(spawners) do if spawner.key==key then return spawner end end
end

local function setSpawnerState(spawner,state)
    if not spawner then return false end
    if maintenanceMode and state==true then state=false end
    spawner.state=state==true; redstone.setOutput(spawner.outputSide,spawner.state); return true
end

local function turnEverythingOff() for _,spawner in ipairs(spawners) do setSpawnerState(spawner,false) end end
local function turnEverythingOn()
    if maintenanceMode then turnEverythingOff(); return false end
    for _,spawner in ipairs(spawners) do setSpawnerState(spawner,true) end
    return true
end

local function sendManifest()
    local keys={}; for _,spawner in ipairs(spawners) do keys[#keys+1]=spawner.key end
    rednet.broadcast({messageType="spawner_manifest",enabledKeys=keys,role="REMOTE_SPAWNER",computerID=computerID,configSource=configSource,maintenance=maintenanceMode,timestamp=os.epoch("utc")},statusProtocol)
end

local function sendSpawnerStatus(spawner)
    rednet.broadcast({messageType="spawner_status",spawnerKey=spawner.key,displayName=spawner.name,state=spawner.state==true,outputSide=spawner.outputSide,role="REMOTE_SPAWNER",computerID=computerID,configSource=configSource,maintenance=maintenanceMode,timestamp=os.epoch("utc")},statusProtocol)
end
local function sendAllStatuses() sendManifest(); for _,spawner in ipairs(spawners) do sendSpawnerStatus(spawner) end end

local function sendRefreshStatus(success,errorMessage)
    rednet.broadcast({command="spawners_refresh_status",success=success==true,error=errorMessage,role="REMOTE_SPAWNER",computerID=computerID,configSource=configSource,maintenance=maintenanceMode,timestamp=os.epoch("utc")},configStatusProtocol)
end

local function drawScreen()
    term.setBackgroundColor(colors.black); term.setTextColor(colors.white); term.clear(); term.setCursorPos(1,1)
    print("REMOTE SPAWNER NODE"); print("==================="); term.setTextColor(colors.cyan); print("COMPUTER ID: "..computerID); term.setTextColor(colors.white); print("Modem: "..string.upper(modemSide)); print("Config: "..configSource)
    if maintenanceMode then term.setTextColor(colors.orange); print("MAINTENANCE LOCKOUT: ON"); term.setTextColor(colors.white) else print("Maintenance: OFF") end
    print("")
    if #spawners==0 then term.setTextColor(colors.orange); print("NO ACTIVE SPAWNERS"); print("Add COMPUTER ID "..computerID); print("to spawners.lua, then REFRESH."); term.setTextColor(colors.white) end
    for index,spawner in ipairs(spawners) do print(index..". "..spawner.name); print("   Side: "..string.upper(spawner.outputSide)); term.setTextColor(spawner.state and colors.lime or colors.red); print("   "..(spawner.state and "ON" or "OFF")); term.setTextColor(colors.white) end
end

local downloaded,downloadError=downloadConfig(false)
if not downloaded then
    print("Master config failed: "..tostring(downloadError))
    local loaded,loadError=loadLocalConfig(); if not loaded then error("Could not load spawner config: "..tostring(loadError)) end
end
turnEverythingOff(); sendAllStatuses(); drawScreen()

local function applyMaintenanceCommand(message)
    local timestamp=tonumber(message.timestamp) or 0
    if timestamp<lastMaintenanceTimestamp then return false end
    lastMaintenanceTimestamp=timestamp; maintenanceMode=message.state==true
    if maintenanceMode then turnEverythingOff() end
    sendAllStatuses(); drawScreen(); return true
end

local function networkLoop()
    while true do
        local _,message,protocol=rednet.receive()
        if type(message)=="table" then
            if protocol==controlProtocol then
                if message.command=="discover" then sendAllStatuses()
                elseif message.command=="maintenance" then applyMaintenanceCommand(message)
                elseif message.command=="all_off" then turnEverythingOff(); sendAllStatuses(); drawScreen()
                elseif message.command=="all_on" then turnEverythingOn(); sendAllStatuses(); drawScreen()
                elseif message.command=="spawn" and type(message.spawnerKey)=="string" and type(message.state)=="boolean" then
                    local spawner=findSpawner(message.spawnerKey); if spawner then setSpawnerState(spawner,message.state); sendSpawnerStatus(spawner); drawScreen() end
                end
            elseif protocol==configControlProtocol and message.command=="force_spawners_refresh" then
                local success,refreshError=downloadConfig(true)
                if maintenanceMode then turnEverythingOff() end
                if success then sendAllStatuses(); sendRefreshStatus(true,nil) else sendRefreshStatus(false,refreshError) end
                drawScreen()
            end
        end
    end
end

local function statusLoop() while true do if maintenanceMode then turnEverythingOff() end; sendAllStatuses(); drawScreen(); sleep(updateInterval) end end
local function configLoop()
    while true do
        sleep(configUpdateInterval)
        local success,configError=downloadConfig(false)
        if maintenanceMode then turnEverythingOff() end
        if success then sendAllStatuses(); drawScreen() else print("Spawner config update failed: "..tostring(configError)) end
    end
end

parallel.waitForAll(networkLoop,statusLoop,configLoop)
