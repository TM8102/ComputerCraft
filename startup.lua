-- =========================================================
-- UNIVERSAL COMPUTERCRAFT STARTUP
-- Clients fetch their role program from the Master Controller.
-- Refresh broadcasts are routed through the Master so nodes are
-- updated one-at-a-time instead of all at once.
-- The startup listener also accepts PUSH ALL from the Master.
-- Clients heartbeat/register so the Master always knows them.
-- Master also runs web_status_publisher.lua for GitHub Pages.
-- =========================================================

local masterProtocol = "cc_master_update"
local rawBase = "https://raw.githubusercontent.com/TM8102/ComputerCraft/main/"
local roleFile = ".computer_role"
local masterTimeout = 3
local heartbeatSeconds = 10
local webPublisherFile = "web_status_publisher.lua"

local roles = {
    ["1"] = { name="MAIN STORAGE SCREEN", file="main_storage.lua" },
    ["2"] = { name="STORAGE BRAIN", file="storage_brain.lua", refreshGroup="targets" },
    ["3"] = { name="STORAGE + MACHINE NODE", file="storage_machine_node.lua", refreshGroup="targets" },
    ["4"] = { name="RESOURCE GENERATOR", file="resource_generator.lua", refreshGroup="targets" },
    ["5"] = { name="TIME WAND CONTROLLER", file="time_wand_controller.lua" },
    ["6"] = { name="MOB CONTROL PANEL", file="mob_control_panel.lua" },
    ["7"] = { name="REMOTE SPAWNER NODE", file="remote_spawner_node.lua", refreshGroup="spawners" },
    ["8"] = { name="MAIN STATUS SCREEN", file="main_status_screen.lua" },
    ["9"] = { name="MASTER CONTROLLER", file="master_controller.lua", master=true }
}

local function clearScreen()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1,1)
end

local function saveRole(role)
    local f=fs.open(roleFile,"w")
    if not f then error("Could not save computer role") end
    f.write(role); f.close()
end

local function loadRole()
    if not fs.exists(roleFile) then return nil end
    local f=fs.open(roleFile,"r")
    if not f then return nil end
    local role=f.readAll(); f.close()
    return roles[role] and role or nil
end

local function chooseRole()
    while true do
        clearScreen()
        print("COMPUTER ROLE SETUP")
        print("===================")
        print("")
        for i=1,9 do
            local role=roles[tostring(i)]
            print(i.." - "..role.name)
        end
        print("")
        write("Choose role: ")
        local choice=read()
        if roles[choice] then saveRole(choice); return choice end
        print("Invalid choice."); sleep(1)
    end
end

local function openAnyModem()
    for _,side in ipairs({"back","front","left","right","top","bottom"}) do
        if peripheral.isPresent(side) and peripheral.getType(side)=="modem" then
            if not rednet.isOpen(side) then rednet.open(side) end
            return side
        end
    end
end

local function validateProgram(program,contents)
    if not contents or contents=="" then return false,"Empty file" end
    local loader,err=load(contents,"@"..program,"t",_ENV)
    if not loader then return false,"Lua error: "..tostring(err) end
    return true
end

local function installProgram(program,contents)
    local ok,err=validateProgram(program,contents)
    if not ok then return false,err end
    local temp=program..".new"
    if fs.exists(temp) then fs.delete(temp) end
    local f=fs.open(temp,"w")
    if not f then return false,"Could not create "..temp end
    f.write(contents); f.close()
    if fs.exists(program) then fs.delete(program) end
    fs.move(temp,program)
    return true
end

local function downloadFromMaster(program,roleNumber,role)
    if not openAnyModem() then return false,"No modem available" end
    local requestID=tostring(os.getComputerID())..":"..tostring(os.epoch("utc"))
    rednet.broadcast({
        type="get_file", file=program, requestID=requestID,
        clientID=os.getComputerID(), roleNumber=roleNumber,
        roleName=role.name, roleFile=role.file,
        refreshGroup=role.refreshGroup
    },masterProtocol)

    local timer=os.startTimer(masterTimeout)
    while true do
        local event,a,b,c=os.pullEvent()
        if event=="rednet_message" then
            local senderID,message,protocol=a,b,c
            if protocol==masterProtocol and type(message)=="table"
                and message.type=="file_response"
                and message.requestID==requestID and message.file==program then
                if not message.success then return false,"Master error: "..tostring(message.error) end
                local ok,err=installProgram(program,message.contents)
                if not ok then return false,err end
                return true,"MASTER "..tostring(senderID)
            end
        elseif event=="timer" and a==timer then
            return false,"Master timeout"
        end
    end
end

