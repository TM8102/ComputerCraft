-- =========================================================
-- MOB CONTROL PANEL
-- Single-row controls, storage-matched card spacing,
-- maintenance lockout, refresh/debug, N/A filtering,
-- animated active borders, and Pink Slime automation.
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
local discoveryInterval = 5
local animationSpeed = 0.12
local fanShutdownSeconds = 15
local refreshWaitSeconds = 5
local refreshResultSeconds = 3
local maintenanceSyncSeconds = 8
local maintenanceTouchGuardMs = 300
local maintenanceRearmMs = 2000
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

local pinkSlimeAutomationActive = false
local pinkSlimeSnapshot = nil

local maintenanceMode = false
local maintenanceSyncDesired = false
local maintenanceSyncUntil = 0
local maintenanceCommandTimestamp = 0
local lastMaintenanceTouch = 0
local maintenanceRearmUntil = 0

local refresh = {
    visible=false,
    running=false,
    started=0,
    finishedAt=0,
    expected={},
    responses={}
}

local function now()
    return os.epoch("utc")
end

local function trim(value)
    value=tostring(value or "")
    return (value:gsub("^%s+",""):gsub("%s+$",""))
end

local function isDisabledName(value)
    local name=string.upper(trim(value))
    return name==""
        or name=="N/A"
        or name=="NA"
        or name=="NONE"
        or name=="DISABLED"
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
    local points={}
    for x=x1,x2 do points[#points+1]={x=x,y=y1} end
    for y=y1+1,y2-1 do points[#points+1]={x=x2,y=y} end
    for x=x2,x1,-1 do points[#points+1]={x=x,y=y2} end
    for y=y2-1,y1+1,-1 do points[#points+1]={x=x1,y=y} end
    return points
end

local function saveMaintenance()
    local file=fs.open(maintenanceFile,"w")
    if file then
        file.write(maintenanceMode and "true" or "false")
        file.close()
    end
end

local function loadMaintenance()
    if not fs.exists(maintenanceFile) then return false end
    local file=fs.open(maintenanceFile,"r")
    if not file then return false end
    local raw=file.readAll()
    file.close()
    return raw=="true"
end

maintenanceMode=loadMaintenance()
maintenanceSyncDesired=maintenanceMode

local function emptySpawner()
    return {
        name="",
        computerID=0,
        spawnerKey="",
        state=false,
        online=false,
        lastUpdate=0,
        mobsPerSecond=nil,
        x1=0,y1=0,x2=0,y2=0,
        borderPoints={}
    }
end

for i=1,maxSpawners do
    spawners[i]=emptySpawner()
end

local function clearSpawner(spawner)
    local fresh=emptySpawner()
    for key in pairs(spawner) do spawner[key]=nil end
    for key,value in pairs(fresh) do spawner[key]=value end
end

local function saveDatabase()
    local saved={}
    for index,spawner in ipairs(spawners) do
        if spawner.computerID~=0
            and spawner.spawnerKey~=""
            and not isDisabledName(spawner.name) then
            saved[index]={
                computerID=spawner.computerID,
                spawnerKey=spawner.spawnerKey,
                name=spawner.name
            }
        end
    end

    local file=fs.open(databaseFile,"w")
    if file then
        file.write(textutils.serialize(saved))
        file.close()
    end
end

local function compactRegistry()
    local keep={}

    for _,spawner in ipairs(spawners) do
        if spawner.computerID~=0
            and spawner.spawnerKey~=""
            and not isDisabledName(spawner.name) then
            keep[#keep+1]={
                name=spawner.name,
                computerID=spawner.computerID,
                spawnerKey=spawner.spawnerKey,
                state=spawner.state,
                online=spawner.online,
                lastUpdate=spawner.lastUpdate,
                mobsPerSecond=spawner.mobsPerSecond
            }
        end
    end

    for i=1,maxSpawners do
        clearSpawner(spawners[i])
        if keep[i] then
            for key,value in pairs(keep[i]) do
                spawners[i][key]=value
            end
        end
    end

    saveDatabase()
end

local function loadDatabase()
    if not fs.exists(databaseFile) then return end

    local file=fs.open(databaseFile,"r")
    if not file then return end
    local raw=file.readAll()
    file.close()

    local ok,saved=pcall(textutils.unserialize,raw)
    if not ok or type(saved)~="table" then return end

    local target=1
    for i=1,maxSpawners do
        local source=saved[i]
        if source
            and not isDisabledName(source.name)
            and target<=maxSpawners then
            spawners[target].computerID=tonumber(source.computerID) or 0
            spawners[target].spawnerKey=tostring(source.spawnerKey or "")
            spawners[target].name=trim(source.name)
            target=target+1
        end
    end

    saveDatabase()
end

loadDatabase()

local function findSpawner(computerID,spawnerKey)
    for index,spawner in ipairs(spawners) do
        if spawner.computerID==computerID
            and spawner.spawnerKey==spawnerKey then
            return spawner,index
        end
    end
end

local function removeSpawner(computerID,spawnerKey)
    local spawner=findSpawner(computerID,spawnerKey)
    if not spawner then return false end
    clearSpawner(spawner)
    compactRegistry()
    return true
end

local function registerSpawner(computerID,spawnerKey,name)
    name=trim(name)
    if type(spawnerKey)~="string" or spawnerKey=="" then return nil end

    if isDisabledName(name) then
        removeSpawner(computerID,spawnerKey)
        return nil
    end

    local spawner,index=findSpawner(computerID,spawnerKey)
    if not spawner then
        for candidateIndex,candidate in ipairs(spawners) do
            if candidate.computerID==0 then
                spawner=candidate
                index=candidateIndex
                break
            end
        end
    end

    if not spawner then return nil end

    spawner.computerID=computerID
    spawner.spawnerKey=spawnerKey
    spawner.name=name
    spawner.online=true
    spawner.lastUpdate=now()
    saveDatabase()
    return spawner,index
end

local function rememberNode(computerID,role)
    knownNodes[computerID]={
        role=role or "REMOTE_SPAWNER",
        lastSeen=now()
    }
end

-- =========================================================
-- LAYOUT
-- Matches Main Storage panel vertical spacing exactly:
-- header rows 1-5, accent row 6, grid region starts at 7,
-- footer occupies height-1 through height.
-- =========================================================
local function calculateLayout()
    local width,height=monitor.getSize()

    -- Six controls, all on one row.
    local margin=2
    local buttonGap=1
    local buttonCount=6
    local buttonWidth=math.floor(
        (width-(margin*2)-(buttonGap*(buttonCount-1))) / buttonCount
    )

    if buttonWidth<10 then
        error("Monitor too narrow for single-row controls")
    end

    local ordered={
        buttons.masterOn,
        buttons.masterOff,
        buttons.fans,
        buttons.maintenance,
        buttons.refresh,
        buttons.reboot
    }

    local x=margin
    for _,button in ipairs(ordered) do
        button.x1=x
        button.x2=x+buttonWidth-1
        button.y1=2
        button.y2=4
        x=button.x2+buttonGap+1
    end

    -- Same card geometry and vertical grid region as Main Storage.
    local columns=5
    local rows=8
    local cardHeight=6
    local horizontalGap=1
    local verticalGap=1
    local topY=7
    local bottomY=height-2
    local availableWidth=width-2
    local availableHeight=bottomY-topY+1

    local cardWidth=math.floor(
        (availableWidth-horizontalGap*(columns-1))/columns
    )
    if cardWidth<10 then error("Monitor too narrow for cards") end

    local gridWidth=columns*cardWidth+horizontalGap*(columns-1)
    local gridHeight=rows*cardHeight+verticalGap*(rows-1)
    if gridHeight>availableHeight then
        error("Monitor too short for 40 six-line cards with row gaps")
    end

    local startX=math.floor((width-gridWidth)/2)+1
    local startY=topY+math.floor((availableHeight-gridHeight)/2)

    for index,spawner in ipairs(spawners) do
        local column=(index-1)%columns
        local row=math.floor((index-1)/columns)
        spawner.x1=startX+column*(cardWidth+horizontalGap)
        spawner.y1=startY+row*(cardHeight+verticalGap)
        spawner.x2=spawner.x1+cardWidth-1
        spawner.y2=spawner.y1+cardHeight-1
        spawner.borderPoints=borderPoints(
            spawner.x1,spawner.y1,spawner.x2,spawner.y2
        )
    end
end

local function drawButton(button,text,color)
    fill(button.x1,button.y1,button.x2,button.y2,color)
    center(button.x1,button.x2,button.y1+1,text,colors.white,color)
end

local function drawFanButton()
    if maintenanceMode then
        drawButton(buttons.fans,"FANS OFF",theme.fanOff)
    elseif fanShutdownRemaining>0 then
        drawButton(buttons.fans,"FANS "..fanShutdownRemaining.."s",theme.fanOn)
    elseif fansState then
        drawButton(buttons.fans,"FANS ON",theme.fanOn)
    else
        drawButton(buttons.fans,"FANS OFF",theme.fanOff)
    end
end

local function drawMaintenanceButton()
    drawButton(
        buttons.maintenance,
        maintenanceMode and "MAINT ON" or "MAINT OFF",
        maintenanceMode and theme.maintenanceOn or theme.maintenanceOff
    )
end

local function drawHeader()
    local width=monitor.getSize()

    -- Same header/accent height as Main Storage.
    fill(1,1,width,5,theme.header)

    local title="SPAWNER CONTROL"
    if maintenanceMode then
        title=title.." | MAINTENANCE"
    elseif pinkSlimeAutomationActive then
        title=title.." | PINK SLIME AUTO"
    end
    center(1,width,1,title,theme.headerText,theme.header)

    drawButton(
        buttons.masterOn,
        pinkSlimeAutomationActive and not maintenanceMode and "AUTO ON" or "MASTER ON",
        maintenanceMode and colors.gray or theme.masterOn
    )
    drawButton(buttons.masterOff,"MASTER OFF",theme.masterOff)
    drawFanButton()
    drawMaintenanceButton()
    drawButton(
        buttons.refresh,
        refresh.running and "REFRESH..." or "REFRESH",
        refresh.running and theme.refreshPressed or theme.refresh
    )
    drawButton(buttons.reboot,"REBOOT",theme.reboot)

    fill(1,6,width,6,theme.accent)
end

local function drawActiveBorder(spawner)
    border(spawner.x1,spawner.y1,spawner.x2,spawner.y2,theme.runningBase)
    local points=spawner.borderPoints
    if not points or #points==0 then return end

    local start=(animationFrame%#points)+1
    for offset=0,chaseLength-1 do
        local index=((start+offset-2)%#points)+1
        local point=points[index]
        pixel(point.x,point.y,theme.runningChase)
    end
end

local function rateText(spawner)
    local rate=tonumber(spawner.mobsPerSecond)
    if rate then return string.format("%.2f /s",rate) end
    return "-- /s"
end

local function drawSpawner(spawner,index)
    if spawner.computerID==0 then
        border(spawner.x1,spawner.y1,spawner.x2,spawner.y2,theme.emptyBorder)
        fill(spawner.x1+1,spawner.y1+1,spawner.x2-1,spawner.y2-1,theme.emptyCard)
        center(
            spawner.x1+1,spawner.x2-1,spawner.y1+2,
            "SLOT "..index,
            theme.placeholder,
            theme.emptyCard
        )
        return
    end

    if isDisabledName(spawner.name) then
        clearSpawner(spawner)
        return
    end

    fill(spawner.x1+1,spawner.y1+1,spawner.x2-1,spawner.y2-1,theme.card)

    -- L1 border
    -- L2 empty
    -- L3 mob name
    center(
        spawner.x1+2,spawner.x2-2,spawner.y1+2,
        string.upper(spawner.name),
        theme.title,
        theme.card
    )

    -- L4 mobs spawned per second
    center(
        spawner.x1+2,spawner.x2-2,spawner.y1+3,
        rateText(spawner),
        theme.rateText,
        theme.card
    )
    -- L5 empty
    -- L6 border

    if maintenanceMode then
        border(spawner.x1,spawner.y1,spawner.x2,spawner.y2,colors.orange)
    elseif not spawner.online then
        border(
            spawner.x1,spawner.y1,spawner.x2,spawner.y2,
            math.floor(animationFrame/4)%2==0 and theme.offlineA or theme.offlineB
        )
    elseif spawner.state then
        drawActiveBorder(spawner)
    else
        border(spawner.x1,spawner.y1,spawner.x2,spawner.y2,theme.off)
    end
end

local function counts()
    local configured,online,running,offline=0,0,0,0

    for _,spawner in ipairs(spawners) do
        if spawner.computerID~=0 and not isDisabledName(spawner.name) then
            configured=configured+1
            if spawner.online then
                online=online+1
                if spawner.state then running=running+1 end
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
    local left="ACTIVE "..running
        .."   ONLINE "..online.."/"..configured
        .."   OFFLINE "..offline

    if maintenanceMode then
        left="MAINTENANCE LOCKOUT | "..left
    end

    writeAt(2,height,shorten(left,width-2),theme.footerText,theme.footer)

    local right=(pinkSlimeAutomationActive and not maintenanceMode and "PINK AUTO   " or "")
        ..(fansState and "FANS ON" or "FANS OFF")

    writeAt(
        math.max(2,width-#right),height,right,
        maintenanceMode and colors.orange or theme.footerText,
        theme.footer
    )
end

local function tableCount(input)
    local count=0
    for _ in pairs(input) do count=count+1 end
    return count
end

local function successCount()
    local count=0
    for _,response in pairs(refresh.responses) do
        if response.success then count=count+1 end
    end
    return count
end

local function failureCount()
    local count=0
    for _,response in pairs(refresh.responses) do
        if not response.success then count=count+1 end
    end
    return count
end

local function drawRefreshPopup()
    if not refresh.visible then return end

    local width,height=monitor.getSize()
    local popupWidth=math.min(64,width-8)
    local popupHeight=math.min(18,height-10)
    local x1=math.floor((width-popupWidth)/2)+1
    local y1=math.floor((height-popupHeight)/2)+1
    local x2=x1+popupWidth-1
    local y2=y1+popupHeight-1

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

    local ids={}
    local seen={}
    for id in pairs(refresh.expected) do
        ids[#ids+1]=id
        seen[id]=true
    end
    for id in pairs(refresh.responses) do
        if not seen[id] then ids[#ids+1]=id end
    end
    table.sort(ids)

    local row=y1+5
    for _,id in ipairs(ids) do
        if row>=y2-1 then break end
        local result=refresh.responses[id]

        writeAt(
            x1+3,row,
            result and (result.success and "+" or "X") or "?",
            result and (result.success and theme.success or theme.failure) or theme.pending,
            theme.popup
        )
        writeAt(x1+5,row,"NODE "..id,colors.white,theme.popup)
        writeAt(
            x2-10,row,
            result and (result.success and "UPDATED" or "FAILED")
                or (refresh.running and "WAITING" or "NO REPLY"),
            result and (result.success and theme.success or theme.failure) or theme.pending,
            theme.popup
        )
        row=row+1
    end

    center(
        x1+2,x2-2,y2-1,
        refresh.running and "WAITING FOR NODES..." or "REFRESH COMPLETE",
        refresh.running and theme.pending or theme.success,
        theme.popup
    )
end

local function drawScreen()
    local width,height=monitor.getSize()
    fill(1,1,width,height,theme.background)
    drawHeader()
    for index,spawner in ipairs(spawners) do
        drawSpawner(spawner,index)
    end
    drawFooter()
    drawRefreshPopup()
end

local function nextMaintenanceTimestamp()
    local timestamp=now()
    if timestamp<=maintenanceCommandTimestamp then
        timestamp=maintenanceCommandTimestamp+1
    end
    maintenanceCommandTimestamp=timestamp
    return timestamp
end

local function sendMaintenanceState(state,targetID)
    local message={
        command="maintenance",
        state=state==true,
        timestamp=nextMaintenanceTimestamp()
    }

    if targetID then
        rednet.send(targetID,message,controlProtocol)
    else
        rednet.broadcast(message,controlProtocol)
        for id in pairs(knownNodes) do
            rednet.send(id,message,controlProtocol)
        end
    end
end

local function sendFansState()
    if maintenanceMode and fansState then fansState=false end
    rednet.broadcast({command="fans",state=fansState},fanProtocol)
end

local function cancelFanShutdown()
    fanShutdownRemaining=0
    fanShutdownTimer=nil
end

local function markAllSpawnersOff()
    for _,spawner in ipairs(spawners) do
        if spawner.computerID~=0 then
            spawner.state=false
        end
    end
end

local function sendSpawnerState(spawner)
    if spawner.computerID==0 or isDisabledName(spawner.name) then return end

    local desired=spawner.state==true
    if maintenanceMode and desired then
        desired=false
        spawner.state=false
    end

    rednet.send(
        spawner.computerID,
        {
            command="spawn",
            spawnerKey=spawner.spawnerKey,
            state=desired
        },
        controlProtocol
    )
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

    for index,spawner in ipairs(spawners) do
        if spawner.computerID~=0 and not isDisabledName(spawner.name) then
            spawner.state=state==true
            sendSpawnerState(spawner)
            drawSpawner(spawner,index)
        end
    end
end

local function masterOn()
    if maintenanceMode then return end

    cancelFanShutdown()
    setFans(true)
    setAllSpawners(true)
    rednet.broadcast({command="all_on"},controlProtocol)
    drawHeader()
    drawFooter()
end

local function masterOff()
    markAllSpawnersOff()
    rednet.broadcast({command="all_off"},controlProtocol)

    if maintenanceMode then
        cancelFanShutdown()
        fansState=false
        sendFansState()
    else
        fansState=true
        sendFansState()
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

local function beginMaintenanceSync(state,seconds)
    maintenanceSyncDesired=state==true
    maintenanceSyncUntil=now()+seconds*1000
    sendMaintenanceState(maintenanceSyncDesired)
end

local function enterMaintenance()
    if maintenanceMode then return end

    maintenanceMode=true
    saveMaintenance()

    pinkSlimeAutomationActive=false
    pinkSlimeSnapshot=nil
    cancelFanShutdown()
    markAllSpawnersOff()
    fansState=false

    drawScreen()

    rednet.broadcast({command="all_off"},controlProtocol)
    sendFansState()
    beginMaintenanceSync(true,maintenanceSyncSeconds)
end

local function exitMaintenance()
    if not maintenanceMode then return end

    maintenanceMode=false
    saveMaintenance()

    pinkSlimeAutomationActive=false
    pinkSlimeSnapshot=nil
    cancelFanShutdown()
    markAllSpawnersOff()
    fansState=false

    maintenanceRearmUntil=now()+maintenanceRearmMs
    drawScreen()

    sendFansState()
    rednet.broadcast({command="all_off"},controlProtocol)
    beginMaintenanceSync(false,maintenanceSyncSeconds)
    rednet.broadcast({command="discover"},controlProtocol)
end

local function stateKey(spawner)
    return tostring(spawner.computerID)..":"..tostring(spawner.spawnerKey)
end

local function capturePinkSnapshot()
    local snapshot={fansState=fansState,spawners={}}

    for _,spawner in ipairs(spawners) do
        if spawner.computerID~=0 and not isDisabledName(spawner.name) then
            snapshot.spawners[stateKey(spawner)]=spawner.state==true
        end
    end

    return snapshot
end

local function restorePinkSnapshot()
    if maintenanceMode then
        pinkSlimeSnapshot=nil
        return
    end

    local snapshot=pinkSlimeSnapshot
    if not snapshot then return end

    cancelFanShutdown()

    for index,spawner in ipairs(spawners) do
        if spawner.computerID~=0 and not isDisabledName(spawner.name) then
            spawner.state=snapshot.spawners[stateKey(spawner)]==true
            sendSpawnerState(spawner)
            drawSpawner(spawner,index)
        end
    end

    setFans(snapshot.fansState==true)
    pinkSlimeSnapshot=nil
    drawHeader()
    drawFooter()
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

local function processMachineStatus(message)
    if type(message)=="table"
        and message.messageType=="resource_machine_status"
        and message.itemID==pinkSlimeItemID then
        setPinkAutomation(message.state==true)
    end
end

local function requestDiscovery()
    rednet.broadcast({command="discover"},controlProtocol)
end

local function processManifest(senderID,message)
    rememberNode(senderID,message.role)
    if type(message.enabledKeys)~="table" then return end

    local enabled={}
    for _,key in ipairs(message.enabledKeys) do
        enabled[key]=true
    end

    local changed=false
    for _,spawner in ipairs(spawners) do
        if spawner.computerID==senderID and not enabled[spawner.spawnerKey] then
            clearSpawner(spawner)
            changed=true
        end
    end

    if changed then
        compactRegistry()
        calculateLayout()
        drawScreen()
    end
end

local function processSpawnerStatus(senderID,message)
    rememberNode(senderID,message.role)
    if message.messageType~="spawner_status" then return end

    if isDisabledName(message.displayName) then
        if removeSpawner(senderID,message.spawnerKey) then
            calculateLayout()
            drawScreen()
        end
        return
    end

    local spawner,index=registerSpawner(
        senderID,
        message.spawnerKey,
        message.displayName
    )
    if not spawner then return end

    spawner.state=message.state==true
    spawner.online=true
    spawner.lastUpdate=now()
    spawner.mobsPerSecond=tonumber(message.mobsPerSecond or message.spawnRate)

    if message.maintenance~=maintenanceMode then
        sendMaintenanceState(maintenanceMode,senderID)
    end

    if maintenanceMode and spawner.state then
        spawner.state=false
        sendSpawnerState(spawner)
    elseif not maintenanceMode
        and pinkSlimeAutomationActive
        and not spawner.state then
        spawner.state=true
        sendSpawnerState(spawner)
    end

    if not refresh.visible then
        drawSpawner(spawner,index)
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

    local timestamp=now()
    for id,info in pairs(knownNodes) do
        if timestamp-(info.lastSeen or 0)<=offlineSeconds*1000 then
            refresh.expected[id]=true
        end
    end

    rednet.broadcast(
        {
            command="force_spawners_refresh",
            requestedBy=os.getComputerID(),
            timestamp=timestamp
        },
        configControlProtocol
    )

    if tableCount(refresh.expected)==0 then
        finishRefresh()
    else
        drawScreen()
    end
end

local function processRefreshStatus(senderID,message)
    rememberNode(senderID,message.role)
    if message.command~="spawners_refresh_status" then return end

    refresh.visible=true
    refresh.responses[senderID]={
        success=message.success==true,
        error=message.error,
        role=message.role,
        configSource=message.configSource,
        timestamp=now()
    }

    if refresh.running
        and tableCount(refresh.responses)>=tableCount(refresh.expected) then
        finishRefresh()
    else
        drawScreen()
    end
end

local function updateRefresh()
    if not refresh.visible then return end

    local timestamp=now()

    if refresh.running then
        if tableCount(refresh.responses)>=tableCount(refresh.expected)
            or timestamp-refresh.started>=refreshWaitSeconds*1000 then
            finishRefresh()
        end
    elseif refresh.finishedAt>0
        and timestamp-refresh.finishedAt>=refreshResultSeconds*1000 then
        refresh.visible=false
        drawScreen()
    end
end

local function updateOffline()
    local timestamp=now()
    local removed=false

    for index,spawner in ipairs(spawners) do
        if spawner.computerID~=0 then
            local age=timestamp-(spawner.lastUpdate or 0)

            if isDisabledName(spawner.name)
                or (spawner.lastUpdate>0 and age>removeAfterSeconds*1000) then
                clearSpawner(spawner)
                removed=true
            elseif spawner.lastUpdate>0
                and age>offlineSeconds*1000
                and spawner.online then
                spawner.online=false
                if not refresh.visible then
                    drawSpawner(spawner,index)
                end
            end
        end
    end

    if removed then
        compactRegistry()
        calculateLayout()
        drawScreen()
    elseif not refresh.visible then
        drawFooter()
    end
end

local function rebootComputer()
    drawButton(buttons.reboot,"REBOOTING",theme.rebootPressed)
    sleep(0.3)
    monitor.setBackgroundColor(colors.black)
    monitor.clear()
    local width,height=monitor.getSize()
    center(
        1,width,math.floor(height/2),
        "REBOOTING SPAWNER CONTROL...",
        colors.cyan,
        colors.black
    )
    sleep(0.7)
    os.reboot()
end

calculateLayout()

if maintenanceMode then
    markAllSpawnersOff()
    fansState=false
    beginMaintenanceSync(true,maintenanceSyncSeconds)
end

drawScreen()
requestDiscovery()

local animationTimer=os.startTimer(animationSpeed)
local offlineTimer=os.startTimer(2)
local discoveryTimer=os.startTimer(discoveryInterval)
local refreshTimer=os.startTimer(0.25)
local maintenanceSyncTimer=os.startTimer(0.5)

while true do
    local event,a,b,c=os.pullEvent()

    if event=="monitor_touch" and a==monitorName then
        local x,y=b,c
        local timestamp=now()

        if inside(x,y,buttons.maintenance) then
            if timestamp-lastMaintenanceTouch>=maintenanceTouchGuardMs then
                lastMaintenanceTouch=timestamp

                if maintenanceMode then
                    exitMaintenance()
                elseif timestamp>=maintenanceRearmUntil then
                    enterMaintenance()
                end
            end

        elseif not refresh.visible then
            if inside(x,y,buttons.masterOn) then
                masterOn()
            elseif inside(x,y,buttons.masterOff) then
                masterOff()
            elseif inside(x,y,buttons.fans) then
                toggleFans()
            elseif inside(x,y,buttons.refresh) then
                startRefresh()
            elseif inside(x,y,buttons.reboot) then
                rebootComputer()
            elseif not maintenanceMode then
                for index,spawner in ipairs(spawners) do
                    if spawner.computerID~=0
                        and not isDisabledName(spawner.name)
                        and x>=spawner.x1 and x<=spawner.x2
                        and y>=spawner.y1 and y<=spawner.y2 then
                        spawner.state=not spawner.state
                        sendSpawnerState(spawner)
                        drawSpawner(spawner,index)
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

    elseif event=="timer" and a==animationTimer then
        animationFrame=animationFrame+1

        if not refresh.visible then
            for index,spawner in ipairs(spawners) do
                if spawner.computerID~=0 and not isDisabledName(spawner.name) then
                    drawSpawner(spawner,index)
                end
            end
        end

        animationTimer=os.startTimer(animationSpeed)

    elseif event=="timer" and a==offlineTimer then
        updateOffline()
        offlineTimer=os.startTimer(2)

    elseif event=="timer" and a==discoveryTimer then
        requestDiscovery()
        discoveryTimer=os.startTimer(discoveryInterval)

    elseif event=="timer" and a==refreshTimer then
        updateRefresh()
        refreshTimer=os.startTimer(0.25)

    elseif event=="timer" and a==maintenanceSyncTimer then
        if now()<maintenanceSyncUntil then
            sendMaintenanceState(maintenanceSyncDesired)
            if maintenanceSyncDesired then
                rednet.broadcast({command="all_off"},controlProtocol)
                fansState=false
                sendFansState()
            end
        end
        maintenanceSyncTimer=os.startTimer(0.5)

    elseif event=="timer" and fanShutdownTimer and a==fanShutdownTimer then
        if maintenanceMode then
            cancelFanShutdown()
            fansState=false
            sendFansState()
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
            drawFanButton()
            drawFooter()
        end

    elseif event=="monitor_resize" and a==monitorName then
        monitor.setTextScale(0.5)
        calculateLayout()
        drawScreen()
    end
end
