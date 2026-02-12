local input = {}

local inputCooldown = 0.2
local timeSinceLastInput = 0
local joystick

-- Require the command and soundmanager modules
local command = require("command")
local soundmanager = require("soundmanager")
local tables = require("tables")

function input.load()
    -- Initialize joystick
    local joysticks = love.joystick.getJoysticks()
    if #joysticks > 0 then
        joystick = joysticks[1]
    end

    -- Load sound effects
    soundmanager.load()
end

function input.update(dt)
    -- Update the timer
    timeSinceLastInput = timeSinceLastInput + dt

    if joystick then
        handleJoystickInput(dt)
    end
end

function handleJoystickInput(dt)
    if timeSinceLastInput >= inputCooldown then
        local changed = false
        local settingChanged = false
        local commandTriggered = false

        -- Determine which menu items are selectable based on settings.mode
        local selectableIndices = {}
        if settings.mode == 0 then  -- Off
            selectableIndices = {1}  -- Enabled only
        else
            selectableIndices = {1, 2}  -- Enabled and Brightness
        end

        -- Ensure the current selection is valid based on the selectable indices
        if not tableContains(selectableIndices, currentSelection) then
            currentSelection = selectableIndices[1]
        end

        -- Check for quit command (LB + RB)
        if joystick:isGamepadDown("leftshoulder") and joystick:isGamepadDown("rightshoulder") then
            love.event.quit()  -- Quit 
            return
        end

        -- Navigate through the menu using D-pad up and down
        if joystick:isGamepadDown("dpup") then
            currentSelection = currentSelection - 1
            -- Wrap around if needed, considering selectable items
            while not tableContains(selectableIndices, currentSelection) do
                currentSelection = currentSelection - 1
                if currentSelection < 1 then 
                    currentSelection = #menu 
                end
            end
            changed = true
            soundmanager.playUp()  -- Play the "up" sound
        elseif joystick:isGamepadDown("dpdown") then
            currentSelection = currentSelection + 1
            -- Wrap around if needed, considering selectable items
            while not tableContains(selectableIndices, currentSelection) do
                currentSelection = currentSelection + 1
                if currentSelection > #menu then 
                    currentSelection = 1 
                end
            end
            changed = true
            soundmanager.playDown()  -- Play the "down" sound
        end

        -- Adjust settings based on D-pad left and right
        if joystick:isGamepadDown("dpleft") or joystick:isGamepadDown("dpright") then
            -- Change settings based on current selection
            if menu[currentSelection] == "Enabled" then
                -- Toggle between On (mode 9) and Off (mode 0)
                if settings.mode == 0 then
                    settings.mode = 9
                else
                    settings.mode = 0
                end
                settingChanged = true
                soundmanager.playLeft()  -- Play the "left" sound
            elseif menu[currentSelection] == "Brightness" then
                local adjustValue = joystick:isGamepadDown("dpright") and 1 or -1
                settings.brightness = settings.brightness + adjustValue
                if settings.brightness < 1 then settings.brightness = 1 end
                if settings.brightness > 10 then settings.brightness = 10 end
                settingChanged = true
                soundmanager.playRight()  -- Play the "right" sound
            end

            -- Save settings if something changed
            if settingChanged then
                saveSettings()
                commandTriggered = true
            end
        end

        -- Run command and reset cooldown if a command was triggered
        if commandTriggered or changed then
            if commandTriggered then
                command.run(settings)
            end
            timeSinceLastInput = 0  -- Reset the cooldown timer
        end
    end
end

-- Utility function to check if a value is in a table
function tableContains(tbl, value)
    for _, v in ipairs(tbl) do
        if v == value then
            return true
        end
    end
    return false
end


return input
