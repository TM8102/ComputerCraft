-- =========================================================
-- RESOURCE MACHINE NODE
--
-- PURPOSE:
--   Controls machines attached directly to this computer.
--
--   NO storage scanning.
--   NO manual ON/OFF.
--   EVERYTHING is automatic.
--
--   Storage Brain decides which resources need production.
--   This computer controls the physical redstone outputs.
--
-- SHARED MACHINES ARE SUPPORTED:
--
--   Resource A -> computer 200 -> TOP
--   Resource B -> computer 200 -> TOP
--
--   TOP stays ON if EITHER resource requests production.
-- =========================================================

local modemSide = "top"

-- =========================================================
-- GITHUB
-- =========================================================

local targetsURL =
    "https://raw.githubusercontent.com/TM8102/ComputerCraft/main/targets.lua"

local configFile =
    "targets.lua"

local tempConfigFile =
    "targets_new.lua"

-- =========================================================
-- NETWORK
-- =========================================================

local machineControlProtocol =
    "resource_machine_control"

local machineStatusProtocol =
    "resource_machine_status"

local configControlProtocol =
    "config_control"

local configStatusProtocol =
    "config_status"

-- =========================================================
-- TIMING
-- =========================================================

local statusInterval = 2

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

rednet.open(
    modemSide
)

-- =========================================================
-- CONFIG
-- =========================================================

local itemConfig = {}

local validSides = {
    top = true,
    bottom = true,
    left = true,
    right = true,
    front = true,
    back = true
}

local function validateConfig(
    config
)
    if type(config)
        ~= "table" then

        return false,
            "Config must return a table"
    end

    for itemID,
        settings
        in pairs(config) do

        if type(itemID)
            ~= "string" then

            return false,
                "Invalid item ID"
        end

        if type(settings)
            ~= "table" then

            return false,
                "Invalid settings for "
                .. tostring(itemID)
        end

        settings.target =
            tonumber(
                settings.target
            )

        if not settings.target
            or settings.target <= 0 then

            return false,
                "Invalid target for "
                .. tostring(itemID)
        end

        if settings.machine then

            local machine =
                settings.machine

            if type(machine)
                ~= "table" then

                return false,
                    "Invalid machine config for "
                    .. itemID
            end

            machine.computerID =
                tonumber(
                    machine.computerID
                )

            if not machine.computerID then

                return false,
                    "Invalid computerID for "
                    .. itemID
            end

            if type(
                machine.machineKey
            ) ~= "string"
                or machine.machineKey
                    == "" then

                return false,
                    "Invalid machineKey for "
                    .. itemID
            end

            if not validSides[
                machine.side
            ] then

                return false,
                    "Invalid machine side for "
                    .. itemID
            end

            machine.startBelow =
                tonumber(
                    machine.startBelow
                )
                or 50

            machine.stopAt =
                tonumber(
                    machine.stopAt
                )
                or 100
        end
    end

    return true,
        nil
end

-- =========================================================
-- LOAD LOCAL TARGETS
-- =========================================================

local function loadConfig()

    if not fs.exists(
        configFile
    ) then

        return false,
            "targets.lua not found"
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

    itemConfig =
        config

    return true,
        nil
end

-- =========================================================
-- GITHUB TARGET DOWNLOAD
--
-- Downloads to temp file FIRST.
-- Working config is not destroyed unless the new file
-- passes validation.
-- =========================================================

local function downloadTargets()

    if fs.exists(
        tempConfigFile
    ) then

        fs.delete(
            tempConfigFile
        )
    end

    local response,
        httpError =
        http.get(
            targetsURL
        )

    if not response then

        return false,
            "DOWNLOAD FAILED: "
            .. tostring(
                httpError
            )
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
            "COULD NOT WRITE TEMP FILE"
    end

    file.write(
        contents
    )

    file.close()

    -- Test downloaded Lua.
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
            "LUA ERROR: "
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

    -- New config is good.
    if fs.exists(
        configFile
    ) then

        fs.delete(
            configFile
        )
    end

    fs.move(
        tempConfigFile,
        configFile
    )

    itemConfig =
        config

    return true,
        nil
end

-- =========================================================
-- INITIAL CONFIG
-- =========================================================

local loaded,
    loadError =
    loadConfig()

if not loaded then

    print(
        "Local targets.lua unavailable."
    )

    print(
        "Downloading from GitHub..."
    )

    local downloaded,
        downloadError =
        downloadTargets()

    if not downloaded then

        error(
            "Could not load targets: "
            .. tostring(
                downloadError
            )
        )
    end
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
        itemConfig[
            itemID
        ]

    if settings
        and type(
            settings.displayName
        ) == "string"
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
-- MACHINE DATA
--
-- resources:
--
-- resourceMachines["minecraft:iron_ingot"] = {
--     side = "top",
--     machineKey = "iron"
-- }
--
-- physicalMachines:
--
-- physicalMachines["top"] = {
--     resources = {...},
--     running = false
-- }
--
-- requestedStates:
--
-- requestedStates["minecraft:iron_ingot"] = true
--
-- =========================================================

