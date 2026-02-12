local command = {}

local tables = require("tables")

-- Convert brightness from 1-10 to 0-255 scale
local function convertBrightness(brightness)
    return math.floor((brightness) * 25.5)
end

local screenReactScript = "/run/muos/storage/init/rgb_screen_react.sh"

-- Ensure the screen react process is running (launch only if not already active)
local function ensureScreenReactRunning()
    local handle = io.popen("pgrep -f rgb_screen_react.sh")
    local result = handle:read("*a")
    handle:close()
    if result == "" then
        os.execute(screenReactScript .. " &")
        print("Launched screen react process: " .. screenReactScript)
    else
        print("Screen react process already running.")
    end
end

-- Construct and run the command based on settings
function command.run(settings)
    local mode = settings.mode
    local brightness = convertBrightness(settings.brightness)
    local commandArgs = ""

    if mode == 0 then
        -- Off: turn LEDs off
        commandArgs = string.format("1 0 0 0 0 0 0 0")
    elseif mode == 9 then
        -- Screen React: the screen reading script handles LED colors,
        -- but we still need to write brightness to the config
        commandArgs = string.format("9 %d", brightness)
        ensureScreenReactRunning()
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
