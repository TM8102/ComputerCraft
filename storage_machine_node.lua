-- =========================================================
-- STORAGE + MACHINE NODE
-- Config comes from the Master Controller, not GitHub.
-- =========================================================

local modemSide = "back"
local masterProtocol = "cc_master_update"
local masterHostname = "master"
local masterTimeout = 2

local configFile = "targets.lua"
local tempConfigFile = "targets_new.lua"

local storageSides = {top=true,bottom=true,left=true,right=true,front=true,back=true}
local storageControlProtocol = "inventory_control"
local storageStatusProtocol = "inventory_status"
local machineControlProtocol = "resource_machine_control"
local machineStatusProtocol = "resource_machine_status"
local configControlProtocol = "config_control"
local configStatusProtocol = "config_status"

local updateInterval = 2
local configUpdateInterval = 300
local computerID = os.getComputerID()

if not peripheral.isPresent(modemSide) then error("No modem found on " .. modemSide) end
rednet.open(modemSide)

local itemConfig = {}
local knownItems = {}
local localMachines = {}
local machineBySide = {}
local machineByKey = {}
local machineSides = {}
local lastConfigStatus = "NONE"
local lastConfigSHA = "UNKNOWN"
local validSides = {top=true,bottom=true,left=true,right=true,front=true,back=true}

local function validateConfig(config)
    if type(config) ~= "table" then return false,"Config must return a table" end
    for itemID,settings in pairs(config) do
        if type(itemID)~="string" then return false,"Invalid item ID" end
        if type(settings)~="table" then return false,"Invalid config for "..tostring(itemID) end
        settings.target=tonumber(settings.target)
        if not settings.target or settings.target<=0 then return false,"Invalid target for "..tostring(itemID) end
        if settings.machine then
            local machine=settings.machine
            if type(machine)~="table" then return false,"Invalid machine config for "..itemID end
            machine.computerID=tonumber(machine.computerID)
            machine.startBelow=tonumber(machine.startBelow) or 50
            machine.stopAt=tonumber(machine.stopAt) or 100
            if not machine.computerID then return false,"Missing computerID for "..itemID end
            if type(machine.machineKey)~="string" or machine.machineKey=="" then return false,"Missing machineKey for "..itemID end
            if not validSides[machine.side] then return false,"Invalid machine side for "..itemID end
        end
    end
    return true
end

local function installConfig(contents,source)
    if fs.exists(tempConfigFile) then fs.delete(tempConfigFile) end
    local file=fs.open(tempConfigFile,"w")
    if not file then return false,"Could not write temp config" end
    file.write(contents); file.close()
    local ok,config=pcall(dofile,tempConfigFile)
    if not ok then fs.delete(tempConfigFile); return false,"CONFIG ERROR: "..tostring(config) end
    local valid,validationError=validateConfig(config)
    if not valid then fs.delete(tempConfigFile); return false,validationError end
    if fs.exists(configFile) then fs.delete(configFile) end
    fs.move(tempConfigFile,configFile)
    itemConfig=config; knownItems={}
    lastConfigStatus=source or "MASTER"; lastConfigSHA="MASTER"
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

local function downloadTargets(fresh)
    local ok,contents,masterID=getMasterFile("targets.lua",fresh)
    if not ok then return false,contents end
    return installConfig(contents,"MASTER "..tostring(masterID))
end

local function loadLocalConfig()
    if not fs.exists(configFile) then return false,"NO LOCAL CONFIG" end
    local ok,config=pcall(dofile,configFile)
    if not ok then return false,tostring(config) end
    local valid,validationError=validateConfig(config)
    if not valid then return false,validationError end
    itemConfig=config; knownItems={}; lastConfigStatus="LOCAL CACHE"; lastConfigSHA="LOCAL"; return true
end

local function makeDisplayName(itemID)
    local name=string.match(itemID,":(.+)$") or itemID
    name=string.gsub(name,"_"," "); name=string.gsub(" "..name,"%W%l",string.upper)
    return string.sub(name,2)
end

local function getDisplayName(itemID)
    local settings=itemConfig[itemID]
    if settings and type(settings.displayName)=="string" and settings.displayName~="" then return settings.displayName end
    return makeDisplayName(itemID)
end

