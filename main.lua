-- ================== Path Setup ==================

-- Get the directory of the currently running script in a robust way.
local scriptPath = debug.getinfo(1, "S").source:sub(2) -- Remove the leading '@'
local scriptDir = scriptPath:match("(.*[/\\])")

-- Define the path to your new, clean library folder.
local libDir = scriptDir .. "Lib/"

-- Combine all paths, giving your local libraries priority.
package.path = table.concat({
    libDir .. '?.lua',                -- For top-level .lua files in Lib (e.g., socket.lua)
    libDir .. '?/init.lua',           -- For packages in Lib (e.g., pegasus)
    scriptDir .. 'Core/?.lua',
    scriptDir .. 'Addons/?.lua',
    scriptDir .. 'Config/?.lua',
    package.path                      -- Finally, the default path
}, ';')

package.cpath = table.concat({
    libDir .. '?.dll',                -- For top-level .dll files in Lib (e.g., lfs.dll)
    libDir .. '?/?.dll',              -- For nested .dll files in Lib (e.g., socket/core.dll)
    package.cpath                     -- Finally, the default path
}, ';')

-- ================================================


print("[OmniSCUM] Loading Core Framework...")
require("OmniSCUM")
require("Utils")
print("[OmniSCUM] Core Framework Loaded.")
print("[OmniSCUM] Loading and Registering Addons...")
require("Bounty")
require("DiscordBot")
print("[OmniSCUM] All Addons Loaded and Registered.")

OmniSCUM:InitializeCore()