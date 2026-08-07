-- =========================================================
-- MAIN STATUS SCREEN
-- Quick overview of resource machines, storage demand,
-- spawners, and mob-farm fans.
--
-- Tap a resource row for a detailed machine view.
-- =========================================================

local machineStatusProtocol = "resource_machine_status"
local storageStatusProtocol = "inventory_status"
local spawnerStatusProtocol = "spawner_status"
local fanProtocol = "mob_farm_fans"

local offlineSeconds = 12
local renderInterval = 0.5

local modemSide
local monitor
local monitorName

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
local storage = {}
local spawners = {}
local fansState = nil

local screenDirty = true
local selectedItemID = nil
local rowButtons = {}
local backButton = nil

-- =========================================================
-- HELPERS
-- =========================================================

local function now()
    return os.epoch("utc")
end

local function keyForSpawner(id, key)
    return tostring(id) .. ":" .. tostring(key)
end

local function short(text, maximum)
    text = tostring(text or "")

    if #text <= maximum then
        return text
    end

    return string.sub(
        text,
        1,
        math.max(1, maximum - 2)
    ) .. ".."
end

local function pct(amount, target)
    amount = tonumber(amount)
    target = tonumber(target)

    if not amount
        or not target
        or target <= 0 then
        return nil
    end

    return amount / target * 100
end

local function formatNumber(value)
    value = tonumber(value)

    if not value then
        return "--"
    end

    value = math.floor(value + 0.5)

    local text = tostring(value)
    local formatted = text

    while true do
        local changed
        formatted, changed = string.gsub(
            formatted,
            "^(-?%d+)(%d%d%d)",
            "%1,%2"
        )

        if changed == 0 then
            break
        end
    end

    return formatted
end

local function ageText(timestamp)
    timestamp = tonumber(timestamp) or 0

    if timestamp <= 0 then
        return "NEVER"
    end

    local ageMs = math.max(0, now() - timestamp)
    local seconds = math.floor(ageMs / 1000)

    if seconds < 60 then
        return tostring(seconds) .. "s AGO"
    end

    local minutes = math.floor(seconds / 60)

    if minutes < 60 then
        return tostring(minutes) .. "m AGO"
    end

    local hours = math.floor(minutes / 60)
    return tostring(hours) .. "h AGO"
end

local function isOnline(timestamp)
    return now() - (tonumber(timestamp) or 0)
        <= offlineSeconds * 1000
end

local function isInside(x, y, button)
    return button
        and x >= button.x1
        and x <= button.x2
        and y >= button.y1
        and y <= button.y2
end

-- =========================================================
-- NETWORK PROCESSING
-- =========================================================

local function processMachine(sender, message)
    if type(message) ~= "table"
        or message.messageType ~= "resource_machine_status"
        or type(message.itemID) ~= "string" then
        return
    end

    local row = machines[message.itemID] or {}

    row.itemID = message.itemID
    row.name = message.displayName
        or row.name
        or message.itemID

    row.computerID = message.computerID or sender
    row.machineKey = message.machineKey or row.machineKey
    row.side = message.side or row.side
    row.role = message.role or row.role

    row.requested =
        message.requested ~= nil
        and message.requested == true
        or message.state == true

    row.running =
        message.running ~= nil
        and message.running == true
        or message.state == true

    if message.amount ~= nil then
        row.amount = tonumber(message.amount)
    end

    if message.target ~= nil then
        row.target = tonumber(message.target)
    end

    if message.percent ~= nil then
        row.percent = tonumber(message.percent)
    end

    row.lastUpdate = now()

    machines[message.itemID] = row
    screenDirty = true
end

local function processStorage(message)
    if type(message) ~= "table"
        or message.messageType ~= "inventory_update" then
        return
    end

    local itemID = message.itemID or message.storageKey

    if type(itemID) ~= "string" then
        return
    end

    storage[itemID] = {
        amount = tonumber(message.amount) or 0,
        target = tonumber(message.targetAmount or message.target) or 0,
        name = message.displayName or itemID,
        computerID = message.computerID,
        role = message.role,
        lastUpdate = now()
    }

    screenDirty = true
end

local function processSpawner(sender, message)
    if type(message) ~= "table"
        or message.messageType ~= "spawner_status" then
        return
    end

    local key = keyForSpawner(
        sender,
        message.spawnerKey
    )

    spawners[key] = {
        name = message.displayName
            or message.spawnerKey
            or key,
        state = message.state == true,
        computerID = message.computerID or sender,
        spawnerKey = message.spawnerKey,
        outputSide = message.outputSide,
        lastUpdate = now()
    }

    screenDirty = true
end

local function processFan(message)
    if type(message) == "table"
        and message.command == "fans" then

        fansState = message.state == true
        screenDirty = true
    end
end

-- =========================================================
-- DRAWING HELPERS
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