local function rebuildLocalMachines()
    local oldStateBySide={}
    for side,machine in pairs(machineBySide) do oldStateBySide[side]=machine.state==true; redstone.setOutput(side,false) end
    localMachines={}; machineBySide={}; machineByKey={}; machineSides={}
    for itemID,settings in pairs(itemConfig) do
        local machine=settings.machine
        if machine and tonumber(machine.computerID)==computerID then
            local side=machine.side; local record=machineBySide[side]
            if not record then record={side=side,state=oldStateBySide[side]==true,itemIDs={},machineKeys={},targets={},lastCommand=0}; machineBySide[side]=record; localMachines[#localMachines+1]=record; machineSides[side]=true end
            record.itemIDs[#record.itemIDs+1]=itemID; record.machineKeys[#record.machineKeys+1]=machine.machineKey; record.targets[itemID]=tonumber(settings.target) or 0; machineByKey[machine.machineKey]=record
        end
    end
    for _,machine in ipairs(localMachines) do redstone.setOutput(machine.side,machine.state) end
end

local function scanItemInventory(p,amounts)
    local ok,items=pcall(function() return p.list() end)
    if not ok or type(items)~="table" then return false,tostring(items) end
    for _,stack in pairs(items) do if type(stack)=="table" and type(stack.name)=="string" then amounts[stack.name]=(amounts[stack.name] or 0)+(tonumber(stack.count) or 0) end end
    return true
end

local function scanFluidInventory(p,amounts)
    local ok,tanks=pcall(function() return p.tanks() end)
    if not ok or type(tanks)~="table" then return false,tostring(tanks) end
    for _,tank in pairs(tanks) do if type(tank)=="table" and type(tank.name)=="string" then amounts[tank.name]=(amounts[tank.name] or 0)+(tonumber(tank.amount) or 0) end end
    return true
end

local function scanDirectStorage()
    local amounts,detectedSources,errors={},{},{}
    for side,enabled in pairs(storageSides) do
        if enabled and side~=modemSide and not machineSides[side] and peripheral.isPresent(side) then
            local p=peripheral.wrap(side)
            if p then
                local used=false
                if type(p.list)=="function" then used=true; local ok,err=scanItemInventory(p,amounts); if ok then detectedSources[#detectedSources+1]={side=side,type="item"} else errors[#errors+1]=string.upper(side).." ITEM: "..tostring(err) end end
                if type(p.tanks)=="function" then used=true; local ok,err=scanFluidInventory(p,amounts); if ok then detectedSources[#detectedSources+1]={side=side,type="fluid"} else errors[#errors+1]=string.upper(side).." FLUID: "..tostring(err) end end
                if not used then errors[#errors+1]=string.upper(side).." NOT STORAGE" end
            end
        end
    end
    return amounts,detectedSources,errors
end

local function updateKnownItems(amounts)
    for itemID in pairs(amounts) do if itemConfig[itemID] then knownItems[itemID]=true end end
    for itemID in pairs(knownItems) do if not itemConfig[itemID] then knownItems[itemID]=nil end end
end

local function sendStorageManifest()
    local keys={}; for itemID in pairs(knownItems) do keys[#keys+1]=itemID end; table.sort(keys)
    rednet.broadcast({messageType="storage_manifest",enabledKeys=keys,role="NODE",computerID=computerID,configSHA=lastConfigSHA,timestamp=os.epoch("utc")},storageStatusProtocol)
end

local function sendStorageUpdate(itemID,amount)
    local settings=itemConfig[itemID]; if not settings then return end
    local target=tonumber(settings.target) or 0
    rednet.broadcast({messageType="inventory_update",storageKey=itemID,itemID=itemID,displayName=getDisplayName(itemID),amount=tonumber(amount) or 0,targetAmount=target,percent=target>0 and ((tonumber(amount) or 0)/target*100) or 0,found=true,online=true,error=nil,role="NODE",computerID=computerID,configSHA=lastConfigSHA,timestamp=os.epoch("utc")},storageStatusProtocol)
end

local function sendMachineStatus(machine)
    for _,itemID in ipairs(machine.itemIDs) do
        rednet.broadcast({messageType="resource_machine_status",itemID=itemID,machineKey=itemConfig[itemID] and itemConfig[itemID].machine and itemConfig[itemID].machine.machineKey or nil,side=machine.side,state=machine.state==true,target=machine.targets[itemID],role="NODE",computerID=computerID,configSHA=lastConfigSHA,timestamp=os.epoch("utc")},machineStatusProtocol)
    end
end
local function sendAllMachineStatus() for _,machine in ipairs(localMachines) do sendMachineStatus(machine) end end

local function reportStorage()
    local amounts,detectedSources,errors=scanDirectStorage(); updateKnownItems(amounts); sendStorageManifest(); for itemID in pairs(knownItems) do sendStorageUpdate(itemID,amounts[itemID] or 0) end
    return amounts,detectedSources,errors
end

local function processAutoSet(message)
    local machine=nil
    if message.side then machine=machineBySide[message.side] end
    if not machine and type(message.machineKey)=="string" then machine=machineByKey[message.machineKey] end
    if not machine and type(message.machineKeys)=="table" then for _,machineKey in ipairs(message.machineKeys) do machine=machineByKey[machineKey]; if machine then break end end end
    if not machine then return end
    machine.state=message.state==true; machine.lastCommand=os.epoch("utc"); redstone.setOutput(machine.side,machine.state); sendMachineStatus(machine)
end

local function sendRefreshStatus(success,errorMessage)
    rednet.broadcast({command="targets_refresh_status",success=success==true,error=errorMessage,role="NODE",computerID=computerID,configSHA=lastConfigSHA,timestamp=os.epoch("utc")},configStatusProtocol)
end

local function forceTargetsRefresh()
    local success,refreshError=downloadTargets(true)
    if not success then sendRefreshStatus(false,refreshError); return false end
    rebuildLocalMachines(); sendStorageManifest(); reportStorage(); sendAllMachineStatus(); sendRefreshStatus(true,nil); return true
end

local function drawLocalScreen()
    local amounts,detectedSources,errors=scanDirectStorage(); updateKnownItems(amounts)
    term.setBackgroundColor(colors.black); term.setTextColor(colors.white); term.clear(); term.setCursorPos(1,1)
    print("STORAGE + MACHINE NODE"); print("======================"); print("Computer: "..computerID); print("Config: "..lastConfigStatus); print("SHA: "..string.sub(lastConfigSHA,1,12)); print("")
    print("STORAGE:")
    if #detectedSources==0 then term.setTextColor(colors.red); print(" NONE FOUND"); term.setTextColor(colors.white) else for _,source in ipairs(detectedSources) do term.setTextColor(source.type=="fluid" and colors.lightBlue or colors.lime); print(" "..string.upper(source.side).." "..string.upper(source.type)); term.setTextColor(colors.white) end end
    if #errors>0 then print(""); term.setTextColor(colors.orange); print("WARNINGS:"); for _,err in ipairs(errors) do print(" "..tostring(err)) end; term.setTextColor(colors.white) end
    print(""); print("RESOURCES:")
    local sortedKnown={}; for itemID in pairs(knownItems) do sortedKnown[#sortedKnown+1]=itemID end; table.sort(sortedKnown)
    if #sortedKnown==0 then print(" NONE") else for _,itemID in ipairs(sortedKnown) do print(" "..getDisplayName(itemID)); print("  "..tostring(math.floor(amounts[itemID] or 0))) end end
    print(""); print("MACHINES:")
    if #localMachines==0 then print(" NONE") else for _,machine in ipairs(localMachines) do print(" "..string.upper(machine.side).." ("..#machine.itemIDs.." resource"..(#machine.itemIDs==1 and "" or "s")..")"); term.setTextColor(machine.state and colors.lime or colors.red); print(machine.state and "  RUNNING" or "  STOPPED"); term.setTextColor(colors.white) end end
end

local downloaded,downloadError=downloadTargets(false)
if not downloaded then
    print("Master config unavailable:"); print(tostring(downloadError)); print("Using local targets.lua...")
    local loaded,loadError=loadLocalConfig(); if not loaded then error("Could not load targets.lua: "..tostring(loadError)) end
else print("targets.lua updated from Master Controller.") end
rebuildLocalMachines()

local function reportingLoop() while true do reportStorage(); sendAllMachineStatus(); sleep(updateInterval) end end
local function displayLoop() while true do drawLocalScreen(); sleep(1) end end
local function configLoop()
    while true do
        sleep(configUpdateInterval)
        local success,configError=downloadTargets(false)
        if success then rebuildLocalMachines(); sendStorageManifest(); reportStorage(); sendAllMachineStatus() else print("Master config update failed:"); print(tostring(configError)) end
    end
end
local function networkLoop()
    while true do
        local _,message,protocol=rednet.receive()
        if protocol==machineControlProtocol and type(message)=="table" and message.command=="auto_set" then processAutoSet(message)
        elseif protocol==storageControlProtocol and type(message)=="table" and message.command=="discover" then reportStorage(); sendAllMachineStatus()
        elseif protocol==machineControlProtocol and type(message)=="table" and message.command=="discover" then sendAllMachineStatus()
        elseif protocol==configControlProtocol and type(message)=="table" and message.command=="force_targets_refresh" then forceTargetsRefresh() end
    end
end

reportStorage(); sendAllMachineStatus()
parallel.waitForAll(reportingLoop,networkLoop,configLoop,displayLoop)
