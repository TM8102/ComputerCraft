local source = peripheral.wrap("left")   -- Clicker
local dest = peripheral.getName(peripheral.wrap("right")) -- Tank

for slot = 1, 4 do
    print("Trying destination slot " .. slot)

    local moved = source.pushItems(dest, 1, 1, slot)

    print("Moved: " .. tostring(moved))

    sleep(2)
end