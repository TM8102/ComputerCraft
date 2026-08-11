-- =========================================================
-- MAIN STORAGE SCREEN - SMOOTH / LIGHTWEIGHT
-- 40 cards per page, fixed alphabetical order, page rotation,
-- refresh popup, low-resource broadcast, and efficient chase animation.
-- =========================================================

local monitorSide="right"
local modemSide="back"

local storageControlProtocol="inventory_control"
local storageStatusProtocol="inventory_status"
local machineControlProtocol="resource_machine_control"
local machineStatusProtocol="resource_machine_status"
local configControlProtocol="config_control"
local configStatusProtocol="config_status"
local systemStatusProtocol="system_status"

local cardsPerPage=40
local pageSeconds=15
local sourceOfflineSeconds=12
local sourceRemoveSeconds=60
local discoveryInterval=5
local animationSpeed=0.10
local flashInterval=0.50
local lowSummaryInterval=2
local refreshWaitSeconds=5
local refreshResultSeconds=10
local chaseLength=4

local monitor=peripheral.wrap(monitorSide)
if not monitor then error("No monitor found on "..monitorSide) end
if not monitor.isColor() then error("Advanced Monitor required") end
monitor.setTextScale(0.5)
local monitorName=peripheral.getName(monitor)

if not peripheral.isPresent(modemSide) then error("No modem found on "..modemSide) end
rednet.open(modemSide)

local theme={
    background=colors.black,header=colors.cyan,headerText=colors.black,headerSub=colors.gray,
    accent=colors.blue,card=colors.gray,cardText=colors.white,empty=colors.black,
    emptyBorder=colors.gray,emptyText=colors.gray,full=colors.lime,good=colors.lightBlue,
    warn=colors.orange,low=colors.red,criticalA=colors.red,criticalB=colors.black,
    errorA=colors.red,errorB=colors.orange,chase=colors.lime,progressBg=colors.black,
    reboot=colors.blue,rebootPressed=colors.lightBlue,refresh=colors.green,
    refreshPressed=colors.lime,footer=colors.gray,footerText=colors.white,popup=colors.gray,
    popupBorder=colors.lightGray,popupTitle=colors.cyan,success=colors.lime,
    failure=colors.red,pending=colors.orange
}

local storageSources={}
local machineStates={}
local cards={}
local cardOrder={}
local layoutSlots={}
local visibleByItem={}
local knownComputers={}
local refresh={visible=false,running=false,started=0,finishedAt=0,responses={},expected={}}

local rebootButton={}
local refreshButton={}
local currentPage=1
local pageChangedAt=os.epoch("utc")
local structureDirty=true
local headerDirty=true
local footerDirty=true
local popupDirty=true
local dirtyCards={}
local dataDirty=true
local flashState=false
local lastFlash=os.epoch("utc")
local chaseFrame=0
local chaseDrawn={}

local function now() return os.epoch("utc") end

local function validRect(x1,y1,x2,y2)
    return type(x1)=="number" and type(y1)=="number" and type(x2)=="number" and type(y2)=="number"
end

local function fill(x1,y1,x2,y2,color)
    if not validRect(x1,y1,x2,y2) then return end
    if x2<x1 or y2<y1 then return end
    monitor.setBackgroundColor(color)
    local line=string.rep(" ",x2-x1+1)
    for y=y1,y2 do
        monitor.setCursorPos(x1,y)
        monitor.write(line)
    end
end

