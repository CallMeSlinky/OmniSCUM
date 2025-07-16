OmniSCUM = OmniSCUM or {
    Addons = {},
    RootSaveFolder = nil,
    RootLogFolder = nil,
    Utils = nil,
    Database = nil,
    RegisteredCommands = {},
    RegisteredHooks = {},
}

function OmniSCUM:RegisterAddon(addon)
    if not addon.Name then
        print("[OmniSCUM] WARNING: An addon tried to register without a name.")
        return
    end

    for _, existingAddon in ipairs(self.Addons) do
        if existingAddon.Name == addon.Name then
            print(string.format("[OmniSCUM] WARNING: Addon '%s' is already registered. Skipping.", addon.Name))
            return
        end
    end

    print(string.format("[OmniSCUM] Registering Addon: %s", addon.Name))
    table.insert(self.Addons, addon)
end

function OmniSCUM:InitializeCore()
    self.Utils = OmniSCUM.Utils
    print("[OmniSCUM] Initializing Core...")

    self:SetupDirectories()

    local dbPath = self.RootSaveFolder .. "OmniSCUM.db"
    self.Database = self.Utils:GetDatabaseConnection(dbPath, function(...) self:Printf("[OmniSCUM::DB]", ...) end)
    
    if not self.Database then
        self:Printf("[OmniSCUM]", "CRITICAL: Database initialization failed. OmniSCUM cannot continue.")
        return
    end

    self:InitializeAddons()
    self:InitializeHookDispatchers()

    self:RegisterHookCallback("/Script/ConZ.PlayerRpcChannel:Chat_Server_BroadcastChatMessage",
        function(...) self:HandleChatCommand(...) end)

    print("[OmniSCUM] Core Initialization Complete.")
end

function OmniSCUM:InitializeAddons()
    print("[OmniSCUM] Initializing Addons...")
    for _, addon in ipairs(self.Addons) do
        local logFilePath = self.RootLogFolder .. addon.Name .. "Log.txt"
        local logPrefix = "OmniSCUM::" .. addon.Name

        addon.Printf = function(self, ...)
            OmniSCUM.Utils:LogPrintf(logFilePath, logPrefix, ...)
        end

        if addon.Initialize then
            print(string.format("[OmniSCUM] Initializing Addon: %s...", addon.Name))
            addon:Initialize(self)
        end
    end
    print("[OmniSCUM] All addons initialized.")
end

function OmniSCUM:RegisterHookCallback(hookName, callback)
    if not self.RegisteredHooks[hookName] then
        self.RegisteredHooks[hookName] = {}
    end
    table.insert(self.RegisteredHooks[hookName], callback)
end

function OmniSCUM:InitializeHookDispatchers()
    local supportedHooks = {
        "/Script/ConZ.ConZGameState:Multicast_AddToOrUpdatePrisonerKillRegistry",
        "/Script/ConZ.PlayerRpcChannel:Chat_Server_BroadcastChatMessage",
        "/Script/ConZ.ConZPlayerController:Server_ReportPlayPreparationsSucceeded",
        "/Script/ConZ.PlayerRpcChannel:SurvivalStats_Server_HandlePlayerLogout",
        "/Script/ConZ.PlayerRpcChannel:Chat_Server_ProcessAdminCommand",
        "/Script/ConZ.Prisoner:Server_lockpickingEnded",
        "/Script/Engine.GameInstance:ReceiveShutdown",
    }

    for _, hookName in ipairs(supportedHooks) do
        RegisterHook(hookName, function(...)
            if self.RegisteredHooks and self.RegisteredHooks[hookName] then
                local args = { ... }
                local processedArgs = {}
                for i, v in ipairs(args) do
                    table.insert(processedArgs, v:get())
                end
                for _, callback in ipairs(self.RegisteredHooks[hookName]) do
                    local success, err = pcall(callback, table.unpack(processedArgs))
                    if not success then
                        self:Printf("[OmniSCUM]", "Error in hook callback for %s: %s", hookName, tostring(err))
                    end
                end
            end
        end)
    end
end

function OmniSCUM:RegisterChatCommand(command, callback)
    local cmd = string.lower(command)
    if self.RegisteredCommands[cmd] then
        print(string.format("[OmniSCUM] WARNING: Command '%s' is already registered and will be overwritten.", cmd))
    end
    self.RegisteredCommands[cmd] = callback
end

function OmniSCUM:HandleChatCommand(rpcChannel, Message, Channel)
    if not rpcChannel:IsValid() then return end
    local controller = rpcChannel:GetOwner()
    if not controller:IsValid() then return end

    local message = Message:ToString()
    local lowerMessage = string.lower(message)
    local cmd = lowerMessage:match("^(%S+)")
    cmd = cmd or lowerMessage

    if self.RegisteredCommands and self.RegisteredCommands[cmd] then
        self.RegisteredCommands[cmd](controller, message)
    end
end

function OmniSCUM:Printf(prefix, ...)
    local logFilePath = self.RootLogFolder .. "OmniSCUM.txt"
    self.Utils:LogPrintf(logFilePath, prefix, ...)
end

function OmniSCUM:SetupDirectories()
    local savedDir = self.Utils:GetRootSaveDirectory()
    self.RootSaveFolder = savedDir .. "SaveFiles/OmniSCUM/"
    self.RootLogFolder = self.RootSaveFolder .. "logs/"
    self.Utils:CreateDirectory(self.RootSaveFolder)
    self.Utils:CreateDirectory(self.RootLogFolder)
end
