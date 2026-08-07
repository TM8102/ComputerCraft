term.clear()
term.setCursorPos(1,1)

local modem = peripheral.wrap("back")

if not modem then
    print("No modem on back")
    return
end

print("REMOTE PERIPHERALS")
print("==================")
print()

local names = modem.getNamesRemote()

table.sort(names)

for _, name in ipairs(names) do
    print(name)
    print("Type: " .. tostring(modem.getTypeRemote(name)))

    local methods = modem.getMethodsRemote(name)

    if methods then
        print("Methods:")
        for _, m in ipairs(methods) do
            print("  " .. m)
        end
    end

    print("-----------------------------")
end