local function writeAt(x,y,text,fg,bg)
    if type(x)~="number" or type(y)~="number" then return end
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
    if type(x1)~="number" or type(x2)~="number" or type(y)~="number" then return end
    local width=x2-x1+1
    text=shorten(text,width)
    writeAt(x1+math.floor((width-#text)/2),y,text,fg,bg)
end

local function border(x1,y1,x2,y2,color)
    if not validRect(x1,y1,x2,y2) then return end
    fill(x1,y1,x2,y1,color)
    fill(x1,y2,x2,y2,color)
    fill(x1,y1,x1,y2,color)
    fill(x2,y1,x2,y2,color)
end

local function pixel(x,y,color)
    if type(x)~="number" or type(y)~="number" then return end
    monitor.setCursorPos(x,y)
    monitor.setBackgroundColor(color)
    monitor.write(" ")
end

local function inside(x,y,b)
    return type(b)=="table" and type(b.x1)=="number" and type(b.x2)=="number"
        and type(b.y1)=="number" and type(b.y2)=="number"
        and x>=b.x1 and x<=b.x2 and y>=b.y1 and y<=b.y2
end

local function borderPoints(x1,y1,x2,y2)
    local p={}
    for x=x1,x2 do p[#p+1]={x=x,y=y1} end
    for y=y1+1,y2-1 do p[#p+1]={x=x2,y=y} end
    for x=x2,x1,-1 do p[#p+1]={x=x,y=y2} end
    for y=y2-1,y1+1,-1 do p[#p+1]={x=x1,y=y} end
    return p
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

local function rememberComputer(id,role)
    local info=knownComputers[id] or {}
    info.role=role or info.role or "NODE"
    info.lastSeen=now()
    knownComputers[id]=info
end

local function ensureSource(id)
    if not storageSources[id] then storageSources[id]={} end
    return storageSources[id]
end

local function percentage(card)
    local a=tonumber(card.amount)
    local t=tonumber(card.targetAmount)
    if not a or not t or t<=0 then return nil end
    return math.max(0,math.min(100,a/t*100))
end

local function hasError(card)
    return not card.online or not card.found or (card.error and card.error~="")
        or not card.targetAmount or tonumber(card.targetAmount)<=0
end

local function errorText(card)
    if not card.online then return "DISCONNECTED" end
    if card.error and card.error~="" then return string.upper(tostring(card.error)) end
    if not card.found then return "STORAGE NOT FOUND" end
    if not card.targetAmount or tonumber(card.targetAmount)<=0 then return "NO TARGET" end
    return "ERROR"
end

local function baseBorderColor(card)
    if hasError(card) then return flashState and theme.errorA or theme.errorB end
    local p=percentage(card)
    if not p then return flashState and theme.errorA or theme.errorB end
    if p<25 then return flashState and theme.criticalA or theme.criticalB end
    if p<50 then return theme.low end
    if p<75 then return theme.warn end
    if p>=100 then return theme.full end
    return theme.good
end

local function progressColor(card)
    local p=percentage(card)
    if not p or p<50 then return theme.low end
    if p<75 then return theme.warn end
    if p>=100 then return theme.full end
    return theme.good
end

local function pageCount() return math.max(1,math.ceil(#cardOrder/cardsPerPage)) end
local function firstIndex() return (currentPage-1)*cardsPerPage+1 end
local function lastIndex() return math.min(#cardOrder,currentPage*cardsPerPage) end

local function calculateLayout()
    local width,height=monitor.getSize()
    local columns,rows=5,8
    local cardHeight=6
    local hGap,vGap=1,1
    local topY,bottomY=7,height-2
    local availableWidth=width-2
    local availableHeight=bottomY-topY+1
    local cardWidth=math.floor((availableWidth-hGap*(columns-1))/columns)
    if cardWidth<10 then error("Monitor too narrow") end
    local totalW=columns*cardWidth+hGap*(columns-1)
    local totalH=rows*cardHeight+vGap*(rows-1)
    if totalH>availableHeight then error("Monitor too short for 40 cards") end
    local startX=math.floor((width-totalW)/2)+1
    local startY=topY+math.floor((availableHeight-totalH)/2)

    layoutSlots={}
    for i=1,cardsPerPage do
        local col=(i-1)%columns
        local row=math.floor((i-1)/columns)
        local x1=startX+col*(cardWidth+hGap)
        local y1=startY+row*(cardHeight+vGap)
        local x2=x1+cardWidth-1
        local y2=y1+cardHeight-1
        layoutSlots[i]={x1=x1,y1=y1,x2=x2,y2=y2,points=borderPoints(x1,y1,x2,y2)}
    end

    rebootButton.x2=width-2; rebootButton.x1=rebootButton.x2-13; rebootButton.y1=2; rebootButton.y2=4
    refreshButton.x2=rebootButton.x1-2; refreshButton.x1=refreshButton.x2-23; refreshButton.y1=2; refreshButton.y2=4
end

local function rebuildCards()
    local time=now()
    local oldCards=cards
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
                if tonumber(data.targetAmount) and tonumber(data.targetAmount)>0 then card.targetAmount=tonumber(data.targetAmount) end
                if data.displayName and data.displayName~="" then card.name=data.displayName end
                if age<=sourceOfflineSeconds*1000 and data.online then card.online=true end
                if not data.found then card.found=false end
                if data.error and data.error~="" then card.error=data.error end
            end
        end
    end

    for itemID,m in pairs(machineStates) do
        local age=time-(m.lastUpdate or 0)
        if age>sourceRemoveSeconds*1000 then machineStates[itemID]=nil
        elseif combined[itemID] then combined[itemID].machineRunning=m.running==true end
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

    local pages=pageCount()
    if currentPage>pages then currentPage=pages; pageChangedAt=time; structureDirty=true end

    for itemID,card in pairs(cards) do
        local old=oldCards[itemID]
        if not old or old.amount~=card.amount or old.targetAmount~=card.targetAmount
            or old.online~=card.online or old.found~=card.found or old.error~=card.error
            or old.machineRunning~=card.machineRunning or old.name~=card.name then
            dirtyCards[itemID]=true
        end
    end

    for itemID in pairs(oldCards) do if not cards[itemID] then structureDirty=true end end
end

local function drawButton(button,text,color)
    fill(button.x1,button.y1,button.x2,button.y2,color)
    center(button.x1,button.x2,button.y1+1,text,colors.white,color)
end

local function drawHeader()
    local width=monitor.getSize()
    fill(1,1,width,5,theme.header)
    writeAt(3,2,"STORAGE MANAGEMENT",theme.headerText,theme.header)
    local subtitle="LIVE RESOURCE STATUS"
    if pageCount()>1 then
        local remaining=math.max(0,pageSeconds-math.floor((now()-pageChangedAt)/1000))
        subtitle=subtitle.."  |  PAGE "..currentPage.."/"..pageCount().."  |  NEXT "..remaining.."s"
    end
    writeAt(3,3,shorten(subtitle,math.max(10,refreshButton.x1-5)),theme.headerSub,theme.header)
    drawButton(refreshButton,refresh.running and "REFRESHING..." or "REFRESH TARGETS",refresh.running and theme.refreshPressed or theme.refresh)
    drawButton(rebootButton,"REBOOT",theme.reboot)
    fill(1,6,width,6,theme.accent)
    headerDirty=false
end

local function drawProgress(card)
    if not validRect(card.x1,card.y1,card.x2,card.y2) then return end
    local y=card.y1+3
    local x1=card.x1+2
    local x2=card.x2-2
    local width=x2-x1+1
    fill(x1,y,x2,y,theme.progressBg)
    if hasError(card) then center(x1,x2,y,errorText(card),theme.cardText,theme.progressBg); return end
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
        local bg=(filled>0 and x<=x1+filled-1) and color or theme.progressBg
        writeAt(x,y,text:sub(i,i),theme.cardText,bg)
    end
end

local function drawCard(card,slot)
    if not card or not slot then return end
    card.x1=slot.x1; card.y1=slot.y1; card.x2=slot.x2; card.y2=slot.y2; card.borderPoints=slot.points
    fill(card.x1+1,card.y1+1,card.x2-1,card.y2-1,theme.card)
    center(card.x1+2,card.x2-2,card.y1+2,string.upper(card.name or "STORAGE"),theme.cardText,theme.card)
    drawProgress(card)
    border(card.x1,card.y1,card.x2,card.y2,baseBorderColor(card))
end

local function drawPlaceholder(slot,index)
    if not slot then return end
    border(slot.x1,slot.y1,slot.x2,slot.y2,theme.emptyBorder)
    fill(slot.x1+1,slot.y1+1,slot.x2-1,slot.y2-1,theme.empty)
    center(slot.x1+1,slot.x2-1,slot.y1+2,"AVAILABLE "..index,theme.emptyText,theme.empty)
end

local function countErrors()
    local n=0
    for _,id in ipairs(cardOrder) do if cards[id] and hasError(cards[id]) then n=n+1 end end
    return n
end
local function countLow()
    local n=0
    for _,id in ipairs(cardOrder) do local c=cards[id]; local p=c and percentage(c); if c and (hasError(c) or (p and p<75)) then n=n+1 end end
    return n
end
local function countRunning()
    local n=0
    for _,id in ipairs(cardOrder) do if cards[id] and cards[id].machineRunning then n=n+1 end end
    return n
end

local function drawFooter()
    local width,height=monitor.getSize()
    fill(1,height-1,width,height,theme.footer)
    local text="RESOURCES "..#cardOrder.."   LOW "..countLow().."   ERRORS "..countErrors().."   RUNNING "..countRunning()
    if pageCount()>1 then text=text.."   PAGE "..currentPage.."/"..pageCount() end
    writeAt(2,height,shorten(text,width-2),theme.footerText,theme.footer)
    footerDirty=false
end

local function tableCount(t) local n=0 for _ in pairs(t) do n=n+1 end return n end

local function drawPopup()
    if not refresh.visible then popupDirty=false; return end
    local width,height=monitor.getSize()
    local popupWidth=math.min(60,width-8)
    local popupHeight=math.min(18,height-10)
    local x1=math.floor((width-popupWidth)/2)+1
    local y1=math.floor((height-popupHeight)/2)+1
    local x2=x1+popupWidth-1
    local y2=y1+popupHeight-1
    border(x1,y1,x2,y2,theme.popupBorder)
    fill(x1+1,y1+1,x2-1,y2-1,theme.popup)
    center(x1+2,x2-2,y1+1,"TARGET REFRESH",theme.popupTitle,theme.popup)
    local success,failure=0,0
    for _,r in pairs(refresh.responses) do if r.success then success=success+1 else failure=failure+1 end end
    local summary=refresh.running and ("UPDATING "..tableCount(refresh.responses).."/"..tableCount(refresh.expected)) or (success.." UPDATED / "..failure.." FAILED")
    center(x1+2,x2-2,y1+3,summary,colors.white,theme.popup)
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
        local mark=result and (result.success and "+" or "X") or "?"
        local color=result and (result.success and theme.success or theme.failure) or theme.pending
        local state=result and (result.success and "UPDATED" or "FAILED") or (refresh.running and "WAITING" or "NO REPLY")
        writeAt(x1+3,row,mark,color,theme.popup)
        writeAt(x1+5,row,shorten(role.." "..id,popupWidth-18),colors.white,theme.popup)
        writeAt(x2-9,row,state,color,theme.popup)
        row=row+1
    end
    popupDirty=false
end

local function rebuildVisibleMap()
    visibleByItem={}
    local slotIndex=1
    for globalIndex=firstIndex(),lastIndex() do
        local itemID=cardOrder[globalIndex]
        if itemID then visibleByItem[itemID]=slotIndex end
        slotIndex=slotIndex+1
    end
end

local function fullDraw()
    rebuildCards()
    dataDirty=false
    chaseDrawn={}
    local width,height=monitor.getSize()
    fill(1,1,width,height,theme.background)
    drawHeader()
    rebuildVisibleMap()
    local slotIndex=1
    for globalIndex=firstIndex(),lastIndex() do
        local itemID=cardOrder[globalIndex]
        local slot=layoutSlots[slotIndex]
        if itemID and slot and cards[itemID] then drawCard(cards[itemID],slot) end
        slotIndex=slotIndex+1
    end
    while slotIndex<=cardsPerPage do
        drawPlaceholder(layoutSlots[slotIndex],(currentPage-1)*cardsPerPage+slotIndex)
        slotIndex=slotIndex+1
    end
    drawFooter()
    if refresh.visible then drawPopup() end
    dirtyCards={}
    structureDirty=false
end

local function restoreOldChase(itemID,card)
    local old=chaseDrawn[itemID]
    if not old then return end
    local color=baseBorderColor(card)
    for _,p in ipairs(old) do pixel(p.x,p.y,color) end
    chaseDrawn[itemID]=nil
end

local function drawChase(card,itemID)
    local points=card.borderPoints
    if not points or #points==0 then return end
    restoreOldChase(itemID,card)
    local start=(chaseFrame%#points)+1
    local drawn={}
    for offset=0,chaseLength-1 do
        local idx=((start+offset-2)%#points)+1
        local p=points[idx]
        pixel(p.x,p.y,theme.chase)
        drawn[#drawn+1]=p
    end
    chaseDrawn[itemID]=drawn
end

local function drawDirtyCards()
    for itemID in pairs(dirtyCards) do
        local slotIndex=visibleByItem[itemID]
        local card=cards[itemID]
        if slotIndex and card and layoutSlots[slotIndex] then
            restoreOldChase(itemID,card)
            drawCard(card,layoutSlots[slotIndex])
        end
        dirtyCards[itemID]=nil
    end
end

local function animate()
    if refresh.visible then return end
    chaseFrame=chaseFrame+1
    for itemID,slotIndex in pairs(visibleByItem) do
        local card=cards[itemID]
        if card and layoutSlots[slotIndex] then
            if card.machineRunning then drawChase(card,itemID)
            elseif chaseDrawn[itemID] then restoreOldChase(itemID,card) end
        end
    end
end

local function flashCritical()
    local time=now()
    if time-lastFlash<flashInterval*1000 then return end
    lastFlash=time
    flashState=not flashState
    for itemID,slotIndex in pairs(visibleByItem) do
        local card=cards[itemID]
        local slot=layoutSlots[slotIndex]
        if card and slot and not card.machineRunning then
            local p=percentage(card)
            if hasError(card) or (p and p<25) then
                card.x1=slot.x1; card.y1=slot.y1; card.x2=slot.x2; card.y2=slot.y2; card.borderPoints=slot.points
                border(card.x1,card.y1,card.x2,card.y2,baseBorderColor(card))
            end
        end
    end
end

local function processStorageManifest(senderID,message)
    rememberComputer(senderID,message.role or "STORAGE")
    if type(message.enabledKeys)~="table" then return end
    local enabled={}
    for _,itemID in ipairs(message.enabledKeys) do if type(itemID)=="string" then enabled[itemID]=true end end
    local source=ensureSource(senderID)
    for itemID in pairs(source) do if not enabled[itemID] then source[itemID]=nil; structureDirty=true; dataDirty=true end end
end

local function processInventoryUpdate(senderID,message)
    rememberComputer(senderID,message.role or "STORAGE")
    local itemID=message.itemID or message.storageKey
    if type(itemID)~="string" then return end
    local source=ensureSource(senderID)
    local previous=source[itemID]
    source[itemID]={itemID=itemID,displayName=message.displayName or itemID,amount=tonumber(message.amount) or 0,
        targetAmount=tonumber(message.targetAmount or message.target) or 0,found=message.found~=false,
        online=message.online~=false,error=message.error,lastUpdate=now()}
    if not previous then structureDirty=true end
    dirtyCards[itemID]=true
    dataDirty=true
end

local function processMachineStatus(senderID,message)
    rememberComputer(senderID,message.role or "NODE")
    if type(message.itemID)~="string" then return end
    local old=machineStates[message.itemID]
    machineStates[message.itemID]={running=message.state==true,computerID=senderID,machineKey=message.machineKey,side=message.side,lastUpdate=now()}
    if not old or old.running~=(message.state==true) then dirtyCards[message.itemID]=true end
    dataDirty=true
end

local function processRefreshStatus(senderID,message)
    rememberComputer(senderID,message.role or "NODE")
    if message.command~="targets_refresh_status" then return end
    refresh.visible=true
    refresh.responses[senderID]={success=message.success==true,error=message.error,role=message.role or (knownComputers[senderID] and knownComputers[senderID].role) or "NODE",timestamp=now()}
    popupDirty=true
end

local function requestDiscovery()
    rednet.broadcast({command="discover"},storageControlProtocol)
    rednet.broadcast({command="discover"},machineControlProtocol)
end

local function forceTargetRefresh()
    refresh.visible=true; refresh.running=true; refresh.started=now(); refresh.finishedAt=0; refresh.responses={}; refresh.expected={}
    local t=now()
    for id,info in pairs(knownComputers) do if t-(info.lastSeen or 0)<=sourceOfflineSeconds*1000 then refresh.expected[id]=true end end
    popupDirty=true; structureDirty=true
    rednet.broadcast({command="force_targets_refresh",requestedBy=os.getComputerID(),timestamp=now()},configControlProtocol)
end

local function updateRefresh()
    if not refresh.visible then return end
    local t=now()
    if refresh.running then
        if (tableCount(refresh.expected)>0 and tableCount(refresh.responses)>=tableCount(refresh.expected)) or t-refresh.started>=refreshWaitSeconds*1000 then
            refresh.running=false; refresh.finishedAt=t; pageChangedAt=t; popupDirty=true; headerDirty=true
        end
    elseif refresh.finishedAt>0 and t-refresh.finishedAt>=refreshResultSeconds*1000 then
        refresh.visible=false; pageChangedAt=t; structureDirty=true; headerDirty=true
    end
end

local function updatePage()
    local pages=pageCount()
    if pages<=1 then if currentPage~=1 then currentPage=1; structureDirty=true end; pageChangedAt=now(); return end
    if refresh.visible then return end
    if now()-pageChangedAt>=pageSeconds*1000 then
        currentPage=currentPage+1; if currentPage>pages then currentPage=1 end
        pageChangedAt=now(); structureDirty=true; headerDirty=true
    end
end

-- IMPORTANT: this function is read-only. It must never call rebuildCards().
-- The previous version rebuilt the shared card table from a parallel loop,
-- replacing cards while the display loop was drawing them. That caused nil
-- coordinates and the line-101 crash seen on the Main Storage Screen.
local function buildLowSummary()
    local low={}
    local snapshotCards=cards
    local snapshotOrder=cardOrder
    for _,itemID in ipairs(snapshotOrder) do
        local card=snapshotCards[itemID]
        local p=card and percentage(card)
        if card and (hasError(card) or (p and p<75)) then
            low[#low+1]={itemID=itemID,name=card.name or itemID,amount=tonumber(card.amount) or 0,
                target=tonumber(card.targetAmount) or 0,percent=p,
                error=hasError(card) and errorText(card) or nil,machineRunning=card.machineRunning==true}
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
    local summary=buildLowSummary()
    rednet.broadcast({messageType="low_resource_summary",resources=summary,totalResources=#cardOrder,
        timestamp=now(),computerID=os.getComputerID()},systemStatusProtocol)
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
            elseif protocol==configStatusProtocol and type(message)=="table" then processRefreshStatus(senderID,message) end
        elseif event=="monitor_touch" and a==monitorName then
            if not refresh.visible then
                local x,y=b,c
                if inside(x,y,rebootButton) then drawButton(rebootButton,"REBOOTING",theme.rebootPressed); sleep(0.15); os.reboot()
                elseif inside(x,y,refreshButton) then forceTargetRefresh() end
            end
        elseif event=="timer" and a==discoveryTimer then
            requestDiscovery(); discoveryTimer=os.startTimer(discoveryInterval)
        elseif event=="timer" and a==staleTimer then
            dataDirty=true; footerDirty=true; staleTimer=os.startTimer(2)
        elseif event=="monitor_resize" and a==monitorName then
            monitor.setTextScale(0.5); calculateLayout(); structureDirty=true
        end
    end
end

local function displayLoop()
    while true do
        updateRefresh(); updatePage()
        if dataDirty then rebuildCards(); dataDirty=false end
        if structureDirty then
            fullDraw()
        else
            if headerDirty then drawHeader() end
            if footerDirty then drawFooter() end
            if popupDirty then drawPopup() end
            drawDirtyCards(); flashCritical(); animate()
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
requestDiscovery()
broadcastLowResources()
parallel.waitForAll(eventLoop,displayLoop,lowSummaryLoop)
