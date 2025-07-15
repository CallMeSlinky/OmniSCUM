Config = Config or {}
Config.DiscordBot = {}

Config.DiscordBot = {
    HttpServer = {
        Enabled = true,
        Port = 8080,
        ApiKey = "sB8jdmLWIc6jDSQUk16SKRPk"
    },
    DiscordHTTPServer = {
        Url = "http://host.docker.internal:3000", 
        ApiKey = "sB8jdmLWIc6jDSQUk16SKRPk" 
    }
}

return Config
