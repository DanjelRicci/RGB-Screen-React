local draw = {}
local push = require "push"
local tables = require("tables")

-- Local variables for assets and fade effect
local backgroundImage, spriteSheet
local icons = {}
local fadeAlpha = 0  -- Fade effect, fully transparent by default

-- Screen and layout variables
local screenWidth, screenHeight
local fixedVerticalSpacing = 24
local leftColumnOffsetX, rightColumnOffsetX = 110, 80
local menuStartHeight, stripYOffset = 64, 16

-- Sprite sheet details
local spriteWidth, spriteHeight = 80, 16
local numFrames = 10  -- Number of frames in the sprite sheet

-- Gradient background variables
local gradientMesh
local lerpDuration = 2.0  -- Seconds per color transition
local lerpTimer = 0

-- Bright color palette for the gradient
local palette = {
    {255, 60, 80},
    {255, 130, 0},
    {255, 220, 30},
    {80, 255, 80},
    {0, 228, 180},
    {60, 180, 255},
    {140, 80, 255},
    {255, 100, 200},
}

-- Current and target colors for left and right sides (0-1 range)
local leftCurrent = {0, 0, 0}
local leftTarget = {0, 0, 0}
local rightCurrent = {0, 0, 0}
local rightTarget = {0, 0, 0}

-- Track which palette index each side is targeting so we avoid picking the same one twice in a row
local leftTargetIndex = 0
local rightTargetIndex = 0

