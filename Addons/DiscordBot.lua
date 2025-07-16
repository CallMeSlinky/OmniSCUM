local json = require("json")
local http = require("socket.http")
local ltn12 = require("ltn12")
local UEHelper = require("UEHelpers")
local ConfigModule = require("DiscordBotConfig")
local Config = ConfigModule.DiscordBot

local DiscordBotAddon = {
    Name = "Discord Bot",
    Core = nil,
    Utils = nil,
    ServerSettings = {},
    StartTime = nil,
    players = {}
}

function DiscordBotAddon:Initialize(core)
    self.Core = core
    self.Utils = core.Utils

    self.BountyAddon = self:GetBountyAddonReference()
    self:GetServerSettings()
    self.StartTime = os.time()
    self:StartCommandPoller()
    self:StartStatusPusher()
    self:InitializeHooks()
end

function DiscordBotAddon:GetBountyAddonReference()
    if self.Core and self.Core.Addons then
        for _, addon in ipairs(self.Core.Addons) do
            if addon.Name == "Bounty" then
                return addon
            end
        end
    end
    self:Printf(false, "Could not find registered Bounty addon.")
    return nil
end

function DiscordBotAddon:StartCommandPoller()
    if not Config.DiscordBotServer or not Config.DiscordBotServer.CommandPolling then
        self:Printf(false, "Command polling is disabled.")
        return
    end

    local pollInterval = Config.DiscordBotServer.CommandPollingIntervalSeconds or 5
    local pollIntervalMs = pollInterval * 1000

    self:Printf(false, "Starting command poller. Will check for commands every %d seconds.", pollInterval)

    LoopAsync(pollIntervalMs, function()
        ExecuteAsync(function()
            self:FetchAndProcessCommands()
        end)
        return false
    end)
end

function DiscordBotAddon:StartStatusPusher()
    local intervalInSeconds = Config.DiscordBotServer.DiscordServerStatusUpdateInterval or 60

    local intervalInMilliseconds = intervalInSeconds * 1000

    self:Printf(false, "Starting status pusher. Will push status updates every %d seconds.", intervalInSeconds)

    LoopAsync(intervalInMilliseconds, function()
        ExecuteAsync(function()
            ExecuteInGameThread(function()
                local playerList = {}
                local allPlayerPawns = UEHelper:GetAllPlayers()
                if allPlayerPawns then
                    for _, currentPawn in ipairs(allPlayerPawns) do
                        if currentPawn:IsValid() and currentPawn:IsA("/Script/ConZ.Prisoner") then
                            local controller = currentPawn:GetController()
                            if controller and controller:IsValid() then
                                table.insert(playerList, {
                                    name = controller:GetUserName2():ToString(),
                                    steamId = controller:GetUserId():ToString()
                                })
                            end
                        end
                    end
                end

                local miscStatics = StaticFindObject("/Script/ConZ.Default__MiscStatics")
                if miscStatics and miscStatics:IsValid() then
                    self.ServerSettings.gameVersion = miscStatics:GetGameVersion():ToString()
                end

                local statusPayload = {
                    serverSettings = self.ServerSettings,
                    playerList = playerList,
                    bounties = {}
                }

                if self.BountyAddon then
                    local bountyData = self.BountyAddon:GetBountyDataForAPI()
                    if bountyData then
                        statusPayload.bounties = bountyData
                    end
                end

                if self.StartTime then
                    statusPayload.serverSettings.uptime = os.time() - self.StartTime
                end

                self:PostEventData("update-status", statusPayload)
            end)
            return false
        end)
    end)
end

