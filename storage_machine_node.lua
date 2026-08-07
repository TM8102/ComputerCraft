local modemSide = "back"

local targetsURL =
    "https://raw.githubusercontent.com/TM8102/ComputerCraft/main/targets.lua"

local configFile =
    "targets.lua"

local tempConfigFile =
    "targets_new.lua"

-- =========================================================
-- STORAGE SIDES
--
-- Machine sides from targets.lua are automatically excluded.
-- =========================================================

local storageSides = {
    top = true,
    bottom = true,
    left = true,
    right = true,
    front = true,
    back = true
}

-- =========================================================
-- NETWORK
-- =========================================================

local storageControlProtocol =
    "inventory_control"

local storageStatusProtocol =
    "inventory_status"

local machineControlProtocol =
    "resource_machine_control"

local machineStatusProtocol =
    "resource_machine_status"

-- =========================================================
-- TIMING
-- =========================================================

local updateInterval = 2
local configUpdateInterval = 300

-- =========================================================
-- COMPUTER
-- =========================================================

local computerID =
    os.getComputerID()

-- =========================================================
-- MODEM
-- =========================================================

if not peripheral.isPresent(
    modemSide
) then

    error(
        "No modem found on "
        .. modemSide
    )
end

rednet.open(modemSide)

-- =========================================================
-- CONFIG
-- =========================================================

local itemConfig = {}

local function validateConfig(
    config
)
    if type(config)
        ~= "table" then

        return false,
            "Config must return a table"
    end

    for itemID, settings
        in pairs(config) do

        if type(itemID)
            ~= "string" then

            return false,
                "Invalid item ID"
        end

        if type(settings)
            ~= "table" then

            return false,
                "Invalid config for "
                .. itemID
        end

        settings.target =
            tonumber(
                settings.target
            )

        if not settings.target
            or settings.target <= 0 then

            return false,
                "Invalid target for "
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
                    "Missing computerID for "
                    .. itemID
            end

            if type(
                machine.machineKey
            ) ~= "string"
                or machine.machineKey
                    == "" then

                return false,
                    "Missing machineKey for "
                    .. itemID
            end

            local side =
                machine.side

            if side ~= "top"
                and side ~= "bottom"
                and side ~= "left"
                and side ~= "right" then

                return false,
                    "Invalid machine side for "
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
        validateConfig(
            config
        )

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
        config =
        pcall(
            dofile,
            configFile
        )

    if not success then
        return false,
            tostring(config)
    end

    local valid,
        validationError =
        validateConfig(
            config
        )

    if not valid then
        return false,
            validationError
    end

    itemConfig = config

    return true,
        nil
end

-- =========================================================
-- INITIAL DOWNLOAD
-- =========================================================

local downloaded,
    downloadError =
    downloadTargets()

if not downloaded then
    print(
        "GitHub unavailable:"
    )

    print(
        tostring(downloadError)
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
-- DISPLAY NAME
-- =========================================================

local function makeDisplayName(
    itemID
)
    local name =
        string.match(
            itemID,
            ":(.+)$"
        )
        or itemID

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
    itemID
)
    local settings =
        itemConfig[itemID]

    if settings
        and settings.displayName
        and settings.displayName
            ~= "" then

        return settings
            .displayName
    end

    return makeDisplayName(
        itemID
    )
end

-- =========================================================
-- LOCAL MACHINES
-- =========================================================

local localMachines = {}
local machineByKey = {}
local machineSides = {}

local function rebuildLocalMachines()
    local oldMachines =
        machineByKey

    -- Save currently running states.
    local oldStates = {}

    for key, machine
        in pairs(oldMachines) do

        oldStates[key] =
            machine.state == true
    end

    -- Turn off sides which might be removed from config.
    for _, machine
        in pairs(oldMachines) do

        redstone.setOutput(
            machine.side,
            false
        )
    end

    localMachines = {}
    machineByKey = {}
    machineSides = {}

    for itemID, settings
        in pairs(itemConfig) do

        local machine =
            settings.machine

        if machine
            and tonumber(
                machine.computerID
            ) == computerID then

            local machineKey =
                machine.machineKey

            local side =
                machine.side

            if machineSides[side] then
                error(
                    "Multiple machines assigned to "
                    .. side
                )
            end

            local record = {
                itemID = itemID,

                machineKey =
                    machineKey,

                side =
                    side,

                name =
                    settings.displayName
                    or makeDisplayName(
                        itemID
                    ),

                state =
                    oldStates[
                        machineKey
                    ] == true,

                percent = nil,
                amount = nil,

                target =
                    tonumber(
                        settings.target
                    ) or 0,

                lastCommand = 0
            }

            localMachines[
                #localMachines + 1
            ] = record

            machineByKey[
                machineKey
            ] = record

            machineSides[
                side
            ] = true

            redstone.setOutput(
                side,
                record.state
            )
        end
    end
