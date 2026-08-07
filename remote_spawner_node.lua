-- =========================================================
-- REMOTE SPAWNER NODE
-- Central config: spawners.lua on GitHub.
-- Supports live config refresh + status replies to the
-- Mob Control Panel and a hard maintenance lockout.
-- =========================================================

local controlProtocol = "spawner_control"
local statusProtocol = "spawner_status"
local configControlProtocol = "spawner_config_control"
local configStatusProtocol = "spawner_config_status"

local githubConfigURL =
    "https://api.github.com/repos/TM8102/ComputerCraft/contents/spawners.lua?ref=main"
local configFile = "spawners.lua"
local tempConfigFile = "spawners_new.lua"

local computerID = os.getComputerID()
local modemSide
local spawners = {}
local updateInterval = 4
local configUpdateInterval = 300
local configSource = "NONE"
local maintenanceMode = false

local validSides = {
    top=true,bottom=true,left=true,right=true,front=true,back=true
}

for _,side in ipairs({"top","bottom","left","right","front","back"}) do
    if peripheral.isPresent(side) and peripheral.getType(side)=="modem" then
        modemSide=side
        break
    end
end
if not modemSide then error("No modem found") end
rednet.open(modemSide)

local function copyTable(t)
    local out={}
    for k,v in pairs(t or {}) do out[k]=type(v)=="table" and copyTable(v) or v end
    return out
end

local function validateSpawnerList(list)
    if type(list)~="table" then return false,"Spawner list must be a table" end
    local keys,sides={},{}
    for i,s in ipairs(list) do
        if type(s)~="table" then return false,"Bad spawner entry "..i end
        s.enabled=s.enabled~=false
        if s.enabled then
            if type(s.key)~="string" or s.key=="" then return false,"Spawner "..i.." needs a key" end
            if keys[s.key] then return false,"Duplicate key: "..s.key end
            keys[s.key]=true
            if type(s.name)~="string" or s.name=="" then return false,"Spawner "..s.key.." needs a name" end
            if not validSides[s.outputSide] then return false,"Bad output side for "..s.key end
            if s.outputSide==modemSide then return false,s.key.." cannot use modem side "..modemSide end
            if sides[s.outputSide] then return false,"Two enabled spawners use "..s.outputSide end
            sides[s.outputSide]=true
        end
    end
    return true
end

local function selectComputerConfig(config)
    if type(config)~="table" then return nil,"Config must return a table" end
    local profile,profileName
    if type(config.computers)=="table" then
        profile=config.computers[computerID]
        if profile then profileName="COMPUTER "..computerID end
    end
    if not profile then profile=config.default; profileName="DEFAULT" end
    if type(profile)~="table" then return nil,"No profile for computer "..computerID end
    local configured=copyTable(profile.spawners or {})
    local ok,err=validateSpawnerList(configured)
    if not ok then return nil,err end
    return {
        spawners=configured,
        updateInterval=tonumber(config.statusUpdateInterval) or 4,
        configUpdateInterval=tonumber(config.configUpdateInterval) or 300,
        profileName=profileName
    }
end

local function allPhysicalOff(list)
    for _,s in ipairs(list or {}) do
        if s.enabled and validSides[s.outputSide] and s.outputSide~=modemSide then
            redstone.setOutput(s.outputSide,false)
        end
    end
end

local function applyConfig(config,source)
    local selected,err=selectComputerConfig(config)
    if not selected then return false,err end
    local oldStates={}
    for _,s in ipairs(spawners) do if s.enabled and s.key then oldStates[s.key]=s.state==true end end
    allPhysicalOff(spawners)
    spawners=selected.spawners
    updateInterval=selected.updateInterval
    configUpdateInterval=selected.configUpdateInterval
    configSource=source.." / "..selected.profileName
    for _,s in ipairs(spawners) do
        s.state=(not maintenanceMode) and oldStates[s.key]==true or false
        if s.enabled then redstone.setOutput(s.outputSide,s.state) end
    end
    return true
end

local function installConfig(contents,source)
    if fs.exists(tempConfigFile) then fs.delete(tempConfigFile) end
    local f=fs.open(tempConfigFile,"w")
    if not f then return false,"Could not write temporary config" end
    f.write(contents); f.close()
    local ok,config=pcall(dofile,tempConfigFile)
    if not ok then fs.delete(tempConfigFile); return false,"CONFIG ERROR: "..tostring(config) end
    local applied,err=applyConfig(config,source)
    if not applied then fs.delete(tempConfigFile); return false,err end
    if fs.exists(configFile) then fs.delete(configFile) end
    fs.move(tempConfigFile,configFile)
    return true
end

local function downloadConfig()
    local url=githubConfigURL.."&cb="..tostring(os.epoch("utc"))
    local r,err=http.get(url,{
        ["User-Agent"]="CC-Tweaked",
        ["Accept"]="application/vnd.github.raw+json",
        ["Cache-Control"]="no-cache, no-store",
        ["Pragma"]="no-cache"
    })
    if not r then return false,"GitHub API failed: "..tostring(err) end
    local code=r.getResponseCode and r.getResponseCode() or 200
    local contents=r.readAll(); r.close()
    if code<200 or code>=300 then return false,"GitHub HTTP "..code end
    if not contents or contents=="" then return false,"GitHub returned empty spawners.lua" end
    return installConfig(contents,"GITHUB")
end