function DiscordBotAddon:FetchAndProcessCommands()
    local ok, err = pcall(function()
        local responseBodyChunks = {}

        local _, code = http.request({
            method = "GET",
            url = Config.DiscordBotServer.Url .. "/get-commands",
            headers = {
                ["X-API-Key"] = Config.DiscordBotServer.ApiKey
            },
            sink = ltn12.sink.table(responseBodyChunks)
        })

        if code ~= 200 then
            self:Printf(true, "Failed to fetch commands. Status Code: %s", tostring(code))
            return
        end

        local resBodyString = table.concat(responseBodyChunks)

        if resBodyString == "" or resBodyString == "[]" then
            return
        end

        local success, commands = pcall(json.decode, resBodyString)
        if not success or type(commands) ~= "table" then
            self:Printf(true, "Failed to decode commands from server. Error: %s", tostring(commands))
            return
        end

        if #commands > 0 then
            self:Printf(false, "Processing %d command(s) from server...", #commands)
            ExecuteInGameThread(function()
                for _, command in ipairs(commands) do
                    self:Printf(false, "Executing command: %s", json.encode(command))
                    if command.type == "announce" and command.message then
                        self.Utils:Announce(command.message, "Announce", "")
                    end
                end
            end)
        end
    end)

    if not ok then
        self:Printf(true, "Error during FetchAndProcessCommands: %s", tostring(err))
    end
end

function DiscordBotAddon:InitializeHooks()
    if Config.Chat.Enabled then
        self.Core:RegisterHookCallback("/Script/ConZ.PlayerRpcChannel:Chat_Server_BroadcastChatMessage",
            function(rpcChannel, message, channel) self:HandleChatEvent(rpcChannel, message, channel) end)
    end

    if Config.Connections.Enabled then
        self.Core:RegisterHookCallback("/Script/ConZ.ConZPlayerController:Server_ReportPlayPreparationsSucceeded",
            function(PlayerController) self:HandlePlayerConnectEvent(PlayerController) end)

        -- This event doesn't seem to return the user's name or Steam ID, but i'm pretty sure this was working before??
        self.Core:RegisterHookCallback("/Script/ConZ.PlayerRpcChannel:SurvivalStats_Server_HandlePlayerLogout",
        function(_, PlayerController) self:HandlePlayerDisconnectEvent(PlayerController) end)
    end

    if Config.Kills.Enabled then
        self.Core:RegisterHookCallback("/Script/ConZ.ConZGameState:Multicast_AddToOrUpdatePrisonerKillRegistry",
            function(_, Target, Killer) self:HandleKillEvent(Target, Killer) end)
    end

    -- Not implemented yet
    
    -- if Config.Admin.Enabled then
    --     self.Core:RegisterHookCallback("/Script/ConZ.PlayerRpcChannel:Chat_Server_ProcessAdminCommand",
    --         function(PlayerRpcChannel, commandText) self:HandleAdminCommand(PlayerRpcChannel, commandText) end)
    -- end

    -- if Config.Interactions.Lockpicking.Enabled then
    --     self.Core:RegisterHookCallback("/Script/ConZ.Prisoner:Server_lockpickingEnded",
    --         function(Prisoner, Lockpickable, Succeeded, lockpickableBaseElement)
    --             self:HandleLockpicking(Prisoner,
    --                 Lockpickable, Succeeded, lockpickableBaseElement)
    --         end)
    -- end
end

function DiscordBotAddon:PostEventData(endpoint, eventPayload)
    ExecuteAsync(function()
        local ok, err = pcall(function()
            local body = json.encode(eventPayload)
            self:Printf(false, "Sending HTTP POST request to: %s/%s", Config.DiscordBotServer.Url, endpoint)
            http.request({
                method = "POST",
                url = Config.DiscordBotServer.Url .. "/" .. endpoint,
                source = ltn12.source.string(body),
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Content-Length"] = #body,
                    ["X-API-Key"] = Config.DiscordBotServer.ApiKey
                }
            })
        end)
        if not ok then
            self:Printf(true, "Crash inside PostEventData's async task: %s", tostring(err))
        end
    end)
end

function DiscordBotAddon:HandleChatEvent(rpcChannel, Message, Channel)
    ExecuteInGameThread(function()
        local message = Message:ToString()

        if string.sub(message, 1, 1) == "!" then
            return
        end

        if not Config.Chat.Enabled or not self:IsChannelEnabled(Channel) then
            return
        end

        local eventPayload = {
            message = message
        }

        if Config.Chat.DisplayUsername or Config.Chat.DisplaySteamID then
            if rpcChannel:IsValid() then
                local controller = rpcChannel:GetOwner()
                if controller:IsValid() then
                    local user = {}
                    if Config.Chat.DisplayUsername then
                        user.name = controller:GetUserName2():ToString()
                    end
                    if Config.Chat.DisplaySteamID then
                        user.steamId = controller:GetUserId():ToString()
                    end
                    eventPayload.user = user
                end
            end
        end

        if Config.Chat.DisplayMessageTime then
            eventPayload.timestamp = os.date("[%H:%M]")
        end

        if Config.Chat.DisplayChannelName then
            eventPayload.channel = self:GetChannelName(Channel)
        end

        self:PostEventData("chat-event", eventPayload)
    end)
end

function DiscordBotAddon:HandlePlayerConnectEvent(PlayerController)
    ExecuteInGameThread(function()
        if not PlayerController or not PlayerController:IsValid() then return end
        
        local userName = PlayerController:GetUserName2():ToString()
        local userId = PlayerController:GetUserId():ToString()

        self.players = self.players or {}
        self.players[userId] = {
            joinTimestamp = os.time()
        }

        local eventPayload = {
            type = "connect",
            user = {
                name = userName,
                steamId = userId
            }
        }

        self:PostEventData("connections", eventPayload)
    end)
end

