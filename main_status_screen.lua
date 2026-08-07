-- =========================================================
-- MAIN STATUS SCREEN
--
-- Quick-glance screen ONLY.
-- This intentionally does NOT duplicate the storage screen.
--
-- Shows:
--   * Resource machines currently requested/running
--   * Active mob spawners
--   * Fan state
--   * Offline warning for a machine that was active
--
-- Tap an active machine row for simple details.
-- =========================================================

local machineStatusProtocol = "resource_machine_status"
local spawnerStatusProtocol = "spawner_status"
local fanProtocol = "mob_farm_fans"

local offlineSeconds = 12
local renderInterval = 0.5

local modemSide = nil
local monitor = nil
local monitorName = nil

-- =========================================================
-- AUTO DISCOVER MODEM + MONITOR
-- =========================================================

for _, side in ipairs({
    "top", "bottom", "left", "right", "front", "back"
}) do
    if peripheral.isPresent(side) then
        local p = peripheral.wrap(side)
        local t = peripheral.getType(side)

        if not modemSide and t == "modem" then
            modemSide = side
        end

        if not monitor
            and p
            and type(p.isColor) == "function"
            and p.isColor() then

            monitor = p
            monitorName = peripheral.getName(p)
        end
    end
end

if not modemSide then
    error("No modem found")
end

if not monitor then
    error("No Advanced Monitor found")
end

rednet.open(modemSide)
monitor.setTextScale(0.5)

-- =========================================================
-- STATE
-- =========================================================

local machines = {}
local spawners = {}
local fansState = nil

local selectedItemID = nil
local rowButtons = {}
local backButton = nil
local screenDirty = true

-- =========================================================
-- HELPERS
-- =========================================================

local function now()
    return os.epoch("utc")
end

local function short(text, maximum)
    text = tostring(text or "")

    if #text <= maximum then
        return text
    end

    if maximum <= 2 then
        return string.sub(text, 1, maximum)
    end

    return string.sub(text, 1, maximum - 2) .. ".."
end

local function isOnline(timestamp)
    timestamp = tonumber(timestamp) or 0

    return timestamp > 0
        and now() - timestamp <= offlineSeconds * 1000
end

local function ageText(timestamp)
    timestamp = tonumber(timestamp) or 0

    if timestamp <= 0 then
        return "NEVER"
    end

    local seconds = math.floor(
        math.max(0, now() - timestamp) / 1000
    )

    if seconds < 60 then
        return tostring(seconds) .. "s AGO"
    end

    local minutes = math.floor(seconds / 60)

    if minutes < 60 then
        return tostring(minutes) .. "m AGO"
    end

    return tostring(math.floor(minutes / 60)) .. "h AGO"
end

local function keyForSpawner(id, key)
    return tostring(id) .. ":" .. tostring(key)
end

local function isInside(x, y, button)
    return button
        and x >= button.x1
        and x <= button.x2
        and y >= button.y1
        and y <= button.y2
end

-- =========================================================
-- NETWORK
-- =========================================================

local function processMachine(senderID, message)
    if type(message) ~= "table"
        or message.messageType ~= "resource_machine_status"
        or type(message.itemID) ~= "string" then

        return
    end

    local machine = machines[message.itemID] or {}

    machine.itemID = message.itemID
    machine.name = message.displayName
        or machine.name
        or message.itemID

    machine.computerID = message.computerID or senderID
    machine.machineKey = message.machineKey or machine.machineKey
    machine.side = message.side or machine.side
    machine.role = message.role or machine.role

    -- At the moment the machine node's redstone output is the
    -- authoritative state, so state=true means it was requested
    -- and the controller has turned that machine output on.
    machine.requested =
        message.requested ~= nil
        and message.requested == true
        or message.state == true

    machine.running =
        message.running ~= nil
        and message.running == true
        or message.state == true

    if message.percent ~= nil then
        machine.percent = tonumber(message.percent)
    end

    if message.amount ~= nil then
        machine.amount = tonumber(message.amount)
    end

    if message.target ~= nil then
        machine.target = tonumber(message.target)
    end

    -- Remember whether this machine was active on its last
    -- successful status. Useful for showing LOST warnings.
    machine.wasActive =
        machine.requested == true
        or machine.running == true

    machine.lastUpdate = now()

    machines[message.itemID] = machine
    screenDirty = true
