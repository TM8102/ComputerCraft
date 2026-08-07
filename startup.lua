-- =========================================================
-- UNIVERSAL COMPUTERCRAFT STARTUP
--
-- First run:
--   asks which role this computer uses
--   saves that role locally
--
-- Every reboot:
--   deletes old program copy
--   downloads latest copy from GitHub
--   runs it
--
-- =========================================================

local repoBase =
    "https://raw.githubusercontent.com/TM8102/ComputerCraft/main/"

local roleFile =
    ".computer_role"

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
    }
}

-- =========================================================
-- HELPERS
-- =========================================================

local function clearScreen()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
end

local function saveRole(roleNumber)
    local file =
        fs.open(
            roleFile,
            "w"
        )

    if not file then
        error(
            "Could not save role"
        )
    end

    file.write(
        roleNumber
    )

    file.close()
end

local function loadRole()
    if not fs.exists(
        roleFile
    ) then
        return nil
    end

    local file =
        fs.open(
            roleFile,
            "r"
        )

    if not file then
        return nil
    end

    local role =
        file.readAll()

    file.close()

    if roles[role] then
        return role
    end

    return nil
end

-- =========================================================
-- ROLE SELECTION
-- =========================================================

local function chooseRole()
    while true do
        clearScreen()

        print(
            "COMPUTER ROLE SETUP"
        )

        print(
            "==================="
        )

        print("")

        print(
            "1 - Main Screen"
        )

        print(
            "2 - Storage Brain"
        )

        print(
            "3 - Storage + Machine Node"
        )

        print(
            "4 - Resource Generator"
        )

        print(
            "5 - Time Wand Controller"
        )

        print("")

        write(
            "Choose role: "
        )

        local choice =
            read()

        if roles[choice] then
            saveRole(
                choice
            )

            return choice
        end

        print("")
        print(
            "Invalid choice."
        )

        sleep(1)
    end
end

-- =========================================================
-- DOWNLOAD PROGRAM
-- =========================================================

local function downloadProgram(
    program
)
    local url =
        repoBase
        .. program

    print(
        "Downloading:"
    )

    print(
        program
    )

    print("")

    -- Keep old copy until download succeeds.
    local response,
        err =
        http.get(
            url,
            {
                ["Cache-Control"] =
                    "no-cache"
            }
        )

    if not response then
        return false,
            tostring(err)
    end

    local contents =
        response.readAll()

    response.close()

    if not contents
        or contents == "" then

        return false,
            "Empty response"
    end

    local tempFile =
        program
        .. ".new"

    if fs.exists(
        tempFile
    ) then
        fs.delete(
            tempFile
        )
    end

    local file =
        fs.open(
            tempFile,
            "w"
        )

    if not file then
        return false,
            "Could not create temp file"
    end

    file.write(
        contents
    )

    file.close()

    -- Only delete old program after new copy
    -- downloaded successfully.
    if fs.exists(
        program
    ) then
        fs.delete(
            program
        )
    end

    fs.move(
        tempFile,
        program
    )

    return true
end

-- =========================================================
-- MAIN
-- =========================================================

clearScreen()

local roleNumber =
    loadRole()

if not roleNumber then
    roleNumber =
        chooseRole()
end

local role =
    roles[
        roleNumber
    ]

clearScreen()

print(
    role.name
)

print(
    string.rep(
        "=",
        #role.name
    )
)

print("")

print(
    "Computer ID: "
    .. os.getComputerID()
)

print(
    "Program: "
    .. role.file
)

print("")

local success,
    downloadError =
    downloadProgram(
        role.file
    )

if success then

    print(
        "Updated successfully."
    )

else

    print(
        "UPDATE FAILED:"
    )

    print(
        tostring(
            downloadError
        )
    )

    print("")

    if fs.exists(
        role.file
    ) then

        print(
            "Using existing local copy."
        )

    else

        print(
            "No local copy available."
        )

        return
    end
end

print("")
print(
    "Starting "
    .. role.file
    .. "..."
)

sleep(
    0.5
)

shell.run(
    role.file
)