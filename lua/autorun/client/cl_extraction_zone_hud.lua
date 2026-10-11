--[[
    Tarkov Extraction - Server-authoritative extraction HUD
    The server validates zones, conditions and completion. This file only draws
    the countdown state sent by the server.
]]

if not CLIENT then return end

TarkovExtractConfig = TarkovExtractConfig or {
    expand = 50,
    grace = 0.3,
    redeployDelay = 10,
}
TarkovExtractConfig.redeployDelay = TarkovExtractConfig.redeployDelay or 10

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

surface.CreateFont("TarkovExtractCountdown", {
    font = "Bender-Bold",
    size = 28,
    weight = 700,
    antialias = true,
})

surface.CreateFont("TarkovExtractCountdownSmall", {
    font = "Bender-Bold",
    size = 20,
    weight = 700,
    antialias = true,
})

surface.CreateFont("TarkovExtractRedeployNotice", {
    font = "Bender-Bold",
    size = 16,
    weight = 700,
    antialias = true,
})

local hudState = {
    active = false,
    type = "extract",
    name = "",
    remaining = 0,
    maxPlayers = 1,
    occupiedPlayers = 0,
    showOccupancy = false,
}

local hudAlpha = 0
local FADE_SPEED_IN = 2.5
local FADE_SPEED_OUT = 2.5

local lastReason = nil
local lastReasonTime = 0
local matExitPmcYes = Material("tarkov_extraction/icon_exit_pmc_yes.png", "noclamp smooth")
local matExitPmcYesMarathon = Material("tarkov_extraction/icon_exit_pmc_yes_marathon.png", "noclamp smooth")
local matExitPmcNo = Material("tarkov_extraction/icon_exit_pmc_no.png", "noclamp smooth")

local function ClearPostExtractProtection()
    timer.Remove("TarkovExtract_ClearPostExtractProtectionAfterDeploy")
    timer.Create("TarkovExtract_ClearPostExtractProtectionAfterDeploy", 0.35, 1, function()
        pcall(function()
            net.Start("TarkovExtract_ClearPostExtractProtection")
            net.SendToServer()
        end)
    end)
end

local function TryRegisterDeployCompleteProtectionClear()
    if TarkovDeployClientAPI and TarkovDeployClientAPI.OnDeployComplete then
        TarkovDeployClientAPI.OnDeployComplete("tarkov_extract_clear_post_extract_protection", ClearPostExtractProtection)
        timer.Remove("TarkovExtract_RegisterDeployProtectionClear")
        return true
    end
    return false
end

hook.Add("InitPostEntity", "TarkovExtract_RegisterDeployProtectionClear", function()
    if TryRegisterDeployCompleteProtectionClear() then return end
    timer.Create("TarkovExtract_RegisterDeployProtectionClear", 1, 0, TryRegisterDeployCompleteProtectionClear)
end)

timer.Simple(0, function()
    if TryRegisterDeployCompleteProtectionClear() then return end
    timer.Create("TarkovExtract_RegisterDeployProtectionClear", 1, 0, TryRegisterDeployCompleteProtectionClear)
end)

local extractEndEffect = {
    active = false,
    startTime = 0,
    redeployDelay = 10,
    fadeDuration = 1.2,
    notifyDelay = 3,
    deployOpened = false,
    notifySoundPlayed = false,
}

local function GetRedeployDelay()
    local settingsDelay = TarkovSettings and tonumber(TarkovSettings.ExtractionRedeployDelay)
    local configDelay = TarkovExtractConfig and tonumber(TarkovExtractConfig.redeployDelay)
    return math.Clamp(math.Round(settingsDelay or configDelay or 10), 3, 120)
end

