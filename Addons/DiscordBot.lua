local json = require("json")
local pegasus = require("pegasus")
local http = require("socket.http")
local ltn12 = require("ltn12")
local Router = require("pegasus.plugins.router")
local UEHelper = require("UEHelpers")
local ConfigModule = require("DiscordBotConfig")
local Config = ConfigModule.DiscordBot

local DiscordBotAddon = {
    Name = "Discord Bot",
    Core = nil,
    Utils = nil,
    Server = nil,
    ServerErr = nil,
    ServerSettings = {},
    httpEventQueue = {},
    StartTime = nil
}

function DiscordBotAddon:Initialize(core)
    self.Core = core
    self.Utils = core.Utils
    self.players = {}

    self:StartHttpServer()
    self:GetServerSettings()
    self.StartTime = os.time()
    self:InitializeHooks()
end

function DiscordBotAddon:StartHttpServer()
    local routes = {
        ["/server"] = {
            GET = function(req, res) self:getServer(req, res) end
        },
        ["/announce"] = {
            POST = function(req, res) self:handleAnnounce(req, res) end
        }
    }

    self.Server, self.ServerErr = pegasus:new({
        host = "0.0.0.0",
        port = Config.HttpServer.Port or 8080,
        plugins = {
            Router:new {
                routes = routes
            }
        }
    })

    if not self.Server then
        self:Printf(true, "Failed to create HTTP server: " .. tostring(self.ServerErr))
        return
    end

    ExecuteAsync(function()
        self:Printf(false, "HTTP Server starting on port %d...", Config.HttpServer.Port or 8080)

        local ok, start_err = pcall(function()
            self.Server:start()
        end)

        if not ok then
            self:Printf(true, "HTTP Server failed to start or crashed: " .. tostring(start_err))
        end
    end)
end

function DiscordBotAddon:InitializeHooks()
    self.Core:RegisterHookCallback("/Script/ConZ.ConZGameState:Multicast_AddToOrUpdatePrisonerKillRegistry",
        function(_, Target, killer) self:HandleKillEvent(Target, killer) end)

    -- self.Core:RegisterHookCallback("/Script/ConZ.ConZPlayerController:Server_ReportPlayPreparationsSucceeded",
    --     function(PlayerController) self:HandlePlayerConnect(PlayerController) end)

    -- self.Core:RegisterHookCallback("/Script/ConZ.PlayerRpcChannel:SurvivalStats_Server_HandlePlayerLogout",
    --     function(_, PlayerController) self:HandlePlayerDisconnect(PlayerController) end)
end

function DiscordBotAddon:PostEventData(endpoint, eventPayload)
    ExecuteInGameThread(function()
        local ok, err = pcall(function()
            local body = json.encode(eventPayload)

            self:Printf(false, "Sending HTTP POST request to: %s/%s", Config.DiscordHTTPServer.Url, endpoint)

            local res, code, headers, status = http.request({
                method = "POST",
                url = Config.DiscordHTTPServer.Url .. "/" .. endpoint,
                source = ltn12.source.string(body),
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Content-Length"] = #body,
                    ["X-API-Key"] = Config.DiscordHTTPServer.ApiKey
                }
            })

            if type(code) == "number" and (code >= 200 and code < 300) then
                self:Printf(false, "Successfully sent event to /%s. Response Code: %s", endpoint, tostring(code))
            else
                -- This 'else' block now correctly handles both HTTP errors (like 404, 500) and connection errors (where 'code' is a string).
                self:Printf(true, "Failed to send /%s event. Status: %s, Code: %s, Response Body: %s", endpoint,
                    tostring(status), tostring(code), tostring(res))
            end
        end)

        if not ok then
            self:Printf(true, "Crash inside PostEventData: %s", tostring(err))
        end
    end)
end

