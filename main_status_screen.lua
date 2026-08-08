-- =========================================================
-- MAIN STATUS SCREEN
-- Quick-glance display for things that need attention or are ON.
-- Also includes a LINKED COMPUTERS page fed by Master Controller.
-- =========================================================

local machineStatusProtocol="resource_machine_status"
local spawnerStatusProtocol="spawner_status"
local fanProtocol="mob_farm_fans"
local systemStatusProtocol="system_status"
local masterProtocol="cc_master_update"

local offlineSeconds=12
local lowSummaryOfflineSeconds=8
local linkedRefreshSeconds=5
local linkedStaleSeconds=25
local renderInterval=0.5

local modemSide,monitor,monitorName
for _,side in ipairs({"top","bottom","left","right","front","back"}) do
    if peripheral.isPresent(side) then
        local p=peripheral.wrap(side)
        local t=peripheral.getType(side)
        if not modemSide and t=="modem" then modemSide=side end
        if not monitor and p and type(p.isColor)=="function" and p.isColor() then
            monitor=p; monitorName=peripheral.getName(p)
        end
    end
end
if not modemSide then error("No modem found") end
if not monitor then error("No Advanced Monitor found") end
rednet.open(modemSide)
monitor.setTextScale(0.5)

local machines,spawners={},{}
local fansState=nil
local lowResources={}
local lowSummaryUpdated=0
local totalResources=0
local linkedComputers={}
local linkedUpdated=0
local linkedMasterID=nil
local currentView="overview"
local screenDirty=true
local buttons={linked={},back={}}

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
local function fill(x1,y1,x2,y2,bg)
    if x2<x1 or y2<y1 then return end
    monitor.setBackgroundColor(bg)
    for y=y1,y2 do monitor.setCursorPos(x1,y); monitor.write(string.rep(" ",math.max(0,x2-x1+1))) end
end
local function writeAt(x,y,text,fg,bg)
    monitor.setCursorPos(x,y); monitor.setTextColor(fg); monitor.setBackgroundColor(bg); monitor.write(tostring(text))