local function loadLocalConfig()
    if not fs.exists(configFile) then return false,"No local spawners.lua" end
    local ok,config=pcall(dofile,configFile)
    if not ok then return false,tostring(config) end
    return applyConfig(config,"LOCAL CACHE")
end

local function findSpawner(key)
    for _,s in ipairs(spawners) do if s.enabled and s.key==key then return s end end
end

local function setSpawnerState(s,state)
    if not s or not s.enabled then return false end
    if maintenanceMode and state==true then state=false end
    s.state=state==true
    redstone.setOutput(s.outputSide,s.state)
    return true
end

local function turnEverythingOff()
    for _,s in ipairs(spawners) do if s.enabled then setSpawnerState(s,false) end end
end

local function turnEverythingOn()
    if maintenanceMode then turnEverythingOff(); return false end
    for _,s in ipairs(spawners) do if s.enabled then setSpawnerState(s,true) end end
    return true
end

local function sendManifest()
    local keys={}
    for _,s in ipairs(spawners) do if s.enabled then keys[#keys+1]=s.key end end
    rednet.broadcast({
        messageType="spawner_manifest",enabledKeys=keys,role="REMOTE_SPAWNER",
        computerID=computerID,configSource=configSource,maintenance=maintenanceMode,
        timestamp=os.epoch("utc")
    },statusProtocol)
end

local function sendSpawnerStatus(s)
    if not s.enabled then return end
    rednet.broadcast({
        messageType="spawner_status",spawnerKey=s.key,displayName=s.name,
        state=s.state==true,outputSide=s.outputSide,role="REMOTE_SPAWNER",
        computerID=computerID,configSource=configSource,maintenance=maintenanceMode,
        timestamp=os.epoch("utc")
    },statusProtocol)
end

local function sendAllStatuses()
    sendManifest()
    for _,s in ipairs(spawners) do if s.enabled then sendSpawnerStatus(s) end end
end

local function sendRefreshStatus(success,errorMessage)
    rednet.broadcast({
        command="spawners_refresh_status",success=success==true,error=errorMessage,
        role="REMOTE_SPAWNER",computerID=computerID,configSource=configSource,
        maintenance=maintenanceMode,timestamp=os.epoch("utc")
    },configStatusProtocol)
end

local function drawScreen()
    term.setBackgroundColor(colors.black); term.setTextColor(colors.white)
    term.clear(); term.setCursorPos(1,1)
    print("REMOTE SPAWNER NODE")
    print("===================")
    print("Computer ID: "..computerID)
    print("Modem: "..string.upper(modemSide))
    print("Config: "..configSource)
    if maintenanceMode then
        term.setTextColor(colors.orange); print("MAINTENANCE LOCKOUT: ON"); term.setTextColor(colors.white)
    else
        print("Maintenance: OFF")
    end
    print("")
    if #spawners==0 then term.setTextColor(colors.orange); print("NO SPAWNERS CONFIGURED"); term.setTextColor(colors.white) end
    for i,s in ipairs(spawners) do
        if s.enabled then
            print(i..". "..s.name)
            print("   Key: "..s.key)
            print("   Side: "..string.upper(s.outputSide))
            term.setTextColor(s.state and colors.lime or colors.red)
            print("   "..(s.state and "ON" or "OFF"))
            term.setTextColor(colors.white)
        else
            print(i..". DISABLED")
        end
    end
end

local downloaded,downloadError=downloadConfig()
if not downloaded then
    print("GitHub config failed: "..tostring(downloadError))
    local loaded,loadError=loadLocalConfig()
    if not loaded then error("Could not load spawner config: "..tostring(loadError)) end
end

turnEverythingOff(); sendAllStatuses(); drawScreen()

local function networkLoop()
    while true do
        local _,message,protocol=rednet.receive()
        if type(message)=="table" then
            if protocol==controlProtocol then
                if message.command=="discover" then
                    sendAllStatuses()
                elseif message.command=="maintenance" then
                    maintenanceMode=message.state==true
                    if maintenanceMode then turnEverythingOff() end
                    sendAllStatuses(); drawScreen()
                elseif message.command=="all_off" then
                    turnEverythingOff(); sendAllStatuses(); drawScreen()
                elseif message.command=="all_on" then
                    turnEverythingOn(); sendAllStatuses(); drawScreen()
                elseif message.command=="spawn"
                    and type(message.spawnerKey)=="string"
                    and type(message.state)=="boolean" then
                    local s=findSpawner(message.spawnerKey)
                    if s then setSpawnerState(s,message.state); sendSpawnerStatus(s); drawScreen() end
                end
            elseif protocol==configControlProtocol
                and message.command=="force_spawners_refresh" then
                local success,err=downloadConfig()
                if maintenanceMode then turnEverythingOff() end
                if success then sendAllStatuses(); sendRefreshStatus(true,nil)
                else sendRefreshStatus(false,err) end
                drawScreen()
            end
        end
    end
end

local function statusLoop()
    while true do
        if maintenanceMode then turnEverythingOff() end
        sendAllStatuses(); drawScreen(); sleep(updateInterval)
    end
end

local function configLoop()
    while true do
        sleep(configUpdateInterval)
        local success,err=downloadConfig()
        if maintenanceMode then turnEverythingOff() end
        if success then sendAllStatuses(); drawScreen()
        else print("Spawner config update failed: "..tostring(err)) end
    end
end

parallel.waitForAll(networkLoop,statusLoop,configLoop)
