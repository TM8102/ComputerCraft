-- =========================================================
-- MOB CONTROL PANEL
-- 6-line storage-style cards, reliable refresh completion,
-- animated active borders, N/A filtering, maintenance lockout.
-- =========================================================

local monitorSide = "right"
local modemSide = "back"

local controlProtocol = "spawner_control"
local statusProtocol = "spawner_status"
local fanProtocol = "mob_farm_fans"
local machineStatusProtocol = "resource_machine_status"
local configControlProtocol = "spawner_config_control"
local configStatusProtocol = "spawner_config_status"

local pinkSlimeItemID = "industrialforegoing:pink_slime"
local databaseFile = "spawner_registry.db"
local maintenanceFile = "mob_maintenance.db"

local maxSpawners = 40
local offlineSeconds = 12
local removeAfterSeconds = 60
local startupDiscoverySeconds = 15
local discoveryInterval = 5
local animationSpeed = 0.12
local fanShutdownSeconds = 30
local refreshWaitSeconds = 5
local refreshResultSeconds = 3
local unlockReassertSeconds = 4
local maintenanceDebounceSeconds = 1.25
local chaseLength = 8

local monitor = peripheral.wrap(monitorSide)
if not monitor then error("No monitor found on " .. monitorSide) end
if not monitor.isColor() then error("Advanced Monitor required") end
if not peripheral.isPresent(modemSide) then error("No modem found on " .. modemSide) end
rednet.open(modemSide)
monitor.setTextScale(0.5)
local monitorName = peripheral.getName(monitor)

local theme = {
    background=colors.black,
    header=colors.cyan,
    headerText=colors.black,
    accent=colors.blue,
    card=colors.gray,
    emptyCard=colors.black,
    title=colors.white,
    rateText=colors.lightGray,
    placeholder=colors.gray,
    runningBase=colors.green,
    runningChase=colors.lime,
    off=colors.red,
    offlineA=colors.red,
    offlineB=colors.orange,
    emptyBorder=colors.gray,
    masterOn=colors.green,
    masterOff=colors.red,
    fanOn=colors.lime,
    fanOff=colors.red,
    maintenanceOn=colors.orange,
    maintenanceOff=colors.gray,
    refresh=colors.green,
    refreshPressed=colors.lime,
    reboot=colors.blue,
    rebootPressed=colors.lightBlue,
    footer=colors.gray,
    footerText=colors.white,
    popup=colors.gray,
    popupBorder=colors.lightGray,
    popupTitle=colors.cyan,
    success=colors.lime,
    failure=colors.red,
    pending=colors.orange
}

local spawners = {}
local buttons = {masterOn={},masterOff={},fans={},maintenance={},refresh={},reboot={}}
local knownNodes = {}
local fansState = false
local fanShutdownRemaining = 0
local fanShutdownTimer = nil
local animationFrame = 0
local startupCheckComplete = false
local pinkSlimeAutomationActive = false
local pinkSlimeSnapshot = nil
local maintenanceMode = false
local maintenanceUnlockUntil = 0
local maintenanceInputLocked = false
local maintenanceDebounceTimer = nil

local refresh = {
    visible=false,
    running=false,
    started=0,
    finishedAt=0,
    expected={},
    responses={}
}

local function now() return os.epoch("utc") end

local function trim(value)
    value=tostring(value or "")
    return (value:gsub("^%s+",""):gsub("%s+$",""))
end

local function isDisabledName(value)
    local name=string.upper(trim(value))
    return name=="" or name=="N/A" or name=="NA" or name=="NONE" or name=="DISABLED"
end

local function fill(x1,y1,x2,y2,color)
    if x2<x1 or y2<y1 then return end
    monitor.setBackgroundColor(color)
    for y=y1,y2 do
        monitor.setCursorPos(x1,y)
        monitor.write(string.rep(" ",x2-x1+1))
    end
end

local function writeAt(x,y,text,fg,bg)
    monitor.setCursorPos(x,y)
    monitor.setTextColor(fg)
    monitor.setBackgroundColor(bg)
    monitor.write(tostring(text))
end

local function shorten(text,width)
    text=tostring(text or "")
    if width<=0 then return "" end
    if #text<=width then return text end
    if width<=3 then return text:sub(1,width) end
    return text:sub(1,width-2)..".."
