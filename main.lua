local mainScriptPath = debug.getinfo(1, "S").source
local scriptsDir = mainScriptPath:sub(2):match("^(.*[/\\])"):gsub("\\", "/")

package.path = package.path .. ';' ..
    scriptsDir .. 'Core/?.lua;' ..
    scriptsDir .. 'Lib/?.lua;' ..
    scriptsDir .. 'Addons/?.lua;' ..
    scriptsDir .. 'Config/?.lua'

print("[OmniSCUM] Loading Core Framework...")
require("OmniSCUM")
require("Utils")
print("[OmniSCUM] Core Framework Loaded.")
print("[OmniSCUM] Loading and Registering Addons...")
require("Bounty")
require("DiscordLogger")
print("[OmniSCUM] All Addons Loaded and Registered.")

OmniSCUM:InitializeCore()