local function downloadFromRawGitHub(program)
    local url=rawBase..program.."?cb="..tostring(os.epoch("utc"))
    local response,httpError=http.get(url,{
        ["User-Agent"]="CC-Tweaked",
        ["Cache-Control"]="no-cache, no-store",
        ["Pragma"]="no-cache"
    })
    if not response then return false,"GitHub RAW failed: "..tostring(httpError) end
    local code=response.getResponseCode and response.getResponseCode() or 200
    local contents=response.readAll(); response.close()
    if code<200 or code>=300 then return false,"GitHub RAW HTTP "..tostring(code) end
    local ok,err=installProgram(program,contents)
    if not ok then return false,err end
    return true,"GITHUB RAW"
end

local function registerWithMaster(roleNumber,role)
    if not openAnyModem() then return end
    rednet.broadcast({
        type="register_client",
        clientID=os.getComputerID(),
        roleNumber=roleNumber,
        roleName=role.name,
        roleFile=role.file,
        refreshGroup=role.refreshGroup,
        timestamp=os.epoch("utc")
    },masterProtocol)
end

local originalBroadcast=rednet.broadcast
local function installRefreshRouter()
    rednet.broadcast=function(message,protocol)
        if type(message)=="table" then
            if protocol=="config_control" and message.command=="force_targets_refresh" then
                return originalBroadcast({
                    type="sequential_refresh",
                    kind="targets",
                    requester=os.getComputerID(),
                    originalMessage=message,
                    timestamp=os.epoch("utc")
                },masterProtocol)
            elseif protocol=="spawner_config_control" and message.command=="force_spawners_refresh" then
                return originalBroadcast({
                    type="sequential_refresh",
                    kind="spawners",
                    requester=os.getComputerID(),
                    originalMessage=message,
                    timestamp=os.epoch("utc")
                },masterProtocol)
            end
        end
        return originalBroadcast(message,protocol)
    end
end

local function masterControlListener(roleNumber,role)
    while true do
        local senderID,message,protocol=rednet.receive(masterProtocol,heartbeatSeconds)

        if senderID and type(message)=="table" then
            if message.type=="push_update" then
                clearScreen()
                term.setTextColor(colors.cyan)
                print("MASTER PUSH UPDATE")
                term.setTextColor(colors.white)
                print("Rebooting to pull latest files...")
                sleep(0.35)
                os.reboot()

            elseif message.type=="discover_clients" then
                registerWithMaster(roleNumber,role)
            end
        else
            registerWithMaster(roleNumber,role)
        end
    end
end

clearScreen()
local roleNumber=loadRole() or chooseRole()
local role=roles[roleNumber]

clearScreen()
print(role.name)
print(string.rep("=",#role.name))
print("")
print("Computer ID: "..os.getComputerID())
print("Program: "..role.file)
print("")

local success,sourceOrError
if role.master then
    print("Master bootstrap: GitHub RAW")
    success,sourceOrError=downloadFromRawGitHub(role.file)
    local webOK,webSource=downloadFromRawGitHub(webPublisherFile)
    if webOK then
        print("Web publisher updated from "..tostring(webSource))
    else
        term.setTextColor(colors.orange)
        print("Web publisher update failed: "..tostring(webSource))
        term.setTextColor(colors.white)
        if not fs.exists(webPublisherFile) then
            print("Web dashboard publisher will be unavailable this boot.")
        end
    end
else
    print("Looking for Master Controller...")
    success,sourceOrError=downloadFromMaster(role.file,roleNumber,role)
    if not success then
        term.setTextColor(colors.orange)
        print("Master unavailable: "..tostring(sourceOrError))
        term.setTextColor(colors.white)
        print("Falling back to GitHub RAW...")
        success,sourceOrError=downloadFromRawGitHub(role.file)
    end
end

if success then
    term.setTextColor(colors.lime)
    print("Updated from "..tostring(sourceOrError))
    term.setTextColor(colors.white)
else
    term.setTextColor(colors.orange)
    print("UPDATE FAILED")
    term.setTextColor(colors.white)
    print(tostring(sourceOrError)); print("")
    if fs.exists(role.file) then
        print("Using existing local copy.")
    else
        term.setTextColor(colors.red); print("No local copy available."); term.setTextColor(colors.white)
        return
    end
end

print("")
print("Starting "..role.file.."...")
sleep(0.5)

if role.master then
    if fs.exists(webPublisherFile) then
        parallel.waitForAny(
            function() shell.run(role.file) end,
            function() shell.run(webPublisherFile) end
        )
    else
        shell.run(role.file)
    end
else
    openAnyModem()
    registerWithMaster(roleNumber,role)
    installRefreshRouter()
    parallel.waitForAny(
        function() shell.run(role.file) end,
        function() masterControlListener(roleNumber,role) end
    )
end