end
local function center(x1,x2,y,text,fg,bg)
    local width=x2-x1+1; text=short(text,width)
    writeAt(x1+math.floor((width-#text)/2),y,text,fg,bg)
end
local function inside(x,y,b) return b and x>=b.x1 and x<=b.x2 and y>=b.y1 and y<=b.y2 end
local function keyForSpawner(id,key) return tostring(id)..":"..tostring(key) end

local function processMachine(senderID,message)
    if type(message)~="table" or message.messageType~="resource_machine_status" or type(message.itemID)~="string" then return end
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
    machines[message.itemID]=m; screenDirty=true
end

local function processSpawner(senderID,message)
    if type(message)~="table" or message.messageType~="spawner_status" then return end
    local key=keyForSpawner(senderID,message.spawnerKey)
    spawners[key]={name=message.displayName or message.spawnerKey or key,state=message.state==true,
        computerID=message.computerID or senderID,spawnerKey=message.spawnerKey,lastUpdate=now()}
    screenDirty=true
end

local function processFans(message)
    if type(message)=="table" and message.command=="fans" then fansState=message.state==true; screenDirty=true end
end

local function processLowSummary(message)
    if type(message)~="table" or message.messageType~="low_resource_summary" or type(message.resources)~="table" then return end
    lowResources={}
    for _,entry in ipairs(message.resources) do
        if type(entry)=="table" then
            lowResources[#lowResources+1]={itemID=entry.itemID,name=entry.name or entry.itemID or "UNKNOWN",
                amount=tonumber(entry.amount) or 0,target=tonumber(entry.target) or 0,percent=tonumber(entry.percent),
                error=entry.error,machineRunning=entry.machineRunning==true}
        end
    end
    totalResources=tonumber(message.totalResources) or totalResources
    lowSummaryUpdated=now(); screenDirty=true
end

local function requestLinkedComputers()
    local requestID=tostring(os.getComputerID())..":"..tostring(now())
    rednet.broadcast({type="get_linked_computers",requestID=requestID,requester=os.getComputerID()},masterProtocol)
end

local function processLinkedComputers(message)
    if type(message)~="table" or message.type~="linked_computers_response" or type(message.computers)~="table" then return end
    linkedComputers={}
    for _,pc in ipairs(message.computers) do
        if type(pc)=="table" and pc.id~=nil then
            linkedComputers[#linkedComputers+1]={id=tonumber(pc.id) or pc.id,roleNumber=pc.roleNumber,
                roleName=pc.roleName or "UNKNOWN",roleFile=pc.roleFile,refreshGroup=pc.refreshGroup,
                lastSeen=tonumber(pc.lastSeen) or 0,isMaster=pc.isMaster==true}
        end
    end
    table.sort(linkedComputers,function(a,b) return tonumber(a.id) < tonumber(b.id) end)
    linkedMasterID=message.masterID
    linkedUpdated=now(); screenDirty=true
end

local function activeMachines()
    local rows={}
    for _,m in pairs(machines) do
        local isOnline=online(m.lastUpdate)
        if (isOnline and (m.requested or m.running)) or (not isOnline and m.wasActive) then rows[#rows+1]=m end
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
    for _,s in pairs(spawners) do if s.state and online(s.lastUpdate) then rows[#rows+1]=s end end
    table.sort(rows,function(a,b) return string.lower(a.name)<string.lower(b.name) end)
    return rows
end

local function lowColor(resource)
    if resource.error then return colors.orange end
    local p=tonumber(resource.percent) or 0
    if p<50 then return colors.red end
    return colors.orange
end

local function lowText(resource,width)
    local status
    if resource.error then status=string.upper(tostring(resource.error))
    elseif resource.percent then status=string.format("%.0f%%",resource.percent)
    else status="LOW" end
    if resource.machineRunning then status=status.." *RUNNING" end
    local name=string.upper(resource.name or resource.itemID or "UNKNOWN")
    return short(name,math.max(6,width-#status-2)).."  "..status
end

local function drawHeader(width,title,subtitle,showLinked,showBack)
    fill(1,1,width,4,colors.cyan)
    writeAt(3,2,title,colors.black,colors.cyan)
    writeAt(3,3,short(subtitle,width-5),colors.gray,colors.cyan)
    if showLinked then
        local bw=22
        buttons.linked={x1=width-bw-2,y1=1,x2=width-2,y2=4}
        fill(buttons.linked.x1,buttons.linked.y1,buttons.linked.x2,buttons.linked.y2,colors.blue)
        center(buttons.linked.x1,buttons.linked.x2,2,"LINKED COMPUTERS",colors.white,colors.blue)
    else buttons.linked={} end
    if showBack then
        local bw=14
        buttons.back={x1=width-bw-2,y1=1,x2=width-2,y2=4}
        fill(buttons.back.x1,buttons.back.y1,buttons.back.x2,buttons.back.y2,colors.blue)
        center(buttons.back.x1,buttons.back.x2,2,"< BACK",colors.white,colors.blue)
    else buttons.back={} end
end

local function drawOverview()
    local width,height=monitor.getSize()
    fill(1,1,width,height,colors.black)
    local lowOnline=online(lowSummaryUpdated,lowSummaryOfflineSeconds)
    local subtitle=not lowOnline and "STORAGE STATUS WAITING / OFFLINE"
        or (#lowResources>0 and (#lowResources.." RESOURCES NEED ATTENTION") or "ALL STORAGE TARGETS HEALTHY")
    drawHeader(width,"SYSTEM STATUS",subtitle,true,false)

    local machineRows=activeMachines(); local spawnerRows=activeSpawners()
    local y=6; local footerY=height-2
    writeAt(2,y,"LOW RESOURCES / STORAGE ALERTS",colors.orange,colors.black); y=y+2
    if not lowOnline then
        writeAt(3,y,"NO CURRENT SUMMARY FROM MAIN STORAGE",colors.orange,colors.black); y=y+2
    elseif #lowResources==0 then
        writeAt(3,y,"NONE - STORAGE HEALTHY",colors.lime,colors.black); y=y+2
    else
        local columns=width>=70 and 2 or 1; local gap=3
        local colWidth=math.floor((width-4-gap*(columns-1))/columns)
        local maxRows=math.max(1,math.floor((footerY-y-9)))
        local shown=math.min(#lowResources,maxRows*columns)
        for i=1,shown do
            local col=(i-1)%columns; local row=math.floor((i-1)/columns)
            local x=2+col*(colWidth+gap); local resource=lowResources[i]
            writeAt(x,y+row,short(lowText(resource,colWidth),colWidth),lowColor(resource),colors.black)
        end
        y=y+math.ceil(shown/columns)+1
        if shown<#lowResources and y<footerY-7 then writeAt(3,y,"+ "..(#lowResources-shown).." MORE LOW RESOURCES",colors.orange,colors.black); y=y+2 end
    end

    if y<footerY-5 then
        writeAt(2,y,"ACTIVE RESOURCE MACHINES",colors.lightBlue,colors.black); y=y+1
        if #machineRows==0 then writeAt(3,y,"NONE",colors.gray,colors.black); y=y+2
        else
            local names={}
            for _,m in ipairs(machineRows) do
                local state=not online(m.lastUpdate) and "LOST" or (m.running and "RUNNING" or "REQUESTED")
                names[#names+1]=string.upper(m.name or m.itemID).." ["..state.."]"
            end
            writeAt(3,y,short(table.concat(names,"  |  "),width-5),colors.lime,colors.black); y=y+2
        end
    end

    if y<footerY-2 then
        writeAt(2,y,"ACTIVE SPAWNERS",colors.lightBlue,colors.black); y=y+1
        if #spawnerRows==0 then writeAt(3,y,"NONE",colors.gray,colors.black)
        else
            local names={}; for _,s in ipairs(spawnerRows) do names[#names+1]=string.upper(s.name) end
            writeAt(3,y,short(table.concat(names,"  |  "),width-5),colors.lime,colors.black)
        end
    end

    fill(1,footerY,width,height,colors.gray)
    writeAt(2,footerY+1,short("LOW "..#lowResources.."  ACTIVE MACHINES "..#machineRows.."  ACTIVE SPAWNERS "..#spawnerRows,width-3),colors.white,colors.gray)
    local fanText="FANS: "..(fansState==nil and "UNKNOWN" or (fansState and "ON" or "OFF"))
    writeAt(2,footerY+2,fanText,fansState and colors.lime or (fansState==nil and colors.orange or colors.white),colors.gray)
end

local function computerState(pc)
    if pc.isMaster then return "ONLINE",colors.lime end
    local age=math.floor(math.max(0,now()-(pc.lastSeen or 0))/1000)
    if age<=linkedStaleSeconds then return "ONLINE",colors.lime end
    if age<=60 then return "STALE "..age.."s",colors.orange end
    return "OFFLINE "..age.."s",colors.red
end

local function drawLinkedComputers()
    local width,height=monitor.getSize()
    fill(1,1,width,height,colors.black)
    local fresh=online(linkedUpdated,linkedRefreshSeconds*3)
    local subtitle=fresh and (#linkedComputers.." COMPUTERS KNOWN TO MASTER") or "WAITING FOR MASTER DIRECTORY..."
    drawHeader(width,"LINKED COMPUTERS",subtitle,false,true)

    local y=6
    if #linkedComputers==0 then
        writeAt(3,y,"NO COMPUTER LIST RECEIVED YET",colors.orange,colors.black)
        requestLinkedComputers()
        return
    end

    local columns=width>=80 and 2 or 1
    local gap=3
    local colWidth=math.floor((width-4-gap*(columns-1))/columns)
    local rowsAvailable=math.max(1,height-8)
    local maxShown=rowsAvailable*columns
    local shown=math.min(#linkedComputers,maxShown)

    for i=1,shown do
        local col=(i-1)%columns
        local row=math.floor((i-1)/columns)
        local x=2+col*(colWidth+gap)
        local pc=linkedComputers[i]
        local state,stateColor=computerState(pc)
        local role=string.upper(pc.roleName or "UNKNOWN")
        local left="PC "..tostring(pc.id).."  "..role
        local stateX=x+colWidth-#state
        writeAt(x,y+row,short(left,math.max(8,colWidth-#state-2)),pc.isMaster and colors.cyan or colors.white,colors.black)
        writeAt(stateX,y+row,state,stateColor,colors.black)
    end

    local footerY=height-1
    fill(1,footerY,width,height,colors.gray)
    local clients=math.max(0,#linkedComputers-1)
    writeAt(2,height,"TOTAL "..#linkedComputers.."  MASTER 1  CLIENTS "..clients.."  MASTER PC "..tostring(linkedMasterID or "?"),colors.white,colors.gray)
end

local function drawCurrent()
    if currentView=="linked" then drawLinkedComputers() else drawOverview() end
end

local function renderLoop()
    while true do
        if screenDirty then screenDirty=false; drawCurrent() end
        sleep(renderInterval)
        screenDirty=true
    end
end

local function linkedRequestLoop()
    while true do
        requestLinkedComputers()
        sleep(linkedRefreshSeconds)
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
            elseif protocol==systemStatusProtocol then processLowSummary(message)
            elseif protocol==masterProtocol then processLinkedComputers(message) end
        elseif event=="monitor_touch" and a==monitorName then
            local x,y=b,c
            if currentView=="overview" and inside(x,y,buttons.linked) then
                currentView="linked"; requestLinkedComputers(); screenDirty=true
            elseif currentView=="linked" and inside(x,y,buttons.back) then
                currentView="overview"; screenDirty=true
            end
        elseif event=="monitor_resize" and a==monitorName then
            monitor.setTextScale(0.5); screenDirty=true
        end
    end
end

drawCurrent()
requestLinkedComputers()
parallel.waitForAll(eventLoop,renderLoop,linkedRequestLoop)
