-- Shared Tarkov player data service.
-- Kept in each addon so the settings UI and coop extraction faction checks
-- work when either Tarkov addon is installed by itself.

util.AddNetworkString("TarkovDeploy_PlayerData")
util.AddNetworkString("TarkovDeploy_UpdatePlayerData")
util.AddNetworkString("TarkovDeploy_RequestPlayerList")
util.AddNetworkString("TarkovDeploy_RequestMyData")

local PLAYER_DATA_FILE = "tarkov_deploy_players.txt"
local PlayerData = {}
local VALID_FACTIONS = {
    USEC = true,
    BEAR = true,
    Scav = true,
}

local VALID_EDITIONS = {
    ["Standard"] = true,
    ["Edge of Darkness"] = true,
    ["The Unheard"] = true,
}

local function DefaultPlayerData(ply)
    return {
        name = IsValid(ply) and ply:Nick() or "Unknown",
        faction = "USEC",
        level = math.random(1, 70),
        time = math.random(1, 9999),
        edition = "Standard",
        battle = math.random(1, 100),
    }
end

local function LoadPlayerData()
    if not file.Exists(PLAYER_DATA_FILE, "DATA") then return end

    local data = file.Read(PLAYER_DATA_FILE, "DATA")
    local tbl = data and util.JSONToTable(data)
    if tbl then
        PlayerData = tbl
    end
end

local function SavePlayerData()
    file.Write(PLAYER_DATA_FILE, util.TableToJSON(PlayerData, true))
end

local function SyncPlayerFactionNW(ply, sid)
    if not IsValid(ply) or not PlayerData[sid] then return end
    ply:SetNWString("TarkovFaction", PlayerData[sid].faction or "USEC")
end

local function EnsurePlayerData(ply)
    if not IsValid(ply) then return nil end

    local sid = ply:SteamID()
    if not PlayerData[sid] then
        PlayerData[sid] = DefaultPlayerData(ply)
    else
        PlayerData[sid].name = ply:Nick()
        PlayerData[sid].faction = VALID_FACTIONS[PlayerData[sid].faction] and PlayerData[sid].faction or "USEC"
        PlayerData[sid].level = tonumber(PlayerData[sid].level) or 1
        PlayerData[sid].time = tonumber(PlayerData[sid].time) or 1
        PlayerData[sid].battle = tonumber(PlayerData[sid].battle) or 1
        PlayerData[sid].edition = VALID_EDITIONS[PlayerData[sid].edition] and PlayerData[sid].edition or "Standard"
    end

    SyncPlayerFactionNW(ply, sid)
    return sid
end

local function SendPlayerData(ply, sid)
    if not IsValid(ply) or not PlayerData[sid] then return end

    net.Start("TarkovDeploy_PlayerData")
    net.WriteString(util.TableToJSON(PlayerData[sid]))
    net.Send(ply)
end

local function SaveAndSync(ply, sid)
    SavePlayerData()
    SyncPlayerFactionNW(ply, sid)
    SendPlayerData(ply, sid)
end

LoadPlayerData()

hook.Add("PlayerInitialSpawn", "TarkovDeploy_RecordPlayer", function(ply)
    timer.Simple(1, function()
        if not IsValid(ply) then return end

        local sid = EnsurePlayerData(ply)
        if not sid then return end

        SavePlayerData()
        SendPlayerData(ply, sid)
    end)
end)

hook.Add("Initialize", "TarkovDeploy_InitHost", function()
    timer.Simple(5, function()
        for _, ply in ipairs(player.GetAll()) do
            local sid = EnsurePlayerData(ply)
            if sid then
                SavePlayerData()
                SendPlayerData(ply, sid)
            end
        end
    end)
end)

net.Receive("TarkovDeploy_RequestPlayerList", function(len, ply)
    if not IsValid(ply) or not ply:IsSuperAdmin() then return end

    for _, target in ipairs(player.GetAll()) do
        EnsurePlayerData(target)
    end
    SavePlayerData()

    net.Start("TarkovDeploy_RequestPlayerList")
    net.WriteString(util.TableToJSON(PlayerData))
    net.Send(ply)
end)

