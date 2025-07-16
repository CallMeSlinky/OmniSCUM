local scriptPath = debug.getinfo(1, "S").source:sub(2)
local scriptDir = scriptPath:match("(.*[/\\])")

local libDir = scriptDir .. "Lib/"

package.path = table.concat({
    libDir .. '?.lua',
    libDir .. '?/init.lua',
    scriptDir .. 'Core/?.lua',
    scriptDir .. 'Addons/?.lua',
    scriptDir .. 'Config/?.lua',
    package.path
}, ';')

package.cpath = table.concat({
    libDir .. '?.dll',
    libDir .. '?/?.dll',
    package.cpath
}, ';')

print("[OmniSCUM] Loading Core Framework...")
require("OmniSCUM")
require("Utils")
print("[OmniSCUM] Core Framework Loaded.")
print("[OmniSCUM] Loading and Registering Addons...")
require("Bounty")
require("DiscordBot")
print("[OmniSCUM] All Addons Loaded and Registered.")

OmniSCUM:InitializeCore()
