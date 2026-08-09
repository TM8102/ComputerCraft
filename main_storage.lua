-- =========================================================
-- MAIN STORAGE SCREEN
-- Stable alphabetical card positions, 40 cards/page.
-- Low resources are reported to the Main Status Screen.
--
-- IMPORTANT: all monitor drawing is handled by ONE display loop.
-- This prevents full-screen redraws and animation writes from
-- fighting each other and freezing/chopping the chase animation.
-- =========================================================

local monitorSide = "right"
local modemSide = "back"

local storageControlProtocol = "inventory_control"
local storageStatusProtocol = "inventory_status"
local machineControlProtocol = "resource_machine_control"
local machineStatusProtocol = "resource_machine_status"
local configControlProtocol = "config_control"
local configStatusProtocol = "config_status"
local systemStatusProtocol = "system_status"

local cardsPerPage = 40
local pageSeconds = 15
local sourceOfflineSeconds = 12
local sourceRemoveSeconds = 60
local discoveryInterval = 5
local animationSpeed = 0.12
local fullRedrawInterval = 0.65
local flashInterval = 0.48
local chaseLength = 6
local lowSummaryInterval = 2
local refreshWaitSeconds = 5
local refreshResultSeconds = 10

local monitor = peripheral.wrap(monitorSide)
if not monitor then error("No monitor found on " .. monitorSide) end
if not monitor.isColor() then error("Advanced Monitor required") end
monitor.setTextScale(0.5)
local monitorName = peripheral.getName(monitor)

if not peripheral.isPresent(modemSide) then error("No modem found on " .. modemSide) end
rednet.open(modemSide)

local theme = {
    background=colors.black, header=colors.cyan, headerText=colors.black,
    headerSubtext=colors.gray, accent=colors.blue, card=colors.gray,
    emptyCard=colors.black, title=colors.white, amountText=colors.white,
    full=colors.lime, good=colors.lightBlue, warning=colors.orange,
    low=colors.red, criticalRed=colors.red, criticalBlack=colors.black,
    errorRed=colors.red, errorOrange=colors.orange, machineChase=colors.lime,
    progressBackground=colors.black, progressFull=colors.lime,
    progressGood=colors.lightBlue, progressWarning=colors.orange,
    progressLow=colors.red, emptyBorder=colors.gray,
    placeholderText=colors.gray, rebootButton=colors.blue,
    rebootPressed=colors.lightBlue, refreshButton=colors.green,
    refreshPressed=colors.lime, popupBackground=colors.gray,
    popupBorder=colors.lightGray, popupTitle=colors.cyan,
    success=colors.lime, failure=colors.red, pending=colors.orange,
    footer=colors.gray, footerText=colors.white
}

local storageSources = {}
local machineStates = {}
local cards = {}
local cardOrder = {}
local layoutSlots = {}
local knownComputers = {}
local rebootButton = {}
local refreshButton = {}
local refresh = {visible=false,running=false,started=0,finishedAt=0,responses={},expected={}}

local currentPage = 1
local pageChangedAt = os.epoch("utc")
local screenDirty = true
local lastFullDraw = 0
local flashState = false
local lastFlash = os.epoch("utc")

local function now() return os.epoch("utc") end

local function rememberComputer(id,role)
    local info=knownComputers[id] or {}
    info.role=role or info.role or "NODE"
    info.lastSeen=now()
    knownComputers[id]=info
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

local function commaNumber(value)
    value=math.floor(tonumber(value) or 0)
    local text=tostring(value)
    while true do
        local out,count=text:gsub("^(-?%d+)(%d%d%d)","%1,%2")
        text=out
        if count==0 then break end
    end
    return text
end

local function ensureSource(id)
    if not storageSources[id] then storageSources[id]={} end
    return storageSources[id]
end

local function processStorageManifest(senderID,message)
    rememberComputer(senderID,message.role or "STORAGE")
    if type(message.enabledKeys)~="table" then return end
    local enabled={}
    for _,itemID in ipairs(message.enabledKeys) do
        if type(itemID)=="string" then enabled[itemID]=true end
    end
    local source=ensureSource(senderID)
    for itemID in pairs(source) do
        if not enabled[itemID] then source[itemID]=nil end
    end
    screenDirty=true
