term.clear()
term.setCursorPos(1, 1)

print("JDT WIRED NETWORK SCAN")
print("======================")
print()

local names = peripheral.getNames()

if #names == 0 then
    print("No peripherals found on network.")
    return
end

for _, name in ipairs(names) do
    local pType = peripheral.getType(name)

    print("NAME: " .. tostring(name))
    print("TYPE: " .. tostring(pType))

    local methods = peripheral.getMethods(name)

    if methods and #methods > 0 then
        print("METHODS:")

        for _, method in ipairs(methods) do
            print("  " .. method)
        end
    else
        print("METHODS: NONE")
    end

    print("----------------------------")
end