-- Pick a random palette color (returns 0-1 range), avoiding the given color index
local function randomColor(avoidIndex)
    local idx = avoidIndex
    while idx == avoidIndex do
        idx = math.random(1, #palette)
    end
    local c = palette[idx]
    return {c[1] / 255, c[2] / 255, c[3] / 255}, idx
end

-- Lerp between two color tables
local function lerpColor(a, b, t)
    return {
        a[1] + (b[1] - a[1]) * t,
        a[2] + (b[2] - a[2]) * t,
        a[3] + (b[3] - a[3]) * t,
    }
end

-- Initialize gradient colors
local function initGradientColors()
    local lc, li = randomColor(0)
    leftCurrent = lc
    leftTargetIndex = li

    local rc, ri = randomColor(li)
    rightCurrent = rc
    rightTargetIndex = ri

    local lt, lti = randomColor(leftTargetIndex)
    leftTarget = lt
    leftTargetIndex = lti

    local rt, rti = randomColor(rightTargetIndex)
    -- Avoid matching the new left target
    while rti == lti do
        rt, rti = randomColor(rightTargetIndex)
    end
    rightTarget = rt
    rightTargetIndex = rti
end

-- Helper function to check if a menu option should be greyed out
local function shouldGreyOutOption(option)
    if settings.mode == 0 then
        return option ~= "Enabled"
    end
    return false
end

-- Load assets function
function draw.load()
    windowWidth, windowHeight = love.graphics.getDimensions()

    -- Load background and sprite sheet
    backgroundImage = love.graphics.newImage("assets/sprites/background.png")
    spriteSheet = love.graphics.newImage("assets/sprites/slider.png")

    -- Load icons based on menu option names
    for _, option in ipairs(menu) do
        local iconPath = string.format("assets/sprites/%s.png", option:lower())
        icons[option] = love.graphics.newImage(iconPath)
    end

    -- Initialize the gradient mesh using actual window dimensions to cover the full screen
    -- 8 vertices in strip mode: solid left (0-10%), gradient (10-90%), solid right (90-100%)
    local sw, sh = love.graphics.getDimensions()
    local x10 = sw * 0.10
    local x90 = sw * 0.90
    gradientMesh = love.graphics.newMesh({
        {0,   0,    0, 0,   0, 0, 0, 1},  -- top-left edge
        {0,   sh,   0, 1,   0, 0, 0, 1},  -- bottom-left edge
        {x10, 0,    0, 0,   0, 0, 0, 1},  -- top-left gradient start
        {x10, sh,   0, 1,   0, 0, 0, 1},  -- bottom-left gradient start
        {x90, 0,    1, 0,   0, 0, 0, 1},  -- top-right gradient end
        {x90, sh,   1, 1,   0, 0, 0, 1},  -- bottom-right gradient end
        {sw,  0,    1, 0,   0, 0, 0, 1},  -- top-right edge
        {sw,  sh,   1, 1,   0, 0, 0, 1},  -- bottom-right edge
    }, "strip", "dynamic")

    -- Seed RNG and pick initial colors
    math.randomseed(os.time())
    initGradientColors()
    lerpTimer = 0
end

-- Update gradient animation
function draw.update(dt)
    lerpTimer = lerpTimer + dt

    if lerpTimer >= lerpDuration then
        -- Transition complete: current becomes the target, pick new targets
        leftCurrent = {leftTarget[1], leftTarget[2], leftTarget[3]}
        rightCurrent = {rightTarget[1], rightTarget[2], rightTarget[3]}

        local lt, lti = randomColor(leftTargetIndex)
        leftTarget = lt
        leftTargetIndex = lti

        local rt, rti = randomColor(rightTargetIndex)
        -- Avoid matching the new left target
        while rti == lti do
            rt, rti = randomColor(rightTargetIndex)
        end
        rightTarget = rt
        rightTargetIndex = rti

        lerpTimer = lerpTimer - lerpDuration
    end

    -- Calculate the interpolated colors
    local t = lerpTimer / lerpDuration
    -- Smoothstep for a nicer easing curve
    t = t * t * (3 - 2 * t)

    local leftColor = lerpColor(leftCurrent, leftTarget, t)
    local rightColor = lerpColor(rightCurrent, rightTarget, t)

    -- Darken the gradient so the UI text remains readable
    local dim = 0.9
    local lc = {leftColor[1] * dim, leftColor[2] * dim, leftColor[3] * dim, 1}
    local rc = {rightColor[1] * dim, rightColor[2] * dim, rightColor[3] * dim, 1}

    -- Update mesh vertex colors (strip: left edge, gradient start, gradient end, right edge)
    gradientMesh:setVertexAttribute(1, 3, lc[1], lc[2], lc[3], lc[4])  -- top-left edge
    gradientMesh:setVertexAttribute(2, 3, lc[1], lc[2], lc[3], lc[4])  -- bottom-left edge
    gradientMesh:setVertexAttribute(3, 3, lc[1], lc[2], lc[3], lc[4])  -- top-left gradient start
    gradientMesh:setVertexAttribute(4, 3, lc[1], lc[2], lc[3], lc[4])  -- bottom-left gradient start
    gradientMesh:setVertexAttribute(5, 3, rc[1], rc[2], rc[3], rc[4])  -- top-right gradient end
    gradientMesh:setVertexAttribute(6, 3, rc[1], rc[2], rc[3], rc[4])  -- bottom-right gradient end
    gradientMesh:setVertexAttribute(7, 3, rc[1], rc[2], rc[3], rc[4])  -- top-right edge
    gradientMesh:setVertexAttribute(8, 3, rc[1], rc[2], rc[3], rc[4])  -- bottom-right edge
end

-- Render the gradient background (called outside push transform to cover full screen)
function draw.renderBackground()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(gradientMesh)
end

-- Render the menu and other elements
function draw.render()
    local w, h = push:getWidth(), push:getHeight()

    -- Draw the UI overlay on top of the gradient
    local bgWidth, bgHeight = backgroundImage:getDimensions()
    local scaleX = w / bgWidth
    local scaleY = h / bgHeight
    local scale = math.max(scaleX, scaleY)
    local offsetX, offsetY = (w - bgWidth * scale) / 2, (h - bgHeight * scale) / 2

    love.graphics.setDefaultFilter("nearest", "nearest")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(backgroundImage, offsetX, offsetY, 0, scale, scale)

    local centerX = w / 2
    local dynamicLeftOffsetX = leftColumnOffsetX * scale
    local dynamicRightOffsetX = rightColumnOffsetX * scale
    local menuVerticalSpacing = fixedVerticalSpacing * scale
    local menuStartY = menuStartHeight * scale
    local iconSize = 16 * scale

    for i, option in ipairs(menu) do
        local yPosition = menuStartY + (i - 1) * menuVerticalSpacing
        local isGreyedOut = shouldGreyOutOption(option)

        love.graphics.setFont(isGreyedOut and fonts.greyedOut or fonts.regular)
        love.graphics.setColor(isGreyedOut and {0.8, 0.8, 0.8} or {1, 1, 1})

        if icons[option] then
            love.graphics.draw(icons[option], centerX - dynamicLeftOffsetX - iconSize - 16, yPosition, 0, scale, scale)
        end

        love.graphics.print(option, centerX - dynamicLeftOffsetX, yPosition)

        if i == currentSelection then
            local optionTextWidth = love.graphics.getFont():getWidth(option)
            local stripX = centerX - dynamicLeftOffsetX - 10
            local stripY = yPosition + stripYOffset + 16
            drawSelectionStrip(stripX, stripY, optionTextWidth + 20, 3 * scale)
        end
    end

    for i, option in ipairs(menu) do
        local yPosition = menuStartY + (i - 1) * menuVerticalSpacing
        local isGreyedOut = shouldGreyOutOption(option)

        love.graphics.setFont(isGreyedOut and fonts.greyedOut or fonts.regular)
        love.graphics.setColor(isGreyedOut and {0.8, 0.8, 0.8} or {1, 1, 1})

        if option == "Brightness" then
            local valueIndex = math.min(math.max(settings.brightness, 1), numFrames)
            local frameX = (valueIndex - 1) * spriteWidth
            local quad = love.graphics.newQuad(frameX, 0, spriteWidth, spriteHeight, spriteSheet:getDimensions())
            love.graphics.draw(spriteSheet, quad, centerX + dynamicRightOffsetX - spriteWidth * scale / 2, yPosition, 0, scale, scale)
        else
            local valueText = getOptionValueText(option)
            love.graphics.print(valueText, centerX + dynamicRightOffsetX - love.graphics.getFont():getWidth(valueText) / 2, yPosition)
        end
    end

    if fadeAlpha > 0 then
        love.graphics.setColor(0, 0, 0, fadeAlpha)
        love.graphics.rectangle("fill", 0, 0, w, h)
        love.graphics.setColor(1, 1, 1)
    end
end

-- Helper function to draw the selection indicator strip
function drawSelectionStrip(x, y, width, height)
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("fill", x + 1, y, width - 2, height / 3)
    love.graphics.rectangle("fill", x, y + 1, width, height / 3)
    love.graphics.rectangle("fill", x + 1, y + 2, width - 2, height / 3)
end

-- Get the text value for a menu option
function getOptionValueText(option)
    if option == "Enabled" then
        return settings.mode == 0 and "Off" or "On"
    else
        return ""
    end
end

-- Set fade alpha value
function draw.setFadeAlpha(alpha)
    fadeAlpha = alpha
end

-- Set the menu starting height
function draw.setMenuStartHeight(height)
    menuStartHeight = height
end

-- Set the vertical offset for the selection strip
function draw.setStripYOffset(offset)
    stripYOffset = offset
end

return draw