net.Receive("TarkovDeploy_UpdatePlayerData", function(len, ply)
    if not IsValid(ply) then return end
    if not ply:IsSuperAdmin() then
        ply:ChatPrint("[Tarkov UI] Only superadmins can modify player data.")
        return
    end

    local data = net.ReadString()
    local tbl = data and util.JSONToTable(data)
    if not tbl or not tbl.steamid then return end

    local sid = tbl.steamid
    PlayerData[sid] = PlayerData[sid] or { name = "Unknown", faction = "USEC", level = 1, time = 1, edition = "Standard", battle = 1 }

    if tbl.faction ~= nil and VALID_FACTIONS[tbl.faction] then PlayerData[sid].faction = tbl.faction end
    if tbl.level ~= nil then PlayerData[sid].level = math.Clamp(tonumber(tbl.level) or 1, 1, 70) end
    if tbl.time ~= nil then PlayerData[sid].time = math.Clamp(tonumber(tbl.time) or 1, 1, 9999) end
    if tbl.battle ~= nil then PlayerData[sid].battle = math.Clamp(tonumber(tbl.battle) or 1, 1, 100) end
    if tbl.edition ~= nil and VALID_EDITIONS[tbl.edition] then PlayerData[sid].edition = tbl.edition end

    SavePlayerData()

    for _, target in ipairs(player.GetAll()) do
        if target:SteamID() == sid then
            SaveAndSync(target, sid)
            break
        end
    end
end)

net.Receive("TarkovDeploy_RequestMyData", function(len, ply)
    local sid = EnsurePlayerData(ply)
    if not sid then return end

    SaveAndSync(ply, sid)
end)

TarkovDeployAPI = TarkovDeployAPI or {}

function TarkovDeployAPI.GetPlayerData(ply)
    if not IsValid(ply) then return nil end
    local sid = EnsurePlayerData(ply)
    return sid and PlayerData[sid] or nil
end

function TarkovDeployAPI.GetAllPlayerData()
    return PlayerData
end

function TarkovDeployAPI.SetPlayerBattle(ply, battle)
    local sid = EnsurePlayerData(ply)
    if not sid then return end
    PlayerData[sid].battle = math.Clamp(tonumber(battle) or 1, 1, 100)
    SaveAndSync(ply, sid)
end

function TarkovDeployAPI.SetPlayerLevel(ply, level)
    local sid = EnsurePlayerData(ply)
    if not sid then return end
    PlayerData[sid].level = math.Clamp(tonumber(level) or 1, 1, 70)
    SaveAndSync(ply, sid)
end

function TarkovDeployAPI.SetPlayerTime(ply, timeValue)
    local sid = EnsurePlayerData(ply)
    if not sid then return end
    PlayerData[sid].time = math.Clamp(tonumber(timeValue) or 1, 1, 9999)
    SaveAndSync(ply, sid)
end

function TarkovDeployAPI.SetPlayerFaction(ply, faction)
    local sid = EnsurePlayerData(ply)
    if not sid or not VALID_FACTIONS[faction] then return end
    PlayerData[sid].faction = faction
    SaveAndSync(ply, sid)
end

function TarkovDeployAPI.SetPlayerEdition(ply, edition)
    local sid = EnsurePlayerData(ply)
    if not sid or not VALID_EDITIONS[edition] then return end
    PlayerData[sid].edition = edition
    SaveAndSync(ply, sid)
end

function TarkovDeployAPI.SetPlayerData(ply, data)
    local sid = EnsurePlayerData(ply)
    if not sid or type(data) ~= "table" then return end

    if data.battle ~= nil then PlayerData[sid].battle = math.Clamp(tonumber(data.battle) or 1, 1, 100) end
    if data.level ~= nil then PlayerData[sid].level = math.Clamp(tonumber(data.level) or 1, 1, 70) end
    if data.time ~= nil then PlayerData[sid].time = math.Clamp(tonumber(data.time) or 1, 1, 9999) end
    if data.faction ~= nil and VALID_FACTIONS[data.faction] then PlayerData[sid].faction = data.faction end
    if data.edition ~= nil and VALID_EDITIONS[data.edition] then PlayerData[sid].edition = data.edition end

    SaveAndSync(ply, sid)
end

function TarkovDeployAPI.ResetPlayerData(ply)
    if not IsValid(ply) then return end

    local sid = ply:SteamID()
    PlayerData[sid] = DefaultPlayerData(ply)
    PlayerData[sid].faction = math.random(2) == 1 and "USEC" or "BEAR"
    SaveAndSync(ply, sid)
end

print("[Tarkov UI] Shared player data service loaded")
