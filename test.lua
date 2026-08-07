local tank = peripheral.wrap("right")
local clicker = peripheral.getName(peripheral.wrap("left"))

print("Moving from tank slot 3 to clicker slot 1")

local moved = tank.pushItems(clicker, 3, 1, 1)

print("Moved:", moved)