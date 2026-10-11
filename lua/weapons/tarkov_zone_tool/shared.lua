--[[
    Tarkov Extraction Zone Tool (SWEP)
    Standalone weapon for setting extraction zones.
    Uses pistol model so it works on servers without toolgun access.
    
    Left click #1: Set corner 1 (aim position)
    Left click #2: Set corner 2 (current eye position), save the box
    Right click: Cancel current placement
    Reload: Remove nearest zone
]]

SWEP.PrintName = "Extraction Zone Tool"
SWEP.Author = "Tarkov Series"
SWEP.Category = "Tarkov"
SWEP.Spawnable = true
SWEP.AdminOnly = true

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

SWEP.Weight = 5
SWEP.AutoSwitchTo = false
SWEP.AutoSwitchFrom = false

SWEP.Slot = 1
SWEP.SlotPos = 5
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true

SWEP.ViewModel = "models/weapons/v_pistol.mdl"
SWEP.WorldModel = "models/weapons/w_pistol.mdl"
SWEP.HoldType = "pistol"

local function Tr(key, fallback, ...)
    if TarkovLangText then
        return TarkovLangText(key, fallback, ...)
    end
    if select("#", ...) > 0 then
        local ok, formatted = pcall(string.format, fallback or key, ...)
        if ok then return formatted end
    end
    return fallback or key
end

if CLIENT then
    surface.CreateFont("TarkovKeyLabel", {
        font = "Bender-Bold",
        size = 14,
        weight = 700,
        antialias = true,
    })
    surface.CreateFont("TarkovKeyHint", {
        font = "Bender-Bold",
        size = 16,
        weight = 700,
        antialias = true,
    })
end

function SWEP:Initialize()
    self:SetHoldType("pistol")
    self.CurrentZoneType = "extract"
end

function SWEP:Deploy()
    return true
end

function SWEP:Holster()
    if CLIENT then
        panelVisible = false
    end
    return true
end

function SWEP:CanPrimaryAttack()
    return true
end

function SWEP:CanSecondaryAttack()
    return true
end

function SWEP:EmitEmptySound()
    return false
end

if CLIENT then
    function SWEP:PrimaryAttack()
        self:SetNextPrimaryFire(CurTime() + 0.5)
        return true
    end

    function SWEP:SecondaryAttack()
        self:SetNextSecondaryFire(CurTime() + 0.5)
        return true
    end
end

-- Detect E key to open zone list, T key to toggle zone type
if CLIENT then
    local eHeld = false
    local tHeld = false
    local cHeld = false
    -- Zone type: "extract" or "transit"
    SWEP.ZoneType = "extract"

    function SWEP:Think()
        local owner = self:GetOwner()
        if not IsValid(owner) or owner ~= LocalPlayer() then return end

        -- E key: open zone list
        local eDown = owner:KeyDown(IN_USE)
        if eDown then
            if not eHeld then
                eHeld = true
                RunConsoleCommand("tarkov_extract_zone_list")
            end
        else
            eHeld = false
        end

        -- T key: toggle zone type
        local tDown = input.IsKeyDown(KEY_T)
        if tDown then
            if not tHeld then
                tHeld = true
                if self.ZoneType == "extract" then
                    self.ZoneType = "transit"
                else
                    self.ZoneType = "extract"
                end
                -- Sync to server via concommand
                RunConsoleCommand("tarkov_zone_settype", self.ZoneType)
                surface.PlaySound("tarkov_extraction/menu_inspector_window_close.wav")
            end
        else
            tHeld = false
        end

        -- C key: open tool settings
        local cDown = input.IsKeyDown(KEY_C)
        if cDown then
            if not cHeld then
                cHeld = true
                RunConsoleCommand("tarkov_extract_tool_settings")
            end
        else
            cHeld = false
        end
    end
end

-- Zone data (shared via networking)
if SERVER then
    -- Network strings registered in autorun/server/sv_zone_tool_net.lua

    -- Set zone type from client
    concommand.Add("tarkov_zone_settype", function(ply, cmd, args)
        if not IsValid(ply) then return end
        local wep = ply:GetActiveWeapon()
        if IsValid(wep) and wep:GetClass() == "tarkov_zone_tool" then
            local ztype = args[1] or "extract"
            if ztype ~= "extract" and ztype ~= "transit" then ztype = "extract" end
            wep.CurrentZoneType = ztype
        end
    end)
end

-- Shared zone storage
TarkovExtractZones = TarkovExtractZones or {}

-- Tool placement state per player
local placeState = {}

local function GetPlaceState(ply)
    if not ply then return nil end
    local sid = ply:SteamID()
    placeState[sid] = placeState[sid] or { corner1 = nil, placing = false }
    return placeState[sid]
end

