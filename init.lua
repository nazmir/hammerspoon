local lastState = nil

local function isInternalScreen(screen)
    local name = screen:name():lower()
    return name:find("built") or name:find("lcd") or name:find("retina")
end

local function has4KDisplay()
    for _, screen in ipairs(hs.screen.allScreens()) do
        if not isInternalScreen(screen) then
            local mode = screen:currentMode()
            local width = mode.w
            local height = mode.h
            if width >= 3840 and height >= 2160 then
                return true
            end
        end
    end
    return false
end

local function updateDockVisibility()
    local shouldHide = not has4KDisplay()
    if lastState ~= shouldHide then
        lastState = shouldHide
        local applescript = string.format([[
            tell application "System Events"
                tell dock preferences
                    set autohide to %s
                end tell
            end tell
        ]], tostring(shouldHide))
        hs.osascript.applescript(applescript)
    end
end

-- Watch for display changes and update dock visibility
local function screenWatcher()
    updateDockVisibility()
end

-- Create a screen watcher that triggers when displays change
local screenWatcher = hs.screen.watcher.new(screenWatcher)

-- Start watching for screen changes
screenWatcher:start()

-- Initial check when Hammerspoon starts (delayed to ensure displays are ready)
hs.timer.doAfter(4, updateDockVisibility)
