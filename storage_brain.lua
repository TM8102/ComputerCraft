local controllerSide = "top"
local modemSide = "back"

local targetsURL =
    "https://raw.githubusercontent.com/TM8102/ComputerCraft/main/targets.lua"

local configFile = "targets.lua"
local tempConfigFile = "targets_new.lua"

local storageControlProtocol = "inventory_control"
local storageStatusProtocol = "inventory_status"
local machineControlProtocol = "resource_machine_control"
local configControlProtocol = "config_control"
local configStatusProtocol = "config_status"

local updateInterval = 2
local configUpdateInterval = 300
local remoteOfflineSeconds = 12

if not peripheral.isPresent(modemSide) then
    error("No modem on " .. modemSide)
end
rednet.open(modemSide)

if not peripheral.isPresent(controllerSide) then
    error("No Storage Controller on " .. controllerSide)
end

local controller = peripheral.wrap(controllerSide)
if not controller then
    error("Could not wrap Storage Controller")
end

if type(controller.list) ~= "function"
    and type(controller.tanks) ~= "function" then
    error("Storage Controller exposes neither list() nor tanks()")
end

local itemConfig = {}
local remoteStorage = {}
local itemDemand = {}

local validSides = {
    top = true,
    bottom = true,
    left = true,
    right = true,
    front = true,
    back = true
}

local function validateConfig(config)
    if type(config) ~= "table" then
        return false, "Config must return a table"
    end

    for itemID, settings in pairs(config) do
        if type(itemID) ~= "string" then
            return false, "Bad item ID"
        end

        if type(settings) ~= "table" then
            return false, "Bad settings for " .. itemID
        end

        settings.target = tonumber(settings.target)
        if not settings.target or settings.target <= 0 then
            return false, "Bad target for " .. itemID
        end

        if settings.machine then
            local machine = settings.machine

            machine.computerID = tonumber(machine.computerID)
            machine.startBelow = tonumber(machine.startBelow) or 50
            machine.stopAt = tonumber(machine.stopAt) or 100

            if not machine.computerID then
                return false, "Bad computerID for " .. itemID
            end

            if type(machine.machineKey) ~= "string"
                or machine.machineKey == "" then
                return false, "Bad machineKey for " .. itemID
            end

            if not validSides[machine.side] then
                return false, "Bad machine side for " .. itemID
            end

            if machine.startBelow < 0 or machine.startBelow > 100 then
                return false, "Bad startBelow for " .. itemID
            end

            if machine.stopAt <= 0 or machine.stopAt > 100 then
                return false, "Bad stopAt for " .. itemID
            end

            if machine.stopAt <= machine.startBelow then
                return false, "stopAt must exceed startBelow for " .. itemID
            end
        end
    end

    return true
end

local function installDownloadedConfig(contents)
    if fs.exists(tempConfigFile) then
        fs.delete(tempConfigFile)
    end

    local file = fs.open(tempConfigFile, "w")
    if not file then
        return false, "COULD NOT WRITE TEMP CONFIG"
    end

    file.write(contents)
    file.close()

    local ok, config = pcall(dofile, tempConfigFile)
    if not ok then
        fs.delete(tempConfigFile)
        return false, "CONFIG ERROR: " .. tostring(config)
    end

    local valid, validationError = validateConfig(config)
    if not valid then
        fs.delete(tempConfigFile)
        return false, validationError
    end

    if fs.exists(configFile) then
        fs.delete(configFile)
    end

    fs.move(tempConfigFile, configFile)
    itemConfig = config

    for itemID in pairs(itemDemand) do
        if not itemConfig[itemID] then
            itemDemand[itemID] = nil
        end
    end

    return true
end

local function downloadTargets()
    local response, httpError = http.get(targetsURL)

    if not response then
        return false, "GITHUB DOWNLOAD FAILED: " .. tostring(httpError)
    end

    local contents = response.readAll()
    response.close()

    if not contents or contents == "" then
        return false, "EMPTY GITHUB RESPONSE"
    end

    return installDownloadedConfig(contents)
end

local function loadLocalConfig()
    if not fs.exists(configFile) then
        return false, "NO CONFIG"
    end

    local ok, config = pcall(dofile, configFile)
    if not ok then
        return false, tostring(config)
    end

    local valid, validationError = validateConfig(config)
    if not valid then
        return false, validationError
    end

    itemConfig = config
    return true
end

local downloaded, downloadError = downloadTargets()
if not downloaded then
    print("GitHub unavailable:")
    print(tostring(downloadError))
    print("Using local targets.lua...")

    local loaded, loadError = loadLocalConfig()
    if not loaded then
        error("Could not load targets.lua: " .. tostring(loadError))
    end
