Config = Config or {}

Config.Bounty = {

    -- Enable/Disable the Bounty addon
    AddonEnabled = true,
    
    System = {
        -- How often (in minutes) to automatically save the bounty data to the disk.
        -- This prevents data loss in case of a server crash. Set to 0 to disable.
        SaveIntervalMinutes = 3
    },

    -- General gameplay and feature settings.
    General = {

        -- If true, bounties on offline players will be visible in the !bounties list.
        ShowOfflineBounties = false,

        -- If true, players can place a bounty on themselves.
        AllowSelfBounty = true,

        -- Settings for announcements.
        Announcements = {
            -- How bounty messages are displayed to all players.
            -- "Announce": Uses the big, centered server announcement text.
            -- "HUD":      Uses a simple HUD element.
            -- "Chat":     Uses the chat.
            AnnouncementType = "Chat",

            AnnouncementPrefix = "[Bounty]",

            -- If true, an announcement is made when a player with a bounty connects to the server.
            AnnounceTargetConnected = true,

            -- If true, an announcement is made when a player with a bounty disconnects from the server.
            AnnounceTargetDisconnected = true
        },

        Whitelist = {
            -- If true, only players whose Steam IDs are in the list below can place bounties.
            Enabled = false,

            -- A list of Steam64 IDs (as strings) that are allowed to place bounties.
            -- Example: WhitelistedSteamIDs = { "76561198000000001", "76561198000000002" }
            WhitelistedSteamIDs = {}
        }
    },

    -- Configure the chat commands used for the bounty system.
    Commands = {
        -- The chat command used to place or update a bounty on a player.
        PlaceBounty = "!bounty",

        -- The chat command used to view the list of all active bounties.
        ViewBounties = "!bounties",

        -- The chat command used to clear a bounty (Admin only)
        ClearBounty = "!clearbounty"
    },

    -- Settings related to currency types and bounty amounts.
    Amount = {
        -- A list of currencies that are allowed for bounties.
        -- Valid options are "cash", "gold", "fame". Remove any you don't want to allow.
        AcceptedCurrencies = { "cash", "gold", "fame" },

        -- The minimum amount a player must place in a single contribution.
        MinimumBounty = {
            cash = 100,
            fame = 5,
            gold = 1,
        },

        -- The maximum amount a player can place in a single contribution.
        MaximumBounty = {
            cash = 10000,
            fame = 500,
            gold = 100,
        },

        -- The total maximum bounty allowed on a single target across all placers.
        -- Set to 0 or a negative number for no limit.
        TotalMaximumBounty = {
            cash = 10000,
            fame = 500,
            gold = 100
        }
    },

    -- Settings related to the duration and expiration of bounties.
    Lifetime = {
        -- If true, when a target with a bounty disconnects, the bounty is cancelled and all placers are refunded.
        RefundBountyOnDisconnect = false,

        -- If true, bounties will expire after a set duration.
        ExpireBounty = true,

        -- How often (in minutes) to check for expired bounties.
        BountyCheckIntervalMinutes = 1,

        -- The total lifetime of a bounty, in hours, before it expires.
        BountyLifetimeHours = 3,

        -- If a bounty expires (isn't claimed), should the target receive the reward for surviving?
        -- The target must be online when the bounty expires to receive the reward.
        RewardTargetOnExpire = true
    },

    -- Settings to prevent players from spamming bounties. Admins bypass rate limiting.
    RateLimiting = {
        -- If true, limits the number of separate bounties a player can place.
        EnableMaxActiveBounties = true,
        MaxActiveBounties = 3,

        -- If true, players must wait a certain amount of time between placing bounties.
        EnableCooldowns = true,

        -- Cooldown in seconds when placing a bounty on a NEW target.
        NewBountyCooldownSeconds = 300, -- 5 minutes

        -- Cooldown in seconds when adding to an EXISTING bounty on the SAME target.
        SameTargetCooldownSeconds = 30
    },

    -- Settings for tracking a bounty target's last known location. This is WIP, I don't see a function in game so it's a bit hacky. But I think it's accurate enough?
    LocationTracking = {
        -- If true, the server will periodically update and store the last known sector of players with active bounties.
        Enabled = true,

        -- How often (in minutes) to update the location of a bounty target.
        UpdateIntervalMinutes = 5,

        -- If true, the sector (e.g., D2) will be shown in the !bounties list.
        ShowSector = true,

        -- If true, the keypad (e.g., K2) will be shown in the !bounties list. This gives a more precise location which can be viewed on maps like https://scum-map.com
        ShowKeypad = true
    },

    -- Configure all user messages.
    Messages = {

        -- Global announcements
        BountyPlaced                  = "{placerName} has placed a {bounty} bounty on {targetName}!",
        BountyPlacedOnSelf            = "{placerName} has placed a {bounty} bounty on themselves!",
        BountyUpdated                 = "{placerName} has updated the bounty on {targetName}! Total is now: {bounty}",
        BountyUpdatedOnSelf           = "{placerName} has updated their own bounty! Total is now: {bounty}",
        BountyClaimed                 = "{killerName} has claimed the bounty on {targetName} for: {bounty}!",
        BountyExpired                 = "The bounty on {targetName} has expired. The total was: {bounty}",
        BountyExpiredWithReward       = "The bounty on {targetName} has expired. They have been rewarded: {bounty}",
        TargetConnected               = "Heads up! {targetName}, who has a bounty of {bounty}, has just connected!",
        TargetDisconnected            = "{targetName}, who had a bounty of {bounty}, has disconnected!",
        AnnounceLocationExposed       =
        "{targetName}'s position has been exposed! Their last position will update every {updateInterval}. Happy hunting!",

        -- HUD messages (sent to specific players)
        HudUsage                      = "Usage: {command} <Name> <Amount> <Currency ({currencies})>",
        HudInvalidCurrency            = "Invalid currency. Use: {currencies}",
        HudPlayerNotFound             = "Player '{targetName}' not found or is offline.",
        HudCannotBountySelf           = "You cannot place a bounty on yourself.",
        HudMaxBounties                = "You have reached the maximum of {maxBounties} active bounties.",
        HudNewBountyCooldown          = "You must wait {time} more before placing a new bounty.",
        HudSameTargetCooldown         = "You must wait {time} more before updating the bounty on this target.",
        HudMinAmount                  = "Bounty for {currency} must be at least {amount}.",
        HudMaxAmount                  = "Bounty for {currency} cannot exceed {amount}.",
        HudTotalMaxExceeded           = "This would exceed the total maximum bounty of {amount} {currency} for this target.",
        HudNotEnoughCash              = "You don't have enough cash.",
        HudNotEnoughFame              = "You don't have enough fame points.",
        HudNotEnoughGold              = "You don't have enough gold.",
        HudNotAuthorized              = "You are not authorized to place bounties.",
        HudClearEntireBounty          = "Successfully cleared the entire bounty for {targetName}.",
        HudClearBounty                = "Successfully cleared {clearedCurrencyList} from the bounty for {targetName}.",
        HudClearBountyErrorCurrencies =
        "No valid currencies specified to clear. Use comma-separated cash, gold, or fame.",
        HudClearBountyErrorSpecified  = "None of the specified currencies had a value on this bounty.",
        BountyRefundedDisconnect      = "Your bounty of {refund} on {targetName} was refunded as they disconnected.",
        BountyRefundedOffline         = "Your bounty of {refund} on {targetName} was refunded while you were offline.",

        -- !bounties command messages
        ViewBountiesHeader            = "----- ACTIVE BOUNTIES -----",
        ViewBountiesLocation          = " (Last seen: {sector} K{keypad}, {timeAgo})",
        ViewBountiesTimeAgoRecent     = "less than a minute ago",
        ViewBountiesTimeAgoSingular   = "1 minute ago",
        ViewBountiesTimeAgoPlural     = "{minutes} minutes ago",
        ViewBountiesLine              = "- {targetName} {status}: {bounty}{expireTime}{location}",
        ViewBountiesNone              = "There are no active bounties.",
        ViewBountiesStatusOnline      = "(Online)",
        ViewBountiesStatusOffline     = "(Offline)",
        ViewBountiesExpireTime        = " (Expires in {time})"
    }
}

return Config