end

local function processSpawner(senderID, message)
    if type(message) ~= "table"
        or message.messageType ~= "spawner_status" then

        return
    end

    local key = keyForSpawner(
        senderID,
        message.spawnerKey
    )

    spawners[key] = {
        name = message.displayName
            or message.spawnerKey
            or key,

        state = message.state == true,
        computerID = message.computerID or senderID,
        spawnerKey = message.spawnerKey,
        outputSide = message.outputSide,
        lastUpdate = now()
    }

    screenDirty = true
end

local function processFans(message)
    if type(message) == "table"
        and message.command == "fans" then

        fansState = message.state == true
        screenDirty = true
    end
end

-- =========================================================
-- DRAWING
-- =========================================================

local function fill(x1, y1, x2, y2, background)
    if x2 < x1 or y2 < y1 then
        return
    end

    monitor.setBackgroundColor(background)

    for y = y1, y2 do
        monitor.setCursorPos(x1, y)
        monitor.write(
            string.rep(
                " ",
                math.max(0, x2 - x1 + 1)
            )
        )
    end
end

local function writeAt(x, y, text, foreground, background)
    monitor.setCursorPos(x, y)
    monitor.setTextColor(foreground)
    monitor.setBackgroundColor(background)
    monitor.write(tostring(text))
end

