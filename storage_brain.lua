local controllerSide = "top"
local modemSide = "back"

local targetsURL =
    "https://raw.githubusercontent.com/TM8102/ComputerCraft/main/targets.lua"

local configFile =
    "targets.lua"

local tempConfigFile =
    "targets_new.lua"

-- =========================================================
-- NETWORK
-- =========================================================

local storageControlProtocol =
    "inventory_control"

local storageStatusProtocol =
    "inventory_status"

local machineControlProtocol =
    "resource_machine_control"

-- =========================================================
-- TIMING
-- =========================================================

local updateInterval = 2
local configUpdateInterval = 300

local remoteOfflineSeconds = 12

-- =========================================================
-- MODEM
-- =========================================================

if not peripheral.isPresent(
    modemSide
) then

    error(
        "No modem on "
        .. modemSide
    )
end

rednet.open(modemSide)

-- =========================================================
-- FUNCTIONAL STORAGE CONTROLLER
-- =========================================================

if not peripheral.isPresent(
    controllerSide
) then

    error(
        "No Storage Controller on "
        .. controllerSide
    )
end

local controller =
    peripheral.wrap(
        controllerSide
    )

if not controller then
    error(
        "Could not wrap Storage Controller"
    )
end

if type(controller.list)
        ~= "function"
    and type(controller.tanks)
        ~= "function" then

    error(
        "Storage Controller exposes neither list() nor tanks()"
    )
end

-- =========================================================
-- CONFIG VALIDATION
-- =========================================================

local itemConfig = {}

local validSides = {
    top = true,
    bottom = false,
    left = false,
    right = false
}

local function validateConfig(
    config
)
    if type(config) ~= "table" then
        return false,
            "Config must return a table"
    end

    for itemID, settings
        in pairs(config) do

        if type(itemID)
            ~= "string" then

            return false,
                "Bad item ID"
        end

        if type(settings)
            ~= "table" then

            return false,
                "Bad settings for "
                .. itemID
        end

        settings.target =
            tonumber(
                settings.target
            )

        if not settings.target
            or settings.target <= 0 then

            return false,
                "Bad target for "
                .. itemID
        end

        if settings.machine then
            local machine =
                settings.machine

            machine.computerID =
                tonumber(
                    machine.computerID
                )

            machine.startBelow =
                tonumber(
                    machine.startBelow
                ) or 50

            machine.stopAt =
                tonumber(
                    machine.stopAt
                ) or 100

            if not machine.computerID then
                return false,
                    "Bad computerID for "
                    .. itemID
            end

            if type(
                machine.machineKey
            ) ~= "string"
                or machine.machineKey
                    == "" then

                return false,
                    "Bad machineKey for "
                    .. itemID
            end

            if not validSides[
                machine.side
            ] then

                return false,
                    "Bad machine side for "
                    .. itemID
            end

            if machine.startBelow < 0
                or machine.startBelow
                    > 100 then

                return false,
                    "Bad startBelow for "
                    .. itemID
            end

            if machine.stopAt <= 0
                or machine.stopAt
                    > 100 then

                return false,
                    "Bad stopAt for "
                    .. itemID
            end

            if machine.stopAt
                <= machine.startBelow then

                return false,
                    "stopAt must exceed startBelow for "
                    .. itemID
            end
        end
    end

    return true,
        nil
end

-- =========================================================
-- GITHUB DOWNLOAD
-- =========================================================

