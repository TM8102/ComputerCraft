local side = "left" -- Change if your clicker is on another side

if not peripheral.isPresent(side) then
    error("No peripheral on " .. side)
end

local clicker = peripheral.wrap(side)

if not clicker.list then
    error("This peripheral does not expose an inventory.")
end

term.clear()
term.setCursorPos(1,1)

print("CLICKER INVENTORY")
print("=================")
print()

print("Size: " .. clicker.size())
print()

for slot = 1, clicker.size() do
    local item = clicker.getItemDetail(slot)

    if item then
        print("Slot " .. slot)
        print("  Item: " .. item.name)
        print("  Count: " .. item.count)
        print("  Name: " .. (item.displayName or ""))
        print("  NBT: " .. tostring(item.nbt))
        print()
    else
        print("Slot " .. slot .. ": EMPTY")
    end
end