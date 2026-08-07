-- =========================================================
-- TIME WAND CONTROLLER
--
-- EMPTY wand:
-- Advanced Clicker -> Tank slot 2
--
-- FULL wand:
-- Tank -> Advanced Clicker slot 1
--
-- =========================================================

local clickerSide =
    "left"

local tankSide =
    "right"

local clickerWandSlot =
    0

local tankWandSlot =
    3

local wandID =
    "justdirethings:time_wand"

-- =========================================================
-- NBT HASHES
-- =========================================================

local emptyHash =
    "77597cdd30145dd6e7f0c1d005ff6dc8"

local fullHash =
    "866815d750ffc888754359b0ed011353"

-- =========================================================
-- TIMING
-- =========================================================

local checkInterval =
    0.25

-- =========================================================
-- PERIPHERALS
-- =========================================================

if not peripheral.isPresent(
    clickerSide
) then

    error(
        "Advanced Clicker not found on "
        .. clickerSide
    )
end

if not peripheral.isPresent(
    tankSide
) then

    error(
        "Tank not found on "
        .. tankSide
    )
end

local clicker =
    peripheral.wrap(
        clickerSide
    )

local tank =
    peripheral.wrap(
        tankSide
    )

local clickerName =
    peripheral.getName(
        clicker
    )

local tankName =
    peripheral.getName(
        tank
    )

if type(clicker.list)
    ~= "function" then

    error(
        "Clicker does not expose item inventory"
    )
end

if type(tank.list)
    ~= "function" then

    error(
        "Tank does not expose item inventory"
    )
end

if type(clicker.getItemDetail)
    ~= "function" then

    error(
        "Clicker does not support getItemDetail()"
    )
end

if type(tank.getItemDetail)
    ~= "function" then

    error(
        "Tank does not support getItemDetail()"
    )
end

if type(clicker.pushItems)
    ~= "function" then

    error(
        "Clicker does not support pushItems()"
    )
end

if type(tank.pushItems)
    ~= "function" then

    error(
        "Tank does not support pushItems()"
    )
end

-- =========================================================
-- FIND TIME WAND
-- =========================================================

local function findWand(
    inventory
)
    local items =
        inventory.list()

    for slot,
        item
        in pairs(items) do

        if item.name
            == wandID then

            local detail =
                inventory.getItemDetail(
                    slot
                )

            return slot,
                detail
        end
    end

    return nil,
        nil
end

-- =========================================================
-- MOVE TIME WAND
-- =========================================================

local function moveWand(
    source,
    destinationName,
    sourceSlot,
    destinationSlot
)
    local moved =
        source.pushItems(
            destinationName,
            sourceSlot,
            1,
            destinationSlot
        )

    return moved == 1,
        moved
end

-- =========================================================
-- DISPLAY
-- =========================================================

local function drawScreen(
    location,
    status,
    hash
)
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
        "TIME WAND CONTROLLER"
    )

    print(
        "===================="
    )

    print("")

    print(
        "Clicker: "
        .. clickerSide
        .. " slot "
        .. clickerWandSlot
    )

    print(
        "Tank:    "
        .. tankSide
        .. " slot "
        .. tankWandSlot
    )

    print("")

    print(
        "Wand: "
        .. tostring(
            location
        )
    )

    print(
        "Status: "
        .. tostring(
            status
        )
    )

    if hash then
        print("")
        print("NBT:")

        print(
            tostring(
                hash
            )
        )
    end
end

-- =========================================================
-- MAIN LOOP
-- =========================================================

while true do

    local clickerSlot,
        clickerDetail =
        findWand(
            clicker
        )

    local tankSlot,
        tankDetail =
        findWand(
            tank
        )

    -- =====================================================
    -- WAND IS IN CLICKER
    -- =====================================================

    if clickerSlot
        and clickerDetail then

        local hash =
            clickerDetail.nbt

        -- =================================================
        -- EMPTY
        -- =================================================

        if hash
            == emptyHash then

            drawScreen(
                "CLICKER",
                "EMPTY - MOVING TO TANK",
                hash
            )

            local success,
                moved =
                moveWand(
                    clicker,
                    tankName,
                    clickerSlot,
                    tankWandSlot
                )

            if success then

                drawScreen(
                    "TANK",
                    "MOVED - CHARGING",
                    hash
                )

                sleep(
                    0.5
                )

            else

                drawScreen(
                    "CLICKER",
                    "MOVE TO TANK FAILED: "
                    .. tostring(
                        moved
                    ),
                    hash
                )
            end

        -- =================================================
        -- FULL
        -- =================================================

        elseif hash
            == fullHash then

            drawScreen(
                "CLICKER",
                "FULL - IN USE",
                hash
            )

        -- =================================================
        -- PARTIALLY CHARGED
        -- =================================================

        else

            drawScreen(
                "CLICKER",
                "IN USE",
                hash
            )
        end

    -- =====================================================
    -- WAND IS IN TANK
    -- =====================================================

    elseif tankSlot
        and tankDetail then

        local hash =
            tankDetail.nbt

        -- =================================================
        -- FULL
        -- =================================================

        if hash
            == fullHash then

            drawScreen(
                "TANK",
                "FULL - MOVING TO CLICKER",
                hash
            )

            local success,
                moved =
                moveWand(
                    tank,
                    clickerName,
                    tankSlot,
                    clickerWandSlot
                )

            if success then

                drawScreen(
                    "CLICKER",
                    "MOVED - READY",
                    hash
                )

                sleep(
                    0.5
                )

            else

                drawScreen(
                    "TANK",
                    "MOVE TO CLICKER FAILED: "
                    .. tostring(
                        moved
                    ),
                    hash
                )
            end

        -- =================================================
        -- EMPTY
        -- =================================================

        elseif hash
            == emptyHash then

            drawScreen(
                "TANK",
                "CHARGING - EMPTY",
                hash
            )

        -- =================================================
        -- CHARGING
        -- =================================================

        else

            drawScreen(
                "TANK",
                "CHARGING",
                hash
            )
        end

    -- =====================================================
    -- WAND NOT FOUND
    -- =====================================================

    else

        drawScreen(
            "NOT FOUND",
            "WAITING FOR TIME WAND",
            nil
        )
    end

    sleep(
        checkInterval
    )
end