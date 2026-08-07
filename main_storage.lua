-- =========================================================
-- MAIN STORAGE SCREEN
-- Low resources first, 45 cards/page, auto-rotation.
-- Card layout:
--   L1 border
--   L2 empty
--   L3 name
--   L4 progress bar
--   L5 empty
--   L6 border
-- =========================================================

local monitorSide = "right"
local modemSide = "back"

local storageControlProtocol = "inventory_control"
local storageStatusProtocol = "inventory_status"
local machineControlProtocol = "resource_machine_control"
local machineStatusProtocol = "resource_machine_status"
local configControlProtocol = "config_control"
local configStatusProtocol = "config_status"

local cardsPerPage = 45
local pageSeconds = 15
local sourceOfflineSeconds = 12
local sourceRemoveSeconds = 60
local discoveryInterval = 5
local renderInterval = 0.20
local refreshWaitSeconds = 5
local refreshResultSeconds = 10
local animationSpeed = 0.12
local flashInterval = 0.48
local chaseLength = 6

local chaseFrame = 0
local flashState = false
local flashElapsed = 0
local screenDirty = true
local currentPage = 1
local pageChangedAt = os.epoch("utc")

local monitor = peripheral.wrap(monitorSide)
if not monitor then error("No monitor found on " .. monitorSide) end
if not monitor.isColor() then error("Advanced Monitor required") end
monitor.setTextScale(0.5)
local monitorName = peripheral.getName(monitor)

if not peripheral.isPresent(modemSide) then
    error("No modem found on " .. modemSide)
end
rednet.open(modemSide)

local theme = {
    background=colors.black,
    header=colors.cyan,
    headerText=colors.black,
    headerSubtext=colors.gray,
    accent=colors.blue,
    card=colors.gray,
    emptyCard=colors.black,
    title=colors.white,
    amountText=colors.white,
    full=colors.lime,
    good=colors.lightBlue,
    warning=colors.orange,
    low=colors.red,
    criticalRed=colors.red,
    criticalBlack=colors.black,
    errorRed=colors.red,
    errorOrange=colors.orange,
    machineChase=colors.lime,
    progressBackground=colors.black,
    progressFull=colors.lime,
    progressGood=colors.lightBlue,
    progressWarning=colors.orange,
    progressLow=colors.red,
    emptyBorder=colors.gray,
    placeholderText=colors.gray,
    rebootButton=colors.blue,
    rebootPressed=colors.lightBlue,
    refreshButton=colors.green,
    refreshPressed=colors.lime,
    popupBackground=colors.gray,
    popupBorder=colors.lightGray,
    popupTitle=colors.cyan,
    success=colors.lime,
    failure=colors.red,
    pending=colors.orange,
    footer=colors.gray,
    footerText=colors.white
}

local storageSources = {}
local machineStates = {}
local cards = {}
local cardOrder = {}
local layoutSlots = {}
local knownComputers = {}
local rebootButton = {}
local refreshButton = {}

local refresh = {
    visible=false,
    running=false,
    started=0,
    finishedAt=0,
    responses={},
    expected={}
}

local function now()
    return os.epoch("utc")
end

local function rememberComputer(computerID, role)
    local info = knownComputers[computerID]
    if not info then
        info = {}
        knownComputers[computerID] = info
    end
    info.role = role or info.role or "NODE"
    info.lastSeen = now()
end

local function fill(x1,y1,x2,y2,color)
    if x2 < x1 or y2 < y1 then return end
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

local function shortenText(text,maxLength)
    text=tostring(text or "")
    if maxLength<=0 then return "" end
    if #text<=maxLength then return text end
    if maxLength<=3 then return string.sub(text,1,maxLength) end
    return string.sub(text,1,maxLength-2)..".."
end

