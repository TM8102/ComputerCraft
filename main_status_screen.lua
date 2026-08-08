-- =========================================================
-- MAIN STATUS SCREEN
-- Quick-glance display for things that need attention or are ON.
-- Shows:
--   * Low / error storage resources (<75%)
--   * Resource machines currently requested/running
--   * Active mob spawners
--   * Fan state
-- =========================================================

local machineStatusProtocol = "resource_machine_status"
local spawnerStatusProtocol = "spawner_status"
local fanProtocol = "mob_farm_fans"
local systemStatusProtocol = "system_status"

local offlineSeconds = 12
local lowSummaryOfflineSeconds = 8
local renderInterval = 0.5

local modemSide
local monitor
local monitorName

for _,side in ipairs({"top","bottom","left","right","front","back"}) do
    if peripheral.isPresent(side) then
        local p=peripheral.wrap(side)
        local t=peripheral.getType(side)
        if not modemSide and t=="modem" then modemSide=side end
        if not monitor and p and type(p.isColor)=="function" and p.isColor() then
            monitor=p
            monitorName=peripheral.getName(p)
        end
    end
end

if not modemSide then error("No modem found") end
if not monitor then error("No Advanced Monitor found") end
rednet.open(modemSide)
monitor.setTextScale(0.5)

local machines={}
local spawners={}
local fansState=nil
local lowResources={}
local lowSummaryUpdated=0
local totalResources=0
local screenDirty=true

local function now() return os.epoch("utc") end

local function short(text,max)
    text=tostring(text or "")
    if max<=0 then return "" end
    if #text<=max then return text end
    if max<=2 then return text:sub(1,max) end
    return text:sub(1,max-2)..".."
end

local function online(timestamp,seconds)
    timestamp=tonumber(timestamp) or 0
    return timestamp>0 and now()-timestamp<=(seconds or offlineSeconds)*1000
end

local function keyForSpawner(id,key)
    return tostring(id)..":"..tostring(key)
end

local function processMachine(senderID,message)
    if type(message)~="table" or message.messageType~="resource_machine_status"
        or type(message.itemID)~="string" then return end

    local m=machines[message.itemID] or {}
    m.itemID=message.itemID
    m.name=message.displayName or m.name or message.itemID
    m.computerID=message.computerID or senderID
    m.machineKey=message.machineKey or m.machineKey
    m.side=message.side or m.side
    m.role=message.role or m.role
    m.requested=(message.requested~=nil and message.requested==true) or message.state==true
    m.running=(message.running~=nil and message.running==true) or message.state==true
    m.percent=tonumber(message.percent) or m.percent
    m.amount=tonumber(message.amount) or m.amount
    m.target=tonumber(message.target) or m.target
    m.wasActive=m.requested or m.running
    m.lastUpdate=now()
    machines[message.itemID]=m
    screenDirty=true
end

local function processSpawner(senderID,message)
    if type(message)~="table" or message.messageType~="spawner_status" then return end
    local key=keyForSpawner(senderID,message.spawnerKey)
    spawners[key]={
        name=message.displayName or message.spawnerKey or key,
        state=message.state==true,
        computerID=message.computerID or senderID,
        spawnerKey=message.spawnerKey,
        lastUpdate=now()
    }
    screenDirty=true
end

local function processFans(message)
    if type(message)=="table" and message.command=="fans" then
        fansState=message.state==true
        screenDirty=true
    end
end

local function processLowSummary(message)
    if type(message)~="table" or message.messageType~="low_resource_summary"
        or type(message.resources)~="table" then return end

    lowResources={}
    for _,entry in ipairs(message.resources) do
        if type(entry)=="table" then
            lowResources[#lowResources+1]={
                itemID=entry.itemID,
                name=entry.name or entry.itemID or "UNKNOWN",
                amount=tonumber(entry.amount) or 0,
                target=tonumber(entry.target) or 0,
                percent=tonumber(entry.percent),
                error=entry.error,
                machineRunning=entry.machineRunning==true
            }
        end
    end
    totalResources=tonumber(message.totalResources) or totalResources
    lowSummaryUpdated=now()
    screenDirty=true
end

local function fill(x1,y1,x2,y2,bg)
    if x2<x1 or y2<y1 then return end
    monitor.setBackgroundColor(bg)
    for y=y1,y2 do
        monitor.setCursorPos(x1,y)
        monitor.write(string.rep(" ",math.max(0,x2-x1+1)))
    end
end

local function writeAt(x,y,text,fg,bg)
    monitor.setCursorPos(x,y)
    monitor.setTextColor(fg)
    monitor.setBackgroundColor(bg)
    monitor.write(tostring(text))
end

