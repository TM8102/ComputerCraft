-- =========================================================
-- COMPUTERCRAFT MASTER CONTROLLER
-- Central GitHub cache + Rednet file server.
-- Normal computers fetch scripts/configs from this PC only.
-- =========================================================

local protocol = "cc_master_update"
local hostname = "master"
local rawBase = "https://raw.githubusercontent.com/TM8102/ComputerCraft/main/"
local cacheDir = ".master_cache"
local refreshInterval = 300 -- seconds
local freshGuardSeconds = 5 -- prevents many nodes refreshing same file at once

local managedFiles = {
    "startup.lua",
    "main_storage.lua",
    "storage_brain.lua",
    "storage_machine_node.lua",
    "resource_generator.lua",
    "time_wand_controller.lua",
    "mob_control_panel.lua",
    "remote_spawner_node.lua",
    "main_status_screen.lua",
    "targets.lua",
    "spawners.lua"
}

local computerID = os.getComputerID()
local modemSide = nil
local cache = {}
local cacheStatus = {}
local lastRefresh = 0
local lastRefreshError = nil
local clientsSeen = {}

local function now()
    return os.epoch("utc")
end

local function findModem()
    for _, side in ipairs({"back","front","left","right","top","bottom"}) do
        if peripheral.isPresent(side) and peripheral.getType(side) == "modem" then
            return side
        end
    end
    return nil
end

modemSide = findModem()
if not modemSide then error("No directly attached modem found") end
rednet.open(modemSide)

pcall(function() rednet.unhost(protocol, hostname) end)
rednet.host(protocol, hostname)

if not fs.exists(cacheDir) then fs.makeDir(cacheDir) end

local function cachePath(file)
    return fs.combine(cacheDir, file:gsub("/", "__"))
end

local function readFile(path)
    if not fs.exists(path) then return nil end
    local handle = fs.open(path, "r")
    if not handle then return nil end
    local data = handle.readAll()
    handle.close()
    return data
end

local function writeFile(path, data)
    local handle = fs.open(path, "w")
    if not handle then return false end
    handle.write(data)
    handle.close()
    return true
end

