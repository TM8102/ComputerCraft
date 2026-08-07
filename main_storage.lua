local monitorSide = "right"
local modemSide = "back"

local storageControlProtocol =
    "inventory_control"

local storageStatusProtocol =
    "inventory_status"

local machineControlProtocol =
    "resource_machine_control"

local machineStatusProtocol =
    "resource_machine_status"

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

-- Main screen redraw frequency.
local renderInterval = 0.20

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
-- DIRTY FLAGS
--
-- Network packets DO NOT redraw the screen directly.
-- They only update data and set screenDirty.
-- =========================================================

local screenDirty = true
local footerDirty = true

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

    -- =====================================================
    -- STORAGE COLORS
    -- =====================================================

    -- >= 100%
    full =
        colors.lime,

    -- 75 - 99.99%
    good =
        colors.lightBlue,

    -- 50 - 74.99%
    warning =
        colors.orange,

    -- 25 - 49.99%
    low =
        colors.red,

    -- <25%
    criticalRed =
        colors.red,

    criticalBlack =
        colors.black,

    -- Offline / errors
    errorRed =
        colors.red,

    errorOrange =
        colors.orange,

    -- Machine running chase
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

    -- Empty card
    emptyBorder =
        colors.gray,

    placeholderText =
        colors.gray,

    -- Reboot
    rebootButton =
        colors.blue,

    rebootPressed =
        colors.lightBlue,

    -- Footer
    footer =
        colors.gray,

    footerText =
        colors.white
}

-- =========================================================
-- DATA
--
-- Multiple computers can report the SAME item.
--
-- Example:
--
-- Functional Storage computer:
--   Ether Gas = 100000
--
-- Remote Drawer computer:
--   Ether Gas = 50000
--
-- Main displays:
--   Ether Gas = 150000
--
-- =========================================================

local storageSources = {}

local machineStates = {}

local cards = {}

local cardOrder = {}

local layoutSlots = {}

local rebootButton = {}

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

    -- Top
    for x = x1, x2 do

        points[
            #points + 1
        ] = {
            x = x,
            y = y1
        }
    end

    -- Right
    for y = y1 + 1,
        y2 - 1 do

        points[
            #points + 1
        ] = {
            x = x2,
            y = y
        }
    end

    -- Bottom
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

    -- Left
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
-- NUMBER FORMATTING
-- =========================================================

local function commaNumber(
    number
)

    number =
        math.floor(
            tonumber(
                number
            )
            or 0
        )

    local text =
        tostring(
            number
        )

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
-- PROCESS MANIFEST
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
                == "string"
            and itemID
                ~= "" then

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
        screenDirty = true
    end
end

-- =========================================================
-- PROCESS INVENTORY UPDATE
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

        storageKey =
            message.storageKey
            or itemID,

        displayName =
            message.displayName
            or itemID,

        amount =
            tonumber(
                message.amount
            )
            or 0,

        targetAmount =
            tonumber(
                message.targetAmount
                or message.target
            )
            or 0,

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

    screenDirty = true
end

-- =========================================================
-- MACHINE STATUS
--
-- Actual machine computer broadcasts this.
-- Main uses it ONLY for visual machine-running chase.
-- =========================================================

local function processMachineStatus(
    senderID,
    message
)

    local itemID =
        message.itemID

    if type(itemID)
        ~= "string" then

        return
    end

    machineStates[
        itemID
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

    screenDirty = true
end

-- =========================================================
-- REBUILD AGGREGATED CARDS
--
-- IMPORTANT:
--
-- This is NOT called from the animation loop anymore.
--
-- Only the render loop calls it when screenDirty = true.
-- =========================================================

local function rebuildCards()

    local now =
        os.epoch(
            "utc"
        )

    local combined = {}

    -- =====================================================
    -- STORAGE
    -- =====================================================

    for computerID,
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

            -- Completely remove stale source report.
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
                        )
                        or 0
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
-- PERCENTAGE
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
            "Monitor too narrow for 5 columns"
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
            "Monitor too short for 8 rows"
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

    local rebootWidth = 18

    rebootButton.x1 =
        width
        - rebootWidth
        - 1

    rebootButton.x2 =
        width - 2

    rebootButton.y1 = 2
    rebootButton.y2 = 4
end

