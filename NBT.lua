local side = "left"

local chest = peripheral.wrap(side)

if not chest then
    error("No inventory found on " .. side)
end

while true do
    term.clear()
    term.setCursorPos(1,1)

    print("TIME WAND NBT WATCHER")
    print("=====================")
    print()

    local found = false

    for slot = 1, chest.size() do
        local item = chest.getItemDetail(slot)

        if item and item.name == "justdirethings:time_wand" then
            found = true

            print("Slot: " .. slot)
            print()
            print("NBT:")
            print(tostring(item.nbt))
        end
    end

    if not found then
        print("No Time Wand found.")
    end

    sleep(0.25)
end