local resourceMachines = {}

local physicalMachines = {}

local requestedStates = {}

-- =========================================================
-- REBUILD MACHINES FROM TARGETS
-- =========================================================

local function rebuildMachines()

    -- Save existing requests where possible.
    local oldRequests =
        requestedStates

    -- Turn off all previously controlled outputs.
    for side
        in pairs(
            physicalMachines
        ) do

        redstone.setOutput(
            side,
            false
        )
    end

    resourceMachines = {}
    physicalMachines = {}
    requestedStates = {}

    for itemID,
        settings
        in pairs(
            itemConfig
        ) do

        local machine =
            settings.machine

        if machine
            and tonumber(
                machine.computerID
            ) == computerID then

            local side =
                machine.side

            local machineKey =
                machine.machineKey

            -- =============================================
            -- RESOURCE -> MACHINE
            -- =============================================

            resourceMachines[
                itemID
            ] = {
                itemID =
                    itemID,

                displayName =
                    getDisplayName(
                        itemID
                    ),

                machineKey =
                    machineKey,

                side =
                    side,

                target =
                    tonumber(
                        settings.target
                    )
                    or 0,

                percent =
                    nil,

                amount =
                    nil
            }

            requestedStates[
                itemID
            ] =
                oldRequests[
                    itemID
                ] == true

            -- =============================================
            -- PHYSICAL SIDE
            --
            -- Multiple resources may share this.
            -- =============================================

            if not physicalMachines[
                side
            ] then

                physicalMachines[
                    side
                ] = {
                    side =
                        side,

                    running =
                        false,

                    resources =
                        {}
                }
            end

            local physical =
                physicalMachines[
                    side
                ]

            physical.resources[
                #physical.resources + 1
            ] =
                itemID
        end
    end
end

-- =========================================================
-- CALCULATE PHYSICAL OUTPUT
--
-- This is what makes shared machines work.
--
-- If ANY resource assigned to TOP needs production:
-- TOP = ON.
--
-- TOP only switches OFF when EVERY resource assigned to
-- TOP says it no longer needs production.
-- =========================================================

local function updatePhysicalMachine(
    side
)

    local physical =
        physicalMachines[
            side
        ]

    if not physical then
        return
    end

    local shouldRun =
        false

    for _,
        itemID
        in ipairs(
            physical.resources
        ) do

        if requestedStates[
            itemID
        ] == true then

            shouldRun =
                true

            break
        end
    end

    physical.running =
        shouldRun

    redstone.setOutput(
        side,
        shouldRun
    )
end

local function updateAllPhysicalMachines()

    for side
        in pairs(
            physicalMachines
        ) do

        updatePhysicalMachine(
            side
        )
    end
end

rebuildMachines()

updateAllPhysicalMachines()

-- =========================================================
-- SEND MACHINE STATUS
--
-- Status is sent for EACH resource.
--
-- If Iron and Gold share TOP and TOP is running,
-- both resources are reported as attached to a running
-- physical machine.
-- =========================================================

local function sendResourceStatus(
    itemID
)

    local resource =
        resourceMachines[
            itemID
        ]

    if not resource then
        return
    end

    local physical =
        physicalMachines[
            resource.side
        ]

    local running =
        physical
        and physical.running
        == true

    rednet.broadcast(
        {
            messageType =
                "resource_machine_status",

            role =
                "RESOURCE",

            itemID =
                itemID,

            displayName =
                resource.displayName,

            machineKey =
                resource.machineKey,

            side =
                resource.side,

            state =
                running,

            requested =
                requestedStates[
                    itemID
                ] == true,

            percent =
                resource.percent,

            amount =
                resource.amount,

            target =
                resource.target,

            computerID =
                computerID,

            timestamp =
                os.epoch(
                    "utc"
                )
        },
        machineStatusProtocol
    )
end

local function sendAllMachineStatus()

    for itemID
        in pairs(
            resourceMachines
        ) do

        sendResourceStatus(
            itemID
        )
    end
end

-- =========================================================
-- PROCESS AUTOMATIC COMMAND
-- =========================================================