local function downloadTargets()
    if fs.exists(
        tempConfigFile
    ) then

        fs.delete(
            tempConfigFile
        )
    end

    print(
        "Checking GitHub targets..."
    )

    local response,
        httpError =
        http.get(
            targetsURL
        )

    if not response then
        return false,
            "GITHUB DOWNLOAD FAILED: "
            .. tostring(httpError)
    end

    local contents =
        response.readAll()

    response.close()

    if not contents
        or contents == "" then

        return false,
            "EMPTY GITHUB RESPONSE"
    end

    local file =
        fs.open(
            tempConfigFile,
            "w"
        )

    if not file then
        return false,
            "COULD NOT WRITE TEMP CONFIG"
    end

    file.write(contents)
    file.close()

    local success,
        config =
        pcall(
            dofile,
            tempConfigFile
        )

    if not success then
        fs.delete(
            tempConfigFile
        )

        return false,
            "CONFIG ERROR: "
            .. tostring(config)
    end

    local valid,
        validationError =
        validateConfig(config)

    if not valid then
        fs.delete(
            tempConfigFile
        )

        return false,
            validationError
    end

    if fs.exists(configFile) then
        fs.delete(configFile)
    end

    fs.move(
        tempConfigFile,
        configFile
    )

    print(
        "targets.lua updated from GitHub."
    )

    return true,
        nil
end

local function loadConfig()
    if not fs.exists(
        configFile
    ) then

        return false,
            "NO CONFIG"
    end

    local success,
        data =
        pcall(
            dofile,
            configFile
        )

    if not success then
        return false,
            tostring(data)
    end

    local valid,
        validationError =
        validateConfig(data)

    if not valid then
        return false,
            validationError
    end

    itemConfig = data

    return true,
        nil
end

-- =========================================================
-- INITIAL CONFIG
-- =========================================================

local downloaded,
    downloadError =
    downloadTargets()

if not downloaded then
    print(
        "GitHub unavailable:"
    )

    print(
        tostring(
            downloadError
        )
    )

    print(
        "Using local targets.lua..."
    )
end

local loaded,
    loadError =
    loadConfig()

if not loaded then
    error(
        "Could not load targets.lua: "
        .. tostring(loadError)
    )
end

-- =========================================================
-- NAMES
-- =========================================================

local function makeDisplayName(
    itemID
)
    local name =
        string.match(
            itemID,
            ":(.+)$"
        ) or itemID

    name =
        string.gsub(
            name,
            "_",
            " "
        )

    name =
        string.gsub(
            " " .. name,
            "%W%l",
            string.upper
        )

    return string.sub(
        name,
        2
    )
end

local function getDisplayName(
    itemID,
    settings
)
    if settings.displayName
        and settings.displayName
            ~= "" then

        return settings.displayName
    end

    return makeDisplayName(itemID)
end

-- =========================================================
-- READ FUNCTIONAL STORAGE
--
-- Supports ITEMS + FLUIDS.
-- =========================================================

local function readController()
    local amounts = {}

    local successfullyRead =
        false

    local errors = {}

    -- ITEMS
    if type(controller.list)
        == "function" then

        local success,
            list =
            pcall(function()
                return controller.list()
            end)

        if success
            and type(list)
                == "table" then

            successfullyRead = true

            for _, stack
                in pairs(list) do

                if type(stack)
                        == "table"
                    and type(stack.name)
                        == "string" then

                    amounts[
                        stack.name
                    ] =
                        (
                            amounts[
                                stack.name
                            ]
                            or 0
                        )
                        + (
                            tonumber(
                                stack.count
                            ) or 0
                        )
                end
            end
        else
            errors[
                #errors + 1
            ] =
                "ITEM READ FAILED"
        end
    end

    -- FLUIDS
    if type(controller.tanks)
        == "function" then

        local success,
            tanks =
            pcall(function()
                return controller.tanks()
            end)

        if success
            and type(tanks)
                == "table" then

            successfullyRead = true

            for _, tank
                in pairs(tanks) do

                if type(tank)
                        == "table"
                    and type(tank.name)
                        == "string" then

                    amounts[
                        tank.name
                    ] =
                        (
                            amounts[
                                tank.name
                            ]
                            or 0
                        )
                        + (
                            tonumber(
                                tank.amount
                            ) or 0
                        )
                end
            end
        else
            errors[
                #errors + 1
            ] =
                "FLUID READ FAILED"
        end
    end

    if not successfullyRead then
        return nil,
            table.concat(
                errors,
                " | "
            )
    end

    return amounts,
        nil
end

-- =========================================================
-- REMOTE STORAGE
-- =========================================================

local remoteStorage = {}

