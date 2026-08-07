local apiURL =
    "https://api.github.com/repos/TM8102/ComputerCraft/contents/targets.lua?ref=main"

print("Downloading targets.lua from GitHub API...")

local response, err =
    http.get(
        apiURL,
        {
            ["User-Agent"] = "CC-Tweaked"
        }
    )

if not response then
    print("FAILED:")
    print(tostring(err))
    return
end

local body =
    response.readAll()

response.close()

local data =
    textutils.unserializeJSON(body)

if not data then
    print("Could not parse GitHub response")
    return
end

if not data.content then
    print("GitHub returned no file content")
    print(body)
    return
end

local encoded =
    string.gsub(
        data.content,
        "\n",
        ""
    )

local decoded =
    textutils.decodeBase64(
        encoded
    )

if not decoded then
    print("Base64 decode failed")
    return
end

local file =
    fs.open(
        "targets_new.lua",
        "w"
    )

file.write(decoded)
file.close()

print("Downloaded!")
print("GitHub SHA:")
print(tostring(data.sha))
print("")
print("Saved as targets_new.lua")