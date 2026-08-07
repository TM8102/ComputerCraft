local monitorSide = "right"
local modemSide = "back"

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

-- NEW
local configControlProtocol =
    "config_control"

local configStatusProtocol =
    "config_status"

-- =========================================================
-- DISPLAY
-- =========================================================

local maxStorages = 40

-- =========================================================
-- TIMING
-- =========================================================

local sourceOfflineSeconds = 12
local sourceRemoveSeconds = 60

local discoveryInterval = 5

local renderInterval = 0.20

-- How long the refresh-status message remains in header.
local refreshMessageSeconds = 8

-- =========================================================
-- ANIMATION
-- =========================================================

local animationSpeed = 0.12
local flashInterval = 0.48
local chaseLength = 6

local chaseFrame = 0

local flashState = false
local flashElapsed = 0

-- =========================================================
-- DIRTY RENDER
-- =========================================================

local screenDirty = true

-- =========================================================
-- MONITOR
-- =========================================================

local monitor =
    peripheral.wrap(
        monitorSide
    )

if not monitor then
    error(
        "No monitor found on "
        .. monitorSide
    )
end

if not monitor.isColor() then
    error(
        "Advanced Monitor required"
    )
end

monitor.setTextScale(0.5)

local monitorName =
    peripheral.getName(
        monitor
    )

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
-- THEME
-- =========================================================

local theme = {
    background =
        colors.black,

    header =
        colors.cyan,

    headerText =
        colors.black,

    headerSubtext =
        colors.gray,

    accent =
        colors.blue,

    card =
        colors.gray,

    emptyCard =
        colors.black,

    title =
        colors.white,

    amountText =
        colors.white,

    -- Storage levels
    full =
        colors.lime,

    good =
        colors.lightBlue,

    warning =
        colors.orange,

    low =
        colors.red,

    criticalRed =
        colors.red,

    criticalBlack =
        colors.black,

    -- Errors
    errorRed =
        colors.red,

    errorOrange =
        colors.orange,

    -- Machine chase
    machineChase =
        colors.lime,

    -- Progress
    progressBackground =
        colors.black,

    progressFull =
        colors.lime,

    progressGood =
        colors.lightBlue,

    progressWarning =
        colors.orange,

    progressLow =
        colors.red,

    -- Empty cards
    emptyBorder =
        colors.gray,

    placeholderText =
        colors.gray,

    -- Buttons
    rebootButton =
        colors.blue,

    rebootPressed =
        colors.lightBlue,

    refreshButton =
        colors.green,

    refreshPressed =
        colors.lime,

    refreshFailure =
        colors.red,

    -- Footer
    footer =
        colors.gray,

    footerText =
        colors.white
}

-- =========================================================
-- DATA
-- =========================================================

local storageSources = {}

local machineStates = {}

local cards = {}

local cardOrder = {}

local layoutSlots = {}

local rebootButton = {}

local refreshButton = {}

-- =========================================================
-- REFRESH STATUS
-- =========================================================

local refreshStatus = {
    active = false,

    started =
        0,

    successCount =
        0,

    failureCount =
        0,

    lastMessage =
        "",

    lastComputer =
        nil
}

-- =========================================================
-- DRAW HELPERS
-- =========================================================

local function fill(
    x1,
    y1,
    x2,
    y2,
    color
)
    if x2 < x1
        or y2 < y1 then

        return
    end

    monitor.setBackgroundColor(
        color
    )

    for y = y1, y2 do
        monitor.setCursorPos(
            x1,
            y
        )

        monitor.write(
            string.rep(
                " ",
                x2 - x1 + 1
            )
        )
    end
end

local function writeAt(
    x,
    y,
    text,
    fg,
    bg
)
    monitor.setCursorPos(
        x,
        y
    )

    monitor.setTextColor(
        fg
    )

    monitor.setBackgroundColor(
        bg
    )

    monitor.write(
        tostring(
            text
        )
    )
end

