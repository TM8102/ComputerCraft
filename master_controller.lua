-- =========================================================
-- COMPUTERCRAFT MASTER CONTROLLER
-- Central authenticated GitHub cache + Rednet file server.
--
-- TOP monitor controls:
--   REFRESH GITHUB = refresh every managed file from GitHub.
--   PUSH TO ALL    = reboot/update known clients one at a time.
--
-- Manual Targets/Spawners refreshes are serialized here:
-- one node -> reply or 5 second timeout -> next node.
-- =========================================================

local protocol = "cc_master_update"
local hostname = "master"
local monitorSide = "top"
local apiBase = "https://api.github.com/repos/TM8102/ComputerCraft/contents/"
local tokenFile = ".github_token"
local cacheDir = ".master_cache"
local refreshInterval = 300
local freshGuardSeconds = 5
local nodeRefreshTimeout = 5
local pushSpacing = 0.8

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
local modemSide
local monitor
local monitorName
local cache = {}
local cacheStatus = {}
local clients = {}
local lastRefresh = 0
local lastRefreshError = nil
local githubToken
local githubRateLimit
local githubRateRemaining
local githubRateReset
local githubAuthStatus = "UNAUTHENTICATED"

local refreshQueue = {}
local activeRefreshJob = nil
local pushQueue = {}
local pushRunning = false
local pushTotal = 0
local pushDone = 0
local lastAction = "READY"

local buttons = { github={}, push={} }

local function now() return os.epoch("utc") end

local function findModem()
    for _,side in ipairs({"back","front","left","right","bottom","top"}) do
        if side ~= monitorSide and peripheral.isPresent(side)
            and peripheral.getType(side)=="modem" then
            return side
        end
    end
    -- fallback in case setup changes
    for _,side in ipairs({"back","front","left","right","bottom","top"}) do
        if peripheral.isPresent(side) and peripheral.getType(side)=="modem" then return side end
    end
end

local function readFile(path)
    if not fs.exists(path) then return nil end
    local h=fs.open(path,"r")
    if not h then return nil end
    local data=h.readAll(); h.close(); return data
end

local function writeFile(path,data)
    local h=fs.open(path,"w")
    if not h then return false end
    h.write(data); h.close(); return true
end

local function trim(v)
    v=tostring(v or "")
    return (v:gsub("^%s+",""):gsub("%s+$",""))
end

local function loadToken()
    local token=trim(readFile(tokenFile))
    if token~="" then githubToken=token; githubAuthStatus="TOKEN LOADED"; return true end
    return false
end

local function setupTokenIfMissing()
    if loadToken() then return end
    term.setBackgroundColor(colors.black); term.setTextColor(colors.white)
    term.clear(); term.setCursorPos(1,1)
    print("MASTER CONTROLLER - GITHUB AUTH")
    print("===============================")
    print("")
    print("No .github_token found.")
    print("Paste a GitHub token now.")
    print("Input is hidden while typing.")
    print("")
    write("Token (blank = unauthenticated): ")
    local token=trim(read("*"))
    if token~="" and writeFile(tokenFile,token) then
        githubToken=token; githubAuthStatus="TOKEN SAVED"
        print(""); term.setTextColor(colors.lime); print("Token saved locally.")
        term.setTextColor(colors.white)
    elseif token~="" then
        githubAuthStatus="TOKEN SAVE FAILED"
    else
        githubAuthStatus="UNAUTHENTICATED"
    end
    sleep(1)
end

local function githubHeaders()
    local headers={
        ["User-Agent"]="CC-Tweaked-Master",
        ["Accept"]="application/vnd.github.raw+json",
        ["X-GitHub-Api-Version"]="2022-11-28",
        ["Cache-Control"]="no-cache, no-store",
        ["Pragma"]="no-cache"
    }
    if githubToken and githubToken~="" then headers["Authorization"]="Bearer "..githubToken end
    return headers
end

local function updateRateInfo(response)
    if not response or type(response.getResponseHeaders)~="function" then return end
    local ok,headers=pcall(response.getResponseHeaders)
    if not ok or type(headers)~="table" then return end
    githubRateLimit=tonumber(headers["x-ratelimit-limit"] or headers["X-RateLimit-Limit"]) or githubRateLimit
    githubRateRemaining=tonumber(headers["x-ratelimit-remaining"] or headers["X-RateLimit-Remaining"]) or githubRateRemaining
    githubRateReset=tonumber(headers["x-ratelimit-reset"] or headers["X-RateLimit-Reset"]) or githubRateReset
end

modemSide=findModem()
if not modemSide then error("No modem found") end
rednet.open(modemSide)
pcall(function() rednet.unhost(protocol,hostname) end)
rednet.host(protocol,hostname)

