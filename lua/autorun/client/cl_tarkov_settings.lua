--[[
    Tarkov Series - Shared Settings UI
    Tarkov-style full-screen settings panel
    Shared across all Tarkov series addons
]]

local TSETTINGS = TSETTINGS or {}
TSETTINGS.Panel = nil
TSETTINGS.IsOpen = false
TSETTINGS.CurrentTab = 1

TarkovSettings = TarkovSettings or {}
TarkovSettingsLanguage = TarkovSettingsLanguage or TarkovSettings.Language or "cn"

local TARKOV_SETTINGS_CONFIG_FILE = "tarkov_series_settings.txt"

local function NormalizeTarkovLanguage(lang)
    lang = tostring(lang or "cn")
    if lang == "" then return "cn" end
    return lang
end

function TarkovSettingsGetLanguage()
    return NormalizeTarkovLanguage(TarkovSettingsLanguage or TarkovSettings.Language or "cn")
end

function TarkovSettingsSetLanguage(lang, saveToDisk)
    lang = NormalizeTarkovLanguage(lang)
    TarkovSettings.Language = lang
    TarkovSettingsLanguage = lang

    if DEPLOY and DEPLOY.Config then
        DEPLOY.Config.Language = lang
    end

    if saveToDisk ~= false then
        TarkovSettingsSaveConfig()
        TarkovSettings._LanguageConfigHasFile = true
    end

    hook.Run("TarkovSettingsLanguageChanged", lang)
end

function TarkovSettingsSaveConfig()
    file.Write(TARKOV_SETTINGS_CONFIG_FILE, util.TableToJSON({
        Language = TarkovSettings.Language,
        ExtractionRedeployDelay = TarkovSettings.ExtractionRedeployDelay or 10,
        RaidTimeMinutes = TarkovSettings.RaidTimeMinutes or 10,
    }, true))
    TarkovSettings._LanguageConfigHasFile = true
end

local function LoadTarkovSettingsConfig()
    if TarkovSettings._LanguageConfigLoaded then return end
    TarkovSettings._LanguageConfigLoaded = true

    local lang = DEPLOY and DEPLOY.Config and DEPLOY.Config.Language or "cn"
    local hasGlobalConfig = file.Exists(TARKOV_SETTINGS_CONFIG_FILE, "DATA")
    TarkovSettings._LanguageConfigHasFile = hasGlobalConfig

    if hasGlobalConfig then
        local data = file.Read(TARKOV_SETTINGS_CONFIG_FILE, "DATA")
        local tbl = data and util.JSONToTable(data)
        if tbl and tbl.Language then
            lang = tbl.Language
        end
        if tbl and tbl.ExtractionRedeployDelay ~= nil then
            TarkovSettings.ExtractionRedeployDelay = math.Clamp(math.Round(tonumber(tbl.ExtractionRedeployDelay) or 10), 3, 120)
        end
        if tbl and tbl.RaidTimeMinutes ~= nil then
            TarkovSettings.RaidTimeMinutes = math.Clamp(math.Round(tonumber(tbl.RaidTimeMinutes) or 10), 10, 180)
        end
    end

    TarkovSettings.ExtractionRedeployDelay = TarkovSettings.ExtractionRedeployDelay or 10
    TarkovSettings.RaidTimeMinutes = TarkovSettings.RaidTimeMinutes or 10
    TarkovExtractConfig = TarkovExtractConfig or {}
    TarkovExtractConfig.redeployDelay = TarkovSettings.ExtractionRedeployDelay
    TarkovSettingsSetLanguage(lang, false)
end

local function TarkovSettingsNetReady(name)
    return util and util.NetworkStringToID and util.NetworkStringToID(name) ~= 0
end

local function TarkovSettingsHasExtraction()
    if EXTRACT then return true end
    if isfunction(TarkovExtractZone_OpenToolSettings) and isfunction(TarkovExtractZone_OpenZoneList) then return true end
    return TarkovSettingsNetReady("TarkovExtract_UpdateRaidSettings")
end

local function TarkovSettingsHasDeploy()
    if DEPLOY then return true end
    local commands = concommand.GetTable and concommand.GetTable() or {}
    return commands.tarkov_deploy ~= nil
end

local function TarkovSettingsApplyRaidSettings(resetRaid)
    if not TarkovSettingsHasExtraction() or not TarkovSettingsNetReady("TarkovExtract_UpdateRaidSettings") then return end
    if not IsValid(LocalPlayer()) or not LocalPlayer():IsSuperAdmin() then return end

    local minutes = math.Clamp(math.Round(tonumber(TarkovSettings.RaidTimeMinutes) or 10), 10, 180)
    local payload = {
        raidTime = minutes * 60,
        reset = resetRaid == true,
    }

    pcall(function()
        local data = util.TableToJSON(payload)
        net.Start("TarkovExtract_UpdateRaidSettings")
        net.WriteString(data)
        net.SendToServer()
    end)
end

local function TarkovSettingsSetRaidRemaining(minutes)
    if not TarkovSettingsHasExtraction() or not TarkovSettingsNetReady("TarkovExtract_UpdateRaidSettings") then return end
    if not IsValid(LocalPlayer()) or not LocalPlayer():IsSuperAdmin() then return end

    local totalMinutes = math.Clamp(math.Round(tonumber(TarkovSettings.RaidTimeMinutes) or 10), 10, 180)
    minutes = math.Clamp(math.Round(tonumber(minutes) or totalMinutes), 1, totalMinutes)

    pcall(function()
        local data = util.TableToJSON({
            raidTime = totalMinutes * 60,
            remainingTime = minutes * 60,
        })
        net.Start("TarkovExtract_UpdateRaidSettings")
        net.WriteString(data)
        net.SendToServer()
    end)
end

LoadTarkovSettingsConfig()

TarkovPlayerData = TarkovPlayerData or {}
TarkovPlayerData.My = TarkovPlayerData.My or nil
TarkovPlayerData.All = TarkovPlayerData.All or {}

local function TarkovSettingsStoreMyPlayerData(data)
    if type(data) ~= "table" then return end
    TarkovPlayerData.My = data
    if DEPLOY then
        DEPLOY.MyPlayerData = data
    end
end

local function TarkovSettingsStoreAllPlayerData(data)
    if type(data) ~= "table" then return end
    TarkovPlayerData.All = data
    if DEPLOY then
        DEPLOY.AllPlayerData = data
        if DEPLOY.RefreshPlayerList then
            DEPLOY.RefreshPlayerList()
        end
    end
    if TarkovPlayerData.RefreshPlayerList then
        TarkovPlayerData.RefreshPlayerList()
    end
end

net.Receive("TarkovDeploy_PlayerData", function()
    local data = net.ReadString()
    local tbl = data and util.JSONToTable(data)
    if tbl then
        TarkovSettingsStoreMyPlayerData(tbl)
    end
end)

net.Receive("TarkovDeploy_RequestPlayerList", function()
    local data = net.ReadString()
    local tbl = data and util.JSONToTable(data)
    if tbl then
        TarkovSettingsStoreAllPlayerData(tbl)
    end
end)

hook.Add("InitPostEntity", "TarkovDeploy_RequestMyData", function()
    timer.Simple(3, function()
        if not TarkovSettingsNetReady("TarkovDeploy_RequestMyData") then return end
        pcall(function()
            net.Start("TarkovDeploy_RequestMyData")
            net.SendToServer()
        end)
    end)
end)

-- Localization table
local L = {
    cn = {
        title = "设置",
        tab_global = "全局设置",
        tab_deploy = "部署界面",
        tab_extraction = "撤离点",
        tab_summary = "结算界面",
        tab_death_effect = "死亡效果",
        tab_inertia = "惯性系统",
        language = "语言/Language",
        background = "背景图片",
        bg_art1 = "插画 1",
        bg_art2 = "插画 2",
        bg_map = "地图略缩图",
        gamename = "游戏名称",
        countdown = "倒计时时间:",
        blur = "背景模糊度:",
        logo_opacity = "Logo不透明度:",
        overlay = "背景遮盖层",
        show_on_join = "加入服务器时显示",
        show_on_respawn = "重生时显示",
        respawn_on_deploy = "重生并部署",
        not_subscribed = "你还未订阅此插件!",
        not_subscribed_en = "You have not subscribed to this addon!",
        subscribe = "前往订阅",
        no_settings = "无可用设置",
        no_settings_en = "No settings available",
        developing = "正在开发中!",
        developing_en = "Working In Progress!",
        btn_deploy = "部署",
        btn_deploy_all = "全体部署",
        btn_player_data = "玩家数据管理",
        player_manager_superadmin_only = "只有超级管理员可以管理玩家数据。",
        player_unknown = "未知",
        btn_set_extract = "设置撤离点",
        btn_tool_settings = "工具设置",
        btn_save = "保存",
        btn_close = "关闭",
        btn_back = "返回",
        btn_zone_list = "撤离点列表",
    },
    en = {
        title = "SETTINGS",
        tab_global = "Global",
        tab_deploy = "Deploy",
        tab_extraction = "Extraction",
        tab_summary = "Summary",
        tab_death_effect = "Death Effect",
        tab_inertia = "Inertia System",
        language = "Language",
        background = "Background",
        bg_art1 = "Art 1",
        bg_art2 = "Art 2",
        bg_map = "Map Thumbnail",
        gamename = "Game Name",
        countdown = "Countdown:",
        blur = "Blur Amount:",
        logo_opacity = "Logo Opacity:",
        overlay = "Background Overlay",
        show_on_join = "Show on Join",
        show_on_respawn = "Show on Respawn",
        respawn_on_deploy = "Respawn on Deploy",
        not_subscribed = "You have not subscribed!",
        not_subscribed_en = "",
        subscribe = "Subscribe",
        no_settings = "No settings available",
        no_settings_en = "",
        developing = "Working In Progress!",
        developing_en = "",
        btn_deploy = "Deploy",
        btn_deploy_all = "Deploy Everyone",
        btn_player_data = "Player Data",
        player_manager_superadmin_only = "Only superadmins can manage player data.",
        player_unknown = "Unknown",
        btn_set_extract = "Set Zone",
        btn_tool_settings = "Tool Settings",
        btn_save = "Save",
        btn_close = "Close",
        btn_back = "Back",
        btn_zone_list = "Zone List",
    }
}

-- Get current language text
local function GetLang()
    local lang = TarkovSettingsGetLanguage()
    -- Use local L table as base, override with global if available
    local result = L[lang] or L["cn"]
    if TarkovLang and TarkovLang[lang] then
        -- Merge: global overrides local
        local merged = {}
        for k, v in pairs(result) do merged[k] = v end
        for k, v in pairs(TarkovLang[lang]) do merged[k] = v end
        return merged
    end
    return result
end

local function TarkovSettingsText(key, fallback)
    local t = GetLang()
    local value = t[key]
    if value == nil or value == "" then
        return fallback or key
    end
    return value
end

-- Tab definitions with independent state
TSETTINGS.Tabs = {}

-- Update tab states based on detected addons
local function UpdateTabStates()
    local t = GetLang()
    TSETTINGS.Tabs = {
        { name = t.tab_global or "全局设置", id = "global", state = "available" },
        { name = t.tab_deploy, id = "deploy", state = "available" },
        { name = t.tab_extraction, id = "extraction", state = "not_subscribed" },
        { name = t.tab_summary, id = "summary", state = "developing" },
        { name = t.tab_death_effect or "死亡效果", id = "death_effect", state = "developing" },
        { name = t.tab_inertia or "惯性系统", id = "inertia", state = "developing" },
        { name = t.tab_about, id = "about", state = "available" },
    }
    -- Deploy: check for DEPLOY global
    if TarkovSettingsHasDeploy() then
        TSETTINGS.Tabs[2].state = "available"
    else
        TSETTINGS.Tabs[2].state = "not_subscribed"
    end
    -- Extraction: check for EXTRACT global
    if TarkovSettingsHasExtraction() then
        TSETTINGS.Tabs[3].state = "available"
    else
        TSETTINGS.Tabs[3].state = "not_subscribed"
    end
    -- Summary: always developing for now
    TSETTINGS.Tabs[4].state = "developing"
    -- Death effect / inertia: future modules
    TSETTINGS.Tabs[5].state = "developing"
    TSETTINGS.Tabs[6].state = "developing"
    -- About: always available
    TSETTINGS.Tabs[7].state = "available"