else
    print("targets.lua updated.")
end

local function makeDisplayName(itemID)
    local name = string.match(itemID, ":(.+)$") or itemID
    name = string.gsub(name, "_", " ")
    name = string.gsub(" " .. name, "%W%l", string.upper)
    return string.sub(name, 2)
end

local function getDisplayName(itemID, settings)
    if settings.displayName and settings.displayName ~= "" then
        return settings.displayName
    end
    return makeDisplayName(itemID)
end

local function readController()
    local amounts = {}
    local readSomething = false
    local errors = {}

    if type(controller.list) == "function" then
        local ok, list = pcall(function()
            return controller.list()
        end)

        if ok and type(list) == "table" then
            readSomething = true
            for _, stack in pairs(list) do
                if type(stack) == "table"
                    and type(stack.name) == "string" then
                    amounts[stack.name] =
                        (amounts[stack.name] or 0)
                        + (tonumber(stack.count) or 0)
                end
            end
        else
            errors[#errors + 1] = "ITEM READ FAILED"
        end
    end

    if type(controller.tanks) == "function" then
        local ok, tanks = pcall(function()
            return controller.tanks()
        end)

        if ok and type(tanks) == "table" then
            readSomething = true
            for _, tank in pairs(tanks) do
                if type(tank) == "table"
                    and type(tank.name) == "string" then
                    amounts[tank.name] =
                        (amounts[tank.name] or 0)
                        + (tonumber(tank.amount) or 0)
                end
            end
        else
            errors[#errors + 1] = "FLUID READ FAILED"
        end
    end

    if not readSomething then
        return nil, table.concat(errors, " | ")
    end

    return amounts
end

local function processRemoteInventory(senderID, message)
    if senderID == os.getComputerID() then
        return
    end

    local itemID = message.itemID or message.storageKey
    if type(itemID) ~= "string" then
        return
    end

    remoteStorage[senderID] = remoteStorage[senderID] or {}

    remoteStorage[senderID][itemID] = {
        amount = tonumber(message.amount) or 0,
        lastUpdate = os.epoch("utc")
    }
end

local function processRemoteManifest(senderID, message)
    if senderID == os.getComputerID()
        or type(message.enabledKeys) ~= "table" then
        return
    end

    remoteStorage[senderID] = remoteStorage[senderID] or {}

    local enabled = {}
    for _, itemID in ipairs(message.enabledKeys) do
        enabled[itemID] = true
    end

    for itemID in pairs(remoteStorage[senderID]) do
        if not enabled[itemID] then
            remoteStorage[senderID][itemID] = nil
        end
    end
end

local function buildCombinedAmounts(localAmounts)
    local totals = {}

    for itemID in pairs(itemConfig) do
        totals[itemID] = tonumber(localAmounts[itemID]) or 0
    end

    local now = os.epoch("utc")

    for _, items in pairs(remoteStorage) do
        for itemID, data in pairs(items) do
            local age = now - (data.lastUpdate or 0)

            if age <= remoteOfflineSeconds * 1000 then
                totals[itemID] =
                    (totals[itemID] or 0)
                    + (tonumber(data.amount) or 0)
            end
        end
    end

    return totals
end

local function sendManifest()
    local keys = {}

    for itemID in pairs(itemConfig) do
        keys[#keys + 1] = itemID
    end

    table.sort(keys)

    rednet.broadcast({
        messageType = "storage_manifest",
        enabledKeys = keys,
        role = "BRAIN",
        computerID = os.getComputerID(),
        timestamp = os.epoch("utc")
    }, storageStatusProtocol)
end

local function sendLocalStorage(itemID, amount, settings)
    rednet.broadcast({
        messageType = "inventory_update",
        storageKey = itemID,
        itemID = itemID,
        displayName = getDisplayName(itemID, settings),
        amount = amount,
        targetAmount = settings.target,
        found = true,
        online = true,
        error = nil,
        role = "BRAIN",
        computerID = os.getComputerID(),
        timestamp = os.epoch("utc")
    }, storageStatusProtocol)
end

local function updateItemDemand(itemID, amount, settings)
    local machine = settings.machine
    if not machine then
        itemDemand[itemID] = nil
        return false
    end

    local percentage = (amount / settings.target) * 100
    local wants = itemDemand[itemID] == true

    if wants then
        if percentage >= machine.stopAt then
            wants = false
        end
    else
        if percentage < machine.startBelow then
            wants = true
        end
    end

    itemDemand[itemID] = wants
    return wants, percentage
end

local function sendGroupedMachineCommands(combined)
    local groups = {}

    for itemID, settings in pairs(itemConfig) do
        if settings.machine then
            local machine = settings.machine
            local wants, percentage =
                updateItemDemand(
                    itemID,
                    tonumber(combined[itemID]) or 0,
                    settings
                )

            local key =
                tostring(machine.computerID)
                .. ":"
                .. tostring(machine.side)

            local group = groups[key]
            if not group then
                group = {
                    computerID = machine.computerID,
                    side = machine.side,
                    state = false,
                    itemIDs = {},
                    machineKeys = {},
                    percentages = {}
                }
                groups[key] = group
            end

            if wants then
                group.state = true
            end

            group.itemIDs[#group.itemIDs + 1] = itemID
            group.machineKeys[#group.machineKeys + 1] =
                machine.machineKey
            group.percentages[itemID] = percentage
        end
    end

    for _, group in pairs(groups) do
        rednet.send(group.computerID, {
            command = "auto_set",
            side = group.side,
            state = group.state,
            itemIDs = group.itemIDs,
            machineKeys = group.machineKeys,
            percentages = group.percentages,
            timestamp = os.epoch("utc")
        }, machineControlProtocol)
    end
end

local function automationCycle()
    local localAmounts, readError = readController()

    if not localAmounts then
        return false, readError
    end

    sendManifest()

    for itemID, settings in pairs(itemConfig) do
        sendLocalStorage(
            itemID,
            tonumber(localAmounts[itemID]) or 0,
            settings
        )
    end

    local combined = buildCombinedAmounts(localAmounts)
    sendGroupedMachineCommands(combined)

    return true
end

local function sendRefreshStatus(success, errorMessage)
    rednet.broadcast({
        command = "targets_refresh_status",
        success = success == true,
        error = errorMessage,
        role = "BRAIN",
        computerID = os.getComputerID(),
        timestamp = os.epoch("utc")
    }, configStatusProtocol)
end

local function forceTargetsRefresh()
    local success, refreshError = downloadTargets()

    if not success then
        sendRefreshStatus(false, refreshError)
        return false
    end

    automationCycle()
    sendRefreshStatus(true, nil)

    return true
end

local function drawLocalScreen()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)

    print("FUNCTIONAL STORAGE BRAIN")
    print("========================")
    print("Computer: " .. os.getComputerID())
    print("Controller: " .. string.upper(controllerSide))
    print("Config: GitHub")
    print("")

    local localAmounts, readError = readController()
    if not localAmounts then
        term.setTextColor(colors.red)
        print("CONTROLLER ERROR")
        print(tostring(readError))
        return
    end

    local combined = buildCombinedAmounts(localAmounts)
    local sorted = {}

    for itemID in pairs(itemConfig) do
        sorted[#sorted + 1] = itemID
    end
    table.sort(sorted)

    for index = 1, math.min(#sorted, 8) do
        local itemID = sorted[index]
        local settings = itemConfig[itemID]

        print(getDisplayName(itemID, settings))
        print(
            " "
            .. math.floor(combined[itemID] or 0)
            .. " / "
            .. math.floor(settings.target)
        )

        if itemDemand[itemID] then
            term.setTextColor(colors.lime)
            print(" MACHINE REQUESTED")
            term.setTextColor(colors.white)
        end

        print("")
    end
end

local function automationLoop()
    while true do
        automationCycle()
        sleep(updateInterval)
    end
end

local function displayLoop()
    while true do
        drawLocalScreen()
        sleep(1)
    end
end

local function configLoop()
    while true do
        sleep(configUpdateInterval)

        local success, configError = downloadTargets()

        if success then
            automationCycle()
        else
            print("GitHub update failed:")
            print(tostring(configError))
        end
    end
end

local function networkLoop()
    while true do
        local senderID, message, protocol = rednet.receive()

        if protocol == storageStatusProtocol
            and type(message) == "table" then

            if message.messageType == "inventory_update" then
                processRemoteInventory(senderID, message)
            elseif message.messageType == "storage_manifest" then
                processRemoteManifest(senderID, message)
            end

        elseif protocol == storageControlProtocol
            and type(message) == "table"
            and message.command == "discover" then

            automationCycle()

        elseif protocol == configControlProtocol
            and type(message) == "table"
            and message.command == "force_targets_refresh" then

            forceTargetsRefresh()
        end
    end
end

automationCycle()

parallel.waitForAll(
    automationLoop,
    networkLoop,
    configLoop,
    displayLoop
)