local function shortenText(
    text,
    maxLength
)
    text =
        tostring(
            text or ""
        )

    if maxLength <= 0 then
        return ""
    end

    if #text <= maxLength then
        return text
    end

    if maxLength <= 3 then
        return string.sub(
            text,
            1,
            maxLength
        )
    end

    return string.sub(
        text,
        1,
        maxLength - 2
    ) .. ".."
end

local function centerInside(
    x1,
    x2,
    y,
    text,
    fg,
    bg
)
    local width =
        x2 - x1 + 1

    text =
        shortenText(
            text,
            width
        )

    local x =
        x1
        + math.floor(
            (
                width
                - #text
            ) / 2
        )

    writeAt(
        x,
        y,
        text,
        fg,
        bg
    )
end

local function drawBorder(
    x1,
    y1,
    x2,
    y2,
    color
)
    fill(
        x1,
        y1,
        x2,
        y1,
        color
    )

    fill(
        x1,
        y2,
        x2,
        y2,
        color
    )

    fill(
        x1,
        y1,
        x1,
        y2,
        color
    )

    fill(
        x2,
        y1,
        x2,
        y2,
        color
    )
end

local function drawPixel(
    x,
    y,
    color
)
    monitor.setCursorPos(
        x,
        y
    )

    monitor.setBackgroundColor(
        color
    )

    monitor.write(" ")
end

local function isInside(
    x,
    y,
    x1,
    y1,
    x2,
    y2
)
    return x >= x1
        and x <= x2
        and y >= y1
        and y <= y2
end

-- =========================================================
-- BORDER POINTS
-- =========================================================

local function getBorderPoints(
    x1,
    y1,
    x2,
    y2
)
    local points = {}

    for x = x1, x2 do
        points[
            #points + 1
        ] = {
            x = x,
            y = y1
        }
    end

    for y = y1 + 1,
        y2 - 1 do

        points[
            #points + 1
        ] = {
            x = x2,
            y = y
        }
    end

    for x = x2,
        x1,
        -1 do

        points[
            #points + 1
        ] = {
            x = x,
            y = y2
        }
    end

    for y = y2 - 1,
        y1 + 1,
        -1 do

        points[
            #points + 1
        ] = {
            x = x1,
            y = y
        }
    end

    return points
end

-- =========================================================
-- NUMBER FORMAT
-- =========================================================

local function commaNumber(
    number
)
    number =
        math.floor(
            tonumber(number)
            or 0
        )

    local text =
        tostring(number)

    while true do
        local formatted,
            replacements =
            string.gsub(
                text,
                "^(-?%d+)(%d%d%d)",
                "%1,%2"
            )

        text =
            formatted

        if replacements == 0 then
            break
        end
    end

    return text
end

-- =========================================================
-- STORAGE SOURCES
-- =========================================================

local function ensureStorageSource(
    computerID
)
    if not storageSources[
        computerID
    ] then

        storageSources[
            computerID
        ] = {}
    end

    return storageSources[
        computerID
    ]
end

-- =========================================================
-- MANIFEST
-- =========================================================

local function processStorageManifest(
    senderID,
    message
)
    if type(
        message.enabledKeys
    ) ~= "table" then

        return
    end

    local enabled = {}

    for _,
        itemID
        in ipairs(
            message.enabledKeys
        ) do

        if type(itemID)
            == "string" then

            enabled[
                itemID
            ] =
                true
        end
    end

    local source =
        ensureStorageSource(
            senderID
        )

    local changed =
        false

    for itemID
        in pairs(
            source
        ) do

        if not enabled[
            itemID
        ] then

            source[
                itemID
            ] =
                nil

            changed =
                true
        end
    end

    if changed then
        screenDirty =
            true
    end
end

-- =========================================================
-- INVENTORY UPDATE
-- =========================================================

