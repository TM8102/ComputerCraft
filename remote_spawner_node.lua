-- =========================================================
-- REMOTE SPAWNER NODE
--
-- Centralized configuration lives in GitHub: spawners.lua
-- This node reads its ComputerCraft ID and automatically
-- loads only the spawners assigned to that computer.
-- =========================================================

local controlProtocol = "spawner_control"
local statusProtocol = "spawner_status"

local githubConfigURL =
    "https://api.github.com/repos/TM8102/ComputerCraft/contents/spawners.lua?ref=main"

local configFile = "spawners.lua"
local tempConfigFile = "spawners_new.lua"

local computerID = os.getComputerID()

local modemSide = nil
local spawners = {}
local updateInterval = 4
local configUpdateInterval = 300
local configSource = "NONE"

local validSides = {
    top = true,
    bottom = true,
    left = true,
    right = true,
    front = true,
    back = true
}

-- =========================================================
-- MODEM DISCOVERY
-- =========================================================

for _, side in ipairs({
    "top", "bottom", "left", "right", "front", "back"
}) do
    if peripheral.isPresent(side)
        and peripheral.getType(side) == "modem" then
        modemSide = side
        break
    end
end

if not modemSide then
    error("No modem found on any side")
end

rednet.open(modemSide)

-- =========================================================
-- HELPERS
-- =========================================================

local function copyTable(source)
    local output = {}

    for key, value in pairs(source or {}) do
        if type(value) == "table" then
            output[key] = copyTable(value)
        else
            output[key] = value
        end
    end

    return output
end

local function validateSpawnerList(list)
    if type(list) ~= "table" then
        return false, "Spawner list must be a table"
    end

    local usedKeys = {}
    local usedSides = {}

    for index, spawner in ipairs(list) do
        if type(spawner) ~= "table" then
            return false, "Bad spawner entry " .. tostring(index)
        end

        spawner.enabled = spawner.enabled ~= false

        if spawner.enabled then
            if type(spawner.key) ~= "string"
                or spawner.key == "" then
                return false, "Spawner " .. index .. " needs a key"
            end

            if usedKeys[spawner.key] then
                return false, "Duplicate key: " .. spawner.key
            end
            usedKeys[spawner.key] = true

            if type(spawner.name) ~= "string"
                or spawner.name == "" then
                return false, "Spawner " .. spawner.key .. " needs a name"
            end

            if not validSides[spawner.outputSide] then
                return false, "Bad output side for " .. spawner.key
            end

            if spawner.outputSide == modemSide then
                return false,
                    spawner.key .. " cannot use modem side " .. modemSide
            end

            if usedSides[spawner.outputSide] then
                return false,
                    "Two enabled spawners use " .. spawner.outputSide
            end

            usedSides[spawner.outputSide] = true
        end
    end

    return true
end

local function selectComputerConfig(config)
    if type(config) ~= "table" then
        return nil, "Config must return a table"
    end

    local computers = config.computers
    local profile = nil
    local profileName = nil

    if type(computers) == "table" then
        profile = computers[computerID]
        if profile then
            profileName = "COMPUTER " .. computerID
        end
    end

    if not profile then
        profile = config.default
        profileName = "DEFAULT"
    end

    if type(profile) ~= "table" then
        return nil,
            "No profile for computer " .. computerID .. " and no default"
    end

    local configured = copyTable(profile.spawners or {})
    local valid, validationError = validateSpawnerList(configured)

    if not valid then
        return nil, validationError
    end

    return {
        spawners = configured,
        updateInterval = tonumber(config.statusUpdateInterval) or 4,
        configUpdateInterval = tonumber(config.configUpdateInterval) or 300,
        profileName = profileName
    }
end

local function turnOldOutputsOff(oldSpawners)
    for _, spawner in ipairs(oldSpawners or {}) do
        if spawner.enabled
            and validSides[spawner.outputSide]
            and spawner.outputSide ~= modemSide then
            redstone.setOutput(spawner.outputSide, false)
        end
    end
end

local function applyConfig(config, source)
    local selected, selectionError = selectComputerConfig(config)

    if not selected then
        return false, selectionError
    end

    local oldStates = {}

    for _, spawner in ipairs(spawners) do
        if spawner.enabled and spawner.key then
            oldStates[spawner.key] = spawner.state == true
        end
    end

    turnOldOutputsOff(spawners)

    spawners = selected.spawners
    updateInterval = selected.updateInterval
    configUpdateInterval = selected.configUpdateInterval
    configSource = source .. " / " .. selected.profileName

    for _, spawner in ipairs(spawners) do
        spawner.state = oldStates[spawner.key] == true

        if spawner.enabled then
            redstone.setOutput(
                spawner.outputSide,
                spawner.state
            )
        end
    end

    return true
end

local function installConfig(contents, source)
    if fs.exists(tempConfigFile) then
        fs.delete(tempConfigFile)
    end

    local file = fs.open(tempConfigFile, "w")
    if not file then
        return false, "Could not write temporary config"
    end

    file.write(contents)
    file.close()

    local ok, config = pcall(dofile, tempConfigFile)

    if not ok then
        fs.delete(tempConfigFile)
        return false, "CONFIG ERROR: " .. tostring(config)
    end

    local applied, applyError = applyConfig(config, source)

    if not applied then
        fs.delete(tempConfigFile)
        return false, applyError
    end

    if fs.exists(configFile) then
        fs.delete(configFile)
    end

    fs.move(tempConfigFile, configFile)
    return true
end