function DiscordBotAddon:HandleKillEvent(Target, Killer)
    self:Printf("Handling kill event...")

    local victimController = self.Utils:GetControllerByUserId(Target.Value)
    local killerController = self.Utils:GetControllerByUserId(Killer.Value)
    if not victimController or not killerController then
        self:Printf(true, "Could not find victim or killer controller.")
        return
    end

    local victimUserId = victimController:GetUserId():ToString()
    local killerUserId = killerController:GetUserId():ToString()
    local victimUsername = victimController:GetUserName2():ToString()
    local killerUsername = killerController:GetUserName2():ToString()
    local victimCharacter = victimController:GetPrisoner()
    local killerCharacter = killerController:GetPrisoner()

    if not victimCharacter:IsValid() or not killerCharacter:IsValid() then
        self:Printf(true, "Victim or Killer character is not valid.")
        return
    end

    local distanceInCm = victimCharacter:GetDistanceTo(killerCharacter)
    local distanceInMeters = distanceInCm / 100.0
    local formattedDistance = self:FormatDistance(distanceInMeters)
    local killTimestamp = os.date("[%H:%M]")

    local eventPayload = {
        killer = {
            name = killerUsername,
            steamId = killerUserId
        },
        victim = {
            name = victimUsername,
            steamId = victimUserId 
        },
        timestamp = killTimestamp,
        distance = formattedDistance
    }

    self:PostEventData("kill-event", eventPayload)
end

function DiscordBotAddon:GetServerSettings()
    self.ServerSettings = {}

    local savedDir = self.Utils:GetRootSaveDirectory()
    if not savedDir or savedDir == "" then
        return nil
    end

    local fullPath = savedDir .. "Config/WindowsServer/ServerSettings.ini"

    local file, err = io.open(fullPath, "r")
    if not file then
        self:Printf(true, "Could not open ServerSettings.ini. Error: %s", tostring(err))
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

function DiscordBotAddon:handleAnnounce(req, res)
    self:Printf(false, "HTTP: Received POST request for /announce")

    if not self:IsAuthorized(req) then
        res:statusCode(401):write(json.encode({ error = "Unauthorized" }))
        return
    end

    local body = req:receiveBody()
    local success, data = pcall(json.decode, body)
    if not success or not data or not data.message or data.message == "" then
        res:statusCode(400):write(json.encode({ error = "Bad Request: Missing or invalid JSON body with 'message' field." }))
        return
    end

    ExecuteInGameThread(function()
        self.Utils:Announce(data.message, "Announce", "")
    end)

    res:statusCode(204):write()
end

function DiscordBotAddon:getServer(req, res)
    self:Printf(false, "HTTP: Received GET request for /server")

    if not self:IsAuthorized(req) then
        res:statusCode(401):write(json.encode({ error = "Unauthorized" }))
        return
    end

    ExecuteInGameThread(function()
        local playerList = {}
        local gameSession = StaticFindObject("/Script/Engine.GameSession")
        local miscStatics = StaticFindObject("/Script/ConZ.Default__MiscStatics")

        if not gameSession or not gameSession:IsValid() then return end
        if not miscStatics or not miscStatics:IsValid() then return end

        local gameVersion = miscStatics:GetGameVersion():ToString()
        self.ServerSettings.gameVersion = gameVersion

        local allPlayerPawns = UEHelper:GetAllPlayers()
        if not allPlayerPawns then return nil end
        for _, currentPawn in ipairs(allPlayerPawns) do
            if not currentPawn:IsValid() or not currentPawn:IsA("/Script/ConZ.Prisoner") then goto continue end
            local controller = currentPawn:GetController()
            if controller and controller:IsValid() then
                table.insert(playerList, {
                    name = controller:GetUserName2():ToString(),
                    steamId = controller:GetUserId():ToString()
                })
            end
            ::continue::
        end
        if self.StartTime then
            self.ServerSettings.uptime = os.time() - self.StartTime
        end

        res:statusCode(200):write(json.encode({ serverSettings = self.ServerSettings, playerList = playerList }))
    end)
end

function DiscordBotAddon:FormatDistance(num)
    local roundedNum = math.floor(num * 10 + 0.5) / 10

    if roundedNum == math.floor(roundedNum) then
        return string.format("%.0f", roundedNum)
    else
        return string.format("%.1f", roundedNum)
    end
end

function DiscordBotAddon:IsAuthorized(req)
    local apiKey = req:headers()["X-API-Key"]
    if not apiKey or apiKey ~= Config.HttpServer.ApiKey then
        return false
    end
    return true
end

if Config.HttpServer.Enabled then
    OmniSCUM:RegisterAddon(DiscordBotAddon)
end