local function processInventoryUpdate(
    senderID,
    message
)
    local itemID =
        message.itemID
        or message.storageKey

    if type(itemID)
        ~= "string" then

        return
    end

    local source =
        ensureStorageSource(
            senderID
        )

    source[
        itemID
    ] = {
        itemID =
            itemID,

        displayName =
            message.displayName
            or itemID,

        amount =
            tonumber(
                message.amount
            ) or 0,

        targetAmount =
            tonumber(
                message.targetAmount
                or message.target
            ) or 0,

        found =
            message.found
            ~= false,

        online =
            message.online
            ~= false,

        error =
            message.error,

        lastUpdate =
            os.epoch(
                "utc"
            )
    }

    screenDirty =
        true
end

-- =========================================================
-- MACHINE STATUS
-- =========================================================

local function processMachineStatus(
    senderID,
    message
)
    if type(
        message.itemID
    ) ~= "string" then

        return
    end

    machineStates[
        message.itemID
    ] = {
        running =
            message.state
            == true,

        computerID =
            senderID,

        machineKey =
            message.machineKey,

        side =
            message.side,

        lastUpdate =
            os.epoch(
                "utc"
            )
    }

    screenDirty =
        true
end

-- =========================================================
-- CONFIG REFRESH ACK
-- =========================================================

local function processConfigStatus(
    senderID,
    message
)
    if message.command
        ~= "targets_refresh_status" then

        return
    end

    refreshStatus.active =
        true

    refreshStatus.lastComputer =
        senderID

    if message.success then
        refreshStatus.successCount =
            refreshStatus.successCount
            + 1

        refreshStatus.lastMessage =
            "Computer "
            .. senderID
            .. " updated"
    else
        refreshStatus.failureCount =
            refreshStatus.failureCount
            + 1

        refreshStatus.lastMessage =
            "Computer "
            .. senderID
            .. " FAILED"
    end

    screenDirty =
        true
end

-- =========================================================
-- AGGREGATE CARDS
-- =========================================================

local function rebuildCards()
    local now =
        os.epoch(
            "utc"
        )

    local combined = {}

    for _,
        source
        in pairs(
            storageSources
        ) do

        for itemID,
            data
            in pairs(
                source
            ) do

            local age =
                now
                - (
                    data.lastUpdate
                    or 0
                )

            if age
                > sourceRemoveSeconds
                    * 1000 then

                source[
                    itemID
                ] =
                    nil

            else
                local card =
                    combined[
                        itemID
                    ]

                if not card then
                    card = {
                        itemID =
                            itemID,

                        name =
                            data.displayName
                            or itemID,

                        amount =
                            0,

                        targetAmount =
                            0,

                        found =
                            true,

                        online =
                            false,

                        error =
                            nil,

                        sourceCount =
                            0,

                        onlineSources =
                            0,

                        machineRunning =
                            false,

                        x1 = 0,
                        y1 = 0,
                        x2 = 0,
                        y2 = 0,

                        borderPoints = {}
                    }

                    combined[
                        itemID
                    ] =
                        card
                end

                card.amount =
                    card.amount
                    + (
                        tonumber(
                            data.amount
                        ) or 0
                    )

                if tonumber(
                    data.targetAmount
                )
                    and tonumber(
                        data.targetAmount
                    ) > 0 then

                    card.targetAmount =
                        tonumber(
                            data.targetAmount
                        )
                end

                if data.displayName
                    and data.displayName
                        ~= "" then

                    card.name =
                        data.displayName
                end

                card.sourceCount =
                    card.sourceCount
                    + 1

                if age
                        <= sourceOfflineSeconds
                            * 1000
                    and data.online then

                    card.online =
                        true

                    card.onlineSources =
                        card.onlineSources
                        + 1
                end

                if not data.found then
                    card.found =
                        false
                end

                if data.error
                    and data.error
                        ~= "" then

                    card.error =
                        data.error
                end
            end
        end
    end

    -- =====================================================
    -- MACHINE STATES
    -- =====================================================

    for itemID,
        machine
        in pairs(
            machineStates
        ) do

        local age =
            now
            - (
                machine.lastUpdate
                or 0
            )

        if age
            > sourceRemoveSeconds
                * 1000 then

            machineStates[
                itemID
            ] =
                nil

        elseif combined[
            itemID
        ] then

            combined[
                itemID
            ].machineRunning =
                machine.running
                == true
        end
    end

    cards =
        combined

    cardOrder = {}

    for itemID
        in pairs(
            cards
        ) do

        cardOrder[
            #cardOrder + 1
        ] =
            itemID
    end

    table.sort(
        cardOrder,
        function(a, b)
            return string.lower(
                cards[a].name
                or a
            )
                < string.lower(
                    cards[b].name
                    or b
                )
        end
    )