local function processAutoSet(
    message
)

    if type(
        message
    ) ~= "table" then

        return
    end

    local itemID =
        message.itemID

    if type(itemID)
        ~= "string" then

        return
    end

    local resource =
        resourceMachines[
            itemID
        ]

    if not resource then
        return
    end

    -- =====================================================
    -- SAFETY CHECKS
    -- =====================================================

    if message.machineKey
        and message.machineKey
            ~= resource.machineKey then

        return
    end

    if message.side
        and message.side
            ~= resource.side then

        return
    end

    -- =====================================================
    -- SAVE RESOURCE REQUEST
    -- =====================================================

    requestedStates[
        itemID
    ] =
        message.state
        == true

    resource.percent =
        tonumber(
            message.percent
        )

    resource.amount =
        tonumber(
            message.amount
        )

    resource.target =
        tonumber(
            message.target
        )
        or resource.target

    -- =====================================================
    -- RECOMPUTE PHYSICAL MACHINE
    -- =====================================================

    updatePhysicalMachine(
        resource.side
    )

    -- Because another resource may share this machine,
    -- resend every resource attached to this side.
    local physical =
        physicalMachines[
            resource.side
        ]

    if physical then

        for _,
            sharedItemID
            in ipairs(
                physical.resources
            ) do

            sendResourceStatus(
                sharedItemID
            )
        end
    end
end

-- =========================================================
-- CONFIG REFRESH STATUS
-- =========================================================

local function sendRefreshStatus(
    success,
    errorMessage
)

    rednet.broadcast(
        {
            command =
                "targets_refresh_status",

            success =
                success == true,

            error =
                errorMessage,

            role =
                "RESOURCE",

            computerID =
                computerID,

            timestamp =
                os.epoch(
                    "utc"
                )
        },
        configStatusProtocol
    )
end

-- =========================================================
-- FORCE TARGET REFRESH
-- =========================================================

local function forceTargetsRefresh()

    print(
        "Refreshing targets..."
    )

    local success,
        refreshError =
        downloadTargets()

    if not success then

        print(
            "Refresh FAILED:"
        )

        print(
            tostring(
                refreshError
            )
        )

        sendRefreshStatus(
            false,
            tostring(
                refreshError
            )
        )

        return false
    end

    -- Rebuild assignments from new config.
    rebuildMachines()

    updateAllPhysicalMachines()

    sendAllMachineStatus()

    sendRefreshStatus(
        true,
        nil
    )

    print(
        "Targets updated."
    )

    return true
end

-- =========================================================
-- LOCAL SCREEN
-- =========================================================

local function drawScreen()

    term.setBackgroundColor(
        colors.black
    )

    term.setTextColor(
        colors.white
    )

    term.clear()

    term.setCursorPos(
        1,
        1
    )

    print(
        "RESOURCE MACHINE NODE"
    )

    print(
        "====================="
    )

    print(
        "Computer: "
        .. tostring(
            computerID
        )
    )

    print(
        "Config: GitHub"
    )

    print("")

    -- =====================================================
    -- PHYSICAL MACHINES
    -- =====================================================

    print(
        "MACHINES:"
    )

    local sides = {
        "top",
        "bottom",
        "left",
        "right",
        "front",
        "back"
    }

    local foundMachine =
        false

    for _,
        side
        in ipairs(
            sides
        ) do

        local physical =
            physicalMachines[
                side
            ]

        if physical then

            foundMachine =
                true

            term.setTextColor(
                colors.white
            )

            print(
                " "
                .. string.upper(
                    side
                )
            )

            if physical.running then

                term.setTextColor(
                    colors.lime
                )

                print(
                    "  RUNNING"
                )

            else

                term.setTextColor(
                    colors.red
                )

                print(
                    "  STOPPED"
                )
            end

            term.setTextColor(
                colors.lightGray
            )

            for _,
                itemID
                in ipairs(
                    physical.resources
                ) do

                local requested =
                    requestedStates[
                        itemID
                    ] == true

                print(
                    "   "
                    .. (
                        requested
                        and "[ON] "
                        or "[--] "
                    )
                    .. getDisplayName(
                        itemID
                    )
                )
            end
        end
    end

    if not foundMachine then

        term.setTextColor(
            colors.orange
        )

        print(
            " NONE ASSIGNED"
        )
    end

    term.setTextColor(
        colors.white
    )

    print("")

    print(
        "Waiting for Storage Brain..."
    )
end

-- =========================================================
-- STATUS LOOP
-- =========================================================

local function statusLoop()

    while true do

        sendAllMachineStatus()

        sleep(
            statusInterval
        )
    end
end

-- =========================================================
-- DISPLAY LOOP
-- =========================================================

local function displayLoop()

    while true do

        drawScreen()

        sleep(1)
    end
end

-- =========================================================
-- NETWORK LOOP
-- =========================================================

local function networkLoop()

    while true do

        local senderID,
            message,
            protocol =
            rednet.receive()

        -- =================================================
        -- AUTOMATIC MACHINE CONTROL
        -- =================================================

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

        -- =================================================
        -- MAIN SCREEN TARGET REFRESH
        -- =================================================

        elseif protocol
                == configControlProtocol
            and type(message)
                == "table"
            and message.command
                == "force_targets_refresh" then

            forceTargetsRefresh()
        end
    end
end

-- =========================================================
-- START
-- =========================================================

sendAllMachineStatus()

parallel.waitForAll(
    networkLoop,
    statusLoop,
    displayLoop
)