-- ==================== SERVER ====================
if SERVER then
    local CURRENT_MAP = game.GetMap()
    local ZONE_FILE_PREFIX = "tarkov_extract_zones_"
    local ZONE_FILE_SUFFIX = ".txt"
    local VISITED_MAPS_FILE = "tarkov_extract_visited_maps.txt"
    local function NormalizeMapName(mapName)
        mapName = tostring(mapName or "")
        if mapName == "" then return nil end
        if string.find(mapName, "/", 1, true) or string.find(mapName, "\\", 1, true) then return nil end
        return mapName
    end
    local function GetZoneFileForMap(mapName)
        mapName = NormalizeMapName(mapName)
        if not mapName then return nil end
        return ZONE_FILE_PREFIX .. mapName .. ZONE_FILE_SUFFIX
    end
    local ZONE_FILE = GetZoneFileForMap(CURRENT_MAP)
    TarkovExtractRaidTime = TarkovExtractRaidTime or 10 * 60
    TarkovExtractRaidStartTime = TarkovExtractRaidStartTime or CurTime()

    -- Per-player zone config storage (received from client tool settings UI)
    local playerZoneConfig = {}
    local activeExtractions = {}
    local inactiveStates = {}
    local completedExtractionLocks = {}
    local postExtractProtectedPlayers = {}
    local postExtractFreezeApplied = {}
    local pendingDeployDestinations = {}
    local ApplyPendingDeployDestination

    local function AddVisitedMap(mapSet, mapName)
        mapName = NormalizeMapName(mapName)
        if not mapName then return end
        mapSet[mapName] = true
    end

    local function BuildVisitedMapSet()
        local mapSet = {}

        if file.Exists(VISITED_MAPS_FILE, "DATA") then
            local data = file.Read(VISITED_MAPS_FILE, "DATA")
            local tbl = data and util.JSONToTable(data)
            if type(tbl) == "table" then
                local list = type(tbl.maps) == "table" and tbl.maps or tbl
                for _, mapName in pairs(list) do
                    AddVisitedMap(mapSet, mapName)
                end
            end
        end

        local files = file.Find(ZONE_FILE_PREFIX .. "*" .. ZONE_FILE_SUFFIX, "DATA") or {}
        for _, fileName in ipairs(files) do
            local prefixLen = #ZONE_FILE_PREFIX
            local suffixLen = #ZONE_FILE_SUFFIX
            if string.sub(fileName, 1, prefixLen) == ZONE_FILE_PREFIX and string.sub(fileName, -suffixLen) == ZONE_FILE_SUFFIX then
                AddVisitedMap(mapSet, string.sub(fileName, prefixLen + 1, #fileName - suffixLen))
            end
        end

        return mapSet
    end

    local function SaveVisitedMapSet(mapSet)
        local maps = {}
        for mapName in pairs(mapSet or {}) do
            table.insert(maps, mapName)
        end
        table.sort(maps)
        file.Write(VISITED_MAPS_FILE, util.TableToJSON({ maps = maps }, true))
    end

    local function EnsureZoneFileForMap(mapName)
        local zoneFile = GetZoneFileForMap(mapName)
        if not zoneFile then return end
        if not file.Exists(zoneFile, "DATA") then
            file.Write(zoneFile, "[]")
        end
    end

    local function EnsureVisitedMapZoneFiles()
        local mapSet = BuildVisitedMapSet()
        AddVisitedMap(mapSet, CURRENT_MAP)
        SaveVisitedMapSet(mapSet)
        for mapName in pairs(mapSet) do
            EnsureZoneFileForMap(mapName)
        end
    end

    local function GetZoneId(zone, idx)
        if zone.id and zone.id ~= "" then return zone.id end
        return "zone_" .. tostring(idx or 0)
    end

    local function SetPostExtractProtection(ply, enabled)
        if not IsValid(ply) then return end
        local sid = ply:SteamID()
        if enabled then
            postExtractProtectedPlayers[sid] = true
            local wasFrozen = isfunction(ply.IsFrozen) and ply:IsFrozen() or false
            if not wasFrozen then
                postExtractFreezeApplied[sid] = true
                ply:Freeze(true)
            end
            ply:SetNWBool("TarkovExtract_PostExtractProtected", true)
        else
            postExtractProtectedPlayers[sid] = nil
            if postExtractFreezeApplied[sid] then
                ply:Freeze(false)
            end
            postExtractFreezeApplied[sid] = nil
            ply:SetNWBool("TarkovExtract_PostExtractProtected", false)
        end
    end

    local function IsPostExtractProtected(ply)
        if not IsValid(ply) then return false end
        return postExtractProtectedPlayers[ply:SteamID()] == true
    end

    local function DefaultCondition()
        return {
            enabled = false,
            key = false,
            pay = false,
            switch = false,
            usec = false,
            bear = false,
            scav = false,
            coop = false,
            payAmount = 0,
            healthBelowEnabled = false,
            healthBelow = 0,
            healthAboveEnabled = false,
            healthAbove = 0,
            armorBelowEnabled = false,
            armorBelow = 0,
            armorAboveEnabled = false,
            armorAbove = 0,
            levelBelowEnabled = false,
            levelBelow = 0,
            levelAboveEnabled = false,
            levelAbove = 0,
        }
    end

    local function AsBool(value)
        if type(value) == "boolean" then return value end
        if type(value) == "number" then return value ~= 0 end
        if type(value) == "string" then
            local trimmed = string.Trim and string.Trim(value) or string.gsub(value, "^%s*(.-)%s*$", "%1")
            local lowered = string.lower(trimmed)
            return lowered ~= "" and lowered ~= "0" and lowered ~= "false" and lowered ~= "no" and lowered ~= "off"
        end
        return false
    end

    local function IsDestinationZone(zone)
        return zone and zone.type == "transit" and AsBool(zone.isDestination)
    end

    local function NormalizeCondition(cond)
        if type(cond) ~= "table" then cond = {} end

        local defaults = DefaultCondition()
        for k, v in pairs(defaults) do
            if cond[k] == nil then cond[k] = v end
        end

        local boolFields = {
            "enabled", "key", "pay", "switch", "usec", "bear", "scav", "coop",
            "healthBelowEnabled", "healthAboveEnabled",
            "armorBelowEnabled", "armorAboveEnabled",
            "levelBelowEnabled", "levelAboveEnabled",
        }
        for _, field in ipairs(boolFields) do
            cond[field] = AsBool(cond[field])
        end

        local numberFields = {
            "payAmount",
            "healthBelow", "healthAbove",
            "armorBelow", "armorAbove",
            "levelBelow", "levelAbove",
        }
        for _, field in ipairs(numberFields) do
            cond[field] = tonumber(cond[field]) or 0
        end

        return cond
    end

    local function HasConditionRules(cond)
        if type(cond) ~= "table" then return false end
        if not cond.enabled then return false end
        return cond.key or cond.pay or cond.switch or cond.coop
            or cond.usec or cond.bear or cond.scav
            or cond.healthBelowEnabled or cond.healthAboveEnabled
            or cond.armorBelowEnabled or cond.armorAboveEnabled
            or cond.levelBelowEnabled or cond.levelAboveEnabled
    end

    local function NormalizeZone(zone, idx)
        if type(zone) ~= "table" then return nil end
        zone.id = zone.id or ("zone_" .. os.time() .. "_" .. tostring(idx or 0) .. "_" .. math.random(1000, 9999))
        zone.type = (zone.type == "transit") and "transit" or "extract"
        zone.name = tostring(zone.name or ((zone.type == "transit" and "Transit " or "Extract ") .. "Zone " .. tostring(idx or 1)))
        zone.extractTime = math.max(1, tonumber(zone.extractTime) or 7)
        zone.openTime = math.max(0, tonumber(zone.openTime) or 0)
        zone.closeTime = math.max(0, tonumber(zone.closeTime) or 0)
        zone.maxPlayers = math.max(1, tonumber(zone.maxPlayers) or 4)
        zone.oneTime = AsBool(zone.oneTime)
        zone.isDestination = zone.type == "transit" and AsBool(zone.isDestination) or false
        zone.transferToDestination = zone.type == "transit" and AsBool(zone.transferToDestination) or false
        zone.transferTargetId = tostring(zone.transferTargetId or "")
        if zone.type ~= "transit" or zone.isDestination or not zone.transferToDestination then
            zone.transferToDestination = false
            zone.transferTargetId = ""
        end
        zone.condition = NormalizeCondition(zone.condition)
        local exclusivePairs = {
            { "healthBelow", "healthAbove" },
            { "armorBelow", "armorAbove" },
            { "levelBelow", "levelAbove" },
        }
        for _, pair in ipairs(exclusivePairs) do
            local belowEnabled = pair[1] .. "Enabled"
            local aboveEnabled = pair[2] .. "Enabled"
            if zone.condition[belowEnabled] and zone.condition[aboveEnabled] then
                zone.condition[belowEnabled] = false
            end
        end
        return zone
    end

    local function NormalizeZones()
        local normalized = {}
        for i, zone in ipairs(TarkovExtractZones or {}) do
            local fixed = NormalizeZone(zone, i)
            if fixed and fixed.mins and fixed.maxs then
                table.insert(normalized, fixed)
            end
        end
        TarkovExtractZones = normalized
    end

    local GetFirstUnmetCondition
    local GetFirstUnmetConditionInfo
    local CountPlayersInside
    local CountActiveExtractionsForZone

    local function IsZoneClosedForList(zone)
        if not zone then return false end
        if zone.used then return true end

        local closeTime = tonumber(zone.closeTime) or 0
        if closeTime <= 0 then return false end

        local elapsed = CurTime() - (TarkovExtractRaidStartTime or CurTime())
        return elapsed >= closeTime
    end

    local function ConditionInfo(order, key, fallback, args)
        return {
            order = order,
            key = key,
            fallback = fallback,
            args = args or {},
        }
    end

    local function ConditionText(order, text)
        return tostring(order) .. " - " .. text
    end

    local function BuildConditionText(info)
        if type(info) ~= "table" or not info.key then return nil end
        return ConditionText(info.order or 0, Tr(info.key, info.fallback or "", unpack(info.args or {})))
    end

    local function GetClosedConditionInfo(zone)
        if not IsZoneClosedForList(zone) then return nil end
        return ConditionInfo(-2, "condition_closed", "已关闭")
    end

    local function GetOpenDelayConditionInfo(zone)
        if not zone or zone.used then return nil end

        local openTime = tonumber(zone.openTime) or 0
        if openTime <= 0 then return nil end

        local elapsed = CurTime() - (TarkovExtractRaidStartTime or CurTime())
        if elapsed >= openTime then return nil end

        local closeTime = tonumber(zone.closeTime) or 0
        if closeTime > 0 and elapsed >= closeTime then return nil end

        return ConditionInfo(-1, "condition_not_open", "未到达开放时间")
    end

    local function BuildExtractionData(ply)
        local extractions = {}
        local destinations = {}
        for i, zone in ipairs(TarkovExtractZones or {}) do
            if not IsDestinationZone(zone) then
                local isClosed = IsZoneClosedForList(zone)
                local conditionInfo = GetClosedConditionInfo(zone) or GetOpenDelayConditionInfo(zone)
                if IsValid(ply) and GetFirstUnmetCondition then
                    conditionInfo = conditionInfo or GetFirstUnmetConditionInfo(ply, zone)
                end
                local conditionText = BuildConditionText(conditionInfo)

                local row = {
                    id = GetZoneId(zone, i),
                    name = zone.name or ((zone.type == "transit" and "Transit " or "Extract ") .. "Zone " .. i),
                    type = zone.type == "transit" and "destination" or "extract",
                    status = isClosed and "closed" or "available",
                    timer = 0,
                    openTime = zone.openTime or 0,
                    closeTime = zone.closeTime or 0,
                    conditionText = conditionText,
                    conditionKey = conditionInfo and conditionInfo.key or nil,
                    conditionArgs = conditionInfo and conditionInfo.args or nil,
                    conditionOrder = conditionInfo and conditionInfo.order or nil,
                    maxPlayers = zone.oneTime and (tonumber(zone.maxPlayers) or 1) or 1,
                    occupiedPlayers = zone.oneTime and CountActiveExtractionsForZone and CountActiveExtractionsForZone(zone) or (CountPlayersInside and CountPlayersInside(zone) or 0),
                }
                if zone.type == "transit" then
                    table.insert(destinations, row)
                else
                    table.insert(extractions, row)
                end
            end
        end

        return {
            raidTime = TarkovExtractRaidTime or 600,
            raidStartTime = TarkovExtractRaidStartTime or CurTime(),
            serverTime = CurTime(),
            extractions = extractions,
            destinations = destinations,
        }
    end

    function TarkovExtractZone_BuildExtractionData(ply)
        return BuildExtractionData(ply)
    end

    local function NetworkReady(name)
        local id = util.NetworkStringToID(name)
        return id and id ~= 0
    end

    local function SyncExtractionData()
        if not NetworkReady("TarkovExtract_SyncData") then return end
        for _, ply in ipairs(player.GetAll()) do
            local payload = util.TableToJSON(BuildExtractionData(ply))
            net.Start("TarkovExtract_SyncData")
            net.WriteString(payload)
            net.Send(ply)
        end
    end

    local function LoadZones()
        EnsureVisitedMapZoneFiles()
        TarkovExtractZones = {}
        if file.Exists(ZONE_FILE, "DATA") then
            local data = file.Read(ZONE_FILE, "DATA")
            if data then
                local tbl = util.JSONToTable(data)
                if tbl then TarkovExtractZones = tbl end
            end
        end
        NormalizeZones()
    end

    local function SaveZones()
        EnsureVisitedMapZoneFiles()
        NormalizeZones()
        file.Write(ZONE_FILE, util.TableToJSON(TarkovExtractZones, true))
    end

    local function SyncZones()
        NormalizeZones()
        local payload = util.TableToJSON(TarkovExtractZones)
        net.Start("TarkovExtractZone_Sync")
        net.WriteString(payload)
        net.Broadcast()
        SyncExtractionData()
    end

    local function SyncToPlayer(ply)
        NormalizeZones()
        local zonesPayload = util.TableToJSON(TarkovExtractZones)
        local extractPayload = NetworkReady("TarkovExtract_SyncData") and util.TableToJSON(BuildExtractionData(ply)) or nil
        net.Start("TarkovExtractZone_Sync")
        net.WriteString(zonesPayload)
        net.Send(ply)
        if extractPayload then
            net.Start("TarkovExtract_SyncData")
            net.WriteString(extractPayload)
            net.Send(ply)
        end
    end

    LoadZones()

    hook.Add("PlayerInitialSpawn", "TarkovExtractZone_EnsureMapStorage", function()
        EnsureVisitedMapZoneFiles()
    end)

    hook.Add("PlayerInitialSpawn", "TarkovExtractZone_Send", function(ply)
        timer.Simple(3, function()
            if IsValid(ply) then SyncToPlayer(ply) end
        end)
    end)

    -- Receive zone config from client
    net.Receive("TarkovExtractZone_SetConfig", function(len, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        local data = net.ReadString()
        if data then
            local tbl = util.JSONToTable(data)
            if tbl then
                playerZoneConfig[ply:SteamID()] = tbl
            end
        end
    end)

    net.Receive("TarkovExtractZone_Edit", function(len, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        local data = net.ReadString()
        local tbl = data and util.JSONToTable(data)
        if type(tbl) ~= "table" then return end

        local idx = tonumber(tbl.index or 0)
        local zone = idx and TarkovExtractZones[idx]
        if not zone then return end

        if tbl.action == "remove" then
            local name = zone.name or ("Zone " .. idx)
            table.remove(TarkovExtractZones, idx)
            SaveZones()
            SyncZones()
            TarkovZone_Notify(ply, "notify_zone_removed", "Zone '%s' removed!", name)
        elseif tbl.action == "rename" then
            local newName = string.Trim(tostring(tbl.name or ""))
            if newName == "" then return end
            zone.name = string.sub(newName, 1, 64)
            SaveZones()
            SyncZones()
            TarkovZone_Notify(ply, "notify_zone_renamed", "Zone renamed to '%s'.", zone.name)
        elseif tbl.action == "update" then
            local cfg = type(tbl.config) == "table" and tbl.config or {}
            local newName = string.Trim(tostring(cfg.name or zone.name or ""))
            if newName ~= "" then
                zone.name = string.sub(newName, 1, 64)
            end
            zone.type = (cfg.type == "transit") and "transit" or "extract"
            zone.extractTime = math.max(1, tonumber(cfg.extractTime) or zone.extractTime or 7)
            zone.openTime = math.max(0, tonumber(cfg.openTime) or zone.openTime or 0)
            zone.closeTime = math.max(0, tonumber(cfg.closeTime) or zone.closeTime or 0)
            zone.oneTime = AsBool(cfg.oneTime)
            zone.maxPlayers = math.max(1, tonumber(cfg.maxPlayers) or zone.maxPlayers or 4)
            zone.highlighted = AsBool(cfg.highlighted)
            zone.isDestination = AsBool(cfg.isDestination)
            zone.transferToDestination = AsBool(cfg.transferToDestination)
            zone.transferTargetId = tostring(cfg.transferTargetId or "")
            zone.condition = NormalizeCondition(cfg.condition or zone.condition)
            NormalizeZone(zone, idx)
            SaveZones()
            SyncZones()
        elseif tbl.action == "highlight" then
            zone.highlighted = tobool(tbl.highlighted)
            SaveZones()
            SyncZones()
        elseif tbl.action == "reset_used" then
            zone.used = false
            SaveZones()
            SyncZones()
            TarkovZone_Notify(ply, "notify_zone_reset_used", "Zone '%s' is available again.", zone.name or idx)
        end
    end)

    -- Clean up config when player disconnects
    hook.Add("PlayerDisconnected", "TarkovExtractZone_CleanConfig", function(ply)
        local sid = IsValid(ply) and ply:SteamID() or nil
        if not sid then return end
        playerZoneConfig[sid] = nil
        activeExtractions[sid] = nil
        inactiveStates[sid] = nil
        completedExtractionLocks[sid] = nil
        postExtractProtectedPlayers[sid] = nil
        postExtractFreezeApplied[sid] = nil
        pendingDeployDestinations[sid] = nil
        timer.Remove("TarkovExtract_DelayedTransfer_" .. string.gsub(sid, "%W", "_"))
    end)

    hook.Add("PlayerSpawn", "TarkovExtract_ClearPostExtractProtectionOnSpawn", function(ply)
        timer.Simple(0, function()
            ApplyPendingDeployDestination(ply)
        end)
    end)

    hook.Add("EntityTakeDamage", "TarkovExtract_BlockPostExtractDamage", function(target, dmginfo)
        if not IsValid(target) or not target:IsPlayer() then return end
        if not IsPostExtractProtected(target) then return end
        if dmginfo then dmginfo:SetDamage(0) end
        return true
    end)

    hook.Add("StartCommand", "TarkovExtract_BlockPostExtractControls", function(ply, cmd)
        if not IsPostExtractProtected(ply) then return end

        cmd:SetForwardMove(0)
        cmd:SetSideMove(0)
        cmd:SetUpMove(0)
        cmd:RemoveKey(bit.bor(IN_ATTACK, IN_ATTACK2, IN_RELOAD, IN_USE, IN_JUMP, IN_DUCK, IN_SPEED, IN_WALK))
    end)

    net.Receive("TarkovExtract_ClearPostExtractProtection", function(len, ply)
        SetPostExtractProtection(ply, false)
        ApplyPendingDeployDestination(ply)
    end)

    local function IsZoneOpen(zone)
        if zone.used then return false, "closed" end
        local elapsed = CurTime() - (TarkovExtractRaidStartTime or CurTime())
        local openTime = tonumber(zone.openTime) or 0
        local closeTime = tonumber(zone.closeTime) or 0
        if openTime > 0 and elapsed < openTime then return false, "not_open" end
        if closeTime > 0 and elapsed >= closeTime then return false, "closed" end
        return true
    end

    local function IsPlayerInsideZone(ply, zone)
        if not IsValid(ply) or not zone or not zone.mins or not zone.maxs then return false end
        local pos = ply:GetPos()
        local mins = Vector(zone.mins.x or 0, zone.mins.y or 0, zone.mins.z or 0)
        local maxs = Vector(zone.maxs.x or 0, zone.maxs.y or 0, zone.maxs.z or 0)
        local expand = TarkovExtractConfig and TarkovExtractConfig.expand or 50
        local realMins = Vector(math.min(mins.x, maxs.x) - expand, math.min(mins.y, maxs.y) - expand, math.min(mins.z, maxs.z) - expand)
        local realMaxs = Vector(math.max(mins.x, maxs.x) + expand, math.max(mins.y, maxs.y) + expand, math.max(mins.z, maxs.z) + expand)

        return pos.x >= realMins.x and pos.x <= realMaxs.x and
            pos.y >= realMins.y and pos.y <= realMaxs.y and
            pos.z >= realMins.z and pos.z <= realMaxs.z
    end

    local function GetZoneCenterPoint(zone)
        if not zone or not zone.mins or not zone.maxs then return nil end
        local mins = Vector(zone.mins.x or 0, zone.mins.y or 0, zone.mins.z or 0)
        local maxs = Vector(zone.maxs.x or 0, zone.maxs.y or 0, zone.maxs.z or 0)
        local low = Vector(math.min(mins.x, maxs.x), math.min(mins.y, maxs.y), math.min(mins.z, maxs.z))
        local high = Vector(math.max(mins.x, maxs.x), math.max(mins.y, maxs.y), math.max(mins.z, maxs.z))
        return Vector((low.x + high.x) / 2, (low.y + high.y) / 2, low.z + 8)
    end

    local function FindDestinationZoneById(zoneId)
        zoneId = tostring(zoneId or "")
        if zoneId == "" then return nil end
        for i, zone in ipairs(TarkovExtractZones or {}) do
            if IsDestinationZone(zone) and GetZoneId(zone, i) == zoneId then
                return zone, i
            end
        end
        return nil
    end

    function ApplyPendingDeployDestination(ply)
        if not IsValid(ply) then return end
        local sid = ply:SteamID()
        local targetId = pendingDeployDestinations[sid]
        if not targetId then return end
        pendingDeployDestinations[sid] = nil

        local destZone = FindDestinationZoneById(targetId)
        local pos = destZone and GetZoneCenterPoint(destZone) or nil
        if not pos then return end

        ply:SetVelocity(-ply:GetVelocity())
        ply:SetPos(pos)
    end

    local function IsPlayerInsideAnyZone(ply)
        if not IsValid(ply) then return false end
        for _, zone in ipairs(TarkovExtractZones or {}) do
            if not IsDestinationZone(zone) and IsPlayerInsideZone(ply, zone) then return true end
        end
        return false
    end

    local function GetPlayerDeployData(ply)
        if TarkovDeployAPI and TarkovDeployAPI.GetPlayerData then
            local ok, data = pcall(TarkovDeployAPI.GetPlayerData, ply)
            if ok and type(data) == "table" then return data end
        end
        return nil
    end

    local function GetPlayerFaction(ply)
        local data = GetPlayerDeployData(ply)
        return data and data.faction or ply:GetNWString("TarkovFaction", "USEC")
    end

    local function GetPlayerLevel(ply)
        local data = GetPlayerDeployData(ply)
        return tonumber(data and data.level) or ply:GetNWInt("TarkovLevel", 1)
    end

    function CountPlayersInside(zone)
        local count = 0
        for _, other in ipairs(player.GetAll()) do
            if IsPlayerInsideZone(other, zone) then
                count = count + 1
            end
        end
        return count
    end

    CountActiveExtractionsForZone = function(zone)
        local zoneId = GetZoneId(zone)
        local count = 0
        for _, session in pairs(activeExtractions) do
            if session and session.zoneId == zoneId then
                count = count + 1
            end
        end
        return count
    end

    local function CountCoopFactionsInside(zone)
        local pmcCount = 0
        local scavCount = 0

        for _, other in ipairs(player.GetAll()) do
            if IsPlayerInsideZone(other, zone) then
                local faction = string.lower(GetPlayerFaction(other) or "")
                if faction == "scav" then
                    scavCount = scavCount + 1
                elseif faction == "usec" or faction == "bear" then
                    pmcCount = pmcCount + 1
                end
            end
        end

        return pmcCount, scavCount
    end

    local function HasCoopPairInside(zone)
        local pmcCount, scavCount = CountCoopFactionsInside(zone)
        return pmcCount >= 1 and scavCount >= 1
    end

    TarkovExtractSwitches = TarkovExtractSwitches or {}
    TarkovExtractAPI = TarkovExtractAPI or {}
    TarkovExtractAPI.ConditionResolvers = TarkovExtractAPI.ConditionResolvers or {}

    function TarkovExtractAPI.SetZoneSwitch(zoneId, enabled)
        TarkovExtractSwitches[tostring(zoneId or "")] = tobool(enabled)
    end

    local function CheckKeyCondition(ply, zone)
        local resolver = TarkovExtractAPI.ConditionResolvers.key
        local hasKey = resolver and resolver(ply, zone)
        if hasKey == nil then
            hasKey = ply:GetNWBool("TarkovExtract_HasKey", false) or ply:GetNWBool("TarkovHasKey", false) or ply:HasWeapon("tarkov_extract_key") or ply:HasWeapon("tarkov_key")
        end
        return hasKey
    end

    local function CheckPayCondition(ply, zone, amount)
        local resolver = TarkovExtractAPI.ConditionResolvers.pay
        local canPay = resolver and resolver(ply, zone, amount)
        if canPay == nil then
            canPay = amount <= 0 or ply:GetNWInt("TarkovRoubles", 0) >= amount or (ply.canAfford and ply:canAfford(amount))
        end
        return canPay
    end

    local function CheckSwitchCondition(ply, zone)
        local zoneId = GetZoneId(zone)
        local resolver = TarkovExtractAPI.ConditionResolvers.switch
        local switchOn = resolver and resolver(ply, zone)
        if switchOn == nil then
            switchOn = TarkovExtractSwitches[zoneId] or ply:GetNWBool("TarkovExtract_Switch_" .. zoneId, false)
        end
        return switchOn
    end

    GetFirstUnmetConditionInfo = function(ply, zone)
        local cond = NormalizeCondition(zone.condition)
        local order = 0

        local function NextCondition(failed, key, fallback, ...)
            if failed then
                return ConditionInfo(order, key, fallback, {...})
            end
            order = order + 1
            return nil
        end

        local faction = string.lower(GetPlayerFaction(ply) or "")
        if cond.usec or cond.bear or cond.scav then
            local allowed = (cond.usec and faction == "usec") or (cond.bear and faction == "bear") or (cond.scav and faction == "scav")
            local allowedNames = {}
            if cond.usec then table.insert(allowedNames, "USEC") end
            if cond.bear then table.insert(allowedNames, "BEAR") end
            if cond.scav then table.insert(allowedNames, "Scav") end
            local text = NextCondition(not allowed, "condition_required_faction", "需要阵营: %s", table.concat(allowedNames, "/"))
            if text then return text end
        end

        if not HasConditionRules(cond) then return nil end

        if cond.key then
            local text = NextCondition(not CheckKeyCondition(ply, zone), "condition_need_key", "需要钥匙")
            if text then return text end
        end

        local payAmount = tonumber(cond.payAmount) or 0
        if cond.pay then
            local text = payAmount > 0
                and NextCondition(not CheckPayCondition(ply, zone, payAmount), "condition_need_pay_amount", "需要付费: %s", tostring(payAmount))
                or NextCondition(not CheckPayCondition(ply, zone, payAmount), "condition_need_pay", "需要付费")
            if text then return text end
        end

        if cond.switch then
            local text = NextCondition(not CheckSwitchCondition(ply, zone), "condition_need_switch", "需要开启开关")
            if text then return text end
        end

        if cond.coop then
            local text = NextCondition(not HasCoopPairInside(zone), "condition_need_coop", "需要合作撤离")
            if text then return text end
        end

        local health = ply:Health()
        local armor = ply:Armor()
        local level = GetPlayerLevel(ply)

        if cond.healthBelowEnabled then
            local val = tonumber(cond.healthBelow) or 0
            local text = NextCondition(health >= val, "condition_health_below", "血量低于 %s", tostring(val))
            if text then return text end
        end

        if cond.healthAboveEnabled then
            local val = tonumber(cond.healthAbove) or 0
            local text = NextCondition(health <= val, "condition_health_above", "血量高于 %s", tostring(val))
            if text then return text end
        end

        if cond.armorBelowEnabled then
            local val = tonumber(cond.armorBelow) or 0
            local text = NextCondition(armor >= val, "condition_armor_below", "护甲低于 %s", tostring(val))
            if text then return text end
        end

        if cond.armorAboveEnabled then
            local val = tonumber(cond.armorAbove) or 0
            local text = NextCondition(armor <= val, "condition_armor_above", "护甲高于 %s", tostring(val))
            if text then return text end
        end

        if cond.levelBelowEnabled then
            local val = tonumber(cond.levelBelow) or 0
            local text = NextCondition(level >= val, "condition_level_below", "等级低于 %s", tostring(val))
            if text then return text end
        end

        if cond.levelAboveEnabled then
            local val = tonumber(cond.levelAbove) or 0
            local text = NextCondition(level <= val, "condition_level_above", "等级高于 %s", tostring(val))
            if text then return text end
        end

        return nil
    end

    GetFirstUnmetCondition = function(ply, zone)
        return BuildConditionText(GetFirstUnmetConditionInfo(ply, zone))
    end

    local function CheckZoneConditions(ply, zone)
        if IsDestinationZone(zone) then return false, "destination_only" end

        local isOpen, openReason = IsZoneOpen(zone)
        if not isOpen then return false, openReason end

        if zone.oneTime then
            local maxPlayers = math.max(1, tonumber(zone.maxPlayers) or 4)
            local sid = IsValid(ply) and ply:SteamID() or nil
            local session = sid and activeExtractions[sid] or nil
            local alreadyActive = session and session.zoneId == GetZoneId(zone)
            if not alreadyActive and CountActiveExtractionsForZone and CountActiveExtractionsForZone(zone) >= maxPlayers then
                return false, "full"
            end
        end

        local cond = NormalizeCondition(zone.condition)

        local faction = string.lower(GetPlayerFaction(ply) or "")
        if cond.usec or cond.bear or cond.scav then
            local allowed = (cond.usec and faction == "usec") or (cond.bear and faction == "bear") or (cond.scav and faction == "scav")
            if not allowed then return false, "wrong_faction" end
        end

        if not HasConditionRules(cond) then return true end

        if cond.key then
            if not CheckKeyCondition(ply, zone) then return false, "need_key" end
        end

        if cond.pay then
            local amount = tonumber(cond.payAmount) or 0
            if not CheckPayCondition(ply, zone, amount) then return false, "need_pay" end
        end

        if cond.switch then
            if not CheckSwitchCondition(ply, zone) then return false, "need_switch" end
        end

        if cond.coop and not HasCoopPairInside(zone) then
            return false, "need_coop"
        end

        local health = ply:Health()
        local armor = ply:Armor()
        local level = GetPlayerLevel(ply)

        if cond.healthBelowEnabled and health >= (tonumber(cond.healthBelow) or 0) then return false, "health_too_high" end
        if cond.healthAboveEnabled and health <= (tonumber(cond.healthAbove) or 0) then return false, "health_too_low" end
        if cond.armorBelowEnabled and armor >= (tonumber(cond.armorBelow) or 0) then return false, "armor_too_high" end
        if cond.armorAboveEnabled and armor <= (tonumber(cond.armorAbove) or 0) then return false, "armor_too_low" end
        if cond.levelBelowEnabled and level >= (tonumber(cond.levelBelow) or 0) then return false, "level_too_high" end
        if cond.levelAboveEnabled and level <= (tonumber(cond.levelAbove) or 0) then return false, "level_too_low" end

        return true
    end

    local function CanStartExtraction(ply, zone)
        local ok, reason = CheckZoneConditions(ply, zone)
        if not ok then return false, reason end

        if GetFirstUnmetCondition and GetFirstUnmetCondition(ply, zone) then
            return false, "condition_unmet"
        end

        return true
    end

    local function IsConditionFailReason(reason)
        return reason == "condition_unmet"
            or reason == "not_open"
            or reason == "closed"
            or reason == "wrong_faction"
            or reason == "full"
            or reason == "need_key"
            or reason == "need_pay"
            or reason == "need_switch"
            or reason == "need_coop"
            or reason == "health_too_high"
            or reason == "health_too_low"
            or reason == "armor_too_high"
            or reason == "armor_too_low"
            or reason == "level_too_high"
            or reason == "level_too_low"
    end

    -- Check if a player is inside any currently usable extraction zone.
    function TarkovExtractZone_IsPlayerInZone(ply, zoneType)
        if not IsValid(ply) then return false, nil end
        local usableZone, usableIdx = nil, nil
        for i, zone in ipairs(TarkovExtractZones or {}) do
            if not IsDestinationZone(zone) and (not zoneType or zone.type == zoneType) and IsPlayerInsideZone(ply, zone) then
                local ok, reason = CanStartExtraction(ply, zone)
                if not ok and IsConditionFailReason(reason) then
                    return false, nil, nil
                elseif ok then
                    usableZone = usableZone or zone
                    usableIdx = usableIdx or i
                end
            end
        end
        if usableZone then return true, usableZone, usableIdx end
        return false, nil, nil
    end

    local function SendExtractionState(ply, payload)
        if not IsValid(ply) then return end
        local data = util.TableToJSON(payload or { active = false })
        net.Start("TarkovExtract_ExtractState")
        net.WriteString(data)
        net.Send(ply)
    end

    local EXTRACT_COMPLETE_FADE_DELAY = 1.2

    local function PerformExtractionTransfer(ply, zone)
        if not IsValid(ply) then return end

        local handled = hook.Run("TarkovExtract_PlayerExtracted", ply, zone)
        if handled == true then return end

        local spawns = ents.FindByClass("info_player_start")
        if #spawns <= 0 then spawns = ents.FindByClass("info_player_deathmatch") end
        local spawnEnt = #spawns > 0 and spawns[math.random(#spawns)] or nil
        if IsValid(spawnEnt) then
            ply:SetVelocity(-ply:GetVelocity())
            ply:SetPos(spawnEnt:GetPos() + Vector(0, 0, 8))
            ply:SetEyeAngles(spawnEnt:GetAngles())
        end
    end

    local function IsCoopZone(zone)
        local cond = NormalizeCondition(zone and zone.condition)
        return cond.coop == true
    end

    local function CompleteExtraction(ply, zone, idx, deferOneTimeUse)
        local sid = ply:SteamID()
        activeExtractions[sid] = nil
        inactiveStates[sid] = nil
        completedExtractionLocks[sid] = true
        SetPostExtractProtection(ply, true)
        if zone.type == "transit" and zone.transferToDestination and tostring(zone.transferTargetId or "") ~= "" then
            pendingDeployDestinations[sid] = tostring(zone.transferTargetId)
        else
            pendingDeployDestinations[sid] = nil
        end

        local cond = NormalizeCondition(zone.condition)
        local payAmount = tonumber(cond.payAmount) or 0
        if HasConditionRules(cond) and cond.pay and payAmount > 0 then
            if ply.addMoney then
                ply:addMoney(-payAmount)
            else
                ply:SetNWInt("TarkovRoubles", math.max(0, ply:GetNWInt("TarkovRoubles", 0) - payAmount))
            end
        end

        if zone.oneTime and not deferOneTimeUse then
            zone.used = true
            SaveZones()
            SyncZones()
        end

        local completePayload = util.TableToJSON({
            type = zone.type or "extract",
            name = zone.name or "Zone",
            fadeDuration = EXTRACT_COMPLETE_FADE_DELAY,
        })
        net.Start("TarkovExtract_Complete")
        net.WriteString(completePayload)
        net.Send(ply)

        local timerName = "TarkovExtract_DelayedTransfer_" .. string.gsub(sid or tostring(ply:EntIndex()), "%W", "_")
        timer.Remove(timerName)
        timer.Create(timerName, EXTRACT_COMPLETE_FADE_DELAY, 1, function()
            PerformExtractionTransfer(ply, zone)
        end)
    end

    local function CompleteCoopExtractionGroup(zone, idx)
        local completed = {}

        for _, other in ipairs(player.GetAll()) do
            if IsPlayerInsideZone(other, zone) then
                local ok = CanStartExtraction(other, zone)
                if ok then
                    table.insert(completed, other)
                end
            end
        end

        if #completed <= 0 then return false end

        for _, other in ipairs(completed) do
            CompleteExtraction(other, zone, idx, true)
            SendExtractionState(other, { active = false })
        end

        if zone.oneTime then
            zone.used = true
            SaveZones()
            SyncZones()
        end

        return true
    end

    hook.Add("Think", "TarkovExtract_ServerExtractionThink", function()
        if (TarkovExtractNextThink or 0) > CurTime() then return end
        TarkovExtractNextThink = CurTime() + 0.1

        for _, ply in ipairs(player.GetAll()) do
            local sid = ply:SteamID()
            if completedExtractionLocks[sid] then
                activeExtractions[sid] = nil
                inactiveStates[sid] = nil
                if not IsPlayerInsideAnyZone(ply) then
                    completedExtractionLocks[sid] = nil
                end
            else
                local chosenZone, chosenIdx, failReason = nil, nil, nil
                local failedZone, failedIdx = nil, nil
                local blockingFailReason, blockingFailedZone, blockingFailedIdx = nil, nil, nil

                for i, zone in ipairs(TarkovExtractZones or {}) do
                    if not IsDestinationZone(zone) and IsPlayerInsideZone(ply, zone) then
                        local ok, reason = CanStartExtraction(ply, zone)
                        if ok then
                            chosenZone = chosenZone or zone
                            chosenIdx = chosenIdx or i
                        else
                            failReason = failReason or reason
                            failedZone = failedZone or zone
                            failedIdx = failedIdx or i
                            if IsConditionFailReason(reason) then
                                blockingFailReason = blockingFailReason or reason
                                blockingFailedZone = blockingFailedZone or zone
                                blockingFailedIdx = blockingFailedIdx or i
                            end
                        end
                    end
                end

                if blockingFailedZone then
                    chosenZone = nil
                    chosenIdx = nil
                    failReason = blockingFailReason
                    failedZone = blockingFailedZone
                    failedIdx = blockingFailedIdx
                end

                local session = activeExtractions[sid]
                if chosenZone then
                    inactiveStates[sid] = nil
                    local zoneId = GetZoneId(chosenZone, chosenIdx)
                    if not session or session.zoneId ~= zoneId then
                        session = {
                            zoneId = zoneId,
                            idx = chosenIdx,
                            startTime = CurTime(),
                            nextSend = 0,
                        }
                        activeExtractions[sid] = session
                    end

                    local extractTime = math.max(1, tonumber(chosenZone.extractTime) or 7)
                    local remaining = math.max(0, extractTime - (CurTime() - session.startTime))
                    if remaining <= 0 then
                        local stillOk, finalReason = CanStartExtraction(ply, chosenZone)
                        if stillOk and IsPlayerInsideZone(ply, chosenZone) then
                            if IsCoopZone(chosenZone) and HasCoopPairInside(chosenZone) then
                                CompleteCoopExtractionGroup(chosenZone, chosenIdx)
                            else
                                CompleteExtraction(ply, chosenZone, chosenIdx)
                                SendExtractionState(ply, { active = false })
                            end
                        else
                            activeExtractions[sid] = nil
                            local zoneId = GetZoneId(chosenZone, chosenIdx)
                            local reason = finalReason or "condition_unmet"
                            inactiveStates[sid] = reason .. ":" .. tostring(zoneId or "")
                            SendExtractionState(ply, {
                                active = false,
                                reason = reason,
                                zoneId = zoneId,
                                type = chosenZone.type or nil,
                                name = chosenZone.name or nil,
                            })
                        end
                    elseif session.nextSend <= CurTime() then
                        session.nextSend = CurTime() + 0.1
                        SendExtractionState(ply, {
                            active = true,
                            type = chosenZone.type or "extract",
                            name = chosenZone.name or "Zone",
                            remaining = remaining,
                            maxPlayers = chosenZone.oneTime and (tonumber(chosenZone.maxPlayers) or 1) or 1,
                            occupiedPlayers = chosenZone.oneTime and CountActiveExtractionsForZone(chosenZone) or CountPlayersInside(chosenZone),
                            showOccupancy = chosenZone.oneTime == true and (tonumber(chosenZone.maxPlayers) or 1) > 1,
                        })
                    end
                elseif session then
                    activeExtractions[sid] = nil
                    local failedZoneId = failedZone and GetZoneId(failedZone, failedIdx) or nil
                    inactiveStates[sid] = (failReason or "left_zone") .. ":" .. tostring(failedZoneId or "")
                    SendExtractionState(ply, {
                        active = false,
                        reason = failReason or "left_zone",
                        zoneId = failedZoneId,
                        type = failedZone and failedZone.type or nil,
                        name = failedZone and failedZone.name or nil,
                    })
                elseif failReason then
                    local failedZoneId = failedZone and GetZoneId(failedZone, failedIdx) or nil
                    local inactiveKey = failReason .. ":" .. tostring(failedZoneId or "")
                    if inactiveStates[sid] ~= inactiveKey then
                        inactiveStates[sid] = inactiveKey
                        SendExtractionState(ply, {
                            active = false,
                            reason = failReason,
                            zoneId = failedZoneId,
                            type = failedZone and failedZone.type or nil,
                            name = failedZone and failedZone.name or nil,
                        })
                    end
                else
                    inactiveStates[sid] = nil
                end
            end
        end
    end)

    -- SWEP functions
    function SWEP:PrimaryAttack()
        if CLIENT then return end
        self:SetNextPrimaryFire(CurTime() + 0.5)
        self:GetOwner():EmitSound("tarkov_extraction/menu_inspector_window_open.wav")

        local ply = self:GetOwner()
        if not IsValid(ply) or not ply:IsSuperAdmin() then
            if IsValid(ply) then
                TarkovZone_Notify(ply, "notify_superadmin_only_set_zones", "Only superadmins can set zones.")
            end
            return
        end

        local state = GetPlaceState(ply)
        local tr = ply:GetEyeTrace()

        if not state.placing then
            -- First click: set corner 1
            state.corner1 = tr.HitPos
            state.placing = true
            TarkovZone_Notify(ply, "notify_corner_1_set", "Corner 1 set. Move to opposite corner and click again.")

            net.Start("TarkovExtractZone_PlaceState")
            net.WriteVector(state.corner1)
            net.WriteBool(true)
            net.Send(ply)
        else
            -- Second click: set corner 2 at eye position
            local corner2 = ply:EyePos()
            local c1 = state.corner1

            local mins = Vector(math.min(c1.x, corner2.x), math.min(c1.y, corner2.y), math.min(c1.z, corner2.z))
            local maxs = Vector(math.max(c1.x, corner2.x), math.max(c1.y, corner2.y), math.max(c1.z, corner2.z))

            -- Read config from player's stored settings
            local cfg = playerZoneConfig[ply:SteamID()] or {}
            local zoneName = cfg.name
            if not zoneName or zoneName == "" then
                zoneName = (self.CurrentZoneType == "transit" and "Transit " or "Extract ") .. "Zone " .. (#TarkovExtractZones + 1)
            end

            local zone = {
                name = zoneName,
                type = self.CurrentZoneType or "extract",
                mins = { x = mins.x, y = mins.y, z = mins.z },
                maxs = { x = maxs.x, y = maxs.y, z = maxs.z },
                map = game.GetMap(),
                extractTime = cfg.extractTime or 7,
                condition = cfg.condition or { enabled = false, key = false, pay = false, switch = false, usec = false, bear = false, scav = false, coop = false, healthBelow = 0, healthAbove = 0, armorBelow = 0, armorAbove = 0, levelBelow = 0, levelAbove = 0 },
                openTime = cfg.openTime or 0,
                closeTime = cfg.closeTime or 0,
                oneTime = cfg.oneTime or false,
                maxPlayers = cfg.maxPlayers or 4,
                isDestination = cfg.isDestination or false,
                transferToDestination = cfg.transferToDestination or false,
                transferTargetId = cfg.transferTargetId or "",
            }

            table.insert(TarkovExtractZones, zone)
            SaveZones()
            SyncZones()
            TarkovZone_Notify(ply, "notify_zone_saved", "Zone '%s' saved!", zone.name)

            state.placing = false
            state.corner1 = nil

            net.Start("TarkovExtractZone_PlaceState")
            net.WriteVector(Vector(0, 0, 0))
            net.WriteBool(false)
            net.Send(ply)
        end
    end

    function SWEP:SecondaryAttack()
        if CLIENT then return end
        self:SetNextSecondaryFire(CurTime() + 0.5)

        local ply = self:GetOwner()
        if not IsValid(ply) then return end

        local state = GetPlaceState(ply)
        if state.placing then
            state.placing = false
            state.corner1 = nil
            ply:EmitSound("tarkov_extraction/menu_escape.wav")
            TarkovZone_Notify(ply, "notify_placement_cancelled", "Placement cancelled.")

            net.Start("TarkovExtractZone_PlaceState")
            net.WriteVector(Vector(0, 0, 0))
            net.WriteBool(false)
            net.Send(ply)
        end
    end

    function SWEP:Reload()
        if CLIENT then return end
        if not self.NextReload or CurTime() > self.NextReload then
            self.NextReload = CurTime() + 1
        else
            return
        end

        local ply = self:GetOwner()
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end

        local function RayBoxDistance(origin, dir, mins, maxs)
            local tNear = -math.huge
            local tFar = math.huge

            local axes = { "x", "y", "z" }
            for _, axis in ipairs(axes) do
                local o = origin[axis]
                local d = dir[axis]
                local minVal = math.min(mins[axis], maxs[axis])
                local maxVal = math.max(mins[axis], maxs[axis])

                if math.abs(d) < 0.000001 then
                    if o < minVal or o > maxVal then
                        return nil
                    end
                else
                    local t1 = (minVal - o) / d
                    local t2 = (maxVal - o) / d
                    if t1 > t2 then t1, t2 = t2, t1 end

                    tNear = math.max(tNear, t1)
                    tFar = math.min(tFar, t2)

                    if tNear > tFar then
                        return nil
                    end
                end
            end

            if tFar < 0 then return nil end
            return math.max(0, tNear)
        end

        -- Find zone that player is aiming at (ray-box intersection)
        local eyePos = ply:EyePos()
        local eyeDir = ply:GetAimVector()

        local hitIdx = nil
        local hitDist = math.huge

        for i, zone in ipairs(TarkovExtractZones) do
            if zone.mins and zone.maxs then
                local mins = Vector(zone.mins.x or 0, zone.mins.y or 0, zone.mins.z or 0)
                local maxs = Vector(zone.maxs.x or 0, zone.maxs.y or 0, zone.maxs.z or 0)
                local dist = RayBoxDistance(eyePos, eyeDir, mins, maxs)
                if dist and dist < hitDist then
                    hitDist = dist
                    hitIdx = i
                end
            end
        end

        if hitIdx then
            local name = TarkovExtractZones[hitIdx].name or "unnamed"
            table.remove(TarkovExtractZones, hitIdx)
            SaveZones()
            SyncZones()
            ply:EmitSound("tarkov_extraction/menu_trader_press.wav")
            TarkovZone_Notify(ply, "notify_zone_removed", "Zone '%s' removed!", name)
        else
            TarkovZone_Notify(ply, "notify_no_zone_crosshair", "No zone in crosshair.")
        end
    end
end

-- ==================== CLIENT ====================
if CLIENT then
    local clientCorner1 = nil
    local clientPlacing = false

    net.Receive("TarkovExtractZone_PlaceState", function()
        clientCorner1 = net.ReadVector()
        clientPlacing = net.ReadBool()
        if not clientPlacing then
            clientCorner1 = nil
        end
    end)

    -- Draw wireframe box
    local function DrawWireBox(mins, maxs, color)
        local corners = {
            Vector(mins.x, mins.y, mins.z),
            Vector(maxs.x, mins.y, mins.z),
            Vector(maxs.x, maxs.y, mins.z),
            Vector(mins.x, maxs.y, mins.z),
            Vector(mins.x, mins.y, maxs.z),
            Vector(maxs.x, mins.y, maxs.z),
            Vector(maxs.x, maxs.y, maxs.z),
            Vector(mins.x, maxs.y, maxs.z),
        }
        render.DrawLine(corners[1], corners[2], color, false)
        render.DrawLine(corners[2], corners[3], color, false)
        render.DrawLine(corners[3], corners[4], color, false)
        render.DrawLine(corners[4], corners[1], color, false)
        render.DrawLine(corners[5], corners[6], color, false)
        render.DrawLine(corners[6], corners[7], color, false)
        render.DrawLine(corners[7], corners[8], color, false)
        render.DrawLine(corners[8], corners[5], color, false)
        render.DrawLine(corners[1], corners[5], color, false)
        render.DrawLine(corners[2], corners[6], color, false)
        render.DrawLine(corners[3], corners[7], color, false)
        render.DrawLine(corners[4], corners[8], color, false)
    end

    -- Panel slide animation state
    local panelSlide = 0 -- 0 = hidden (off-screen right), 1 = fully visible
    local panelVisible = false
    local SLIDE_SPEED = 5

    -- Persistent HUD hook for slide-out animation after holster
    hook.Add("HUDPaint", "TarkovZoneTool_SlidePanel", function()
        local ply = LocalPlayer()
        local wep = ply:GetActiveWeapon()
        local isHolding = IsValid(wep) and wep:GetClass() == "tarkov_zone_tool"

        if isHolding then
            panelVisible = true
        else
            panelVisible = false
        end

        -- Animate
        if panelVisible then
            panelSlide = math.min(1, panelSlide + FrameTime() * SLIDE_SPEED)
        else
            panelSlide = math.max(0, panelSlide - FrameTime() * SLIDE_SPEED)
        end

        if panelSlide <= 0 then return end

        local scrW, scrH = ScrW(), ScrH()
        local panelW = 350
        local panelH = 340
        local panelFinalX = scrW - panelW
        local panelStartX = scrW
        local eased = panelSlide * panelSlide * (3 - 2 * panelSlide) -- smoothstep
        local panelX = Lerp(eased, panelStartX, panelFinalX)
        local panelY = (scrH - panelH) / 2

        surface.SetDrawColor(0, 0, 0, math.floor(217 * panelSlide))
        surface.DrawRect(panelX, panelY, panelW, panelH)
        surface.SetDrawColor(205, 201, 175, math.floor(255 * panelSlide))
        surface.DrawOutlinedRect(panelX, panelY, panelW, panelH, 1)

        local alpha = math.floor(255 * panelSlide)

        -- Title
        draw.SimpleText(Tr("zone_tool_title", "Zone Tool"), "TSettings_Label", panelX + 15, panelY + 18, Color(205, 201, 175, alpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

        -- Description
        draw.SimpleText(Tr("zone_tool_desc_1", "Left click to set corners."), "TSettings_Section", panelX + 15, panelY + 48, Color(150, 148, 130, alpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText(Tr("zone_tool_desc_2", "Two corners define the zone box."), "TSettings_Section", panelX + 15, panelY + 65, Color(150, 148, 130, alpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

        -- Key bindings with icons
        local iconSize = 22
        local bindY = panelY + 95

        -- Switch type: Key_Big + T
        local matKeyBig = Material("tarkov_extraction/Key_Small.png", "noclamp smooth")
        draw.SimpleText(Tr("zone_tool_switch_type", "Switch Type"), "TarkovKeyHint", panelX + 15, bindY + 4, Color(205, 201, 175, alpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        if matKeyBig and not matKeyBig:IsError() then
            surface.SetDrawColor(255, 255, 255, alpha)
            surface.SetMaterial(matKeyBig)
            surface.DrawTexturedRect(panelX + 120, bindY, iconSize, iconSize)
        end
        draw.SimpleText("T", "TarkovKeyLabel", panelX + 120 + (iconSize) / 2, bindY + 4, Color(205, 201, 175, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

        bindY = bindY + 40

        -- Remove zone: Key_Big + R
        draw.SimpleText(Tr("zone_tool_remove_zone", "Remove Zone"), "TarkovKeyHint", panelX + 15, bindY + 4, Color(205, 201, 175, alpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        if matKeyBig and not matKeyBig:IsError() then
            surface.SetDrawColor(255, 255, 255, alpha)
            surface.SetMaterial(matKeyBig)
            surface.DrawTexturedRect(panelX + 120, bindY, iconSize, iconSize)
        end
        draw.SimpleText("R", "TarkovKeyLabel", panelX + 120 + (iconSize) / 2, bindY + 4, Color(205, 201, 175, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

        bindY = bindY + 40

        -- Place zone: Mouse icons
        local matMouseL = Material("tarkov_extraction/Key_Mouse_Left.png", "noclamp smooth")
        local matMouseR = Material("tarkov_extraction/Key_Mouse_Right.png", "noclamp smooth")
        local matComma = Material("tarkov_extraction/Key_Comma.png", "noclamp smooth")
        draw.SimpleText(Tr("zone_tool_place_zone", "Place Zone"), "TarkovKeyHint", panelX + 15, bindY + 4, Color(205, 201, 175, alpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        if matMouseL and not matMouseL:IsError() then
            surface.SetDrawColor(255, 255, 255, alpha)
            surface.SetMaterial(matMouseL)
            surface.DrawTexturedRect(panelX + 120, bindY - 2, iconSize, iconSize + 4)
        end

        -- Comma separator
        local commaX = panelX + 120 + iconSize + 4
        if matComma and not matComma:IsError() then
            surface.SetDrawColor(255, 255, 255, alpha)
            surface.SetMaterial(matComma)
            surface.DrawTexturedRect(commaX + 4, bindY + 15, 4, 4)
        end

        -- Cancel placement: right click
        draw.SimpleText(Tr("zone_tool_cancel", "Cancel"), "TarkovKeyHint", commaX + 14, bindY + 4, Color(205, 201, 175, alpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        if matMouseR and not matMouseR:IsError() then
            surface.SetDrawColor(255, 255, 255, alpha)
            surface.SetMaterial(matMouseR)
            surface.DrawTexturedRect(commaX + 80, bindY - 2, iconSize, iconSize + 4)
        end

        bindY = bindY + 40

        -- Zone list: Key_Big + E
        draw.SimpleText(Tr("zone_tool_zone_list", "Zone List"), "TarkovKeyHint", panelX + 15, bindY + 4, Color(205, 201, 175, alpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        if matKeyBig and not matKeyBig:IsError() then
            surface.SetDrawColor(255, 255, 255, alpha)
            surface.SetMaterial(matKeyBig)
            surface.DrawTexturedRect(panelX + 120, bindY, iconSize, iconSize)
        end
        draw.SimpleText("E", "TarkovKeyLabel", panelX + 120 + (iconSize) / 2, bindY + 4, Color(205, 201, 175, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

        bindY = bindY + 40

        -- Settings: Key_Big + C
        draw.SimpleText(Tr("zone_tool_settings", "Settings"), "TarkovKeyHint", panelX + 15, bindY + 4, Color(205, 201, 175, alpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        if matKeyBig and not matKeyBig:IsError() then
            surface.SetDrawColor(255, 255, 255, alpha)
            surface.SetMaterial(matKeyBig)
            surface.DrawTexturedRect(panelX + 120, bindY, iconSize, iconSize)
        end
        draw.SimpleText("C", "TarkovKeyLabel", panelX + 120 + (iconSize) / 2, bindY + 4, Color(205, 201, 175, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

        -- Current mode indicator below key hints
        bindY = bindY + 40
        local zoneType = "extract"
        if isHolding and wep.ZoneType then
            zoneType = wep.ZoneType
        end
        local modeText = zoneType == "extract" and Tr("zone_tool_mode_extract", "Extraction Point") or Tr("zone_tool_mode_transit", "Transit Point")
        local modeColor = zoneType == "extract" and Color(140, 200, 50, alpha) or Color(255, 160, 40, alpha)
        -- "Mode:" left-aligned, mode name + icon centered on same line
        surface.SetFont("TarkovKeyHint")
        local modeLabel = Tr("zone_tool_mode", "Mode:")
        local modeLabelW = select(1, surface.GetTextSize(modeLabel .. " "))
        local modeTextW = select(1, surface.GetTextSize(modeText))
        local modeIconSize = 18
        local modeIconGap = 4
        local modeTotalW = modeTextW + modeIconGap + modeIconSize
        local modeStartX = panelX + modeLabelW + 15 + ((panelW - modeLabelW - 15) - modeTotalW) / 2 - 18

        draw.SimpleText(modeLabel, "TarkovKeyHint", panelX + 15, bindY, Color(205, 201, 175, alpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText(modeText, "TarkovKeyHint", modeStartX, bindY, modeColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

        local modeIconPath = zoneType == "extract" and "tarkov_extraction/icon_exit_pmc_yes.png" or "tarkov_extraction/icon_exit_pmc_yes_marathon.png"
        local matModeIcon = Material(modeIconPath, "noclamp smooth")
        if matModeIcon and not matModeIcon:IsError() then
            surface.SetDrawColor(255, 255, 255, alpha)
            surface.SetMaterial(matModeIcon)
            surface.DrawTexturedRect(modeStartX + modeTextW + modeIconGap, bindY + 1, modeIconSize, modeIconSize)
        end

        -- Notification system (replaces static bottom bar)
        if not TarkovZoneNotifications then
            TarkovZoneNotifications = {}
        end

        local notifW = 520
        local notifH = 28
        local notifBaseY = scrH 
        local notifGap = 2
        local NOTIF_IN_TIME = 0.3
        local NOTIF_VISIBLE_TIME = 3
        local NOTIF_OUT_TIME = 0.4
        local NOTIF_SLIDE = 30

        local matAlert = Material("tarkov_extraction/notification_icon_alert_green.png", "noclamp smooth")

        local removeList = {}
        for i, notif in ipairs(TarkovZoneNotifications) do
            local elapsed = CurTime() - notif.startTime
            local nalpha = 0
            local offsetY = 0

            if notif.state == "in" then
                local frac = math.min(1, elapsed / NOTIF_IN_TIME)
                nalpha = frac * 255
                offsetY = (1 - frac) * NOTIF_SLIDE
                if frac >= 1 then
                    notif.state = "visible"
                    notif.startTime = CurTime()
                end
            elseif notif.state == "visible" then
                nalpha = 255
                offsetY = 0
                if elapsed >= NOTIF_VISIBLE_TIME then
                    notif.state = "out"
                    notif.startTime = CurTime()
                end
            elseif notif.state == "out" then
                local frac = math.min(1, elapsed / NOTIF_OUT_TIME)
                nalpha = (1 - frac) * 255
                offsetY = frac * NOTIF_SLIDE
                if frac >= 1 then
                    table.insert(removeList, 1, i)
                end
            end

            nalpha = math.floor(nalpha * panelSlide)
            if nalpha > 0 then
                local ny = notifBaseY - (i * (notifH + notifGap)) + offsetY
                local nx = scrW - notifW

                surface.SetDrawColor(0, 0, 0, math.floor(nalpha * 0.85))
                surface.DrawRect(nx, ny, notifW, notifH)

                if matAlert and not matAlert:IsError() then
                    local iconSize = notifH - 4
                    surface.SetDrawColor(255, 255, 255, nalpha)
                    surface.SetMaterial(matAlert)
                    surface.DrawTexturedRect(nx + 2, ny + 2, iconSize, iconSize)
                end

                local notifText = TarkovResolveNotificationText and TarkovResolveNotificationText(notif) or (notif.text or "")
                draw.SimpleText(notifText, "TarkovKeyHint", nx + 30, ny + notifH / 2, Color(205, 201, 175, nalpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
        end

        for _, idx in ipairs(removeList) do
            table.remove(TarkovZoneNotifications, idx)
        end
    end)

    function SWEP:DrawHUD()
        -- Drawing handled by persistent hook above
    end

    hook.Add("PostDrawTranslucentRenderables", "TarkovExtractZone_Draw3D", function()
        local ply = LocalPlayer()
        if not IsValid(ply) then return end
        local wep = ply:GetActiveWeapon()
        if not IsValid(wep) or wep:GetClass() ~= "tarkov_zone_tool" then return end

        -- Draw saved zones (green wireframe, highlighted = filled faces)
        for i, zone in ipairs(TarkovExtractZones) do
            if zone.mins and zone.maxs then
                local mins = Vector(zone.mins.x or 0, zone.mins.y or 0, zone.mins.z or 0)
                local maxs = Vector(zone.maxs.x or 0, zone.maxs.y or 0, zone.maxs.z or 0)
                render.SetColorMaterial()
                local zoneColor = (zone.type == "transit") and Color(255, 160, 40, 255) or Color(140, 200, 50, 255)
                DrawWireBox(mins, maxs, zoneColor)

                -- Fill with semi-transparent green if highlighted
                if zone.highlighted then
                    render.SetColorMaterial()
                    render.SetBlend(0.15)
                    render.DrawQuad(
                        Vector(mins.x, mins.y, mins.z), Vector(maxs.x, mins.y, mins.z),
                        Vector(maxs.x, maxs.y, mins.z), Vector(mins.x, maxs.y, mins.z))
                    render.DrawQuad(
                        Vector(mins.x, mins.y, maxs.z), Vector(mins.x, maxs.y, maxs.z),
                        Vector(maxs.x, maxs.y, maxs.z), Vector(maxs.x, mins.y, maxs.z))
                    render.DrawQuad(
                        Vector(mins.x, mins.y, mins.z), Vector(mins.x, mins.y, maxs.z),
                        Vector(maxs.x, mins.y, maxs.z), Vector(maxs.x, mins.y, mins.z))
                    render.DrawQuad(
                        Vector(maxs.x, maxs.y, mins.z), Vector(maxs.x, maxs.y, maxs.z),
                        Vector(mins.x, maxs.y, maxs.z), Vector(mins.x, maxs.y, mins.z))
                    render.DrawQuad(
                        Vector(mins.x, mins.y, mins.z), Vector(mins.x, maxs.y, mins.z),
                        Vector(mins.x, maxs.y, maxs.z), Vector(mins.x, mins.y, maxs.z))
                    render.DrawQuad(
                        Vector(maxs.x, mins.y, mins.z), Vector(maxs.x, mins.y, maxs.z),
                        Vector(maxs.x, maxs.y, maxs.z), Vector(maxs.x, maxs.y, mins.z))
                    render.SetBlend(1)
                end

                -- Zone name on top
                local center = (mins + maxs) / 2
                cam.Start3D2D(Vector(center.x, center.y, maxs.z + 2), Angle(0, 0, 0), 0.75)
                    surface.SetFont("TSettings_Title")
                    local zoneName = zone.name or "Zone"
                    local tw, th = surface.GetTextSize(zoneName)
                    local pad = 10
                    surface.SetDrawColor(40, 40, 40, 150)
                    surface.DrawRect(-tw/2 - pad, -th/2 - pad/2, tw + pad*2, th + pad)
                    draw.SimpleText(zoneName, "TSettings_Title", 0, 0, Color(140, 200, 50), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                cam.End3D2D()
            end
        end

        -- Draw current placement preview (yellow wireframe)
        if clientPlacing and clientCorner1 then
            local corner2 = LocalPlayer():EyePos()
            local mins = Vector(
                math.min(clientCorner1.x, corner2.x),
                math.min(clientCorner1.y, corner2.y),
                math.min(clientCorner1.z, corner2.z)
            )
            local maxs = Vector(
                math.max(clientCorner1.x, corner2.x),
                math.max(clientCorner1.y, corner2.y),
                math.max(clientCorner1.z, corner2.z)
            )
            render.SetColorMaterial()
            DrawWireBox(mins, maxs, Color(255, 200, 50, 255))
        end
    end)
end