end

-- =========================================================
-- PERCENT
-- =========================================================

local function calculatePercentage(
    card
)
    local amount =
        tonumber(
            card.amount
        )

    local target =
        tonumber(
            card.targetAmount
        )

    if not amount
        or not target
        or target <= 0 then

        return nil
    end

    local percentage =
        (
            amount
            / target
        ) * 100

    if percentage < 0 then
        percentage = 0
    end

    if percentage > 100 then
        percentage = 100
    end

    return percentage
end

-- =========================================================
-- ERROR
-- =========================================================

local function hasError(
    card
)
    if not card.online then
        return true
    end

    if card.error
        and card.error
            ~= "" then

        return true
    end

    if not card.found then
        return true
    end

    if not card.targetAmount
        or tonumber(
            card.targetAmount
        ) <= 0 then

        return true
    end

    return false
end

local function getErrorText(
    card
)
    if not card.online then
        return "DISCONNECTED"
    end

    if card.error
        and card.error
            ~= "" then

        return string.upper(
            tostring(
                card.error
            )
        )
    end

    if not card.found then
        return "STORAGE NOT FOUND"
    end

    if not card.targetAmount
        or tonumber(
            card.targetAmount
        ) <= 0 then

        return "NO TARGET"
    end

    return "ERROR"
end

-- =========================================================
-- COLORS
-- =========================================================

local function getBorderColor(
    card
)
    if hasError(
        card
    ) then

        if flashState then
            return theme.errorRed
        else
            return theme.errorOrange
        end
    end

    local percentage =
        calculatePercentage(
            card
        )

    if not percentage then
        if flashState then
            return theme.errorRed
        else
            return theme.errorOrange
        end
    end

    if percentage < 25 then
        if flashState then
            return theme.criticalRed
        else
            return theme.criticalBlack
        end
    end

    if percentage < 50 then
        return theme.low
    end

    if percentage < 75 then
        return theme.warning
    end

    if percentage >= 100 then
        return theme.full
    end

    return theme.good
end

local function getProgressColor(
    card
)
    local percentage =
        calculatePercentage(
            card
        )

    if not percentage
        or percentage < 50 then

        return theme.progressLow
    end

    if percentage < 75 then
        return theme.progressWarning
    end

    if percentage >= 100 then
        return theme.progressFull
    end

    return theme.progressGood
end

-- =========================================================
-- LAYOUT
-- =========================================================