local function downloadConfig()
    local url =
        githubConfigURL
        .. "&cb="
        .. tostring(os.epoch("utc"))

    local response, httpError = http.get(
        url,
        {
            ["User-Agent"] = "CC-Tweaked",
            ["Accept"] = "application/vnd.github.raw+json",
            ["Cache-Control"] = "no-cache, no-store",
            ["Pragma"] = "no-cache"
        }
    )

    if not response then
        return false, "GitHub API failed: " .. tostring(httpError)
    end

    local code = response.getResponseCode
        and response.getResponseCode()
        or 200

    local contents = response.readAll()
    response.close()

    if code < 200 or code >= 300 then
        return false, "GitHub HTTP " .. tostring(code)
    end

    if not contents or contents == "" then
        return false, "GitHub returned empty spawners.lua"
    end

    return installConfig(contents, "GITHUB")
end

local function loadLocalConfig()
    if not fs.exists(configFile) then
        return false, "No local spawners.lua"
    end

    local ok, config = pcall(dofile, configFile)

    if not ok then
        return false, tostring(config)
    end

    return applyConfig(config, "LOCAL CACHE")
end

-- =========================================================
-- SPAWNER CONTROL
-- =========================================================

local function findSpawner(spawnerKey)
    for _, spawner in ipairs(spawners) do
        if spawner.enabled
            and spawner.key == spawnerKey then
            return spawner
        end
    end

    return nil
end

local function setSpawnerState(spawner, state)
    if not spawner or not spawner.enabled then
        return false
    end

    spawner.state = state == true

    redstone.setOutput(
        spawner.outputSide,
        spawner.state
    )

    return true
end

local function turnEverythingOff()
    for _, spawner in ipairs(spawners) do
        if spawner.enabled then
            setSpawnerState(spawner, false)
        end
    end
end

local function turnEverythingOn()
    for _, spawner in ipairs(spawners) do
        if spawner.enabled then
            setSpawnerState(spawner, true)
        end
    end
end

-- =========================================================
-- NETWORK STATUS
-- =========================================================

local function sendManifest()
    local enabledKeys = {}

    for _, spawner in ipairs(spawners) do
        if spawner.enabled then
            enabledKeys[#enabledKeys + 1] = spawner.key
        end
    end

    rednet.broadcast(
        {
            messageType = "spawner_manifest",
            enabledKeys = enabledKeys,
            computerID = computerID,
            configSource = configSource,
            timestamp = os.epoch("utc")
        },
        statusProtocol
    )
end

local function sendSpawnerStatus(spawner)
    if not spawner.enabled then
        return
    end

    rednet.broadcast(
        {
            messageType = "spawner_status",
            spawnerKey = spawner.key,
            displayName = spawner.name,
            state = spawner.state == true,
            outputSide = spawner.outputSide,
            computerID = computerID,
            configSource = configSource,
            timestamp = os.epoch("utc")
        },
        statusProtocol
    )
end

local function sendAllStatuses()
    sendManifest()

    for _, spawner in ipairs(spawners) do
        if spawner.enabled then
            sendSpawnerStatus(spawner)
        end
    end
end

-- =========================================================
-- LOCAL DISPLAY
-- =========================================================

local function drawComputerScreen()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)

    print("REMOTE SPAWNER NODE")
    print("===================")
    print("Computer ID: " .. computerID)
    print("Modem: " .. string.upper(modemSide))
    print("Config: " .. configSource)
    print("")

    if #spawners == 0 then
        term.setTextColor(colors.orange)
        print("NO SPAWNERS CONFIGURED")
        term.setTextColor(colors.white)
    end

    for index, spawner in ipairs(spawners) do
        if spawner.enabled then
            print(index .. ". " .. spawner.name)
            print("   Key: " .. spawner.key)
            print("   Side: " .. string.upper(spawner.outputSide))

            term.setTextColor(
                spawner.state and colors.lime or colors.red
            )
            print("   " .. (spawner.state and "ON" or "OFF"))
            term.setTextColor(colors.white)
        else
            print(index .. ". DISABLED")
        end
    end
end

-- =========================================================
-- STARTUP CONFIG
-- =========================================================

local downloaded, downloadError = downloadConfig()

if not downloaded then
    print("GitHub config failed:")
    print(tostring(downloadError))
    print("Using local spawners.lua...")

    local loaded, loadError = loadLocalConfig()

    if not loaded then
        error("Could not load spawner config: " .. tostring(loadError))
    end
end

-- Safe startup: spawners always begin OFF after a reboot.
turnEverythingOff()
sendAllStatuses()
drawComputerScreen()

-- =========================================================
-- LOOPS
-- =========================================================

local function receiveControls()
    while true do
        local _, message = rednet.receive(controlProtocol)

        if type(message) == "table" then
            if message.command == "discover" then
                sendAllStatuses()

            elseif message.command == "all_off" then
                turnEverythingOff()
                sendAllStatuses()
                drawComputerScreen()

            elseif message.command == "all_on" then
                turnEverythingOn()
                sendAllStatuses()
                drawComputerScreen()

            elseif message.command == "refresh_config" then
                local success = downloadConfig()
                if success then
                    sendAllStatuses()
                    drawComputerScreen()
                end

            elseif message.command == "spawn"
                and type(message.spawnerKey) == "string"
                and type(message.state) == "boolean" then

                local spawner = findSpawner(message.spawnerKey)

                if spawner then
                    setSpawnerState(spawner, message.state)
                    sendSpawnerStatus(spawner)
                    drawComputerScreen()
                end
            end
        end
    end
end

local function statusReporter()
    while true do
        sendAllStatuses()
        drawComputerScreen()
        sleep(updateInterval)
    end
end

local function configUpdater()
    while true do
        sleep(configUpdateInterval)

        local success, configError = downloadConfig()

        if success then
            sendAllStatuses()
            drawComputerScreen()
        else
            print("Spawner config update failed:")
            print(tostring(configError))
        end
    end
end

parallel.waitForAll(
    receiveControls,
    statusReporter,
    configUpdater
)