local function StartExtractEndEffect(payload)
    local delay = GetRedeployDelay()
    local fadeDuration = math.max(0.1, tonumber(payload and payload.fadeDuration) or extractEndEffect.fadeDuration or 1.2)
    extractEndEffect.active = true
    extractEndEffect.startTime = CurTime()
    extractEndEffect.redeployDelay = delay
    extractEndEffect.fadeDuration = fadeDuration
    extractEndEffect.notifyDelay = 3
    extractEndEffect.deployOpened = false
    extractEndEffect.notifySoundPlayed = false

    timer.Remove("TarkovExtract_HideTransitionCover")
    timer.Remove("TarkovExtract_PlayExitSound")
    timer.Create("TarkovExtract_PlayExitSound", extractEndEffect.fadeDuration + 1, 1, function()
        if extractEndEffect.active then
            surface.PlaySound("tarkov_extraction/exit_yes.wav")
        end
    end)
    timer.Remove("TarkovExtract_OpenRedeploy")
    timer.Create("TarkovExtract_OpenRedeploy", fadeDuration + extractEndEffect.notifyDelay + delay, 1, function()
        extractEndEffect.deployOpened = true
        local commands = concommand.GetTable and concommand.GetTable() or {}
        local hasDeploy = DEPLOY or commands.tarkov_deploy
        if hasDeploy then
            RunConsoleCommand("tarkov_deploy")
        end
        timer.Remove("TarkovExtract_HideTransitionCover")
        timer.Create("TarkovExtract_HideTransitionCover", 0.75, 1, function()
            extractEndEffect.active = false
            if not hasDeploy then
                ClearPostExtractProtection()
            end
        end)
    end)
end

