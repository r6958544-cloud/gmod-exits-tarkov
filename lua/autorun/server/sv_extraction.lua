--[[
    Tarkov Extraction Points - серверная часть
    Управляет данными точек эвакуации и синхронизирует их с клиентами
]]

util.AddNetworkString("TarkovExtract_SyncData")
util.AddNetworkString("TarkovExtract_UpdateData")
util.AddNetworkString("TarkovExtract_RequestData")
util.AddNetworkString("TarkovExtract_UpdateRaidSettings")

local DEFAULT_RAID_TIME = 10 * 60

local CONFIG_FILE = "tarkov_extraction_data.txt"

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

-- Raid metadata only. The visible extraction list is built from real map zones.
-- (Только метаданные рейда. Видимый список эвакуации строится по реальным зонам карты.)
local ExtractionData = {
    raidTime = DEFAULT_RAID_TIME, -- общее время рейда: 10 минут
    raidStartTime = 0, -- серверное время начала рейда
    extractions = {},
    destinations = {},
}

-- Загрузка данных из файла
local function LoadData()
    if file.Exists(CONFIG_FILE, "DATA") then
        local data = file.Read(CONFIG_FILE, "DATA")
        if data then
            local tbl = util.JSONToTable(data)
            if tbl then
                ExtractionData = tbl
            end
        end
    end
    -- Raid time is authoritative for the current server session, so reset it
    -- on load instead of trusting a persisted CurTime() value from an old run.
    -- (Время рейда определяется текущей серверной сессией, поэтому при загрузке
    -- оно сбрасывается, а не берётся из сохранённого значения CurTime() старого запуска.)
    ExtractionData.raidStartTime = CurTime()
    TarkovExtractRaidTime = ExtractionData.raidTime or DEFAULT_RAID_TIME
    TarkovExtractRaidStartTime = ExtractionData.raidStartTime
end

-- Сохранение данных в файл
local function SaveData()
    ExtractionData.raidTime = TarkovExtractRaidTime or ExtractionData.raidTime or DEFAULT_RAID_TIME
    ExtractionData.raidStartTime = TarkovExtractRaidStartTime or ExtractionData.raidStartTime or CurTime()
    file.Write(CONFIG_FILE, util.TableToJSON(ExtractionData, true))
end

local function GetCurrentExtractionData(ply)
    if TarkovExtractZone_BuildExtractionData then
        return TarkovExtractZone_BuildExtractionData(ply)
    end

    return {
        raidTime = TarkovExtractRaidTime or ExtractionData.raidTime or DEFAULT_RAID_TIME,
        raidStartTime = TarkovExtractRaidStartTime or ExtractionData.raidStartTime or CurTime(),
        serverTime = CurTime(),
        extractions = {},
        destinations = {},
    }
end

-- Синхронизация данных со всеми игроками
local function SyncToAll()
    for _, ply in ipairs(player.GetAll()) do
        local payload = util.TableToJSON(GetCurrentExtractionData(ply))
        net.Start("TarkovExtract_SyncData")
        net.WriteString(payload)
        net.Send(ply)
    end
end

-- Синхронизация данных с одним игроком
local function SyncToPlayer(ply)
    local payload = util.TableToJSON(GetCurrentExtractionData(ply))
    net.Start("TarkovExtract_SyncData")
    net.WriteString(payload)
    net.Send(ply)
end

LoadData()

-- Отправка данных при входе игрока
hook.Add("PlayerInitialSpawn", "TarkovExtract_SendData", function(ply)
    timer.Simple(2, function()
        if IsValid(ply) then
            SyncToPlayer(ply)
        end
    end)
end)

-- Администратор обновляет данные эвакуации
net.Receive("TarkovExtract_UpdateData", function(len, ply)
    if not IsValid(ply) then return end
    if not ply:IsSuperAdmin() then
        ply:ChatPrint(Tr("admin_only_modify_extraction_data", "[Tarkov Extract] Только суперадмины могут изменять данные эвакуации."))
        return
    end
    local data = net.ReadString()
    if data then
        local tbl = util.JSONToTable(data)
        if tbl then
            ExtractionData = tbl
            SaveData()
            SyncToAll()
        end
    end
end)