local function calculateLayout()
    local width,
        height =
        monitor.getSize()

    local columns = 5
    local rows = 8

    local cardHeight = 6

    local horizontalGap = 1
    local verticalGap = 1

    local topY = 7
    local bottomY =
        height - 2

    local availableWidth =
        width - 2

    local availableHeight =
        bottomY
        - topY
        + 1

    local cardWidth =
        math.floor(
            (
                availableWidth
                - horizontalGap
                    * (
                        columns - 1
                    )
            )
            / columns
        )

    if cardWidth < 10 then
        error(
            "Monitor too narrow"
        )
    end

    local totalGridWidth =
        columns
        * cardWidth
        + horizontalGap
            * (
                columns - 1
            )

    local totalGridHeight =
        rows
        * cardHeight
        + verticalGap
            * (
                rows - 1
            )

    if totalGridHeight
        > availableHeight then

        error(
            "Monitor too short"
        )
    end

    local startX =
        math.floor(
            (
                width
                - totalGridWidth
            )
            / 2
        ) + 1

    local startY =
        topY
        + math.floor(
            (
                availableHeight
                - totalGridHeight
            )
            / 2
        )

    layoutSlots = {}

    for index = 1,
        maxStorages do

        local column =
            (
                index - 1
            )
            % columns

        local row =
            math.floor(
                (
                    index - 1
                )
                / columns
            )

        local x1 =
            startX
            + column
                * (
                    cardWidth
                    + horizontalGap
                )

        local y1 =
            startY
            + row
                * (
                    cardHeight
                    + verticalGap
                )

        local x2 =
            x1
            + cardWidth
            - 1

        local y2 =
            y1
            + cardHeight
            - 1

        layoutSlots[
            index
        ] = {
            x1 = x1,
            y1 = y1,
            x2 = x2,
            y2 = y2,

            borderPoints =
                getBorderPoints(
                    x1,
                    y1,
                    x2,
                    y2
                )
        }
    end

    -- =====================================================
    -- HEADER BUTTONS
    -- =====================================================

    local rebootWidth = 14
    local refreshWidth = 24

    rebootButton.x2 =
        width - 2

    rebootButton.x1 =
        rebootButton.x2
        - rebootWidth
        + 1

    rebootButton.y1 = 2
    rebootButton.y2 = 4

    refreshButton.x2 =
        rebootButton.x1
        - 2

    refreshButton.x1 =
        refreshButton.x2
        - refreshWidth
        + 1

    refreshButton.y1 = 2
    refreshButton.y2 = 4
end

-- =========================================================
-- HEADER BUTTONS
-- =========================================================

local function drawRebootButton(
    color
)
    fill(
        rebootButton.x1,
        rebootButton.y1,
        rebootButton.x2,
        rebootButton.y2,
        color
    )

    centerInside(
        rebootButton.x1,
        rebootButton.x2,
        rebootButton.y1 + 1,
        "REBOOT",
        colors.white,
        color
    )
end

local function drawRefreshButton(
    color
)
    fill(
        refreshButton.x1,
        refreshButton.y1,
        refreshButton.x2,
        refreshButton.y2,
        color
    )

    centerInside(
        refreshButton.x1,
        refreshButton.x2,
        refreshButton.y1 + 1,
        "REFRESH TARGETS",
        colors.white,
        color
    )
end

local function drawHeader()
    local width =
        monitor.getSize()

    fill(
        1,
        1,
        width,
        5,
        theme.header
    )

    writeAt(
        3,
        2,
        "STORAGE MANAGEMENT",
        theme.headerText,
        theme.header
    )

    local subtitle =
        "TARGET BASED RESOURCE STORAGE"

    if refreshStatus.active then
        local age =
            os.epoch("utc")
            - refreshStatus.started

        if age
            <= refreshMessageSeconds
                * 1000 then

            subtitle =
                "TARGET REFRESH: "
                .. refreshStatus.successCount
                .. " OK / "
                .. refreshStatus.failureCount
                .. " FAILED"
        else
            refreshStatus.active =
                false
        end
    end

    writeAt(
        3,
        3,
        shortenText(
            subtitle,
            refreshButton.x1
            - 6
        ),
        theme.headerSubtext,
        theme.header
    )

    drawRefreshButton(
        theme.refreshButton
    )

    drawRebootButton(
        theme.rebootButton
    )

    fill(
        1,
        6,
        width,
        6,
        theme.accent
    )
end

-- =========================================================
-- PROGRESS BAR
-- =========================================================

