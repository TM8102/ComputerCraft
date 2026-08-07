-- =========================================================
-- UNIVERSAL COMPUTERCRAFT STARTUP
--
-- First run:
--   choose this computer's role once.
--
-- Every reboot:
--   downloads the newest role script from GitHub API,
--   replaces the old local copy only after a good download,
--   then launches it.
-- =========================================================

local githubBase =
    "https://api.github.com/repos/TM8102/ComputerCraft/contents/"

local roleFile = ".computer_role"

local roles = {
    ["1"] = {
        name = "MAIN SCREEN",
        file = "main_storage.lua"
    },

    ["2"] = {
        name = "STORAGE BRAIN",
        file = "storage_brain.lua"
    },

    ["3"] = {
        name = "STORAGE + MACHINE NODE",
        file = "storage_machine_node.lua"
    },

    ["4"] = {
        name = "RESOURCE GENERATOR",
        file = "resource_generator.lua"
    },

    ["5"] = {
        name = "TIME WAND CONTROLLER",
        file = "time_wand_controller.lua"
    },

    ["6"] = {
        name = "MOB CONTROL PANEL",
        file = "mob_control_panel.lua"
    },

    ["7"] = {
        name = "REMOTE SPAWNER NODE",
        file = "remote_spawner_node.lua"
    }
}

local function clearScreen()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
end

local function saveRole(roleNumber)
    local file = fs.open(roleFile, "w")

    if not file then
        error("Could not save computer role")
    end

    file.write(roleNumber)
    file.close()
end

local function loadRole()
    if not fs.exists(roleFile) then
        return nil
    end

    local file = fs.open(roleFile, "r")

    if not file then
        return nil
    end

    local roleNumber = file.readAll()
    file.close()

    if roles[roleNumber] then
        return roleNumber
    end

    return nil
end

local function chooseRole()
    while true do
        clearScreen()

        print("COMPUTER ROLE SETUP")
        print("===================")
        print("")
        print("1 - Main Screen")
        print("2 - Storage Brain")
        print("3 - Storage + Machine Node")
        print("4 - Resource Generator")
        print("5 - Time Wand Controller")
        print("6 - Mob Control Panel")
        print("7 - Remote Spawner Node")
        print("")
        write("Choose role: ")

        local choice = read()

        if roles[choice] then
            saveRole(choice)
            return choice
        end

        print("")
        print("Invalid choice.")
        sleep(1)
    end
end

local function downloadProgram(program)
    local cacheBuster = tostring(os.epoch("utc"))

    local url =
        githubBase
        .. program
        .. "?ref=main&cb="
        .. cacheBuster

    print("Downloading latest:")
    print(program)
    print("")

    local response, httpError = http.get(
        url,
        {
            ["User-Agent"] = "CC-Tweaked",
            ["Accept"] = "application/vnd.github.raw+json",
            ["Cache-Control"] = "no-cache, no-store",
            ["Pragma"] = "no-cache"
        }
    )

    if not response then
        return false,
            "GitHub API failed: " .. tostring(httpError)
    end

    local code =
        response.getResponseCode
        and response.getResponseCode()
        or 200

    local contents = response.readAll()
    response.close()

    if code < 200 or code >= 300 then
        return false,
            "GitHub HTTP " .. tostring(code)
    end

    if not contents or contents == "" then
        return false,
            "GitHub returned an empty file"
    end

    if string.sub(contents, 1, 1) == "{"
        and string.find(contents, '"message"') then
        return false,
            "GitHub returned JSON instead of raw Lua"
    end

    local tempFile = program .. ".new"

    if fs.exists(tempFile) then
        fs.delete(tempFile)
    end

    local file = fs.open(tempFile, "w")

    if not file then
        return false,
            "Could not create " .. tempFile
    end

    file.write(contents)
    file.close()

    local loader, syntaxError = loadfile(tempFile)

    if not loader then
        fs.delete(tempFile)
        return false,
            "Downloaded Lua error: " .. tostring(syntaxError)
    end

    if fs.exists(program) then
        fs.delete(program)
    end

    fs.move(tempFile, program)

    return true
end

clearScreen()

local roleNumber = loadRole()

if not roleNumber then
    roleNumber = chooseRole()
end

local role = roles[roleNumber]

clearScreen()

print(role.name)
print(string.rep("=", #role.name))
print("")
print("Computer ID: " .. os.getComputerID())
print("Program: " .. role.file)
print("")

local success, downloadError =
    downloadProgram(role.file)

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
        print("No local copy is available.")
        term.setTextColor(colors.white)
        return
    end
end

print("")
print("Starting " .. role.file .. "...")
sleep(0.5)

shell.run(role.file)