end

local function processInventoryUpdate(senderID,message)
    rememberComputer(senderID,message.role or "STORAGE")
    local itemID=message.itemID or message.storageKey
    if type(itemID)~="string" then return end
    local source=ensureSource(senderID)
    source[itemID]={
        itemID=itemID,
        displayName=message.displayName or itemID,
        amount=tonumber(message.amount) or 0,
        targetAmount=tonumber(message.targetAmount or message.target) or 0,
        found=message.found~=false,
        online=message.online~=false,
        error=message.error,
        lastUpdate=now()
    }
    screenDirty=true
end

local function processMachineStatus(senderID,message)
    rememberComputer(senderID,message.role or "NODE")
    if type(message.itemID)~="string" then return end
    machineStates[message.itemID]={
        running=message.state==true,
        computerID=senderID,
        machineKey=message.machineKey,
        side=message.side,
        lastUpdate=now()
    }
    screenDirty=true
end

local function processRefreshStatus(senderID,message)
    rememberComputer(senderID,message.role or "NODE")
    if message.command~="targets_refresh_status" then return end
    refresh.visible=true
    refresh.responses[senderID]={
        success=message.success==true,
        error=message.error,
        role=message.role or (knownComputers[senderID] and knownComputers[senderID].role) or "NODE",
        timestamp=now()
    }
    screenDirty=true
end

local function percentage(card)
    local amount=tonumber(card.amount)
    local target=tonumber(card.targetAmount)
    if not amount or not target or target<=0 then return nil end
    return math.max(0,math.min(100,amount/target*100))
end

local function hasError(card)
    return not card.online
        or not card.found
        or (card.error and card.error~="")
        or not card.targetAmount
        or tonumber(card.targetAmount)<=0
end

local function errorText(card)
    if not card.online then return "DISCONNECTED" end
    if card.error and card.error~="" then return string.upper(tostring(card.error)) end
    if not card.found then return "STORAGE NOT FOUND" end
    if not card.targetAmount or tonumber(card.targetAmount)<=0 then return "NO TARGET" end
    return "ERROR"
end