local function center(x1, x2, y, text, foreground, background)
    local width = x2 - x1 + 1
    text = short(text, width)

    local x = x1
        + math.floor((width - #text) / 2)

    writeAt(
        x,
        y,
        text,
        foreground,
        background
    )
end

local function drawHeader(title, subtitle)
    local width = monitor.getSize()

    fill(1, 1, width, 4, colors.cyan)

    writeAt(
        3,
        2,
        title,
        colors.black,
        colors.cyan
    )

    writeAt(
        3,
        3,
        subtitle,
        colors.gray,
        colors.cyan
    )
end

-- =========================================================
-- ACTIVE LIST BUILDERS
-- =========================================================

local function activeMachines()
    local rows = {}

    for _, machine in pairs(machines) do
        local online = isOnline(machine.lastUpdate)

        if online then
            -- Hide all normal idle machines.
            if machine.requested or machine.running then
                rows[#rows + 1] = machine
            end
        elseif machine.wasActive then
            -- Keep an active machine visible if we lose contact
            -- with it, so an unexpected shutdown is obvious.
            rows[#rows + 1] = machine
        end
    end

    table.sort(
        rows,
        function(a, b)
            local aOnline = isOnline(a.lastUpdate)
            local bOnline = isOnline(b.lastUpdate)

            if aOnline ~= bOnline then
                return not aOnline
            end

            return string.lower(a.name or a.itemID)
                < string.lower(b.name or b.itemID)
        end
    )

    return rows
end

local function activeSpawners()
    local rows = {}

    for _, spawner in pairs(spawners) do
        if spawner.state
            and isOnline(spawner.lastUpdate) then

            rows[#rows + 1] = spawner
        end
    end

    table.sort(
        rows,
        function(a, b)
            return string.lower(a.name)
                < string.lower(b.name)
        end
    )

    return rows
end

-- =========================================================
-- OVERVIEW
-- =========================================================

local function drawOverview()
    local width, height = monitor.getSize()

    rowButtons = {}
    backButton = nil

    fill(1, 1, width, height, colors.black)

    drawHeader(
        "SYSTEM STATUS",
        "ACTIVE / REQUESTED EQUIPMENT ONLY"
    )

    local machineRows = activeMachines()
    local spawnerRows = activeSpawners()

    local y = 6

    writeAt(
        2,
        y,
        "RESOURCE MACHINES",
        colors.lightBlue,
        colors.black
    )

    y = y + 2

    if #machineRows == 0 then
        writeAt(
            3,
            y,
            "ALL RESOURCE MACHINES IDLE",
            colors.gray,
            colors.black
        )

        y = y + 2
    else
        for index, machine in ipairs(machineRows) do
            if y >= height - 8 then
                break
            end

            local online = isOnline(machine.lastUpdate)

            local background =
                index % 2 == 0
                and colors.black
                or colors.gray

            fill(1, y, width, y + 1, background)

            writeAt(
                2,
                y,
                short(
                    string.upper(
                        machine.name or machine.itemID
                    ),
                    math.max(10, math.floor(width * 0.52))
                ),
                colors.white,
                background
            )

            local stateText
            local stateColor

            if not online then
                stateText = "OFFLINE / LOST"
                stateColor = colors.orange
            elseif machine.running then
                stateText = "RUNNING"
                stateColor = colors.lime
            elseif machine.requested then
                stateText = "REQUESTED"
                stateColor = colors.orange
            else
                stateText = "ACTIVE"
                stateColor = colors.lightBlue
            end

            writeAt(
                math.floor(width * 0.58),
                y,
                stateText,
                stateColor,
                background
            )

            local extra =
                "PC "
                .. tostring(machine.computerID or "?")
                .. "  "
                .. string.upper(
                    tostring(machine.side or "?")
                )

            if machine.percent then
                extra = extra
                    .. "  "
                    .. string.format("%.0f%%", machine.percent)
            end

            writeAt(
                3,
                y + 1,
                short(extra, width - 5),
                colors.lightGray,
                background
            )

            rowButtons[#rowButtons + 1] = {
                x1 = 1,
                y1 = y,
                x2 = width,
                y2 = y + 1,
                itemID = machine.itemID
            }

            y = y + 2
        end
    end

    if y < height - 7 then
        writeAt(
            2,
            y,
            "ACTIVE SPAWNERS",
            colors.lightBlue,
            colors.black
        )

        y = y + 2

        if #spawnerRows == 0 then
            writeAt(
                3,
                y,
                "NONE",
                colors.gray,
                colors.black
            )
        else
            local names = {}

            for _, spawner in ipairs(spawnerRows) do
                names[#names + 1] = spawner.name
            end

            writeAt(
                3,
                y,
                short(
                    table.concat(names, "  |  "),
                    width - 5
                ),
                colors.lime,
                colors.black
            )
        end
    end

    local footerY = height - 3

    fill(
        1,
        footerY,
        width,
        height,
        colors.gray
    )

    local machineText =
        "ACTIVE MACHINES " .. #machineRows
        .. "  ACTIVE SPAWNERS " .. #spawnerRows

    writeAt(
        2,
        footerY + 1,
        short(machineText, width - 3),
        colors.white,
        colors.gray
    )

    local fanText =
        "FANS: "
        .. (
            fansState == nil
            and "UNKNOWN"
            or (
                fansState
                and "ON"
                or "OFF"
            )
        )

    writeAt(
        2,
        footerY + 2,
        fanText,
        fansState
            and colors.lime
            or (
                fansState == nil
                and colors.orange
                or colors.white
            ),
        colors.gray
    )
end

-- =========================================================
-- SIMPLE MACHINE DETAILS
-- =========================================================

local function detailLine(y, label, value, valueColor)
    local width = monitor.getSize()
    local valueX = math.max(18, math.floor(width * 0.30))

    writeAt(
        3,
        y,
        label,
        colors.lightGray,
        colors.black
    )

    writeAt(
        valueX,
        y,
        short(
            tostring(value or "--"),
            width - valueX - 2
        ),
        valueColor or colors.white,
        colors.black
    )
end

local function drawDetail()
    local width, height = monitor.getSize()
    local machine = machines[selectedItemID]

    rowButtons = {}

    if not machine then
        selectedItemID = nil
        drawOverview()
        return
    end

    fill(1, 1, width, height, colors.black)

    drawHeader(
        "ACTIVE MACHINE",
        short(
            string.upper(machine.name or machine.itemID),
            width - 6
        )
    )

    backButton = {
        x1 = math.max(2, width - 14),
        y1 = 2,
        x2 = width - 2,
        y2 = 3
    }

    fill(
        backButton.x1,
        backButton.y1,
        backButton.x2,
        backButton.y2,
        colors.blue
    )

    center(
        backButton.x1,
        backButton.x2,
        2,
        "< BACK",
        colors.white,
        colors.blue
    )

    local online = isOnline(machine.lastUpdate)
    local y = 6

    local stateText
    local stateColor

    if not online then
        stateText = "OFFLINE / LOST"
        stateColor = colors.orange
    elseif machine.running then
        stateText = "RUNNING"
        stateColor = colors.lime
    elseif machine.requested then
        stateText = "REQUESTED"
        stateColor = colors.orange
    else
        stateText = "IDLE"
        stateColor = colors.gray
    end

    detailLine(y, "STATUS", stateText, stateColor)
    y = y + 2

    detailLine(y, "RESOURCE", machine.name or machine.itemID)
    y = y + 1

    detailLine(y, "ITEM ID", machine.itemID)
    y = y + 1

    detailLine(y, "MACHINE KEY", machine.machineKey)
    y = y + 1

    detailLine(y, "COMPUTER", machine.computerID, colors.lightBlue)
    y = y + 1

    detailLine(
        y,
        "SIDE",
        string.upper(tostring(machine.side or "--"))
    )
    y = y + 1

    detailLine(y, "NODE ROLE", machine.role)
    y = y + 2

    detailLine(
        y,
        "REQUESTED",
        machine.requested and "YES" or "NO",
        machine.requested and colors.orange or colors.gray
    )
    y = y + 1

    detailLine(
        y,
        "RUNNING",
        machine.running and "YES" or "NO",
        machine.running and colors.lime or colors.red
    )
    y = y + 1

    detailLine(
        y,
        "LAST UPDATE",
        ageText(machine.lastUpdate),
        online and colors.white or colors.orange
    )
    y = y + 2

    if machine.percent then
        detailLine(
            y,
            "RESOURCE LEVEL",
            string.format("%.1f%%", machine.percent)
        )
    end
end

local function drawScreen()
    if selectedItemID then
        drawDetail()
    else
        drawOverview()
    end
end

-- =========================================================
-- EVENT LOOP
-- =========================================================

local function eventLoop()
    while true do
        local event, a, b, c = os.pullEvent()

        if event == "rednet_message" then
            if c == machineStatusProtocol then
                processMachine(a, b)

            elseif c == spawnerStatusProtocol then
                processSpawner(a, b)

            elseif c == fanProtocol then
                processFans(b)
            end

        elseif event == "monitor_touch"
            and a == monitorName then

            local x = b
            local y = c

            if selectedItemID then
                if isInside(x, y, backButton) then
                    selectedItemID = nil
                    screenDirty = true
                end
            else
                for _, button in ipairs(rowButtons) do
                    if isInside(x, y, button) then
                        selectedItemID = button.itemID
                        screenDirty = true
                        break
                    end
                end
            end

        elseif event == "monitor_resize"
            and a == monitorName then

            monitor.setTextScale(0.5)
            screenDirty = true
        end
    end
end

local function renderLoop()
    while true do
        if screenDirty then
            screenDirty = false
            drawScreen()
        end

        sleep(renderInterval)
        screenDirty = true
    end
end

parallel.waitForAll(
    eventLoop,
    renderLoop
)
