local side = "right" -- Tank side

local tank = peripheral.wrap(side)

if not tank then
    error("No peripheral on " .. side)
end

print("Tank Type:")
print(peripheral.getType(side))
print()

print("Inventory Size: " .. tank.size())
print()

for slot = 1, tank.size() do
    print("==========")
    print("Slot " .. slot)

    local item = tank.getItemDetail(slot)

    if item then
        print("Item: " .. item.name)
        print("Display: " .. (item.displayName or ""))
        print("Count: " .. item.count)
        print("NBT: " .. tostring(item.nbt))
    else
        print("EMPTY")
    end

    print()
end