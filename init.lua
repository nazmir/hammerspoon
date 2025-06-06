-- Configuration
local LOG_PREFIX = "[Dock Auto-Hide] "
local DOCK_HIDE_DELAY = 2 -- seconds to wait before toggling dock after screen changes

-- State
local lastState = nil

-- Logging function
local function log(message)
    print(LOG_PREFIX .. message)
end

-- Check if a screen is internal
local function isInternalScreen(screen)
    local name = screen:name():lower()
    local isMainScreen = screen == hs.screen.primaryScreen()
    local isInternal = name:find("built") or 
                      name:find("lcd") or 
                      name:find("retina") or 
                      name:find("color l[cd]") or
                      name:find("built%-in") or
                      name:find("display")
    log(string.format("Screen: %s (Internal: %s, Main: %s)", screen:name(), tostring(isInternal), tostring(isMainScreen)))
    return isInternal
end

-- Get the native resolution of a screen with debug logging
local function getNativeResolution(screen)
    log(string.format("Checking modes for display: %s", screen:name()))
    
    -- Get all available modes
    local modes = screen:availableModes()
    
    -- Log all available modes for debugging
    log(string.format("  Found %d available modes:", #modes))
    for i, mode in ipairs(modes) do
        log(string.format("    Mode %d: %dx%d @ %.0fHz", i, mode.w, mode.h, mode.scale or 1))
    end
    
    if #modes > 0 then
        -- Sort by resolution (highest first)
        table.sort(modes, function(a, b) 
            return (a.w * a.h) > (b.w * b.h)
        end)
        
        -- Get the highest resolution mode (should be native)
        local nativeW, nativeH = modes[1].w, modes[1].h
        log(string.format("  Selected native resolution: %dx%d", nativeW, nativeH))
        return nativeW, nativeH
    end
    
    -- Fallback to current mode if we can't get available modes
    local mode = screen:currentMode()
    log(string.format("  Using current mode as fallback: %dx%d", 
        mode and mode.w or 0, 
        mode and mode.h or 0))
    return mode and mode.w or 0, mode and mode.h or 0
end

-- Check for 4K or higher resolution displays
local function has4KDisplay()
    local screens = hs.screen.allScreens()
    log("Checking displays...")
    
    -- Safely get system information
    local systemInfo = ""
    local hostName = ""
    local osVersion = ""
    
    -- Get host name
    local hostSuccess, hostResult = pcall(function() return hs.host.localizedName() end)
    if hostSuccess and hostResult then
        hostName = tostring(hostResult)
    end
    
    -- Get OS version
    local osSuccess, osResult = pcall(function() 
        local ver = hs.host.operatingSystemVersion()
        return ver and ver.versionString or "unknown version"
    end)
    if osSuccess and osResult then
        osVersion = tostring(osResult)
    end
    
    -- Build the info string
    systemInfo = "System: " .. (hostName ~= "" and hostName or "[unknown host]")
    if osVersion ~= "" then
        systemInfo = systemInfo .. " (" .. osVersion .. ")"
    end
    
    log(systemInfo)
    
    for _, screen in ipairs(screens) do
        local screenID = screen:id()
        local screenName = screen:name()
        local isInternal = isInternalScreen(screen)
        
        log(string.format("\n=== Display: %s (ID: %s) ===", screenName, screenID))
        log(string.format("  Frame: %s", hs.inspect(screen:frame())))
        log(string.format("  Full frame: %s", hs.inspect(screen:fullFrame())))
        
        -- Get current mode and calculate physical resolution
        local currentMode = screen:currentMode()
        local physicalW, physicalH = 0, 0
        
        if currentMode then
            local scale = currentMode.scale or 1
            physicalW = math.floor(currentMode.w * scale + 0.5)  -- Round to nearest integer
            physicalH = math.floor(currentMode.h * scale + 0.5)  -- Round to nearest integer
            
            log(string.format("  Current mode: %dx%d @ %.0fx (physical: %dx%d)", 
                currentMode.w, currentMode.h, scale, physicalW, physicalH))
        else
            log("  Could not get current display mode")
        end
        
        -- Get native resolution (try to get the highest available mode)
        local nativeW, nativeH = getNativeResolution(screen)
        
        -- If we couldn't get native resolution, use the physical resolution from current mode
        if (nativeW == 0 or nativeH == 0) and currentMode then
            nativeW, nativeH = physicalW, physicalH
        end
        
        -- Check for 4K in either physical or native resolution
        local is4K = false
        local reason = ""
        
        -- Function to check if resolution is 4K
        local function isResolution4K(w, h)
            return (w >= 3840 and h >= 2160) or (w >= 2160 and h >= 3840)
        end
        
        -- Check native resolution first
        if isResolution4K(nativeW, nativeH) then
            is4K = true
            reason = string.format("native resolution %dx%d", nativeW, nativeH)
        -- Then check physical resolution (current resolution * scale)
        elseif currentMode and isResolution4K(physicalW, physicalH) then
            is4K = true
            reason = string.format("physical resolution %dx%d (scaled from %dx%d @ %.0fx)",
                physicalW, physicalH, currentMode.w, currentMode.h, currentMode.scale or 1)
        -- Then check current resolution (unscaled)
        elseif currentMode and isResolution4K(currentMode.w, currentMode.h) then
            is4K = true
            reason = string.format("current resolution %dx%d", currentMode.w, currentMode.h)
        end
        
        log(string.format("  %s: %s - %s", 
            is4K and "✓ 4K+" or "  Not 4K",
            screenName,
            is4K and ("(" .. reason .. ")") or "(resolution too low)"))
            
        if not isInternal and is4K then
            log("  ✓ Found 4K+ external display: " .. screenName .. " (" .. reason .. ")")
            return true
        end
    end
    
    log("\nNo 4K+ external displays found")
    return false
end

-- Update dock visibility based on display configuration
local function updateDockVisibility()
    local has4K = has4KDisplay()
    local shouldHide = not has4K
    
    if lastState == nil or lastState ~= shouldHide then
        lastState = shouldHide
        local action = shouldHide and "Hiding" or "Showing"
        log(string.format("%s Dock (4K display %s)", 
            action, has4K and "connected" or "not connected"))
        
        -- Use both hs.dockicon and AppleScript for maximum compatibility
        local success, err = pcall(function()
            -- First try using hs.dockicon
            hs.dockicon.hide(shouldHide)
            
            -- Then use AppleScript to ensure the setting is applied
            local script = string.format([[
                tell application "System Events"
                    tell dock preferences
                        set autohide to %s
                    end tell
                end tell
            ]], tostring(shouldHide))
            
            local ok, result = hs.osascript.applescript(script)
            if not ok then
                log("AppleScript error: " .. tostring(result))
            end
        end)
        
        if not success then
            log("Error toggling Dock: " .. tostring(err))
        end
        
        -- Show a notification about the change
        hs.notify.new({
            title = "Dock Auto-Hide",
            subTitle = string.format("Dock will now %s", shouldHide and "hide" or "show"),
            informativeText = string.format("4K+ display %s", has4K and "detected" or "not detected")
        }):send()
    end
end

-- Debounced update function
local debouncedUpdate = hs.timer.delayed.new(DOCK_HIDE_DELAY, function()
    updateDockVisibility()
end)

-- Watch for display changes and update dock visibility
local function screenWatcher()
    debouncedUpdate:stop()
    debouncedUpdate:start()
end

-- Create screen watchers
local screenWatcher = hs.screen.watcher.new(screenWatcher)
local usbWatcher = hs.usb.watcher.new(function()
    -- USB events might indicate display changes
    screenWatcher()
end)

-- Start watching for changes
screenWatcher:start()
usbWatcher:start()

-- Initial check when Hammerspoon starts (with delay to ensure displays are ready)
hs.timer.doAfter(4, function()
    log("Initializing...")
    updateDockVisibility()
end)

-- Add a hotkey for manual refresh (⌘⌃⌥D)
hs.hotkey.bind({"cmd", "ctrl", "alt"}, "D", function()
    log("Manual refresh triggered")
    updateDockVisibility()
end)

log("Dock Auto-Hide script loaded")
