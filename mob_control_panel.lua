-- =========================================================
-- MOB CONTROL PANEL
-- Master controls, fan clear-out timer, Pink Slime override,
-- live spawner discovery, and Storage-style refresh debug.
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

local maxSpawners = 45
local offlineSeconds = 12
local removeAfterSeconds = 60
local startupDiscoverySeconds = 15
local discoveryInterval = 5
local animationSpeed = 0.15
local fanShutdownSeconds = 30
local refreshWaitSeconds = 5
local refreshResultSeconds = 10

local monitor = peripheral.wrap(monitorSide)
if not monitor then error("No monitor found on "..monitorSide) end
if not monitor.isColor() then error("Advanced Monitor required") end
if not peripheral.isPresent(modemSide) then error("No modem found on "..modemSide) end
rednet.open(modemSide)
monitor.setTextScale(0.5)
local monitorName = peripheral.getName(monitor)

local theme = {
    background=colors.black, header=colors.cyan, headerText=colors.black,
    subtext=colors.gray, accent=colors.blue, card=colors.gray,
    emptyCard=colors.black, runningDark=colors.green,runningBright=colors.lime,
    off=colors.red,offlineA=colors.red,offlineB=colors.orange,
    emptyBorder=colors.gray,title=colors.white,placeholder=colors.gray,
    masterOn=colors.green,masterOff=colors.red,fanOn=colors.lime,fanOff=colors.red,
    refresh=colors.green,refreshPressed=colors.lime,reboot=colors.blue,
    rebootPressed=colors.lightBlue,footer=colors.gray,footerText=colors.white,
    popup=colors.gray,popupBorder=colors.lightGray,popupTitle=colors.cyan,
    success=colors.lime,failure=colors.red,pending=colors.orange
}

local spawners = {}
local buttons = {masterOn={},masterOff={},fans={},refresh={},reboot={}}
local fansState = false
local fanShutdownRemaining = 0
local fanShutdownTimer = nil
local animationFrame = 0
local startupCheckComplete = false
local pinkSlimeAutomationActive = false
local pinkSlimeSnapshot = nil
local knownNodes = {}

local refresh = {visible=false,running=false,started=0,finishedAt=0,expected={},responses={}}

local function now() return os.epoch("utc") end
local function fill(x1,y1,x2,y2,color)
    if x2<x1 or y2<y1 then return end
    monitor.setBackgroundColor(color)
    for y=y1,y2 do monitor.setCursorPos(x1,y); monitor.write(string.rep(" ",x2-x1+1)) end
end
local function writeAt(x,y,text,fg,bg)
    monitor.setCursorPos(x,y); monitor.setTextColor(fg); monitor.setBackgroundColor(bg); monitor.write(tostring(text))
end
local function shorten(text,n)
    text=tostring(text or "")
    if #text<=n then return text end
    if n<=3 then return string.sub(text,1,n) end
    return string.sub(text,1,n-2)..".."
