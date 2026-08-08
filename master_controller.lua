-- =========================================================
-- COMPUTERCRAFT MASTER CONTROLLER
-- Central authenticated GitHub cache + Rednet file server.
-- Normal computers fetch scripts/configs from this PC only.
--
-- GitHub token is stored LOCALLY in .github_token.
-- It is never stored in this script or sent to client PCs.
-- =========================================================

local protocol = "cc_master_update"
local hostname = "master"
local apiBase = "https://api.github.com/repos/TM8102/ComputerCraft/contents/"
local tokenFile = ".github_token"
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
local githubToken = nil
local githubRateLimit = nil
local githubRateRemaining = nil
local githubRateReset = nil
local githubAuthStatus = "UNAUTHENTICATED"

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

local function trim(value)
    value = tostring(value or "")
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function loadToken()
    local token = trim(readFile(tokenFile))
    if token ~= "" then
        githubToken = token
        githubAuthStatus = "TOKEN LOADED"
        return true
    end
    return false
end

local function setupTokenIfMissing()
    if loadToken() then return end

    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1,1)
    print("MASTER CONTROLLER - GITHUB AUTH")
    print("===============================")
    print("")
    print("No .github_token found.")
    print("Paste a GitHub token now.")
    print("Input is hidden while typing.")
    print("")
    write("Token (blank = unauthenticated): ")

    local token = trim(read("*"))
    if token ~= "" then
        if writeFile(tokenFile, token) then
            githubToken = token
            githubAuthStatus = "TOKEN SAVED"
            print("")
            term.setTextColor(colors.lime)
            print("Token saved locally to " .. tokenFile)
            term.setTextColor(colors.white)
        else
            githubAuthStatus = "TOKEN SAVE FAILED"
            print("")
            term.setTextColor(colors.red)
            print("Could not save token.")
            term.setTextColor(colors.white)
        end
    else
        githubAuthStatus = "UNAUTHENTICATED"
    end

    sleep(1)
end

local function updateRateInfo(response)
    if not response or type(response.getResponseHeaders) ~= "function" then return end

    local ok, headers = pcall(response.getResponseHeaders)
    if not ok or type(headers) ~= "table" then return end

    githubRateLimit = tonumber(headers["x-ratelimit-limit"] or headers["X-RateLimit-Limit"]) or githubRateLimit
    githubRateRemaining = tonumber(headers["x-ratelimit-remaining"] or headers["X-RateLimit-Remaining"]) or githubRateRemaining
    githubRateReset = tonumber(headers["x-ratelimit-reset"] or headers["X-RateLimit-Reset"]) or githubRateReset
end

local function githubHeaders()
    local headers = {
        ["User-Agent"] = "CC-Tweaked-Master",
        ["Accept"] = "application/vnd.github.raw+json",
        ["X-GitHub-Api-Version"] = "2022-11-28",
        ["Cache-Control"] = "no-cache, no-store",
        ["Pragma"] = "no-cache"
    }

    if githubToken and githubToken ~= "" then
        headers["Authorization"] = "Bearer " .. githubToken
    end

    return headers
end

modemSide = findModem()
if not modemSide then error("No directly attached modem found") end
rednet.open(modemSide)

pcall(function() rednet.unhost(protocol, hostname) end)
rednet.host(protocol, hostname)

if not fs.exists(cacheDir) then fs.makeDir(cacheDir) end

local function cachePath(file)
    local safeName = (tostring(file):gsub("/", "__"))
    return fs.combine(cacheDir, safeName)
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

local function downloadFromGitHub(file)
    local url = apiBase .. file
        .. "?ref=main&cb=" .. tostring(now())

    local response, err = http.get(url, githubHeaders())
    if not response then
        return false, "HTTP FAILED: " .. tostring(err)
    end

    updateRateInfo(response)

    local code = response.getResponseCode and response.getResponseCode() or 200
    local data = response.readAll()
    response.close()

    if code == 401 then
        githubAuthStatus = "TOKEN REJECTED"
        return false, "GITHUB 401 - TOKEN REJECTED"
    elseif code == 403 and githubRateRemaining == 0 then
        return false, "GITHUB RATE LIMIT EXHAUSTED"
    elseif code < 200 or code >= 300 then
        return false, "GITHUB HTTP " .. tostring(code)
    end

    if githubToken and githubToken ~= "" then
        githubAuthStatus = "AUTHENTICATED"
    else
        githubAuthStatus = "UNAUTHENTICATED"
    end

    if not data or data == "" then return false, "EMPTY FILE" end

    if tostring(file):sub(-4) == ".lua" then
        local loader, syntaxError = load(data, "@" .. tostring(file), "t", _ENV)
        if not loader then
            return false, "LUA ERROR: " .. tostring(syntaxError)
        end
    end

    cache[file] = data
    cacheStatus[file] = {
        source = githubToken and "GITHUB API AUTH" or "GITHUB API",
        updated = now(),
        bytes = #data
    }
    writeFile(cachePath(file), data)
    return true
end

local function refreshFile(file)
    return downloadFromGitHub(file)
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
        if ok then
            successes = successes + 1
        else
            failures[#failures + 1] = file .. ": " .. tostring(err)
        end
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
    print("Hostname: " .. hostname)
    print("")

    if githubAuthStatus == "AUTHENTICATED" then
        term.setTextColor(colors.lime)
    elseif githubAuthStatus == "TOKEN REJECTED" then
        term.setTextColor(colors.red)
    else
        term.setTextColor(colors.orange)
    end
    print("GitHub: " .. githubAuthStatus)
    term.setTextColor(colors.white)

    if githubRateLimit and githubRateRemaining then
        print("Rate: " .. githubRateRemaining .. " / " .. githubRateLimit)
    else
        print("Rate: waiting for GitHub response")
    end

    local cached = 0
    for _, file in ipairs(managedFiles) do
        if cache[file] then cached = cached + 1 end
    end

    term.setTextColor(cached == #managedFiles and colors.lime or colors.orange)
    print("Cached: " .. cached .. " / " .. #managedFiles)
    term.setTextColor(colors.white)

    local clientCount = 0
    local cutoff = now() - 60000
    for id, seen in pairs(clientsSeen) do
        if seen >= cutoff then
            clientCount = clientCount + 1
        else
            clientsSeen[id] = nil
        end
    end
    print("Clients (60s): " .. clientCount)

    if lastRefresh > 0 then
        print("Last refresh: " .. math.floor((now()-lastRefresh)/1000) .. "s ago")
    else
        print("Last refresh: NEVER")
    end

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
    print("Only this PC contacts GitHub.")
    print("Token stays local on this PC.")
end

local function displayLoop()
    while true do
        drawScreen()
        sleep(1)
    end
end

setupTokenIfMissing()
loadDiskCache()

term.clear()
term.setCursorPos(1,1)
print("MASTER CONTROLLER")
print("Initial GitHub cache refresh...")
local successes, failures = refreshAll()
print("Updated " .. successes .. " / " .. #managedFiles)
if #failures > 0 then
    print("Some downloads failed; disk cache used where available.")
end
sleep(1)

parallel.waitForAll(networkLoop, refreshLoop, displayLoop)
