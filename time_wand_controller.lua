-- =========================================================
-- TIME WAND CONTROLLER
--
-- EMPTY wand in Advanced Clicker slot 1
--      ↓
-- move to Tank charging slot 3
--      ↓
-- Tank charges wand
--      ↓
-- Tank automatically moves finished wand to slot 4
--      ↓
-- move wand from Tank slot 4
-- back to Advanced Clicker slot 1
--
-- =========================================================

local clickerSide =
    "left"

local tankSide =
    "right"

-- =========================================================
-- INVENTORY SLOTS
-- =========================================================

local clickerWandSlot =
    1

local tankChargeSlot =
    3

local tankOutputSlot =
    4

-- =========================================================
-- ITEM
-- =========================================================

local wandID =
    "justdirethings:time_wand"

-- Empty Time Wand fingerprint
local emptyHash =
    "77597cdd30145dd6e7f0c1d005ff6dc8"

-- =========================================================
-- TIMING
-- =========================================================

local checkInterval =
    0.25

local moveCooldown =
    0.5

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

-- =========================================================
-- VALIDATE INVENTORIES
-- =========================================================

local function requireMethod(
    object,
    method,
    label
)
    if type(
        object[method]
    ) ~= "function" then

        error(
            label
            .. " does not support "
            .. method
            .. "()"
        )
    end
end

requireMethod(
    clicker,
    "list",
    "Clicker"
)

requireMethod(
    clicker,
    "getItemDetail",
    "Clicker"
)

requireMethod(
    clicker,
    "pushItems",
    "Clicker"
)

requireMethod(
    tank,
    "list",
    "Tank"
)

requireMethod(
    tank,
    "getItemDetail",
    "Tank"
)

requireMethod(
    tank,
    "pushItems",
    "Tank"
)

-- =========================================================
-- HELPERS
-- =========================================================

local function getDetail(
    inventory,
    slot
)
    local ok,
        detail =
        pcall(
            inventory.getItemDetail,
            slot
        )

    if not ok then
        return nil
    end

    return detail
end

local function isWand(
    detail
)
    return detail
        and detail.name
            == wandID
end

local function moveItem(
    source,
    destinationName,
    sourceSlot,
    destinationSlot
)
    local ok,
        moved =
        pcall(
            source.pushItems,
            destinationName,
            sourceSlot,
            1,
            destinationSlot
        )

    if not ok then
        return false,
            tostring(
                moved
            )
    end

    return moved == 1,
        moved
end

-- =========================================================
-- DISPLAY
-- =========================================================

local function drawScreen(
    location,
    status,
    extra
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
        "Tank charge: "
        .. tankSide
        .. " slot "
        .. tankChargeSlot
    )

    print(
        "Tank output: "
        .. tankSide
        .. " slot "
        .. tankOutputSlot
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

    if extra then
        print("")
        print(
            tostring(
                extra
            )
        )
    end
end

-- =========================================================
-- MAIN LOOP
-- =========================================================

while true do

    local clickerDetail =
        getDetail(
            clicker,
            clickerWandSlot
        )

    local tankChargeDetail =
        getDetail(
            tank,
            tankChargeSlot
        )

    local tankOutputDetail =
        getDetail(
            tank,
            tankOutputSlot
        )

    -- =====================================================
    -- PRIORITY 1:
    -- FINISHED WAND IN TANK OUTPUT SLOT
    -- =====================================================

    if isWand(
        tankOutputDetail
    ) then

        drawScreen(
            "TANK OUTPUT",
            "FULL - MOVING TO CLICKER"
        )

        local success,
            result =
            moveItem(
                tank,
                clickerName,
                tankOutputSlot,
                clickerWandSlot
            )

        if success then

            drawScreen(
                "CLICKER",
                "FULL - READY"
            )

            sleep(
                moveCooldown
            )

        else

            drawScreen(
                "TANK OUTPUT",
                "MOVE TO CLICKER FAILED",
                "Moved: "
                    .. tostring(
                        result
                    )
            )
        end

    -- =====================================================
    -- PRIORITY 2:
    -- WAND IN CLICKER
    -- =====================================================

    elseif isWand(
        clickerDetail
    ) then

        local hash =
            clickerDetail.nbt

        if hash
            == emptyHash then

            drawScreen(
                "CLICKER",
                "EMPTY - MOVING TO TANK",
                "NBT: "
                    .. tostring(
                        hash
                    )
            )

            local success,
                result =
                moveItem(
                    clicker,
                    tankName,
                    clickerWandSlot,
                    tankChargeSlot
                )

            if success then

                drawScreen(
                    "TANK",
                    "CHARGING"
                )

                sleep(
                    moveCooldown
                )

            else

                drawScreen(
                    "CLICKER",
                    "MOVE TO TANK FAILED",
                    "Moved: "
                        .. tostring(
                            result
                        )
                )
            end

        else

            drawScreen(
                "CLICKER",
                "IN USE",
                "NBT: "
                    .. tostring(
                        hash
                    )
            )
        end

    -- =====================================================
    -- PRIORITY 3:
    -- WAND IS CURRENTLY CHARGING
    -- =====================================================

    elseif isWand(
        tankChargeDetail
    ) then

        drawScreen(
            "TANK CHARGE",
            "CHARGING",
            "Waiting for tank to move wand to slot "
                .. tankOutputSlot
        )

    -- =====================================================
    -- NO WAND FOUND
    -- =====================================================

    else

        drawScreen(
            "NOT FOUND",
            "WAITING FOR TIME WAND"
        )
    end

    sleep(
        checkInterval
    )
end