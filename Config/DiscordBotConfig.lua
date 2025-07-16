Config = Config or {}
Config.DiscordBot = {}

Config.DiscordBot = {
    AddonEnabled = true,
    DiscordBotServer = {
        CommandPolling = true,
        CommandPollingIntervalSeconds = 5,
        DiscordServerStatusUpdateInterval = 60,
        Url = "http://localhost:3000", 
        ApiKey = "sB8jdmLWIc6jDSQUk16SKRPk" 
    },

    Chat = {
        Enabled = true,
        DisplayMessageTime = true,
        DisplayChannelName  = true,
        DisplayUsername = true,
        DisplaySteamID = true,
        -- Available: "Default", "Local", "Global", "Squad", "Admin", "Commands", "Server", "Error"
        Channels = {
            "Global",
            "Local"
        },
    },

    Connections = {
        Enabled = true
    },

    Kills = {
        Enabled = true
    },

    Admin = {
        Enabled = true
    },

    Interactions = {
        Lockpicking = {
            Enabled = true
        }
    }

}

return Config