end

rebuildLocalMachines()

-- =========================================================
-- KNOWN STORAGE
-- =========================================================

local knownItems = {}

-- =========================================================
-- ITEM STORAGE
-- =========================================================

local function scanItemInventory(
    peripheralObject,
    amounts
)
    local success,
        items =
        pcall(function()
            return peripheralObject
                .list()
        end)

    if not success then
        return false,
            tostring(items)
    end

    if type(items)
        ~= "table" then

        return false,
            "INVALID ITEM INVENTORY"
    end

    for _, stack
        in pairs(items) do

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

    return true,
        nil
end

-- =========================================================
-- FLUID STORAGE
-- =========================================================

local function scanFluidInventory(
    peripheralObject,
    amounts
)
    local success,
        tanks =
        pcall(function()
            return peripheralObject
                .tanks()
        end)

    if not success then
        return false,
            tostring(tanks)
    end

    if type(tanks)
        ~= "table" then

        return false,
            "INVALID FLUID DATA"
    end

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

    return true,
        nil
end

-- =========================================================
-- SCAN STORAGE
-- =========================================================

local function scanDirectStorage()
    local amounts = {}

    local detectedSources = {}
    local errors = {}

    for side, enabled
        in pairs(
            storageSides
        ) do

        if enabled
            and side ~= modemSide
            and not machineSides[
                side
            ]
            and peripheral.isPresent(
                side
            ) then

            local p =
                peripheral.wrap(side)

            if p then
                if type(p.list)
                    == "function" then

                    local success,
                        readError =
                        scanItemInventory(
                            p,
                            amounts
                        )

                    if success then
                        detectedSources[
                            #detectedSources
                            + 1
                        ] = {
                            side = side,
                            type = "item"
                        }
                    else
                        errors[
                            #errors + 1
                        ] =
                            string.upper(side)
                            .. " ITEM: "
                            .. tostring(
                                readError
                            )
                    end

                elseif type(p.tanks)
                    == "function" then

                    local success,
                        readError =
                        scanFluidInventory(
                            p,
                            amounts
                        )

                    if success then
                        detectedSources[
                            #detectedSources
                            + 1
                        ] = {
                            side = side,
                            type = "fluid"
                        }
                    else
                        errors[
                            #errors + 1
                        ] =
                            string.upper(side)
                            .. " FLUID: "
                            .. tostring(
                                readError
                            )
                    end

                else
                    errors[
                        #errors + 1
                    ] =
                        string.upper(side)
                        .. " NOT STORAGE"
                end
            end
        end
    end

    return amounts,
        detectedSources,
        errors
end

-- =========================================================
-- KNOWN ITEMS
-- =========================================================

local function updateKnownItems(
    amounts
)
    for itemID
        in pairs(amounts) do

        if itemConfig[itemID] then
            knownItems[itemID] =
                true
        end
    end
end

-- =========================================================
-- STORAGE REPORTS
-- =========================================================

local function sendStorageManifest()
    local keys = {}

    for itemID
        in pairs(knownItems) do

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
                computerID,

            timestamp =
                os.epoch("utc")
        },
        storageStatusProtocol
    )
end

local function sendStorageUpdate(
    itemID,
    amount
)
    local settings =
        itemConfig[itemID]

    if not settings then
        return
    end

    local target =
        tonumber(
            settings.target
        ) or 0

    local percentage = 0

    if target > 0 then
        percentage =
            amount
            / target
            * 100
    end

    rednet.broadcast(
        {
            messageType =
                "inventory_update",

            storageKey = itemID,
            itemID = itemID,

            displayName =
                getDisplayName(
                    itemID
                ),

            amount =
                tonumber(amount)
                or 0,

            targetAmount =
                target,

            percent =
                percentage,

            found = true,
            online = true,
            error = nil,

            computerID =
                computerID,

            timestamp =
                os.epoch("utc")
        },
        storageStatusProtocol
    )
end

-- =========================================================
-- MACHINE STATUS
-- =========================================================

local function sendMachineStatus(
    machine
)
    rednet.broadcast(
        {
            messageType =
                "resource_machine_status",

            itemID =
                machine.itemID,

            machineKey =
                machine.machineKey,

            displayName =
                machine.name,

            side =
                machine.side,

            state =
                machine.state == true,

            percent =
                machine.percent,

            amount =
                machine.amount,

            target =
                machine.target,

            computerID =
                computerID,

            timestamp =
                os.epoch("utc")
        },
        machineStatusProtocol
    )
end

local function sendAllMachineStatus()
    for _, machine
        in ipairs(
            localMachines
        ) do

        sendMachineStatus(
            machine
        )
    end
end

-- =========================================================
-- STORAGE REPORT CYCLE
-- =========================================================

