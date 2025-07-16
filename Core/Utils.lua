local UEHelpers = require("UEHelpers")
local JSON = require("json")
local sqlite3 = require("lsqlite3complete")

OmniSCUM.Utils = OmniSCUM.Utils or {}

function OmniSCUM.Utils:LogPrintf(logFilePath, prefix, ...)
    local args = {...}
    local shouldLogToFile = true
    
    if type(args[1]) == "boolean" then
        shouldLogToFile = table.remove(args, 1)
    end
    
    local message
    if #args == 0 then
        message = ""
    else
        local success, result = pcall(string.format, table.unpack(args))
        if success then
            message = result
        else
            local messageParts = {}
            for i = 1, #args do
                table.insert(messageParts, tostring(args[i]))
            end
            message = table.concat(messageParts, " ")
        end
    end
    
    print(string.format("[%s] %s", prefix, message))
    
    if shouldLogToFile and logFilePath then
        local file, err = io.open(logFilePath, "a")
        if file then
            local timestamp = os.date("[%Y-%m-%d %H:%M:%S]")
            file:write(timestamp .. " " .. string.format("[%s] ", prefix) .. message .. "\n")
            file:close()
        end
    end
end

function OmniSCUM.Utils:CreateDirectory(path)
    local file = io.open(path .. "check.tmp", "w")
    if not file then
        os.execute('mkdir "' .. path .. '"')
        return
    end
    file:close()
    os.remove(path .. "check.tmp")
end

function OmniSCUM.Utils:GetRootSaveDirectory()
    local KismetSystemLibrary = UEHelpers:GetKismetSystemLibrary()
    local savedDir = ""

    if KismetSystemLibrary and KismetSystemLibrary:IsValid() then
        savedDir = KismetSystemLibrary:GetProjectSavedDirectory():ToString()
    else
        print("[OmniSCUM::Utils] WARNING: KismetSystemLibrary not valid, can't determine saved directory.")
        return ""
    end
    
    return savedDir
end

function OmniSCUM.Utils:GetDatabaseConnection(dbPath, printFunc)
    local db, err = sqlite3.open(dbPath)
    if not db then
        if printFunc then printFunc(false, "FATAL: Could not open database: %s", tostring(err)) end
        return nil
    end

    db:busy_timeout(5000)

    local ok, exec_err = pcall(function() db:exec("PRAGMA foreign_keys = ON;") end)
    if not ok then
        if printFunc then printFunc(false, "WARNING: Could not enable foreign keys: %s", tostring(exec_err)) end
    end
    
    if printFunc then printFunc(false, "Database connection successful: %s", dbPath) end
    return db
end

function OmniSCUM.Utils:SaveJSON(filePath, data, printFunc)
    local file, err = io.open(filePath, "w")
    if not file then
        if printFunc then printFunc(false, "ERROR: Failed to write to data file: %s", tostring(err)) end
        return false
    end

    local success, jsonString = pcall(JSON.encode, data)
    if not success then
        if printFunc then printFunc(false, "ERROR: Failed to encode data: %s", tostring(jsonString)) end
        file:close()
        return false
    end

    file:write(jsonString)
    file:close()
    return true
end

function OmniSCUM.Utils:LoadJSON(filePath, printFunc)
    local file = io.open(filePath, "r")
    if not file then
        return nil
    end

    local content = file:read("*a")
    file:close()

    if not content or content == "" then
        return {}
    end

    local success, data = pcall(JSON.decode, content)
    if not success or type(data) ~= "table" then
        if printFunc then printFunc(false, "ERROR: Failed to decode data file: %s", tostring(data)) end
        return nil
    end
    return data
end

function OmniSCUM.Utils:GetMessage(messagesTable, key, replacements, printFunc)
    if not messagesTable or not messagesTable[key] then
        if printFunc then printFunc(false, "WARNING: Missing message key in config: %s", key) end
        return "MISSING_MESSAGE: " .. key
    end

    local message = messagesTable[key]

    if replacements then
        for placeholder, value in pairs(replacements) do
            message = message:gsub("{" .. tostring(placeholder) .. "}", tostring(value))
        end
    end
    return message
end


function OmniSCUM.Utils:GetControllerByName(name)
    local allPlayerPawns = UEHelpers.GetAllPlayers()
    if not allPlayerPawns then return nil end
    local lowerName = string.lower(name)
    for _, currentPawn in ipairs(allPlayerPawns) do
        if not currentPawn:IsValid() or not currentPawn:IsA("/Script/ConZ.Prisoner") then goto continue end
        local controller = currentPawn:GetController()
        if controller:IsValid() and string.lower(controller:GetUserName2():ToString()) == lowerName then
            return controller
        end
        ::continue::
    end
    return nil
end

function OmniSCUM.Utils:GetControllerByUserSteamId(userId)
    local allPlayerPawns = UEHelpers.GetAllPlayers()
    if not allPlayerPawns then return nil end
    for _, currentPawn in ipairs(allPlayerPawns) do
        if not currentPawn:IsValid() or not currentPawn:IsA("/Script/ConZ.Prisoner") then goto continue end
        local controller = currentPawn:GetController()
        if controller:IsValid() and controller:GetUserId():ToString() == userId then
            return controller
        end
        ::continue::
    end
    return nil
end

