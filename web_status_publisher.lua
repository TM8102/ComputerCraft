-- =========================================================
-- COMPUTERCRAFT WEB STATUS PUBLISHER
-- Runs beside master_controller.lua on the Master PC.
-- Watches the existing Rednet traffic, builds a full system snapshot,
-- and updates docs/status.json for the GitHub Pages dashboard.
--
-- Requires .github_token with Contents: Read and write.
-- =========================================================

local storageStatusProtocol = "inventory_status"
local machineStatusProtocol = "resource_machine_status"
local spawnerStatusProtocol = "spawner_status"
local fanProtocol = "mob_farm_fans"
local masterProtocol = "cc_master_update"

local tokenFile = ".github_token"
local apiURL = "https://api.github.com/repos/TM8102/ComputerCraft/contents/docs/status.json"
local branch = "main"
local publishInterval = 60
local sourceOfflineSeconds = 15
local sourceRemoveSeconds = 120
local computerOfflineSeconds = 35

local storageSources = {}
local machines = {}
local spawners = {}
local computers = {}
local fansState = nil
local githubToken = nil
local statusSha = nil
local lastPublish = 0
local lastPublishOK = false
local lastPublishError = nil

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

local b64chars='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function base64(data)
    return ((data:gsub('.',function(x)
        local r,b='',x:byte()
        for i=8,1,-1 do r=r..(b%2^i-b%2^(i-1)>0 and '1' or '0') end
        return r
    end)..'0000'):gsub('%d%d%d?%d?%d?%d?',function(x)
        if #x<6 then return '' end
        local c=0
        for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
        return b64chars:sub(c+1,c+1)
    end)..({ '', '==', '=' })[#data%3+1])
end

local function headers(raw)
    local h={
        ["User-Agent"]="CC-Tweaked-Web-Status",
        ["X-GitHub-Api-Version"]="2022-11-28",
        ["Cache-Control"]="no-cache, no-store"
    }
    h["Accept"] = raw and "application/vnd.github.raw+json" or "application/vnd.github+json"
    if githubToken then h["Authorization"]="Bearer "..githubToken end
    return h
end

local function httpRequest(method,url,body,requestHeaders)
    local args={url=url,method=method,headers=requestHeaders or {}}
    if body~=nil then args.body=body end
    local ok,err=http.request(args)
    if not ok then return nil,"REQUEST FAILED: "..tostring(err) end

    while true do
        local event,eventURL,a,b=os.pullEvent()
        if eventURL==url then
            if event=="http_success" then
                local handle=a
                local code=handle.getResponseCode and handle.getResponseCode() or 200
                local data=handle.readAll(); handle.close()
                return {code=code,body=data}
            elseif event=="http_failure" then
                local errorMessage=a
                local handle=b
                local code=nil
                local data=nil
                if handle then
                    code=handle.getResponseCode and handle.getResponseCode() or nil
                    data=handle.readAll(); handle.close()
                end
                return {code=code,body=data},"HTTP FAILURE: "..tostring(errorMessage)
            end
        end
    end
end

local function getStatusSha()
    local url=apiURL.."?ref="..branch.."&cb="..tostring(now())
    local response,err=httpRequest("GET",url,nil,headers(false))
    if not response then return false,err end
    if not response.code or response.code<200 or response.code>=300 then
        return false,"GET STATUS HTTP "..tostring(response.code or "?")
    end
    local ok,data=pcall(textutils.unserialiseJSON,response.body)
    if not ok or type(data)~="table" or type(data.sha)~="string" then
        return false,"COULD NOT READ status.json SHA"
    end
    statusSha=data.sha
    return true
end

local function ensureSource(id)
    if not storageSources[id] then storageSources[id]={} end
    return storageSources[id]
end

local function rememberComputer(id,message)
    if not id then return end
    local c=computers[id] or {id=id}
    c.lastSeen=now()
    if type(message)=="table" then
        c.roleNumber=message.roleNumber or c.roleNumber
        c.roleName=message.roleName or message.role or c.roleName
        c.roleFile=message.roleFile or c.roleFile
        c.refreshGroup=message.refreshGroup or c.refreshGroup
    end
    computers[id]=c
end

local function processStorage(senderID,message)
    rememberComputer(senderID,message)
    if message.messageType=="storage_manifest" and type(message.enabledKeys)=="table" then
        local wanted={}
        for _,itemID in ipairs(message.enabledKeys) do wanted[itemID]=true end
        local source=ensureSource(senderID)
        for itemID in pairs(source) do if not wanted[itemID] then source[itemID]=nil end end
        return
    end

    if message.messageType~="inventory_update" then return end
    local itemID=message.itemID or message.storageKey
    if type(itemID)~="string" then return end
    local source=ensureSource(senderID)
    source[itemID]={
        itemID=itemID,
        name=message.displayName or itemID,
        amount=tonumber(message.amount) or 0,
        target=tonumber(message.targetAmount or message.target) or 0,
        found=message.found~=false,
        online=message.online~=false,
        error=message.error,
        lastUpdate=now()
    }
end

local function processMachine(senderID,message)
    if message.messageType~="resource_machine_status" or type(message.itemID)~="string" then return end
    rememberComputer(senderID,message)
    machines[message.itemID]={
        itemID=message.itemID,
        name=message.displayName or message.itemID,
        state=message.state==true,
        requested=message.requested==true,
        running=(message.running~=nil and message.running==true) or message.state==true,
        computerID=message.computerID or senderID,
        lastUpdate=now()
    }
end

local function processSpawner(senderID,message)
    if message.messageType~="spawner_status" then return end
    rememberComputer(senderID,message)
    local key=tostring(senderID)..":"..tostring(message.spawnerKey)
    spawners[key]={
        name=message.displayName or message.spawnerKey or key,
        state=message.state==true,
        computerID=message.computerID or senderID,
        lastUpdate=now()
    }
end

local function buildResources()
    local time=now()
    local combined={}
    for sourceID,source in pairs(storageSources) do
        for itemID,data in pairs(source) do
            local age=time-(data.lastUpdate or 0)
            if age>sourceRemoveSeconds*1000 then
                source[itemID]=nil
            else
                local r=combined[itemID]
                if not r then
                    r={itemID=itemID,name=data.name or itemID,amount=0,target=0,found=true,online=false,error=nil,machineRunning=false}
                    combined[itemID]=r
                end
                r.amount=r.amount+(tonumber(data.amount) or 0)
                if tonumber(data.target) and tonumber(data.target)>0 then r.target=tonumber(data.target) end
                if data.name and data.name~="" then r.name=data.name end
                if age<=sourceOfflineSeconds*1000 and data.online then r.online=true end
                if not data.found then r.found=false end
                if data.error and data.error~="" then r.error=tostring(data.error) end
            end
        end
    end

    for itemID,m in pairs(machines) do
        if time-(m.lastUpdate or 0)<=sourceRemoveSeconds*1000 and combined[itemID] then
            combined[itemID].machineRunning=m.running==true or m.state==true
        end
    end

    local list={}
    for _,r in pairs(combined) do
        if not r.online then r.error=r.error or "DISCONNECTED"
        elseif not r.found then r.error=r.error or "STORAGE NOT FOUND"
        elseif not r.target or r.target<=0 then r.error=r.error or "NO TARGET" end
        if r.target and r.target>0 then r.percent=math.max(0,math.min(100,r.amount/r.target*100)) end
        list[#list+1]=r
    end
    table.sort(list,function(a,b) return string.lower(a.name or a.itemID)<string.lower(b.name or b.itemID) end)
    return list
end

local function buildSpawners()
    local time=now(); local list={}
    for key,s in pairs(spawners) do
        if time-(s.lastUpdate or 0)>sourceRemoveSeconds*1000 then
            spawners[key]=nil
        else
            list[#list+1]=s
        end
    end
    table.sort(list,function(a,b) return string.lower(a.name)<string.lower(b.name) end)
    return list
end

local function buildComputers()
    local time=now(); local list={{
        id=os.getComputerID(),roleNumber="9",roleName="MASTER CONTROLLER",
        roleFile="master_controller.lua",lastSeen=time,isMaster=true
    }}
    for id,c in pairs(computers) do
        if id~=os.getComputerID() then
            list[#list+1]={
                id=id,roleNumber=c.roleNumber,roleName=c.roleName or "UNKNOWN",
                roleFile=c.roleFile,refreshGroup=c.refreshGroup,
                lastSeen=c.lastSeen or 0,isMaster=false,
                online=(time-(c.lastSeen or 0)<=computerOfflineSeconds*1000)
            }
        end
    end
    table.sort(list,function(a,b) return tonumber(a.id)<tonumber(b.id) end)
    return list
end

local function buildSnapshot()
    return {
        updatedAt=now(),
        masterID=os.getComputerID(),
        resources=buildResources(),
        spawners=buildSpawners(),
        computers=buildComputers(),
        fans=fansState
    }
end

local function publishSnapshot()
    if not githubToken and not loadToken() then
        return false,"NO GITHUB TOKEN"
    end

    if not statusSha then
        local ok,err=getStatusSha()
        if not ok then return false,err end
    end

    local snapshot=buildSnapshot()
    local json=textutils.serialiseJSON(snapshot)
    local body=textutils.serialiseJSON({
        message="Update live ComputerCraft status",
        content=base64(json),
        sha=statusSha,
        branch=branch
    })
    local h=headers(false)
    h["Content-Type"]="application/json"

    local response,err=httpRequest("PUT",apiURL,body,h)
    if not response then return false,err end
    if not response.code or response.code<200 or response.code>=300 then
        statusSha=nil
        return false,"PUBLISH HTTP "..tostring(response.code or "?").." "..tostring(err or "")
    end

    local ok,data=pcall(textutils.unserialiseJSON,response.body)
    if ok and type(data)=="table" and type(data.content)=="table" and type(data.content.sha)=="string" then
        statusSha=data.content.sha
    else
        statusSha=nil
    end

    lastPublish=now()
    lastPublishOK=true
    lastPublishError=nil
    return true
end

local function networkLoop()
    while true do
        local senderID,message,protocol=rednet.receive()
        if type(message)=="table" then
            if protocol==storageStatusProtocol then
                processStorage(senderID,message)
            elseif protocol==machineStatusProtocol then
                processMachine(senderID,message)
            elseif protocol==spawnerStatusProtocol then
                processSpawner(senderID,message)
            elseif protocol==fanProtocol and message.command=="fans" then
                fansState=message.state==true
            elseif protocol==masterProtocol then
                if message.type=="register_client" or message.type=="get_file" then
                    rememberComputer(senderID,message)
                end
            end
        end
    end
end

local function publishLoop()
    sleep(8)
    while true do
        local ok,err=publishSnapshot()
        if not ok then
            lastPublishOK=false
            lastPublishError=tostring(err)
            print("WEB STATUS PUBLISH FAILED: "..lastPublishError)
        else
            print("WEB STATUS PUBLISHED: "..os.date("%H:%M:%S"))
        end
        sleep(publishInterval)
    end
end

if not peripheral.find("modem") then error("No modem found for web status publisher") end
for _,side in ipairs({"back","front","left","right","top","bottom"}) do
    if peripheral.isPresent(side) and peripheral.getType(side)=="modem" and not rednet.isOpen(side) then
        rednet.open(side)
    end
end

print("WEB STATUS PUBLISHER")
print("Publishes docs/status.json every "..publishInterval.." seconds")
print("Master ID: "..os.getComputerID())

parallel.waitForAll(networkLoop,publishLoop)