local function DrawRedeployNotifyBar(elapsed)
    local notifyElapsed = elapsed - extractEndEffect.fadeDuration - (extractEndEffect.notifyDelay or 3)
    if notifyElapsed < 0 then return end

    if not extractEndEffect.notifySoundPlayed then
        extractEndEffect.notifySoundPlayed = true
        surface.PlaySound("tarkov_extraction/message_notice.wav")
    end

    local notifyInTime = 0.3
    local notifyOutTime = 0.4
    local notifySlide = 30
    local outStart = math.max(notifyInTime, extractEndEffect.redeployDelay - notifyOutTime)
    local alphaFrac = 1
    local offsetY = 0

    if notifyElapsed < notifyInTime then
        local frac = math.Clamp(notifyElapsed / notifyInTime, 0, 1)
        alphaFrac = frac
        offsetY = (1 - frac) * notifySlide
    elseif notifyElapsed >= outStart then
        local frac = math.Clamp((notifyElapsed - outStart) / notifyOutTime, 0, 1)
        if frac >= 1 then return end
        alphaFrac = 1 - frac
        offsetY = frac * notifySlide
    end

    local remaining = math.max(0, math.ceil(extractEndEffect.redeployDelay - notifyElapsed))
    local message = Tr("hud_redeploy_notice", "Вы повторно развернётесь через %d сек. Удачи!", remaining)
    local scrW, scrH = ScrW(), ScrH()
    local notifW = 520
    local notifH = 28
    local alpha = math.floor(255 * alphaFrac)
    local nx = scrW - notifW
    local ny = scrH - notifH - 2 + offsetY
    local matAlert = Material("tarkov_extraction/notification_icon_alert_green.png", "noclamp smooth")

    surface.SetDrawColor(0, 0, 0, math.floor(alpha * 0.85))
    surface.DrawRect(nx, ny, notifW, notifH)

    if matAlert and not matAlert:IsError() then
        local iconSize = notifH - 4
        surface.SetDrawColor(255, 255, 255, alpha)
        surface.SetMaterial(matAlert)
        surface.DrawTexturedRect(nx + 2, ny + 2, iconSize, iconSize)
    end

    draw.SimpleText(message, "TarkovExtractRedeployNotice", nx + 30, ny + notifH / 2, Color(205, 201, 175, alpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end

net.Receive("TarkovExtract_ExtractState", function()
    local data = net.ReadString()
    local tbl = data and util.JSONToTable(data)
    if type(tbl) ~= "table" then return end

    if extractEndEffect.active and tbl.active == true then
        hudState.active = false
        hudState.remaining = 0
        hudAlpha = 0
        return
    end

    local wasActive = hudState.active == true
    hudState.active = tbl.active == true
    hudState.type = tbl.type or hudState.type or "extract"
    hudState.name = tbl.name or hudState.name or ""
    hudState.remaining = tonumber(tbl.remaining) or hudState.remaining or 0
    hudState.maxPlayers = math.max(1, math.floor(tonumber(tbl.maxPlayers) or hudState.maxPlayers or 1))
    hudState.occupiedPlayers = math.Clamp(math.floor(tonumber(tbl.occupiedPlayers) or hudState.occupiedPlayers or 0), 0, hudState.maxPlayers)
    hudState.showOccupancy = tbl.showOccupancy == true and hudState.maxPlayers > 1

    if not hudState.active then
        if tbl.reason == "left_zone" and wasActive then
            hudState.remaining = hudState.remaining or 0
        else
            hudState.remaining = 0
        end

        if tbl.reason and tbl.reason ~= "left_zone" then
            hudAlpha = 0
        end
    end

    if not hudState.active and tbl.reason and tbl.reason ~= "left_zone" and tbl.zoneId then
        local reasonKey = tostring(tbl.reason) .. ":" .. tostring(tbl.zoneId)
        if reasonKey ~= lastReason or CurTime() - lastReasonTime > 2 then
            lastReason = reasonKey
            lastReasonTime = CurTime()
            if EXTRACT and EXTRACT.ShowDeniedZone then
                EXTRACT:ShowDeniedZone(tbl.zoneId)
            end
        end
    end
end)

net.Receive("TarkovExtract_Complete", function()
    local data = net.ReadString()
    local tbl = data and util.JSONToTable(data) or {}

    hudState.active = false
    hudState.remaining = 0
    hudAlpha = 0
    StartExtractEndEffect(tbl)
end)

local function DrawOccupancyIcons(barX, barY, barW, barH, alpha)
    if not hudState.showOccupancy then return end
    local alphaFrac = math.Clamp(tonumber(alpha) or 1, 0, 1)
    local iconAlpha = math.Clamp(math.floor(255 * alphaFrac), 0, 255)

    local maxPlayers = math.floor(tonumber(hudState.maxPlayers) or 1)
    if maxPlayers <= 1 then return end

    local occupiedPlayers = math.Clamp(math.floor(tonumber(hudState.occupiedPlayers) or 0), 0, maxPlayers)
    local gap = 12
    local iconH = barH - 20
    local iconW = iconH * 0.8
    local totalW = iconW * maxPlayers + gap * (maxPlayers - 1)
    if totalW > barW then
        local scale = barW / totalW
        iconW = math.max(14, math.floor(iconW * scale))
        iconH = math.max(18, math.floor(iconH * scale))
        totalW = iconW * maxPlayers + gap * (maxPlayers - 1)
    end
    local startX = barX + (barW - totalW) / 2
    local iconY = barY - iconH - 24
    local padX = 16
    local padY = 10

    surface.SetDrawColor(0, 0, 0, iconAlpha)
    surface.DrawRect(startX - padX, iconY - padY, totalW + padX * 2, iconH + padY * 2)

    local activeYesMat = (hudState.type == "transit" or hudState.type == "destination") and matExitPmcYesMarathon or matExitPmcYes
    if not activeYesMat or activeYesMat:IsError() then
        activeYesMat = matExitPmcYes
    end

    for i = 1, maxPlayers do
        local mat = i <= occupiedPlayers and activeYesMat or matExitPmcNo
        if mat and not mat:IsError() then
            if mat.SetFloat then mat:SetFloat("$alpha", alphaFrac) end
            surface.SetDrawColor(255, 255, 255, iconAlpha)
            surface.SetMaterial(mat)
            surface.DrawTexturedRect(startX + (i - 1) * (iconW + gap), iconY, iconW, iconH)
            if mat.SetFloat then mat:SetFloat("$alpha", 1) end
        end
    end
end

hook.Add("PrePlayerDraw", "TarkovExtract_EndEffectPlayerFade", function(ply)
    if not extractEndEffect.active or ply ~= LocalPlayer() then return end
    local elapsed = CurTime() - extractEndEffect.startTime
    local fade = math.Clamp(elapsed / extractEndEffect.fadeDuration, 0, 1)
    render.SetBlend(1 - fade)
end)

hook.Add("PostPlayerDraw", "TarkovExtract_EndEffectPlayerFadeReset", function(ply)
    if not extractEndEffect.active or ply ~= LocalPlayer() then return end
    render.SetBlend(1)
end)

hook.Add("PreDrawViewModel", "TarkovExtract_EndEffectViewModelFade", function()
    if not extractEndEffect.active then return end
    local elapsed = CurTime() - extractEndEffect.startTime
    local fade = math.Clamp(elapsed / extractEndEffect.fadeDuration, 0, 1)
    render.SetBlend(1 - fade)
end)

hook.Add("PostDrawViewModel", "TarkovExtract_EndEffectViewModelFadeReset", function()
    if not extractEndEffect.active then return end
    render.SetBlend(1)
end)

hook.Add("Think", "TarkovExtract_ServerStateHUDThink", function()
    local dt = FrameTime()
    if hudState.active then
        hudAlpha = math.min(1, hudAlpha + dt * FADE_SPEED_IN)
    else
        hudAlpha = math.max(0, hudAlpha - dt * FADE_SPEED_OUT)
        if hudAlpha <= 0 then
            hudState.maxPlayers = 1
            hudState.occupiedPlayers = 0
            hudState.showOccupancy = false
        end
    end
end)

hook.Add("HUDPaint", "TarkovExtract_ServerStateHUD", function()
    if hudAlpha <= 0 then return end

    local a = hudAlpha
    local scrW, scrH = ScrW(), ScrH()
    local barW = 250
    local barH = 54
    local barX = (scrW - barW) / 2
    local barY = scrH * 0.75
    local isTransit = hudState.type == "transit"
    local barColor = isTransit and Color(255, 160, 40, math.floor(230 * a)) or Color(140, 200, 50, math.floor(230 * a))
    local label = isTransit and Tr("hud_transit_countdown", "Переход через: ") or Tr("hud_extract_countdown", "Эвакуация через: ")

    DrawOccupancyIcons(barX, barY, barW, barH, a)

    draw.RoundedBox(0, barX, barY, barW, barH, barColor)

    local matRunner = Material("tarkov_extraction/exit_status_runner.png", "noclamp smooth")
    local iconH = barH - 20
    local iconW = iconH * 0.8
    local iconGap = 5
    local startX = barX + 10

    if matRunner and not matRunner:IsError() then
        surface.SetDrawColor(255, 255, 255, math.floor(255 * a))
        surface.SetMaterial(matRunner)
        surface.DrawTexturedRect(startX, barY + (barH - iconH) / 2, iconW, iconH)
    end

    local countText = string.format("%.1f", math.max(0, hudState.remaining or 0))
    draw.SimpleText(label .. countText, "TarkovExtractCountdown", startX + iconW + iconGap + 10, barY + barH / 2, Color(0, 0, 0, math.floor(220 * a)), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end)

hook.Add("HUDPaint", "TarkovExtract_EndEffectOverlay", function()
    if not extractEndEffect.active then return end

    local elapsed = CurTime() - extractEndEffect.startTime
    local fade = math.Clamp(elapsed / extractEndEffect.fadeDuration, 0, 1)
    local scrW, scrH = ScrW(), ScrH()
    surface.SetDrawColor(0, 0, 0, math.floor(255 * fade))
    surface.DrawRect(0, 0, scrW, scrH)

    DrawRedeployNotifyBar(elapsed)
end)
