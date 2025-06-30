Config = Config or {}
Config.DiscordLogger = {}

Config.DiscordLogger = {

    -- Enable/Disable the Discord Logger addon
    AddonEnabled = true,

    -- This is the master webhook URL. If a specific log type below doesn't have a URL,
    -- it will use this one. You can leave this blank if you want to use separate webhooks for everything.
    MasterWebhook =
    "https://discord.com/api/webhooks/1388649468840251423/I5_pNseWNTyrKehOXY34tPjZ9UfuyHe6ynOL4ywwkoSdn_kSgW866E7jEnGTTaNkkfdU",

    Appearance = {
        Username = "OmniSCUM Log",
        AvatarURL = nil
    },

    -- Chat logging.
    Chat = {
        Enabled = true,
        Webhook =
        "https://discord.com/api/webhooks/1388801073631985664/fLI0qtRvqjglMH_D1KwpuoR8K8m0EjpUwv_BriCRAP4z1R98PUiT5aohAQt8YE3REukC", -- If "Webhook" is empty, it will use MasterWebhook

        -- Available: "Default", "Local", "Global", "Squad", "Admin", "Commands", "Server", "Error"
        Channels = {
            "Global",
            "Local"
        },
        DisplayMessageTime = true,
        DisplayChannelName = true,
        DisplayUsername = true,
        DisplaySteamID = true,
    },

    -- Connection logging (Connect/Disconnect).
    Connections = {
        Enabled = true,
        Webhook = "https://discord.com/api/webhooks/1389006282358526074/j8Jl4RNfn22tiOHQHiAl0s-liVaTultO-9AaBPSrZC7z7DxqLZea2RetSkj774xcNtrW" -- If "Webhook" is empty, it will use MasterWebhook.
    },

     -- Kills/Deaths logging.
    Kills = {
        Enabled = true,
        Webhook = "https://discord.com/api/webhooks/1389226480638099526/g9vH902LNyH2T2GYwpVKBq-lKLMxSaSEDPVxmYwwH-clN9h4vsCbfDGJd7lQwEhlDo6C"
    },

    -- Admin command logging.
    Admin = {
        Enabled = true,
        Webhook = "https://discord.com/api/webhooks/1389248344873898094/mHJ_k9pKRqKF7VPGEstnJCZJWVlARS9KuDFRFjpcUjAvzgyhVjHExXWo5LLwrWamMzgu" -- If "Webhook" is empty, it will use MasterWebhook.
    },

    Interactions = {
        Webhook = "https://discord.com/api/webhooks/1389257040500625538/zxNg-HYaPc2rEnMx3sn6WOs_CnCrVaeWpnK0snsuq5UbehCUBox2qLABMunLrQjFCt6m",
        -- Lockpicking logging.
        Lockpicking = {
            Enabled = true,
        }
    }
}

return Config
