-- =========================================================
-- COMPUTERCRAFT WEB CONTROL BRIDGE
-- Polls docs/control.json and translates web commands into
-- existing mob-farm Rednet controls.
-- =========================================================

local controlProtocol = "spawner_control"
local statusProtocol = "spawner_status"
local fanProtocol = "mob_farm_fans"

local tokenFile = ".github_token"
local controlAPI = "https://api.github.com/repos/TM8102/ComputerCraft/contents/docs/control.json"
local branch = "main"
local pollSeconds = 5
local fanShutdownSeconds = 15
local maintenanceFreshSeconds = 20
local commandFreshSeconds = 120

local githubToken = nil
local lastNonce = 0
local maintenanceByNode = {}
local fanShutdownTimer = nil
local fanShutdownRemaining = 0

local function now() return os.epoch("utc") end

local function readFile(path)
    if not fs.exists(path) then return nil end
    local h=fs.open(path,"r")
    if not h then return nil end
    local data=h.readAll(); h.close(); return data
end

local function trim(v)
    v=tostring(v or "")
    return (v:gsub("^%s+",""):gsub("%s+$",""))
end

local function loadToken()
    githubToken=trim(readFile(tokenFile))
    if githubToken=="" then githubToken=nil end
    return githubToken~=nil
end

local function headers()
    local h={
        ["User-Agent"]="CC-Tweaked-Web-Control",
        ["Accept"]="application/vnd.github.raw+json",
        ["X-GitHub-Api-Version"]="2022-11-28",
        ["Cache-Control"]="no-cache, no-store",
        ["Pragma"]="no-cache"
    }
    if githubToken then h["Authorization"]="Bearer "..githubToken end
    return h
end

local function maintenanceActive()
    local t=now()
    for _,info in pairs(maintenanceByNode) do
        if info.state and t-(info.updated or 0)<=maintenanceFreshSeconds*1000 then return true end
    end
    return false
end

local function setFans(state)
    rednet.broadcast({command="fans",state=state==true,source="WEB"},fanProtocol)
end

local function startFarm()
    if maintenanceActive() then
        print("WEB START REFUSED: maintenance is active")
        return false
    end
    fanShutdownTimer=nil
    fanShutdownRemaining=0
    setFans(true)
    rednet.broadcast({command="all_on",source="WEB",timestamp=now()},controlProtocol)
    print("WEB COMMAND: MOB FARM ON")
    return true
end

local function stopFarm()
    rednet.broadcast({command="all_off",source="WEB",timestamp=now()},controlProtocol)
    setFans(true)
    fanShutdownRemaining=fanShutdownSeconds
    fanShutdownTimer=os.startTimer(1)
    print("WEB COMMAND: MOB FARM OFF - fans cooling for "..fanShutdownSeconds.."s")
    return true
end

local function processCommand(data)
    if type(data)~="table" then return end
    local nonce=tonumber(data.nonce) or 0
    if nonce<=lastNonce then return end
    lastNonce=nonce

    local requestedAt=tonumber(data.requestedAt) or 0
    if requestedAt<=0 or now()-requestedAt>commandFreshSeconds*1000 then
        print("WEB CONTROL: ignored stale command nonce "..tostring(nonce))
        return
    end

    local command=string.lower(tostring(data.command or "none"))
    if command=="mob_on" then startFarm()
    elseif command=="mob_off" then stopFarm() end
end

local function pollOnce()
    local url=controlAPI.."?ref="..branch.."&cb="..tostring(now())
    local response,err=http.get(url,headers())
    if not response then
        print("WEB CONTROL POLL FAILED: "..tostring(err))
        return
    end
    local code=response.getResponseCode and response.getResponseCode() or 200
    local body=response.readAll(); response.close()
    if code<200 or code>=300 then
        print("WEB CONTROL HTTP "..tostring(code))
        return
    end
    local ok,data=pcall(textutils.unserialiseJSON,body)
    if not ok or type(data)~="table" then
        print("WEB CONTROL BAD JSON")
        return
    end
    processCommand(data)
end

local function networkLoop()
    while true do
        local senderID,message,protocol=rednet.receive()
        if protocol==statusProtocol and type(message)=="table" and message.messageType=="spawner_status" then
            maintenanceByNode[senderID]={state=message.maintenance==true,updated=now()}
        end
    end
end

local function pollLoop()
    sleep(5)
    while true do
        pollOnce()
        sleep(pollSeconds)
    end
end

local function timerLoop()
    while true do
        local _,id=os.pullEvent("timer")
        if fanShutdownTimer and id==fanShutdownTimer then
            fanShutdownRemaining=fanShutdownRemaining-1
            if fanShutdownRemaining<=0 then
                fanShutdownTimer=nil
                fanShutdownRemaining=0
                setFans(false)
                print("WEB MOB FARM: fans OFF")
            else
                fanShutdownTimer=os.startTimer(1)
            end
        end
    end
end

if not peripheral.find("modem") then error("No modem found for web control bridge") end
for _,side in ipairs({"back","front","left","right","top","bottom"}) do
    if peripheral.isPresent(side) and peripheral.getType(side)=="modem" and not rednet.isOpen(side) then rednet.open(side) end
end

loadToken()
print("WEB CONTROL BRIDGE")
print("Polling GitHub every "..pollSeconds.." seconds")
parallel.waitForAll(networkLoop,pollLoop,timerLoop)
