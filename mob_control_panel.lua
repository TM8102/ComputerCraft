-- =========================================================
-- MOB CONTROL PANEL
-- Wide two-row controls, maintenance lockout, fan clear-out,
-- Pink Slime override, live discovery, and refresh debug.
-- =========================================================

local monitorSide = "right"
local modemSide = "back"

local controlProtocol = "spawner_control"
local statusProtocol = "spawner_status"
local fanProtocol = "mob_farm_fans"
local machineStatusProtocol = "resource_machine_status"
local configControlProtocol = "spawner_config_control"
local configStatusProtocol = "spawner_config_status"

local pinkSlimeItemID = "industrialforegoing:pink_slime"
local databaseFile = "spawner_registry.db"
local maintenanceFile = "mob_maintenance.db"

local maxSpawners = 45
local offlineSeconds = 12
local removeAfterSeconds = 60
local startupDiscoverySeconds = 15
local discoveryInterval = 5
local animationSpeed = 0.15
local fanShutdownSeconds = 30
local refreshWaitSeconds = 5
local refreshResultSeconds = 10

local monitor = peripheral.wrap(monitorSide)
if not monitor then error("No monitor found on " .. monitorSide) end
if not monitor.isColor() then error("Advanced Monitor required") end
if not peripheral.isPresent(modemSide) then error("No modem found on " .. modemSide) end

rednet.open(modemSide)
monitor.setTextScale(0.5)
local monitorName = peripheral.getName(monitor)

local theme = {
    background = colors.black,
    header = colors.cyan,
    headerText = colors.black,
    accent = colors.blue,
    card = colors.gray,
    emptyCard = colors.black,
    title = colors.white,
    placeholder = colors.gray,
    runningDark = colors.green,
    runningBright = colors.lime,
    off = colors.red,
    offlineA = colors.red,
    offlineB = colors.orange,
    emptyBorder = colors.gray,
    masterOn = colors.green,
    masterOff = colors.red,
    fanOn = colors.lime,
    fanOff = colors.red,
    maintenanceOn = colors.orange,
    maintenanceOff = colors.gray,
    refresh = colors.green,
    refreshPressed = colors.lime,
    reboot = colors.blue,
    rebootPressed = colors.lightBlue,
    footer = colors.gray,
    footerText = colors.white,
    popup = colors.gray,
    popupBorder = colors.lightGray,
    popupTitle = colors.cyan,
    success = colors.lime,
    failure = colors.red,
    pending = colors.orange
}

local spawners = {}
local buttons = {
    masterOn = {},
    masterOff = {},
    fans = {},
    maintenance = {},
    refresh = {},
    reboot = {}
}

local fansState = false
local fanShutdownRemaining = 0
local fanShutdownTimer = nil
local animationFrame = 0
local startupCheckComplete = false
local pinkSlimeAutomationActive = false
local pinkSlimeSnapshot = nil
local knownNodes = {}
local maintenanceMode = false

local refresh = {
    visible = false,
    running = false,
    started = 0,
    finishedAt = 0,
    expected = {},
    responses = {}
}

-- =========================================================
-- HELPERS
-- =========================================================

local function now()
    return os.epoch("utc")
end

local function fill(x1, y1, x2, y2, color)
    if x2 < x1 or y2 < y1 then return end
    monitor.setBackgroundColor(color)
    for y = y1, y2 do
        monitor.setCursorPos(x1, y)
        monitor.write(string.rep(" ", x2 - x1 + 1))
    end
end

local function writeAt(x, y, text, foreground, background)
    monitor.setCursorPos(x, y)
    monitor.setTextColor(foreground)
    monitor.setBackgroundColor(background)
    monitor.write(tostring(text))
end

local function shorten(text, width)
    text = tostring(text or "")
    if width <= 0 then return "" end
    if #text <= width then return text end
    if width <= 3 then return string.sub(text, 1, width) end
    return string.sub(text, 1, width - 2) .. ".."
end