local function drawCenteredBarText(
    x1,
    x2,
    y,
    text,
    filledUntil,
    filledColor
)
    local width =
        x2 - x1 + 1

    text =
        shortenText(
            text,
            width
        )

    local textX =
        x1
        + math.floor(
            (
                width
                - #text
            )
            / 2
        )

    for index = 1,
        #text do

        local x =
            textX
            + index
            - 1

        local background =
            theme.progressBackground

        if filledUntil
            and x <= filledUntil then

            background =
                filledColor
        end

        writeAt(
            x,
            y,
            string.sub(
                text,
                index,
                index
            ),
            theme.amountText,
            background
        )
    end
end

local function drawProgressBar(
    card
)
    local y =
        card.y1 + 3

    local x1 =
        card.x1 + 2

    local x2 =
        card.x2 - 2

    local width =
        x2 - x1 + 1

    fill(
        x1,
        y,
        x2,
        y,
        theme.progressBackground
    )

    if hasError(
        card
    ) then

        drawCenteredBarText(
            x1,
            x2,
            y,
            getErrorText(
                card
            ),
            nil,
            nil
        )

        return
    end

    local percentage =
        calculatePercentage(
            card
        )

    local filledWidth =
        math.floor(
            width
            * percentage
            / 100
        )

    if percentage > 0
        and filledWidth < 1 then

        filledWidth = 1
    end

    if filledWidth > width then
        filledWidth = width
    end

    local progressColor =
        getProgressColor(
            card
        )

    local filledUntil =
        nil

    if filledWidth > 0 then
        filledUntil =
            x1
            + filledWidth
            - 1

        fill(
            x1,
            y,
            filledUntil,
            y,
            progressColor
        )
    end

    local text =
        commaNumber(
            card.amount
        )
        .. " / "
        .. commaNumber(
            card.targetAmount
        )

    drawCenteredBarText(
        x1,
        x2,
        y,
        text,
        filledUntil,
        progressColor
    )
end

-- =========================================================
-- MACHINE CHASE
-- =========================================================

local function drawMachineChase(
    card
)
    if not card.machineRunning then
        return
    end

    local points =
        card.borderPoints

    if not points
        or #points == 0 then

        return
    end

    local startIndex =
        (
            chaseFrame
            % #points
        ) + 1

    for offset = 0,
        chaseLength - 1 do

        local pointIndex =
            (
                startIndex
                + offset
                - 1
            )
            % #points
            + 1

        local point =
            points[
                pointIndex
            ]

        drawPixel(
            point.x,
            point.y,
            theme.machineChase
        )
    end
end

local function drawCardBorder(
    card
)
    drawBorder(
        card.x1,
        card.y1,
        card.x2,
        card.y2,
        getBorderColor(
            card
        )
    )

    drawMachineChase(
        card
    )
end

-- =========================================================
-- CARDS
-- =========================================================

local function drawPlaceholder(
    slot,
    index
)
    drawBorder(
        slot.x1,
        slot.y1,
        slot.x2,
        slot.y2,
        theme.emptyBorder
    )

    fill(
        slot.x1 + 1,
        slot.y1 + 1,
        slot.x2 - 1,
        slot.y2 - 1,
        theme.emptyCard
    )

    centerInside(
        slot.x1 + 1,
        slot.x2 - 1,
        slot.y1 + 2,
        "AVAILABLE "
            .. index,
        theme.placeholderText,
        theme.emptyCard
    )
end

local function drawCard(
    card
)
    drawCardBorder(
        card
    )

    fill(
        card.x1 + 1,
        card.y1 + 1,
        card.x2 - 1,
        card.y2 - 1,
        theme.card
    )

    centerInside(
        card.x1 + 2,
        card.x2 - 2,
        card.y1 + 2,
        string.upper(
            card.name
            or "STORAGE"
        ),
        theme.title,
        theme.card
    )

    drawProgressBar(
        card
    )

    drawMachineChase(
        card
    )
end

-- =========================================================
-- COUNTS
-- =========================================================

local function countOnline()
    local count = 0

    for _,
        itemID
        in ipairs(
            cardOrder
        ) do

        if cards[itemID]
            and cards[itemID]
                .online then

            count =
                count + 1
        end
    end

    return count
