local side = "right"

term.clear()
term.setCursorPos(1, 1)

if not peripheral.isPresent(side) then
    error(
        "No peripheral on "
        .. side
    )
end

local p =
    peripheral.wrap(side)

print(
    "TYPE: "
    .. tostring(
        peripheral.getType(side)
    )
)

print("")

if type(p.list)
    ~= "function" then

    print(
        "This peripheral does NOT expose list()"
    )

    return
end

local items =
    p.list()

print(
    "VISIBLE SLOTS:"
)

local highestSlot = 0

for slot, item
    in pairs(items) do

    if slot > highestSlot then
        highestSlot = slot
    end

    print(
        "Slot "
        .. tostring(slot)
        .. ": "
        .. tostring(item.name)
        .. " x"
        .. tostring(item.count)
    )
end

print("")
print(
    "Testing slot count..."
)

-- Try getItemLimit on sequential slots if available
if type(p.getItemLimit)
    == "function" then

    for slot = 1, 20 do
        local ok,
            result =
            pcall(function()
                return p.getItemLimit(slot)
            end)

        if ok then
            print(
                "Slot "
                .. slot
                .. " limit = "
                .. tostring(result)
            )
        else
            print(
                "Slot "
                .. slot
                .. " INVALID"
            )

            break
        end
    end
else
    print(
        "getItemLimit() not available"
    )
end

print("")
print(
    "METHODS:"
)

local methods =
    peripheral.getMethods(side)

table.sort(methods)

for _, method
    in ipairs(methods) do

    print(method)
end