local function center(x1, x2, y, text, foreground, background)
    local width = x2 - x1 + 1
    text = shorten(text, width)
    local x = x1 + math.floor((width - #text) / 2)
    writeAt(x, y, text, foreground, background)
end

local function border(x1, y1, x2, y2, color)
    fill(x1, y1, x2, y1, color)
    fill(x1, y2, x2, y2, color)
    fill(x1, y1, x1, y2, color)
    fill(x2, y1, x2, y2, color)
end

local function inside(x, y, button)
    return x >= button.x1
        and x <= button.x2
        and y >= button.y1
        and y <= button.y2
end

local function borderPoints(x1, y1, x2, y2)
    local result = {}
    for x = x1, x2 do result[#result + 1] = {x=x, y=y1} end
    for y = y1 + 1, y2 - 1 do result[#result + 1] = {x=x2, y=y} end
    for x = x2, x1, -1 do result[#result + 1] = {x=x, y=y2} end
    for y = y2 - 1, y1 + 1, -1 do result[#result + 1] = {x=x1, y=y} end
    return result
end

-- =========================================================
-- MAINTENANCE PERSISTENCE
-- =========================================================

local function saveMaintenance()
    local file = fs.open(maintenanceFile, "w")
    if file then
        file.write(maintenanceMode and "true" or "false")
        file.close()
    end
end

local function loadMaintenance()
    if not fs.exists(maintenanceFile) then return false end
    local file = fs.open(maintenanceFile, "r")
    if not file then return false end
    local raw = file.readAll()
    file.close()
    return raw == "true"
end

maintenanceMode = loadMaintenance()

-- =========================================================
-- SPAWNER REGISTRY
-- =========================================================

local function emptySpawner()
    return {
        name = "",
        computerID = 0,
        spawnerKey = "",
        state = false,
        online = false,
        lastUpdate = 0,
        seenSinceBoot = false,
        x1 = 0, y1 = 0, x2 = 0, y2 = 0,
        titleY = 0,
        borderPoints = {}
    }
end

for index = 1, maxSpawners do
    spawners[index] = emptySpawner()
end

local function saveDatabase()
    local saved = {}

    for index, spawner in ipairs(spawners) do
        if spawner.computerID ~= 0 and spawner.spawnerKey ~= "" then
            saved[index] = {
                computerID = spawner.computerID,
                spawnerKey = spawner.spawnerKey,
                name = spawner.name
            }
        end
    end

    local file = fs.open(databaseFile, "w")
    if file then
        file.write(textutils.serialize(saved))
        file.close()
    end
end

local function loadDatabase()
    if not fs.exists(databaseFile) then return end

    local file = fs.open(databaseFile, "r")
    if not file then return end

    local raw = file.readAll()
    file.close()

    local ok, saved = pcall(textutils.unserialize, raw)
    if not ok or type(saved) ~= "table" then return end

    for index = 1, maxSpawners do
        local source = saved[index]
        if source then
            spawners[index].computerID = tonumber(source.computerID) or 0
            spawners[index].spawnerKey = tostring(source.spawnerKey or "")
            spawners[index].name = tostring(source.name or "")
        end
    end
end

loadDatabase()

local function clearSpawner(spawner)
    local fresh = emptySpawner()
    for key, value in pairs(fresh) do
        spawner[key] = value
    end
end

local function compactRegistry()
    local keep = {}

    for _, spawner in ipairs(spawners) do
        if spawner.computerID ~= 0 and spawner.spawnerKey ~= "" then
            keep[#keep + 1] = {
                name = spawner.name,
                computerID = spawner.computerID,
                spawnerKey = spawner.spawnerKey,
                state = spawner.state,
                online = spawner.online,
                lastUpdate = spawner.lastUpdate,
                seenSinceBoot = spawner.seenSinceBoot
            }
        end
    end

    for index = 1, maxSpawners do
        clearSpawner(spawners[index])
        local source = keep[index]
        if source then
            for key, value in pairs(source) do
                spawners[index][key] = value
            end
        end
    end

    saveDatabase()
end

local function findSpawner(computerID, spawnerKey)
    for index, spawner in ipairs(spawners) do
        if spawner.computerID == computerID
            and spawner.spawnerKey == spawnerKey then
            return spawner, index
        end
    end
end

local function registerSpawner(computerID, spawnerKey, name)
    if type(spawnerKey) ~= "string" or spawnerKey == "" then return nil end

    local spawner, index = findSpawner(computerID, spawnerKey)

    if not spawner then
        for candidateIndex, candidate in ipairs(spawners) do
            if candidate.computerID == 0 then
                spawner = candidate
                index = candidateIndex
                break
            end
        end
    end

    if not spawner then return nil end

    spawner.computerID = computerID
    spawner.spawnerKey = spawnerKey
    if type(name) == "string" and name ~= "" then
        spawner.name = name
    end
    spawner.online = true
    spawner.seenSinceBoot = true
    spawner.lastUpdate = now()
    saveDatabase()

    return spawner, index
end

local function rememberNode(id, role)
    knownNodes[id] = {
        role = role or "REMOTE_SPAWNER",
        lastSeen = now()
    }
end

-- =========================================================
-- LAYOUT
-- =========================================================

local function calculateLayout()
    local width, height = monitor.getSize()

    -- Larger controls: two rows of three buttons.
    -- Row 1: MASTER ON | MASTER OFF | FANS
    -- Row 2: MAINTENANCE | REFRESH | REBOOT
    local margin = 2
    local gap = 1
    local buttonWidth = math.floor((width - (margin * 2) - (gap * 2)) / 3)

    if buttonWidth < 14 then
        error("Monitor too narrow for control panel")
    end

    local x1 = margin
    local x2 = x1 + buttonWidth - 1
    local x3 = x2 + gap + 1
    local x4 = x3 + buttonWidth - 1
    local x5 = x4 + gap + 1
    local x6 = width - margin

    buttons.masterOn = {x1=x1, x2=x2, y1=2, y2=4}
    buttons.masterOff = {x1=x3, x2=x4, y1=2, y2=4}
    buttons.fans = {x1=x5, x2=x6, y1=2, y2=4}

    buttons.maintenance = {x1=x1, x2=x2, y1=5, y2=7}
    buttons.refresh = {x1=x3, x2=x4, y1=5, y2=7}
    buttons.reboot = {x1=x5, x2=x6, y1=5, y2=7}

    local columns = 5
    local rows = 9
    local cardHeight = 5
    local gapX = 1
    local gapY = 1
    local topY = 9
    local bottomY = height - 2
    local availableWidth = width - 2
    local availableHeight = bottomY - topY + 1
    local cardWidth = math.floor((availableWidth - gapX * (columns - 1)) / columns)

    if cardWidth < 10 then error("Monitor too narrow") end

    local gridWidth = columns * cardWidth + gapX * (columns - 1)
    local gridHeight = rows * cardHeight + gapY * (rows - 1)

    if gridHeight > availableHeight then
        error("Monitor too short")
    end

    local startX = math.floor((width - gridWidth) / 2) + 1
    local startY = topY + math.floor((availableHeight - gridHeight) / 2)

    for index, spawner in ipairs(spawners) do
        local column = (index - 1) % columns
        local row = math.floor((index - 1) / columns)

        spawner.x1 = startX + column * (cardWidth + gapX)
        spawner.y1 = startY + row * (cardHeight + gapY)
        spawner.x2 = spawner.x1 + cardWidth - 1
        spawner.y2 = spawner.y1 + cardHeight - 1
        spawner.titleY = spawner.y1 + 2
        spawner.borderPoints = borderPoints(
            spawner.x1, spawner.y1, spawner.x2, spawner.y2
        )
    end
end

-- =========================================================
-- DRAWING
-- =========================================================

local function drawButton(button, text, color)
    fill(button.x1, button.y1, button.x2, button.y2, color)
    center(button.x1, button.x2, button.y1 + 1, text, colors.white, color)
end

local function drawFanButton()
    if maintenanceMode then
        drawButton(buttons.fans, "FANS: OFF", theme.fanOff)
    elseif fanShutdownRemaining > 0 then
        drawButton(
            buttons.fans,
            "FANS: " .. fanShutdownRemaining .. "s",
            theme.fanOn
        )
    elseif fansState then
        drawButton(buttons.fans, "FANS: ON", theme.fanOn)
    else
        drawButton(buttons.fans, "FANS: OFF", theme.fanOff)
    end
end

local function drawMaintenanceButton()
    if maintenanceMode then
        drawButton(buttons.maintenance, "MAINTENANCE: ON", theme.maintenanceOn)
    else
        drawButton(buttons.maintenance, "MAINTENANCE", theme.maintenanceOff)
    end
end

local function drawHeader()
    local width = monitor.getSize()
    fill(1, 1, width, 8, theme.header)

    local title = "SPAWNER CONTROL"
    if maintenanceMode then
        title = title .. "  |  MAINTENANCE LOCKOUT"
    elseif pinkSlimeAutomationActive then
        title = title .. "  |  PINK SLIME AUTO"
    end

    center(1, width, 1, title, theme.headerText, theme.header)

    drawButton(
        buttons.masterOn,
        pinkSlimeAutomationActive and not maintenanceMode
            and "AUTO / MASTER ON"
            or "MASTER ON",
        maintenanceMode and colors.gray or theme.masterOn
    )

    drawButton(buttons.masterOff, "MASTER OFF", theme.masterOff)
    drawFanButton()
    drawMaintenanceButton()
    drawButton(
        buttons.refresh,
        refresh.running and "REFRESHING..." or "REFRESH SPAWNERS",
        refresh.running and theme.refreshPressed or theme.refresh
    )
    drawButton(buttons.reboot, "REBOOT PANEL", theme.reboot)

    fill(1, 8, width, 8, theme.accent)
end

local function drawSpawner(spawner, index)
    local inner = spawner.computerID == 0
        and theme.emptyCard
        or theme.card

    fill(spawner.x1 + 1, spawner.y1 + 1, spawner.x2 - 1, spawner.y2 - 1, inner)

    local title = spawner.computerID == 0
        and ("SLOT " .. index)
        or string.upper(
            spawner.name ~= ""
            and spawner.name
            or ("SPAWNER " .. spawner.spawnerKey)
        )

    center(
        spawner.x1 + 1,
        spawner.x2 - 1,
        spawner.titleY,
        title,
        spawner.computerID == 0 and theme.placeholder or theme.title,
        inner
    )

    if spawner.computerID == 0 then
        border(spawner.x1, spawner.y1, spawner.x2, spawner.y2, theme.emptyBorder)

    elseif maintenanceMode then
        border(spawner.x1, spawner.y1, spawner.x2, spawner.y2, colors.orange)

    elseif not spawner.online then
        local color = math.floor(animationFrame / 3) % 2 == 0
            and theme.offlineA
            or theme.offlineB
        border(spawner.x1, spawner.y1, spawner.x2, spawner.y2, color)

    elseif not spawner.state then
        border(spawner.x1, spawner.y1, spawner.x2, spawner.y2, theme.off)

    else
        local pattern = {
            theme.runningDark,
            theme.runningDark,
            theme.runningDark,
            theme.runningBright,
            theme.runningBright,
            theme.runningDark
        }

        for pointIndex, point in ipairs(spawner.borderPoints) do
            local color = pattern[((pointIndex + animationFrame - 2) % #pattern) + 1]
            writeAt(point.x, point.y, " ", colors.white, color)
        end
    end
end

local function counts()
    local configured, online, running, offline = 0, 0, 0, 0

    for _, spawner in ipairs(spawners) do
        if spawner.computerID ~= 0 then
            configured = configured + 1
            if spawner.online then
                online = online + 1
                if spawner.state then running = running + 1 end
            else
                offline = offline + 1
            end
        end
    end

    return configured, online, running, offline
end

local function drawFooter()
    local width, height = monitor.getSize()
    fill(1, height - 1, width, height, theme.footer)

    local configured, online, running, offline = counts()

    local left = "ACTIVE " .. running
        .. "   ONLINE " .. online .. "/" .. configured
        .. "   OFFLINE " .. offline

    if maintenanceMode then
        left = "MAINTENANCE LOCKOUT   |   " .. left
    end

    writeAt(2, height, shorten(left, width - 2), theme.footerText, theme.footer)

    local right = fansState and "FANS ON" or "FANS OFF"
    if pinkSlimeAutomationActive and not maintenanceMode then
        right = "PINK AUTO   " .. right
    end

    writeAt(
        math.max(2, width - #right),
        height,
        right,
        maintenanceMode and colors.orange or theme.footerText,
        theme.footer
    )
end

-- =========================================================
-- REFRESH POPUP
-- =========================================================

local function tableCount(input)
    local count = 0
    for _ in pairs(input) do count = count + 1 end
    return count
end

local function refreshSuccessCount()
    local count = 0
    for _, response in pairs(refresh.responses) do
        if response.success then count = count + 1 end
    end
    return count
end

local function refreshFailureCount()
    local count = 0
    for _, response in pairs(refresh.responses) do
        if not response.success then count = count + 1 end
    end
    return count
end

local function drawRefreshPopup()
    if not refresh.visible then return end

    local width, height = monitor.getSize()
    local popupWidth = math.min(64, width - 8)
    local popupHeight = math.min(18, height - 10)
    local x1 = math.floor((width - popupWidth) / 2) + 1
    local y1 = math.floor((height - popupHeight) / 2) + 1
    local x2 = x1 + popupWidth - 1
    local y2 = y1 + popupHeight - 1

    border(x1, y1, x2, y2, theme.popupBorder)
    fill(x1 + 1, y1 + 1, x2 - 1, y2 - 1, theme.popup)
    center(x1 + 2, x2 - 2, y1 + 1, "SPAWNER CONFIG REFRESH", theme.popupTitle, theme.popup)

    local expected = tableCount(refresh.expected)
    local responses = tableCount(refresh.responses)

    local summary = refresh.running
        and ("UPDATING " .. responses .. " / " .. expected)
        or (refreshSuccessCount() .. " UPDATED   " .. refreshFailureCount() .. " FAILED")

    center(x1 + 2, x2 - 2, y1 + 3, summary, colors.white, theme.popup)

    local ids = {}
    local seen = {}

    for id in pairs(refresh.expected) do
        ids[#ids + 1] = id
        seen[id] = true
    end

    for id in pairs(refresh.responses) do
        if not seen[id] then ids[#ids + 1] = id end
    end

    table.sort(ids)

    local row = y1 + 5

    for _, id in ipairs(ids) do
        if row >= y2 - 1 then break end

        local response = refresh.responses[id]

        if response then
            writeAt(
                x1 + 3, row,
                response.success and "+" or "X",
                response.success and theme.success or theme.failure,
                theme.popup
            )
            writeAt(x1 + 5, row, "NODE " .. id, colors.white, theme.popup)
            writeAt(
                x2 - 10, row,
                response.success and "UPDATED" or "FAILED",
                response.success and theme.success or theme.failure,
                theme.popup
            )

            if not response.success and response.error and row + 1 < y2 - 1 then
                row = row + 1
                writeAt(
                    x1 + 7, row,
                    shorten(response.error, popupWidth - 12),
                    theme.failure,
                    theme.popup
                )
            end
        else
            writeAt(x1 + 3, row, "?", theme.pending, theme.popup)
            writeAt(x1 + 5, row, "NODE " .. id, colors.white, theme.popup)
            writeAt(
                x2 - 10, row,
                refresh.running and "WAITING" or "NO REPLY",
                theme.pending,
                theme.popup
            )
        end

        row = row + 1
    end
end

local function drawScreen()
    local width, height = monitor.getSize()
    fill(1, 1, width, height, theme.background)
    drawHeader()
    for index, spawner in ipairs(spawners) do
        drawSpawner(spawner, index)
    end
    drawFooter()
    drawRefreshPopup()
end

-- =========================================================
-- OUTPUT CONTROL
-- =========================================================

local function sendSpawnerState(spawner)
    if spawner.computerID == 0 then return end

    local desired = spawner.state == true
    if maintenanceMode and desired then
        desired = false
        spawner.state = false
    end

    rednet.send(
        spawner.computerID,
        {
            command = "spawn",
            spawnerKey = spawner.spawnerKey,
            state = desired
        },
        controlProtocol
    )
end

local function sendFansState()
    if maintenanceMode and fansState then
        fansState = false
    end

    rednet.broadcast({
        command = "fans",
        state = fansState
    }, fanProtocol)
end

local function cancelFanShutdown()
    fanShutdownRemaining = 0
    fanShutdownTimer = nil
end

local function setFans(state)
    if maintenanceMode and state == true then state = false end
    fansState = state == true
    sendFansState()
    drawFanButton()
    drawFooter()
end

local function setAllSpawners(state)
    if maintenanceMode and state == true then state = false end

    for index, spawner in ipairs(spawners) do
        if spawner.computerID ~= 0 then
            spawner.state = state == true
            sendSpawnerState(spawner)
            drawSpawner(spawner, index)
        end
    end
end

local function masterOn()
    if maintenanceMode then
        setAllSpawners(false)
        setFans(false)
        return
    end

    cancelFanShutdown()
    setFans(true)
    setAllSpawners(true)
    rednet.broadcast({command="all_on"}, controlProtocol)
    drawHeader()
    drawFooter()
end

local function masterOff()
    setAllSpawners(false)
    rednet.broadcast({command="all_off"}, controlProtocol)

    if maintenanceMode then
        cancelFanShutdown()
        setFans(false)
    else
        fansState = true
        sendFansState()
        fanShutdownRemaining = fanShutdownSeconds
        fanShutdownTimer = os.startTimer(1)
    end

    drawHeader()
    drawFooter()
end

local function toggleFans()
    if maintenanceMode then
        cancelFanShutdown()
        setFans(false)
        return
    end

    cancelFanShutdown()
    setFans(not fansState)
end

-- =========================================================
-- MAINTENANCE
-- =========================================================

local function applyMaintenanceLockout()
    cancelFanShutdown()
    pinkSlimeAutomationActive = false
    pinkSlimeSnapshot = nil

    setAllSpawners(false)
    rednet.broadcast({command="all_off"}, controlProtocol)

    fansState = false
    sendFansState()

    rednet.broadcast({
        command = "maintenance",
        state = true,
        timestamp = now()
    }, controlProtocol)
end

local function setMaintenance(state)
    state = state == true

    if state == maintenanceMode then
        if maintenanceMode then applyMaintenanceLockout() end
        return
    end

    maintenanceMode = state
    saveMaintenance()

    if maintenanceMode then
        applyMaintenanceLockout()
    else
        rednet.broadcast({
            command = "maintenance",
            state = false,
            timestamp = now()
        }, controlProtocol)

        setAllSpawners(false)
        setFans(false)
    end

    drawScreen()
end

local function toggleMaintenance()
    setMaintenance(not maintenanceMode)
end

-- =========================================================
-- PINK SLIME AUTOMATION
-- =========================================================

local function stateKey(spawner)
    return tostring(spawner.computerID)
        .. ":"
        .. tostring(spawner.spawnerKey)
end

local function capturePinkSnapshot()
    local snapshot = {
        fansState = fansState,
        spawners = {}
    }

    for _, spawner in ipairs(spawners) do
        if spawner.computerID ~= 0 then
            snapshot.spawners[stateKey(spawner)] = spawner.state == true
        end
    end

    return snapshot
end

local function restorePinkSnapshot()
    if maintenanceMode then
        pinkSlimeSnapshot = nil
        return
    end

    local snapshot = pinkSlimeSnapshot
    if not snapshot then return end

    cancelFanShutdown()

    for index, spawner in ipairs(spawners) do
        if spawner.computerID ~= 0 then
            spawner.state = snapshot.spawners[stateKey(spawner)] == true
            sendSpawnerState(spawner)
            drawSpawner(spawner, index)
        end
    end

    setFans(snapshot.fansState == true)
    pinkSlimeSnapshot = nil
    drawHeader()
    drawFooter()
end

local function setPinkAutomation(requested)
    requested = requested == true

    if maintenanceMode then
        pinkSlimeAutomationActive = false
        pinkSlimeSnapshot = nil
        applyMaintenanceLockout()
        return
    end

    if requested and not pinkSlimeAutomationActive then
        pinkSlimeSnapshot = capturePinkSnapshot()
        pinkSlimeAutomationActive = true
        masterOn()

    elseif not requested and pinkSlimeAutomationActive then
        pinkSlimeAutomationActive = false
        restorePinkSnapshot()
    end
end

local function processMachineStatus(message)
    if type(message) == "table"
        and message.messageType == "resource_machine_status"
        and message.itemID == pinkSlimeItemID then
        setPinkAutomation(message.state == true)
    end
end

-- =========================================================
-- DISCOVERY / STATUS
-- =========================================================

local function requestDiscovery()
    rednet.broadcast({command="discover"}, controlProtocol)

    if maintenanceMode then
        rednet.broadcast({
            command = "maintenance",
            state = true,
            timestamp = now()
        }, controlProtocol)

        rednet.broadcast({command="all_off"}, controlProtocol)
        fansState = false
        sendFansState()
    end
end

local function processManifest(senderID, message)
    rememberNode(senderID, message.role)

    if type(message.enabledKeys) ~= "table" then return end

    local enabled = {}
    for _, key in ipairs(message.enabledKeys) do
        enabled[key] = true
    end

    local changed = false

    for _, spawner in ipairs(spawners) do
        if spawner.computerID == senderID then
            if enabled[spawner.spawnerKey] then
                spawner.seenSinceBoot = true
            else
                -- Important for N/A: when a side disappears from the
                -- node manifest, its old card is removed immediately.
                clearSpawner(spawner)
                changed = true
            end
        end
    end

    if changed then
        compactRegistry()
        calculateLayout()
        drawScreen()
    end
end

local function processSpawnerStatus(senderID, message)
    rememberNode(senderID, message.role)

    if message.messageType ~= "spawner_status" then return end

    local spawner, index = registerSpawner(
        senderID,
        message.spawnerKey,
        message.displayName
    )

    if not spawner then return end

    spawner.state = message.state == true
    spawner.online = true
    spawner.seenSinceBoot = true
    spawner.lastUpdate = now()

    if maintenanceMode then
        if spawner.state then
            spawner.state = false
            sendSpawnerState(spawner)
        end

        rednet.send(
            senderID,
            {command="maintenance", state=true, timestamp=now()},
            controlProtocol
        )

    elseif pinkSlimeAutomationActive and not spawner.state then
        spawner.state = true
        sendSpawnerState(spawner)
    end

    if not refresh.visible then
        drawSpawner(spawner, index)
        drawFooter()
    end
end

-- =========================================================
-- REFRESH
-- =========================================================

local function startRefresh()
    refresh.visible = true
    refresh.running = true
    refresh.started = now()
    refresh.finishedAt = 0
    refresh.responses = {}
    refresh.expected = {}

    local timestamp = now()

    for id, info in pairs(knownNodes) do
        if timestamp - (info.lastSeen or 0) <= offlineSeconds * 1000 then
            refresh.expected[id] = true
        end
    end

    rednet.broadcast({
        command = "force_spawners_refresh",
        requestedBy = os.getComputerID(),
        timestamp = timestamp
    }, configControlProtocol)

    drawScreen()
end

local function processRefreshStatus(senderID, message)
    rememberNode(senderID, message.role)

    if message.command ~= "spawners_refresh_status" then return end

    refresh.visible = true
    refresh.responses[senderID] = {
        success = message.success == true,
        error = message.error,
        role = message.role,
        configSource = message.configSource,
        timestamp = now()
    }

    drawScreen()
end

local function updateRefresh()
    if not refresh.visible then return end

    local timestamp = now()

    if refresh.running then
        local expected = tableCount(refresh.expected)
        local responses = tableCount(refresh.responses)

        if (expected > 0 and responses >= expected)
            or timestamp - refresh.started >= refreshWaitSeconds * 1000 then

            refresh.running = false
            refresh.finishedAt = timestamp
            drawScreen()
        end

    elseif refresh.finishedAt > 0
        and timestamp - refresh.finishedAt >= refreshResultSeconds * 1000 then

        refresh.visible = false
        drawScreen()
    end
end

-- =========================================================
-- CLEANUP / OFFLINE
-- =========================================================

local function finishStartupCleanup()
    if startupCheckComplete then return end
    startupCheckComplete = true

    local changed = false

    for _, spawner in ipairs(spawners) do
        if spawner.computerID ~= 0 and not spawner.seenSinceBoot then
            clearSpawner(spawner)
            changed = true
        end
    end

    if changed then
        compactRegistry()
        calculateLayout()
        drawScreen()
    end
end

local function updateOffline()
    local timestamp = now()
    local removed = false

    for index, spawner in ipairs(spawners) do
        if spawner.computerID ~= 0 and spawner.lastUpdate > 0 then
            local age = timestamp - spawner.lastUpdate

            if age > removeAfterSeconds * 1000 then
                clearSpawner(spawner)
                removed = true

            elseif age > offlineSeconds * 1000 and spawner.online then
                spawner.online = false
                if not refresh.visible then
                    drawSpawner(spawner, index)
                end
            end
        end
    end

    if removed then
        compactRegistry()
        calculateLayout()
        drawScreen()
    elseif not refresh.visible then
        drawFooter()
    end
end

local function rebootComputer()
    drawButton(buttons.reboot, "REBOOTING...", theme.rebootPressed)
    sleep(0.3)

    monitor.setBackgroundColor(colors.black)
    monitor.clear()

    local width, height = monitor.getSize()
    center(
        1, width, math.floor(height / 2),
        "REBOOTING SPAWNER CONTROL...",
        colors.cyan, colors.black
    )

    sleep(0.7)
    os.reboot()
end

-- =========================================================
-- START
-- =========================================================

calculateLayout()

if maintenanceMode then
    applyMaintenanceLockout()
end

drawScreen()
requestDiscovery()

local animationTimer = os.startTimer(animationSpeed)
local offlineTimer = os.startTimer(2)
local discoveryTimer = os.startTimer(discoveryInterval)
local startupTimer = os.startTimer(startupDiscoverySeconds)
local refreshTimer = os.startTimer(0.5)

while true do
    local event, a, b, c = os.pullEvent()

    if event == "monitor_touch" and a == monitorName then
        local x, y = b, c

        if not refresh.visible then
            if inside(x, y, buttons.masterOn) then
                masterOn()

            elseif inside(x, y, buttons.masterOff) then
                masterOff()

            elseif inside(x, y, buttons.fans) then
                toggleFans()

            elseif inside(x, y, buttons.maintenance) then
                toggleMaintenance()

            elseif inside(x, y, buttons.refresh) then
                startRefresh()

            elseif inside(x, y, buttons.reboot) then
                rebootComputer()

            elseif not maintenanceMode then
                for index, spawner in ipairs(spawners) do
                    if spawner.computerID ~= 0
                        and x >= spawner.x1 and x <= spawner.x2
                        and y >= spawner.y1 and y <= spawner.y2 then

                        spawner.state = not spawner.state
                        sendSpawnerState(spawner)
                        drawSpawner(spawner, index)
                        drawFooter()
                        break
                    end
                end
            end
        end

    elseif event == "rednet_message" then
        local senderID, message, protocol = a, b, c

        if protocol == statusProtocol and type(message) == "table" then
            if message.messageType == "spawner_manifest" then
                processManifest(senderID, message)
            elseif message.messageType == "spawner_status" then
                processSpawnerStatus(senderID, message)
            end

        elseif protocol == configStatusProtocol and type(message) == "table" then
            processRefreshStatus(senderID, message)

        elseif protocol == machineStatusProtocol and type(message) == "table" then
            processMachineStatus(message)
        end

    elseif event == "timer" and a == animationTimer then
        animationFrame = animationFrame + 1

        if not refresh.visible then
            for index, spawner in ipairs(spawners) do
                if spawner.computerID ~= 0 then
                    drawSpawner(spawner, index)
                end
            end
        end

        animationTimer = os.startTimer(animationSpeed)

    elseif event == "timer" and a == offlineTimer then
        if maintenanceMode then applyMaintenanceLockout() end
        updateOffline()
        offlineTimer = os.startTimer(2)

    elseif event == "timer" and a == discoveryTimer then
        requestDiscovery()
        discoveryTimer = os.startTimer(discoveryInterval)

    elseif event == "timer" and a == startupTimer then
        finishStartupCleanup()

    elseif event == "timer" and a == refreshTimer then
        updateRefresh()
        refreshTimer = os.startTimer(0.5)

    elseif event == "timer" and fanShutdownTimer and a == fanShutdownTimer then
        if maintenanceMode then
            cancelFanShutdown()
            setFans(false)
        else
            fanShutdownRemaining = math.max(0, fanShutdownRemaining - 1)

            if fanShutdownRemaining > 0 then
                fanShutdownTimer = os.startTimer(1)
            else
                fanShutdownTimer = nil
                setFans(false)
            end
        end

        if not refresh.visible then
            drawFanButton()
            drawFooter()
        end

    elseif event == "monitor_resize" and a == monitorName then
        monitor.setTextScale(0.5)
        calculateLayout()
        drawScreen()
    end
end
