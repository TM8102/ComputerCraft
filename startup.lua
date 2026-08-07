-- =========================================================
-- UNIVERSAL COMPUTERCRAFT STARTUP
-- Downloads the newest role script from the GitHub API on
-- every reboot, then launches it. Role is selected once and
-- saved in .computer_role.
-- =========================================================

local githubBase =
    "https://api.github.com/repos/TM8102/ComputerCraft/contents/"

local roleFile = ".computer_role"

local roles = {
    ["1"] = { name = "MAIN STORAGE SCREEN", file = "main_storage.lua" },
    ["2"] = { name = "STORAGE BRAIN", file = "storage_brain.lua" },
    ["3"] = { name = "STORAGE + MACHINE NODE", file = "storage_machine_node.lua" },
    ["4"] = { name = "RESOURCE GENERATOR", file = "resource_generator.lua" },
    ["5"] = { name = "TIME WAND CONTROLLER", file = "time_wand_controller.lua" },
    ["6"] = { name = "MOB CONTROL PANEL", file = "mob_control_panel.lua" },
    ["7"] = { name = "REMOTE SPAWNER NODE", file = "remote_spawner_node.lua" },
    ["8"] = { name = "MAIN STATUS SCREEN", file = "main_status_screen.lua" }
}

local function clearScreen()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1,1)
end

local function saveRole(role)
    local f = fs.open(roleFile,"w")
    if not f then error("Could not save computer role") end
    f.write(role)
    f.close()
end

local function loadRole()
    if not fs.exists(roleFile) then return nil end
    local f = fs.open(roleFile,"r")
    if not f then return nil end
    local role = f.readAll()
    f.close()
    return roles[role] and role or nil
end

local function chooseRole()
    while true do
        clearScreen()
        print("COMPUTER ROLE SETUP")
        print("===================")
        print("")
        print("1 - Main Storage Screen")
        print("2 - Storage Brain")
        print("3 - Storage + Machine Node")
        print("4 - Resource Generator")
        print("5 - Time Wand Controller")
        print("6 - Mob Control Panel")
        print("7 - Remote Spawner Node")
        print("8 - Main Status Screen")
        print("")
        write("Choose role: ")
        local choice = read()
        if roles[choice] then
            saveRole(choice)
            return choice
        end
        print("Invalid choice.")
        sleep(1)
    end
end

local function downloadProgram(program)
    local url = githubBase .. program
        .. "?ref=main&cb=" .. tostring(os.epoch("utc"))

    print("Downloading latest:")
    print(program)
    print("")

    local response, httpError = http.get(url,{
        ["User-Agent"] = "CC-Tweaked",
        ["Accept"] = "application/vnd.github.raw+json",
        ["Cache-Control"] = "no-cache, no-store",
        ["Pragma"] = "no-cache"
    })

    if not response then return false,"GitHub API failed: "..tostring(httpError) end
    local code = response.getResponseCode and response.getResponseCode() or 200
    local contents = response.readAll()
    response.close()

    if code < 200 or code >= 300 then return false,"GitHub HTTP "..tostring(code) end
    if not contents or contents == "" then return false,"GitHub returned an empty file" end

    local temp = program .. ".new"
    if fs.exists(temp) then fs.delete(temp) end
    local f = fs.open(temp,"w")
    if not f then return false,"Could not create "..temp end
    f.write(contents)
    f.close()

    local loader, syntaxError = loadfile(temp)
    if not loader then
        fs.delete(temp)
        return false,"Downloaded Lua error: "..tostring(syntaxError)
    end

    if fs.exists(program) then fs.delete(program) end
    fs.move(temp,program)
    return true
end

clearScreen()
local roleNumber = loadRole() or chooseRole()
local role = roles[roleNumber]

clearScreen()
print(role.name)
print(string.rep("=",#role.name))
print("")
print("Computer ID: "..os.getComputerID())
print("Program: "..role.file)
print("")

local success, downloadError = downloadProgram(role.file)
if success then
    term.setTextColor(colors.lime)
    print("Updated successfully.")
    term.setTextColor(colors.white)
else
    term.setTextColor(colors.orange)
    print("UPDATE FAILED")
    term.setTextColor(colors.white)
    print(tostring(downloadError))
    print("")
    if fs.exists(role.file) then
        print("Using existing local copy.")
    else
        term.setTextColor(colors.red)
        print("No local copy available.")
        term.setTextColor(colors.white)
        return
    end
end

print("")
print("Starting "..role.file.."...")
sleep(0.5)
shell.run(role.file)