monitor=peripheral.wrap(monitorSide)
if not monitor then error("No monitor on "..monitorSide) end
if not monitor.isColor() then error("Advanced Monitor required on "..monitorSide) end
monitor.setTextScale(0.5)
monitorName=peripheral.getName(monitor)

if not fs.exists(cacheDir) then fs.makeDir(cacheDir) end

local function cachePath(file)
    local safe=(tostring(file):gsub("/","__"))
    return fs.combine(cacheDir,safe)
end

local function loadDiskCache()
    for _,file in ipairs(managedFiles) do
        local data=readFile(cachePath(file))
        if data and data~="" then
            cache[file]=data
            cacheStatus[file]={source="DISK CACHE",updated=0,bytes=#data}
        end
    end
end

local function downloadFromGitHub(file)
    local url=apiBase..file.."?ref=main&cb="..tostring(now())
    local response,err=http.get(url,githubHeaders())
    if not response then return false,"HTTP FAILED: "..tostring(err) end
    updateRateInfo(response)
    local code=response.getResponseCode and response.getResponseCode() or 200
    local data=response.readAll(); response.close()

    if code==401 then githubAuthStatus="TOKEN REJECTED"; return false,"GITHUB 401 - TOKEN REJECTED" end
    if code==403 and githubRateRemaining==0 then return false,"GITHUB RATE LIMIT EXHAUSTED" end
    if code<200 or code>=300 then return false,"GITHUB HTTP "..tostring(code) end
    githubAuthStatus=(githubToken and githubToken~="") and "AUTHENTICATED" or "UNAUTHENTICATED"
    if not data or data=="" then return false,"EMPTY FILE" end

    if tostring(file):sub(-4)==".lua" then
        local loader,syntaxError=load(data,"@"..tostring(file),"t",_ENV)
        if not loader then return false,"LUA ERROR: "..tostring(syntaxError) end
    end

    cache[file]=data
    cacheStatus[file]={
        source=githubToken and "GITHUB API AUTH" or "GITHUB API",
        updated=now(), bytes=#data
    }
    writeFile(cachePath(file),data)
    return true
end

local function refreshFile(file) return downloadFromGitHub(file) end

local function refreshFileIfNeeded(file,forceFresh)
    if not forceFresh then return true end
    local status=cacheStatus[file]
    local age=status and status.updated and (now()-status.updated) or math.huge
    if age<freshGuardSeconds*1000 then return true end
    return refreshFile(file)
end

local function refreshAll()
    lastAction="REFRESHING GITHUB..."
    local successes=0; local failures={}
    for _,file in ipairs(managedFiles) do
        local ok,err=refreshFile(file)
        if ok then successes=successes+1 else failures[#failures+1]=file..": "..tostring(err) end
        sleep(0.12)
    end
    lastRefresh=now()
    lastRefreshError=#failures>0 and table.concat(failures," | ") or nil
    lastAction="GITHUB "..successes.."/"..#managedFiles.." UPDATED"
    return successes,failures
end

local function rememberClient(id,message)
    local info=clients[id] or {}
    info.lastSeen=now()
    if type(message)=="table" then
        info.roleNumber=message.roleNumber or info.roleNumber
        info.roleName=message.roleName or info.roleName
        info.roleFile=message.roleFile or info.roleFile
        info.refreshGroup=message.refreshGroup or info.refreshGroup
        if message.file=="targets.lua" then info.refreshGroup="targets" end
        if message.file=="spawners.lua" then info.refreshGroup="spawners" end
    end
    clients[id]=info
end

local function sendFile(targetID,file,requestID,forceFresh)
    local refreshed,refreshError=refreshFileIfNeeded(file,forceFresh==true)
    local data=cache[file]
    if not data then
        rednet.send(targetID,{type="file_response",requestID=requestID,file=file,
            success=false,error=refreshError or "FILE NOT CACHED",masterID=computerID},protocol)
        return
    end
    rednet.send(targetID,{type="file_response",requestID=requestID,file=file,success=true,
        contents=data,bytes=#data,masterID=computerID,
        cachedAt=cacheStatus[file] and cacheStatus[file].updated or 0,
        refreshError=refreshed and nil or refreshError},protocol)
end

local function queueSequentialRefresh(senderID,message)
    local kind=message.kind
    if kind~="targets" and kind~="spawners" then return end
    refreshQueue[#refreshQueue+1]={
        kind=kind,
        requester=message.requester or senderID,
        originalMessage=message.originalMessage or {},
        queuedAt=now()
    }
    lastAction=string.upper(kind).." REFRESH QUEUED"
end

local function networkLoop()
    while true do
        local senderID,message,incomingProtocol=rednet.receive()
        if incomingProtocol==protocol and type(message)=="table" then
            rememberClient(senderID,message)
            if message.type=="discover_master" then
                rednet.send(senderID,{type="master_hello",masterID=computerID,timestamp=now()},protocol)
            elseif message.type=="register_client" then
                rednet.send(senderID,{type="register_ack",masterID=computerID,timestamp=now()},protocol)
            elseif message.type=="get_file" and type(message.file)=="string" then
                sendFile(senderID,message.file,message.requestID,message.fresh)
            elseif message.type=="refresh_file" and type(message.file)=="string" then
                local ok,err=refreshFile(message.file)
                rednet.send(senderID,{type="refresh_result",file=message.file,success=ok,error=err,masterID=computerID},protocol)
            elseif message.type=="refresh_all" then
                local successes,failures=refreshAll()
                rednet.send(senderID,{type="refresh_all_result",success=#failures==0,
                    updated=successes,failed=#failures,errors=failures,masterID=computerID},protocol)
            elseif message.type=="sequential_refresh" then
                queueSequentialRefresh(senderID,message)
            end
        end
    end
end

local function clientIDsForGroup(group)
    local ids={}
    for id,info in pairs(clients) do
        if info.refreshGroup==group then ids[#ids+1]=id end
    end
    table.sort(ids)
    return ids
end

local function waitForNodeReply(targetID,statusProtocol,replyCommand,timeoutSeconds)
    local timer=os.startTimer(timeoutSeconds)
    while true do
        local event,a,b,c=os.pullEvent()
        if event=="rednet_message" then
            local senderID,msg,proto=a,b,c
            if senderID==targetID and proto==statusProtocol and type(msg)=="table"
                and msg.command==replyCommand then
                return true,msg
            end
        elseif event=="timer" and a==timer then
            return false,nil
        end
    end
end

local function sequentialRefreshLoop()
    while true do
        if #refreshQueue==0 then
            sleep(0.1)
        else
            activeRefreshJob=table.remove(refreshQueue,1)
            local job=activeRefreshJob
            local group=job.kind
            local configFile=(group=="targets") and "targets.lua" or "spawners.lua"
            local controlProtocol=(group=="targets") and "config_control" or "spawner_config_control"
            local statusProtocol=(group=="targets") and "config_status" or "spawner_config_status"
            local replyCommand=(group=="targets") and "targets_refresh_status" or "spawners_refresh_status"
            local ids=clientIDsForGroup(group)

            -- ONE GitHub read for the whole batch. Client requests marked fresh
            -- will then hit this just-refreshed cache and not GitHub again.
            lastAction=string.upper(group).." CONFIG -> GITHUB"
            local configOK,configErr=refreshFile(configFile)
            if not configOK then lastAction="CONFIG REFRESH FAILED: "..tostring(configErr) end

            job.total=#ids; job.done=0; job.current=nil; job.timeouts=0
            for _,id in ipairs(ids) do
                job.current=id
                lastAction=string.upper(group).." -> PC "..id.." ("..(job.done+1).."/"..job.total..")"
                local outgoing={}
                for k,v in pairs(job.originalMessage or {}) do outgoing[k]=v end
                if group=="targets" then outgoing.command="force_targets_refresh"
                else outgoing.command="force_spawners_refresh" end
                outgoing.masterSequential=true
                outgoing.batchTimestamp=job.queuedAt
                rednet.send(id,outgoing,controlProtocol)

                local replied=waitForNodeReply(id,statusProtocol,replyCommand,nodeRefreshTimeout)
                if not replied then job.timeouts=job.timeouts+1 end
                job.done=job.done+1
                sleep(0.08)
            end

            lastAction=string.upper(group).." COMPLETE "..job.done.."/"..job.total
                ..(job.timeouts>0 and ("  TIMEOUTS "..job.timeouts) or "")
            activeRefreshJob=nil
        end
    end
end

local function refreshLoop()
    while true do sleep(refreshInterval); refreshAll() end
end

local function buildPushQueue()
    pushQueue={}
    for id in pairs(clients) do
        if id~=computerID then pushQueue[#pushQueue+1]=id end
    end
    table.sort(pushQueue)
    pushTotal=#pushQueue; pushDone=0; pushRunning=pushTotal>0
    lastAction=pushRunning and ("PUSH QUEUED: "..pushTotal.." PCS") or "PUSH: NO CLIENTS KNOWN"
end

local function pushLoop()
    while true do
        if pushRunning and #pushQueue>0 then
            local id=table.remove(pushQueue,1)
            lastAction="PUSH -> PC "..id.." ("..(pushDone+1).."/"..pushTotal..")"
            rednet.send(id,{type="push_update",masterID=computerID,timestamp=now()},protocol)
            pushDone=pushDone+1
            sleep(pushSpacing)
            if #pushQueue==0 then
                pushRunning=false
                lastAction="PUSH COMPLETE "..pushDone.."/"..pushTotal
            end
        else
            sleep(0.1)
        end
    end
end

local function fill(x1,y1,x2,y2,color)
    monitor.setBackgroundColor(color)
    for y=y1,y2 do monitor.setCursorPos(x1,y); monitor.write(string.rep(" ",x2-x1+1)) end
end

local function center(x1,x2,y,text,fg,bg)
    text=tostring(text or "")
    local width=x2-x1+1
    if #text>width then text=text:sub(1,width) end
    monitor.setCursorPos(x1+math.floor((width-#text)/2),y)
    monitor.setTextColor(fg); monitor.setBackgroundColor(bg); monitor.write(text)
end

local function inside(x,y,b) return x>=b.x1 and x<=b.x2 and y>=b.y1 and y<=b.y2 end

local function calculateLayout()
    local width=monitor.getSize()
    local gap=2; local margin=2
    local buttonWidth=math.floor((width-margin*2-gap)/2)
    buttons.github={x1=margin,y1=2,x2=margin+buttonWidth-1,y2=4}
    buttons.push={x1=buttons.github.x2+gap+1,y1=2,x2=width-margin,y2=4}
end

local function drawButton(b,text,color)
    fill(b.x1,b.y1,b.x2,b.y2,color)
    center(b.x1,b.x2,b.y1+1,text,colors.white,color)
end

local function drawScreen()
    local width,height=monitor.getSize()
    fill(1,1,width,height,colors.black)
    fill(1,1,width,5,colors.cyan)
    center(1,width,1,"MASTER CONTROLLER",colors.black,colors.cyan)
    drawButton(buttons.github,"REFRESH GITHUB",colors.green)
    drawButton(buttons.push,pushRunning and ("PUSH "..pushDone.."/"..pushTotal) or "PUSH TO ALL",colors.blue)
    fill(1,6,width,6,colors.blue)

    local y=8
    monitor.setBackgroundColor(colors.black); monitor.setTextColor(colors.white)
    local function line(text,color)
        if y>height then return end
        monitor.setCursorPos(2,y); monitor.setTextColor(color or colors.white)
        monitor.write(tostring(text)); y=y+1
    end

    line("Computer ID: "..computerID)
    line("Modem: "..string.upper(modemSide))
    line("GitHub: "..githubAuthStatus, githubAuthStatus=="AUTHENTICATED" and colors.lime or colors.orange)
    if githubRateLimit and githubRateRemaining then line("API Rate: "..githubRateRemaining.." / "..githubRateLimit) end

    local cached=0
    for _,file in ipairs(managedFiles) do if cache[file] then cached=cached+1 end end
    line("Cached: "..cached.." / "..#managedFiles, cached==#managedFiles and colors.lime or colors.orange)

    local clientCount=0
    for _ in pairs(clients) do clientCount=clientCount+1 end
    line("Known clients: "..clientCount)
    line("Refresh queue: "..#refreshQueue..(activeRefreshJob and " + ACTIVE" or ""))
    if activeRefreshJob then
        line("Current: "..string.upper(activeRefreshJob.kind).." PC "..tostring(activeRefreshJob.current or "PREP"),colors.orange)
        line("Progress: "..tostring(activeRefreshJob.done or 0).." / "..tostring(activeRefreshJob.total or 0))
    end

    if lastRefresh>0 then line("GitHub refreshed: "..math.floor((now()-lastRefresh)/1000).."s ago") end
    line("")
    line("STATUS: "..lastAction,colors.cyan)
    if lastRefreshError then line("LAST GITHUB REFRESH HAD ERRORS",colors.orange)
    else line("CACHE HEALTHY",colors.lime) end

    monitor.setTextColor(colors.white)
end

local function displayLoop()
    while true do drawScreen(); sleep(0.25) end
end

local function monitorLoop()
    while true do
        local event,side,x,y=os.pullEvent("monitor_touch")
        if side==monitorName then
            if inside(x,y,buttons.github) then
                drawButton(buttons.github,"REFRESHING...",colors.lime)
                refreshAll()
            elseif inside(x,y,buttons.push) and not pushRunning then
                buildPushQueue()
            end
        end
    end
end

setupTokenIfMissing()
loadDiskCache()
calculateLayout()

term.clear(); term.setCursorPos(1,1)
print("MASTER CONTROLLER")
print("Monitor UI: TOP")
print("Initial GitHub cache refresh...")
local successes,failures=refreshAll()
print("Updated "..successes.." / "..#managedFiles)
if #failures>0 then print("Some downloads failed; disk cache used where available.") end

parallel.waitForAll(
    networkLoop,
    sequentialRefreshLoop,
    refreshLoop,
    pushLoop,
    displayLoop,
    monitorLoop
)
