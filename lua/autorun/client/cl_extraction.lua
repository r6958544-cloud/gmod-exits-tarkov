--[[
    Tarkov Extraction Points - Client HUD
    Tarkov-style extraction point display
]]

EXTRACT = EXTRACT or {}
-- Display modes: 0=hidden, 1=timer peek (fade), 2=full list (animated)
EXTRACT.DisplayMode = 0
EXTRACT.ServerTimeOffset = EXTRACT.ServerTimeOffset or 0

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

-- Mode 1 fade animation
EXTRACT.FadeAlpha = 0
EXTRACT.FadeState = "hidden" -- "fadein", "visible", "fadeout", "hidden"
EXTRACT.FadeStart = 0
local FADE_IN_TIME = 0.4
local FADE_VISIBLE_TIME = 3
local FADE_OUT_TIME = 0.6

-- Mode 2 animation phases (open + close)
-- Open: timefade -> greenslide -> rowslide -> visible
-- Close: rowclose -> greenclose -> timeclose -> hidden
EXTRACT.Anim2Phase = "none"
EXTRACT.Anim2Start = 0
local ANIM2_TIMEFADE = 0.3
local ANIM2_GREENSLIDE = 0.6
local ANIM2_ROWSLIDE = 0.5
local ANIM2_VISIBLE = 6  -- stay visible for 6 seconds
local ANIM2_ROWCLOSE = 0.5
local ANIM2_GREENCLOSE = 0.6
local ANIM2_TIMECLOSE = 0.5

-- Easing functions
local function EaseOutCubic(t)
    t = t - 1
    return t * t * t + 1
end

local function EaseInCubic(t)
    return t * t * t
end

-- Register command first
concommand.Add("tarkov_extract", function()
    EXTRACT.DisplayMode = (EXTRACT.DisplayMode + 1) % 3
    local modes = { [0] = "Hidden", [1] = "Timer Only", [2] = "Full" }
    print("[Tarkov Extract] Mode: " .. modes[EXTRACT.DisplayMode])
    if EXTRACT.DisplayMode == 2 then
        EXTRACT.Anim2Phase = "timefade"
        EXTRACT.Anim2Start = CurTime()
    end
end)

print("[Tarkov Extraction] INIT START")

-- Extraction data
EXTRACT.LocalData = {
    raidTime = 10 * 60,
    raidStartTime = 0,
    extractions = {},
    destinations = {},
}

-- The O-key extraction list is server-authoritative because condition hints are
-- player-specific. Do not rebuild it from raw client zone data.

-- Font definitions
surface.CreateFont("ExtractHeaderBold", {
    font = "Bender",
    size = 25,
    weight = 700,
    antialias = true,
})

surface.CreateFont("ExtractHeaderTime", {
    font = "Bender",
    size = 30,
    weight = 700,
    antialias = true,
})

surface.CreateFont("ExtractRowBold", {
    font = "Bender",
    size = 20,
    weight = 700,
    antialias = true,
})

surface.CreateFont("ExtractRowName", {
    font = "Bender",
    size = 20,
    weight = 400,
    antialias = true,
})

surface.CreateFont("ExtractRowTime", {
    font = "Bender",
    size = 30,
    weight = 700,
    antialias = true,
})

surface.CreateFont("ExtractRowTimeUnknown", {
    font = "Bender",
    size = 25,
    weight = 700,
    antialias = true,
})

surface.CreateFont("ExtractConditionItalic", {
    font = "Bender",
    size = 18,
    weight = 400,
    italic = true,
    antialias = true,
})

-- Network
pcall(function()
    net.Receive("TarkovExtract_SyncData", function()
        local data = net.ReadString()
        if data then
            local tbl = util.JSONToTable(data)
            if tbl then
                EXTRACT.LocalData = tbl
                local serverTime = tonumber(tbl.serverTime)
                if serverTime then
                    EXTRACT.ServerTimeOffset = serverTime - CurTime()
                end
            end
        end
    end)
end)

