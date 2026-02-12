local command = {}

local tables = require("tables")

-- Convert brightness from 1-10 to 0-255 scale
local function convertBrightness(brightness)
    return math.floor((brightness) * 25.5)
end

local initDir = "/run/muos/storage/init"
local initScript = initDir .. "/rgb_screen_react.sh"

-- Get the path to the bundled rgb_screen_react.sh in the app root
local function getSourceScript()
    local sourceDir = love.filesystem.getSource()
    -- sourceDir points to rgbscreenreact/, go up one level to app root
    local appRoot = sourceDir:match("(.+)/[^/]+$")
    return appRoot .. "/rgb_screen_react.sh"
end

-- Install the init script from the app bundle
local function installInitScript()
    local source = getSourceScript()
    os.execute("mkdir -p " .. initDir)
    os.execute("cp " .. string.format("%q", source) .. " " .. string.format("%q", initScript))
    os.execute("chmod +x " .. string.format("%q", initScript))
    print("Installed init script: " .. initScript)
end

-- Remove the init script
local function removeInitScript()
    os.execute("rm -f " .. string.format("%q", initScript))
    print("Removed init script: " .. initScript)
end

-- Ensure the screen react process is running (launch only if not already active)
local function ensureScreenReactRunning()
    local handle = io.popen("pgrep -f rgb_screen_react.sh")
    local result = handle:read("*a")
    handle:close()
    if result == "" then
        os.execute(initScript .. " &")
        print("Launched screen react process: " .. initScript)
    else
        print("Screen react process already running.")
    end
end

-- Construct and run the command based on settings
function command.run(settings)
    local mode = settings.mode
    local brightness = convertBrightness(settings.brightness)
    local commandArgs = ""

    if mode == 9 then
        -- Screen React: install init script, ensure process is running
        commandArgs = string.format("9 %d", brightness)
        installInitScript()
        ensureScreenReactRunning()
    else
        -- Any other mode: turn LEDs off and remove init script
        commandArgs = string.format("1 0 0 0 0 0 0 0")
        removeInitScript()
    end

    -- Define the path to the folder and the command file
    local folderPath = "/run/muos/storage/theme/active/rgb"
    local commandFile = folderPath .. "/rgbconf.sh"

    -- Ensure the directory exists
    os.execute("mkdir -p " .. folderPath)

    -- Open the file for writing
    local file = io.open(commandFile, "w")
    if file then
        -- Add the shebang at the beginning
        file:write("#!/bin/sh\n")

        -- Add the dynamic device-specific path with the correct arguments
        file:write(string.format("/opt/muos/script/device/rgb.sh %s\n", commandArgs))

        file:close()
        print("Command saved to: " .. commandFile)
    else
        print("Error: Could not save the file.")
    end

    -- Print the final command to the console for debugging
    print("Running command: /opt/muos/script/device/rgb.sh " .. commandArgs)

    -- Execute the command in the system shell
    os.execute("/run/muos/storage/theme/active/rgb/rgbconf.sh")
end

return command