local function center(x1,x2,y,text,fg,bg)
    local width=x2-x1+1
    text=short(text,width)
    writeAt(x1+math.floor((width-#text)/2),y,text,fg,bg)
end

local function activeMachines()
    local rows={}
    for _,m in pairs(machines) do
        local isOnline=online(m.lastUpdate)
        if (isOnline and (m.requested or m.running)) or (not isOnline and m.wasActive) then
            rows[#rows+1]=m
        end
    end
    table.sort(rows,function(a,b)
        local ao=online(a.lastUpdate); local bo=online(b.lastUpdate)
        if ao~=bo then return not ao end
        return string.lower(a.name or a.itemID)<string.lower(b.name or b.itemID)
    end)
    return rows
end

local function activeSpawners()
    local rows={}
    for _,s in pairs(spawners) do
        if s.state and online(s.lastUpdate) then rows[#rows+1]=s end
    end
    table.sort(rows,function(a,b) return string.lower(a.name)<string.lower(b.name) end)
    return rows
end

local function lowColor(resource)
    if resource.error then return colors.orange end
    local p=tonumber(resource.percent) or 0
    if p<25 then return colors.red end
    if p<50 then return colors.red end
    return colors.orange
end

local function lowText(resource,width)
    local status
    if resource.error then
        status=string.upper(tostring(resource.error))
    elseif resource.percent then
        status=string.format("%.0f%%",resource.percent)
    else
        status="LOW"
    end
    if resource.machineRunning then status=status.." *RUNNING" end
    local name=string.upper(resource.name or resource.itemID or "UNKNOWN")
    local room=math.max(6,width-#status-2)
    return short(name,room).."  "..status
end

local function drawHeader(width)
    fill(1,1,width,4,colors.cyan)
    writeAt(3,2,"SYSTEM STATUS",colors.black,colors.cyan)
    local lowOnline=online(lowSummaryUpdated,lowSummaryOfflineSeconds)
    local subtitle
    if not lowOnline then subtitle="STORAGE STATUS WAITING / OFFLINE"
    elseif #lowResources>0 then subtitle=#lowResources.." RESOURCES NEED ATTENTION"
    else subtitle="ALL STORAGE TARGETS HEALTHY" end
    writeAt(3,3,short(subtitle,width-5),colors.gray,colors.cyan)
end

local function drawOverview()
    local width,height=monitor.getSize()
    fill(1,1,width,height,colors.black)
    drawHeader(width)

    local machineRows=activeMachines()
    local spawnerRows=activeSpawners()
    local y=6
    local footerY=height-2

    -- LOW RESOURCES FIRST on STATUS screen only.
    writeAt(2,y,"LOW RESOURCES / STORAGE ALERTS",colors.orange,colors.black)
    y=y+2

    if not online(lowSummaryUpdated,lowSummaryOfflineSeconds) then
        writeAt(3,y,"NO CURRENT SUMMARY FROM MAIN STORAGE",colors.orange,colors.black)
        y=y+2
    elseif #lowResources==0 then
        writeAt(3,y,"NONE - STORAGE HEALTHY",colors.lime,colors.black)
        y=y+2
    else
        local columns=width>=70 and 2 or 1
        local gap=3
        local colWidth=math.floor((width-4-gap*(columns-1))/columns)
        local maxRows=math.max(1,math.floor((footerY-y-9)))
        local shown=math.min(#lowResources,maxRows*columns)

        for i=1,shown do
            local col=(i-1)%columns
            local row=math.floor((i-1)/columns)
            local x=2+col*(colWidth+gap)
            local resource=lowResources[i]
            writeAt(x,y+row,short(lowText(resource,colWidth),colWidth),lowColor(resource),colors.black)
        end
        y=y+math.ceil(shown/columns)+1
        if shown<#lowResources and y<footerY-7 then
            writeAt(3,y,"+ "..(#lowResources-shown).." MORE LOW RESOURCES",colors.orange,colors.black)
            y=y+2
        end
    end

    if y<footerY-5 then
        writeAt(2,y,"ACTIVE RESOURCE MACHINES",colors.lightBlue,colors.black)
        y=y+1
        if #machineRows==0 then
            writeAt(3,y,"NONE",colors.gray,colors.black)
            y=y+2
        else
            local names={}
            for _,m in ipairs(machineRows) do
                local state=not online(m.lastUpdate) and "LOST" or (m.running and "RUNNING" or "REQUESTED")
                names[#names+1]=string.upper(m.name or m.itemID).." ["..state.."]"
            end
            local text=table.concat(names,"  |  ")
            writeAt(3,y,short(text,width-5),colors.lime,colors.black)
            y=y+2
        end
    end

    if y<footerY-2 then
        writeAt(2,y,"ACTIVE SPAWNERS",colors.lightBlue,colors.black)
        y=y+1
        if #spawnerRows==0 then
            writeAt(3,y,"NONE",colors.gray,colors.black)
        else
            local names={}
            for _,s in ipairs(spawnerRows) do names[#names+1]=string.upper(s.name) end
            writeAt(3,y,short(table.concat(names,"  |  "),width-5),colors.lime,colors.black)
        end
    end

    fill(1,footerY,width,height,colors.gray)
    local summary="LOW "..#lowResources.."  ACTIVE MACHINES "..#machineRows.."  ACTIVE SPAWNERS "..#spawnerRows
    writeAt(2,footerY+1,short(summary,width-3),colors.white,colors.gray)
    local fanText="FANS: "..(fansState==nil and "UNKNOWN" or (fansState and "ON" or "OFF"))
    writeAt(2,footerY+2,fanText,fansState and colors.lime or (fansState==nil and colors.orange or colors.white),colors.gray)
end

local function renderLoop()
    while true do
        if screenDirty then
            screenDirty=false
            drawOverview()
        end
        sleep(renderInterval)
        -- redraw periodically so offline states age correctly
        screenDirty=true
    end
end

local function eventLoop()
    while true do
        local event,a,b,c=os.pullEvent()
        if event=="rednet_message" then
            local senderID,message,protocol=a,b,c
            if protocol==machineStatusProtocol then processMachine(senderID,message)
            elseif protocol==spawnerStatusProtocol then processSpawner(senderID,message)
            elseif protocol==fanProtocol then processFans(message)
            elseif protocol==systemStatusProtocol then processLowSummary(message) end
        elseif event=="monitor_resize" and a==monitorName then
            monitor.setTextScale(0.5)
            screenDirty=true
        end
    end
end

drawOverview()
parallel.waitForAll(eventLoop,renderLoop)
