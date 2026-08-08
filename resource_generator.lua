-- =========================================================
-- RESOURCE GENERATOR NODE
-- Controls machines only. Config comes from Master Controller.
-- =========================================================

local modemSide = "top"
local masterProtocol = "cc_master_update"
local masterHostname = "master"
local masterTimeout = 2

local configFile = "targets.lua"
local tempConfigFile = "targets_new.lua"

local machineControlProtocol = "resource_machine_control"
local machineStatusProtocol = "resource_machine_status"
local configControlProtocol = "config_control"
local configStatusProtocol = "config_status"

local statusInterval = 2
local configUpdateInterval = 300
local computerID = os.getComputerID()

if not peripheral.isPresent(modemSide) then error("No modem found on " .. modemSide) end
rednet.open(modemSide)

local itemConfig = {}
local resourceByItem = {}
local machineBySide = {}
local machineByKey = {}
local lastConfigStatus = "LOCAL"

local validSides = {top=true,bottom=true,left=true,right=true,front=true,back=true}

local function validateConfig(config)
    if type(config) ~= "table" then return false, "Config must return a table" end
    for itemID, settings in pairs(config) do
        if type(itemID) ~= "string" then return false, "Invalid item ID" end
        if type(settings) ~= "table" then return false, "Invalid settings for " .. tostring(itemID) end
        settings.target = tonumber(settings.target)
        if not settings.target or settings.target <= 0 then return false, "Invalid target for " .. tostring(itemID) end
        if settings.machine then
            local machine = settings.machine
            machine.computerID = tonumber(machine.computerID)
            machine.startBelow = tonumber(machine.startBelow) or 50
            machine.stopAt = tonumber(machine.stopAt) or 100
            if not machine.computerID then return false, "Invalid computerID for " .. itemID end
            if type(machine.machineKey) ~= "string" or machine.machineKey == "" then return false, "Invalid machineKey for " .. itemID end
            if not validSides[machine.side] then return false, "Invalid machine side for " .. itemID end
        end
    end
    return true
end

local function installConfig(contents)
    if fs.exists(tempConfigFile) then fs.delete(tempConfigFile) end
    local file = fs.open(tempConfigFile,"w")
    if not file then return false,"COULD NOT WRITE TEMP CONFIG" end
    file.write(contents); file.close()
    local ok, config = pcall(dofile,tempConfigFile)
    if not ok then fs.delete(tempConfigFile); return false,"CONFIG ERROR: "..tostring(config) end
    local valid, validationError = validateConfig(config)
    if not valid then fs.delete(tempConfigFile); return false,validationError end
    if fs.exists(configFile) then fs.delete(configFile) end
    fs.move(tempConfigFile,configFile)
    itemConfig = config
    return true
end

local function getMasterFile(fileName,fresh)
    local masterID = rednet.lookup(masterProtocol,masterHostname)
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

local function downloadTargets(fresh)
    local ok,contents,masterID=getMasterFile("targets.lua",fresh)
    if not ok then return false,contents end
    local installed,err=installConfig(contents)
    if installed then lastConfigStatus="MASTER "..tostring(masterID) end
    return installed,err
end

local function loadLocalConfig()
    if not fs.exists(configFile) then return false,"NO CONFIG" end
    local ok,config=pcall(dofile,configFile)
    if not ok then return false,tostring(config) end
    local valid,validationError=validateConfig(config)
    if not valid then return false,validationError end
    itemConfig=config; lastConfigStatus="LOCAL CACHE"; return true
end

local function makeDisplayName(itemID)
    local name=string.match(itemID,":(.+)$") or itemID
    name=string.gsub(name,"_"," ")
    name=string.gsub(" "..name,"%W%l",string.upper)
    return string.sub(name,2)
end

local function getDisplayName(itemID)
    local settings=itemConfig[itemID]
    if settings and settings.displayName and settings.displayName~="" then return settings.displayName end
    return makeDisplayName(itemID)
end

