term.clear()
term.setCursorPos(1, 1)

local sides = {
    "top",
    "bottom",
    "left",
    "right",
    "front",
    "back"
}

print("ADJACENT PERIPHERAL SCAN")
print("========================")
print()

for _, side in ipairs(sides) do

    print("SIDE: " .. string.upper(side))

    if peripheral.isPresent(side) then

        local pType = peripheral.getType(side)

        print("Peripheral: YES")
        print("Type: " .. tostring(pType))
        print("Methods:")

        local methods = peripheral.getMethods(side)

        if methods then
            for _, method in ipairs(methods) do
                print("  " .. method)
            end
        end

    else

        print("Peripheral: NO")

    end

    print("------------------------")
end