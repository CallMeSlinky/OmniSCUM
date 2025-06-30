local json = require("json")
local UEHelper = require("UEHelpers")
local ConfigModule = require("DiscordLoggerConfig")
local Config = ConfigModule.DiscordLogger

local DiscordLoggerAddon = {
    Name = "Discord Logger",
    Core = nil,
    Utils = nil
}

function DiscordLoggerAddon:Initialize(core)
    self.Core = core
    self.Utils = core.Utils
    self.players = {}

    self:InitializeHooks()
end

function DiscordLoggerAddon:InitializeHooks()
    if Config.Chat.Enabled then
        self.Core:RegisterHookCallback("/Script/ConZ.PlayerRpcChannel:Chat_Server_BroadcastChatMessage",
            function(rpcChannel, message, channel) self:HandleChat(rpcChannel, message, channel) end)
    end

    if Config.Connections.Enabled then
        self.Core:RegisterHookCallback("/Script/ConZ.ConZPlayerController:Server_ReportPlayPreparationsSucceeded",
            function(PlayerController) self:HandlePlayerConnect(PlayerController) end)

        self.Core:RegisterHookCallback("/Script/ConZ.PlayerRpcChannel:SurvivalStats_Server_HandlePlayerLogout",
            function(_, PlayerController) self:HandlePlayerDisconnect(PlayerController) end)
    end

    if Config.Kills.Enabled then
        self.Core:RegisterHookCallback("/Script/ConZ.ConZGameState:Multicast_AddToOrUpdatePrisonerKillRegistry",
            function(_, Target, Killer) self:HandleKillEvent(Target, Killer) end)
    end

    if Config.Admin.Enabled then
        self.Core:RegisterHookCallback("/Script/ConZ.PlayerRpcChannel:Chat_Server_ProcessAdminCommand",
            function(PlayerRpcChannel, commandText) self:HandleAdminCommand(PlayerRpcChannel, commandText) end)
    end

    if Config.Interactions.Lockpicking.Enabled then
        self.Core:RegisterHookCallback("/Script/ConZ.Prisoner:Server_lockpickingEnded",
            function(Prisoner, Lockpickable, Succeeded, lockpickableBaseElement) self:HandleLockpicking(Prisoner,
                    Lockpickable, Succeeded, lockpickableBaseElement) end)
    end
end

function DiscordLoggerAddon:HandleChat(rpcChannel, Message, Channel)
    if not Config.Chat.Enabled or not self:IsChannelEnabled(Channel) then
        return
    end

    if not rpcChannel:IsValid() then return end
    local controller = rpcChannel:GetOwner()
    if not controller:IsValid() then return end

    local playerName = controller:GetUserName2():ToString()
    local playerSteamID = controller:GetUserId():ToString()
    local sanitizedMessage = self:SanitizeMessage(Message:ToString())

    local messageParts = {}

    if Config.Chat.DisplayMessageTime then
        local timestamp = os.date("[%H:%M]")
        table.insert(messageParts, timestamp)
    end

    if Config.Chat.DisplayChannelName then
        local channelName = self:GetChannelName(Channel)
        table.insert(messageParts, string.format("[%s]", channelName))
    end

    if Config.Chat.DisplayUsername then
        table.insert(messageParts, string.format("**%s**", playerName))
    end

    if Config.Chat.DisplaySteamID then
        table.insert(messageParts, string.format("(%s):", playerSteamID))
    end

    table.insert(messageParts, sanitizedMessage)

    local messageFormat = table.concat(messageParts, " ")

    self:SendToDiscord(self:GetWebhookUrl(Config.Chat), messageFormat)
end