hook.Add("InitPostEntity", "TarkovExtract_RequestData", function()
    timer.Simple(3, function()
        pcall(function()
            net.Start("TarkovExtract_RequestData")
            net.SendToServer()
        end)
    end)
end)

-- Format time as H:MM:SS
local function FormatTime(seconds)
    if seconds < 0 then return "??:??:??" end
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    return string.format("%d:%02d:%02d", h, m, s)
end

local function GetRowTimeDisplay(row, raidElapsed)
    local openTime = tonumber(row.openTime) or 0
    if openTime > 0 and raidElapsed < openTime then
        return FormatTime(openTime - raidElapsed), "ExtractRowTime", true
    end

    local closeTime = tonumber(row.closeTime) or 0
    if closeTime > 0 and raidElapsed < closeTime then
        local closeRemaining = closeTime - raidElapsed
        return FormatTime(closeRemaining), "ExtractRowTime", closeRemaining < 10 * 60
    end

    local rowTimer = tonumber(row.timer) or 0
    if rowTimer == 0 then return nil end
    if rowTimer == -1 then
        return "??:??:??", "ExtractRowTimeUnknown", false
    end

    return FormatTime(rowTimer), "ExtractRowTime", false
end

-- Icon material
local matFindPoint = Material("tarkov_extraction/icon_find_point.png", "noclamp smooth")

EXTRACT.FlashRows = EXTRACT.FlashRows or {}
EXTRACT.PendingFlashRows = EXTRACT.PendingFlashRows or {}

local function StartPendingFlashRows()
    if not EXTRACT.PendingFlashRows then return end

    for rowId in pairs(EXTRACT.PendingFlashRows) do
        EXTRACT.FlashRows[rowId] = CurTime()
        EXTRACT.PendingFlashRows[rowId] = nil
    end
end

local function RequestExtractionData()
    pcall(function()
        net.Start("TarkovExtract_RequestData")
        net.SendToServer()
    end)
end

function EXTRACT:OpenFullList()
    RequestExtractionData()

    if self.DisplayMode == 2 and (self.Anim2Phase == "visible" or self.Anim2Phase == "rowslide") then
        if self.Anim2Phase == "visible" then
            self.Anim2Start = CurTime()
        end
        return
    end

    self.DisplayMode = 2
    self.FadeState = "hidden"
    self.FadeAlpha = 0
    self.Anim2Phase = "timefade"
    self.Anim2Start = CurTime()
end

function EXTRACT:ShowDeniedZone(zoneId)
    if not zoneId or zoneId == "" then return end
    if self.DisplayMode == 2 and self.Anim2Phase == "visible" then
        self.FlashRows[zoneId] = CurTime()
    else
        self.PendingFlashRows[zoneId] = true
    end
    self:OpenFullList()
end

local function GetFlashAlpha(rowId, rowAlpha)
    if not rowId or not EXTRACT.FlashRows then return 0 end

    local startTime = EXTRACT.FlashRows[rowId]
    if not startTime then return 0 end

    local elapsed = CurTime() - startTime
    if elapsed < 0 then return 0 end

    local duration = 1.5
    if elapsed >= duration then
        EXTRACT.FlashRows[rowId] = nil
        return 0
    end

    local pulse = math.max(0, math.sin((elapsed / duration) * math.pi * 6))
    return math.floor(pulse * 230 * (rowAlpha / 255))
end