local function rebuildMachines()
    local oldStateBySide={}
    for side,machine in pairs(machineBySide) do oldStateBySide[side]=machine.state==true; redstone.setOutput(side,false) end
    resourceByItem={}; machineBySide={}; machineByKey={}
    for itemID,settings in pairs(itemConfig) do
        local machine=settings.machine
        if machine and tonumber(machine.computerID)==computerID then
            local side=machine.side
            local physical=machineBySide[side]
            if not physical then
                physical={side=side,state=oldStateBySide[side]==true,itemIDs={},machineKeys={},lastCommand=0}
                machineBySide[side]=physical
            end
            physical.itemIDs[#physical.itemIDs+1]=itemID
            physical.machineKeys[#physical.machineKeys+1]=machine.machineKey
            machineByKey[machine.machineKey]=physical
            resourceByItem[itemID]={itemID=itemID,displayName=getDisplayName(itemID),side=side,machineKey=machine.machineKey,target=tonumber(settings.target) or 0,amount=nil,percent=nil}
        end
    end
    for side,machine in pairs(machineBySide) do redstone.setOutput(side,machine.state) end
end

local downloaded,downloadError=downloadTargets(false)
if not downloaded then
    print("Master config unavailable:"); print(tostring(downloadError)); print("Using local targets.lua...")
    local loaded,loadError=loadLocalConfig()
    if not loaded then error("Could not load targets.lua: "..tostring(loadError)) end
else
    print("targets.lua updated from Master Controller.")
end
rebuildMachines()

local function sendMachineStatus(machine)
    for _,itemID in ipairs(machine.itemIDs) do
        local resource=resourceByItem[itemID]
        if resource then
            rednet.broadcast({messageType="resource_machine_status",role="RESOURCE",itemID=itemID,displayName=resource.displayName,machineKey=resource.machineKey,side=machine.side,state=machine.state==true,amount=resource.amount,percent=resource.percent,target=resource.target,computerID=computerID,timestamp=os.epoch("utc")},machineStatusProtocol)
        end
    end
end

local function sendAllMachineStatus() for _,machine in pairs(machineBySide) do sendMachineStatus(machine) end end

local function applyCommandData(message,machine)
    if type(message.itemIDs)=="table" then
        for _,itemID in ipairs(message.itemIDs) do
            local resource=resourceByItem[itemID]
            if resource then
                if type(message.amounts)=="table" then resource.amount=tonumber(message.amounts[itemID]) end
                if type(message.percentages)=="table" then resource.percent=tonumber(message.percentages[itemID]) end
                if type(message.targets)=="table" then resource.target=tonumber(message.targets[itemID]) or resource.target end
            end
        end
    elseif type(message.itemID)=="string" then
        local resource=resourceByItem[message.itemID]
        if resource then resource.amount=tonumber(message.amount); resource.percent=tonumber(message.percent); resource.target=tonumber(message.target) or resource.target end
    end
end

local function processAutoSet(message)
    if type(message)~="table" then return end
    local machine=nil
    if message.side then machine=machineBySide[message.side] end
    if not machine and type(message.machineKey)=="string" then machine=machineByKey[message.machineKey] end
    if not machine and type(message.machineKeys)=="table" then
        for _,machineKey in ipairs(message.machineKeys) do machine=machineByKey[machineKey]; if machine then break end end
    end
    if not machine then return end
    applyCommandData(message,machine)
    machine.state=message.state==true; machine.lastCommand=os.epoch("utc")
    redstone.setOutput(machine.side,machine.state); sendMachineStatus(machine)
end

local function sendRefreshStatus(success,errorMessage)
    rednet.broadcast({command="targets_refresh_status",success=success==true,error=errorMessage,role="RESOURCE",computerID=computerID,timestamp=os.epoch("utc")},configStatusProtocol)
end

local function forceTargetsRefresh()
    local success,refreshError=downloadTargets(true)
    if not success then sendRefreshStatus(false,refreshError); return false end
    rebuildMachines(); sendAllMachineStatus(); sendRefreshStatus(true,nil); return true
end

local function drawScreen()
    term.setBackgroundColor(colors.black); term.setTextColor(colors.white); term.clear(); term.setCursorPos(1,1)
    print("RESOURCE GENERATOR"); print("=================="); print("Computer: "..computerID); print("Config: "..lastConfigStatus); print(""); print("MACHINES:")
    local sides={"top","bottom","left","right","front","back"}; local found=false
    for _,side in ipairs(sides) do
        local machine=machineBySide[side]
        if machine then
            found=true; print(" "..string.upper(side).." ("..#machine.itemIDs.." resource"..(#machine.itemIDs==1 and "" or "s")..")")
            term.setTextColor(machine.state and colors.lime or colors.red); print(machine.state and "  RUNNING" or "  STOPPED"); term.setTextColor(colors.white)
            for _,itemID in ipairs(machine.itemIDs) do
                local resource=resourceByItem[itemID]
                if resource then local detail="   "..resource.displayName; if resource.percent then detail=detail.." "..string.format("%.1f%%",resource.percent) end; print(detail) end
            end
        end
    end
    if not found then print(" NONE ASSIGNED") end
end

local function statusLoop() while true do sendAllMachineStatus(); sleep(statusInterval) end end
local function displayLoop() while true do drawScreen(); sleep(1) end end
local function configLoop()
    while true do
        sleep(configUpdateInterval)
        local success,configError=downloadTargets(false)
        if success then rebuildMachines(); sendAllMachineStatus() else print("Master config update failed:"); print(tostring(configError)) end
    end
end
local function networkLoop()
    while true do
        local _,message,protocol=rednet.receive()
        if protocol==machineControlProtocol and type(message)=="table" then
            if message.command=="auto_set" then processAutoSet(message)
            elseif message.command=="discover" then sendAllMachineStatus() end
        elseif protocol==configControlProtocol and type(message)=="table" and message.command=="force_targets_refresh" then forceTargetsRefresh() end
    end
end

sendAllMachineStatus()
parallel.waitForAll(networkLoop,statusLoop,configLoop,displayLoop)