-- Игрок запрашивает данные (горячая перезагрузка)
net.Receive("TarkovExtract_RequestData", function(len, ply)
    if not IsValid(ply) then return end
    SyncToPlayer(ply)
end)

net.Receive("TarkovExtract_UpdateRaidSettings", function(len, ply)
    if not IsValid(ply) then return end
    if not ply:IsSuperAdmin() then
        ply:ChatPrint(Tr("admin_only_modify_raid_time", "[Tarkov Extract] Только суперадмины могут изменять время рейда."))
        return
    end

    local data = net.ReadString()
    local tbl = data and util.JSONToTable(data)
    if type(tbl) ~= "table" then return end

    local raidTime = math.Clamp(math.Round(tonumber(tbl.raidTime) or TarkovExtractRaidTime or DEFAULT_RAID_TIME), 10 * 60, 180 * 60)
    local shouldReset = tbl.reset == true
    local remainingTime = tonumber(tbl.remainingTime)

    TarkovExtractRaidTime = raidTime
    ExtractionData.raidTime = raidTime

    if shouldReset then
        TarkovExtractRaidStartTime = CurTime()
        ExtractionData.raidStartTime = TarkovExtractRaidStartTime
    elseif remainingTime then
        remainingTime = math.Clamp(math.Round(remainingTime), 60, raidTime)
        TarkovExtractRaidStartTime = CurTime() - (raidTime - remainingTime)
        ExtractionData.raidStartTime = TarkovExtractRaidStartTime
    end

    SaveData()
    SyncToAll()
end)

-- ==================== API для разработчиков ====================
TarkovExtractAPI = TarkovExtractAPI or {}

--[[
    Задать общее время рейда (в секундах)
    @param seconds: number
]]
function TarkovExtractAPI.SetRaidTime(seconds)
    TarkovExtractRaidTime = math.max(60, tonumber(seconds) or DEFAULT_RAID_TIME)
    TarkovExtractRaidStartTime = CurTime()
    ExtractionData.raidTime = TarkovExtractRaidTime
    ExtractionData.raidStartTime = TarkovExtractRaidStartTime
    SaveData()
    SyncToAll()
end

--[[
    Сбросить таймер рейда
]]
function TarkovExtractAPI.ResetRaid()
    TarkovExtractRaidStartTime = CurTime()
    ExtractionData.raidStartTime = TarkovExtractRaidStartTime
    SaveData()
    SyncToAll()
end

--[[
    Добавить точку эвакуации
    @param id: string уникальный ID
    @param name: string отображаемое название
    @param status: string "available"/"unknown"/"closed"
    @param timer: number секунды обратного отсчёта, 0 = без отсчёта, -1 = показывать ??:??:??
]]
function TarkovExtractAPI.AddExtraction(id, name, status, timer)
    table.insert(ExtractionData.extractions, {
        id = id,
        name = name,
        type = "extract",
        status = status or "available",
        timer = timer or 0
    })
    SaveData()
    SyncToAll()
end

--[[
    Добавить пункт назначения
    @param id: string уникальный ID
    @param name: string отображаемое название
    @param timer: number секунды обратного отсчёта
]]
function TarkovExtractAPI.AddDestination(id, name, timer)
    table.insert(ExtractionData.destinations, {
        id = id,
        name = name,
        type = "destination",
        timer = timer or 60
    })
    SaveData()
    SyncToAll()
end

--[[
    Очистить все точки эвакуации и пункты назначения
]]
function TarkovExtractAPI.ClearAll()
    ExtractionData.extractions = {}
    ExtractionData.destinations = {}
    SaveData()
    SyncToAll()
end

--[[
    Получить текущие данные эвакуации
    @return table
]]
function TarkovExtractAPI.GetData()
    return GetCurrentExtractionData()
end

print("[Tarkov Extraction] Server loaded")
