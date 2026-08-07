-- =========================================================
-- REUSABLE FLOPPY INSTALLER
-- Put this on a floppy and run it on each computer.
-- It never modifies the floppy itself.
--
-- If the computer already has a valid startup + role config,
-- it leaves the computer alone.
-- Otherwise it downloads the universal startup.lua from
-- GitHub, compile-checks it, installs it to the computer,
-- and reboots into setup.
-- =========================================================

local startupURL =
    "https://api.github.com/repos/TM8102/ComputerCraft/contents/startup.lua?ref=main"

local startupFile = "startup.lua"
local roleFile = ".computer_role"
local validRoles = {
    ["1"] = true,
    ["2"] = true,
    ["3"] = true,
    ["4"] = true,
    ["5"] = true,
    ["6"] = true,
    ["7"] = true,
    ["8"] = true
}

local function clear()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1,1)
end

local function readRole()
    if not fs.exists(roleFile) then return nil end
    local f = fs.open(roleFile,"r")
    if not f then return nil end
    local role = f.readAll()
    f.close()
    if validRoles[role] then return role end
    return nil
end

local function startupIsValid()
    if not fs.exists(startupFile) then return false end
    local loader = loadfile(startupFile)
    return loader ~= nil
end

local function downloadStartup()
    local url = startupURL .. "&cb=" .. tostring(os.epoch("utc"))
    local response, err = http.get(url,{
        ["User-Agent"] = "CC-Tweaked",
        ["Accept"] = "application/vnd.github.raw+json",
        ["Cache-Control"] = "no-cache, no-store",
        ["Pragma"] = "no-cache"
    })

    if not response then return false,"GitHub API failed: "..tostring(err) end
    local code = response.getResponseCode and response.getResponseCode() or 200
    local contents = response.readAll()
    response.close()
    if code < 200 or code >= 300 then return false,"GitHub HTTP "..tostring(code) end
    if not contents or contents == "" then return false,"Empty startup.lua" end

    local temp = startupFile .. ".new"
    if fs.exists(temp) then fs.delete(temp) end
    local f = fs.open(temp,"w")
    if not f then return false,"Could not write startup.lua.new" end
    f.write(contents)
    f.close()

    local loader, syntaxError = loadfile(temp)
    if not loader then
        fs.delete(temp)
        return false,"Downloaded startup syntax error: "..tostring(syntaxError)
    end

    if fs.exists(startupFile) then fs.delete(startupFile) end
    fs.move(temp,startupFile)
    return true
end

clear()
print("COMPUTERCRAFT INSTALLER")
print("======================")
print("Computer ID: "..os.getComputerID())
print("")

local role = readRole()
local validStartup = startupIsValid()

if role and validStartup then
    term.setTextColor(colors.lime)
    print("Already configured.")
    term.setTextColor(colors.white)
    print("Role: "..role)
    print("Startup: VALID")
    print("")
    print("Floppy can be moved to the next computer.")
    return
end

if not role then
    print("Role config: MISSING / INVALID")
else
    print("Role config: "..role)
end
print("Startup: "..(validStartup and "VALID" or "MISSING / INVALID"))
print("")
print("Installing latest universal startup...")

local ok, err = downloadStartup()
if not ok then
    term.setTextColor(colors.red)
    print("INSTALL FAILED")
    term.setTextColor(colors.white)
    print(tostring(err))
    return
end

term.setTextColor(colors.lime)
print("Startup installed successfully.")
term.setTextColor(colors.white)

-- If the role file exists but is invalid, remove it so the
-- universal startup asks for a clean role selection.
if not role and fs.exists(roleFile) then
    fs.delete(roleFile)
end

print("Rebooting into setup...")
sleep(1)
os.reboot()