local function loadDiskCache()
    for _, file in ipairs(managedFiles) do
        local data = readFile(cachePath(file))
        if data and data ~= "" then
            cache[file] = data
            cacheStatus[file] = {source="DISK CACHE",updated=0,bytes=#data}
        end
    end
end

local function downloadRaw(file)
    local url = rawBase .. file .. "?cb=" .. tostring(now())
    local response, err = http.get(url, {
        ["Cache-Control"] = "no-cache, no-store",
        ["Pragma"] = "no-cache",
        ["User-Agent"] = "CC-Tweaked-Master"
    })

    if not response then return false, "HTTP FAILED: " .. tostring(err) end

    local code = response.getResponseCode and response.getResponseCode() or 200
    local data = response.readAll()
    response.close()

    if code < 200 or code >= 300 then return false, "HTTP " .. tostring(code) end
    if not data or data == "" then return false, "EMPTY FILE" end

    if file:sub(-4) == ".lua" then
        local loader, syntaxError = load(data, "@" .. file, "t", _ENV)
        if not loader then return false, "LUA ERROR: " .. tostring(syntaxError) end
    end

    cache[file] = data
    cacheStatus[file] = {source="GITHUB RAW",updated=now(),bytes=#data}
    writeFile(cachePath(file), data)
    return true
end

local function refreshFile(file)
    return downloadRaw(file)
end

local function refreshFileIfNeeded(file, forceFresh)
    if not forceFresh then return true end
    local status = cacheStatus[file]
    local age = status and status.updated and (now() - status.updated) or math.huge
    if age < freshGuardSeconds * 1000 then return true end
    return refreshFile(file)
end

local function refreshAll()
    local successes = 0
    local failures = {}

    for _, file in ipairs(managedFiles) do
        local ok, err = refreshFile(file)
        if ok then successes = successes + 1
        else failures[#failures + 1] = file .. ": " .. tostring(err) end
        sleep(0.15)
    end

    lastRefresh = now()
    lastRefreshError = #failures > 0 and table.concat(failures, " | ") or nil
    return successes, failures
end

local function sendFile(targetID, file, requestID, forceFresh)
    local refreshed, refreshError = refreshFileIfNeeded(file, forceFresh == true)
    local data = cache[file]

    if not data then
        rednet.send(targetID, {
            type="file_response",requestID=requestID,file=file,success=false,
            error=refreshError or "FILE NOT CACHED",masterID=computerID
        }, protocol)
        return
    end

    rednet.send(targetID, {
        type="file_response",
        requestID=requestID,
        file=file,
        success=true,
        contents=data,
        bytes=#data,
        masterID=computerID,
        cachedAt=cacheStatus[file] and cacheStatus[file].updated or 0,
        refreshError=refreshed and nil or refreshError
    }, protocol)
end

local function networkLoop()
    while true do
        local senderID, message, incomingProtocol = rednet.receive()
        if incomingProtocol == protocol and type(message) == "table" then
            clientsSeen[senderID] = now()

            if message.type == "discover_master" then
                rednet.send(senderID, {
                    type="master_hello",masterID=computerID,timestamp=now()
                }, protocol)

            elseif message.type == "get_file" and type(message.file) == "string" then
                sendFile(senderID, message.file, message.requestID, message.fresh)

            elseif message.type == "refresh_file" and type(message.file) == "string" then
                local ok, err = refreshFile(message.file)
                rednet.send(senderID, {
                    type="refresh_result",file=message.file,success=ok,error=err,masterID=computerID
                }, protocol)

            elseif message.type == "refresh_all" then
                local successes, failures = refreshAll()
                rednet.send(senderID, {
                    type="refresh_all_result",success=#failures==0,updated=successes,
                    failed=#failures,errors=failures,masterID=computerID
                }, protocol)
            end
        end
    end
end

local function refreshLoop()
    while true do
        sleep(refreshInterval)
        refreshAll()
    end
end

local function drawScreen()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1,1)

    print("MASTER CONTROLLER")
    print("=================")
    print("Computer ID: " .. computerID)
    print("Modem: " .. string.upper(modemSide))
    print("Protocol: " .. protocol)
    print("Hostname: " .. hostname)
    print("")

    local cached = 0
    for _, file in ipairs(managedFiles) do if cache[file] then cached = cached + 1 end end

    term.setTextColor(cached == #managedFiles and colors.lime or colors.orange)
    print("Cached: " .. cached .. " / " .. #managedFiles)
    term.setTextColor(colors.white)

    local clientCount = 0
    local cutoff = now() - 60000
    for id, seen in pairs(clientsSeen) do
        if seen >= cutoff then clientCount = clientCount + 1 else clientsSeen[id] = nil end
    end
    print("Clients (60s): " .. clientCount)

    if lastRefresh > 0 then print("Last refresh: " .. math.floor((now()-lastRefresh)/1000) .. "s ago")
    else print("Last refresh: NEVER") end

    if lastRefreshError then
        term.setTextColor(colors.orange)
        print("")
        print("LAST REFRESH HAD ERRORS")
    else
        term.setTextColor(colors.lime)
        print("")
        print("CACHE HEALTHY")
    end
    term.setTextColor(colors.white)

    print("")
    print("GitHub is contacted ONLY here.")
    print("Clients receive scripts/configs over Rednet.")
end

local function displayLoop()
    while true do drawScreen(); sleep(1) end
end

loadDiskCache()

term.clear()
term.setCursorPos(1,1)
print("MASTER CONTROLLER")
print("Initial GitHub cache refresh...")
local successes, failures = refreshAll()
print("Updated " .. successes .. " / " .. #managedFiles)
if #failures > 0 then print("Some downloads failed; disk cache used where available.") end
sleep(1)

parallel.waitForAll(networkLoop, refreshLoop, displayLoop)