local function reportStorage()
    local amounts,
        detectedSources,
        errors =
        scanDirectStorage()

    updateKnownItems(
        amounts
    )

    sendStorageManifest()

    for itemID
        in pairs(
            knownItems
        ) do

        sendStorageUpdate(
            itemID,
            amounts[itemID]
            or 0
        )
    end

    return amounts,
        detectedSources,
        errors
end

-- =========================================================
-- AUTOMATIC MACHINE COMMAND
-- =========================================================

local function processAutoSet(
    message
)
    if type(
        message.machineKey
    ) ~= "string" then

        return
    end

    local machine =
        machineByKey[
            message.machineKey
        ]

    if not machine then
        return
    end

    if message.side
        and message.side
            ~= machine.side then

        return
    end

    if message.itemID
        and message.itemID
            ~= machine.itemID then

        return
    end

    machine.state =
        message.state == true

    machine.percent =
        tonumber(
            message.percent
        )

    machine.amount =
        tonumber(
            message.amount
        )

    machine.target =
        tonumber(
            message.target
        )
        or machine.target

    machine.lastCommand =
        os.epoch("utc")

    redstone.setOutput(
        machine.side,
        machine.state
    )

    sendMachineStatus(
        machine
    )
end

-- =========================================================
-- LOCAL DISPLAY
-- =========================================================

local function drawLocalScreen()
    local amounts,
        detectedSources,
        errors =
        scanDirectStorage()

    term.setBackgroundColor(
        colors.black
    )

    term.setTextColor(
        colors.white
    )

    term.clear()
    term.setCursorPos(1, 1)

    print(
        "STORAGE + MACHINE NODE"
    )

    print(
        "======================"
    )

    print(
        "Computer: "
        .. computerID
    )

    print("Config: GitHub")
    print("")

    print("STORAGE:")

    if #detectedSources == 0 then
        term.setTextColor(
            colors.red
        )

        print(" NONE FOUND")

        term.setTextColor(
            colors.white
        )
    else
        for _, source
            in ipairs(
                detectedSources
            ) do

            if source.type
                == "fluid" then

                term.setTextColor(
                    colors.lightBlue
                )
            else
                term.setTextColor(
                    colors.lime
                )
            end

            print(
                " "
                .. string.upper(
                    source.side
                )
                .. " "
                .. string.upper(
                    source.type
                )
            )

            term.setTextColor(
                colors.white
            )
        end
    end

    if #errors > 0 then
        print("")

        term.setTextColor(
            colors.orange
        )

        print("WARNINGS:")

        for _, err
            in ipairs(errors) do

            print(
                " "
                .. tostring(err)
            )
        end

        term.setTextColor(
            colors.white
        )
    end

    print("")
    print("RESOURCES:")

    local resourceCount = 0

    local sortedKnown = {}

    for itemID
        in pairs(knownItems) do

        sortedKnown[
            #sortedKnown + 1
        ] = itemID
    end

    table.sort(sortedKnown)

    for _, itemID
        in ipairs(
            sortedKnown
        ) do

        resourceCount =
            resourceCount + 1

        print(
            " "
            .. getDisplayName(
                itemID
            )
        )

        print(
            "  "
            .. tostring(
                math.floor(
                    amounts[itemID]
                    or 0
                )
            )
        )
    end

    if resourceCount == 0 then
        print(" NONE")
    end

    print("")
    print("MACHINES:")

    if #localMachines == 0 then
        print(" NONE")
    end

    for _, machine
        in ipairs(
            localMachines
        ) do

        print(
            " "
            .. string.upper(
                machine.side
            )
            .. " "
            .. machine.name
        )

        if machine.state then
            term.setTextColor(
                colors.lime
            )

            print("  RUNNING")
        else
            term.setTextColor(
                colors.red
            )

            print("  STOPPED")
        end

        term.setTextColor(
            colors.white
        )
    end
end

-- =========================================================
-- CONFIG UPDATE
-- =========================================================

local function updateConfig()
    local success,
        updateError =
        downloadTargets()

    if not success then
        return false,
            updateError
    end

    local loaded,
        loadError =
        loadConfig()

    if not loaded then
        return false,
            loadError
    end

    rebuildLocalMachines()

    return true,
        nil
end

-- =========================================================
-- LOOPS
-- =========================================================

local function reportingLoop()
    while true do
        reportStorage()

        sendAllMachineStatus()

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

            reportStorage()
            sendAllMachineStatus()
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
                == machineControlProtocol
            and type(message)
                == "table" then

            if message.command
                == "auto_set" then

                processAutoSet(
                    message
                )

            elseif message.command
                == "discover" then

                sendAllMachineStatus()
            end

        elseif protocol
                == storageControlProtocol
            and type(message)
                == "table"
            and message.command
                == "discover" then

            reportStorage()
        end
    end
end

-- =========================================================
-- START
-- =========================================================

reportStorage()
sendAllMachineStatus()

parallel.waitForAll(
    reportingLoop,
    networkLoop,
    configLoop,
    displayLoop
)