function OmniSCUM.Utils:GetControllerByUserId(userId)
    local allPlayerPawns = UEHelpers.GetAllPlayers()
    if not allPlayerPawns then return nil end
    for _, currentPawn in ipairs(allPlayerPawns) do
        if not currentPawn:IsValid() or not currentPawn:IsA("/Script/ConZ.Prisoner") then goto continue end
        local controller = currentPawn:GetController()
        if controller:IsValid() and controller:GetUserProfileId().Value == userId then
            return controller
        end
        ::continue::
    end
    return nil
end

function OmniSCUM.Utils:Announce(message, announcementType, prefix)
    prefix = prefix or ""
    announcementType = announcementType or "Chat" 

    if announcementType == "Announce" then
        local rpcAdminCommand = FindFirstOf("PlayerRpcChannel")
        if rpcAdminCommand and rpcAdminCommand:IsValid() then
            rpcAdminCommand:Chat_Server_ProcessAdminCommand(string.format("Announce %s%s", prefix, message))
        end
    elseif announcementType == "HUD" then
        local gameMode = UEHelpers:GetGameModeBase()
        if gameMode and gameMode:IsValid() then
            gameMode:SendHUDMessageToAll(prefix .. message, false)
        end
    elseif announcementType == "Chat" then
        local miscStatics = StaticFindObject("/Script/ConZ.Default__MiscStatics")
        if miscStatics and miscStatics:IsValid() then
            local worldContext = UEHelpers:GetWorldContextObject()
            if worldContext and worldContext:IsValid() then
                miscStatics:BroadcastChatLine(worldContext, prefix .. message, 6)
            end
        end
    end
end

function OmniSCUM.Utils:SendClientHUDMessage(controller, message)
    if not controller or not controller:IsValid() then return end
    controller:SendHUDMessageToClient(message, nil)
end

function OmniSCUM.Utils:GetPlayerSector(controller)
    if not (controller and controller:IsValid() and controller.Pawn and controller.Pawn:IsValid()) then
        return nil, nil
    end

    local worldSettings = UEHelpers:GetWorldSettings()
    if not worldSettings then return nil, nil end

    local worldBounds = worldSettings.WorldBounds
    if not worldBounds then return nil, nil end

    local worldMin = worldBounds.Min
    local worldMax = worldBounds.Max

    local map_size_x = worldMax.X - worldMin.X
    local map_size_y = worldMax.Y - worldMin.Y

    local NUM_SECTORS_PER_AXIS = 5
    local KEYPADS_PER_SECTOR_AXIS = 3
    local sector_size_x = map_size_x / NUM_SECTORS_PER_AXIS
    local sector_size_y = map_size_y / NUM_SECTORS_PER_AXIS
    local keypad_size_x = sector_size_x / KEYPADS_PER_SECTOR_AXIS
    local keypad_size_y = sector_size_y / KEYPADS_PER_SECTOR_AXIS

    local location = controller.Pawn:K2_GetActorLocation()
    
    local logical_x = worldMax.X - location.X
    local logical_y = location.Y - worldMin.Y
    
    local colIndex = math.floor(logical_x / sector_size_x)
    local rowIndex = math.floor(logical_y / sector_size_y)
    
    rowIndex = math.max(0, math.min(NUM_SECTORS_PER_AXIS - 1, rowIndex))
    colIndex = math.max(0, math.min(NUM_SECTORS_PER_AXIS - 1, colIndex))

    local rowLabels = { 'Z', 'A', 'B', 'C', 'D' }
    local sectorRow = rowLabels[rowIndex + 1]

    local colLabels = { '4', '3', '2', '1', '0' }
    local sectorCol = colLabels[colIndex + 1]

    local sector = sectorRow .. tostring(sectorCol)

    local x_in_sector = logical_x % sector_size_x
    local y_in_sector = logical_y % sector_size_y
    
    local keypadColIndex = math.floor(x_in_sector / keypad_size_x)
    local keypadRowIndex = math.floor(y_in_sector / keypad_size_y)

    local keypadNumber = (keypadRowIndex * KEYPADS_PER_SECTOR_AXIS) + keypadColIndex + 1
    local keypad = tostring(keypadNumber)

    return sector, keypad
end

function OmniSCUM.Utils:FormatNumber(n)
    if not n then return "0" end
    local s = tostring(math.floor(n))
    s = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return s:gsub("^,", "")
end

function OmniSCUM.Utils:FormatTime(totalSeconds)
    if totalSeconds <= 0 then return "0 seconds" end
    local hours = math.floor(totalSeconds / 3600)
    local minutes = math.floor((totalSeconds % 3600) / 60)
    local seconds = totalSeconds % 60
    local parts = {}
    if hours > 0 then table.insert(parts, string.format("%d %s", hours, hours == 1 and "hour" or "hours")) end
    if minutes > 0 then table.insert(parts, string.format("%d %s", minutes, minutes == 1 and "minute" or "minutes")) end
    if hours == 0 and seconds > 0 then
        table.insert(parts,
            string.format("%d %s", seconds, seconds == 1 and "second" or "seconds"))
    end
    local count = #parts
    if count == 0 then
        return "0 seconds"
    elseif count == 1 then
        return parts[1]
    elseif count == 2 then
        return table.concat(parts, " and ")
    else
        local lastItem = table.remove(parts)
        return table.concat(parts, ", ") .. ", and " .. lastItem
    end
end

function OmniSCUM.Utils:FormatTimeShort(totalSeconds)
    local hours = math.floor(totalSeconds / 3600)
    local minutes = math.floor((totalSeconds % 3600) / 60)
    return string.format("%d:%02d", hours, minutes)
end