end

local function countErrors()
    local count = 0

    for _,
        itemID
        in ipairs(
            cardOrder
        ) do

        if cards[itemID]
            and hasError(
                cards[itemID]
            ) then

            count =
                count + 1
        end
    end

    return count
end

local function countCritical()
    local count = 0

    for _,
        itemID
        in ipairs(
            cardOrder
        ) do

        local card =
            cards[itemID]

        if card
            and not hasError(
                card
            ) then

            local percentage =
                calculatePercentage(
                    card
                )

            if percentage
                and percentage < 25 then

                count =
                    count + 1
            end
        end
    end

    return count
end

local function countRunning()
    local count = 0

    for _,
        itemID
        in ipairs(
            cardOrder
        ) do

        if cards[itemID]
            and cards[itemID]
                .machineRunning then

            count =
                count + 1
        end
    end

    return count
end

-- =========================================================
-- FOOTER
-- =========================================================

local function drawFooter()
    local width,
        height =
        monitor.getSize()

    fill(
        1,
        height - 1,
        width,
        height,
        theme.footer
    )

    local text =
        "ONLINE "
        .. countOnline()
        .. "/"
        .. #cardOrder
        .. "  ERRORS "
        .. countErrors()
        .. "  CRITICAL "
        .. countCritical()
        .. "  RUNNING "
        .. countRunning()

    writeAt(
        2,
        height,
        shortenText(
            text,
            width - 2
        ),
        theme.footerText,
        theme.footer
    )
end

-- =========================================================
-- FULL DRAW
-- =========================================================

local function drawScreen()
    rebuildCards()

    local width,
        height =
        monitor.getSize()

    fill(
        1,
        1,
        width,
        height,
        theme.background
    )

    drawHeader()

    for index = 1,
        maxStorages do

        local slot =
            layoutSlots[
                index
            ]

        local itemID =
            cardOrder[
                index
            ]

        if itemID then
            local card =
                cards[
                    itemID
                ]

            card.x1 =
                slot.x1

            card.y1 =
                slot.y1

            card.x2 =
                slot.x2

            card.y2 =
                slot.y2

            card.borderPoints =
                slot.borderPoints

            drawCard(
                card
            )
        else
            drawPlaceholder(
                slot,
                index
            )
        end
    end

    drawFooter()
end

-- =========================================================
-- DISCOVERY
-- =========================================================

local function requestDiscovery()
    rednet.broadcast(
        {
            command =
                "discover"
        },
        storageControlProtocol
    )

    rednet.broadcast(
        {
            command =
                "discover"
        },
        machineControlProtocol
    )
end

-- =========================================================
-- FORCE TARGET REFRESH
-- =========================================================

local function forceTargetRefresh()
    refreshStatus.active =
        true

    refreshStatus.started =
        os.epoch(
            "utc"
        )

    refreshStatus.successCount =
        0

    refreshStatus.failureCount =
        0

    refreshStatus.lastMessage =
        "Sending refresh..."

    refreshStatus.lastComputer =
        nil

    drawRefreshButton(
        theme.refreshPressed
    )

    rednet.broadcast(
        {
            command =
                "force_targets_refresh",

            senderID =
                os.getComputerID(),

            timestamp =
                os.epoch(
                    "utc"
                )
        },
        configControlProtocol
    )

    screenDirty =
        true
end

-- =========================================================
-- REBOOT
-- =========================================================

local function rebootComputer()
    drawRebootButton(
        theme.rebootPressed
    )

    sleep(0.15)

    os.reboot()
end

-- =========================================================
-- RENDER LOOP
-- =========================================================

local function renderLoop()
    while true do
        if screenDirty then
            screenDirty =
                false

            drawScreen()
        end

        sleep(
            renderInterval
        )
    end
end

-- =========================================================
-- ANIMATION LOOP
-- =========================================================