local function processRemoteInventory(
    senderID,
    message
)
    if senderID
        == os.getComputerID() then

        return
    end

    local itemID =
        message.itemID
        or message.storageKey

    if type(itemID)
        ~= "string" then

        return
    end

    if not remoteStorage[
        senderID
    ] then

        remoteStorage[
            senderID
        ] = {}
    end

    remoteStorage[
        senderID
    ][itemID] = {
        amount =
            tonumber(
                message.amount
            ) or 0,

        lastUpdate =
            os.epoch("utc")
    }
end

local function processRemoteManifest(
    senderID,
    message
)
    if senderID
            == os.getComputerID()
        or type(
            message.enabledKeys
        ) ~= "table" then

        return
    end

    if not remoteStorage[
        senderID
    ] then

        remoteStorage[
            senderID
        ] = {}
    end

    local enabled = {}

    for _, itemID
        in ipairs(
            message.enabledKeys
        ) do

        enabled[itemID] = true
    end

    for itemID
        in pairs(
            remoteStorage[
                senderID
            ]
        ) do

        if not enabled[itemID] then
            remoteStorage[
                senderID
            ][itemID] = nil
        end
    end
end

-- =========================================================
-- COMBINED TOTAL
-- =========================================================

local function buildCombinedAmounts(
    localAmounts
)
    local totals = {}

    for itemID
        in pairs(
            itemConfig
        ) do

        totals[itemID] =
            tonumber(
                localAmounts[itemID]
            ) or 0
    end

    local now =
        os.epoch("utc")

    for _, items
        in pairs(
            remoteStorage
        ) do

        for itemID, data
            in pairs(items) do

            local age =
                now
                - (
                    data.lastUpdate
                    or 0
                )

            if age
                <= remoteOfflineSeconds
                    * 1000 then

                totals[itemID] =
                    (
                        totals[itemID]
                        or 0
                    )
                    + (
                        tonumber(
                            data.amount
                        ) or 0
                    )
            end
        end
    end

    return totals
end

-- =========================================================
-- AUTOMATION
-- =========================================================

local machineStates = {}

local function machineStateKey(
    machine
)
    return tostring(
        machine.computerID
    )
        .. ":"
        .. tostring(
            machine.machineKey
        )
        .. ":"
        .. tostring(
            machine.side
        )
end

local function calculateMachineState(
    amount,
    target,
    machine
)
    local percentage =
        amount / target * 100

    local key =
        machineStateKey(machine)

    local running =
        machineStates[key]
        == true

    if running then
        if percentage
            >= machine.stopAt then

            running = false
        end
    else
        if percentage
            < machine.startBelow then

            running = true
        end
    end

    machineStates[key] =
        running

    return running,
        percentage
end

local function sendMachineCommand(
    itemID,
    amount,
    settings
)
    if not settings.machine then
        return false
    end

    local machine =
        settings.machine

    local running,
        percentage =
        calculateMachineState(
            amount,
            settings.target,
            machine
        )

    rednet.send(
        machine.computerID,
        {
            command = "auto_set",

            itemID = itemID,

            machineKey =
                machine.machineKey,

            side =
                machine.side,

            state =
                running,

            percent =
                percentage,

            amount =
                amount,

            target =
                settings.target,

            timestamp =
                os.epoch("utc")
        },
        machineControlProtocol
    )

    return running
end

-- =========================================================
-- REPORT LOCAL STORAGE
-- =========================================================

local function sendManifest()
    local keys = {}

    for itemID
        in pairs(itemConfig) do

        keys[
            #keys + 1
        ] = itemID
    end

    table.sort(keys)

    rednet.broadcast(
        {
            messageType =
                "storage_manifest",

            enabledKeys = keys,

            computerID =
                os.getComputerID(),

            timestamp =
                os.epoch("utc")
        },
        storageStatusProtocol
    )
end

local function sendLocalStorage(
    itemID,
    amount,
    settings
)
    rednet.broadcast(
        {
            messageType =
                "inventory_update",

            storageKey = itemID,
            itemID = itemID,

            displayName =
                getDisplayName(
                    itemID,
                    settings
                ),

            amount =
                amount,

            targetAmount =
                settings.target,

            found = true,
            online = true,
            error = nil,

            computerID =
                os.getComputerID(),

            timestamp =
                os.epoch("utc")
        },
        storageStatusProtocol
    )
