local tank = peripheral.wrap("right")
local clickerName = peripheral.getName(peripheral.wrap("left"))

print("Tank name: " .. peripheral.getName(tank))
print("Clicker: " .. clickerName)

local moved = tank.pushItems(clickerName, 3, 1, 1)

print("Moved = " .. tostring(moved))