function DiscordLoggerAddon:HandlePlayerConnect(playerController)
    if not playerController or not playerController:IsValid() then return end
    local userName = playerController:GetUserName2():ToString()
    local userId = playerController:GetUserId():ToString()

    self.players[userId] = {
        joinTimestamp = os.time()
    }

    local embed = {
        title = ":white_check_mark: Player Connected",
        description = string.format("[%s](http://steamcommunity.com/profiles/%s) has joined the server", userName, userId),
        color = 0x4CAF50,
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
    self:SendToDiscord(self:GetWebhookUrl(Config.Connections), embed, { useEmbed = true })
end

function DiscordLoggerAddon:HandlePlayerDisconnect(playerController)
    if not playerController or not playerController:IsValid() then return end

    local userId = playerController:GetUserId():ToString()
    local userName = playerController:GetUserName2():ToString()
    
    local fields = {}

    if self.players and self.players[userId] and self.players[userId].joinTimestamp then
        local joinTimestamp = self.players[userId].joinTimestamp
        local playDurationSeconds = os.time() - joinTimestamp
        
        if playDurationSeconds >= 0 then
            local playDurationFormatted = self:FormatDuration(playDurationSeconds)
            
            table.insert(fields, {
                name = ":video_game: Play Time",
                value = playDurationFormatted,
                inline = false
            })
        end
    end

    local embed = {
        title = ":x: Player Disconnected",
        description = string.format("[%s](https://steamcommunity.com/profiles/%s) has left the server.", userName, userId),
        color = 0xAF4C50, 
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }

    embed.fields = fields

    self:SendToDiscord(self:GetWebhookUrl(Config.Connections), embed, { useEmbed = true })

    if self.players then
        self.players[userId] = nil
    end
end

function DiscordLoggerAddon:HandleKillEvent(Target, Killer)
    local victimController = self.Utils:GetControllerByUserId(Target.Value)
    local killerController = self.Utils:GetControllerByUserId(Killer.Value)
    if not victimController or not killerController then return end

    local victimUserId = victimController:GetUserId():ToString()
    local killerUserId = victimController:GetUserId():ToString()
    local victimUsername = victimController:GetUserName2():ToString()
    local killerUsername = killerController:GetUserName2():ToString()
    local victimCharacter = victimController:GetPrisoner()
    local killerCharacter = killerController:GetPrisoner()

    if not victimCharacter:IsValid() or not killerCharacter:IsValid() then return end

    local distanceInCm = victimCharacter:GetDistanceTo(killerCharacter)
    local distanceInMeters = distanceInCm / 100.0
    local formattedDistance = self:FormatDistance(distanceInMeters)
    local killTimestamp = os.date("[%H:%M]")

    local messageFormat = ""

    if Target.Value == Killer.Value then
        messageFormat = string.format(":skull: %s **%s** (%s) killed themselves.", killTimestamp, victimUsername,
            victimUserId)
    else
        messageFormat = string.format(":skull: %s **~%s** (%s) killed **%s** (%s) from %sm", killTimestamp, killerUsername,
            killerUserId, victimUsername, victimUserId, formattedDistance)
    end

    self:SendToDiscord(self:GetWebhookUrl(Config.Kills), messageFormat)
end

function DiscordLoggerAddon:HandleAdminCommand(PlayerRpcChannel, commandText)
    local playerController = PlayerRpcChannel:GetOwner()
    if not playerController or not playerController:IsValid() then return end

    local adminUserId = playerController:GetUserId():ToString()
    local adminUsername = playerController:GetUserName2():ToString()
    local adminText = commandText:ToString() or ""
    local timestamp = os.date("[%H:%M]")

    if not adminText or not playerController:IsUserAdmin() then return end

    local messageFormat = string.format("%s **%s** (%s): `#%s`", timestamp, adminUsername, adminUserId, adminText)
    self:SendToDiscord(self:GetWebhookUrl(Config.Admin), messageFormat)
end

function DiscordLoggerAddon:HandleLockpicking(Prisoner, Lockpickable, Succeeded, lockpickableBaseElement)
    print("lockpicking")
    if not Prisoner or not Prisoner:IsValid() then return end

    local controller = Prisoner:GetController()

    if not controller or not controller:IsValid() then 
        print("Controller not valid")
     end

    local playerUserId = controller:GetUserId():ToString()
    local playerUsername = controller:GetUserName2():ToString()

    local lockpickableName = self:GetDisplayName(Lockpickable)
    print(lockpickableName)
    if not lockpickableName then return end


    local location = Lockpickable:K2_GetActorLocation()
    local x = math.floor(location.X)
    local y = math.floor(location.Y)
    local z = math.floor(location.Z)

    local teleportCmd = string.format("#teleport %d %d %d", x, y, z)

    local title, color
    if not Succeeded then
        title = "Lockpick Failure :lock:"
        color = 0xF44336
    else
        title = "Lockpick Success :unlock:"
        color = 0x4CAF50
    end

    local embed = {
        title = title,
        color = color,
        fields = {
            {
                name = "Player",
                value = string.format("[%s](http://steamcommunity.com/profiles/%s)", playerUsername, playerUserId),
                inline = true
            },
            {
                name = "Object",
                value = lockpickableName,
                inline = false
            },
            {
                name = "Location (Copy/Paste)",
                value = string.format("`%s`", teleportCmd),
                inline = false
            }
        },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }

    self:SendToDiscord(self:GetWebhookUrl(Config.Interactions), embed, { useEmbed = true })
end

function DiscordLoggerAddon:FormatDuration(totalSeconds)
    if not totalSeconds or totalSeconds < 0 then
        return "0s"
    end

    local days = math.floor(totalSeconds / 86400)
    local hours = math.floor((totalSeconds % 86400) / 3600)
    local minutes = math.floor((totalSeconds % 3600) / 60)
    local seconds = math.floor(totalSeconds % 60)

    local parts = {}
    if days > 0 then table.insert(parts, string.format("%dd", days)) end
    if hours > 0 then table.insert(parts, string.format("%dh", hours)) end
    if minutes > 0 then table.insert(parts, string.format("%dm", minutes)) end

    if seconds > 0 or #parts == 0 then
        table.insert(parts, string.format("%ds", seconds))
    end

    return table.concat(parts, " ")
end

function DiscordLoggerAddon:FormatDistance(num)
    local roundedNum = math.floor(num * 10 + 0.5) / 10

    if roundedNum == math.floor(roundedNum) then
        return string.format("%.0f", roundedNum)
    else
        return string.format("%.1f", roundedNum)
    end
end

function DiscordLoggerAddon:GetWebhookUrl(logTypeConfig)
    if logTypeConfig and logTypeConfig.Webhook and logTypeConfig.Webhook ~= "" then
        return logTypeConfig.Webhook
    end

    if Config.MasterWebhook and Config.MasterWebhook ~= "" then
        return Config.MasterWebhook
    end

    return nil
end

function DiscordLoggerAddon:SanitizeMessage(message)
    if not message then return "" end

    local sanitized = tostring(message)

    sanitized = sanitized:gsub("[^%w%s%.%,%!%?%-%(%)%'%\"%:%; ]", "")

    sanitized = sanitized:gsub("@everyone", "everyone")
    sanitized = sanitized:gsub("@here", "here")
    sanitized = sanitized:gsub("@([%w_]+)", "%1")

    sanitized = sanitized:gsub("^%s+", ""):gsub("%s+$", "")
    if #sanitized > 500 then
        sanitized = sanitized:sub(1, 500) .. "..."
    end

    return sanitized
end

function DiscordLoggerAddon:GetDisplayName(Object)
    if not Object or not Object:IsValid() then
        return nil
    end

    local kismetLib = UEHelper:GetKismetSystemLibrary()

    if not kismetLib then return end
    
    local displayName = kismetLib:GetDisplayName(Object):ToString()
    if displayName and displayName ~= "" then
        return displayName
    end
end

function DiscordLoggerAddon:IsChannelEnabled(channelValue)
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

function DiscordLoggerAddon:GetChannelName(channelValue)
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

function DiscordLoggerAddon:GetChannelValue(channelName)
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

function DiscordLoggerAddon:SendToDiscord(webhookUrl, data, options)
    if not webhookUrl then
        self:Printf(false, "Error: No webhook URL provided")
        return false
    end

    local payload = {
        username = Config.Appearance.Username or "SCUM Server",
        avatar_url = Config.Appearance.AvatarURL or ""
    }

    options = options or {}

    if options.content then
        payload.content = tostring(options.content)
    elseif not options.useEmbed then
        payload.content = tostring(data) or ""
    end

    if options.embed and type(options.embed) == "table" then
        payload.embeds = { options.embed }
        if not options.content and data then
            payload.content = tostring(data)
        end
    elseif options.useEmbed and type(data) == "table" then
        payload.embeds = { data }
    end

    local success, json_body = pcall(json.encode, payload)
    if not success then
        self:Printf("Error: Failed to encode JSON payload - " .. tostring(json_body))
        return false
    end

    local escaped_json = json_body:gsub('"', '\\"')
    local command = string.format(
        'chcp 65001 > nul && curl -H "Content-Type: application/json; charset=utf-8" -d "%s" "%s"', escaped_json,
        webhookUrl)

    local pipe = io.popen(command .. " 2>&1")
    if not pipe then
        self:Printf(false, "Error: Failed to execute curl command")
        return false
    end

    local result = pipe:read("*a")
    local exit_success = pipe:close()

    if not exit_success then
        self:Printf(false, "Error: curl command failed with non-zero exit code")
        return false
    end

    if result and result ~= "" then
        if result:find("error") or result:find("Error") or result:find("failed") or result:find("Failed") then
            self:Printf(false, "Error: Discord webhook request failed - " .. result:gsub("\n", " "))
            return false
        elseif result:find("HTTP/") and not result:find("200") and not result:find("204") then
            self:Printf(false, "Warning: Discord webhook returned non-success status - " .. result:gsub("\n", " "))
            return false
        end
    end

    return true
end

if Config.AddonEnabled then
    OmniSCUM:RegisterAddon(DiscordLoggerAddon)
end