-- =========================================================
-- HEADER
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

    writeAt(
        3,
        3,
        "TARGET BASED RESOURCE STORAGE",
        theme.headerSubtext,
        theme.header
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
-- PROGRESS BAR TEXT
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

-- =========================================================
-- PROGRESS BAR
-- =========================================================

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

    if width <= 0 then
        return
    end

    fill(
        x1,
        y,
        x2,
        y,
        theme.progressBackground
    )

    -- =====================================================
    -- ERROR
    --
    -- Show empty bar with centered error message.
    -- =====================================================

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

    if not percentage then

        drawCenteredBarText(
            x1,
            x2,
            y,
            "ERROR",
            nil,
            nil
        )

        return
    end

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

    local pointCount =
        #points

    local startIndex =
        (
            chaseFrame
            % pointCount
        ) + 1

    for offset = 0,
        chaseLength - 1 do

        local pointIndex =
            (
                startIndex
                + offset
                - 1
            )
            % pointCount
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

-- =========================================================
-- DRAW BORDER ONLY
--
-- Used by animation loop.
--
-- Does NOT touch card interior.
-- =========================================================

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

    if card.machineRunning then

        drawMachineChase(
            card
        )
    end
end

-- =========================================================
-- PLACEHOLDER
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

-- =========================================================
-- DRAW CARD
-- =========================================================

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

    -- Redraw chase because filling card interior may touch
    -- corner/background pixels depending on card size.
    if card.machineRunning then

        drawMachineChase(
            card
        )
    end
end

-- =========================================================
-- FOOTER COUNTERS
-- =========================================================

local function countOnline()

    local count = 0

    for _,
        itemID
        in ipairs(
            cardOrder
        ) do

        local card =
            cards[
                itemID
            ]

        if card
            and card.online then

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

        local card =
            cards[
                itemID
            ]

        if card
            and hasError(
                card
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
            cards[
                itemID
            ]

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

        local card =
            cards[
                itemID
            ]

        if card
            and card
                .machineRunning then

            count =
                count + 1
        end
    end

    return count
end

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

    local modemText =
        "MODEM: "
        .. string.upper(
            modemSide
        )

    if width
        - #modemText
        > #text + 3 then

        writeAt(
            width
            - #modemText,
            height,
            modemText,
            theme.footerText,
            theme.footer
        )
    end
end

-- =========================================================
-- FULL SCREEN DRAW
--
-- ONLY renderLoop calls this during normal operation.
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
-- REQUEST DISCOVERY
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
-- REBOOT
-- =========================================================

local function rebootComputer()

    drawRebootButton(
        theme.rebootPressed
    )

    monitor.setBackgroundColor(
        colors.black
    )

    monitor.setTextColor(
        colors.white
    )

    monitor.clear()

    local width,
        height =
        monitor.getSize()

    centerInside(
        1,
        width,
        math.floor(
            height / 2
        ),
        "REBOOTING STORAGE SYSTEM...",
        colors.cyan,
        colors.black
    )

    os.reboot()
end

-- =========================================================
-- RENDER LOOP
--
-- THIS IS THE FLICKER FIX.
--
-- Incoming packets:
--     update tables
--     screenDirty = true
--
-- Renderer:
--     redraws ONCE after many packets
--
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
--
-- IMPORTANT:
--
-- NO rebuildCards()
-- NO drawScreen()
-- NO monitor.clear()
--
-- Only redraws borders that actually animate.
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

            if index
                <= maxStorages then

                local card =
                    cards[
                        itemID
                    ]

                local slot =
                    layoutSlots[
                        index
                    ]

                if card
                    and slot then

                    -- Keep geometry current.
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

                    -- =========================================
                    -- MACHINE RUNNING
                    --
                    -- Continuously animate.
                    -- =========================================

                    if card
                        .machineRunning then

                        drawCardBorder(
                            card
                        )

                    -- =========================================
                    -- FLASHING ERROR / CRITICAL
                    --
                    -- Only redraw when flash changes.
                    -- =========================================

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
        -- REDNET
        -- =================================================

        if event
            == "rednet_message" then

            local senderID =
                a

            local message =
                b

            local protocol =
                c

            -- =============================================
            -- STORAGE
            -- =============================================

            if protocol
                    == storageStatusProtocol
                and type(message)
                    == "table" then

                if message
                    .messageType
                    == "storage_manifest" then

                    processStorageManifest(
                        senderID,
                        message
                    )

                elseif message
                    .messageType
                    == "inventory_update" then

                    processInventoryUpdate(
                        senderID,
                        message
                    )
                end

            -- =============================================
            -- MACHINE STATUS
            -- =============================================

            elseif protocol
                    == machineStatusProtocol
                and type(message)
                    == "table"
                and message
                    .messageType
                    == "resource_machine_status" then

                processMachineStatus(
                    senderID,
                    message
                )
            end

        -- =================================================
        -- TOUCH
        --
        -- ONLY REBOOT IS CLICKABLE.
        -- =================================================

        elseif event
            == "monitor_touch"
            and a
                == monitorName then

            local x = b
            local y = c

            if isInside(
                x,
                y,
                rebootButton.x1,
                rebootButton.y1,
                rebootButton.x2,
                rebootButton.y2
            ) then

                rebootComputer()
            end

        -- =================================================
        -- DISCOVERY TIMER
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
        -- STALE DATA CHECK
        --
        -- Mark screen dirty every 2 seconds so offline
        -- state/removal can be recalculated.
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
        -- MONITOR RESIZE
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