-- =========================================================
-- TIME WAND AUTO CHARGER
-- =========================================================
--
-- EMPTY wand:
-- Advanced Clicker -> Mekanism Tank
--
-- FULL wand:
-- Mekanism Tank -> Advanced Clicker
--
-- =========================================================

local clickerSide = "left"
local tankSide = "right"

local wandID =
    "justdirethings:time_wand"

local emptyHash =
    "77597cd4301458d6e7f0e1b005ff6d68"

local fullHash =
    "866815d750ffc888754359b0ed011353"

local checkInterval = 0.25

-- =========================================================
-- PERIPHERALS
-- =========================================================

if not peripheral.isPresent(clickerSide) then
    error(
        "Advanced Clicker not found on "
        .. clickerSide
    )
end

if not peripheral.isPresent(tankSide) then
    error(
        "Mekanism Tank not found on "
        .. tankSide
    )
end

local clicker =
    peripheral.wrap(clickerSide)

local tank =
    peripheral.wrap(tankSide)

local clickerName =
    peripheral.getName(clicker)

local tankName =
    peripheral.getName(tank)

if type(clicker.list) ~= "function" then
    error(
        "Clicker does not expose inventory"
    )
end

if type(tank.list) ~= "function" then
    error(
        "Tank does not expose item inventory"
    )
end

if type(clicker.getItemDetail) ~= "function" then
    error(
        "Clicker does not support getItemDetail()"
    )
end

if type(tank.getItemDetail) ~= "function" then
    error(
        "Tank does not support getItemDetail()"
    )
end

-- =========================================================
-- FIND WAND
-- =========================================================

local function findWand(inv)
    local items =
        inv.list()

    for slot, item
        in pairs(items) do

        if item.name == wandID then

            local detail =
                inv.getItemDetail(
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
-- MOVE ITEM
-- =========================================================

local function moveWand(
    source,
    destinationName,
    slot
)
    if type(source.pushItems)
        ~= "function" then

        return false,
            "pushItems unavailable"
    end

    local moved =
        source.pushItems(
            destinationName,
            slot,
            1
        )

    return moved == 1,
        moved
end

-- =========================================================
-- DISPLAY
-- =========================================================

local function draw(
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
    )

    print(
        "Tank:    "
        .. tankSide
    )

    print("")

    print(
        "Wand: "
        .. tostring(location)
    )

    print(
        "Status: "
        .. tostring(status)
    )

    if hash then
        print("")
        print("NBT:")

        print(
            tostring(hash)
        )
    end
end

-- =========================================================
-- MAIN LOOP
-- =========================================================

while true do

    local clickerSlot,
        clickerDetail =
        findWand(clicker)

    local tankSlot,
        tankDetail =
        findWand(tank)

    -- =====================================================
    -- WAND IS IN CLICKER
    -- =====================================================

    if clickerSlot
        and clickerDetail then

        local hash =
            clickerDetail.nbt

        if hash == emptyHash then

            draw(
                "CLICKER",
                "EMPTY - MOVING TO TANK",
                hash
            )

            local success,
                result =
                moveWand(
                    clicker,
                    tankName,
                    clickerSlot
                )

            if not success then

                draw(
                    "CLICKER",
                    "MOVE TO TANK FAILED: "
                    .. tostring(result),
                    hash
                )
            end

        elseif hash == fullHash then

            draw(
                "CLICKER",
                "FULL - RUNNING",
                hash
            )

        else

            draw(
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

        if hash == fullHash then

            draw(
                "TANK",
                "FULL - MOVING TO CLICKER",
                hash
            )

            local success,
                result =
                moveWand(
                    tank,
                    clickerName,
                    tankSlot
                )

            if not success then

                draw(
                    "TANK",
                    "MOVE TO CLICKER FAILED: "
                    .. tostring(result),
                    hash
                )
            end

        elseif hash == emptyHash then

            draw(
                "TANK",
                "CHARGING - EMPTY",
                hash
            )

        else

            draw(
                "TANK",
                "CHARGING",
                hash
            )
        end

    -- =====================================================
    -- NO WAND
    -- =====================================================

    else

        draw(
            "UNKNOWN",
            "TIME WAND NOT FOUND",
            nil
        )
    end

    sleep(
        checkInterval
    )
end