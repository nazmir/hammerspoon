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

-- Toggle Stage Manager
local function setStageManager(enabled)
    pcall(function()
        -- First try using the direct defaults write command
        local result = os.execute(string.format('defaults write com.apple.WindowManager GloballyEnabled -bool %s', enabled and 'true' or 'false'))
        
        -- If the direct method fails, fall back to UI automation
        if result ~= 0 then
            hs.osascript.applescript([[
                tell application "System Events"
                    -- Open Desktop & Dock settings
                    tell application "System Settings"
                        activate
                        reveal anchor "StageManager" in pane id "com.apple.Desktop-Settings.extension"
                        delay 1  -- Give it more time to load
                    end tell
                    
                    -- Wait for the window to be available
                    set maxWait to 10  -- seconds
                    set waitTime to 0
                    repeat until (exists window "Desktop & Dock" of process "System Settings") or (waitTime ≥ maxWait)
                        delay 0.5
                        set waitTime to waitTime + 0.5
                    end repeat
                    
                    -- Toggle the Stage Manager checkbox
                    tell process "System Settings"
                        try
                            set stageManagerCheckbox to checkbox 1 of group 1 of group 1 of group 2 of splitter group 1 of group 1 of window "Desktop & Dock"
                            set currentState to value of stageManagerCheckbox as boolean
                            if currentValue is not (]] .. (enabled and "1" or "0") .. [[) then
                                click stageManagerCheckbox
                                delay 0.5  -- Give it time to process the click
                            end if
                        on error errMsg
                            log "Error toggling Stage Manager: " & errMsg
                        end try
                    end tell
                    
                    -- Close System Settings
                    if running of application "System Settings" then
                        tell application "System Settings" to quit
                    end if
                end tell
            ]])
        end
    end)
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
            
            -- Toggle Stage Manager based on dock visibility
            setStageManager(not shouldHide)
        end)
        
        -- Show notification
        hs.notify.new({
            title = "Dock Auto-Hide",
            subTitle = string.format("Dock will now %s", shouldHide and "hide" or "show"),
            informativeText = string.format("4K+ display %s. Stage Manager %s.", 
                shouldHide and "not detected" or "detected",
                shouldHide and "disabled" or "enabled")
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