local function animationLoop()
    while true do
        chaseFrame =
            chaseFrame + 1

        flashElapsed =
            flashElapsed
            + animationSpeed

        local flashChanged =
            false

        if flashElapsed
            >= flashInterval then

            flashElapsed =
                flashElapsed
                - flashInterval

            flashState =
                not flashState

            flashChanged =
                true
        end

        for index,
            itemID
            in ipairs(
                cardOrder
            ) do

            if index <= maxStorages then
                local card =
                    cards[itemID]

                local slot =
                    layoutSlots[index]

                if card
                    and slot then

                    card.x1 =
                        slot.x1

                    card.y1 =
                        slot.y1

                    card.x2 =
                        slot.x2

                    card.y2 =
                        slot.y2

                    card.borderPoints =
                        slot.borderPoints

                    if card.machineRunning then
                        drawCardBorder(
                            card
                        )

                    elseif flashChanged then
                        local percentage =
                            calculatePercentage(
                                card
                            )

                        if hasError(
                            card
                        )
                            or (
                                percentage
                                and percentage
                                    < 25
                            ) then

                            drawCardBorder(
                                card
                            )
                        end
                    end
                end
            end
        end

        sleep(
            animationSpeed
        )
    end
end

-- =========================================================
-- EVENT LOOP
-- =========================================================

local function eventLoop()
    local discoveryTimer =
        os.startTimer(
            discoveryInterval
        )

    local staleTimer =
        os.startTimer(2)

    while true do
        local event,
            a,
            b,
            c =
            os.pullEvent()

        -- =================================================
        -- NETWORK
        -- =================================================

        if event
            == "rednet_message" then

            local senderID =
                a

            local message =
                b

            local protocol =
                c

            if protocol
                    == storageStatusProtocol
                and type(message)
                    == "table" then

                if message.messageType
                    == "storage_manifest" then

                    processStorageManifest(
                        senderID,
                        message
                    )

                elseif message.messageType
                    == "inventory_update" then

                    processInventoryUpdate(
                        senderID,
                        message
                    )
                end

            elseif protocol
                    == machineStatusProtocol
                and type(message)
                    == "table"
                and message.messageType
                    == "resource_machine_status" then

                processMachineStatus(
                    senderID,
                    message
                )

            elseif protocol
                    == configStatusProtocol
                and type(message)
                    == "table" then

                processConfigStatus(
                    senderID,
                    message
                )
            end

        -- =================================================
        -- TOUCH
        -- =================================================

        elseif event
                == "monitor_touch"
            and a
                == monitorName then

            local x = b
            local y = c

            -- REBOOT
            if isInside(
                x,
                y,
                rebootButton.x1,
                rebootButton.y1,
                rebootButton.x2,
                rebootButton.y2
            ) then

                rebootComputer()

            -- REFRESH TARGETS
            elseif isInside(
                x,
                y,
                refreshButton.x1,
                refreshButton.y1,
                refreshButton.x2,
                refreshButton.y2
            ) then

                forceTargetRefresh()
            end

        -- =================================================
        -- DISCOVERY
        -- =================================================

        elseif event
                == "timer"
            and a
                == discoveryTimer then

            requestDiscovery()

            discoveryTimer =
                os.startTimer(
                    discoveryInterval
                )

        -- =================================================
        -- STALE
        -- =================================================

        elseif event
                == "timer"
            and a
                == staleTimer then

            screenDirty =
                true

            staleTimer =
                os.startTimer(2)

        -- =================================================
        -- RESIZE
        -- =================================================

        elseif event
                == "monitor_resize"
            and a
                == monitorName then

            monitor.setTextScale(
                0.5
            )

            calculateLayout()

            screenDirty =
                true
        end
    end
end

-- =========================================================
-- START
-- =========================================================

calculateLayout()

drawScreen()

screenDirty =
    false

requestDiscovery()

parallel.waitForAll(
    eventLoop,
    renderLoop,
    animationLoop
)