local function centerInside(x1,x2,y,text,fg,bg)
    local width=x2-x1+1
    text=shortenText(text,width)
    local x=x1+math.floor((width-#text)/2)
    writeAt(x,y,text,fg,bg)
end

local function drawBorder(x1,y1,x2,y2,color)
    fill(x1,y1,x2,y1,color)
    fill(x1,y2,x2,y2,color)
    fill(x1,y1,x1,y2,color)
    fill(x2,y1,x2,y2,color)
end

local function drawPixel(x,y,color)
    monitor.setCursorPos(x,y)
    monitor.setBackgroundColor(color)
    monitor.write(" ")
end

local function isInside(x,y,x1,y1,x2,y2)
    return x>=x1 and x<=x2 and y>=y1 and y<=y2
end

local function getBorderPoints(x1,y1,x2,y2)
    local points={}
    for x=x1,x2 do points[#points+1]={x=x,y=y1} end
    for y=y1+1,y2-1 do points[#points+1]={x=x2,y=y} end
    for x=x2,x1,-1 do points[#points+1]={x=x,y=y2} end
    for y=y2-1,y1+1,-1 do points[#points+1]={x=x1,y=y} end
    return points
end

local function commaNumber(number)
    number=math.floor(tonumber(number) or 0)
    local text=tostring(number)
    while true do
        local formatted,replacements=string.gsub(text,"^(-?%d+)(%d%d%d)","%1,%2")
        text=formatted
        if replacements==0 then break end
    end
    return text
end

local function ensureStorageSource(computerID)
    if not storageSources[computerID] then storageSources[computerID]={} end
    return storageSources[computerID]
end

local function processStorageManifest(senderID,message)
    rememberComputer(senderID,message.role or "STORAGE")
    if type(message.enabledKeys)~="table" then return end

    local enabled={}
    for _,itemID in ipairs(message.enabledKeys) do
        if type(itemID)=="string" then enabled[itemID]=true end
    end

    local source=ensureStorageSource(senderID)
    for itemID in pairs(source) do
        if not enabled[itemID] then source[itemID]=nil end
    end
    screenDirty=true
end

local function processInventoryUpdate(senderID,message)
    rememberComputer(senderID,message.role or "STORAGE")
    local itemID=message.itemID or message.storageKey
    if type(itemID)~="string" then return end

    local source=ensureStorageSource(senderID)
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

local function calculatePercentage(card)
    local amount=tonumber(card.amount)
    local target=tonumber(card.targetAmount)
    if not amount or not target or target<=0 then return nil end
    return math.max(0,math.min(100,amount/target*100))
end

local function hasError(card)
    if not card.online then return true end
    if card.error and card.error~="" then return true end
    if not card.found then return true end
    if not card.targetAmount or tonumber(card.targetAmount)<=0 then return true end
    return false
end

local function getErrorText(card)
    if not card.online then return "DISCONNECTED" end
    if card.error and card.error~="" then return string.upper(tostring(card.error)) end
    if not card.found then return "STORAGE NOT FOUND" end
    if not card.targetAmount or tonumber(card.targetAmount)<=0 then return "NO TARGET" end
    return "ERROR"
end

local function priorityForCard(card)
    if hasError(card) then return 0,-1 end
    local p=calculatePercentage(card) or 0
    if p<25 then return 1,p end
    if p<50 then return 2,p end
    if p<75 then return 3,p end
    return 4,p
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
                    card={
                        itemID=itemID,
                        name=data.displayName or itemID,
                        amount=0,
                        targetAmount=0,
                        found=true,
                        online=false,
                        error=nil,
                        machineRunning=false,
                        x1=0,y1=0,x2=0,y2=0,borderPoints={}
                    }
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
        local pa,va=priorityForCard(cards[a])
        local pb,vb=priorityForCard(cards[b])
        if pa~=pb then return pa<pb end
        if va~=vb then return va<vb end
        return string.lower(cards[a].name or a)<string.lower(cards[b].name or b)
    end)

    local pages=math.max(1,math.ceil(#cardOrder/cardsPerPage))
    if currentPage>pages then
        currentPage=pages
        pageChangedAt=time
    end
end

local function getBorderColor(card)
    if hasError(card) then return flashState and theme.errorRed or theme.errorOrange end
    local p=calculatePercentage(card)
    if not p then return flashState and theme.errorRed or theme.errorOrange end
    if p<25 then return flashState and theme.criticalRed or theme.criticalBlack end
    if p<50 then return theme.low end
    if p<75 then return theme.warning end
    if p>=100 then return theme.full end
    return theme.good
end

local function getProgressColor(card)
    local p=calculatePercentage(card)
    if not p or p<50 then return theme.progressLow end
    if p<75 then return theme.progressWarning end
    if p>=100 then return theme.progressFull end
    return theme.progressGood
end

local function pageCount()
    return math.max(1,math.ceil(#cardOrder/cardsPerPage))
end

local function firstIndexOnPage()
    return (currentPage-1)*cardsPerPage+1
end

local function lastIndexOnPage()
    return math.min(#cardOrder,currentPage*cardsPerPage)
end

local function updatePageRotation()
    local pages=pageCount()
    if pages<=1 then
        if currentPage~=1 then
            currentPage=1
            screenDirty=true
        end
        pageChangedAt=now()
        return
    end

    if refresh.visible then return end

    local time=now()
    if time-pageChangedAt>=pageSeconds*1000 then
        currentPage=currentPage+1
        if currentPage>pages then currentPage=1 end
        pageChangedAt=time
        screenDirty=true
    end
end

-- =========================================================
-- LAYOUT
-- 5 columns x 9 rows = 45 cards.
-- Cards are exactly six lines tall. Vertical gap is 0 so the
-- 45-card capacity is preserved while using the requested shape.
-- =========================================================

local function calculateLayout()
    local width,height=monitor.getSize()
    local columns=5
    local rows=9
    local cardHeight=6
    local horizontalGap=1
    local verticalGap=0
    local topY=7
    local bottomY=height-2
    local availableWidth=width-2
    local availableHeight=bottomY-topY+1

    local cardWidth=math.floor((availableWidth-horizontalGap*(columns-1))/columns)
    if cardWidth<10 then error("Monitor too narrow") end

    local totalGridWidth=columns*cardWidth+horizontalGap*(columns-1)
    local totalGridHeight=rows*cardHeight+verticalGap*(rows-1)
    if totalGridHeight>availableHeight then
        error("Monitor too short for 45 six-line cards")
    end

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
        layoutSlots[index]={
            x1=x1,y1=y1,x2=x2,y2=y2,
            borderPoints=getBorderPoints(x1,y1,x2,y2)
        }
    end

    local rebootWidth=14
    local refreshWidth=24
    rebootButton.x2=width-2
    rebootButton.x1=rebootButton.x2-rebootWidth+1
    rebootButton.y1=2
    rebootButton.y2=4

    refreshButton.x2=rebootButton.x1-2
    refreshButton.x1=refreshButton.x2-refreshWidth+1
    refreshButton.y1=2
    refreshButton.y2=4
end

local function drawRebootButton(color)
    fill(rebootButton.x1,rebootButton.y1,rebootButton.x2,rebootButton.y2,color)
    centerInside(rebootButton.x1,rebootButton.x2,rebootButton.y1+1,"REBOOT",colors.white,color)
end

local function drawRefreshButton(color)
    fill(refreshButton.x1,refreshButton.y1,refreshButton.x2,refreshButton.y2,color)
    centerInside(refreshButton.x1,refreshButton.x2,refreshButton.y1+1,"REFRESH TARGETS",colors.white,color)
end

local function drawHeader()
    local width=monitor.getSize()
    fill(1,1,width,5,theme.header)
    writeAt(3,2,"STORAGE MANAGEMENT",theme.headerText,theme.header)

    local pages=pageCount()
    local subtitle="LOW RESOURCES FIRST"
    if pages>1 then
        local elapsed=math.floor((now()-pageChangedAt)/1000)
        local remaining=math.max(0,pageSeconds-elapsed)
        subtitle=subtitle.."  |  PAGE "..currentPage.."/"..pages.."  |  NEXT "..remaining.."s"
    end

    writeAt(3,3,shortenText(subtitle,math.max(10,refreshButton.x1-5)),theme.headerSubtext,theme.header)
    drawRefreshButton(refresh.running and theme.refreshPressed or theme.refreshButton)
    drawRebootButton(theme.rebootButton)
    fill(1,6,width,6,theme.accent)
end

local function drawCenteredBarText(x1,x2,y,text,filledUntil,filledColor)
    local width=x2-x1+1
    text=shortenText(text,width)
    local textX=x1+math.floor((width-#text)/2)

    for index=1,#text do
        local x=textX+index-1
        local bg=theme.progressBackground
        if filledUntil and x<=filledUntil then bg=filledColor end
        writeAt(x,y,string.sub(text,index,index),theme.amountText,bg)
    end
end

local function drawProgressBar(card)
    -- Requested L4.
    local y=card.y1+3
    local x1=card.x1+2
    local x2=card.x2-2
    local width=x2-x1+1
    fill(x1,y,x2,y,theme.progressBackground)

    if hasError(card) then
        drawCenteredBarText(x1,x2,y,getErrorText(card),nil,nil)
        return
    end

    local p=calculatePercentage(card)
    local filledWidth=math.floor(width*p/100)
    if p>0 and filledWidth<1 then filledWidth=1 end
    if filledWidth>width then filledWidth=width end

    local progressColor=getProgressColor(card)
    local filledUntil=nil
    if filledWidth>0 then
        filledUntil=x1+filledWidth-1
        fill(x1,y,filledUntil,y,progressColor)
    end

    local text=commaNumber(card.amount).." / "..commaNumber(card.targetAmount)
    drawCenteredBarText(x1,x2,y,text,filledUntil,progressColor)
end

local function drawMachineChase(card)
    if not card.machineRunning then return end
    local points=card.borderPoints
    if not points or #points==0 then return end

    local startIndex=(chaseFrame%#points)+1
    for offset=0,chaseLength-1 do
        local index=(startIndex+offset-1)%#points+1
        local point=points[index]
        drawPixel(point.x,point.y,theme.machineChase)
    end
end

local function drawCardBorder(card)
    drawBorder(card.x1,card.y1,card.x2,card.y2,getBorderColor(card))
    drawMachineChase(card)
end

local function drawPlaceholder(slot,index)
    -- L1 + L6 border, L2-L5 empty black, placeholder on L3.
    drawBorder(slot.x1,slot.y1,slot.x2,slot.y2,theme.emptyBorder)
    fill(slot.x1+1,slot.y1+1,slot.x2-1,slot.y2-1,theme.emptyCard)
    centerInside(
        slot.x1+1,slot.x2-1,slot.y1+2,
        "AVAILABLE "..index,
        theme.placeholderText,
        theme.emptyCard
    )
end

local function drawCard(card)
    -- Fill interior first, then border so L1/L6 remain pure border.
    fill(card.x1+1,card.y1+1,card.x2-1,card.y2-1,theme.card)

    -- L2 intentionally empty.

    -- L3 name.
    centerInside(
        card.x1+2,
        card.x2-2,
        card.y1+2,
        string.upper(card.name or "STORAGE"),
        theme.title,
        theme.card
    )

    -- L4 progress.
    drawProgressBar(card)

    -- L5 intentionally empty.

    -- L1/L6 + side borders.
    drawCardBorder(card)
end

local function countErrors()
    local count=0
    for _,itemID in ipairs(cardOrder) do
        if cards[itemID] and hasError(cards[itemID]) then count=count+1 end
    end
    return count
end

local function countRunning()
    local count=0
    for _,itemID in ipairs(cardOrder) do
        if cards[itemID] and cards[itemID].machineRunning then count=count+1 end
    end
    return count
end

local function countLow()
    local count=0
    for _,itemID in ipairs(cardOrder) do
        local card=cards[itemID]
        if card then
            local p=calculatePercentage(card)
            if hasError(card) or (p and p<75) then count=count+1 end
        end
    end
    return count
end

local function drawFooter()
    local width,height=monitor.getSize()
    fill(1,height-1,width,height,theme.footer)

    local text="RESOURCES "..#cardOrder
        .."  LOW "..countLow()
        .."  ERRORS "..countErrors()
        .."  RUNNING "..countRunning()

    local pages=pageCount()
    if pages>1 then text=text.."  PAGE "..currentPage.."/"..pages end

    writeAt(2,height,shortenText(text,width-2),theme.footerText,theme.footer)
end

local function tableCount(t)
    local c=0
    for _ in pairs(t) do c=c+1 end
    return c
end

local function getSuccessCount()
    local c=0
    for _,r in pairs(refresh.responses) do if r.success then c=c+1 end end
    return c
end

local function getFailureCount()
    local c=0
    for _,r in pairs(refresh.responses) do if not r.success then c=c+1 end end
    return c
end

local function resetRefresh()
    refresh.visible=true
    refresh.running=true
    refresh.started=now()
    refresh.finishedAt=0
    refresh.responses={}
    refresh.expected={}

    local time=now()
    for computerID,info in pairs(knownComputers) do
        if time-(info.lastSeen or 0)<=sourceOfflineSeconds*1000 then
            refresh.expected[computerID]=true
        end
    end
end

local function drawRefreshPopup()
    if not refresh.visible then return end

    local width,height=monitor.getSize()
    local popupWidth=math.min(60,width-8)
    local popupHeight=math.min(18,height-10)
    local x1=math.floor((width-popupWidth)/2)+1
    local y1=math.floor((height-popupHeight)/2)+1
    local x2=x1+popupWidth-1
    local y2=y1+popupHeight-1

    drawBorder(x1,y1,x2,y2,theme.popupBorder)
    fill(x1+1,y1+1,x2-1,y2-1,theme.popupBackground)
    centerInside(x1+2,x2-2,y1+1,"TARGET REFRESH",theme.popupTitle,theme.popupBackground)

    local expected=tableCount(refresh.expected)
    local responses=tableCount(refresh.responses)
    local summary
    if refresh.running then
        summary="UPDATING... "..responses.." / "..expected
    else
        summary=getSuccessCount().." UPDATED / "..getFailureCount().." FAILED"
    end
    centerInside(x1+2,x2-2,y1+3,summary,colors.white,theme.popupBackground)

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
        local label=tostring(role).." "..tostring(id)

        if result then
            writeAt(x1+3,row,result.success and "+" or "X",result.success and theme.success or theme.failure,theme.popupBackground)
            writeAt(x1+5,row,shortenText(label,popupWidth-10),colors.white,theme.popupBackground)
            writeAt(x2-9,row,result.success and "UPDATED" or "FAILED",result.success and theme.success or theme.failure,theme.popupBackground)
            if not result.success and result.error and row+1<y2-1 then
                row=row+1
                writeAt(x1+7,row,shortenText(result.error,popupWidth-12),theme.failure,theme.popupBackground)
            end
        else
            writeAt(x1+3,row,"?",theme.pending,theme.popupBackground)
            writeAt(x1+5,row,shortenText(label,popupWidth-10),colors.white,theme.popupBackground)
            writeAt(x2-8,row,refresh.running and "WAITING" or "NO REPLY",theme.pending,theme.popupBackground)
        end
        row=row+1
    end

    centerInside(
        x1+2,x2-2,y2-1,
        refresh.running and "WAITING FOR COMPUTERS..." or "RESULTS WILL CLOSE AUTOMATICALLY",
        refresh.running and theme.pending or colors.lightGray,
        theme.popupBackground
    )
end

local function drawScreen()
    rebuildCards()

    local width,height=monitor.getSize()
    fill(1,1,width,height,theme.background)
    drawHeader()

    local first=firstIndexOnPage()
    local last=lastIndexOnPage()
    local slotIndex=1

    for globalIndex=first,last do
        local slot=layoutSlots[slotIndex]
        local itemID=cardOrder[globalIndex]
        if slot and itemID then
            local card=cards[itemID]
            card.x1=slot.x1
            card.y1=slot.y1
            card.x2=slot.x2
            card.y2=slot.y2
            card.borderPoints=slot.borderPoints
            drawCard(card)
        end
        slotIndex=slotIndex+1
    end

    while slotIndex<=cardsPerPage do
        local slot=layoutSlots[slotIndex]
        if slot then
            drawPlaceholder(slot,(currentPage-1)*cardsPerPage+slotIndex)
        end
        slotIndex=slotIndex+1
    end

    drawFooter()
    drawRefreshPopup()
end

local function requestDiscovery()
    rednet.broadcast({command="discover"},storageControlProtocol)
    rednet.broadcast({command="discover"},machineControlProtocol)
end

local function forceTargetRefresh()
    resetRefresh()
    screenDirty=true
    rednet.broadcast({
        command="force_targets_refresh",
        requestedBy=os.getComputerID(),
        timestamp=now()
    },configControlProtocol)
end

local function updateRefreshState()
    if not refresh.visible then return end
    local time=now()

    if refresh.running then
        local expected=tableCount(refresh.expected)
        local responses=tableCount(refresh.responses)
        local age=time-refresh.started

        if (expected>0 and responses>=expected) or age>=refreshWaitSeconds*1000 then
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

local function rebootComputer()
    drawRebootButton(theme.rebootPressed)
    sleep(0.15)
    os.reboot()
end

local function renderLoop()
    while true do
        updateRefreshState()
        updatePageRotation()

        if screenDirty then
            screenDirty=false
            drawScreen()
        elseif pageCount()>1 and not refresh.visible then
            drawHeader()
        end

        sleep(renderInterval)
    end
end

local function animationLoop()
    while true do
        chaseFrame=chaseFrame+1
        flashElapsed=flashElapsed+animationSpeed
        local flashChanged=false

        if flashElapsed>=flashInterval then
            flashElapsed=flashElapsed-flashInterval
            flashState=not flashState
            flashChanged=true
        end

        if not refresh.visible then
            local first=firstIndexOnPage()
            local last=lastIndexOnPage()
            local slotIndex=1

            for globalIndex=first,last do
                local itemID=cardOrder[globalIndex]
                local card=cards[itemID]
                local slot=layoutSlots[slotIndex]

                if card and slot then
                    card.x1=slot.x1
                    card.y1=slot.y1
                    card.x2=slot.x2
                    card.y2=slot.y2
                    card.borderPoints=slot.borderPoints

                    if card.machineRunning then
                        drawCardBorder(card)
                    elseif flashChanged then
                        local p=calculatePercentage(card)
                        if hasError(card) or (p and p<25) then
                            drawCardBorder(card)
                        end
                    end
                end
                slotIndex=slotIndex+1
            end
        end

        sleep(animationSpeed)
    end
end

local function eventLoop()
    local discoveryTimer=os.startTimer(discoveryInterval)
    local staleTimer=os.startTimer(2)

    while true do
        local event,a,b,c=os.pullEvent()

        if event=="rednet_message" then
            local senderID,message,protocol=a,b,c

            if protocol==storageStatusProtocol and type(message)=="table" then
                if message.messageType=="storage_manifest" then
                    processStorageManifest(senderID,message)
                elseif message.messageType=="inventory_update" then
                    processInventoryUpdate(senderID,message)
                end

            elseif protocol==machineStatusProtocol
                and type(message)=="table"
                and message.messageType=="resource_machine_status" then
                processMachineStatus(senderID,message)

            elseif protocol==configStatusProtocol and type(message)=="table" then
                processRefreshStatus(senderID,message)
            end

        elseif event=="monitor_touch" and a==monitorName then
            local x,y=b,c
            if not refresh.visible then
                if isInside(x,y,rebootButton.x1,rebootButton.y1,rebootButton.x2,rebootButton.y2) then
                    rebootComputer()
                elseif isInside(x,y,refreshButton.x1,refreshButton.y1,refreshButton.x2,refreshButton.y2) then
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

calculateLayout()
drawScreen()
screenDirty=false
requestDiscovery()

parallel.waitForAll(eventLoop,renderLoop,animationLoop)