local function rebuildCards()
    local time=now()
    local combined={}

    for _,source in pairs(storageSources) do
        for itemID,data in pairs(source) do
            local age=time-(data.lastUpdate or 0)
            if age>sourceRemoveSeconds*1000 then
                source[itemID]=nil
            else
                local card=combined[itemID]
                if not card then
                    card={itemID=itemID,name=data.displayName or itemID,amount=0,targetAmount=0,
                        found=true,online=false,error=nil,machineRunning=false}
                    combined[itemID]=card
                end
                card.amount=card.amount+(tonumber(data.amount) or 0)
                if tonumber(data.targetAmount) and tonumber(data.targetAmount)>0 then
                    card.targetAmount=tonumber(data.targetAmount)
                end
                if data.displayName and data.displayName~="" then card.name=data.displayName end
                if age<=sourceOfflineSeconds*1000 and data.online then card.online=true end
                if not data.found then card.found=false end
                if data.error and data.error~="" then card.error=data.error end
            end
        end
    end

    for itemID,machine in pairs(machineStates) do
        local age=time-(machine.lastUpdate or 0)
        if age>sourceRemoveSeconds*1000 then
            machineStates[itemID]=nil
        elseif combined[itemID] then
            combined[itemID].machineRunning=machine.running==true
        end
    end

    cards=combined
    cardOrder={}
    for itemID in pairs(cards) do cardOrder[#cardOrder+1]=itemID end
    table.sort(cardOrder,function(a,b)
        local an=string.lower(cards[a].name or a)
        local bn=string.lower(cards[b].name or b)
        if an~=bn then return an<bn end
        return a<b
    end)

    local pages=math.max(1,math.ceil(#cardOrder/cardsPerPage))
    if currentPage>pages then currentPage=pages; pageChangedAt=time end
end

local function borderColor(card)
    if hasError(card) then return flashState and theme.errorRed or theme.errorOrange end
    local p=percentage(card)
    if not p then return flashState and theme.errorRed or theme.errorOrange end
    if p<25 then return flashState and theme.criticalRed or theme.criticalBlack end
    if p<50 then return theme.low end
    if p<75 then return theme.warning end
    if p>=100 then return theme.full end
    return theme.good
end

local function progressColor(card)
    local p=percentage(card)
    if not p or p<50 then return theme.progressLow end
    if p<75 then return theme.progressWarning end
    if p>=100 then return theme.progressFull end
    return theme.progressGood
end

local function pageCount() return math.max(1,math.ceil(#cardOrder/cardsPerPage)) end
local function firstIndex() return (currentPage-1)*cardsPerPage+1 end
local function lastIndex() return math.min(#cardOrder,currentPage*cardsPerPage) end

local function calculateLayout()
    local width,height=monitor.getSize()
    local columns,rows=5,8
    local cardHeight=6
    local horizontalGap,verticalGap=1,1
    local topY,bottomY=7,height-2
    local availableWidth=width-2
    local availableHeight=bottomY-topY+1
    local cardWidth=math.floor((availableWidth-horizontalGap*(columns-1))/columns)
    if cardWidth<10 then error("Monitor too narrow") end
    local totalGridWidth=columns*cardWidth+horizontalGap*(columns-1)
    local totalGridHeight=rows*cardHeight+verticalGap*(rows-1)
    if totalGridHeight>availableHeight then error("Monitor too short for 40 six-line cards with row gaps") end
    local startX=math.floor((width-totalGridWidth)/2)+1
    local startY=topY+math.floor((availableHeight-totalGridHeight)/2)

    layoutSlots={}
    for index=1,cardsPerPage do
        local column=(index-1)%columns
        local row=math.floor((index-1)/columns)
        local x1=startX+column*(cardWidth+horizontalGap)
        local y1=startY+row*(cardHeight+verticalGap)
        local x2=x1+cardWidth-1
        local y2=y1+cardHeight-1
        layoutSlots[index]={x1=x1,y1=y1,x2=x2,y2=y2,points=borderPoints(x1,y1,x2,y2)}
    end

    rebootButton.x2=width-2; rebootButton.x1=rebootButton.x2-13
    rebootButton.y1=2; rebootButton.y2=4
    refreshButton.x2=rebootButton.x1-2; refreshButton.x1=refreshButton.x2-23
    refreshButton.y1=2; refreshButton.y2=4
end

local function drawButton(button,text,color)
    fill(button.x1,button.y1,button.x2,button.y2,color)
    center(button.x1,button.x2,button.y1+1,text,colors.white,color)
end

local function drawHeader()
    local width=monitor.getSize()
    fill(1,1,width,5,theme.header)
    writeAt(3,2,"STORAGE MANAGEMENT",theme.headerText,theme.header)
    local subtitle="FIXED RESOURCE POSITIONS"
    local pages=pageCount()
    if pages>1 then
        local remaining=math.max(0,pageSeconds-math.floor((now()-pageChangedAt)/1000))
        subtitle=subtitle.."  |  PAGE "..currentPage.."/"..pages.."  |  NEXT "..remaining.."s"
    end
    writeAt(3,3,shorten(subtitle,math.max(10,refreshButton.x1-5)),theme.headerSubtext,theme.header)
    drawButton(refreshButton,refresh.running and "REFRESHING..." or "REFRESH TARGETS",
        refresh.running and theme.refreshPressed or theme.refreshButton)
    drawButton(rebootButton,"REBOOT",theme.rebootButton)
    fill(1,6,width,6,theme.accent)
end

local function drawProgress(card)
    local y=card.y1+3
    local x1=card.x1+2
    local x2=card.x2-2
    local width=x2-x1+1
    fill(x1,y,x2,y,theme.progressBackground)

    if hasError(card) then
        center(x1,x2,y,errorText(card),theme.amountText,theme.progressBackground)
        return
    end

    local p=percentage(card) or 0
    local filled=math.floor(width*p/100)
    if p>0 and filled<1 then filled=1 end
    if filled>width then filled=width end
    local color=progressColor(card)
    if filled>0 then fill(x1,y,x1+filled-1,y,color) end

    local text=shorten(commaNumber(card.amount).." / "..commaNumber(card.targetAmount),width)
    local tx=x1+math.floor((width-#text)/2)
    for i=1,#text do
        local x=tx+i-1
        writeAt(x,y,text:sub(i,i),theme.amountText,(filled>0 and x<=x1+filled-1) and color or theme.progressBackground)
    end
end

local function drawStaticCard(card,slot)
    card.x1=slot.x1; card.y1=slot.y1; card.x2=slot.x2; card.y2=slot.y2; card.borderPoints=slot.points
    fill(card.x1+1,card.y1+1,card.x2-1,card.y2-1,theme.card)
    center(card.x1+2,card.x2-2,card.y1+2,string.upper(card.name or "STORAGE"),theme.title,theme.card)
    drawProgress(card)
    border(card.x1,card.y1,card.x2,card.y2,borderColor(card))
end

local function drawPlaceholder(slot,index)
    border(slot.x1,slot.y1,slot.x2,slot.y2,theme.emptyBorder)
    fill(slot.x1+1,slot.y1+1,slot.x2-1,slot.y2-1,theme.emptyCard)
    center(slot.x1+1,slot.x2-1,slot.y1+2,"AVAILABLE "..index,theme.placeholderText,theme.emptyCard)
end

local function countErrors()
    local n=0
    for _,id in ipairs(cardOrder) do if cards[id] and hasError(cards[id]) then n=n+1 end end
    return n
end

local function countRunning()
    local n=0
    for _,id in ipairs(cardOrder) do if cards[id] and cards[id].machineRunning then n=n+1 end end
    return n
end

local function countLow()
    local n=0
    for _,id in ipairs(cardOrder) do
        local card=cards[id]
        local p=card and percentage(card)
        if card and (hasError(card) or (p and p<75)) then n=n+1 end
    end
    return n
end

local function drawFooter()
    local width,height=monitor.getSize()
    fill(1,height-1,width,height,theme.footer)
    local text="RESOURCES "..#cardOrder.."  LOW "..countLow().."  ERRORS "..countErrors().."  RUNNING "..countRunning()
    if pageCount()>1 then text=text.."  PAGE "..currentPage.."/"..pageCount() end
    writeAt(2,height,shorten(text,width-2),theme.footerText,theme.footer)
end

local function tableCount(t) local n=0 for _ in pairs(t) do n=n+1 end return n end
local function successCount() local n=0 for _,r in pairs(refresh.responses) do if r.success then n=n+1 end end return n end
local function failureCount() local n=0 for _,r in pairs(refresh.responses) do if not r.success then n=n+1 end end return n end

local function drawRefreshPopup()
    if not refresh.visible then return end
    local width,height=monitor.getSize()
    local popupWidth=math.min(60,width-8)
    local popupHeight=math.min(18,height-10)
    local x1=math.floor((width-popupWidth)/2)+1
    local y1=math.floor((height-popupHeight)/2)+1
    local x2=x1+popupWidth-1
    local y2=y1+popupHeight-1
    border(x1,y1,x2,y2,theme.popupBorder)
    fill(x1+1,y1+1,x2-1,y2-1,theme.popupBackground)
    center(x1+2,x2-2,y1+1,"TARGET REFRESH",theme.popupTitle,theme.popupBackground)
    local summary=refresh.running and ("UPDATING... "..tableCount(refresh.responses).." / "..tableCount(refresh.expected))
        or (successCount().." UPDATED / "..failureCount().." FAILED")
    center(x1+2,x2-2,y1+3,summary,colors.white,theme.popupBackground)

    local ids,seen={},{}
    for id in pairs(refresh.expected) do ids[#ids+1]=id; seen[id]=true end
    for id in pairs(refresh.responses) do if not seen[id] then ids[#ids+1]=id end end
    table.sort(ids)
    local row=y1+5
    for _,id in ipairs(ids) do
        if row>=y2-1 then break end
        local result=refresh.responses[id]
        local info=knownComputers[id]
        local role=result and result.role or (info and info.role) or "NODE"
        writeAt(x1+3,row,result and (result.success and "+" or "X") or "?",
            result and (result.success and theme.success or theme.failure) or theme.pending,theme.popupBackground)
        writeAt(x1+5,row,shorten(role.." "..id,popupWidth-18),colors.white,theme.popupBackground)
        writeAt(x2-9,row,result and (result.success and "UPDATED" or "FAILED") or (refresh.running and "WAITING" or "NO REPLY"),
            result and (result.success and theme.success or theme.failure) or theme.pending,theme.popupBackground)
        row=row+1
    end
end

local function fullDraw()
    rebuildCards()
    local width,height=monitor.getSize()
    fill(1,1,width,height,theme.background)
    drawHeader()

    local slotIndex=1
    for globalIndex=firstIndex(),lastIndex() do
        local slot=layoutSlots[slotIndex]
        local itemID=cardOrder[globalIndex]
        if slot and itemID and cards[itemID] then drawStaticCard(cards[itemID],slot) end
        slotIndex=slotIndex+1
    end
    while slotIndex<=cardsPerPage do
        local slot=layoutSlots[slotIndex]
        if slot then drawPlaceholder(slot,(currentPage-1)*cardsPerPage+slotIndex) end
        slotIndex=slotIndex+1
    end
    drawFooter()
    drawRefreshPopup()
end

local function drawAnimations()
    if refresh.visible then return end

    -- Time-based frame: even if ComputerCraft gets busy for a moment,
    -- the animation resumes at the correct position instead of freezing.
    local frame=math.floor(now()/(animationSpeed*1000))
    local slotIndex=1
    for globalIndex=firstIndex(),lastIndex() do
        local itemID=cardOrder[globalIndex]
        local card=cards[itemID]
        local slot=layoutSlots[slotIndex]
        if card and slot then
            card.x1=slot.x1; card.y1=slot.y1; card.x2=slot.x2; card.y2=slot.y2; card.borderPoints=slot.points
            if card.machineRunning then
                -- Erase the previous chase first by restoring the base border.
                border(card.x1,card.y1,card.x2,card.y2,borderColor(card))
                local points=card.borderPoints
                if points and #points>0 then
                    local start=(frame%#points)+1
                    for offset=0,chaseLength-1 do
                        local index=((start+offset-2)%#points)+1
                        local point=points[index]
                        pixel(point.x,point.y,theme.machineChase)
                    end
                end
            elseif hasError(card) or ((percentage(card) or 100)<25) then
                border(card.x1,card.y1,card.x2,card.y2,borderColor(card))
            end
        end
        slotIndex=slotIndex+1
    end
end

local function updatePage()
    local pages=pageCount()
    if pages<=1 then
        if currentPage~=1 then currentPage=1; screenDirty=true end
        pageChangedAt=now()
        return
    end
    if refresh.visible then return end
    if now()-pageChangedAt>=pageSeconds*1000 then
        currentPage=currentPage+1
        if currentPage>pages then currentPage=1 end
        pageChangedAt=now()
        screenDirty=true
    end
end

local function updateRefresh()
    if not refresh.visible then return end
    local time=now()
    if refresh.running then
        if (tableCount(refresh.expected)>0 and tableCount(refresh.responses)>=tableCount(refresh.expected))
            or time-refresh.started>=refreshWaitSeconds*1000 then
            refresh.running=false
            refresh.finishedAt=time
            pageChangedAt=time
            screenDirty=true
        end
    elseif refresh.finishedAt>0 and time-refresh.finishedAt>=refreshResultSeconds*1000 then
        refresh.visible=false
        pageChangedAt=time
        screenDirty=true
    end
end

local function requestDiscovery()
    rednet.broadcast({command="discover"},storageControlProtocol)
    rednet.broadcast({command="discover"},machineControlProtocol)
end

local function forceTargetRefresh()
    refresh.visible=true
    refresh.running=true
    refresh.started=now()
    refresh.finishedAt=0
    refresh.responses={}
    refresh.expected={}
    local time=now()
    for id,info in pairs(knownComputers) do
        if time-(info.lastSeen or 0)<=sourceOfflineSeconds*1000 then refresh.expected[id]=true end
    end
    screenDirty=true
    rednet.broadcast({command="force_targets_refresh",requestedBy=os.getComputerID(),timestamp=now()},configControlProtocol)
end

local function buildLowSummary()
    rebuildCards()
    local low={}
    for _,itemID in ipairs(cardOrder) do
        local card=cards[itemID]
        local p=card and percentage(card)
        if card and (hasError(card) or (p and p<75)) then
            low[#low+1]={
                itemID=itemID,name=card.name or itemID,
                amount=tonumber(card.amount) or 0,target=tonumber(card.targetAmount) or 0,
                percent=p,error=hasError(card) and errorText(card) or nil,
                machineRunning=card.machineRunning==true
            }
        end
    end
    table.sort(low,function(a,b)
        if (a.error~=nil)~=(b.error~=nil) then return a.error~=nil end
        local ap=tonumber(a.percent) or -1
        local bp=tonumber(b.percent) or -1
        if ap~=bp then return ap<bp end
        return string.lower(a.name)<string.lower(b.name)
    end)
    return low
end

local function broadcastLowResources()
    rednet.broadcast({
        messageType="low_resource_summary",
        resources=buildLowSummary(),
        totalResources=#cardOrder,
        timestamp=now(),
        computerID=os.getComputerID()
    },systemStatusProtocol)
end

local function eventLoop()
    local discoveryTimer=os.startTimer(discoveryInterval)
    local staleTimer=os.startTimer(2)
    while true do
        local event,a,b,c=os.pullEvent()
        if event=="rednet_message" then
            local senderID,message,protocol=a,b,c
            if protocol==storageStatusProtocol and type(message)=="table" then
                if message.messageType=="storage_manifest" then processStorageManifest(senderID,message)
                elseif message.messageType=="inventory_update" then processInventoryUpdate(senderID,message) end
            elseif protocol==machineStatusProtocol and type(message)=="table" and message.messageType=="resource_machine_status" then
                processMachineStatus(senderID,message)
            elseif protocol==configStatusProtocol and type(message)=="table" then
                processRefreshStatus(senderID,message)
            end

        elseif event=="monitor_touch" and a==monitorName then
            if not refresh.visible then
                local x,y=b,c
                if inside(x,y,rebootButton) then
                    drawButton(rebootButton,"REBOOTING",theme.rebootPressed)
                    sleep(0.15)
                    os.reboot()
                elseif inside(x,y,refreshButton) then
                    forceTargetRefresh()
                end
            end

        elseif event=="timer" and a==discoveryTimer then
            requestDiscovery()
            discoveryTimer=os.startTimer(discoveryInterval)

        elseif event=="timer" and a==staleTimer then
            screenDirty=true
            staleTimer=os.startTimer(2)

        elseif event=="monitor_resize" and a==monitorName then
            monitor.setTextScale(0.5)
            calculateLayout()
            screenDirty=true
        end
    end
end

local function displayLoop()
    while true do
        updateRefresh()
        updatePage()

        local time=now()
        if time-lastFlash>=flashInterval*1000 then
            flashState=not flashState
            lastFlash=time
        end

        -- Throttle expensive full redraws. Rednet can deliver dozens of
        -- inventory updates in a burst; previously each burst repeatedly
        -- erased the chase animation and made it look frozen.
        if screenDirty and time-lastFullDraw>=fullRedrawInterval*1000 then
            screenDirty=false
            fullDraw()
            lastFullDraw=now()
        else
            drawAnimations()
            if pageCount()>1 and not refresh.visible then drawHeader() end
        end

        sleep(animationSpeed)
    end
end

local function lowSummaryLoop()
    while true do
        broadcastLowResources()
        sleep(lowSummaryInterval)
    end
end

calculateLayout()
fullDraw()
lastFullDraw=now()
screenDirty=false
requestDiscovery()
broadcastLowResources()

parallel.waitForAll(eventLoop,displayLoop,lowSummaryLoop)
