-- =========================================================
-- MAIN STATUS SCREEN
-- Quick overview of resource machines, storage demand,
-- spawners, and mob-farm fans.
-- =========================================================

local machineStatusProtocol = "resource_machine_status"
local storageStatusProtocol = "inventory_status"
local spawnerStatusProtocol = "spawner_status"
local fanProtocol = "mob_farm_fans"
local offlineSeconds = 12
local renderInterval = 0.5

local modemSide
local monitor
local monitorName

for _, side in ipairs({"top","bottom","left","right","front","back"}) do
    if peripheral.isPresent(side) then
        local p = peripheral.wrap(side)
        local t = peripheral.getType(side)
        if not modemSide and t == "modem" then modemSide = side end
        if not monitor and p and type(p.isColor) == "function" and p.isColor() then
            monitor = p
            monitorName = peripheral.getName(p)
        end
    end
end

if not modemSide then error("No modem found") end
if not monitor then error("No Advanced Monitor found") end
rednet.open(modemSide)
monitor.setTextScale(0.5)

local machines = {}
local storage = {}
local spawners = {}
local fansState = nil
local screenDirty = true

local function now() return os.epoch("utc") end
local function keyForSpawner(id, key) return tostring(id) .. ":" .. tostring(key) end
local function short(s, n)
    s = tostring(s or "")
    if #s <= n then return s end
    return string.sub(s,1,math.max(1,n-2)) .. ".."
end
local function pct(amount, target)
    amount, target = tonumber(amount), tonumber(target)
    if not amount or not target or target <= 0 then return nil end
    return amount / target * 100
end

local function processMachine(sender, m)
    if type(m) ~= "table" or m.messageType ~= "resource_machine_status" or type(m.itemID) ~= "string" then return end
    local row = machines[m.itemID] or {}
    row.itemID = m.itemID
    row.name = m.displayName or row.name or m.itemID
    row.computerID = m.computerID or sender
    row.machineKey = m.machineKey
    row.side = m.side
    row.requested = m.requested ~= nil and (m.requested == true) or (m.state == true)
    row.running = m.running ~= nil and (m.running == true) or (m.state == true)
    row.amount = tonumber(m.amount) or row.amount
    row.target = tonumber(m.target) or row.target
    row.percent = tonumber(m.percent) or row.percent
    row.lastUpdate = now()
    machines[m.itemID] = row
    screenDirty = true
end

local function processStorage(m)
    if type(m) ~= "table" or m.messageType ~= "inventory_update" then return end
    local itemID = m.itemID or m.storageKey
    if type(itemID) ~= "string" then return end
    storage[itemID] = {
        amount = tonumber(m.amount) or 0,
        target = tonumber(m.targetAmount or m.target) or 0,
        name = m.displayName or itemID,
        lastUpdate = now()
    }
    screenDirty = true
end

local function processSpawner(sender, m)
    if type(m) ~= "table" or m.messageType ~= "spawner_status" then return end
    local k = keyForSpawner(sender, m.spawnerKey)
    spawners[k] = {
        name = m.displayName or m.spawnerKey or k,
        state = m.state == true,
        lastUpdate = now()
    }
    screenDirty = true
end

local function processFan(m)
    if type(m) == "table" and m.command == "fans" then
        fansState = m.state == true
        screenDirty = true
    end
end

local function fill(x1,y1,x2,y2,bg)
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

local function draw()
    local w,h = monitor.getSize()
    fill(1,1,w,h,colors.black)
    fill(1,1,w,4,colors.cyan)
    writeAt(3,2,"SYSTEM STATUS",colors.black,colors.cyan)
    writeAt(3,3,"RESOURCE / MOB QUICK VIEW",colors.gray,colors.cyan)

    local nowMs = now()
    local rows = {}
    for itemID,m in pairs(machines) do
        local s = storage[itemID]
        if s then
            m.name = s.name or m.name
            m.amount = s.amount
            m.target = s.target
            m.percent = pct(s.amount,s.target)
        end
        rows[#rows+1] = m
    end
    table.sort(rows,function(a,b) return string.lower(a.name or a.itemID) < string.lower(b.name or b.itemID) end)

    local y = 6
    writeAt(2,y,"RESOURCE",colors.lightGray,colors.black)
    writeAt(math.floor(w*0.46),y,"REQ",colors.lightGray,colors.black)
    writeAt(math.floor(w*0.58),y,"RUN",colors.lightGray,colors.black)
    writeAt(math.floor(w*0.69),y,"PC",colors.lightGray,colors.black)
    writeAt(math.floor(w*0.80),y,"LEVEL",colors.lightGray,colors.black)
    y = y + 1

    local maxRows = math.max(1,h-13)
    for i=1,math.min(#rows,maxRows) do
        local m = rows[i]
        local online = (nowMs - (m.lastUpdate or 0)) <= offlineSeconds*1000
        local reqText = m.requested and "YES" or "NO"
        local runText = online and (m.running and "ON" or "OFF") or "LOST"
        local level = m.percent and string.format("%.0f%%",m.percent) or "--"
        writeAt(2,y,short(m.name or m.itemID,math.floor(w*0.42)-2),colors.white,colors.black)
        writeAt(math.floor(w*0.46),y,reqText,m.requested and colors.orange or colors.gray,colors.black)
        writeAt(math.floor(w*0.58),y,runText,(online and m.running) and colors.lime or (online and colors.red or colors.orange),colors.black)
        writeAt(math.floor(w*0.69),y,tostring(m.computerID or "?"),colors.lightBlue,colors.black)
        writeAt(math.floor(w*0.80),y,level,colors.white,colors.black)
        y = y + 1
    end

    local configured, active, offline = 0,0,0
    for _,s in pairs(spawners) do
        configured = configured + 1
        if nowMs - (s.lastUpdate or 0) > offlineSeconds*1000 then
            offline = offline + 1
        elseif s.state then
            active = active + 1
        end
    end

    local footerY = h-3
    fill(1,footerY,w,h,colors.gray)
    writeAt(2,footerY+1,"MACHINES "..#rows.."  REQUESTED "..(function() local c=0 for _,m in ipairs(rows) do if m.requested then c=c+1 end end return c end)().."  RUNNING "..(function() local c=0 for _,m in ipairs(rows) do if m.running and nowMs-(m.lastUpdate or 0)<=offlineSeconds*1000 then c=c+1 end end return c end)(),colors.white,colors.gray)
    writeAt(2,footerY+2,"SPAWNERS "..configured.."  ACTIVE "..active.."  OFFLINE "..offline.."  FANS "..(fansState==nil and "?" or (fansState and "ON" or "OFF")),colors.white,colors.gray)
end

local function eventLoop()
    while true do
        local event,a,b,c = os.pullEvent()
        if event == "rednet_message" then
            if c == machineStatusProtocol then processMachine(a,b)
            elseif c == storageStatusProtocol then processStorage(b)
            elseif c == spawnerStatusProtocol then processSpawner(a,b)
            elseif c == fanProtocol then processFan(b) end
        elseif event == "monitor_resize" and a == monitorName then
            monitor.setTextScale(0.5)
            screenDirty = true
        end
    end
end

local function renderLoop()
    while true do
        if screenDirty then screenDirty=false; draw() end
        sleep(renderInterval)
        screenDirty = true
    end
end

parallel.waitForAll(eventLoop,renderLoop)