function DiscordBotAddon:HandlePlayerDisconnectEvent(PlayerController)
    ExecuteInGameThread(function()
        if not PlayerController:IsValid() then return end

        local userName = PlayerController:GetUserName2():ToString()
        local userId = PlayerController:GetUserId():ToString()

        self:Printf("username: %s, userId: %s", userName, userId)

        local eventPayload = {
            type = "disconnect",
            user = {
                name = userName,
                steamId = userId
            }
        }

        if self.players and self.players[userId] and self.players[userId].joinTimestamp then
            local joinTimestamp = self.players[userId].joinTimestamp
            local playDurationSeconds = os.time() - joinTimestamp
            
            if playDurationSeconds >= 0 then
                eventPayload.playDuration = playDurationSeconds
            end
        end

        self:PostEventData("connections", eventPayload)

        if self.players then
            self.players[userId] = nil
        end
    end)
end

function DiscordBotAddon:HandleKillEvent(Target, Killer)
    ExecuteInGameThread(function()
        local victimController = self.Utils:GetControllerByUserId(Target.Value)
        local killerController = self.Utils:GetControllerByUserId(Killer.Value)
        if not victimController or not killerController then
            return
        end

        local victimUserId = victimController:GetUserId():ToString()
        local killerUserId = killerController:GetUserId():ToString()
        local victimUsername = victimController:GetUserName2():ToString()
        local killerUsername = killerController:GetUserName2():ToString()
        local victimCharacter = victimController:GetPrisoner()
        local killerCharacter = killerController:GetPrisoner()

        if not victimCharacter:IsValid() or not killerCharacter:IsValid() then
            return
        end

        local distanceInCm = victimCharacter:GetDistanceTo(killerCharacter)
        local distanceInMeters = distanceInCm / 100.0
        local formattedDistance = self:FormatDistance(distanceInMeters)
        local killTimestamp = os.date("[%H:%M]")

        local eventPayload = {
            killer = { name = killerUsername, steamId = killerUserId },
            victim = { name = victimUsername, steamId = victimUserId },
            timestamp = killTimestamp,
            distance = formattedDistance
        }

        self:PostEventData("kill-event", eventPayload)
    end)
end

function DiscordBotAddon:GetServerSettings()
    self.ServerSettings = {}
    local savedDir = self.Utils:GetRootSaveDirectory()
    if not savedDir or savedDir == "" then
        return
    end

    local fullPath = savedDir .. "Config/WindowsServer/ServerSettings.ini"
    local file, err = io.open(fullPath, "r")
    if not file then
        self:Printf(true, "Could not open ServerSettings.ini. Error: %s", tostring(err))
        return
    end

    for line in file:lines() do
        local key, value = line:match("^%s*scum%.([^=]+)%s*=%s*(.*)")
        if key then
            value = value:match("^(.-)%s*$")

            if key == "ServerName" then
                self.ServerSettings.name = value
            elseif key == "ServerDescription" then
                self.ServerSettings.description = value
            elseif key == "MaxPlayers" then
                self.ServerSettings.maxPlayers = tonumber(value)
            elseif key == "ServerPlaystyle" then
                self.ServerSettings.playstyle = value
            end
        end
    end

    file:close()
end

function DiscordBotAddon:IsChannelEnabled(channelValue)
    for _, enabledChannel in ipairs(Config.Chat.Channels) do
        if type(enabledChannel) == "string" then
            local convertedValue = self:GetChannelValue(enabledChannel)
            if convertedValue and convertedValue == channelValue then
                return true
            end
        elseif type(enabledChannel) == "number" then
            if enabledChannel == channelValue then
                return true
            end
        end
    end
    return false
end

function DiscordBotAddon:GetChannelName(channelValue)
    local channelNames = {
        [0] = "Default",
        [1] = "Local",
        [2] = "Global",
        [3] = "Squad",
        [4] = "Admin",
        [5] = "Commands",
        [6] = "Server",
        [7] = "Error"
    }
    return channelNames[channelValue] or "Unknown"
end

function DiscordBotAddon:GetChannelValue(channelName)
    local channelMap = {
        ["Default"] = 0,
        ["Local"] = 1,
        ["Global"] = 2,
        ["Squad"] = 3,
        ["Admin"] = 4,
        ["CommandsOnly"] = 5,
        ["Commands"] = 5,
        ["ServerMessage"] = 6,
        ["Server"] = 6,
        ["Error"] = 7
    }
    return channelMap[channelName]
end

function DiscordBotAddon:FormatDistance(num)
    local roundedNum = math.floor(num * 10 + 0.5) / 10
    if roundedNum == math.floor(roundedNum) then
        return string.format("%.0f", roundedNum)
    else
        return string.format("%.1f", roundedNum)
    end
end

if Config.AddonEnabled then
    OmniSCUM:RegisterAddon(DiscordBotAddon)
end