end

local function GetTabState(tabId)
    for _, tab in ipairs(TSETTINGS.Tabs) do
        if tab.id == tabId then
            return tab.state
        end
    end
    return "available"
end

local function BuildNotSubscribedTab(contentPanel, w, h, subscribeUrl)
    local msgPanel = vgui.Create("DPanel", contentPanel)
    msgPanel:SetPos(0, 0)
    msgPanel:SetSize(w, h)
    msgPanel.Paint = function(s, pw, ph)
        local tt = GetLang()
        draw.SimpleText(tt.not_subscribed, "TSettings_NotSubscribed", pw / 2, ph / 2 - 36, Color(120, 120, 120), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        if tt.not_subscribed_en ~= "" then
            draw.SimpleText(tt.not_subscribed_en, "TSettings_NotSubscribedEN", pw / 2, ph / 2, Color(120, 120, 120), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end

    local t = GetLang()
    local subBtnW, subBtnH = 306, 61
    CreateTabBarButton(contentPanel, (w - subBtnW) / 2, h / 2 + 30, subBtnW, subBtnH, t.subscribe, function()
        gui.OpenURL(subscribeUrl or "https://steamcommunity.com/workshop/browse/")
    end)
end

-- Fonts
surface.CreateFont("TSettings_Title", {
    font = "Bender",
    size = 48,
    weight = 700,
    antialias = true,
})

surface.CreateFont("TSettings_ConfirmTitle", {
    font = "Bender-Bold",
    size = 15,
    weight = 700,
    antialias = true,
})

surface.CreateFont("TSettings_ConfirmText", {
    font = "Bender-Bold",
    size = 18,
    weight = 700,
    antialias = true,
})

surface.CreateFont("TSettings_Tab", {
    font = "Bender",
    size = 24,
    weight = 600,
    antialias = true,
})

surface.CreateFont("TSettings_Label", {
    font = "Bender",
    size = 20,
    weight = 400,
    antialias = true,
})

surface.CreateFont("TSettings_Value", {
    font = "Bender",
    size = 19,
    weight = 500,
    antialias = true,
})

surface.CreateFont("TSettings_Section", {
    font = "Bender",
    size = 17,
    weight = 400,
    antialias = true,
})

surface.CreateFont("TSettings_SliderVal", {
    font = "Bender",
    size = 18,
    weight = 500,
    antialias = true,
})

surface.CreateFont("TSettings_NotSubscribed", {
    font = "Bender",
    size = 28,
    weight = 500,
    italic = true,
    antialias = true,
})

surface.CreateFont("TSettings_NotSubscribedEN", {
    font = "Bender",
    size = 22,
    weight = 400,
    italic = true,
    antialias = true,
})

surface.CreateFont("TSettings_Developing", {
    font = "Bender",
    size = 28,
    weight = 500,
    italic = true,
    antialias = true,
})

surface.CreateFont("TSettings_DevelopingEN", {
    font = "Bender",
    size = 22,
    weight = 400,
    italic = true,
    antialias = true,
})

surface.CreateFont("TSettings_Tooltip", {
    font = "Bender",
    size = 16,
    weight = 500,
    antialias = true,
})

surface.CreateFont("TSettings_TraderName", {
    font = "Bender",
    size = 36,
    weight = 700,
    antialias = true,
})

surface.CreateFont("TSettings_TraderContribution", {
    font = "Bender",
    size = 18,
    weight = 600,
    antialias = true,
})

surface.CreateFont("TSettings_TraderNameMini", {
    font = "Bender",
    size = 16,
    weight = 700,
    antialias = true,
})

surface.CreateFont("TSettings_TraderContributionMini", {
    font = "Bender",
    size = 15,
    weight = 600,
    antialias = true,
})

function TarkovUI_CreateSteamProfileCard(parent, x, y, w, h, options)
    options = options or {}

    local steamID64 = options.steamID64 or "76561198851798075"
    local roleText = options.roleText or (TarkovLangText and TarkovLangText("about_creator_role", "创建者") or "创建者")
    local useSteamName = options.useSteamName ~= false
    local profileName = useSteamName and "Loading..." or "Contributor"
    if isstring(options.displayName) and options.displayName ~= "" and options.displayName ~= roleText then
        profileName = options.displayName
    end

    local matGradient = Material("tarkov_extraction/image_diagonal_trader.png", "noclamp smooth")
    local matLoyaltyPanel = Material("tarkov_extraction/loyalty_level_panel.png", "noclamp smooth")
    local matLoyaltyKing = Material("tarkov_extraction/loyalty_king_new.png", "noclamp smooth")

    local scale = w / 124
    local photoPad = options.photoPad or math.max(4, math.Round(6 * scale))
    local nameH = options.nameH or math.max(18, math.Round(23 * scale))
    local roleH = options.roleH or math.max(20, math.Round(28 * scale))
    local border = options.border or 1
    local photoX = photoPad
    local photoY = photoPad
    local photoW = w - photoPad * 2
    local photoH = h - nameH - roleH - photoPad * 2
    local nameY = photoY + photoH

    local function ApplySteamName(name)
        if not isstring(name) then return end

        name = string.Trim(name)
        if name ~= "" and name ~= roleText and name ~= steamID64 then
            profileName = name
        end
    end

    local function ApplyCachedSteamName()
        if not steamworks or not steamworks.GetPlayerName then return end

        local ok, name = pcall(function()
            return steamworks.GetPlayerName(steamID64)
        end)
        if ok then ApplySteamName(name) end
    end

    local function FitTextToWidth(text, font, maxW)
        text = tostring(text or "")
        surface.SetFont(font)
        if select(1, surface.GetTextSize(text)) <= maxW then
            return text
        end

        for len = #text, 1, -1 do
            local clipped = string.sub(text, 1, len) .. "..."
            if select(1, surface.GetTextSize(clipped)) <= maxW then
                return clipped
            end
        end

        return "..."
    end

    if useSteamName and steamworks then
        ApplyCachedSteamName()
        if steamworks.RequestPlayerInfo then
            steamworks.RequestPlayerInfo(steamID64, function(name)
                ApplySteamName(name)
                ApplyCachedSteamName()
            end)
        end
    end

    local card = vgui.Create("DPanel", parent)
    card:SetPos(x, y)
    card:SetSize(w, h)
    card.Paint = function(s, cw, ch)
        surface.SetDrawColor(0, 0, 0, 245)
        surface.DrawRect(0, 0, cw, ch)

        if matGradient and not matGradient:IsError() then
            surface.SetDrawColor(255, 255, 255, 125)
            surface.SetMaterial(matGradient)
            local texW = matGradient:GetInt("$realwidth") or matGradient:Width() or 64
            local texH = matGradient:GetInt("$realheight") or matGradient:Height() or 64
            if texW <= 0 then texW = 64 end
            if texH <= 0 then texH = 64 end
            surface.DrawTexturedRect(0, 0, texW, texH)
        end

        surface.SetDrawColor(230, 230, 220, 255)
        surface.DrawOutlinedRect(photoX, photoY, photoW, photoH)
        surface.DrawOutlinedRect(photoX + 1, photoY + 1, photoW - 2, photoH - 2)

        surface.SetDrawColor(18, 18, 16, 255)
        surface.DrawRect(photoX + border, photoY + border, photoW - border * 2, photoH - border * 2)
        local avatarText = TarkovLangText and TarkovLangText("steam_avatar", "Steam\nAvatar") or "Steam\nAvatar"
        local avatarLine1, avatarLine2 = string.match(avatarText, "([^\n]*)\n?(.*)")
        draw.SimpleText(avatarLine1 or "Steam", "TSettings_TraderContributionMini", photoX + photoW / 2, photoY + photoH / 2 - 4, Color(100, 100, 90), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(avatarLine2 ~= "" and avatarLine2 or "Avatar", "TSettings_TraderContributionMini", photoX + photoW / 2, photoY + photoH / 2 + 4, Color(75, 75, 70), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        surface.SetDrawColor(40, 38, 36, 255)
        surface.DrawRect(photoX, nameY, photoW, nameH)
        surface.SetDrawColor(56, 54, 50, 255)
        surface.DrawRect(photoX, nameY, photoW, 1)

        local fittedName = FitTextToWidth(profileName, "TSettings_TraderNameMini", photoW - 8)
        draw.SimpleText(fittedName, "TSettings_TraderNameMini", cw / 2 + 1, nameY + nameH / 2 + 1, Color(0, 0, 0, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(fittedName, "TSettings_TraderNameMini", cw / 2, nameY + nameH / 2, Color(205, 201, 175), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        local fittedRole = FitTextToWidth(roleText, "TSettings_TraderContributionMini", cw - 8)
        draw.SimpleText(fittedRole, "TSettings_TraderContributionMini", cw / 2, ch - roleH / 2, Color(205, 201, 175), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    card.PaintOver = function()
        local crownBox = math.max(18, math.Round(22 * scale))
        if matLoyaltyPanel and not matLoyaltyPanel:IsError() then
            surface.SetDrawColor(255, 255, 255, 245)
            surface.SetMaterial(matLoyaltyPanel)
            surface.DrawTexturedRect(photoX + 4, photoY + 4, crownBox, crownBox)
        else
            surface.SetDrawColor(230, 235, 230, 245)
            surface.DrawRect(photoX + 4, photoY + 4, crownBox, crownBox)
        end

        if matLoyaltyKing and not matLoyaltyKing:IsError() then
            local crownSize = math.max(8, math.Round(10 * scale))
            surface.SetDrawColor(0, 0, 0, 230)
            surface.SetMaterial(matLoyaltyKing)
            surface.DrawTexturedRect(photoX + 10, photoY + 10, crownSize, crownSize)
        end
    end

    local avatar = vgui.Create("AvatarImage", card)
    if IsValid(avatar) then
        avatar:SetPos(photoX + border, photoY + border)
        avatar:SetSize(photoW - border * 2, photoH - border * 2)
        avatar:SetMouseInputEnabled(false)

        local function ApplySteamAvatar()
            if not IsValid(avatar) then return end
            pcall(function()
                avatar:SetSteamID(steamID64, 184)
            end)
        end

        ApplySteamAvatar()
        if steamworks and steamworks.RequestPlayerInfo then
            steamworks.RequestPlayerInfo(steamID64, function()
                timer.Simple(0, ApplySteamAvatar)
            end)
        end
    end

    return card
end

-- Global helper: create a fully styled Tarkov combo box (usable from other files)
-- @param parent: parent panel
-- @param x, y: position
-- @param w, h: size
-- @param choices: table of {label, value}
-- @param defaultVal: default display text
-- @param onChange: callback(value)
-- @return DComboBox
local function TarkovUI_AttachDropdownMenu(menu, control)
    if not IsValid(menu) or not IsValid(control) then return end

    local function RepositionMenu()
        if not IsValid(menu) or not IsValid(control) then return end

        local x, y = control:LocalToScreen(0, control:GetTall())
        local menuW = math.max(menu:GetWide(), control:GetWide())
        local menuH = menu:GetTall()

        x = math.Clamp(x, 0, math.max(0, ScrW() - menuW))
        if menuH > 0 and y + menuH > ScrH() then
            local _, topY = control:LocalToScreen(0, 0)
            y = math.max(0, topY - menuH)
        end

        menu:SetMinimumWidth(control:GetWide())
        menu:SetPos(x, y)
    end

    timer.Simple(0, RepositionMenu)
    menu.Think = function(mn)
        if not IsValid(control) then
            mn:Remove()
            return
        end
        RepositionMenu()
    end
end

function TarkovUI_StyledCombo(parent, x, y, w, h, choices, defaultVal, onChange)
    local combo = vgui.Create("DComboBox", parent)
    combo:SetPos(x, y)
    combo:SetSize(w, h or 28)
    combo:SetFont("TSettings_Value")
    combo:SetTextColor(Color(205, 201, 175))
    combo:SetContentAlignment(5)
    combo:SetTextInset(-18, 0)
    combo.Paint = function(s, cw, ch)
        draw.RoundedBox(2, 0, 0, cw, ch, Color(40, 40, 40, 255))
        surface.SetDrawColor(80, 80, 80)
        surface.DrawOutlinedRect(0, 0, cw, ch, 1)
        local matArrow = Material("tarkov_extraction/button_up.png", "noclamp smooth")
        if matArrow and not matArrow:IsError() then
            local arrowSize = 10
            local ax = cw - arrowSize - 8
            local ay = (ch - arrowSize) / 2
            surface.SetDrawColor(205, 201, 175, 255)
            surface.SetMaterial(matArrow)
            surface.DrawTexturedRectRotated(ax + arrowSize/2, ay + arrowSize/2, arrowSize, arrowSize, 180)
        end
    end

    local dropBtn = combo:GetChildren()[1]
    if IsValid(dropBtn) then
        dropBtn:SetVisible(false)
    end

    combo.OpenMenu = function(s, pControlOpener)
        if IsValid(s.Menu) then
            surface.PlaySound("tarkov_extraction/menu_dropdown.wav")
            s.Menu:Remove()
            s.Menu = nil
            return
        end

        surface.PlaySound("tarkov_extraction/menu_dropdown.wav")
        s.Menu = DermaMenu(false, s)
        s.Menu.OnRemove = function(mn)
            if s.Menu == mn then
                s.Menu = nil
            end
        end
        s.Menu.Paint = function(mn, mw, mh)
            surface.SetDrawColor(0, 0, 0, 255)
            surface.DrawRect(0, 0, mw, mh)
        end

        for i, choice in ipairs(choices) do
            local option = s.Menu:AddOption(choice.label, function()
                surface.PlaySound("tarkov_extraction/menu_dropdown_select.wav")
                s:SetValue(choice.label)
                s:SetText(choice.label)
                if s.OnSelect then
                    s:OnSelect(i, choice.label, choice.value)
                end
            end)
            option:SetFont("TSettings_Value")
            option:SetTextColor(Color(205, 201, 175))
            option:SetContentAlignment(5)
            option:SetTextInset(0, 0)
            option:SetIcon(nil)
            option:SetTall(h or 28)
            option.PerformLayout = function(op)
                op:SetTall(h or 28)
            end
            option.hoverFrac = 0
            option.Paint = function(op, ow, oh)
                if op:IsHovered() then
                    op.hoverFrac = math.min(1, op.hoverFrac + FrameTime() * 8)
                else
                    op.hoverFrac = math.max(0, op.hoverFrac - FrameTime() * 6)
                end
                local bgR = Lerp(op.hoverFrac, 0, 205)
                local bgG = Lerp(op.hoverFrac, 0, 201)
                local bgB = Lerp(op.hoverFrac, 0, 175)
                surface.SetDrawColor(bgR, bgG, bgB, 255)
                surface.DrawRect(0, 0, ow, oh)
                local tR = Lerp(op.hoverFrac, 205, 0)
                local tG = Lerp(op.hoverFrac, 201, 0)
                local tB = Lerp(op.hoverFrac, 175, 0)
                op:SetTextColor(Color(tR, tG, tB))
            end
        end

        local mx, my = s:LocalToScreen(0, s:GetTall())
        s.Menu:SetMinimumWidth(s:GetWide())
        s.Menu:Open(mx, my, false, s)
        TarkovUI_AttachDropdownMenu(s.Menu, s)
    end

    for _, choice in ipairs(choices) do
        combo:AddChoice(choice.label, choice.value)
    end
    combo:SetValue(defaultVal)
    combo.OnSelect = function(s, idx, val, data)
        if TSETTINGS and data ~= "_noop" then TSETTINGS:MarkDirty() end
        if onChange then onChange(data) end
    end

    return combo
end

local function BuildTarkovLanguageChoices()
    local langDefault = TarkovSettingsGetLanguage()
    local langDefaultLabel = langDefault
    local langChoices = {}

    if TarkovLang then
        local codes = {}
        for code in pairs(TarkovLang) do
            table.insert(codes, code)
        end
        table.sort(codes)

        for _, code in ipairs(codes) do
            local tbl = TarkovLang[code]
            local displayName = tbl._display_name or code
            table.insert(langChoices, { label = displayName, value = code })
            if code == langDefault then
                langDefaultLabel = displayName
            end
        end
    else
        langChoices = {
            { label = "中文", value = "cn" },
            { label = "English", value = "en" },
        }
        langDefaultLabel = (langDefault == "en") and "English" or "中文"
    end

    local t = GetLang()
    table.insert(langChoices, { label = t.language_support_welcome or "Language support welcome!", value = "_noop" })
    return langChoices, langDefaultLabel
end

local function ApplyTarkovLanguage(lang)
    if lang == "_noop" then return end

    TarkovSettingsSetLanguage(lang, true)

    if TSETTINGS and TSETTINGS.IsOpen then
        TSETTINGS.Saved = true
        TSETTINGS:Close()
        timer.Simple(0.05, function()
            TSETTINGS:Open()
        end)
    end
end

-- Helper: create a tarkov-style long bar tab button
-- @param parent: parent panel
-- @param x, y: position
-- @param w, h: size
-- @param text: button label
-- @param onClick: callback function
-- @return DButton
function CreateTabBarButton(parent, x, y, w, h, text, onClick)
    local btn = vgui.Create("DButton", parent)
    btn:SetPos(x, y)
    btn:SetSize(w, h)
    btn:SetText("")
    btn.hoverAlpha = 0
    btn.isActive = false

    btn.OnCursorEntered = function(s)
        surface.PlaySound("tarkov_extraction/button_over.wav")
    end

    btn.Paint = function(s, bw, bh)
        -- Fade in/out hover background
        if s:IsHovered() or s.isActive then
            s.hoverAlpha = math.min(255, s.hoverAlpha + FrameTime() * 1600)
        else
            s.hoverAlpha = math.max(0, s.hoverAlpha - FrameTime() * 1200)
        end

        -- Keep active tab background visible
        if s.isActive and not s:IsHovered() then
            s.hoverAlpha = 255
        end

        -- Draw background image when hovered/active
        if s.hoverAlpha > 0 then
            local matBtn = Material("tarkov_extraction/button_back_big.png", "noclamp smooth")
            if matBtn and not matBtn:IsError() then
                surface.SetDrawColor(255, 255, 255, s.hoverAlpha)
                surface.SetMaterial(matBtn)
                surface.DrawTexturedRect(0, 0, bw, bh)
            end
        end

        -- Text color: lerp between normal and black based on hover
        local lerpFrac = s.hoverAlpha / 255
        local r = Lerp(lerpFrac, 205, 0)
        local g = Lerp(lerpFrac, 201, 0)
        local b = Lerp(lerpFrac, 175, 0)
        draw.SimpleText(text, "TSettings_Tab", bw / 2, bh / 2, Color(r, g, b), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    btn.DoClick = function(s)
        surface.PlaySound("tarkov_extraction/button_click.wav")
        if onClick then onClick(s) end
    end

    return btn
end

local function TarkovSettingsUpdateLocalPlayerData(sid, key, value)
    if sid ~= LocalPlayer():SteamID() then return end
    TarkovPlayerData.My = TarkovPlayerData.My or {}
    TarkovPlayerData.My[key] = value
    if DEPLOY then
        DEPLOY.MyPlayerData = DEPLOY.MyPlayerData or {}
        DEPLOY.MyPlayerData[key] = value
    end
end

local function TarkovSettingsSendPlayerDataUpdate(sid, key, value)
    if not TarkovSettingsNetReady("TarkovDeploy_UpdatePlayerData") then return end
    pcall(function()
        net.Start("TarkovDeploy_UpdatePlayerData")
        net.WriteString(util.TableToJSON({ steamid = sid, [key] = value }))
        net.SendToServer()
    end)
end

function TarkovSettings_OpenPlayerManager()
    if IsValid(TarkovPlayerData.Panel) then
        TarkovPlayerData.Panel:Remove()
        TarkovPlayerData.Panel = nil
        return
    end

    if not IsValid(LocalPlayer()) or not LocalPlayer():IsSuperAdmin() then
        chat.AddText(Color(255, 100, 100), "[Tarkov UI] ", Color(255, 255, 255), TarkovSettingsText("player_manager_superadmin_only", "Only superadmins can manage player data."))
        return
    end

    local scrW, scrH = ScrW(), ScrH()
    local contentW = math.min(800, scrW * 0.55)
    local contentH = scrH * 0.75
    local contentX = (scrW - contentW) / 2
    local contentY = scrH * 0.12

    TarkovPlayerData.Panel = vgui.Create("DFrame")
    local pm = TarkovPlayerData.Panel
    pm:SetSize(scrW, scrH)
    pm:SetPos(0, 0)
    pm:SetTitle("")
    pm:SetDraggable(false)
    pm:ShowCloseButton(false)
    pm:MakePopup()

    pm.Paint = function(s, w, h)
        surface.SetDrawColor(15, 15, 15, 230)
        surface.DrawRect(0, 0, w, h)
    end

    pm.OnKeyCodePressed = function(s, key)
        if key == KEY_ESCAPE then
            pm:Remove()
            TarkovPlayerData.Panel = nil
        end
    end

    pm.OnRemove = function()
        TarkovPlayerData.Panel = nil
    end

    local titlePanel = vgui.Create("DPanel", pm)
    titlePanel:SetSize(contentW, 50)
    titlePanel:SetPos(contentX, contentY - 60)
    titlePanel.Paint = function(s, w, h)
        draw.SimpleText(TarkovSettingsText("player_manager_title", "Player Data"), "TSettings_Tab", w / 2, h / 2, Color(205, 201, 175), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    local contentPanel = vgui.Create("DScrollPanel", pm)
    contentPanel:SetPos(contentX, contentY)
    contentPanel:SetSize(contentW, contentH)
    contentPanel.Paint = function(s, w, h)
        surface.SetDrawColor(0, 0, 0, 180)
        surface.DrawRect(0, 0, w, h)
    end

    local closeOverlay = vgui.Create("DButton", pm)
    closeOverlay:SetPos(0, 0)
    closeOverlay:SetSize(scrW, scrH)
    closeOverlay:SetText("")
    closeOverlay:SetZPos(-1)
    closeOverlay.Paint = function() end
    closeOverlay.DoClick = function()
        pm:Remove()
        TarkovPlayerData.Panel = nil
    end

    local backBtnW = 210
    local backBtnH = 57
    local backY = contentY + contentH + 15
    CreateTabBarButton(pm, contentX, backY, backBtnW, backBtnH, TarkovSettingsText("btn_back", "Back"), function()
        pm:Remove()
        TarkovPlayerData.Panel = nil
        RunConsoleCommand("tarkov_settings")
    end)

    local function RefreshList()
        if not IsValid(contentPanel) then return end
        contentPanel:Clear()

        local allData = TarkovPlayerData.All or (DEPLOY and DEPLOY.AllPlayerData) or {}
        local onlineSIDs = {}
        for _, ply in ipairs(player.GetAll()) do
            onlineSIDs[ply:SteamID()] = ply:Nick()
        end

        local yPos = 15
        local entryW = contentW - 30
        local margin = 15

        for sid, pData in pairs(allData) do
            local isOnline = onlineSIDs[sid] ~= nil
            local displayName = isOnline and onlineSIDs[sid] or (pData.name or TarkovSettingsText("player_unknown", "Unknown"))

            local entry = vgui.Create("DPanel", contentPanel)
            entry:SetPos(margin, yPos)
            entry:SetSize(entryW, 150)
            entry.Paint = function(s, w, h)
                surface.SetDrawColor(30, 30, 30, 200)
                surface.DrawRect(0, 0, w, h)
                local statusColor = isOnline and Color(80, 200, 80) or Color(150, 150, 150)
                local statusText = isOnline and TarkovSettingsText("player_online", "Online") or TarkovSettingsText("player_offline", "Offline")
                draw.SimpleText(statusText, "TSettings_Label", 12, 10, statusColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                draw.SimpleText(displayName, "TSettings_Tab", 110, 8, Color(205, 201, 175), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                draw.SimpleText(sid, "TSettings_Section", 12, 34, Color(120, 120, 120), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            end

            local rowY = 58
            local ctrlH = 26
            local gap = 8
            local curX = 12

            local factionLabel = vgui.Create("DLabel", entry)
            factionLabel:SetPos(curX, rowY + 4)
            factionLabel:SetFont("TSettings_Label")
            factionLabel:SetTextColor(Color(205, 201, 175))
            factionLabel:SetText(TarkovSettingsText("player_faction", "Faction:"))
            factionLabel:SizeToContents()
            curX = curX + factionLabel:GetWide() + gap

            TarkovUI_StyledCombo(entry, curX, rowY, 90, ctrlH, {
                { label = "USEC", value = "USEC" },
                { label = "BEAR", value = "BEAR" },
                { label = "Scav", value = "Scav" },
            }, pData.faction or "USEC", function(data)
                TarkovSettingsSendPlayerDataUpdate(sid, "faction", data)
                TarkovSettingsUpdateLocalPlayerData(sid, "faction", data)
            end)
            curX = curX + 90 + gap * 2

            local battleLabel = vgui.Create("DLabel", entry)
            battleLabel:SetPos(curX, rowY + 4)
            battleLabel:SetFont("TSettings_Label")
            battleLabel:SetTextColor(Color(205, 201, 175))
            battleLabel:SetText(TarkovSettingsText("info_battle", "Battle") .. ":")
            battleLabel:SizeToContents()
            curX = curX + battleLabel:GetWide() + gap

            local battleEntry = vgui.Create("DTextEntry", entry)
            battleEntry:SetPos(curX, rowY)
            battleEntry:SetSize(50, ctrlH)
            battleEntry:SetFont("TSettings_Value")
            battleEntry:SetTextColor(Color(205, 201, 175))
            battleEntry:SetNumeric(true)
            battleEntry:SetValue(tostring(pData.battle or 1))
            battleEntry.Paint = function(s, tw, th)
                surface.SetDrawColor(40, 40, 40, 255)
                surface.DrawRect(0, 0, tw, th)
                surface.SetDrawColor(80, 80, 80)
                surface.DrawOutlinedRect(0, 0, tw, th, 1)
                s:DrawTextEntryText(Color(205, 201, 175), Color(100, 150, 200), Color(205, 201, 175))
            end
            local function SaveBattle()
                local val = math.Clamp(tonumber(battleEntry:GetValue()) or 1, 1, 100)
                battleEntry:SetValue(tostring(val))
                TarkovSettingsSendPlayerDataUpdate(sid, "battle", val)
                TarkovSettingsUpdateLocalPlayerData(sid, "battle", val)
            end
            battleEntry.OnEnter = SaveBattle
            battleEntry.OnLoseFocus = SaveBattle
            curX = curX + 50 + gap * 2

            local levelLabel = vgui.Create("DLabel", entry)
            levelLabel:SetPos(curX, rowY + 4)
            levelLabel:SetFont("TSettings_Label")
            levelLabel:SetTextColor(Color(205, 201, 175))
            levelLabel:SetText(TarkovSettingsText("player_level", "Level:"))
            levelLabel:SizeToContents()
            curX = curX + levelLabel:GetWide() + gap

            local levelEntry = vgui.Create("DTextEntry", entry)
            levelEntry:SetPos(curX, rowY)
            levelEntry:SetSize(50, ctrlH)
            levelEntry:SetFont("TSettings_Value")
            levelEntry:SetTextColor(Color(205, 201, 175))
            levelEntry:SetNumeric(true)
            levelEntry:SetValue(tostring(pData.level or 1))
            levelEntry.Paint = battleEntry.Paint
            local function SaveLevel()
                local val = math.Clamp(tonumber(levelEntry:GetValue()) or 1, 1, 70)
                levelEntry:SetValue(tostring(val))
                TarkovSettingsSendPlayerDataUpdate(sid, "level", val)
                TarkovSettingsUpdateLocalPlayerData(sid, "level", val)
            end
            levelEntry.OnEnter = SaveLevel
            levelEntry.OnLoseFocus = SaveLevel

            local rowY2 = rowY + 34
            curX = 12

            local timeLabel = vgui.Create("DLabel", entry)
            timeLabel:SetPos(curX, rowY2 + 4)
            timeLabel:SetFont("TSettings_Label")
            timeLabel:SetTextColor(Color(205, 201, 175))
            timeLabel:SetText(TarkovSettingsText("player_time", "Time:"))
            timeLabel:SizeToContents()
            curX = curX + timeLabel:GetWide() + gap

            local timeEntry = vgui.Create("DTextEntry", entry)
            timeEntry:SetPos(curX, rowY2)
            timeEntry:SetSize(60, ctrlH)
            timeEntry:SetFont("TSettings_Value")
            timeEntry:SetTextColor(Color(205, 201, 175))
            timeEntry:SetNumeric(true)
            timeEntry:SetValue(tostring(pData.time or 1))
            timeEntry.Paint = battleEntry.Paint
            local function SaveTime()
                local val = math.Clamp(tonumber(timeEntry:GetValue()) or 1, 1, 9999)
                timeEntry:SetValue(tostring(val))
                TarkovSettingsSendPlayerDataUpdate(sid, "time", val)
                TarkovSettingsUpdateLocalPlayerData(sid, "time", val)
            end
            timeEntry.OnEnter = SaveTime
            timeEntry.OnLoseFocus = SaveTime
            curX = curX + 60 + gap * 2

            local editionLabel = vgui.Create("DLabel", entry)
            editionLabel:SetPos(curX, rowY2 + 4)
            editionLabel:SetFont("TSettings_Label")
            editionLabel:SetTextColor(Color(205, 201, 175))
            editionLabel:SetText(TarkovSettingsText("player_edition", "Edition:"))
            editionLabel:SizeToContents()
            curX = curX + editionLabel:GetWide() + gap

            local editionData = {
                { value = "Standard", label = TarkovSettingsText("edition_standard", "Standard"), color = Color(205, 201, 175), icon = nil },
                { value = "Edge of Darkness", label = TarkovSettingsText("edition_eod", "Edge of Darkness"), color = Color(255, 215, 0), icon = "tarkov_deploy/edge_of_darkness.png" },
                { value = "The Unheard", label = TarkovSettingsText("edition_unheard", "The Unheard"), color = Color(100, 200, 220), icon = "tarkov_deploy/the_unheard.png" },
            }

            local currentEditionLabel = TarkovSettingsText("edition_standard", "Standard")
            local currentEditionColor = Color(205, 201, 175)
            local currentEditionIcon = nil
            for _, ed in ipairs(editionData) do
                if ed.value == (pData.edition or "Standard") then
                    currentEditionLabel = ed.label
                    currentEditionColor = ed.color
                    currentEditionIcon = ed.icon
                    break
                end
            end

            local editionCombo = vgui.Create("DButton", entry)
            editionCombo:SetPos(curX, rowY2)
            editionCombo:SetSize(240, ctrlH)
            editionCombo:SetText("")
            editionCombo.currentLabel = currentEditionLabel
            editionCombo.currentColor = currentEditionColor
            editionCombo.currentIcon = currentEditionIcon

            editionCombo.Paint = function(s, cw, ch)
                draw.RoundedBox(2, 0, 0, cw, ch, Color(40, 40, 40, 255))
                surface.SetDrawColor(80, 80, 80)
                surface.DrawOutlinedRect(0, 0, cw, ch, 1)

                local iconSize, iconVisualW, iconGap = 0, 0, 3
                if s.currentIcon then
                    iconSize = ch + 36
                    iconVisualW = iconSize * 0.6
                end
                surface.SetFont("TSettings_Value")
                local textW = select(1, surface.GetTextSize(s.currentLabel))
                local arrowSpace = 24
                local textCenterX = (cw - arrowSpace) / 2

                if s.currentIcon then
                    local iconMat = Material(s.currentIcon, "noclamp smooth")
                    if iconMat and not iconMat:IsError() then
                        surface.SetDrawColor(255, 255, 255, 255)
                        surface.SetMaterial(iconMat)
                        local textLeft = textCenterX - textW / 2
                        local iconX = textLeft - iconGap - iconVisualW - (iconSize - iconVisualW) / 2
                        surface.DrawTexturedRect(iconX, (ch - iconSize) / 2, iconSize, iconSize)
                    end
                end

                draw.SimpleText(s.currentLabel, "TSettings_Value", textCenterX, ch / 2, s.currentColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

                local matArrow = Material("tarkov_extraction/button_up.png", "noclamp smooth")
                if matArrow and not matArrow:IsError() then
                    local arrowSize = 10
                    surface.SetDrawColor(205, 201, 175, 255)
                    surface.SetMaterial(matArrow)
                    surface.DrawTexturedRectRotated(cw - arrowSize - 3, ch / 2, arrowSize, arrowSize, 180)
                end
            end

            editionCombo.DoClick = function(s)
                if IsValid(s.Menu) then
                    surface.PlaySound("tarkov_extraction/menu_dropdown.wav")
                    s.Menu:Remove()
                    s.Menu = nil
                    return
                end

                surface.PlaySound("tarkov_extraction/menu_dropdown.wav")
                local menu = DermaMenu(false, s)
                s.Menu = menu
                menu.OnRemove = function(mn)
                    if s.Menu == mn then
                        s.Menu = nil
                    end
                end
                menu.Paint = function(mn, mw, mh)
                    surface.SetDrawColor(0, 0, 0, 255)
                    surface.DrawRect(0, 0, mw, mh)
                end

                for _, ed in ipairs(editionData) do
                    local option = menu:AddOption(ed.label, function()
                        surface.PlaySound("tarkov_extraction/menu_dropdown_select.wav")
                        s.currentLabel = ed.label
                        s.currentColor = ed.color
                        s.currentIcon = ed.icon
                        TarkovSettingsSendPlayerDataUpdate(sid, "edition", ed.value)
                        TarkovSettingsUpdateLocalPlayerData(sid, "edition", ed.value)
                    end)
                    option:SetFont("TSettings_Value")
                    option:SetTextColor(ed.color)
                    option:SetContentAlignment(5)
                    option:SetTextInset(0, 0)
                    option:SetIcon(nil)
                    option:SetTall(32)
                    option.PerformLayout = function(op) op:SetTall(32) end
                    option.edColor = ed.color
                    option.edLabel = ed.label
                    option.edIcon = ed.icon
                    option.hoverFrac = 0
                    option.Paint = function(op, ow, oh)
                        if op:IsHovered() then
                            op.hoverFrac = math.min(1, op.hoverFrac + FrameTime() * 8)
                        else
                            op.hoverFrac = math.max(0, op.hoverFrac - FrameTime() * 6)
                        end
                        surface.SetDrawColor(Lerp(op.hoverFrac, 0, 60), Lerp(op.hoverFrac, 0, 60), Lerp(op.hoverFrac, 0, 60), 255)
                        surface.DrawRect(0, 0, ow, oh)

                        local iconSize, iconVisualW, iconGap = 0, 0, 3
                        if op.edIcon then
                            iconSize = oh + 36
                            iconVisualW = iconSize * 0.6
                        end

                        surface.SetFont("TSettings_Value")
                        local textW = select(1, surface.GetTextSize(op.edLabel))
                        local textCenterX = ow / 2

                        if op.edIcon then
                            local iconMat = Material(op.edIcon, "noclamp smooth")
                            if iconMat and not iconMat:IsError() then
                                surface.SetDrawColor(255, 255, 255, 255)
                                surface.SetMaterial(iconMat)
                                local textLeft = textCenterX - textW / 2
                                local iconX = textLeft - iconGap - iconVisualW - (iconSize - iconVisualW) / 2
                                surface.DrawTexturedRect(iconX, (oh - iconSize) / 2, iconSize, iconSize)
                            end
                        end

                        draw.SimpleText(op.edLabel, "TSettings_Value", textCenterX, oh / 2, op.edColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                        op:SetTextColor(Color(0, 0, 0, 0))
                    end
                end

                local mx, my = s:LocalToScreen(0, s:GetTall())
                menu:SetMinimumWidth(s:GetWide())
                menu:Open(mx, my, false, s)
                TarkovUI_AttachDropdownMenu(menu, s)
            end

            yPos = yPos + 160
        end

        if yPos == 15 then
            local noData = vgui.Create("DPanel", contentPanel)
            noData:SetPos(0, 0)
            noData:SetSize(contentW, 100)
            noData.Paint = function(s, w, h)
                draw.SimpleText(TarkovSettingsText("player_no_data", "No player data"), "TSettings_Label", w / 2, h / 2, Color(120, 120, 120), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end
    end

    TarkovPlayerData.RefreshPlayerList = RefreshList
    if DEPLOY then
        DEPLOY.RefreshPlayerList = RefreshList
        DEPLOY.PlayerManagerPanel = pm
        DEPLOY.OpenPlayerManager = function()
            TarkovSettings_OpenPlayerManager()
        end
    end

    if TarkovSettingsNetReady("TarkovDeploy_RequestPlayerList") then
        pcall(function()
            net.Start("TarkovDeploy_RequestPlayerList")
            net.SendToServer()
        end)
    else
        RefreshList()
    end
end

if DEPLOY then
    DEPLOY.OpenPlayerManager = function()
        TarkovSettings_OpenPlayerManager()
    end
end

concommand.Add("tarkov_players", function()
    TarkovSettings_OpenPlayerManager()
end)

function TSETTINGS:MarkDirty()
    self.Dirty = true
    self.Saved = false
end

function TSETTINGS:SaveAllSettings()
    if DEPLOY and DEPLOY.SaveConfig then
        if DEPLOY.CurrentBG then
            DEPLOY.Config.CurrentBG = DEPLOY.CurrentBG
        end
        DEPLOY:SaveConfig()
    end

    if TarkovSettingsSaveConfig then
        TarkovSettingsSaveConfig()
    end

    if TarkovSettingsApplyRaidSettings then
        TarkovSettingsApplyRaidSettings(false)
    end

    self.Dirty = false
    self.Saved = true
end

function TSETTINGS:RestoreBackups()
    if self.ConfigBackup and DEPLOY then
        DEPLOY.Config = table.Copy(self.ConfigBackup)
        if self.CurrentBGBackup then
            DEPLOY.CurrentBG = self.CurrentBGBackup
        end
        if DEPLOY.UpdateBG then DEPLOY.UpdateBG() end
        if DEPLOY.UpdateLogo then DEPLOY.UpdateLogo() end
    end

    if self.SettingsBackup then
        TarkovSettings = table.Copy(self.SettingsBackup)
        TarkovSettingsLanguage = self.LanguageBackup or TarkovSettings.Language or TarkovSettingsLanguage
        if DEPLOY and DEPLOY.Config then
            DEPLOY.Config.Language = TarkovSettingsLanguage
        end
    end

    if self.ExtractConfigBackup then
        TarkovExtractConfig = table.Copy(self.ExtractConfigBackup)
    end
end

function TSETTINGS:CloseWithoutPrompt(saveChanges)
    if saveChanges then
        self:SaveAllSettings()
    else
        self:RestoreBackups()
        self.Dirty = false
        self.Saved = false
    end

    self.IsOpen = false
    self.ConfigBackup = nil
    self.CurrentBGBackup = nil
    self.SettingsBackup = nil
    self.LanguageBackup = nil
    self.ExtractConfigBackup = nil

    if IsValid(self.ConfirmPanel) then
        self.ConfirmPanel:Remove()
    end
    self.ConfirmPanel = nil

    if IsValid(self.Panel) then
        self.Panel:Remove()
    end
    self.Panel = nil
    return true
end

function TSETTINGS:ShowUnsavedConfirm()
    if IsValid(self.ConfirmPanel) then return end
    local t = GetLang()
    surface.PlaySound("tarkov_extraction/menu_inspector_window_open.wav")

    local parent = IsValid(self.Panel) and self.Panel or nil
    local scrW, scrH = ScrW(), ScrH()
    local boxW, boxH = 446, 122
    local boxX, boxY = (scrW - boxW) / 2, (scrH - boxH) / 2
    local matCloseBg = Material("tarkov_extraction/close_button.png", "noclamp smooth")
    local matCloseX = Material("tarkov_extraction/close_window_x.png", "noclamp smooth")

    local overlay = vgui.Create("DPanel", parent)
    overlay:SetSize(scrW, scrH)
    overlay:SetPos(0, 0)
    overlay:SetMouseInputEnabled(true)
    overlay:SetKeyboardInputEnabled(true)
    overlay:MakePopup()
    overlay.Paint = function() end
    self.ConfirmPanel = overlay

    local dialog = vgui.Create("DPanel", overlay)
    dialog:SetSize(boxW, boxH)
    dialog:SetPos(boxX, boxY)
    dialog.Paint = function(s, w, h)
        surface.SetDrawColor(0, 0, 0, 245)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(205, 201, 175, 180)
        surface.DrawRect(0, 0, w, 1)
        surface.DrawRect(0, h - 1, w, 1)
        surface.DrawRect(0, 0, 1, h)
        surface.DrawRect(w - 1, 0, 1, h)
        surface.SetDrawColor(25, 27, 26, 255)
        surface.DrawRect(1, 1, w - 2, 23)
        draw.SimpleText(t.confirm_title or "确认", "TSettings_ConfirmTitle", 8, 12, Color(205, 201, 175), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(t.confirm_unsaved or "部分设置已改变。你想要保存它们吗？", "TSettings_ConfirmText", w / 2, 55, Color(205, 201, 175), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    local function ConfirmSave()
        surface.PlaySound("tarkov_extraction/button_click.wav")
        TSETTINGS:CloseWithoutPrompt(true)
    end

    local function ConfirmDiscard()
        surface.PlaySound("tarkov_extraction/button_click.wav")
        TSETTINGS:CloseWithoutPrompt(false)
    end

    local closeBtn = vgui.Create("DButton", dialog)
    closeBtn:SetSize(28, 18)
    closeBtn:SetPos(boxW - 31, 4)
    closeBtn:SetText("")
    closeBtn.Paint = function(s, w, h)
        if matCloseBg and not matCloseBg:IsError() then
            surface.SetDrawColor(255, 255, 255, s:IsHovered() and 255 or 220)
            surface.SetMaterial(matCloseBg)
            surface.DrawTexturedRect(0, 0, w, h)
        else
            surface.SetDrawColor(120, 25, 25, 240)
            surface.DrawRect(0, 0, w, h)
        end
        if matCloseX and not matCloseX:IsError() then
            surface.SetDrawColor(255, 255, 255, 245)
            surface.SetMaterial(matCloseX)
            surface.DrawTexturedRect((w - 10) / 2, (h - 10) / 2, 10, 10)
        else
            draw.SimpleText("×", "TSettings_ConfirmTitle", w / 2, h / 2, Color(235, 235, 235), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
    closeBtn.DoClick = function()
        surface.PlaySound("tarkov_extraction/menu_inspector_window_close.wav")
        if IsValid(TSETTINGS.ConfirmPanel) then
            TSETTINGS.ConfirmPanel:Remove()
        end
        TSETTINGS.ConfirmPanel = nil
    end

    CreateTabBarButton(dialog, 84, 72, 128, 48, t.confirm_yes or "是 [Y]", ConfirmSave)
    CreateTabBarButton(dialog, boxW - 212, 72, 128, 48, t.confirm_no or "否 [N]", ConfirmDiscard)

    overlay.OnKeyCodePressed = function(s, key)
        if key == KEY_Y then
            ConfirmSave()
        elseif key == KEY_N or key == KEY_ESCAPE then
            ConfirmDiscard()
        end
    end
end

-- Layout: label on left (left-aligned), controls on right (right-aligned)
local LAYOUT_GAP = 20
local LAYOUT_CONTROL_W = 220 -- fixed width for controls on the right

local function AttachOptionTooltip(label, description)
    if not IsValid(label) or not isstring(description) or description == "" then return end

    label:SetMouseInputEnabled(true)
    local tooltip

    local function RemoveTooltip()
        if IsValid(tooltip) then
            tooltip:Remove()
        end
        tooltip = nil
    end

    label.OnCursorEntered = function(s)
        RemoveTooltip()

        local root = IsValid(TSETTINGS.Panel) and TSETTINGS.Panel or s:GetParent()
        if not IsValid(root) then return end

        tooltip = vgui.Create("DPanel", root)
        tooltip:SetMouseInputEnabled(false)
        tooltip:SetKeyboardInputEnabled(false)

        local tooltipW = 360
        local borderColor = Color(205, 201, 175, 255)
        local textColor = Color(205, 201, 175, 255)

        local text = vgui.Create("DLabel", tooltip)
        text:SetPos(8, 7)
        text:SetWide(tooltipW - 16)
        text:SetFont("TSettings_Tooltip")
        text:SetTextColor(textColor)
        text:SetText(description)
        text:SetWrap(true)
        text:SetAutoStretchVertical(true)

        tooltip.Paint = function(tt, tw, th)
            surface.SetDrawColor(0, 0, 0, 255)
            surface.DrawRect(0, 0, tw, th)
            surface.SetDrawColor(borderColor)
            surface.DrawOutlinedRect(0, 0, tw, th, 1)
        end

        tooltip.Think = function(tt)
            if not IsValid(s) or not s:IsHovered() then
                RemoveTooltip()
                return
            end

            text:SizeToContentsY()
            local targetH = math.Clamp(text:GetTall() + 14, 36, 150)
            tt:SetSize(tooltipW, targetH)

            local sx, sy = gui.MousePos()
            sx = sx + 18
            sy = sy + 18
            local rx, ry = root:ScreenToLocal(sx, sy)
            local maxX = root:GetWide() - tooltipW - 12
            local maxY = root:GetTall() - targetH - 12

            rx = math.Clamp(rx, 12, math.max(12, maxX))
            if ry > maxY then
                ry = math.max(12, maxY)
            end

            tt:SetPos(rx, ry)
            tt:MoveToFront()
        end
    end

    label.OnCursorExited = RemoveTooltip
    label.OnRemove = RemoveTooltip
end

-- Helper: create a styled combo box row
local function CreateComboRow(parent, x, y, w, labelText, choices, defaultVal, onChange, description)
    local controlW = LAYOUT_CONTROL_W
    local controlX = x + w - controlW

    local label = vgui.Create("DLabel", parent)
    label:SetPos(x, y + 4)
    label:SetSize(w - controlW - LAYOUT_GAP, 24)
    label:SetFont("TSettings_Label")
    label:SetTextColor(Color(205, 201, 175))
    label:SetText(labelText)
    label:SetContentAlignment(4)
    AttachOptionTooltip(label, description)

    local combo = vgui.Create("DComboBox", parent)
    combo:SetPos(controlX, y)
    combo:SetSize(controlW, 28)
    combo:SetFont("TSettings_Value")
    combo:SetTextColor(Color(205, 201, 175))
    combo:SetContentAlignment(5)
    combo:SetTextInset(-18, 0)
    combo.Paint = function(s, cw, ch)
        draw.RoundedBox(2, 0, 0, cw, ch, Color(40, 40, 40, 255))
        surface.SetDrawColor(80, 80, 80)
        surface.DrawOutlinedRect(0, 0, cw, ch, 1)
        local matArrow = Material("tarkov_extraction/button_up.png", "noclamp smooth")
        if matArrow and not matArrow:IsError() then
            local arrowSize = 10
            local ax = cw - arrowSize - 8
            local ay = (ch - arrowSize) / 2
            surface.SetDrawColor(205, 201, 175, 255)
            surface.SetMaterial(matArrow)
            surface.DrawTexturedRectRotated(ax + arrowSize/2, ay + arrowSize/2, arrowSize, arrowSize, 180)
        end
    end

    local dropBtn = combo:GetChildren()[1]
    if IsValid(dropBtn) then
        dropBtn:SetVisible(false)
    end

    combo.OpenMenu = function(s, pControlOpener)
        if IsValid(s.Menu) then
            surface.PlaySound("tarkov_extraction/menu_dropdown.wav")
            s.Menu:Remove()
            s.Menu = nil
            return
        end

        surface.PlaySound("tarkov_extraction/menu_dropdown.wav")
        s.Menu = DermaMenu(false, s)
        s.Menu.OnRemove = function(mn)
            if s.Menu == mn then
                s.Menu = nil
            end
        end
        s.Menu.Paint = function(mn, mw, mh)
            surface.SetDrawColor(0, 0, 0, 255)
            surface.DrawRect(0, 0, mw, mh)
        end

        for i, choice in ipairs(choices) do
            local option = s.Menu:AddOption(choice.label, function()
                surface.PlaySound("tarkov_extraction/menu_dropdown_select.wav")
                s:SetValue(choice.label)
                s:SetText(choice.label)
                if s.OnSelect then
                    s:OnSelect(i, choice.label, choice.value)
                end
            end)
            option:SetFont("TSettings_Value")
            option:SetTextColor(Color(205, 201, 175))
            option:SetContentAlignment(5)
            option:SetTextInset(0, 0)
            option:SetIcon(nil)
            option:SetTall(28)
            option.PerformLayout = function(s)
                s:SetTall(28)
            end
            option.hoverFrac = 0
            option.Paint = function(op, ow, oh)
                if op:IsHovered() then
                    op.hoverFrac = math.min(1, op.hoverFrac + FrameTime() * 8)
                else
                    op.hoverFrac = math.max(0, op.hoverFrac - FrameTime() * 6)
                end
                local bgR = Lerp(op.hoverFrac, 0, 205)
                local bgG = Lerp(op.hoverFrac, 0, 201)
                local bgB = Lerp(op.hoverFrac, 0, 175)
                surface.SetDrawColor(bgR, bgG, bgB, 255)
                surface.DrawRect(0, 0, ow, oh)
                local tR = Lerp(op.hoverFrac, 205, 0)
                local tG = Lerp(op.hoverFrac, 201, 0)
                local tB = Lerp(op.hoverFrac, 175, 0)
                op:SetTextColor(Color(tR, tG, tB))
            end
        end

        local mx, my = s:LocalToScreen(0, s:GetTall())
        s.Menu:SetMinimumWidth(s:GetWide())
        s.Menu:Open(mx, my, false, s)
        TarkovUI_AttachDropdownMenu(s.Menu, s)
    end

    for _, choice in ipairs(choices) do
        combo:AddChoice(choice.label, choice.value)
    end
    combo:SetValue(defaultVal)
    combo.OnSelect = function(s, idx, val, data)
        if onChange then onChange(data) end
    end

    return combo
end

-- Helper: create a styled checkbox row
local function CreateCheckboxRow(parent, x, y, w, labelText, default, onChange, description)
    local matCheckbox = Material("tarkov_extraction/checkbox.png", "noclamp smooth")
    local matCheckmark = Material("tarkov_extraction/checkmark.png", "noclamp smooth")

    local boxSize = 18
    local controlX = w - LAYOUT_CONTROL_W

    local panel = vgui.Create("DPanel", parent)
    panel:SetPos(x, y)
    panel:SetSize(w, 24)
    panel.Paint = function() end

    local label = vgui.Create("DLabel", panel)
    label:SetPos(0, 2)
    label:SetSize(controlX - LAYOUT_GAP, 20)
    label:SetFont("TSettings_Label")
    label:SetTextColor(Color(205, 201, 175))
    label:SetText(labelText)
    label:SetContentAlignment(4)
    AttachOptionTooltip(label, description)

    local isChecked = default

    local btn = vgui.Create("DButton", panel)
    btn:SetPos(controlX + (LAYOUT_CONTROL_W - boxSize) / 2, 2)
    btn:SetSize(boxSize, boxSize)
    btn:SetText("")
    btn.Paint = function(s, bw, bh)
        if matCheckbox and not matCheckbox:IsError() then
            surface.SetDrawColor(255, 255, 255, 255)
            surface.SetMaterial(matCheckbox)
            surface.DrawTexturedRect(0, 0, bw, bh)
        end
        if isChecked and matCheckmark and not matCheckmark:IsError() then
            local texW = matCheckmark:GetInt("$realwidth") or matCheckmark:Width() or bw
            local texH = matCheckmark:GetInt("$realheight") or matCheckmark:Height() or bh
            if texW == 0 then texW = bw end
            if texH == 0 then texH = bh end
            local cx = (bw - texW) / 2
            local cy = (bh - texH) / 2
            surface.SetDrawColor(255, 255, 255, 255)
            surface.SetMaterial(matCheckmark)
            surface.DrawTexturedRect(cx, cy, texW, texH)
        end
    end
    btn.DoClick = function()
        isChecked = not isChecked
        surface.PlaySound("tarkov_extraction/menu_checkbox.wav")
        if TSETTINGS then TSETTINGS:MarkDirty() end
        if onChange then onChange(isChecked) end
    end

    return panel
end

-- Helper: create a styled slider row
local function CreateSliderRow(parent, x, y, w, labelText, minVal, maxVal, defaultVal, onChange, description, onCommit)
    local controlW = LAYOUT_CONTROL_W
    local valW = 50
    local sliderW = controlW - valW - LAYOUT_GAP
    local controlX = x + w - controlW

    local label = vgui.Create("DLabel", parent)
    label:SetPos(x, y + 2)
    label:SetSize(w - controlW - LAYOUT_GAP, 24)
    label:SetFont("TSettings_Label")
    label:SetTextColor(Color(205, 201, 175))
    label:SetText(labelText)
    label:SetContentAlignment(4)
    AttachOptionTooltip(label, description)

    local valEntry = vgui.Create("DTextEntry", parent)
    valEntry:SetPos(controlX + sliderW + LAYOUT_GAP, y + 2)
    valEntry:SetSize(valW, 24)
    valEntry:SetFont("TSettings_SliderVal")
    valEntry:SetTextColor(Color(205, 201, 175))
    valEntry:SetNumeric(true)
    valEntry:SetValue(tostring(defaultVal))
    valEntry:SetContentAlignment(5)
    valEntry.Paint = function(s, vw, vh)
        surface.SetDrawColor(30, 30, 30, 255)
        surface.DrawRect(0, 0, vw, vh)
        -- Draw text centered manually
        local txt = s:GetValue()
        if s:IsEditing() then
            s:DrawTextEntryText(Color(205, 201, 175), Color(100, 150, 200), Color(205, 201, 175))
        else
            draw.SimpleText(txt, "TSettings_SliderVal", vw / 2, vh / 2, Color(205, 201, 175), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end

    local slider = vgui.Create("DSlider", parent)
    slider:SetPos(controlX, y)
    slider:SetSize(sliderW, 25)
    slider:SetSlideX((defaultVal - minVal) / (maxVal - minVal))
    -- Hide default knob graphic
    if IsValid(slider.Knob) then
        slider.Knob.Paint = function() end
    end
    local totalSteps = maxVal - minVal
    slider.Paint = function(s, sw, sh)
        -- Inset track so knob has room at edges
        local pad = 6
        local trackW = sw - pad * 2

        -- Track background (dark gray, thin)
        draw.RoundedBox(1, pad, sh/2 - 1, trackW, 2, Color(30, 30, 30, 255))

        -- Tick marks
        if totalSteps <= 10 then
            for step = 0, totalSteps do
                local tx = pad + (step / totalSteps) * trackW
                surface.SetDrawColor(205, 201, 175, 255)
                surface.DrawRect(tx - 1, sh/2 - 1, 2, 2)
            end
        else
            surface.SetDrawColor(205, 201, 175, 255)
            surface.DrawRect(pad - 1, sh/2 - 1, 2, 2)
            surface.DrawRect(pad + trackW - 1, sh/2 - 1, 2, 2)
        end

        -- Knob (button_up.png displayed below the track)
        local matKnob = Material("tarkov_extraction/button_up.png", "noclamp smooth")
        local knobSize = 12
        local knobX = pad + s:GetSlideX() * trackW - knobSize / 2
        local knobY = sh/2 + 2
        if matKnob and not matKnob:IsError() then
            surface.SetDrawColor(255, 255, 255, 255)
            surface.SetMaterial(matKnob)
            surface.DrawTexturedRect(knobX, knobY, knobSize, knobSize)
        end
    end

    -- Snap to nearest step
    slider.OnValueChanged = function(s, xVal)
        local snapped = math.Round(xVal * totalSteps) / totalSteps
        if snapped ~= xVal then
            s:SetSlideX(snapped)
            return
        end
        local val = math.Round(minVal + snapped * totalSteps)
        valEntry:SetValue(tostring(val))
        if TSETTINGS then TSETTINGS:MarkDirty() end
        if onChange then onChange(val) end
    end
    local lastCommittedValue
    local function CommitSliderValue()
        if not onCommit then return end
        local val = math.Clamp(tonumber(valEntry:GetValue()) or minVal, minVal, maxVal)
        if lastCommittedValue == val then return end
        lastCommittedValue = val
        onCommit(val)
    end

    local oldSliderMouseReleased = slider.OnMouseReleased
    slider.OnMouseReleased = function(s, code)
        if oldSliderMouseReleased then
            oldSliderMouseReleased(s, code)
        end
        CommitSliderValue()
    end
    if IsValid(slider.Knob) then
        local oldKnobMouseReleased = slider.Knob.OnMouseReleased
        slider.Knob.OnMouseReleased = function(knob, code)
            if oldKnobMouseReleased then
                oldKnobMouseReleased(knob, code)
            else
                knob.Depressed = false
                knob:MouseCapture(false)
            end
            CommitSliderValue()
        end
    end

    -- Allow direct editing of the value
    local function ApplyEntryValue()
        local val = math.Clamp(tonumber(valEntry:GetValue()) or minVal, minVal, maxVal)
        valEntry:SetValue(tostring(val))
        slider:SetSlideX((val - minVal) / totalSteps)
        if TSETTINGS then TSETTINGS:MarkDirty() end
        if onChange then onChange(val) end
        if onCommit then onCommit(val) end
    end
    valEntry.OnEnter = function(s) ApplyEntryValue() end
    valEntry.OnLoseFocus = function(s) ApplyEntryValue() end

    return slider, valEntry
end

-- Build the "Deploy" tab content
local function BuildDeployTab(contentPanel, w, h)
    local state = GetTabState("deploy")
    if state == "not_subscribed" then
        BuildNotSubscribedTab(contentPanel, w, h, "https://steamcommunity.com/sharedfiles/filedetails/?id=3724531081")
        return
    end

    local cfg = DEPLOY and DEPLOY.Config or {}
    local t = GetLang()
    local y = 20
    local margin = 40
    local rowW = w - margin * 2
    local spacing = 40

    -- Background
    local bgNames = { t.bg_art1 or "Art 1", t.bg_art2 or "Art 2", t.bg_map or "Map" }
    local bgDefault = bgNames[cfg.CurrentBG or 1] or bgNames[1]
    CreateComboRow(contentPanel, margin, y, rowW, t.background, {
        { label = t.bg_art1 or "Art 1", value = 1 },
        { label = t.bg_art2 or "Art 2", value = 2 },
        { label = t.bg_map or "Map", value = 3 },
    }, bgDefault, function(val)
        if DEPLOY then
            DEPLOY.CurrentBG = val
            DEPLOY.Config.CurrentBG = val
            if DEPLOY.UpdateBG then DEPLOY.UpdateBG() end
        end
    end, t.desc_background)
    y = y + spacing

    -- Game name
    local gameNameLabel = vgui.Create("DLabel", contentPanel)
    gameNameLabel:SetPos(margin, y + 4)
    gameNameLabel:SetSize(rowW * 0.45, 24)
    gameNameLabel:SetFont("TSettings_Label")
    gameNameLabel:SetTextColor(Color(205, 201, 175))
    gameNameLabel:SetText(t.gamename or "Game Name")
    gameNameLabel:SetContentAlignment(4)
    AttachOptionTooltip(gameNameLabel, t.desc_gamename)

    local gameNameEntry = vgui.Create("DTextEntry", contentPanel)
    gameNameEntry:SetPos(margin + rowW - LAYOUT_CONTROL_W, y)
    gameNameEntry:SetSize(LAYOUT_CONTROL_W, 28)
    gameNameEntry:SetFont("TSettings_Value")
    gameNameEntry:SetTextColor(Color(205, 201, 175))
    gameNameEntry:SetValue(cfg.GameName or "")
    gameNameEntry:SetContentAlignment(5)
    gameNameEntry.Paint = function(s, ew, eh)
        surface.SetDrawColor(40, 40, 40, 255)
        surface.DrawRect(0, 0, ew, eh)
        surface.SetDrawColor(80, 80, 80)
        surface.DrawOutlinedRect(0, 0, ew, eh, 1)
        if s:IsEditing() then
            s:DrawTextEntryText(Color(205, 201, 175), Color(100, 150, 200), Color(205, 201, 175))
        else
            draw.SimpleText(s:GetValue(), "TSettings_Value", ew / 2, eh / 2, Color(205, 201, 175), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
    gameNameEntry.OnChange = function(s)
        if TSETTINGS then TSETTINGS:MarkDirty() end
        if DEPLOY then DEPLOY.Config.GameName = s:GetValue() end
    end
    y = y + spacing

    -- Countdown time
    CreateSliderRow(contentPanel, margin, y, rowW, t.countdown, 5, 60, cfg.CountdownTime or 10, function(val)
        if DEPLOY then DEPLOY.Config.CountdownTime = val end
    end, t.desc_countdown)
    y = y + spacing

    -- Blur amount
    CreateSliderRow(contentPanel, margin, y, rowW, t.blur, 0, 10, cfg.BlurAmount or 3, function(val)
        if DEPLOY then
            DEPLOY.Config.BlurAmount = val
            if DEPLOY.UpdateBG then DEPLOY.UpdateBG() end
        end
    end, t.desc_blur)
    y = y + spacing

    -- Logo opacity
    CreateSliderRow(contentPanel, margin, y, rowW, t.logo_opacity, 0, 100, cfg.LogoOpacity or 70, function(val)
        if DEPLOY then
            DEPLOY.Config.LogoOpacity = val
            if DEPLOY.UpdateLogo then DEPLOY.UpdateLogo() end
        end
    end, t.desc_logo_opacity)
    y = y + spacing

    -- Checkboxes
    CreateCheckboxRow(contentPanel, margin, y, rowW, t.overlay, cfg.OverlayEnabled ~= false, function(val)
        if DEPLOY then DEPLOY.Config.OverlayEnabled = val end
    end, t.desc_overlay)
    y = y + spacing

    CreateCheckboxRow(contentPanel, margin, y, rowW, t.show_on_join, cfg.ShowOnJoin ~= false, function(val)
        if DEPLOY then DEPLOY.Config.ShowOnJoin = val end
    end, t.desc_show_on_join)
    y = y + spacing

    CreateCheckboxRow(contentPanel, margin, y, rowW, t.show_on_respawn, cfg.ShowOnRespawn or false, function(val)
        if DEPLOY then DEPLOY.Config.ShowOnRespawn = val end
    end, t.desc_show_on_respawn)
    y = y + spacing

    CreateCheckboxRow(contentPanel, margin, y, rowW, t.respawn_on_deploy, cfg.RespawnOnDeploy or false, function(val)
        if DEPLOY then DEPLOY.Config.RespawnOnDeploy = val end
    end, t.desc_respawn_on_deploy)
    y = y + spacing + 20

    -- Action buttons (vertical, centered)
    local btnW = 300
    local btnH = 54
    local btnX = (rowW - btnW) / 2 + margin

    CreateTabBarButton(contentPanel, btnX, y, btnW, btnH, t.btn_deploy, function()
        if not TSETTINGS:Close() then return end
        if DEPLOY and DEPLOY.Toggle then
            DEPLOY:Toggle()
        else
            RunConsoleCommand("tarkov_deploy")
        end
    end)
    y = y + spacing

    CreateTabBarButton(contentPanel, btnX, y, btnW, btnH, t.btn_deploy_all, function()
        if not TSETTINGS:Close() then return end
        pcall(function()
            if not TarkovSettingsNetReady("TarkovDeploy_DeployAll") then return end
            net.Start("TarkovDeploy_DeployAll")
            net.SendToServer()
        end)
    end)
end

-- Build the "Global" tab content
local function BuildGlobalTab(contentPanel, w, h)
    local t = GetLang()
    local y = 20
    local margin = 40
    local rowW = w - margin * 2
    local spacing = 40

    local langChoices, langDefaultLabel = BuildTarkovLanguageChoices()
    CreateComboRow(contentPanel, margin, y, rowW, t.language_label or t.language or "Language/语言", langChoices, langDefaultLabel, ApplyTarkovLanguage, t.desc_language)
    y = y + spacing + 20

    if TarkovSettingsHasExtraction() then
        local serverRaidSeconds = EXTRACT and EXTRACT.LocalData and tonumber(EXTRACT.LocalData.raidTime)
        local defaultRaidMinutes = serverRaidSeconds and math.Round(serverRaidSeconds / 60) or 10
        local raidMinutes = math.Clamp(math.Round(tonumber(TarkovSettings.RaidTimeMinutes) or defaultRaidMinutes), 10, 180)
        TarkovSettings.RaidTimeMinutes = raidMinutes
        local setRaidMinutes = math.Clamp(math.Round(tonumber(TarkovSettings.SetRaidTimeMinutes) or raidMinutes), 1, raidMinutes)
        TarkovSettings.SetRaidTimeMinutes = setRaidMinutes

        CreateSliderRow(contentPanel, margin, y, rowW, t.raid_time or "战局时间(分钟):", 10, 180, raidMinutes, function(val)
            TarkovSettings.RaidTimeMinutes = val
            TarkovSettings.SetRaidTimeMinutes = math.Clamp(math.Round(tonumber(TarkovSettings.SetRaidTimeMinutes) or val), 1, val)
        end, t.desc_raid_time, function()
            TarkovSettingsApplyRaidSettings(false)
            if IsValid(contentPanel) then
                contentPanel:Clear()
                BuildGlobalTab(contentPanel, w, h)
            end
        end)
        y = y + spacing + 20
    end

    if TarkovSettingsHasExtraction() then
        local btnW = 300
        local btnH = 54
        local btnX = (rowW - btnW) / 2 + margin
        CreateTabBarButton(contentPanel, btnX, y, btnW, btnH, t.btn_reset_raid_time or "重设战局时间", function()
            TarkovSettingsApplyRaidSettings(true)
        end)
        y = y + spacing

        local raidMinutes = math.Clamp(math.Round(tonumber(TarkovSettings.RaidTimeMinutes) or 10), 10, 180)
        local setRaidMinutes = math.Clamp(math.Round(tonumber(TarkovSettings.SetRaidTimeMinutes) or raidMinutes), 1, raidMinutes)
        TarkovSettings.SetRaidTimeMinutes = setRaidMinutes
        CreateSliderRow(contentPanel, margin, y, rowW, t.set_raid_time or "设置战局时间(分钟):", 1, raidMinutes, setRaidMinutes, function(val)
            TarkovSettings.SetRaidTimeMinutes = val
        end, t.desc_set_raid_time)
        y = y + spacing

        CreateTabBarButton(contentPanel, btnX, y, btnW, btnH, t.btn_set_raid_time or "设置战局时间", function()
            TarkovSettingsSetRaidRemaining(TarkovSettings.SetRaidTimeMinutes)
        end)
        y = y + spacing
    end

    local btnW = 300
    local btnH = 54
    local btnX = (rowW - btnW) / 2 + margin
    CreateTabBarButton(contentPanel, btnX, y, btnW, btnH, t.btn_player_data, function()
        if not TSETTINGS:Close() then return end
        RunConsoleCommand("tarkov_players")
    end)
end

-- Build the "Extraction" tab content
local function BuildExtractionTab(contentPanel, w, h)
    local state = GetTabState("extraction")

    if state == "available" then
        local t = GetLang()
        local margin = 40
        local rowW = w - margin * 2
        local spacing = 40
        local y = 20

        -- Zone expand setting
        local cfg = TarkovExtractConfig or { expand = 50, grace = 0.3, redeployDelay = 10 }
        CreateSliderRow(contentPanel, margin, y, rowW, t.zone_expand or "Zone Expand:", 0, 200, cfg.expand or 50, function(val)
            if TarkovExtractConfig then TarkovExtractConfig.expand = val end
        end, t.desc_zone_expand)
        y = y + spacing

        -- Grace period setting
        CreateSliderRow(contentPanel, margin, y, rowW, t.zone_grace or "Grace (x0.1s):", 0, 30, math.floor((cfg.grace or 0.3) * 10), function(val)
            if TarkovExtractConfig then TarkovExtractConfig.grace = val * 0.1 end
        end, t.desc_zone_grace)
        y = y + spacing

        CreateSliderRow(contentPanel, margin, y, rowW, t.extraction_redeploy_delay or "Redeploy Delay After Extract:", 3, 120, cfg.redeployDelay or TarkovSettings.ExtractionRedeployDelay or 10, function(val)
            TarkovSettings.ExtractionRedeployDelay = val
            TarkovExtractConfig = TarkovExtractConfig or {}
            TarkovExtractConfig.redeployDelay = val
        end, t.desc_extraction_redeploy_delay)
        y = y + spacing + 20

        -- Three horizontal buttons
        local btnW = 180
        local btnH = 46
        local btnGap = 12
        local totalBtnW = btnW * 3 + btnGap * 2
        local btnStartX = (w - totalBtnW) / 2
        local btnY = y

        CreateTabBarButton(contentPanel, btnStartX, btnY, btnW, btnH, t.btn_set_extract, function()
            if not TSETTINGS:Close() then return end
            pcall(function()
                if not TarkovSettingsHasExtraction() or not TarkovSettingsNetReady("TarkovExtractZone_GiveTool") then return end
                net.Start("TarkovExtractZone_GiveTool")
                net.SendToServer()
            end)
        end)

        CreateTabBarButton(contentPanel, btnStartX + btnW + btnGap, btnY, btnW, btnH, t.btn_tool_settings, function()
            if not TSETTINGS:Close() then return end
            if isfunction(TarkovExtractZone_OpenToolSettings) then
                TarkovExtractZone_OpenToolSettings(true)
            end
        end)

        CreateTabBarButton(contentPanel, btnStartX + (btnW + btnGap) * 2, btnY, btnW, btnH, t.btn_zone_list or "Zone List", function()
            if not TSETTINGS:Close() then return end
            if isfunction(TarkovExtractZone_OpenZoneList) then
                TarkovExtractZone_OpenZoneList(true)
            end
        end)
    elseif state == "not_subscribed" then
        BuildNotSubscribedTab(contentPanel, w, h, "https://steamcommunity.com/sharedfiles/filedetails/?id=3730567414")
    elseif state == "developing" then
        local msgPanel = vgui.Create("DPanel", contentPanel)
        msgPanel:SetPos(0, 0)
        msgPanel:SetSize(w, h)
        msgPanel.Paint = function(s, pw, ph)
            local tt = GetLang()
            draw.SimpleText(tt.developing, "TSettings_Developing", pw / 2, ph / 2 - 20, Color(120, 120, 120), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            if tt.developing_en ~= "" then
                draw.SimpleText(tt.developing_en, "TSettings_DevelopingEN", pw / 2, ph / 2 + 16, Color(120, 120, 120), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end
    end
end

-- Build the "Summary" tab content
local function BuildSummaryTab(contentPanel, w, h)
    local state = GetTabState("summary")

    if state == "available" then
        -- Future: summary settings here
    elseif state == "developing" then
        local msgPanel = vgui.Create("DPanel", contentPanel)
        msgPanel:SetPos(0, 0)
        msgPanel:SetSize(w, h)
        msgPanel.Paint = function(s, pw, ph)
            local tt = GetLang()
            draw.SimpleText(tt.developing, "TSettings_Developing", pw / 2, ph / 2 - 20, Color(120, 120, 120), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            if tt.developing_en ~= "" then
                draw.SimpleText(tt.developing_en, "TSettings_DevelopingEN", pw / 2, ph / 2 + 16, Color(120, 120, 120), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end
    elseif state == "not_subscribed" then
        local msgPanel = vgui.Create("DPanel", contentPanel)
        msgPanel:SetPos(0, 0)
        msgPanel:SetSize(w, h)
        msgPanel.Paint = function(s, pw, ph)
            local tt = GetLang()
            draw.SimpleText(tt.not_subscribed, "TSettings_NotSubscribed", pw / 2, ph / 2 - 36, Color(120, 120, 120), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            if tt.not_subscribed_en ~= "" then
                draw.SimpleText(tt.not_subscribed_en, "TSettings_NotSubscribedEN", pw / 2, ph / 2, Color(120, 120, 120), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end

        local t = GetLang()
        local subBtnW, subBtnH = 306, 61
        CreateTabBarButton(contentPanel, (w - subBtnW) / 2, h / 2 + 30, subBtnW, subBtnH, t.subscribe, function()
            gui.OpenURL("https://steamcommunity.com/workshop/browse/")
        end)
    end
end

local function BuildDevelopingTab(contentPanel, w, h)
    local msgPanel = vgui.Create("DPanel", contentPanel)
    msgPanel:SetPos(0, 0)
    msgPanel:SetSize(w, h)
    msgPanel.Paint = function(s, pw, ph)
        local tt = GetLang()
        draw.SimpleText(tt.developing, "TSettings_Developing", pw / 2, ph / 2 - 20, Color(120, 120, 120), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        if tt.developing_en ~= "" then
            draw.SimpleText(tt.developing_en, "TSettings_DevelopingEN", pw / 2, ph / 2 + 16, Color(120, 120, 120), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
end

-- Build the "About" tab content
local function BuildAboutTab(contentPanel, w, h)
    local t = GetLang()
    local aboutPanel = vgui.Create("DPanel", contentPanel)
    aboutPanel:SetPos(0, 0)
    aboutPanel:SetSize(w, h)

    local textX = 40
    local cardW = math.Clamp(w * 0.197, 101, 124)
    local cardH = math.Clamp((h - 310) * 0.703, 144, 169)
    local cardGap = 20
    local cardX = (w - cardW * 4 - cardGap * 3) / 2
    local cardY = math.max(190, (h - cardH) / 2 + 60)

    aboutPanel.Paint = function(s, pw, ph)
        draw.SimpleText(t.about_addons_title or "Tarkov Series Addons", "TSettings_Tab", pw / 2, 28, Color(205, 201, 175), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

        local aboutText = t.about_body or "版本: 1.2.0\n作者: 滑稽没JJ\n感谢使用本系列插件!"
        draw.DrawText(aboutText, "TSettings_Label", pw / 2, 70, Color(170, 170, 170), TEXT_ALIGN_CENTER)
    end

    TarkovUI_CreateSteamProfileCard(aboutPanel, cardX, cardY, cardW, cardH, {
        steamID64 = "76561198851798075",
        displayName = "滑稽没JJ",
        roleText = t.about_creator_role or "创建者",
        useSteamName = false,
    })

    TarkovUI_CreateSteamProfileCard(aboutPanel, cardX + cardW + cardGap, cardY, cardW, cardH, {
        steamID64 = "76561199129391925",
        displayName = "Greent1m0",
        roleText = t.about_ru_translation_role or "俄语翻译",
        useSteamName = false,
    })

    TarkovUI_CreateSteamProfileCard(aboutPanel, cardX + (cardW + cardGap) * 2, cardY, cardW, cardH, {
        steamID64 = "76561199117185321",
        displayName = "POW",
        roleText = t.about_ko_translation_role or "韩语翻译",
        useSteamName = false,
    })

    TarkovUI_CreateSteamProfileCard(aboutPanel, cardX + (cardW + cardGap) * 3, cardY, cardW, cardH, {
        steamID64 = "76561199042844827",
        displayName = "Kona疏",
        roleText = t.about_tester_role or "测试",
        useSteamName = false,
    })
end

-- Main panel creation
function TSETTINGS:Open()
    if IsValid(self.Panel) then
        self:Close()
        return
    end

    self.IsOpen = true
    self.Saved = false
    self.Dirty = false

    -- Backup current config so we can restore on cancel
    if DEPLOY and DEPLOY.Config then
        self.ConfigBackup = table.Copy(DEPLOY.Config)
        self.CurrentBGBackup = DEPLOY.CurrentBG
    end
    self.SettingsBackup = table.Copy(TarkovSettings or {})
    self.LanguageBackup = TarkovSettingsLanguage
    self.ExtractConfigBackup = table.Copy(TarkovExtractConfig or {})

    UpdateTabStates()
    if self.CurrentTab < 1 or self.CurrentTab > #self.Tabs then
        self.CurrentTab = 1
    end
    local scrW, scrH = ScrW(), ScrH()

    self.Panel = vgui.Create("DFrame")
    self.Panel:SetSize(scrW, scrH)
    self.Panel:SetPos(0, 0)
    self.Panel:SetTitle("")
    self.Panel:SetDraggable(false)
    self.Panel:ShowCloseButton(false)
    self.Panel:MakePopup()

    local mainPanel = self.Panel

    -- Background
    mainPanel.Paint = function(s, w, h)
        surface.SetDrawColor(15, 15, 15, 230)
        surface.DrawRect(0, 0, w, h)
    end

    -- Content area dimensions
    local contentW = math.min(800, scrW * 0.55)
    local contentH = scrH * 0.75
    local contentX = (scrW - contentW) / 2
    local contentY = scrH * 0.12

    -- Settings icon material
    local matSettingsIcon = Material("tarkov_extraction/settings_icon.png", "noclamp smooth")

    -- Title area (centered)
    local titlePanel = vgui.Create("DPanel", mainPanel)
    titlePanel:SetSize(contentW, 80)
    titlePanel:SetPos(contentX, contentY - 90)
    titlePanel.Paint = function(s, w, h)
        local t = GetLang()
        local iconSize = 46
        local titleCenterY = 30
        local textFont = "TSettings_Title"
        surface.SetFont(textFont)
        local textW = select(1, surface.GetTextSize(t.title))
        local totalW = iconSize + 12 + textW
        local startX = (w - totalW) / 2

        -- Icon
        if matSettingsIcon and not matSettingsIcon:IsError() then
            surface.SetDrawColor(255, 255, 255, 220)
            surface.SetMaterial(matSettingsIcon)
            surface.DrawTexturedRect(startX, titleCenterY - iconSize / 2, iconSize, iconSize)
        end
        -- Title text
        draw.SimpleText(t.title, textFont, startX + iconSize + 12, titleCenterY, Color(205, 201, 175), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    -- Tab bar
    local tabBar = vgui.Create("DPanel", mainPanel)
    local baseTabCount = 5
    local tabW = contentW / baseTabCount
    local tabBarW = tabW * #self.Tabs
    tabBar:SetPos(contentX + (contentW - tabBarW) / 2, contentY)
    tabBar:SetSize(tabBarW, 46)
    tabBar.Paint = function() end

    -- Red separator line removed

    -- Content scroll panel
    local contentInset = 60
    local contentPanel = vgui.Create("DPanel", mainPanel)
    contentPanel:SetPos(contentX + contentInset, contentY + 55)
    contentPanel:SetSize(contentW - contentInset * 2, contentH - 55)
    contentPanel.Paint = function(s, w, h)
        surface.SetDrawColor(0, 0, 0, 230)
        surface.DrawRect(0, 0, w, h)
    end

    -- Tab buttons
    local tabButtons = {}

    local function SwitchTab(idx)
        TSETTINGS.CurrentTab = idx
        -- Clear content
        for _, child in ipairs(contentPanel:GetChildren()) do
            child:Remove()
        end
        -- Build new content
        local tab = self.Tabs[idx]
        local tabId = tab and tab.id or "global"
        if tabId == "global" then
            BuildGlobalTab(contentPanel, contentW - contentInset * 2, contentH - 55)
        elseif tabId == "deploy" then
            BuildDeployTab(contentPanel, contentW - contentInset * 2, contentH - 55)
        elseif tabId == "extraction" then
            BuildExtractionTab(contentPanel, contentW - contentInset * 2, contentH - 55)
        elseif tabId == "summary" then
            BuildSummaryTab(contentPanel, contentW - contentInset * 2, contentH - 55)
        elseif tabId == "death_effect" or tabId == "inertia" then
            BuildDevelopingTab(contentPanel, contentW - contentInset * 2, contentH - 55)
        elseif tabId == "about" then
            BuildAboutTab(contentPanel, contentW - contentInset * 2, contentH - 55)
        end
        -- Update tab visuals
        for i, btn in ipairs(tabButtons) do
            btn.isActive = (i == idx)
        end
    end

    for i, tab in ipairs(self.Tabs) do
        local btn = CreateTabBarButton(tabBar, (i - 1) * tabW, 0, tabW, 46, tab.name, function()
            SwitchTab(i)
        end)
        btn.isActive = (i == self.CurrentTab)
        tabButtons[i] = btn
    end

    -- Close button (ESC or click outside)
    mainPanel.OnKeyCodePressed = function(s, key)
        if key == KEY_ESCAPE then
            TSETTINGS:Close()
        end
    end

    -- Override Close to ensure save happens
    mainPanel.Close = function(s)
        TSETTINGS:Close()
    end

    -- Override OnRemove to catch any removal (restore if not saved)
    mainPanel.OnRemove = function(s)
        if TSETTINGS.IsOpen and not TSETTINGS.Saved then
            TSETTINGS:RestoreBackups()
        end
        TSETTINGS.IsOpen = false
        TSETTINGS.ConfigBackup = nil
        TSETTINGS.CurrentBGBackup = nil
        TSETTINGS.SettingsBackup = nil
        TSETTINGS.LanguageBackup = nil
        TSETTINGS.ExtractConfigBackup = nil
        TSETTINGS.Saved = false
        TSETTINGS.Dirty = false
        TSETTINGS.Panel = nil
    end

    -- Initialize first tab
    SwitchTab(self.CurrentTab)

    -- Bottom buttons (Close left, Save right)
    local t = GetLang()
    local bottomBtnW = 210
    local bottomBtnH = 57
    local bottomY = contentY + contentH + 15

    CreateTabBarButton(mainPanel, contentX + contentInset, bottomY, bottomBtnW, bottomBtnH, t.btn_close or "Close", function()
        TSETTINGS:Close()
    end)

    CreateTabBarButton(mainPanel, contentX + contentW - contentInset - bottomBtnW, bottomY, bottomBtnW, bottomBtnH, t.btn_save or "Save", function()
        TSETTINGS:SaveAllSettings()
    end)
end

function TSETTINGS:Close()
    if self.Dirty and not self.Saved then
        self:ShowUnsavedConfirm()
        return false
    end

    self:CloseWithoutPrompt(self.Saved == true)
    return true
end

function TSETTINGS:Toggle()
    if self.IsOpen then
        self:Close()
    else
        self:Open()
    end
end

-- Console command
concommand.Add("tarkov_settings", function()
    TSETTINGS:Toggle()
end)

-- Context menu entry. This lives in the shared settings UI so either addon
-- can provide the C-menu Tarkov UI button on its own.
list.Set("DesktopWindows", "TarkovDeploySettings", {
    title = "Tarkov UI",
    icon = "tarkov_extraction/sb_game_eft.png",
    init = function(icon, window)
        window:Remove()
        RunConsoleCommand("tarkov_settings")
    end
})

print("[Tarkov Settings] Shared settings UI loaded")