end
local function center(x1,x2,y,text,fg,bg)
    local width=x2-x1+1; text=shorten(text,width)
    writeAt(x1+math.floor((width-#text)/2),y,text,fg,bg)
end
local function border(x1,y1,x2,y2,color)
    fill(x1,y1,x2,y1,color); fill(x1,y2,x2,y2,color); fill(x1,y1,x1,y2,color); fill(x2,y1,x2,y2,color)
end
local function inside(x,y,b) return x>=b.x1 and x<=b.x2 and y>=b.y1 and y<=b.y2 end
local function points(x1,y1,x2,y2)
    local p={}
    for x=x1,x2 do p[#p+1]={x=x,y=y1} end
    for y=y1+1,y2-1 do p[#p+1]={x=x2,y=y} end
    for x=x2,x1,-1 do p[#p+1]={x=x,y=y2} end
    for y=y2-1,y1+1,-1 do p[#p+1]={x=x1,y=y} end
    return p
end

local function emptySpawner()
    return {name="",computerID=0,spawnerKey="",state=false,online=false,lastUpdate=0,seenSinceBoot=false,x1=0,y1=0,x2=0,y2=0,titleY=0,borderPoints={}}
end
for i=1,maxSpawners do spawners[i]=emptySpawner() end

local function saveDatabase()
    local saved={}
    for i,s in ipairs(spawners) do
        if s.computerID~=0 and s.spawnerKey~="" then saved[i]={computerID=s.computerID,spawnerKey=s.spawnerKey,name=s.name} end
    end
    local f=fs.open(databaseFile,"w")
    if f then f.write(textutils.serialize(saved)); f.close() end
end
local function loadDatabase()
    if not fs.exists(databaseFile) then return end
    local f=fs.open(databaseFile,"r"); if not f then return end
    local raw=f.readAll(); f.close()
    local ok,saved=pcall(textutils.unserialize,raw)
    if not ok or type(saved)~="table" then return end
    for i=1,maxSpawners do
        local src=saved[i]
        if src then spawners[i].computerID=tonumber(src.computerID) or 0; spawners[i].spawnerKey=tostring(src.spawnerKey or ""); spawners[i].name=tostring(src.name or "") end
    end
end
loadDatabase()

local function clearSpawner(s)
    local fresh=emptySpawner()
    for k,v in pairs(fresh) do s[k]=v end
end
local function compactRegistry()
    local keep={}
    for _,s in ipairs(spawners) do
        if s.computerID~=0 and s.spawnerKey~="" then
            keep[#keep+1]={name=s.name,computerID=s.computerID,spawnerKey=s.spawnerKey,state=s.state,online=s.online,lastUpdate=s.lastUpdate,seenSinceBoot=s.seenSinceBoot}
        end
    end
    for i=1,maxSpawners do
        clearSpawner(spawners[i]); local src=keep[i]
        if src then for k,v in pairs(src) do spawners[i][k]=v end end
    end
    saveDatabase()
end
local function findSpawner(computerID,key)
    for i,s in ipairs(spawners) do if s.computerID==computerID and s.spawnerKey==key then return s,i end end
end
local function registerSpawner(computerID,key,name)
    if type(key)~="string" or key=="" then return nil end
    local s,index=findSpawner(computerID,key)
    if not s then for i,c in ipairs(spawners) do if c.computerID==0 then s,index=c,i break end end end
    if not s then return nil end
    s.computerID=computerID; s.spawnerKey=key
    if type(name)=="string" and name~="" then s.name=name end
    s.online=true; s.seenSinceBoot=true; s.lastUpdate=now(); saveDatabase()
    return s,index
end

local function rememberNode(id,role)
    knownNodes[id]={role=role or "REMOTE_SPAWNER",lastSeen=now()}
end

local function calculateLayout()
    local width,height=monitor.getSize()
    local columns,rows=5,9; local cardHeight,gapX,gapY=5,1,1
    local topY,bottomY=7,height-2; local availableWidth=width-2; local availableHeight=bottomY-topY+1
    local cardWidth=math.floor((availableWidth-gapX*(columns-1))/columns)
    if cardWidth<10 then error("Monitor too narrow") end
    local gridWidth=columns*cardWidth+gapX*(columns-1); local gridHeight=rows*cardHeight+gapY*(rows-1)
    if gridHeight>availableHeight then error("Monitor too short") end
    local startX=math.floor((width-gridWidth)/2)+1; local startY=topY+math.floor((availableHeight-gridHeight)/2)
    for i,s in ipairs(spawners) do
        local col=(i-1)%columns; local row=math.floor((i-1)/columns)
        s.x1=startX+col*(cardWidth+gapX); s.y1=startY+row*(cardHeight+gapY)
        s.x2=s.x1+cardWidth-1; s.y2=s.y1+cardHeight-1; s.titleY=s.y1+2
        s.borderPoints=points(s.x1,s.y1,s.x2,s.y2)
    end
    local bw,gap=14,1
    buttons.reboot.x2=width-2; buttons.reboot.x1=buttons.reboot.x2-bw+1
    buttons.refresh.x2=buttons.reboot.x1-gap-1; buttons.refresh.x1=buttons.refresh.x2-bw+1
    buttons.fans.x2=buttons.refresh.x1-gap-1; buttons.fans.x1=buttons.fans.x2-bw+1
    buttons.masterOff.x2=buttons.fans.x1-gap-1; buttons.masterOff.x1=buttons.masterOff.x2-bw+1
    buttons.masterOn.x2=buttons.masterOff.x1-gap-1; buttons.masterOn.x1=buttons.masterOn.x2-bw+1
    for _,b in pairs(buttons) do b.y1,b.y2=2,4 end
end

local function drawButton(b,text,color) fill(b.x1,b.y1,b.x2,b.y2,color); center(b.x1,b.x2,3,text,colors.white,color) end
local function drawFanButton()
    if fanShutdownRemaining>0 then drawButton(buttons.fans,"FANS "..fanShutdownRemaining.."s",theme.fanOn)
    elseif fansState then drawButton(buttons.fans,"FANS: ON",theme.fanOn)
    else drawButton(buttons.fans,"FANS: OFF",theme.fanOff) end
end
local function drawHeader()
    local width=monitor.getSize(); fill(1,1,width,5,theme.header)
    writeAt(3,2,"SPAWNER CONTROL",theme.headerText,theme.header)
    writeAt(3,3,pinkSlimeAutomationActive and "PINK SLIME AUTO ACTIVE" or "DYNAMIC MOB MANAGEMENT",pinkSlimeAutomationActive and colors.red or theme.subtext,theme.header)
    drawButton(buttons.masterOn,pinkSlimeAutomationActive and "AUTO: ON" or "MASTER ON",theme.masterOn)
    drawButton(buttons.masterOff,"MASTER OFF",theme.masterOff); drawFanButton()
    drawButton(buttons.refresh,"REFRESH",refresh.running and theme.refreshPressed or theme.refresh)
    drawButton(buttons.reboot,"REBOOT",theme.reboot); fill(1,6,width,6,theme.accent)
end
local function drawSpawner(s,index)
    local inner=s.computerID==0 and theme.emptyCard or theme.card
    fill(s.x1+1,s.y1+1,s.x2-1,s.y2-1,inner)
    local title=s.computerID==0 and ("SLOT "..index) or string.upper(s.name~="" and s.name or ("SPAWNER "..s.spawnerKey))
    center(s.x1+1,s.x2-1,s.titleY,title,s.computerID==0 and theme.placeholder or theme.title,inner)
    if s.computerID==0 then border(s.x1,s.y1,s.x2,s.y2,theme.emptyBorder)
    elseif not s.online then border(s.x1,s.y1,s.x2,s.y2,math.floor(animationFrame/3)%2==0 and theme.offlineA or theme.offlineB)
    elseif not s.state then border(s.x1,s.y1,s.x2,s.y2,theme.off)
    else
        local pattern={theme.runningDark,theme.runningDark,theme.runningDark,theme.runningBright,theme.runningBright,theme.runningDark}
        for i,p in ipairs(s.borderPoints) do writeAt(p.x,p.y," ",colors.white,pattern[((i+animationFrame-2)%#pattern)+1]) end
    end
end
local function counts()
    local configured,online,running,offline=0,0,0,0
    for _,s in ipairs(spawners) do
        if s.computerID~=0 then configured=configured+1; if s.online then online=online+1; if s.state then running=running+1 end else offline=offline+1 end end
    end
    return configured,online,running,offline
end
local function drawFooter()
    local width,height=monitor.getSize(); fill(1,height-1,width,height,theme.footer)
    local configured,online,running,offline=counts()
    writeAt(2,height,"ACTIVE "..running.."  ONLINE "..online.."/"..configured.."  OFFLINE "..offline,theme.footerText,theme.footer)
    local right=(pinkSlimeAutomationActive and "PINK AUTO  " or "")..(fansState and "FANS ON" or "FANS OFF")
    writeAt(math.max(2,width-#right),height,right,theme.footerText,theme.footer)
end

local function refreshCount(t) local c=0 for _ in pairs(t) do c=c+1 end return c end
local function successCount()
    local c=0 for _,r in pairs(refresh.responses) do if r.success then c=c+1 end end return c
end
local function failureCount()
    local c=0 for _,r in pairs(refresh.responses) do if not r.success then c=c+1 end end return c
end
local function drawRefreshPopup()
    if not refresh.visible then return end
    local width,height=monitor.getSize(); local pw=math.min(60,width-8); local ph=math.min(18,height-10)
    local x1=math.floor((width-pw)/2)+1; local y1=math.floor((height-ph)/2)+1; local x2=x1+pw-1; local y2=y1+ph-1
    border(x1,y1,x2,y2,theme.popupBorder); fill(x1+1,y1+1,x2-1,y2-1,theme.popup)
    center(x1+2,x2-2,y1+1,"SPAWNER REFRESH",theme.popupTitle,theme.popup)
    local expected,responses=refreshCount(refresh.expected),refreshCount(refresh.responses)
    local summary=refresh.running and ("UPDATING... "..responses.." / "..expected) or (successCount().." UPDATED / "..failureCount().." FAILED")
    center(x1+2,x2-2,y1+3,summary,colors.white,theme.popup)
    local ids={}; for id in pairs(refresh.expected) do ids[#ids+1]=id end
    for id in pairs(refresh.responses) do if not refresh.expected[id] then ids[#ids+1]=id end end
    table.sort(ids)
    local row=y1+5
    for _,id in ipairs(ids) do
        if row>=y2-1 then break end
        local result=refresh.responses[id]; local label="NODE "..id
        if result then
            writeAt(x1+3,row,result.success and "+" or "X",result.success and theme.success or theme.failure,theme.popup)
            writeAt(x1+5,row,label,colors.white,theme.popup)
            writeAt(x2-9,row,result.success and "UPDATED" or "FAILED",result.success and theme.success or theme.failure,theme.popup)
            if not result.success and result.error and row+1<y2-1 then row=row+1; writeAt(x1+7,row,shorten(result.error,pw-12),theme.failure,theme.popup) end
        else
            writeAt(x1+3,row,"?",theme.pending,theme.popup); writeAt(x1+5,row,label,colors.white,theme.popup)
            writeAt(x2-8,row,refresh.running and "WAITING" or "NO REPLY",theme.pending,theme.popup)
        end
        row=row+1
    end
    center(x1+2,x2-2,y2-1,refresh.running and "WAITING FOR NODES..." or "RESULTS CLOSE AUTOMATICALLY",refresh.running and theme.pending or colors.lightGray,theme.popup)
end

local function drawScreen()
    local width,height=monitor.getSize(); fill(1,1,width,height,theme.background); drawHeader()
    for i,s in ipairs(spawners) do drawSpawner(s,i) end
    drawFooter(); drawRefreshPopup()
end

local function sendSpawnerState(s)
    if s.computerID==0 then return end
    rednet.send(s.computerID,{command="spawn",spawnerKey=s.spawnerKey,state=s.state},controlProtocol)
end
local function sendFansState() rednet.broadcast({command="fans",state=fansState},fanProtocol) end
local function cancelFanShutdown() fanShutdownRemaining=0; fanShutdownTimer=nil end
local function setFans(state) fansState=state==true; sendFansState(); drawFanButton(); drawFooter() end
local function setAllSpawners(state)
    for i,s in ipairs(spawners) do if s.computerID~=0 then s.state=state==true; sendSpawnerState(s); drawSpawner(s,i) end end
end
local function masterOn() cancelFanShutdown(); setFans(true); setAllSpawners(true); rednet.broadcast({command="all_on"},controlProtocol); drawHeader(); drawFooter() end
local function masterOff()
    setAllSpawners(false); rednet.broadcast({command="all_off"},controlProtocol)
    fansState=true; sendFansState(); fanShutdownRemaining=fanShutdownSeconds; fanShutdownTimer=os.startTimer(1); drawHeader(); drawFooter()
end
local function toggleFans() cancelFanShutdown(); setFans(not fansState) end

local function stateKey(s) return tostring(s.computerID)..":"..tostring(s.spawnerKey) end
local function capturePinkSnapshot()
    local snap={fansState=fansState,spawners={}}
    for _,s in ipairs(spawners) do if s.computerID~=0 then snap.spawners[stateKey(s)]=s.state==true end end
    return snap
end
local function restorePinkSnapshot()
    local snap=pinkSlimeSnapshot; if not snap then return end
    cancelFanShutdown()
    for i,s in ipairs(spawners) do if s.computerID~=0 then s.state=snap.spawners[stateKey(s)]==true; sendSpawnerState(s); drawSpawner(s,i) end end
    setFans(snap.fansState==true); pinkSlimeSnapshot=nil; drawHeader(); drawFooter()
end
local function setPinkAutomation(requested)
    requested=requested==true
    if requested and not pinkSlimeAutomationActive then pinkSlimeSnapshot=capturePinkSnapshot(); pinkSlimeAutomationActive=true; masterOn()
    elseif not requested and pinkSlimeAutomationActive then pinkSlimeAutomationActive=false; restorePinkSnapshot() end
end
local function processMachineStatus(m)
    if type(m)=="table" and m.messageType=="resource_machine_status" and m.itemID==pinkSlimeItemID then setPinkAutomation(m.state==true) end
end

local function requestDiscovery() rednet.broadcast({command="discover"},controlProtocol) end
local function processManifest(senderID,m)
    rememberNode(senderID,m.role)
    if type(m.enabledKeys)~="table" then return end
    local enabled={}; for _,key in ipairs(m.enabledKeys) do enabled[key]=true end
    local changed=false
    for _,s in ipairs(spawners) do if s.computerID==senderID then if enabled[s.spawnerKey] then s.seenSinceBoot=true else clearSpawner(s); changed=true end end end
    if changed then compactRegistry(); calculateLayout(); drawScreen() end
end
local function processSpawnerStatus(senderID,m)
    rememberNode(senderID,m.role)
    if m.messageType~="spawner_status" then return end
    local s,index=registerSpawner(senderID,m.spawnerKey,m.displayName); if not s then return end
    s.state=m.state==true; s.online=true; s.seenSinceBoot=true; s.lastUpdate=now()
    if pinkSlimeAutomationActive and not s.state then s.state=true; sendSpawnerState(s) end
    if not refresh.visible then drawSpawner(s,index); drawFooter() end
end

local function startRefresh()
    refresh.visible=true; refresh.running=true; refresh.started=now(); refresh.finishedAt=0; refresh.responses={}; refresh.expected={}
    local t=now()
    for id,info in pairs(knownNodes) do if t-(info.lastSeen or 0)<=offlineSeconds*1000 then refresh.expected[id]=true end end
    rednet.broadcast({command="force_spawners_refresh",requestedBy=os.getComputerID(),timestamp=now()},configControlProtocol)
    drawScreen()
end
local function processRefreshStatus(senderID,m)
    rememberNode(senderID,m.role)
    if m.command~="spawners_refresh_status" then return end
    refresh.visible=true
    refresh.responses[senderID]={success=m.success==true,error=m.error,role=m.role,configSource=m.configSource,timestamp=now()}
    drawScreen()
end
local function updateRefresh()
    if not refresh.visible then return end
    local t=now()
    if refresh.running then
        local expected,responses=refreshCount(refresh.expected),refreshCount(refresh.responses)
        if (expected>0 and responses>=expected) or t-refresh.started>=refreshWaitSeconds*1000 then refresh.running=false; refresh.finishedAt=t; drawScreen() end
    elseif refresh.finishedAt>0 and t-refresh.finishedAt>=refreshResultSeconds*1000 then refresh.visible=false; drawScreen() end
end

local function finishStartupCleanup()
    if startupCheckComplete then return end; startupCheckComplete=true
    local changed=false
    for _,s in ipairs(spawners) do if s.computerID~=0 and not s.seenSinceBoot then clearSpawner(s); changed=true end end
    if changed then compactRegistry(); calculateLayout(); drawScreen() end
end
local function updateOffline()
    local t=now(); local removed=false
    for i,s in ipairs(spawners) do
        if s.computerID~=0 and s.lastUpdate>0 then
            local age=t-s.lastUpdate
            if age>removeAfterSeconds*1000 then clearSpawner(s); removed=true
            elseif age>offlineSeconds*1000 and s.online then s.online=false; if not refresh.visible then drawSpawner(s,i) end end
        end
    end
    if removed then compactRegistry(); calculateLayout(); drawScreen() elseif not refresh.visible then drawFooter() end
end
local function rebootComputer()
    drawButton(buttons.reboot,"REBOOT",theme.rebootPressed); sleep(0.3); monitor.setBackgroundColor(colors.black); monitor.clear()
    local width,height=monitor.getSize(); center(1,width,math.floor(height/2),"REBOOTING SPAWNER CONTROL...",colors.cyan,colors.black); sleep(0.7); os.reboot()
end

calculateLayout(); drawScreen(); requestDiscovery()
local animationTimer=os.startTimer(animationSpeed)
local offlineTimer=os.startTimer(2)
local discoveryTimer=os.startTimer(discoveryInterval)
local startupTimer=os.startTimer(startupDiscoverySeconds)
local refreshTimer=os.startTimer(0.5)

while true do
    local event,a,b,c=os.pullEvent()
    if event=="monitor_touch" and a==monitorName then
        local x,y=b,c
        if not refresh.visible then
            if inside(x,y,buttons.masterOn) then masterOn()
            elseif inside(x,y,buttons.masterOff) then masterOff()
            elseif inside(x,y,buttons.fans) then toggleFans()
            elseif inside(x,y,buttons.refresh) then startRefresh()
            elseif inside(x,y,buttons.reboot) then rebootComputer()
            else
                for i,s in ipairs(spawners) do
                    if s.computerID~=0 and x>=s.x1 and x<=s.x2 and y>=s.y1 and y<=s.y2 then s.state=not s.state; sendSpawnerState(s); drawSpawner(s,i); drawFooter(); break end
                end
            end
        end
    elseif event=="rednet_message" then
        local senderID,message,protocol=a,b,c
        if protocol==statusProtocol and type(message)=="table" then
            if message.messageType=="spawner_manifest" then processManifest(senderID,message)
            elseif message.messageType=="spawner_status" then processSpawnerStatus(senderID,message) end
        elseif protocol==configStatusProtocol and type(message)=="table" then processRefreshStatus(senderID,message)
        elseif protocol==machineStatusProtocol and type(message)=="table" then processMachineStatus(message) end
    elseif event=="timer" and a==animationTimer then
        animationFrame=animationFrame+1
        if not refresh.visible then for i,s in ipairs(spawners) do if s.computerID~=0 then drawSpawner(s,i) end end end
        animationTimer=os.startTimer(animationSpeed)
    elseif event=="timer" and a==offlineTimer then updateOffline(); offlineTimer=os.startTimer(2)
    elseif event=="timer" and a==discoveryTimer then requestDiscovery(); discoveryTimer=os.startTimer(discoveryInterval)
    elseif event=="timer" and a==startupTimer then finishStartupCleanup()
    elseif event=="timer" and a==refreshTimer then updateRefresh(); refreshTimer=os.startTimer(0.5)
    elseif event=="timer" and fanShutdownTimer and a==fanShutdownTimer then
        fanShutdownRemaining=math.max(0,fanShutdownRemaining-1)
        if fanShutdownRemaining>0 then fanShutdownTimer=os.startTimer(1) else fanShutdownTimer=nil; setFans(false) end
        if not refresh.visible then drawFanButton(); drawFooter() end
    elseif event=="monitor_resize" and a==monitorName then monitor.setTextScale(0.5); calculateLayout(); drawScreen() end
end