end

local function center(x1,x2,y,text,fg,bg)
    local width=x2-x1+1
    text=shorten(text,width)
    writeAt(x1+math.floor((width-#text)/2),y,text,fg,bg)
end

local function border(x1,y1,x2,y2,color)
    fill(x1,y1,x2,y1,color)
    fill(x1,y2,x2,y2,color)
    fill(x1,y1,x1,y2,color)
    fill(x2,y1,x2,y2,color)
end

local function pixel(x,y,color)
    monitor.setCursorPos(x,y)
    monitor.setBackgroundColor(color)
    monitor.write(" ")
end

local function inside(x,y,b)
    return x>=b.x1 and x<=b.x2 and y>=b.y1 and y<=b.y2
end

local function borderPoints(x1,y1,x2,y2)
    local p={}
    for x=x1,x2 do p[#p+1]={x=x,y=y1} end
    for y=y1+1,y2-1 do p[#p+1]={x=x2,y=y} end
    for x=x2,x1,-1 do p[#p+1]={x=x,y=y2} end
    for y=y2-1,y1+1,-1 do p[#p+1]={x=x1,y=y} end
    return p
end

local function saveMaintenance()
    local f=fs.open(maintenanceFile,"w")
    if f then f.write(maintenanceMode and "true" or "false"); f.close() end
end

local function loadMaintenance()
    if not fs.exists(maintenanceFile) then return false end
    local f=fs.open(maintenanceFile,"r")
    if not f then return false end
    local raw=f.readAll(); f.close()
    return raw=="true"
end
maintenanceMode=loadMaintenance()

local function emptySpawner()
    return {
        name="",computerID=0,spawnerKey="",state=false,online=false,
        lastUpdate=0,seenSinceBoot=false,mobsPerSecond=nil,
        x1=0,y1=0,x2=0,y2=0,borderPoints={}
    }
end

for i=1,maxSpawners do spawners[i]=emptySpawner() end

local function clearSpawner(s)
    local fresh=emptySpawner()
    for k in pairs(s) do s[k]=nil end
    for k,v in pairs(fresh) do s[k]=v end
end

local function saveDatabase()
    local saved={}
    for i,s in ipairs(spawners) do
        if s.computerID~=0 and s.spawnerKey~="" and not isDisabledName(s.name) then
            saved[i]={computerID=s.computerID,spawnerKey=s.spawnerKey,name=s.name}
        end
    end
    local f=fs.open(databaseFile,"w")
    if f then f.write(textutils.serialize(saved)); f.close() end
end

local function compactRegistry()
    local keep={}
    for _,s in ipairs(spawners) do
        if s.computerID~=0 and s.spawnerKey~="" and not isDisabledName(s.name) then
            keep[#keep+1]={
                name=s.name,computerID=s.computerID,spawnerKey=s.spawnerKey,
                state=s.state,online=s.online,lastUpdate=s.lastUpdate,
                seenSinceBoot=s.seenSinceBoot,mobsPerSecond=s.mobsPerSecond
            }
        end
    end
    for i=1,maxSpawners do
        clearSpawner(spawners[i])
        local src=keep[i]
        if src then for k,v in pairs(src) do spawners[i][k]=v end end
    end
    saveDatabase()
end

local function loadDatabase()
    if not fs.exists(databaseFile) then return end
    local f=fs.open(databaseFile,"r"); if not f then return end
    local raw=f.readAll(); f.close()
    local ok,saved=pcall(textutils.unserialize,raw)
    if not ok or type(saved)~="table" then return end

    local target=1
    for i=1,maxSpawners do
        local src=saved[i]
        if src and not isDisabledName(src.name) and target<=maxSpawners then
            spawners[target].computerID=tonumber(src.computerID) or 0
            spawners[target].spawnerKey=tostring(src.spawnerKey or "")
            spawners[target].name=trim(src.name)
            target=target+1
        end
    end
    saveDatabase()
end
loadDatabase()

local function findSpawner(id,key)
    for i,s in ipairs(spawners) do
        if s.computerID==id and s.spawnerKey==key then return s,i end
    end
end

local function removeSpawner(id,key)
    local s=findSpawner(id,key)
    if s then
        clearSpawner(s)
        compactRegistry()
        return true
    end
    return false
end

local function registerSpawner(id,key,name)
    name=trim(name)
    if type(key)~="string" or key=="" then return nil end

    if isDisabledName(name) then
        removeSpawner(id,key)
        return nil
    end

    local s,index=findSpawner(id,key)
    if not s then
        for i,c in ipairs(spawners) do
            if c.computerID==0 then s,index=c,i break end
        end
    end
    if not s then return nil end

    s.computerID=id
    s.spawnerKey=key
    s.name=name
    s.online=true
    s.seenSinceBoot=true
    s.lastUpdate=now()
    saveDatabase()
    return s,index
end

local function rememberNode(id,role)
    knownNodes[id]={role=role or "REMOTE_SPAWNER",lastSeen=now()}
end

local function calculateLayout()
    local width,height=monitor.getSize()
    local margin,gap=2,1
    local bw=math.floor((width-margin*2-gap*2)/3)
    if bw<14 then error("Monitor too narrow for control panel") end

    local x1=margin; local x2=x1+bw-1
    local x3=x2+gap+1; local x4=x3+bw-1
    local x5=x4+gap+1; local x6=width-margin

    buttons.masterOn={x1=x1,x2=x2,y1=2,y2=4}
    buttons.masterOff={x1=x3,x2=x4,y1=2,y2=4}
    buttons.fans={x1=x5,x2=x6,y1=2,y2=4}
    buttons.maintenance={x1=x1,x2=x2,y1=6,y2=8}
    buttons.refresh={x1=x3,x2=x4,y1=6,y2=8}
    buttons.reboot={x1=x5,x2=x6,y1=6,y2=8}

    -- Same physical card dimensions as the Main Storage screen.
    -- 5 columns x 8 rows, six lines per card, one blank line between rows.
    local columns,rows=5,8
    local cardHeight,gapX,gapY=6,1,1
    local topY,bottomY=11,height-2
    local availableWidth=width-2
    local availableHeight=bottomY-topY+1
    local cardWidth=math.floor((availableWidth-gapX*(columns-1))/columns)
    if cardWidth<10 then error("Monitor too narrow") end

    local gridWidth=columns*cardWidth+gapX*(columns-1)
    local gridHeight=rows*cardHeight+gapY*(rows-1)
    if gridHeight>availableHeight then error("Monitor too short for 40 six-line cards") end

    local startX=math.floor((width-gridWidth)/2)+1
    local startY=topY+math.floor((availableHeight-gridHeight)/2)

    for i,s in ipairs(spawners) do
        local col=(i-1)%columns
        local row=math.floor((i-1)/columns)
        s.x1=startX+col*(cardWidth+gapX)
        s.y1=startY+row*(cardHeight+gapY)
        s.x2=s.x1+cardWidth-1
        s.y2=s.y1+cardHeight-1
        s.borderPoints=borderPoints(s.x1,s.y1,s.x2,s.y2)
    end
end

local function drawButton(b,text,color)
    fill(b.x1,b.y1,b.x2,b.y2,color)
    center(b.x1,b.x2,b.y1+1,text,colors.white,color)
end

local function drawFanButton()
    if maintenanceMode then drawButton(buttons.fans,"FANS: OFF",theme.fanOff)
    elseif fanShutdownRemaining>0 then drawButton(buttons.fans,"FANS: "..fanShutdownRemaining.."s",theme.fanOn)
    elseif fansState then drawButton(buttons.fans,"FANS: ON",theme.fanOn)
    else drawButton(buttons.fans,"FANS: OFF",theme.fanOff) end
end

local function drawMaintenanceButton()
    drawButton(
        buttons.maintenance,
        maintenanceMode and "MAINTENANCE: ON" or "MAINTENANCE: OFF",
        maintenanceMode and theme.maintenanceOn or theme.maintenanceOff
    )
end

local function drawHeader()
    local width=monitor.getSize()
    fill(1,1,width,10,theme.header)
    local title="SPAWNER CONTROL"
    if maintenanceMode then title=title.."  |  MAINTENANCE LOCKOUT"
    elseif pinkSlimeAutomationActive then title=title.."  |  PINK SLIME AUTO" end
    center(1,width,1,title,theme.headerText,theme.header)

    drawButton(buttons.masterOn,
        pinkSlimeAutomationActive and not maintenanceMode and "AUTO / MASTER ON" or "MASTER ON",
        maintenanceMode and colors.gray or theme.masterOn)
    drawButton(buttons.masterOff,"MASTER OFF",theme.masterOff)
    drawFanButton()
    drawMaintenanceButton()
    drawButton(buttons.refresh,refresh.running and "REFRESHING..." or "REFRESH SPAWNERS",
        refresh.running and theme.refreshPressed or theme.refresh)
    drawButton(buttons.reboot,"REBOOT PANEL",theme.reboot)
    fill(1,10,width,10,theme.accent)
end

local function drawActiveBorder(s)
    border(s.x1,s.y1,s.x2,s.y2,theme.runningBase)
    local points=s.borderPoints
    if not points or #points==0 then return end
    local start=(animationFrame % #points)+1
    for offset=0,chaseLength-1 do
        local idx=((start+offset-2)%#points)+1
        local p=points[idx]
        pixel(p.x,p.y,theme.runningChase)
    end
end

local function rateText(s)
    local rate=tonumber(s.mobsPerSecond)
    if rate then return string.format("%.2f /s",rate) end
    return "-- /s"
end

local function drawSpawner(s,index)
    if s.computerID==0 then
        border(s.x1,s.y1,s.x2,s.y2,theme.emptyBorder)
        fill(s.x1+1,s.y1+1,s.x2-1,s.y2-1,theme.emptyCard)
        center(s.x1+1,s.x2-1,s.y1+2,"SLOT "..index,theme.placeholder,theme.emptyCard)
        return
    end

    -- N/A can never render, even if stale data somehow reaches this point.
    if isDisabledName(s.name) then
        clearSpawner(s)
        return
    end

    fill(s.x1+1,s.y1+1,s.x2-1,s.y2-1,theme.card)

    -- L2 intentionally empty.
    -- L3 mob name.
    center(s.x1+2,s.x2-2,s.y1+2,string.upper(s.name),theme.title,theme.card)
    -- L4 mobs spawned per second.
    center(s.x1+2,s.x2-2,s.y1+3,rateText(s),theme.rateText,theme.card)
    -- L5 intentionally empty.

    if maintenanceMode then
        border(s.x1,s.y1,s.x2,s.y2,colors.orange)
    elseif not s.online then
        border(s.x1,s.y1,s.x2,s.y2,
            math.floor(animationFrame/4)%2==0 and theme.offlineA or theme.offlineB)
    elseif s.state then
        drawActiveBorder(s)
    else
        border(s.x1,s.y1,s.x2,s.y2,theme.off)
    end
end

local function counts()
    local configured,online,running,offline=0,0,0,0
    for _,s in ipairs(spawners) do
        if s.computerID~=0 and not isDisabledName(s.name) then
            configured=configured+1
            if s.online then
                online=online+1
                if s.state then running=running+1 end
            else
                offline=offline+1
            end
        end
    end
    return configured,online,running,offline
end

local function drawFooter()
    local width,height=monitor.getSize()
    fill(1,height-1,width,height,theme.footer)
    local configured,online,running,offline=counts()
    local left="ACTIVE "..running.."   ONLINE "..online.."/"..configured.."   OFFLINE "..offline
    if maintenanceMode then left="MAINTENANCE LOCKOUT   |   "..left end
    writeAt(2,height,shorten(left,width-2),theme.footerText,theme.footer)

    local right=(pinkSlimeAutomationActive and not maintenanceMode and "PINK AUTO   " or "")
        ..(fansState and "FANS ON" or "FANS OFF")
    writeAt(math.max(2,width-#right),height,right,
        maintenanceMode and colors.orange or theme.footerText,theme.footer)
end

local function tableCount(t)
    local c=0
    for _ in pairs(t) do c=c+1 end
    return c
end

local function successCount()
    local c=0
    for _,r in pairs(refresh.responses) do if r.success then c=c+1 end end
    return c
end

local function failureCount()
    local c=0
    for _,r in pairs(refresh.responses) do if not r.success then c=c+1 end end
    return c
end

local function drawRefreshPopup()
    if not refresh.visible then return end
    local width,height=monitor.getSize()
    local pw=math.min(64,width-8)
    local ph=math.min(18,height-10)
    local x1=math.floor((width-pw)/2)+1
    local y1=math.floor((height-ph)/2)+1
    local x2=x1+pw-1
    local y2=y1+ph-1

    border(x1,y1,x2,y2,theme.popupBorder)
    fill(x1+1,y1+1,x2-1,y2-1,theme.popup)
    center(x1+2,x2-2,y1+1,"SPAWNER CONFIG REFRESH",theme.popupTitle,theme.popup)

    local summary
    if refresh.running then
        summary="UPDATING "..tableCount(refresh.responses).." / "..tableCount(refresh.expected)
    else
        summary=successCount().." UPDATED   "..failureCount().." FAILED"
    end
    center(x1+2,x2-2,y1+3,summary,colors.white,theme.popup)

    local ids,seen={},{}
    for id in pairs(refresh.expected) do ids[#ids+1]=id; seen[id]=true end
    for id in pairs(refresh.responses) do if not seen[id] then ids[#ids+1]=id end end
    table.sort(ids)

    local row=y1+5
    for _,id in ipairs(ids) do
        if row>=y2-1 then break end
        local r=refresh.responses[id]
        writeAt(x1+3,row,r and (r.success and "+" or "X") or "?",
            r and (r.success and theme.success or theme.failure) or theme.pending,theme.popup)
        writeAt(x1+5,row,"NODE "..id,colors.white,theme.popup)
        writeAt(x2-10,row,
            r and (r.success and "UPDATED" or "FAILED") or (refresh.running and "WAITING" or "NO REPLY"),
            r and (r.success and theme.success or theme.failure) or theme.pending,theme.popup)
        row=row+1
    end

    center(x1+2,x2-2,y2-1,
        refresh.running and "WAITING FOR NODES..." or "REFRESH COMPLETE",
        refresh.running and theme.pending or theme.success,theme.popup)
end

local function drawScreen()
    local width,height=monitor.getSize()
    fill(1,1,width,height,theme.background)
    drawHeader()
    for i,s in ipairs(spawners) do drawSpawner(s,i) end
    drawFooter()
    drawRefreshPopup()
end

local function sendSpawnerState(s)
    if s.computerID==0 or isDisabledName(s.name) then return end
    local desired=s.state==true
    if maintenanceMode and desired then desired=false; s.state=false end
    rednet.send(s.computerID,{command="spawn",spawnerKey=s.spawnerKey,state=desired},controlProtocol)
end

local function sendFansState()
    if maintenanceMode and fansState then fansState=false end
    rednet.broadcast({command="fans",state=fansState},fanProtocol)
end

local function cancelFanShutdown()
    fanShutdownRemaining=0
    fanShutdownTimer=nil
end

local function setFans(state)
    if maintenanceMode and state then state=false end
    fansState=state==true
    sendFansState()
    drawFanButton()
    drawFooter()
end

local function setAllSpawners(state)
    if maintenanceMode and state then state=false end
    for i,s in ipairs(spawners) do
        if s.computerID~=0 and not isDisabledName(s.name) then
            s.state=state==true
            sendSpawnerState(s)
            drawSpawner(s,i)
        end
    end
end

local function markAllSpawnersOff()
    for _,s in ipairs(spawners) do
        if s.computerID~=0 then s.state=false end
    end
end

local function masterOn()
    if maintenanceMode then return end
    cancelFanShutdown()
    setFans(true)
    setAllSpawners(true)
    rednet.broadcast({command="all_on"},controlProtocol)
    drawHeader(); drawFooter()
end

local function masterOff()
    markAllSpawnersOff()
    rednet.broadcast({command="all_off"},controlProtocol)
    if maintenanceMode then
        cancelFanShutdown(); fansState=false; sendFansState()
    else
        fansState=true; sendFansState()
        fanShutdownRemaining=fanShutdownSeconds
        fanShutdownTimer=os.startTimer(1)
    end
    drawScreen()
end

local function toggleFans()
    if maintenanceMode then return end
    cancelFanShutdown()
    setFans(not fansState)
end

local function sendMaintenanceState(state)
    local message={command="maintenance",state=state==true,timestamp=now()}
    rednet.broadcast(message,controlProtocol)
    for id in pairs(knownNodes) do rednet.send(id,message,controlProtocol) end
end

local function applyMaintenanceLockout()
    cancelFanShutdown()
    pinkSlimeAutomationActive=false
    pinkSlimeSnapshot=nil
    markAllSpawnersOff()
    fansState=false
    drawScreen()
    rednet.broadcast({command="all_off"},controlProtocol)
    sendFansState()
    sendMaintenanceState(true)
end

local function setMaintenance(state)
    state=state==true
    if state==maintenanceMode then
        if state then applyMaintenanceLockout() end
        return
    end

    maintenanceMode=state
    saveMaintenance()
    drawScreen()

    if maintenanceMode then
        maintenanceUnlockUntil=0
        applyMaintenanceLockout()
    else
        maintenanceUnlockUntil=now()+unlockReassertSeconds*1000
        pinkSlimeAutomationActive=false
        pinkSlimeSnapshot=nil
        cancelFanShutdown()
        markAllSpawnersOff()
        fansState=false
        drawScreen()
        sendFansState()
        sendMaintenanceState(false)
        rednet.broadcast({command="all_off"},controlProtocol)
        rednet.broadcast({command="discover"},controlProtocol)
    end
end

local function toggleMaintenance()
    setMaintenance(not maintenanceMode)
end

local function stateKey(s)
    return tostring(s.computerID)..":"..tostring(s.spawnerKey)
end

local function capturePinkSnapshot()
    local snap={fansState=fansState,spawners={}}
    for _,s in ipairs(spawners) do
        if s.computerID~=0 and not isDisabledName(s.name) then
            snap.spawners[stateKey(s)]=s.state==true
        end
    end
    return snap
end

local function restorePinkSnapshot()
    if maintenanceMode then pinkSlimeSnapshot=nil; return end
    local snap=pinkSlimeSnapshot
    if not snap then return end
    cancelFanShutdown()
    for i,s in ipairs(spawners) do
        if s.computerID~=0 and not isDisabledName(s.name) then
            s.state=snap.spawners[stateKey(s)]==true
            sendSpawnerState(s)
            drawSpawner(s,i)
        end
    end
    setFans(snap.fansState==true)
    pinkSlimeSnapshot=nil
    drawHeader(); drawFooter()
end

local function setPinkAutomation(requested)
    requested=requested==true
    if maintenanceMode then
        pinkSlimeAutomationActive=false
        pinkSlimeSnapshot=nil
        return
    end
    if requested and not pinkSlimeAutomationActive then
        pinkSlimeSnapshot=capturePinkSnapshot()
        pinkSlimeAutomationActive=true
        masterOn()
    elseif not requested and pinkSlimeAutomationActive then
        pinkSlimeAutomationActive=false
        restorePinkSnapshot()
    end
end

local function processMachineStatus(m)
    if type(m)=="table" and m.messageType=="resource_machine_status" and m.itemID==pinkSlimeItemID then
        setPinkAutomation(m.state==true)
    end
end

local function requestDiscovery()
    rednet.broadcast({command="discover"},controlProtocol)
    if maintenanceMode then
        sendMaintenanceState(true)
        rednet.broadcast({command="all_off"},controlProtocol)
        fansState=false
        sendFansState()
    elseif maintenanceUnlockUntil>now() then
        sendMaintenanceState(false)
    end
end

local function processManifest(senderID,m)
    rememberNode(senderID,m.role)
    if type(m.enabledKeys)~="table" then return end

    local enabled={}
    for _,key in ipairs(m.enabledKeys) do enabled[key]=true end

    local changed=false
    for _,s in ipairs(spawners) do
        if s.computerID==senderID then
            if enabled[s.spawnerKey] then
                s.seenSinceBoot=true
            else
                clearSpawner(s)
                changed=true
            end
        end
    end

    if changed then
        compactRegistry()
        calculateLayout()
        drawScreen()
    end
end

local function processSpawnerStatus(senderID,m)
    rememberNode(senderID,m.role)
    if m.messageType~="spawner_status" then return end

    if isDisabledName(m.displayName) then
        if removeSpawner(senderID,m.spawnerKey) then
            calculateLayout(); drawScreen()
        end
        return
    end

    local s,index=registerSpawner(senderID,m.spawnerKey,m.displayName)
    if not s then return end

    s.state=m.state==true
    s.online=true
    s.seenSinceBoot=true
    s.lastUpdate=now()
    s.mobsPerSecond=tonumber(m.mobsPerSecond or m.spawnRate)

    if maintenanceMode then
        if s.state then s.state=false; sendSpawnerState(s) end
        rednet.send(senderID,{command="maintenance",state=true,timestamp=now()},controlProtocol)
    else
        if m.maintenance==true or maintenanceUnlockUntil>now() then
            rednet.send(senderID,{command="maintenance",state=false,timestamp=now()},controlProtocol)
        end
        if pinkSlimeAutomationActive and not s.state then
            s.state=true
            sendSpawnerState(s)
        end
    end

    if not refresh.visible then
        drawSpawner(s,index)
        drawFooter()
    end
end

local function finishRefresh()
    if not refresh.running then return end
    refresh.running=false
    refresh.finishedAt=now()
    drawScreen()
end

local function startRefresh()
    refresh.visible=true
    refresh.running=true
    refresh.started=now()
    refresh.finishedAt=0
    refresh.responses={}
    refresh.expected={}

    local t=now()
    for id,info in pairs(knownNodes) do
        if t-(info.lastSeen or 0)<=offlineSeconds*1000 then
            refresh.expected[id]=true
        end
    end

    rednet.broadcast({
        command="force_spawners_refresh",
        requestedBy=os.getComputerID(),
        timestamp=t
    },configControlProtocol)

    drawScreen()
end

local function processRefreshStatus(senderID,m)
    rememberNode(senderID,m.role)
    if m.command~="spawners_refresh_status" then return end

    refresh.visible=true
    refresh.responses[senderID]={
        success=m.success==true,
        error=m.error,
        role=m.role,
        configSource=m.configSource,
        timestamp=now()
    }

    -- Finish immediately on the final reply. Do NOT wait for a timer tick.
    local expected=tableCount(refresh.expected)
    local responses=tableCount(refresh.responses)
    if refresh.running and expected>0 and responses>=expected then
        finishRefresh()
    else
        drawScreen()
    end
end

local function updateRefresh()
    if not refresh.visible then return end
    local t=now()

    if refresh.running then
        local expected=tableCount(refresh.expected)
        local responses=tableCount(refresh.responses)
        if (expected>0 and responses>=expected)
            or t-refresh.started>=refreshWaitSeconds*1000 then
            finishRefresh()
        end
    elseif refresh.finishedAt>0 and t-refresh.finishedAt>=refreshResultSeconds*1000 then
        refresh.visible=false
        drawScreen()
    end
end

local function finishStartupCleanup()
    if startupCheckComplete then return end
    startupCheckComplete=true
    local changed=false
    for _,s in ipairs(spawners) do
        if s.computerID~=0 and (not s.seenSinceBoot or isDisabledName(s.name)) then
            clearSpawner(s)
            changed=true
        end
    end
    if changed then
        compactRegistry(); calculateLayout(); drawScreen()
    end
end

local function updateOffline()
    local t=now()
    local removed=false
    for i,s in ipairs(spawners) do
        if s.computerID~=0 and s.lastUpdate>0 then
            local age=t-s.lastUpdate
            if age>removeAfterSeconds*1000 or isDisabledName(s.name) then
                clearSpawner(s)
                removed=true
            elseif age>offlineSeconds*1000 and s.online then
                s.online=false
                if not refresh.visible then drawSpawner(s,i) end
            end
        end
    end
    if removed then
        compactRegistry(); calculateLayout(); drawScreen()
    elseif not refresh.visible then
        drawFooter()
    end
end

local function rebootComputer()
    drawButton(buttons.reboot,"REBOOTING...",theme.rebootPressed)
    sleep(0.3)
    monitor.setBackgroundColor(colors.black)
    monitor.clear()
    local width,height=monitor.getSize()
    center(1,width,math.floor(height/2),"REBOOTING SPAWNER CONTROL...",colors.cyan,colors.black)
    sleep(0.7)
    os.reboot()
end

calculateLayout()
if maintenanceMode then applyMaintenanceLockout() end
drawScreen()
requestDiscovery()

local animationTimer=os.startTimer(animationSpeed)
local offlineTimer=os.startTimer(2)
local discoveryTimer=os.startTimer(discoveryInterval)
local startupTimer=os.startTimer(startupDiscoverySeconds)
local refreshTimer=os.startTimer(0.25)
local maintenanceTimer=os.startTimer(0.5)

while true do
    local event,a,b,c=os.pullEvent()

    if event=="monitor_touch" and a==monitorName then
        local x,y=b,c

        if inside(x,y,buttons.maintenance) then
            if not maintenanceInputLocked then
                maintenanceInputLocked=true
                maintenanceDebounceTimer=os.startTimer(maintenanceDebounceSeconds)
                toggleMaintenance()
            end

        elseif not refresh.visible then
            if inside(x,y,buttons.masterOn) then masterOn()
            elseif inside(x,y,buttons.masterOff) then masterOff()
            elseif inside(x,y,buttons.fans) then toggleFans()
            elseif inside(x,y,buttons.refresh) then startRefresh()
            elseif inside(x,y,buttons.reboot) then rebootComputer()
            elseif not maintenanceMode then
                for i,s in ipairs(spawners) do
                    if s.computerID~=0 and not isDisabledName(s.name)
                        and x>=s.x1 and x<=s.x2 and y>=s.y1 and y<=s.y2 then
                        s.state=not s.state
                        sendSpawnerState(s)
                        drawSpawner(s,i)
                        drawFooter()
                        break
                    end
                end
            end
        end

    elseif event=="rednet_message" then
        local senderID,message,protocol=a,b,c
        if protocol==statusProtocol and type(message)=="table" then
            if message.messageType=="spawner_manifest" then
                processManifest(senderID,message)
            elseif message.messageType=="spawner_status" then
                processSpawnerStatus(senderID,message)
            end
        elseif protocol==configStatusProtocol and type(message)=="table" then
            processRefreshStatus(senderID,message)
        elseif protocol==machineStatusProtocol and type(message)=="table" then
            processMachineStatus(message)
        end

    elseif event=="timer" and maintenanceDebounceTimer and a==maintenanceDebounceTimer then
        maintenanceInputLocked=false
        maintenanceDebounceTimer=nil
        drawMaintenanceButton()

    elseif event=="timer" and a==animationTimer then
        animationFrame=animationFrame+1
        if not refresh.visible then
            for i,s in ipairs(spawners) do
                if s.computerID~=0 and not isDisabledName(s.name) then
                    drawSpawner(s,i)
                end
            end
        end
        animationTimer=os.startTimer(animationSpeed)

    elseif event=="timer" and a==offlineTimer then
        if maintenanceMode then
            rednet.broadcast({command="all_off"},controlProtocol)
            sendMaintenanceState(true)
        end
        updateOffline()
        offlineTimer=os.startTimer(2)

    elseif event=="timer" and a==discoveryTimer then
        requestDiscovery()
        discoveryTimer=os.startTimer(discoveryInterval)

    elseif event=="timer" and a==startupTimer then
        finishStartupCleanup()

    elseif event=="timer" and a==refreshTimer then
        updateRefresh()
        refreshTimer=os.startTimer(0.25)

    elseif event=="timer" and a==maintenanceTimer then
        if maintenanceMode then sendMaintenanceState(true)
        elseif maintenanceUnlockUntil>now() then sendMaintenanceState(false) end
        maintenanceTimer=os.startTimer(0.5)

    elseif event=="timer" and fanShutdownTimer and a==fanShutdownTimer then
        if maintenanceMode then
            cancelFanShutdown(); fansState=false; sendFansState()
        else
            fanShutdownRemaining=math.max(0,fanShutdownRemaining-1)
            if fanShutdownRemaining>0 then
                fanShutdownTimer=os.startTimer(1)
            else
                fanShutdownTimer=nil
                setFans(false)
            end
        end
        if not refresh.visible then
            drawFanButton(); drawFooter()
        end

    elseif event=="monitor_resize" and a==monitorName then
        monitor.setTextScale(0.5)
        calculateLayout()
        drawScreen()
    end
end
