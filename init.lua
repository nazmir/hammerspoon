-- Configuration
local DOCK_HIDE_DELAY = 2 -- seconds to wait before toggling dock after screen changes
local lastState = nil

-- Check if a screen is internal (simplified)
local function isInternalScreen(screen)
    local name = screen:name():lower()
    return name:find("built") or name:find("lcd") or name:find("retina") or 
           name:find("color l[cd]") or name:find("built%-in")
end

-- Check for 4K or higher resolution displays (simplified)
local function has4KDisplay()
    for _, screen in ipairs(hs.screen.allScreens()) do
        if not isInternalScreen(screen) then
            local mode = screen:currentMode()
            if mode then
                -- Calculate physical resolution (accounting for scaling)
                local scale = mode.scale or 1
                local physicalW, physicalH = mode.w * scale, mode.h * scale
                
                -- Check if either dimension is 4K or higher
                if (physicalW >= 3840 and physicalH >= 2160) or 
                   (physicalH >= 3840 and physicalW >= 2160) then
                    return true
                end
            end
        end
    end
    return false
end

-- Update dock visibility based on display configuration
local function updateDockVisibility()
    local shouldHide = not has4KDisplay()
    
    if lastState == nil or lastState ~= shouldHide then
        lastState = shouldHide
        
        -- Toggle dock visibility
        pcall(function()
            hs.dockicon.hide(shouldHide)
            hs.osascript.applescript(string.format([[
                tell application "System Events"
                    tell dock preferences to set autohide to %s
                end tell
            ]], tostring(shouldHide)))
        end)
        
        -- Show notification
        hs.notify.new({
            title = "Dock Auto-Hide",
            subTitle = string.format("Dock will now %s", shouldHide and "hide" or "show"),
            informativeText = string.format("4K+ display %s", shouldHide and "not detected" or "detected")
        }):send()
    end
end

-- Debounced update function
local debouncedUpdate = hs.timer.delayed.new(DOCK_HIDE_DELAY, updateDockVisibility)

-- Watch for display and USB changes
local screenWatcher = hs.screen.watcher.new(debouncedUpdate.start)
local usbWatcher = hs.usb.watcher.new(debouncedUpdate.start)

-- Start watchers
screenWatcher:start()
usbWatcher:start()

-- Initial check
hs.timer.doAfter(4, updateDockVisibility)

-- Manual refresh hotkey (⌘⌃⌥D)
hs.hotkey.bind({"cmd", "ctrl", "alt"}, "D", updateDockVisibility)

-- Initial notification
hs.notify.new({title = "Dock Auto-Hide", informativeText = "Script loaded and running"}):send()