-- Main HUD Draw
local function DrawExtractionHUD()
    if EXTRACT.DisplayMode == 0 then return end

    local data = EXTRACT.LocalData
    if not data then return end

    local scrW, scrH = ScrW(), ScrH()

    -- Layout
    local panelW = math.max(380, scrW * 0.28)
    local rowGap = 3
    local timeW = 110
    local infoW = panelW - timeW - rowGap
    local headerH = 44
    local rowH = 44
    local conditionH = 24
    local startX = scrW - panelW - 16
    local startY = 16

    local numExtracts = #data.extractions
    local numDests = #data.destinations

    local function GetConditionDisplayText(row)
        if row.conditionKey then
            local args = istable(row.conditionArgs) and row.conditionArgs or {}
            local text = Tr(row.conditionKey, row.conditionText or "", unpack(args))
            if row.conditionKey ~= "condition_need_coop" and row.conditionOrder ~= nil then
                return Tr("condition_list_format", "%s - %s", tostring(row.conditionOrder), text)
            end
            return text
        end

        return isstring(row.conditionText) and row.conditionText or ""
    end

    local function HasConditionText(row)
        return GetConditionDisplayText(row) ~= ""
    end

    local function GetRowLabelColor(row, defaultColor, alpha)
        if row and row.status == "closed" then
            return Color(210, 45, 45, alpha)
        end
        return Color(defaultColor.r, defaultColor.g, defaultColor.b, alpha)
    end

    local function GetRowHeight(row)
        return rowH + (HasConditionText(row) and conditionH or 0)
    end

    local function GetListHeight()
        local totalH = 0
        local count = 0
        for _, ext in ipairs(data.extractions) do
            totalH = totalH + GetRowHeight(ext)
            count = count + 1
        end
        for _, dest in ipairs(data.destinations) do
            totalH = totalH + GetRowHeight(dest)
            count = count + 1
        end
        if count > 1 then
            totalH = totalH + rowGap * (count - 1)
        end
        return totalH
    end

    -- Raid timer value
    local serverNow = CurTime() + (EXTRACT.ServerTimeOffset or 0)
    local elapsed = serverNow - (data.raidStartTime or serverNow)
    local remaining = math.max(0, (data.raidTime or 600) - elapsed)
    local raidTimeStr = FormatTime(remaining)
    local raidTimeR, raidTimeG, raidTimeB = 255, 255, 255
    if remaining < 10 * 60 then
        raidTimeR, raidTimeG, raidTimeB = 210, 45, 45
    end

    -- ==================== MODE 1: Timer peek with fade ====================
    if EXTRACT.DisplayMode == 1 then
        local fadeElapsed = CurTime() - EXTRACT.FadeStart
        if EXTRACT.FadeState == "fadein" then
            EXTRACT.FadeAlpha = math.min(255, (fadeElapsed / FADE_IN_TIME) * 255)
            if fadeElapsed >= FADE_IN_TIME then
                EXTRACT.FadeState = "visible"
                EXTRACT.FadeStart = CurTime()
            end
        elseif EXTRACT.FadeState == "visible" then
            EXTRACT.FadeAlpha = 255
            if fadeElapsed >= FADE_VISIBLE_TIME then
                EXTRACT.FadeState = "fadeout"
                EXTRACT.FadeStart = CurTime()
            end
        elseif EXTRACT.FadeState == "fadeout" then
            EXTRACT.FadeAlpha = math.max(0, 255 - (fadeElapsed / FADE_OUT_TIME) * 255)
            if fadeElapsed >= FADE_OUT_TIME then
                EXTRACT.FadeState = "hidden"
                EXTRACT.FadeAlpha = 0
                EXTRACT.DisplayMode = 0
                return
            end
        end

        local a = math.floor(EXTRACT.FadeAlpha)
        local timeBarX = scrW - timeW - 16
        surface.SetDrawColor(20, 20, 20, math.floor(a * 200 / 255))
        surface.DrawRect(timeBarX, startY, timeW, headerH)
        draw.SimpleText(raidTimeStr, "ExtractHeaderTime", timeBarX + 10, startY + headerH / 2, Color(raidTimeR, raidTimeG, raidTimeB, a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        return
    end

    -- ==================== MODE 2: Full list with open/close animation ====================
    local animElapsed = CurTime() - EXTRACT.Anim2Start
    local timeAlpha = 255
    local greenProgress = 1  -- 0=hidden, 1=fully expanded
    local rowProgress = 1    -- 0=hidden behind header, 1=fully visible

    -- OPEN phases
    if EXTRACT.Anim2Phase == "timefade" then
        timeAlpha = math.min(255, (animElapsed / ANIM2_TIMEFADE) * 255)
        greenProgress = 0
        rowProgress = 0
        if animElapsed >= ANIM2_TIMEFADE then
            EXTRACT.Anim2Phase = "greenslide"
            EXTRACT.Anim2Start = CurTime()
        end
    elseif EXTRACT.Anim2Phase == "greenslide" then
        timeAlpha = 255
        greenProgress = EaseOutCubic(math.min(1, animElapsed / ANIM2_GREENSLIDE))
        rowProgress = 0
        if animElapsed >= ANIM2_GREENSLIDE then
            EXTRACT.Anim2Phase = "rowslide"
            EXTRACT.Anim2Start = CurTime()
        end
    elseif EXTRACT.Anim2Phase == "rowslide" then
        timeAlpha = 255
        greenProgress = 1
        rowProgress = EaseOutCubic(math.min(1, animElapsed / ANIM2_ROWSLIDE))
        if animElapsed >= ANIM2_ROWSLIDE then
            EXTRACT.Anim2Phase = "visible"
            EXTRACT.Anim2Start = CurTime()
            StartPendingFlashRows()
        end
    elseif EXTRACT.Anim2Phase == "visible" then
        timeAlpha = 255
        greenProgress = 1
        rowProgress = 1
        StartPendingFlashRows()
        if animElapsed >= ANIM2_VISIBLE then
            EXTRACT.Anim2Phase = "rowclose"
            EXTRACT.Anim2Start = CurTime()
        end
    -- CLOSE phases
    elseif EXTRACT.Anim2Phase == "rowclose" then
        timeAlpha = 255
        greenProgress = 1
        rowProgress = 1 - EaseInCubic(math.min(1, animElapsed / ANIM2_ROWCLOSE))
        if animElapsed >= ANIM2_ROWCLOSE then
            EXTRACT.Anim2Phase = "greenclose"
            EXTRACT.Anim2Start = CurTime()
        end
    elseif EXTRACT.Anim2Phase == "greenclose" then
        timeAlpha = 255
        greenProgress = 1 - EaseInCubic(math.min(1, animElapsed / ANIM2_GREENCLOSE))
        rowProgress = 0
        if animElapsed >= ANIM2_GREENCLOSE then
            EXTRACT.Anim2Phase = "timeclose"
            EXTRACT.Anim2Start = CurTime()
        end
    elseif EXTRACT.Anim2Phase == "timeclose" then
        timeAlpha = math.max(0, 255 - (animElapsed / ANIM2_TIMECLOSE) * 255)
        greenProgress = 0
        rowProgress = 0
        if animElapsed >= ANIM2_TIMECLOSE then
            EXTRACT.Anim2Phase = "none"
            EXTRACT.DisplayMode = 0
            return
        end
    else
        -- "done" or "none" (static full display)
        timeAlpha = 255
        greenProgress = 1
        rowProgress = 1
        StartPendingFlashRows()
    end

    local timeAlphaInt = math.floor(timeAlpha)

    -- Time bar (header right)
    local timeBarHeaderX = startX + infoW + rowGap
    surface.SetDrawColor(20, 20, 20, math.floor(timeAlphaInt * 200 / 255))
    surface.DrawRect(timeBarHeaderX, startY, timeW, headerH)
    draw.SimpleText(raidTimeStr, "ExtractHeaderTime", timeBarHeaderX + 10, startY + headerH / 2, Color(raidTimeR, raidTimeG, raidTimeB, timeAlphaInt), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

    -- Green bar (expands/contracts from the left edge of time bar)
    if greenProgress > 0 then
        local greenRightEdge = timeBarHeaderX - rowGap
        local currentWidth = infoW * greenProgress
        local greenCurrentX = greenRightEdge - currentWidth
        local greenAlpha = math.floor(greenProgress * 255)

        surface.SetDrawColor(140, 200, 50, greenAlpha)
        surface.DrawRect(greenCurrentX, startY, currentWidth, headerH)

        surface.SetDrawColor(120, 180, 40, math.floor(greenProgress * 80))
        surface.DrawRect(greenCurrentX, startY + headerH - 4, currentWidth, 4)

        -- Clip icon and text to green bar bounds
        render.SetScissorRect(greenCurrentX, startY, greenCurrentX + currentWidth, startY + headerH, true)

        local iconSize = 32
        local iconX = greenCurrentX + 6
        local iconY = startY + (headerH - iconSize) / 2
        if matFindPoint and not matFindPoint:IsError() then
            surface.SetDrawColor(255, 255, 255, greenAlpha)
            surface.SetMaterial(matFindPoint)
            surface.DrawTexturedRect(iconX, iconY, iconSize, iconSize)
        end

        draw.SimpleText(Tr("hud_find_extraction", "Find Extraction"), "ExtractHeaderBold", greenCurrentX + iconSize + 18, startY + headerH / 2, Color(0, 0, 0, greenAlpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        render.SetScissorRect(0, 0, 0, 0, false)
    end

    -- Rows (slide down/up as a whole block from header bottom edge)
    if rowProgress > 0 then
        local headerBottom = startY + headerH
        local listTotalH = GetListHeight()
        local finalListY = headerBottom + rowGap
        local startListY = headerBottom - listTotalH
        local currentListY = startListY + (finalListY - startListY) * rowProgress
        local rowAlpha = math.floor(rowProgress * 255)

        -- Clip everything above the header bottom
        render.SetScissorRect(startX, headerBottom, startX + panelW, scrH, true)

        local listOffsetY = 0
        for i, ext in ipairs(data.extractions) do
            local rowY = currentListY + listOffsetY
            local fullRowH = GetRowHeight(ext)
            local hasCondition = HasConditionText(ext)
            local flashAlpha = GetFlashAlpha(ext.id, rowAlpha)

            surface.SetDrawColor(20, 20, 20, math.floor(rowProgress * 200))
            surface.DrawRect(startX, rowY, infoW, fullRowH)
            if flashAlpha > 0 then
                surface.SetDrawColor(180, 35, 35, flashAlpha)
                surface.DrawRect(startX, rowY, infoW, fullRowH)
            end

            local label = Tr("hud_extract_label", "Extract %02d", i)
            draw.SimpleText(label, "ExtractRowBold", startX + 12, rowY + rowH / 2, GetRowLabelColor(ext, Color(255, 255, 255), rowAlpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            surface.SetFont("ExtractRowBold")
            local labelW = select(1, surface.GetTextSize(label))
            draw.SimpleText(ext.name, "ExtractRowName", startX + 12 + labelW + 8, rowY + rowH / 2, Color(170, 170, 170, rowAlpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            local timeBarX = startX + infoW + rowGap
            surface.SetDrawColor(20, 20, 20, math.floor(rowProgress * 200))
            surface.DrawRect(timeBarX, rowY, timeW, fullRowH)
            if flashAlpha > 0 then
                surface.SetDrawColor(180, 35, 35, flashAlpha)
                surface.DrawRect(timeBarX, rowY, timeW, fullRowH)
            end

            local timeStr, timeFont, timeWarning = GetRowTimeDisplay(ext, elapsed)
            if timeStr then
                local timeColor = timeWarning and Color(210, 45, 45, rowAlpha) or Color(255, 255, 255, rowAlpha)
                draw.SimpleText(timeStr, timeFont, timeBarX + 10, rowY + rowH / 2, timeColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end

            if hasCondition then
                local conditionY = rowY + rowH - 4
                draw.SimpleText(GetConditionDisplayText(ext), "ExtractConditionItalic", startX + 14, conditionY + conditionH / 2, Color(170, 170, 170, rowAlpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end

            listOffsetY = listOffsetY + fullRowH + rowGap
        end

        for i, dest in ipairs(data.destinations) do
            local rowY = currentListY + listOffsetY
            local fullRowH = GetRowHeight(dest)
            local hasCondition = HasConditionText(dest)
            local flashAlpha = GetFlashAlpha(dest.id, rowAlpha)

            surface.SetDrawColor(20, 20, 20, math.floor(rowProgress * 200))
            surface.DrawRect(startX, rowY, infoW, fullRowH)
            if flashAlpha > 0 then
                surface.SetDrawColor(180, 35, 35, flashAlpha)
                surface.DrawRect(startX, rowY, infoW, fullRowH)
            end

            local label = Tr("hud_destination_label", "Dest %02d", i)
            draw.SimpleText(label, "ExtractRowBold", startX + 12, rowY + rowH / 2, GetRowLabelColor(dest, Color(230, 145, 35), rowAlpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            surface.SetFont("ExtractRowBold")
            local labelW = select(1, surface.GetTextSize(label))
            draw.SimpleText(dest.name, "ExtractRowName", startX + 12 + labelW + 8, rowY + rowH / 2, Color(170, 170, 170, rowAlpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            local timeBarX = startX + infoW + rowGap
            surface.SetDrawColor(20, 20, 20, math.floor(rowProgress * 200))
            surface.DrawRect(timeBarX, rowY, timeW, fullRowH)
            if flashAlpha > 0 then
                surface.SetDrawColor(180, 35, 35, flashAlpha)
                surface.DrawRect(timeBarX, rowY, timeW, fullRowH)
            end

            local timeStr, timeFont, timeWarning = GetRowTimeDisplay(dest, elapsed)
            if timeStr then
                local timeColor = timeWarning and Color(210, 45, 45, rowAlpha) or Color(255, 255, 255, rowAlpha)
                draw.SimpleText(timeStr, timeFont, timeBarX + 10, rowY + rowH / 2, timeColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end

            if hasCondition then
                local conditionY = rowY + rowH - 4
                draw.SimpleText(GetConditionDisplayText(dest), "ExtractConditionItalic", startX + 14, conditionY + conditionH / 2, Color(170, 170, 170, rowAlpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end

            listOffsetY = listOffsetY + fullRowH + rowGap
        end

        render.SetScissorRect(0, 0, 0, 0, false)
    end
end

hook.Add("HUDPaint", "TarkovExtract_DrawHUD", DrawExtractionHUD)

-- O key: single press = fade in raid timer, double press = full animated list
local lastOPress = 0
local oWaitTimer = nil
local oKeyWasDown = false

hook.Add("Think", "TarkovExtract_Toggle", function()
    local isDown = input.IsKeyDown(KEY_O)

    if isDown and not oKeyWasDown then
        local now = CurTime()

        if now - lastOPress < 0.3 then
            -- Double press: trigger full list with animation
            RequestExtractionData()
            if oWaitTimer then
                timer.Remove("TarkovExtract_OWait")
                oWaitTimer = nil
            end

            -- If already in mode 2 and visible/done, skip (let auto-close handle it)
            if EXTRACT.DisplayMode == 2 then
                -- Do nothing, auto-close will handle it
            else
                EXTRACT.DisplayMode = 2
                -- If timer is already showing (mode 1), skip timefade, go straight to greenslide
                if EXTRACT.FadeState ~= "hidden" and EXTRACT.FadeAlpha > 200 then
                    EXTRACT.Anim2Phase = "greenslide"
                else
                    EXTRACT.Anim2Phase = "timefade"
                end
                EXTRACT.Anim2Start = CurTime()
            end
        else
            -- Single press: wait to confirm not double
            if oWaitTimer then
                timer.Remove("TarkovExtract_OWait")
            end
            oWaitTimer = true
            timer.Create("TarkovExtract_OWait", 0.3, 1, function()
                oWaitTimer = nil
                -- If already showing (mode 1), just reset the visible timer
                if EXTRACT.DisplayMode == 1 and EXTRACT.FadeState ~= "hidden" then
                    EXTRACT.FadeState = "visible"
                    EXTRACT.FadeStart = CurTime()
                    EXTRACT.FadeAlpha = 255
                elseif EXTRACT.DisplayMode ~= 2 then
                    -- Trigger fade in for mode 1
                    EXTRACT.DisplayMode = 1
                    EXTRACT.FadeState = "fadein"
                    EXTRACT.FadeStart = CurTime()
                    EXTRACT.FadeAlpha = 0
                end
            end)
        end

        lastOPress = now
    end

    oKeyWasDown = isDown
end)

print("[Tarkov Extraction] Client HUD loaded OK")
print("[Tarkov Extraction] Commands: tarkov_extract | O=peek timer | OO=full list")