end

-- =========================================================
-- AUTOMATION CYCLE
-- =========================================================

local function automationCycle()
    local localAmounts,
        readError =
        readController()

    if not localAmounts then
        return false,
            readError
    end

    sendManifest()

    -- Send ONLY this controller's actual contents to Main.
    for itemID, settings
        in pairs(itemConfig) do

        sendLocalStorage(
            itemID,
            tonumber(
                localAmounts[
                    itemID
                ]
            ) or 0,
            settings
        )
    end

    -- Automation uses TOTAL storage everywhere.
    local combined =
        buildCombinedAmounts(
            localAmounts
        )

    for itemID, settings
        in pairs(itemConfig) do

        if settings.machine then
            sendMachineCommand(
                itemID,
                tonumber(
                    combined[itemID]
                ) or 0,
                settings
            )
        end
    end

    return true,
        nil
end

-- =========================================================
-- LOCAL DISPLAY
-- =========================================================

local function drawLocalScreen()
    term.setBackgroundColor(
        colors.black
    )

    term.setTextColor(
        colors.white
    )

    term.clear()
    term.setCursorPos(1, 1)

    print(
        "FUNCTIONAL STORAGE BRAIN"
    )

    print(
        "========================"
    )

    print(
        "Computer: "
        .. os.getComputerID()
    )

    print("Config: GitHub")
    print("")

    local localAmounts,
        readError =
        readController()

    if not localAmounts then
        term.setTextColor(
            colors.red
        )

        print("CONTROLLER ERROR")
        print(tostring(readError))

        return
    end

    local combined =
        buildCombinedAmounts(
            localAmounts
        )

    local sorted = {}

    for itemID
        in pairs(itemConfig) do

        sorted[
            #sorted + 1
        ] = itemID
    end

    table.sort(sorted)

    for index = 1,
        math.min(
            #sorted,
            8
        ) do

        local itemID =
            sorted[index]

        local settings =
            itemConfig[itemID]

        local amount =
            combined[itemID]
            or 0

        print(
            getDisplayName(
                itemID,
                settings
            )
        )

        print(
            " "
            .. math.floor(amount)
            .. " / "
            .. math.floor(
                settings.target
            )
        )

        if settings.machine then
            local key =
                machineStateKey(
                    settings.machine
                )

            if machineStates[key] then
                term.setTextColor(
                    colors.lime
                )

                print(
                    " MACHINE RUNNING"
                )

                term.setTextColor(
                    colors.white
                )
            end
        end

        print("")
    end
end

-- =========================================================
-- CONFIG UPDATE
-- =========================================================

local function updateConfig()
    local success,
        downloadError =
        downloadTargets()

    if not success then
        return false,
            downloadError
    end

    return loadConfig()
end

-- =========================================================
-- LOOPS
-- =========================================================

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
        sleep(
            configUpdateInterval
        )

        local success,
            configError =
            updateConfig()

        if success then
            print(
                "GitHub targets refreshed."
            )

            automationCycle()
        else
            print(
                "GitHub update failed:"
            )

            print(
                tostring(configError)
            )
        end
    end
end

local function networkLoop()
    while true do
        local senderID,
            message,
            protocol =
            rednet.receive()

        if protocol
                == storageStatusProtocol
            and type(message)
                == "table" then

            if message.messageType
                == "inventory_update" then

                processRemoteInventory(
                    senderID,
                    message
                )

            elseif message.messageType
                == "storage_manifest" then

                processRemoteManifest(
                    senderID,
                    message
                )
            end

        elseif protocol
                == storageControlProtocol
            and type(message)
                == "table"
            and message.command
                == "discover" then

            automationCycle()
        end
    end
end

-- =========================================================
-- START
-- =========================================================

automationCycle()

parallel.waitForAll(
    automationLoop,
    networkLoop,
    configLoop,
    displayLoop
)