local function mergedMachine(itemID)
    local source = machines[itemID]

    if not source then
        return nil
    end

    local result = {}

    for key, value in pairs(source) do
        result[key] = value
    end

    local stored = storage[itemID]

    if stored then
        result.name = stored.name or result.name
        result.amount = stored.amount
        result.target = stored.target
        result.percent = pct(
            stored.amount,
            stored.target
        )
        result.storageComputerID = stored.computerID
        result.storageRole = stored.role
        result.storageLastUpdate = stored.lastUpdate
    end

    return result
end

local function sortedMachines()
    local rows = {}

    for itemID in pairs(machines) do
        local row = mergedMachine(itemID)

        if row then
            rows[#rows + 1] = row
        end
    end

    table.sort(
        rows,
        function(a, b)
            return string.lower(
                a.name or a.itemID
            ) < string.lower(
                b.name or b.itemID
            )
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

    fill(
        1,
        1,
        width,
        height,
        colors.black
    )

    drawHeader(
        "SYSTEM STATUS",
        "TAP A RESOURCE FOR DETAILS"
    )

    local rows = sortedMachines()
    local nowMs = now()

    local y = 6

    local reqX = math.floor(width * 0.46)
    local runX = math.floor(width * 0.58)
    local pcX = math.floor(width * 0.69)
    local levelX = math.floor(width * 0.80)

    writeAt(
        2,
        y,
        "RESOURCE",
        colors.lightGray,
        colors.black
    )

    writeAt(reqX, y, "REQ", colors.lightGray, colors.black)
    writeAt(runX, y, "RUN", colors.lightGray, colors.black)
    writeAt(pcX, y, "PC", colors.lightGray, colors.black)
    writeAt(levelX, y, "LEVEL", colors.lightGray, colors.black)

    y = y + 1

    local maxRows = math.max(1, height - 13)

    for index = 1, math.min(#rows, maxRows) do
        local machine = rows[index]
        local online = isOnline(machine.lastUpdate)

        local requestText =
            machine.requested and "YES" or "NO"

        local runningText

        if not online then
            runningText = "LOST"
        elseif machine.running then
            runningText = "ON"
        else
            runningText = "OFF"
        end

        local levelText =
            machine.percent
            and string.format(
                "%.0f%%",
                machine.percent
            )
            or "--"

        local rowBackground =
            index % 2 == 0
            and colors.black
            or colors.gray

        fill(
            1,
            y,
            width,
            y,
            rowBackground
        )

        writeAt(
            2,
            y,
            short(
                machine.name or machine.itemID,
                math.floor(width * 0.42) - 2
            ),
            colors.white,
            rowBackground
        )

        writeAt(
            reqX,
            y,
            requestText,
            machine.requested
                and colors.orange
                or colors.lightGray,
            rowBackground
        )

        writeAt(
            runX,
            y,
            runningText,
            online
                and (
                    machine.running
                    and colors.lime
                    or colors.red
                )
                or colors.orange,
            rowBackground
        )

        writeAt(
            pcX,
            y,
            tostring(machine.computerID or "?"),
            colors.lightBlue,
            rowBackground
        )

        writeAt(
            levelX,
            y,
            levelText,
            colors.white,
            rowBackground
        )

        rowButtons[#rowButtons + 1] = {
            x1 = 1,
            y1 = y,
            x2 = width,
            y2 = y,
            itemID = machine.itemID
        }

        y = y + 1
    end

    local configured = 0
    local active = 0
    local offline = 0

    for _, spawner in pairs(spawners) do
        configured = configured + 1

        if nowMs - (spawner.lastUpdate or 0)
            > offlineSeconds * 1000 then
            offline = offline + 1
        elseif spawner.state then
            active = active + 1
        end
    end

    local requestedCount = 0
    local runningCount = 0

    for _, machine in ipairs(rows) do
        if machine.requested then
            requestedCount = requestedCount + 1
        end

        if machine.running
            and isOnline(machine.lastUpdate) then
            runningCount = runningCount + 1
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

    writeAt(
        2,
        footerY + 1,
        "MACHINES "
            .. #rows
            .. "  REQUESTED "
            .. requestedCount
            .. "  RUNNING "
            .. runningCount,
        colors.white,
        colors.gray
    )

    writeAt(
        2,
        footerY + 2,
        "SPAWNERS "
            .. configured
            .. "  ACTIVE "
            .. active
            .. "  OFFLINE "
            .. offline
            .. "  FANS "
            .. (
                fansState == nil
                and "?"
                or (
                    fansState
                    and "ON"
                    or "OFF"
                )
            ),
        colors.white,
        colors.gray
    )
end

-- =========================================================
-- MACHINE DETAIL VIEW
-- =========================================================

local function detailLine(
    y,
    label,
    value,
    valueColor
)
    local width = monitor.getSize()

    writeAt(
        3,
        y,
        label,
        colors.lightGray,
        colors.black
    )

    local valueX = math.max(
        20,
        math.floor(width * 0.30)
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
    local machine = mergedMachine(selectedItemID)

    rowButtons = {}

    if not machine then
        selectedItemID = nil
        drawOverview()
        return
    end

    fill(
        1,
        1,
        width,
        height,
        colors.black
    )

    drawHeader(
        "MACHINE DETAILS",
        short(
            string.upper(
                machine.name or machine.itemID
            ),
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

    detailLine(
        y,
        "RESOURCE",
        machine.name or machine.itemID,
        colors.white
    )
    y = y + 2

    detailLine(
        y,
        "ITEM ID",
        machine.itemID,
        colors.lightBlue
    )
    y = y + 1

    detailLine(
        y,
        "MACHINE KEY",
        machine.machineKey or "--",
        colors.lightBlue
    )
    y = y + 1

    detailLine(
        y,
        "COMPUTER ID",
        machine.computerID or "?",
        colors.lightBlue
    )
    y = y + 1

    detailLine(
        y,
        "OUTPUT SIDE",
        machine.side
            and string.upper(machine.side)
            or "--",
        colors.lightBlue
    )
    y = y + 1

    detailLine(
        y,
        "NODE ROLE",
        machine.role or "--",
        colors.lightBlue
    )
    y = y + 2

    detailLine(
        y,
        "REQUESTED",
        machine.requested and "YES" or "NO",
        machine.requested
            and colors.orange
            or colors.lightGray
    )
    y = y + 1

    detailLine(
        y,
        "RUNNING",
        online
            and (
                machine.running
                and "YES"
                or "NO"
            )
            or "NO SIGNAL",
        online
            and (
                machine.running
                and colors.lime
                or colors.red
            )
            or colors.orange
    )
    y = y + 1

    detailLine(
        y,
        "ONLINE",
        online and "YES" or "NO",
        online and colors.lime or colors.red
    )
    y = y + 1

    detailLine(
        y,
        "LAST MACHINE",
        ageText(machine.lastUpdate),
        online and colors.white or colors.orange
    )
    y = y + 2

    detailLine(
        y,
        "CURRENT",
        formatNumber(machine.amount),
        colors.white
    )
    y = y + 1

    detailLine(
        y,
        "TARGET",
        formatNumber(machine.target),
        colors.white
    )
    y = y + 1

    detailLine(
        y,
        "LEVEL",
        machine.percent
            and string.format(
                "%.2f%%",
                machine.percent
            )
            or "--",
        machine.percent
            and machine.percent >= 100
            and colors.lime
            or colors.white
    )
    y = y + 2

    detailLine(
        y,
        "STORAGE PC",
        machine.storageComputerID or "--",
        colors.lightBlue
    )
    y = y + 1

    detailLine(
        y,
        "STORAGE ROLE",
        machine.storageRole or "--",
        colors.lightBlue
    )
    y = y + 1

    detailLine(
        y,
        "LAST STORAGE",
        machine.storageLastUpdate
            and ageText(machine.storageLastUpdate)
            or "--",
        colors.white
    )

    local statusY = height - 3

    fill(
        1,
        statusY,
        width,
        height,
        colors.gray
    )

    local stateText
    local stateColor

    if not online then
        stateText = "OFFLINE / NO MACHINE STATUS"
        stateColor = colors.orange
    elseif machine.running then
        stateText = "RUNNING"
        stateColor = colors.lime
    elseif machine.requested then
        stateText = "REQUESTED - WAITING"
        stateColor = colors.orange
    else
        stateText = "IDLE"
        stateColor = colors.white
    end

    center(
        1,
        width,
        statusY + 1,
        stateText,
        stateColor,
        colors.gray
    )

    center(
        1,
        width,
        statusY + 2,
        "TAP BACK TO RETURN TO OVERVIEW",
        colors.white,
        colors.gray
    )
end

local function draw()
    if selectedItemID then
        drawDetail()
    else
        drawOverview()
    end
end

-- =========================================================
-- EVENTS
-- =========================================================

local function handleTouch(x, y)
    if selectedItemID then
        if isInside(x, y, backButton) then
            selectedItemID = nil
            screenDirty = true
        end

        return
    end

    for _, button in ipairs(rowButtons) do
        if isInside(x, y, button) then
            selectedItemID = button.itemID
            screenDirty = true
            return
        end
    end
end

local function eventLoop()
    while true do
        local event, a, b, c = os.pullEvent()

        if event == "rednet_message" then
            if c == machineStatusProtocol then
                processMachine(a, b)

            elseif c == storageStatusProtocol then
                processStorage(b)

            elseif c == spawnerStatusProtocol then
                processSpawner(a, b)

            elseif c == fanProtocol then
                processFan(b)
            end

        elseif event == "monitor_touch"
            and a == monitorName then

            handleTouch(b, c)

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
            draw()
        end

        sleep(renderInterval)
        screenDirty = true
    end
end

parallel.waitForAll(
    eventLoop,
    renderLoop
)
