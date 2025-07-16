local ConfigModule = require("BountyConfig")
local Config = ConfigModule.Bounty
local JSON = require("json")

local BountyAddon = {
    Name = "Bounty",
    Data = nil,
    Core = nil,
    Utils = nil,
    DB = nil
}

function BountyAddon:Initialize(core)
    self.Core = core
    self.Utils = core.Utils
    self.DB = core.Database

    if not self.DB then
        self:Printf(false, "FATAL: Database connection not available. Bounty addon cannot start.")
        return
    end

    self:InitializeDatabaseSchema()
    self:LoadData()
    self:InitializeHooks()
    self:StartSaveTimer()
    self:StartBountyExpirationTimer()
    self:StartLocationUpdateTimer()
end

function BountyAddon:InitializeDatabaseSchema()
    local sql = [[
        CREATE TABLE IF NOT EXISTS bounties (
            target_user_id TEXT PRIMARY KEY NOT NULL,
            target_name TEXT NOT NULL,
            reward_cash INTEGER DEFAULT 0,
            reward_gold INTEGER DEFAULT 0,
            reward_fame INTEGER DEFAULT 0,
            creation_timestamp INTEGER NOT NULL,
            last_seen_timestamp INTEGER,
            last_seen_sector TEXT,
            last_seen_keypad TEXT
        );

        CREATE TABLE IF NOT EXISTS bounty_placers (
            bounty_target_user_id TEXT NOT NULL,
            placer_user_id TEXT NOT NULL,
            placer_name TEXT NOT NULL,
            contribution_cash INTEGER DEFAULT 0,
            contribution_gold INTEGER DEFAULT 0,
            contribution_fame INTEGER DEFAULT 0,
            PRIMARY KEY (bounty_target_user_id, placer_user_id),
            FOREIGN KEY (bounty_target_user_id) REFERENCES bounties(target_user_id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS pending_refunds (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            placer_user_id TEXT NOT NULL,
            target_name TEXT NOT NULL,
            refund_cash INTEGER DEFAULT 0,
            refund_gold INTEGER DEFAULT 0,
            refund_fame INTEGER DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS placer_cooldowns (
            placer_user_id TEXT PRIMARY KEY NOT NULL,
            last_new_bounty_timestamp INTEGER,
            last_placement_per_target_json TEXT
        );
    ]]

    local success, err = pcall(function() self.DB:exec(sql) end)
    if not success then
        self:Printf(false, "ERROR: Failed to create database schema: %s", tostring(err))
    else
        self:Printf(false, "Database schema verified/created successfully.")
    end
end

function BountyAddon:GetMessage(key, replacements)
    return self.Utils:GetMessage(Config.Messages, key, replacements, function(...) self:Printf(...) end)
end

function BountyAddon:SaveData()
    local success, err = pcall(function()
        self.DB:exec('BEGIN')

        self.DB:exec(
            'DELETE FROM bounty_placers; DELETE FROM bounties; DELETE FROM pending_refunds; DELETE FROM placer_cooldowns;')

        local bounty_stmt = self.DB:prepare('INSERT INTO bounties VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)')
        local placer_stmt = self.DB:prepare('INSERT INTO bounty_placers VALUES (?, ?, ?, ?, ?, ?)')
        local refund_stmt = self.DB:prepare(
            'INSERT INTO pending_refunds (placer_user_id, target_name, refund_cash, refund_gold, refund_fame) VALUES (?, ?, ?, ?, ?)')
        local cooldown_stmt = self.DB:prepare('INSERT INTO placer_cooldowns VALUES (?, ?, ?)')

        -- Save Active Bounties
        for targetId, bounty in pairs(self.Data.ActiveBounties) do
            bounty_stmt:bind_values(
                bounty.TargetUserId, bounty.TargetName, bounty.Rewards.cash, bounty.Rewards.gold, bounty.Rewards.fame,
                bounty.CreationTimestamp, (bounty.LastSeen and bounty.LastSeen.Timestamp) or nil,
                (bounty.LastSeen and bounty.LastSeen.Sector) or nil, (bounty.LastSeen and bounty.LastSeen.Keypad) or nil
            )
            bounty_stmt:step()
            bounty_stmt:reset()

            for placerId, placer in pairs(bounty.Placers) do
                placer_stmt:bind_values(
                    targetId, placer.PlacerUserId, placer.PlacerName,
                    placer.Contributions.cash, placer.Contributions.gold, placer.Contributions.fame
                )
                placer_stmt:step()
                placer_stmt:reset()
            end
        end

        -- Save Pending Refunds
        for placerId, refunds in pairs(self.Data.PendingRefunds) do
            for _, refund in ipairs(refunds) do
                refund_stmt:bind_values(
                    placerId, refund.targetName,
                    refund.amount.cash, refund.amount.gold, refund.amount.fame
                )
                refund_stmt:step()
                refund_stmt:reset()
            end
        end

        -- Save Placer Cooldowns
        for placerId, data in pairs(self.Data.PlacerData) do
            cooldown_stmt:bind_values(
                placerId, data.lastNewBountyTimestamp, JSON.encode(data.lastPlacementPerTarget or {})
            )
            cooldown_stmt:step()
            cooldown_stmt:reset()
        end

        -- Finalize statements
        bounty_stmt:finalize()
        placer_stmt:finalize()
        refund_stmt:finalize()
        cooldown_stmt:finalize()

        self.DB:exec('COMMIT')
    end)

    if not success then
        self:Printf(false, "ERROR: Failed to save data to database: %s", tostring(err))
        self.DB:exec('ROLLBACK')
    else
        self:Printf(false, "Bounty data saved to database successfully.")
    end
end

function BountyAddon:LoadData()
    self.Data = {
        ActiveBounties = {},
        PendingRefunds = {},
        PlacerData = {}
    }

    local success, err = pcall(function()
        -- Load Bounties
        for row in self.DB:nrows('SELECT * FROM bounties') do
            self.Data.ActiveBounties[row.target_user_id] = {
                TargetUserId = row.target_user_id,
                TargetName = row.target_name,
                Rewards = { cash = row.reward_cash or 0, gold = row.reward_gold or 0, fame = row.reward_fame or 0 },
                Placers = {},
                CreationTimestamp = row.creation_timestamp,
                LastSeen = (row.last_seen_timestamp and {
                    Timestamp = row.last_seen_timestamp,
                    Sector = row.last_seen_sector,
                    Keypad = row.last_seen_keypad
                }) or nil
            }
        end

        -- Load Placers and attach to bounties
        for row in self.DB:nrows('SELECT * FROM bounty_placers') do
            local bounty = self.Data.ActiveBounties[row.bounty_target_user_id]
            if bounty then
                bounty.Placers[row.placer_user_id] = {
                    PlacerUserId = row.placer_user_id,
                    PlacerName = row.placer_name,
                    Contributions = { cash = row.contribution_cash or 0, gold = row.contribution_gold or 0, fame = row.contribution_fame or 0 }
                }
            end
        end

        -- Load Pending Refunds
        for row in self.DB:nrows('SELECT * FROM pending_refunds') do
            self.Data.PendingRefunds[row.placer_user_id] = self.Data.PendingRefunds[row.placer_user_id] or {}
            table.insert(self.Data.PendingRefunds[row.placer_user_id], {
                targetName = row.target_name,
                amount = { cash = row.refund_cash or 0, gold = row.refund_gold or 0, fame = row.refund_fame or 0 }
            })
        end

        -- Load Placer Cooldowns
        for row in self.DB:nrows('SELECT * FROM placer_cooldowns') do
            local placementData = nil
            local success_decode, decoded_value = pcall(JSON.decode, row.last_placement_per_target_json or "{}")

            if success_decode and type(decoded_value) == "table" then
                placementData = decoded_value
            else
                placementData = {}
            end

            self.Data.PlacerData[row.placer_user_id] = {
                lastNewBountyTimestamp = row.last_new_bounty_timestamp,
                lastPlacementPerTarget = placementData
            }
        end
    end)

    if not success then
        self:Printf(false, "ERROR: Failed to load data from database: %s", tostring(err))
    else
        self:Printf(false, "Bounty data loaded from database successfully.")
    end
end

function BountyAddon:InitializeHooks()
    local placeCmd = string.lower((Config.Commands and Config.Commands.PlaceBounty) or "!bounty")
    local viewCmd = string.lower((Config.Commands and Config.Commands.ViewBounties) or "!bounties")
    local clearCmd = string.lower((Config.Commands and Config.Commands.ClearBounty) or "!clearbounty")

    self.Core:RegisterChatCommand(placeCmd, function(c, m) self:Command_PlaceBounty(c, m) end)
    self.Core:RegisterChatCommand(viewCmd, function(c) self:Command_ViewBounties(c) end)
    self.Core:RegisterChatCommand(clearCmd, function(c, m) self:Command_ClearBounty(c, m) end)

    self.Core:RegisterHookCallback("/Script/ConZ.ConZGameState:Multicast_AddToOrUpdatePrisonerKillRegistry",
        function(_, Target, killer) self:HandleKillEvent(Target, killer) end)

    self.Core:RegisterHookCallback("/Script/ConZ.ConZPlayerController:Server_ReportPlayPreparationsSucceeded",
        function(PlayerController) self:HandlePlayerConnect(PlayerController) end)

    self.Core:RegisterHookCallback("/Script/ConZ.PlayerRpcChannel:SurvivalStats_Server_HandlePlayerLogout",
        function(_, PlayerController) self:HandlePlayerDisconnect(PlayerController) end)

    self.Core:RegisterHookCallback("/Script/Engine.GameInstance:ReceiveShutdown", function()
        self:Printf(false, "Server shutting down, saving bounty data...")
        self:SaveData()
    end)
end

function BountyAddon:Announce(message)
    local announcementType = Config.General.Announcements.AnnouncementType
    local prefix = string.format("%s: ", Config.General.Announcements.AnnouncementPrefix or "[Bounty]: ")
    self.Utils:Announce(message, announcementType, prefix)
end

function BountyAddon:GetAcceptedCurrenciesString()
    if not Config.Amount or not Config.Amount.AcceptedCurrencies then return "" end
    return table.concat(Config.Amount.AcceptedCurrencies, "/")
end

function BountyAddon:IsCurrencyAccepted(currency)
    if not Config.Amount or not Config.Amount.AcceptedCurrencies then return false end
    for _, acceptedCurrency in ipairs(Config.Amount.AcceptedCurrencies) do
        if currency == acceptedCurrency then return true end
    end
    return false
end

function BountyAddon:CountBountiesPlacedBy(placerUserId)
    local count = 0
    for _, bounty in pairs(self.Data.ActiveBounties) do
        if bounty.Placers[placerUserId] then count = count + 1 end
    end
    return count
end

function BountyAddon:Command_PlaceBounty(placerController, message)
    if not self:ValidatePlacerIsWhitelisted(placerController) then return end

    local args = self:ParsePlaceBountyArgs(placerController, message)
    if not args then return end

    if not self:ValidateCurrency(placerController, args.lowerCurrency) then return end

    local targetInfo = self:ValidateTarget(placerController, args.targetName)
    if not targetInfo then return end

    if not self:ValidateSelfBounty(placerController, targetInfo.targetUserId) then return end
    if not self:ValidateRateLimiting(placerController, targetInfo.targetUserId) then return end
    if not self:ValidateAmount(placerController, args.amount, args.lowerCurrency) then return end
    if not self:ValidateTotalBounty(placerController, targetInfo.targetUserId, args.amount, args.lowerCurrency) then return end
    if not self:DeductPlacerFunds(placerController, args.amount, args.lowerCurrency) then return end

    self:UpdateBountyData(placerController, targetInfo, args.amount, args.lowerCurrency)
    self:SaveData()
end

function BountyAddon:ParsePlaceBountyArgs(placerController, message)
    local placeCmd = (Config.Commands and Config.Commands.PlaceBounty) or "!bounty"
    local currencyUsage = self:GetAcceptedCurrenciesString()
    local argsStr = message:match("^%S+%s+(.*)")

    if not argsStr then
        self.Utils:SendClientHUDMessage(placerController,
            self:GetMessage("HudUsage", { command = placeCmd, currencies = currencyUsage }))
        return nil
    end

    local targetName, amountStr, currencyType = argsStr:match('^"([^"]+)"%s+(%d+)%s+(%w+)')
    if not targetName then
        targetName, amountStr, currencyType = argsStr:match('^([%S]+)%s+(%d+)%s+(%w+)')
    end

    if not targetName or not amountStr or not currencyType then
        self.Utils:SendClientHUDMessage(placerController,
            self:GetMessage("HudUsage", { command = placeCmd, currencies = currencyUsage }))
        return nil
    end

    return {
        targetName = targetName,
        amount = tonumber(amountStr),
        lowerCurrency = string.lower(currencyType)
    }
end

function BountyAddon:ValidatePlacerIsWhitelisted(placerController)
    if Config.General.Whitelist and Config.General.Whitelist.Enabled then
        local placerSteamId = placerController:GetUserId():ToString()
        for _, whitelistedId in ipairs(Config.General.Whitelist.WhitelistedSteamIDs) do
            if whitelistedId == placerSteamId then return true end
        end
        self.Utils:SendClientHUDMessage(placerController, self:GetMessage("HudNotAuthorized"))
        return false
    end
    return true
end

function BountyAddon:ValidateCurrency(placerController, lowerCurrency)
    if not self:IsCurrencyAccepted(lowerCurrency) then
        local currencyUsage = self:GetAcceptedCurrenciesString()
        self.Utils:SendClientHUDMessage(placerController,
            self:GetMessage("HudInvalidCurrency", { currencies = currencyUsage }))
        return false
    end
    return true
end

function BountyAddon:ValidateTarget(placerController, targetName)
    local targetController = self.Utils:GetControllerByName(targetName)
    if not targetController or not targetController:IsValid() then
        self.Utils:SendClientHUDMessage(placerController,
            self:GetMessage("HudPlayerNotFound", { targetName = targetName }))
        return nil
    end
    return {
        targetController = targetController,
        targetUserId = targetController:GetUserId():ToString(),
        targetName = targetController:GetUserName2():ToString()
    }
end

function BountyAddon:ValidateSelfBounty(placerController, targetUserId)
    if targetUserId == placerController:GetUserId():ToString() and not Config.General.AllowSelfBounty then
        self.Utils:SendClientHUDMessage(placerController, self:GetMessage("HudCannotBountySelf"))
        return false
    end
    return true
end

function BountyAddon:ValidateRateLimiting(placerController, targetUserId)
    if not Config.RateLimiting or placerController:IsUserAdmin() then return true end

    local placerUserId = placerController:GetUserId():ToString()

    local isUpdate = self.Data.ActiveBounties[targetUserId] and
        self.Data.ActiveBounties[targetUserId].Placers[placerUserId]

    if not isUpdate and Config.RateLimiting.EnableMaxActiveBounties then
        if self:CountBountiesPlacedBy(placerUserId) >= Config.RateLimiting.MaxActiveBounties then
            self.Utils:SendClientHUDMessage(placerController,
                self:GetMessage("HudMaxBounties", { maxBounties = Config.RateLimiting.MaxActiveBounties }))
            return false
        end
    end

    if Config.RateLimiting.EnableCooldowns then
        if type(self.Data.PlacerData[placerUserId]) ~= "table" then
            self.Data.PlacerData[placerUserId] = { lastPlacementPerTarget = {} }
        end
        local placerData = self.Data.PlacerData[placerUserId]

        if isUpdate then
            local timePassed = os.time() - (placerData.lastPlacementPerTarget[targetUserId] or 0)
            if timePassed < Config.RateLimiting.SameTargetCooldownSeconds then
                self.Utils:SendClientHUDMessage(placerController,
                    self:GetMessage("HudSameTargetCooldown",
                        { time = self.Utils:FormatTime(Config.RateLimiting.SameTargetCooldownSeconds - timePassed) }))
                return false
            end
        else
            local timePassed = os.time() - (placerData.lastNewBountyTimestamp or 0)
            if timePassed < Config.RateLimiting.NewBountyCooldownSeconds then
                self.Utils:SendClientHUDMessage(placerController,
                    self:GetMessage("HudNewBountyCooldown",
                        { time = self.Utils:FormatTime(Config.RateLimiting.NewBountyCooldownSeconds - timePassed) }))
                return false
            end
        end
    end
    return true
end

function BountyAddon:ValidateAmount(placerController, amount, lowerCurrency)
    local minAmount = Config.Amount.MinimumBounty[lowerCurrency]
    if not minAmount or amount < minAmount then
        self.Utils:SendClientHUDMessage(placerController,
            self:GetMessage("HudMinAmount",
                { currency = lowerCurrency, amount = self.Utils:FormatNumber(minAmount or 0) }))
        return false
    end

    local maxAmount = Config.Amount.MaximumBounty and Config.Amount.MaximumBounty[lowerCurrency]
    if maxAmount and amount > maxAmount then
        self.Utils:SendClientHUDMessage(placerController,
            self:GetMessage("HudMaxAmount", { currency = lowerCurrency, amount = self.Utils:FormatNumber(maxAmount) }))
        return false
    end
    return true
end

function BountyAddon:ValidateTotalBounty(placerController, targetUserId, amount, lowerCurrency)
    local totalMax = Config.Amount.TotalMaximumBounty and Config.Amount.TotalMaximumBounty[lowerCurrency]
    if totalMax and totalMax > 0 then
        local currentBountyAmount = (self.Data.ActiveBounties[targetUserId] and self.Data.ActiveBounties[targetUserId].Rewards[lowerCurrency]) or
            0
        if currentBountyAmount + amount > totalMax then
            self.Utils:SendClientHUDMessage(placerController,
                self:GetMessage("HudTotalMaxExceeded",
                    { currency = lowerCurrency, amount = self.Utils:FormatNumber(totalMax) }))
            return false
        end
    end
    return true
end

function BountyAddon:DeductPlacerFunds(placerController, amount, lowerCurrency)
    if lowerCurrency == "cash" then
        if placerController._moneyBalanceRep < amount then
            self.Utils:SendClientHUDMessage(placerController, self:GetMessage("HudNotEnoughCash")); return false
        end
        placerController:SetCurrencyBalanceRep(1, placerController._moneyBalanceRep - amount)
    elseif lowerCurrency == "gold" then
        if placerController._goldBalanceRep < amount then
            self.Utils:SendClientHUDMessage(placerController, self:GetMessage("HudNotEnoughGold")); return false
        end
        placerController:SetCurrencyBalanceRep(2, placerController._goldBalanceRep - amount)
    elseif lowerCurrency == "fame" then
        if placerController:GetFamePoints() < amount then
            self.Utils:SendClientHUDMessage(placerController, self:GetMessage("HudNotEnoughFame")); return false
        end
        placerController:SetFamePoints(placerController:GetFamePoints() - amount)
    end
    return true
end

function BountyAddon:UpdateBountyData(placerController, targetInfo, amount, lowerCurrency)
    local placerUserId = placerController:GetUserId():ToString()
    local placerName = placerController:GetUserName2():ToString()
    local targetUserId = targetInfo.targetUserId

    local isNewBounty = not self.Data.ActiveBounties[targetUserId]
    local isUpdateForPlacer = (not isNewBounty) and self.Data.ActiveBounties[targetUserId].Placers[placerUserId]

    if isNewBounty then
        self.Data.ActiveBounties[targetUserId] = {
            TargetName = targetInfo.targetName,
            TargetUserId = targetUserId,
            Rewards = { cash = 0, gold = 0, fame = 0 },
            Placers = {},
            CreationTimestamp = os.time()
        }
    end

    local bounty = self.Data.ActiveBounties[targetUserId]
    bounty.TargetName = targetInfo.targetName -- Update name in case of change
    bounty.Rewards[lowerCurrency] = (bounty.Rewards[lowerCurrency] or 0) + amount

    if not bounty.Placers[placerUserId] then
        bounty.Placers[placerUserId] = { PlacerName = placerName, PlacerUserId = placerUserId, Contributions = { cash = 0, gold = 0, fame = 0 } }
    end
    bounty.Placers[placerUserId].PlacerName = placerName -- Update name in case of change
    bounty.Placers[placerUserId].Contributions[lowerCurrency] = (bounty.Placers[placerUserId].Contributions[lowerCurrency] or 0) +
    amount

    if type(self.Data.PlacerData[placerUserId]) ~= "table" then
        self.Data.PlacerData[placerUserId] = { lastPlacementPerTarget = {} }
    end

    local currentTime = os.time()
    self.Data.PlacerData[placerUserId].lastPlacementPerTarget[targetUserId] = currentTime

    if not isUpdateForPlacer then
        self.Data.PlacerData[placerUserId].lastNewBountyTimestamp = currentTime
    end

    local totalBountyStr = self:FormatBountyString(bounty.Rewards)
    local messageKey
    if placerUserId == targetUserId then
        messageKey = isNewBounty and "BountyPlacedOnSelf" or "BountyUpdatedOnSelf"
    else
        messageKey = isNewBounty and "BountyPlaced" or "BountyUpdated"
    end

    self:Announce(self:GetMessage(messageKey,
        { placerName = placerName, bounty = totalBountyStr, targetName = targetInfo.targetName }))
    self:Printf("Bounty data updated for target %s (%s) by %s (%s). New total: %s", targetInfo.targetName, targetUserId,
        placerName, placerUserId, totalBountyStr)
end

function BountyAddon:Command_ViewBounties(controller)
    self.Utils:SendClientHUDMessage(controller, self:GetMessage("ViewBountiesHeader"))
    local hasBounties = false
    for _, bounty in pairs(self.Data.ActiveBounties) do
        local targetIsOnline = self.Utils:GetControllerByName(bounty.TargetName) and true or false
        if not targetIsOnline and not (Config.General.ShowOfflineBounties and not Config.Lifetime.RefundBountyOnDisconnect) then
            goto continue
        end

        hasBounties = true
        local status = targetIsOnline and self:GetMessage("ViewBountiesStatusOnline") or
            self:GetMessage("ViewBountiesStatusOffline")
        local totalBountyStr = self:FormatBountyString(bounty.Rewards)
        local remainingTimeStr = ""

        if Config.Lifetime.ExpireBounty and bounty.CreationTimestamp then
            local timeLeft = (Config.Lifetime.BountyLifetimeHours * 3600) - (os.time() - bounty.CreationTimestamp)
            if timeLeft > 0 then
                remainingTimeStr = self:GetMessage("ViewBountiesExpireTime", { time = self.Utils:FormatTime(timeLeft) })
            end
        end

        local locationStr = ""
        if Config.LocationTracking and Config.LocationTracking.Enabled and bounty.LastSeen and bounty.LastSeen.Timestamp then
            local locationReplacements = {}
            local hasLocationPart = false

            if Config.LocationTracking.ShowSector and bounty.LastSeen.Sector then
                locationReplacements.sector = bounty.LastSeen.Sector
                hasLocationPart = true
            end
            if Config.LocationTracking.ShowKeypad and bounty.LastSeen.Keypad then
                locationReplacements.keypad = bounty.LastSeen.Keypad
                hasLocationPart = true
            end

            if hasLocationPart then
                local timeAgoSeconds = os.time() - bounty.LastSeen.Timestamp
                local timeAgoMinutes = math.floor(timeAgoSeconds / 60)

                if timeAgoMinutes < 1 then
                    locationReplacements.timeAgo = self:GetMessage("ViewBountiesTimeAgoRecent")
                elseif timeAgoMinutes == 1 then
                    locationReplacements.timeAgo = self:GetMessage("ViewBountiesTimeAgoSingular")
                else
                    locationReplacements.timeAgo = self:GetMessage("ViewBountiesTimeAgoPlural",
                        { minutes = timeAgoMinutes })
                end

                locationReplacements.sector = locationReplacements.sector or ""
                locationReplacements.keypad = locationReplacements.keypad or ""

                locationStr = self:GetMessage("ViewBountiesLocation", locationReplacements)
            end
        end

        self.Utils:SendClientHUDMessage(controller,
            self:GetMessage("ViewBountiesLine",
                {
                    targetName = bounty.TargetName,
                    status = status,
                    bounty = totalBountyStr,
                    expireTime = remainingTimeStr,
                    location = locationStr
                }))
        ::continue::
    end
    if not hasBounties then
        self.Utils:SendClientHUDMessage(controller, self:GetMessage("ViewBountiesNone"))
    end
end

function BountyAddon:Command_ClearBounty(adminController, message)
    if not adminController:IsUserAdmin() then
        self.Utils:SendClientHUDMessage(adminController, "You do not have permission to use this command.")
        return
    end

    local commandName = (Config.Commands and Config.Commands.ClearBounty) or "!clearbounty"
    local args = message:match("^%S+%s+(.*)")
    if not args then
        self.Utils:SendClientHUDMessage(adminController, "Usage: " .. commandName .. " \"<username>\" [cash,gold,fame]")
        return
    end

    local targetName, currencyStr = args:match('^"([^"]+)"%s*(.*)')
    if not targetName then
        targetName, currencyStr = args:match('^(%S+)%s*(.*)')
    end

    if not targetName then
        self.Utils:SendClientHUDMessage(adminController, "Usage: " .. commandName .. " \"<username>\" [cash,gold,fame]")
        return
    end

    local targetController = self.Utils:GetControllerByName(targetName)
    if not targetController or not targetController:IsValid() then
        self.Utils:SendClientHUDMessage(adminController,
            self:GetMessage("HudPlayerNotFound", { targetName = targetName }))
        return
    end

    local targetUserId = targetController:GetUserId():ToString()
    local officialTargetName = targetController:GetUserName2():ToString()

    local bounty = self.Data.ActiveBounties[targetUserId]
    if not bounty then
        self.Utils:SendClientHUDMessage(adminController, "This player does not have an active bounty.")
        return
    end

    local adminName = adminController:GetUserName2():ToString()
    local adminId = adminController:GetUserId():ToString()

    currencyStr = currencyStr or ""

    if currencyStr:match("^%s*$") then
        local clearedAmountStr = self:FormatBountyString(bounty.Rewards)
        self.Data.ActiveBounties[targetUserId] = nil

        self:Printf("(Admin) %s (%s) cleared the entire bounty (%s) for player %s (%s).",
            adminName, adminId, clearedAmountStr, officialTargetName, targetUserId)

        self.Utils:SendClientHUDMessage(adminController,
            self:GetMessage("HudClearEntireBounty", { targetName = targetName }))
    else
        local currenciesToClear = {}
        for currency in currencyStr:gmatch("([^,]+)") do
            local cleanCurrency = currency:gsub("^%s*(.-)%s*$", "%1"):lower()
            if cleanCurrency ~= "" then
                table.insert(currenciesToClear, cleanCurrency)
            end
        end

        if #currenciesToClear == 0 then
            self.Utils:SendClientHUDMessage(adminController, self:GetMessage("HudClearBountyErrorCurrencies"))
            return
        end

        local clearedCurrenciesList = {}
        for _, currency in ipairs(currenciesToClear) do
            if bounty.Rewards[currency] and bounty.Rewards[currency] > 0 then
                bounty.Rewards[currency] = 0
                for _, placerData in pairs(bounty.Placers) do
                    if placerData.Contributions[currency] then
                        placerData.Contributions[currency] = 0
                    end
                end
                table.insert(clearedCurrenciesList, currency)
            end
        end

        if #clearedCurrenciesList == 0 then
            self.Utils:SendClientHUDMessage(adminController, self:GetMessage("HudClearBountyErrorSpecified"))
            return
        end

        local remainingValue = (bounty.Rewards.cash or 0) + (bounty.Rewards.gold or 0) + (bounty.Rewards.fame or 0)

        local clearedListStr = table.concat(clearedCurrenciesList, ", ")
        self:Printf("(Admin) %s (%s) cleared the %s bounty portion for player %s (%s).",
            adminName, adminId, clearedListStr, officialTargetName, targetUserId)
        self.Utils:SendClientHUDMessage(adminController,
            self:GetMessage("HudClearBounty", { clearedCurrencyList = clearedListStr, targetName = targetName }))

        if remainingValue <= 0 then
            self.Data.ActiveBounties[targetUserId] = nil
            self:Printf("(Admin) Bounty for %s (%s) was fully cleared and removed.", officialTargetName, targetUserId)
        end
    end

    self:SaveData()
end

function BountyAddon:FormatBountyString(rewards)
    local parts = {}
    if rewards.cash and rewards.cash > 0 then
        table.insert(parts,
            string.format("$%s", self.Utils:FormatNumber(rewards.cash)))
    end
    if rewards.gold and rewards.gold > 0 then
        table.insert(parts,
            string.format("%s Gold", self.Utils:FormatNumber(rewards.gold)))
    end
    if rewards.fame and rewards.fame > 0 then
        table.insert(parts,
            string.format("%s FP", self.Utils:FormatNumber(rewards.fame)))
    end
    local count = #parts
    if count == 0 then
        return "No Reward"
    elseif count == 1 then
        return parts[1]
    elseif count == 2 then
        return table.concat(parts, " and ")
    else
        local lastItem = table.remove(parts)
        return table.concat(parts, ", ") .. ", and " .. lastItem
    end
end

function BountyAddon:HandleKillEvent(Target, killer)
    if Target.Value == killer.Value then return end
    local victimController = self.Utils:GetControllerByUserId(Target.Value)
    if not victimController then return end
    local victimUserId = victimController:GetUserId():ToString()
    local bounty = self.Data.ActiveBounties[victimUserId]
    if not bounty then return end
    local killerController = self.Utils:GetControllerByUserId(killer.Value)
    if not killerController then return end
    local killerCharacter = killerController:GetPrisoner()
    local victimCharacter = victimController:GetPrisoner()
    if not killerCharacter or not victimCharacter then return end
    if victimCharacter:IsMemberOfMySquad(killerCharacter) then return end

    local killerName = killerController:GetUserName2():ToString()
    local totalBountyStr = self:FormatBountyString(bounty.Rewards)

    self:Announce(self:GetMessage("BountyClaimed",
        { killerName = killerName, targetName = bounty.TargetName, bounty = totalBountyStr }))
    self:Printf("Bounty CLAIMED by %s (%s) on %s (%s) for %s.", killerName,
        killerController:GetUserId():ToString(), bounty.TargetName, victimUserId, totalBountyStr)

    if bounty.Rewards.cash > 0 then
        killerController:SetCurrencyBalanceRep(1,
            killerController._moneyBalanceRep + bounty.Rewards.cash)
    end
    if bounty.Rewards.gold > 0 then
        killerController:SetCurrencyBalanceRep(2,
            killerController._goldBalanceRep + bounty.Rewards.gold)
    end
    if bounty.Rewards.fame > 0 then
        killerController:SetFamePoints(killerController:GetFamePoints() + bounty.Rewards
            .fame)
    end

    self.Data.ActiveBounties[victimUserId] = nil
    self:SaveData()
end

function BountyAddon:HandlePlayerConnect(controller)
    if not controller:IsValid() then return end
    local userId = controller:GetUserId():ToString()
    local userName = controller:GetUserName2():ToString()
    local dataWasChanged = false
    local pending = self.Data.PendingRefunds[userId]

    if pending and #pending > 0 then
        for _, refundInfo in ipairs(pending) do
            local contributions = refundInfo.amount
            if contributions.cash > 0 then
                controller:SetCurrencyBalanceRep(1,
                    controller._moneyBalanceRep + contributions.cash)
            end
            if contributions.gold > 0 then
                controller:SetCurrencyBalanceRep(2,
                    controller._goldBalanceRep + contributions.gold)
            end
            if contributions.fame > 0 then controller:SetFamePoints(controller:GetFamePoints() + contributions.fame) end
            local refundString = self:FormatBountyString(contributions)
            self.Utils:SendClientHUDMessage(controller,
                self:GetMessage("BountyRefundedOffline", { refund = refundString, targetName = refundInfo.targetName }))
            self:Printf("REFUND (Offline): Gave refund of %s to %s (%s) for bounty on %s.", refundString,
                userName, userId, refundInfo.targetName)
        end
        self.Data.PendingRefunds[userId] = nil
        dataWasChanged = true
    end

    for targetId, bounty in pairs(self.Data.ActiveBounties) do
        if targetId == userId then
            if Config.General.Announcements and Config.General.Announcements.AnnounceTargetConnected then
                self:Announce(self:GetMessage("TargetConnected",
                    { targetName = userName, bounty = self:FormatBountyString(bounty.Rewards) }))
            end

            if bounty.TargetName ~= userName then
                bounty.TargetName = userName
                self:Printf("Updated bounty target name for %s.", userName)
                dataWasChanged = true
            end
        end

        if bounty.Placers and bounty.Placers[userId] and bounty.Placers[userId].PlacerName ~= userName then
            bounty.Placers[userId].PlacerName = userName
            self:Printf("Updated bounty placer name for %s.", userName)
            dataWasChanged = true
        end
    end

    if dataWasChanged then self:SaveData() end
end

function BountyAddon:HandlePlayerDisconnect(controller)
    if not controller:IsValid() then return end
    local userId = controller:GetUserId():ToString()
    local bounty = self.Data.ActiveBounties[userId]
    if not bounty then return end

    if Config.General.Announcements and Config.General.Announcements.AnnounceTargetDisconnected then
        local totalBountyStr = self:FormatBountyString(bounty.Rewards)
        self:Announce(self:GetMessage("TargetDisconnected", { targetName = bounty.TargetName, bounty = totalBountyStr }))
    end

    if not Config.Lifetime.RefundBountyOnDisconnect then return end

    for placerUserId, placerData in pairs(bounty.Placers) do
        local placerController = self.Utils:GetControllerByUserSteamId(placerUserId)
        if not placerController or not placerController:IsValid() then
            self.Data.PendingRefunds[placerUserId] = self.Data.PendingRefunds[placerUserId] or {}
            table.insert(self.Data.PendingRefunds[placerUserId],
                { amount = placerData.Contributions, targetName = bounty.TargetName })
            self:Printf("REFUND (Queued): Gave refund of %s for %s (%s) due to %s disconnecting.",
                self:FormatBountyString(placerData.Contributions), placerData.PlacerName, placerUserId, bounty
                .TargetName)
            goto continue
        end
        if placerData.Contributions.cash > 0 then
            placerController:SetCurrencyBalanceRep(1,
                placerController._moneyBalanceRep + placerData.Contributions.cash)
        end
        if placerData.Contributions.gold > 0 then
            placerController:SetCurrencyBalanceRep(2,
                placerController._goldBalanceRep + placerData.Contributions.gold)
        end
        if placerData.Contributions.fame > 0 then
            placerController:SetFamePoints(placerController:GetFamePoints() +
                placerData.Contributions.fame)
        end

        local refundString = self:FormatBountyString(placerData.Contributions)
        self:Printf("REFUND: Gave refund of %s to %s (%s) due to %s disconnecting.", refundString,
            placerController:GetUserName2():ToString(), placerUserId, bounty.TargetName)
        self.Utils:SendClientHUDMessage(placerController,
            self:GetMessage("BountyRefundedDisconnect", { refund = refundString, targetName = bounty.TargetName }))
        ::continue::
    end

    self.Data.ActiveBounties[userId] = nil
    self:SaveData()
end

function BountyAddon:CheckExpiredBounties()
    local currentTime = os.time()
    local lifetimeInSeconds = Config.Lifetime.BountyLifetimeHours * 3600
    local expiredBountyKeys = {}

    for userId, bounty in pairs(self.Data.ActiveBounties) do
        if bounty.CreationTimestamp and (currentTime - bounty.CreationTimestamp > lifetimeInSeconds) then
            table.insert(expiredBountyKeys, userId)
        end
    end

    if #expiredBountyKeys == 0 then return end

    ExecuteInGameThread(function()
        local dataWasChanged = false
        for _, userId in ipairs(expiredBountyKeys) do
            local bounty = self.Data.ActiveBounties[userId]
            if not bounty then goto continue end
            dataWasChanged = true
            local totalBountyStr = self:FormatBountyString(bounty.Rewards)
            self:Printf("Bounty EXPIRED on %s (%s). Total was: %s.", bounty.TargetName, userId, totalBountyStr)
            local targetController = self.Utils:GetControllerByUserSteamId(userId)
            local canReward = Config.Lifetime.RewardTargetOnExpire and targetController and targetController:IsValid()

            if canReward then
                if bounty.Rewards.cash > 0 then
                    targetController:SetCurrencyBalanceRep(1,
                        targetController._moneyBalanceRep + bounty.Rewards.cash)
                end
                if bounty.Rewards.gold > 0 then
                    targetController:SetCurrencyBalanceRep(2,
                        targetController._goldBalanceRep + bounty.Rewards.gold)
                end
                if bounty.Rewards.fame > 0 then
                    targetController:SetFamePoints(targetController:GetFamePoints() +
                        bounty.Rewards.fame)
                end
                self:Announce(self:GetMessage("BountyExpiredWithReward",
                    { targetName = bounty.TargetName, bounty = totalBountyStr }))
                self:Printf("REWARD: Gave reward of %s to %s (%s) for surviving an expired bounty.",
                    totalBountyStr, bounty.TargetName, userId)
            else
                self:Announce(self:GetMessage("BountyExpired",
                    { targetName = bounty.TargetName, bounty = totalBountyStr }))
                if Config.Lifetime.RewardTargetOnExpire then
                    self:Printf(
                        "REWARD FORFEITED: Reward for %s (%s) was forfeited because the player was offline when the bounty expired.",
                        bounty.TargetName, userId)
                end
            end
            self.Data.ActiveBounties[userId] = nil
            ::continue::
        end
        if dataWasChanged then self:SaveData() end
    end)
end

function BountyAddon:StartSaveTimer()
    local saveIntervalMinutes = Config.System.SaveIntervalMinutes
    if not saveIntervalMinutes or saveIntervalMinutes <= 0 then
        self:Printf(false, "Periodic saving is disabled.")
        return
    end

    local saveIntervalSeconds = saveIntervalMinutes * 60
    local saveIntervalMs = math.floor(saveIntervalSeconds * 1000)

    self:Printf(false, "Starting auto-save timer. Bounty data will be saved every %s.",
        self.Utils:FormatTime(saveIntervalSeconds))

    LoopAsync(saveIntervalMs, function()
        self:Printf(false, "Auto-saving bounty data...")
        self:SaveData()
        return false
    end)
end

function BountyAddon:StartBountyExpirationTimer()
    if not Config.Lifetime.ExpireBounty then return end
    local checkIntervalMinutes = Config.Lifetime.BountyCheckIntervalMinutes or 1
    if checkIntervalMinutes <= 0 then checkIntervalMinutes = 1 end
    local checkIntervalSeconds = checkIntervalMinutes * 60
    local checkIntervalMs = math.floor(checkIntervalSeconds * 1000)
    self:Printf(false, "Starting bounty expiration checker. Bounties will be checked every %s.",
        self.Utils:FormatTime(checkIntervalSeconds))

    LoopAsync(checkIntervalMs, function()
        self:CheckExpiredBounties()
        return false
    end)
end

function BountyAddon:StartLocationUpdateTimer()
    if not Config.LocationTracking or not Config.LocationTracking.Enabled then return end

    local updateIntervalMinutes = Config.LocationTracking.UpdateIntervalMinutes or 5
    if updateIntervalMinutes <= 0 then updateIntervalMinutes = 5 end

    local updateIntervalSeconds = updateIntervalMinutes * 60

    local updateIntervalMs = math.floor(updateIntervalSeconds * 1000)

    self:Printf(false, "Starting bounty location tracker. Locations will be updated every %s.",
        self.Utils:FormatTime(updateIntervalSeconds))

    LoopAsync(updateIntervalMs, function()
        self:Printf(false, "Updating location")
        self:UpdateBountyLocations()
        return false
    end)
end

function BountyAddon:UpdateBountyLocations()
    if not (self.Data and self.Data.ActiveBounties) then return end
    local dataWasChanged = false

    ExecuteInGameThread(function()
        for userId, bounty in pairs(self.Data.ActiveBounties) do
            local targetController = self.Utils:GetControllerByUserSteamId(userId)
            if targetController and targetController:IsValid() then
                local sector, keypad = self.Utils:GetPlayerSector(targetController)
                if sector then
                    local isFirstUpdate = not bounty.LastSeen

                    bounty.LastSeen = bounty.LastSeen or {}
                    bounty.LastSeen.Sector = sector
                    bounty.LastSeen.Keypad = keypad
                    bounty.LastSeen.Timestamp = os.time()

                    dataWasChanged = true

                    if isFirstUpdate then
                        local updateIntervalMinutes = Config.LocationTracking.UpdateIntervalMinutes or 5
                        local updateIntervalSeconds = updateIntervalMinutes * 60
                        local formattedInterval = self.Utils:FormatTime(updateIntervalSeconds)

                        self:Announce(self:GetMessage("AnnounceLocationExposed",
                            { targetName = bounty.TargetName, updateInterval = formattedInterval }))

                        self:Printf(false, "Sent location exposed warning for target: %s", bounty.TargetName)
                    end
                end
            end
        end
        if dataWasChanged then
            self:SaveData()
        end
    end)
end

function BountyAddon:GetBountyDataForAPI()
    local bounties = {}
    local sql = [[
        SELECT
            target_user_id,
            target_name,
            reward_cash,
            reward_gold,
            reward_fame,
            last_seen_sector,
            last_seen_keypad
        FROM bounties
        ORDER BY (reward_cash + reward_gold + reward_fame) DESC
    ]]

    local success, err = pcall(function()
        for row in self.DB:nrows(sql) do
            local bountyData = {
                targetUserId = row.target_user_id,
                targetName = row.target_name,
                rewards = {
                    cash = row.reward_cash,
                    gold = row.reward_gold,
                    fame = row.reward_fame
                }
            }

            if Config.LocationTracking and Config.LocationTracking.Enabled then
                if Config.LocationTracking.ShowSector and row.last_seen_sector then
                    bountyData.lastSeenSector = row.last_seen_sector
                end

                if Config.LocationTracking.ShowKeypad and row.last_seen_keypad then
                    bountyData.lastSeenKeypad = row.last_seen_keypad
                end
            end
            table.insert(bounties, bountyData)
        end
    end)

    if not success then
        self:Printf(true, "Error fetching bounty data for API: %s", tostring(err))
        return nil
    end

    return bounties
end

if Config.AddonEnabled then
    OmniSCUM:RegisterAddon(BountyAddon)
end
