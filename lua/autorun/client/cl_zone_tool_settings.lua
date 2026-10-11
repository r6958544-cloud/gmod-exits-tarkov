--[[
    Tarkov Extraction Zone Tool - Settings & Zone List Panels
]]

-- Global zone storage (accessible from SWEP and panels)
TarkovExtractZones = TarkovExtractZones or {}

if CLIENT then
    local toolSettingsPanel = nil

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

    surface.CreateFont("TSettings_Tooltip", {
        font = "Bender",
        size = 16,
        weight = 500,
        antialias = true,
    })

    local ZONE_OPTION_DESCRIPTIONS = {}

    local function AttachZoneOptionTooltip(label, labelText, descKey)
        local description = descKey and Tr(descKey, "") or ZONE_OPTION_DESCRIPTIONS[labelText]
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

            local root = IsValid(toolSettingsPanel) and toolSettingsPanel or s:GetParent()
            if not IsValid(root) then return end

            tooltip = vgui.Create("DPanel", root)
            tooltip:SetMouseInputEnabled(false)
            tooltip:SetKeyboardInputEnabled(false)

            local tooltipW = 360
            local borderColor = Color(205, 201, 175, 255)

            local text = vgui.Create("DLabel", tooltip)
            text:SetPos(8, 7)
            text:SetWide(tooltipW - 16)
            text:SetFont("TSettings_Tooltip")
            text:SetTextColor(borderColor)
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

    -- Receive zone sync from server
    net.Receive("TarkovExtractZone_Sync", function()
        local data = net.ReadString()
        if data then
            local tbl = util.JSONToTable(data)
            if tbl then
                TarkovExtractZones = tbl
            end
        end
    end)

    -- Receive notification from server
    net.Receive("TarkovExtractZone_Notify", function()
        local payload = net.ReadString()
        local tbl = payload and util.JSONToTable(payload)
        if type(tbl) == "table" then
            if tbl.key then
                TarkovNotify(tbl.key, tbl.fallback, tbl.args)
            else
                TarkovNotify(tbl.text or "")
            end
        else
            TarkovNotify(payload or "")
        end
    end)

    local function SendZoneEdit(action, index, extra)
        local payload = extra or {}
        payload.action = action
        payload.index = index
        local data = util.TableToJSON(payload)
        net.Start("TarkovExtractZone_Edit")
        net.WriteString(data)
        net.SendToServer()
    end

    local function ResolveNotificationText(notif)
        if notif and notif.key then
            return Tr(notif.key, notif.fallback or "", unpack(istable(notif.args) and notif.args or {}))
        end
        return notif and notif.text or ""
    end
    TarkovResolveNotificationText = ResolveNotificationText

    -- Global notification function for easy calling
    -- Usage: TarkovNotify("Your message here") or TarkovNotify("language_key", "fallback %s", {"arg"})
    function TarkovNotify(textOrKey, fallback, args)
        if not TarkovZoneNotifications then
            TarkovZoneNotifications = {}
        end
        table.insert(TarkovZoneNotifications, 1, {
            text = fallback == nil and tostring(textOrKey or "") or nil,
            key = fallback ~= nil and tostring(textOrKey or "") or nil,
            fallback = fallback,
            args = istable(args) and args or {},
            startTime = CurTime(),
            state = "in"
        })
        surface.PlaySound("tarkov_extraction/message_notice.wav")
    end

    -- Global notification rendering (visible regardless of held weapon)
    hook.Add("HUDPaint", "TarkovExtract_GlobalNotify", function()
        if not TarkovZoneNotifications or #TarkovZoneNotifications == 0 then return end

        -- Skip rendering here if the zone tool panel is visible (it renders its own)
        local ply = LocalPlayer()
        local wep = IsValid(ply) and ply:GetActiveWeapon()
        if IsValid(wep) and wep:GetClass() == "tarkov_zone_tool" then return end

        local scrW, scrH = ScrW(), ScrH()
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

            nalpha = math.floor(nalpha)
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

                draw.SimpleText(ResolveNotificationText(notif), "TarkovKeyHint", nx + 30, ny + notifH / 2, Color(205, 201, 175, nalpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
        end

        for _, idx in ipairs(removeList) do
            table.remove(TarkovZoneNotifications, idx)
        end
    end)

    -- ==================== Error Notification (red warning style) ====================
    -- Usage: TarkovNotifyError("Your error message here") or TarkovNotifyError("language_key", "fallback %s", {"arg"})
    TarkovErrorNotifications = TarkovErrorNotifications or {}

    function TarkovNotifyError(textOrKey, fallback, args)
        if not TarkovErrorNotifications then
            TarkovErrorNotifications = {}
        end
        table.insert(TarkovErrorNotifications, 1, {
            text = fallback == nil and tostring(textOrKey or "") or nil,
            key = fallback ~= nil and tostring(textOrKey or "") or nil,
            fallback = fallback,
            args = istable(args) and args or {},
            startTime = CurTime(),
            state = "in"
        })
        surface.PlaySound("tarkov_extraction/error_message.wav")
    end

    -- Global error notification rendering
    hook.Add("HUDPaint", "TarkovExtract_GlobalErrorNotify", function()
        if not TarkovErrorNotifications or #TarkovErrorNotifications == 0 then return end

        local scrW, scrH = ScrW(), ScrH()
        local notifW = 520
        local notifH = 28
        -- Stack above normal notifications
        local normalCount = (TarkovZoneNotifications and #TarkovZoneNotifications) or 0
        local notifBaseY = scrH - normalCount * (notifH + 2)
        local notifGap = 2
        local NOTIF_IN_TIME = 0.3
        local NOTIF_VISIBLE_TIME = 4
        local NOTIF_OUT_TIME = 0.4
        local NOTIF_SLIDE = 30

        local matWarning = Material("tarkov_extraction/trader_red_warning.png", "noclamp smooth")

        local removeList = {}
        for i, notif in ipairs(TarkovErrorNotifications) do
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

            nalpha = math.floor(nalpha)
            if nalpha > 0 then
                local ny = notifBaseY - (i * (notifH + notifGap)) + offsetY
                local nx = scrW - notifW

                surface.SetDrawColor(0, 0, 0, math.floor(nalpha * 0.85))
                surface.DrawRect(nx, ny, notifW, notifH)

                if matWarning and not matWarning:IsError() then
                    local iconSize = notifH - 8
                    surface.SetDrawColor(255, 255, 255, nalpha)
                    surface.SetMaterial(matWarning)
                    surface.DrawTexturedRect(nx + 4, ny + 4, iconSize, iconSize)
                end

                draw.SimpleText(ResolveNotificationText(notif), "TarkovKeyHint", nx + 30, ny + notifH / 2, Color(205, 201, 175, nalpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
        end

        for _, idx in ipairs(removeList) do
            table.remove(TarkovErrorNotifications, idx)
        end
    end)

    -- ==================== TOOL SETTINGS PANEL ====================
    function TarkovExtractZone_OpenToolSettings(fromSettings, editIndex)
        if IsValid(toolSettingsPanel) then
            toolSettingsPanel:Remove()
            toolSettingsPanel = nil
            return
        end

        editIndex = tonumber(editIndex)
        local editZone = editIndex and TarkovExtractZones and TarkovExtractZones[editIndex] or nil
        local editMode = editZone ~= nil

        local scrW, scrH = ScrW(), ScrH()
        local panelW = math.min(550, scrW * 0.4)
        local panelH = scrH * 0.7
        local panelX = (scrW - panelW) / 2
        local panelY = (scrH - panelH) / 2

        toolSettingsPanel = vgui.Create("DFrame")
        toolSettingsPanel:SetSize(scrW, scrH)
        toolSettingsPanel:SetPos(0, 0)
        toolSettingsPanel:SetTitle("")
        toolSettingsPanel:SetDraggable(false)
        toolSettingsPanel:ShowCloseButton(false)
        toolSettingsPanel:MakePopup()

        toolSettingsPanel.Paint = function(s, w, h)
            surface.SetDrawColor(15, 15, 15, 230)
            surface.DrawRect(0, 0, w, h)
        end

        toolSettingsPanel.OnKeyCodePressed = function(s, key)
            if key == KEY_ESCAPE then
                toolSettingsPanel:Remove()
                toolSettingsPanel = nil
            end
        end

        -- Title
        local titlePanel = vgui.Create("DPanel", toolSettingsPanel)
        titlePanel:SetSize(panelW, 50)
        titlePanel:SetPos(panelX, panelY - 60)
        titlePanel.Paint = function(s, w, h)
            draw.SimpleText(editMode and Tr("tool_settings_edit_title", "Edit Zone") or Tr("tool_settings_title", "Tool Settings"), "TSettings_Tab", w / 2, h / 2, Color(205, 201, 175), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end

        -- Content area with scroll
        local content = vgui.Create("DPanel", toolSettingsPanel)
        content:SetPos(panelX, panelY)
        content:SetSize(panelW, panelH)
        content.Paint = function(s, w, h)
            surface.SetDrawColor(0, 0, 0, 230)
            surface.DrawRect(0, 0, w, h)
        end

        local scroll = vgui.Create("DScrollPanel", content)
        scroll:SetPos(0, 0)
        scroll:SetSize(panelW, panelH)

        -- Style scrollbar
        local sbar = scroll:GetVBar()
        sbar:SetWide(4)
        sbar.Paint = function() end
        sbar.btnUp.Paint = function() end
        sbar.btnDown.Paint = function() end
        sbar.btnGrip.Paint = function(s, w, h)
            draw.RoundedBox(2, 0, 0, w, h, Color(171, 178, 184, 200))
        end

        local y = 20
        local margin = 30
        local rowW = panelW - margin * 2
        local controlW = 220  -- same as LAYOUT_CONTROL_W in settings
        local spacing = 36

        -- Current zone config (stored globally for next zone placement)
        TarkovZoneNextConfig = TarkovZoneNextConfig or {
            name = "",
            extractTime = 7,
            condition = { enabled = false, key = false, pay = false, switch = false, usec = false, bear = false, scav = false, coop = false, payAmount = 0, healthBelow = 0, healthAbove = 0, armorBelow = 0, armorAbove = 0, levelBelow = 0, levelAbove = 0 },
            openTime = 0,
            closeTime = 0,
            oneTime = false,
            maxPlayers = 4,
            isDestination = false,
            transferToDestination = false,
            transferTargetId = "",
        }
        local cfg = editMode and table.Copy(editZone) or TarkovZoneNextConfig
        cfg.name = cfg.name or ""
        cfg.type = (cfg.type == "transit") and "transit" or "extract"
        cfg.extractTime = cfg.extractTime or 7
        cfg.openTime = cfg.openTime or 0
        cfg.closeTime = cfg.closeTime or 0
        cfg.oneTime = cfg.oneTime or false
        cfg.maxPlayers = cfg.maxPlayers or 4
        cfg.highlighted = cfg.highlighted or false
        cfg.isDestination = cfg.type == "transit" and cfg.isDestination == true or false
        cfg.transferToDestination = cfg.type == "transit" and cfg.transferToDestination == true or false
        cfg.transferTargetId = tostring(cfg.transferTargetId or "")
        cfg.condition = cfg.condition or { enabled = false, key = false, pay = false, switch = false, usec = false, bear = false, scav = false, coop = false, payAmount = 0, healthBelow = 0, healthAbove = 0, armorBelow = 0, armorAbove = 0, levelBelow = 0, levelAbove = 0 }

        local function RebuildToolSettings()
            if editMode and TarkovExtractZones and editIndex then
                TarkovExtractZones[editIndex] = table.Copy(cfg)
            end
            if IsValid(toolSettingsPanel) then
                toolSettingsPanel:Remove()
                toolSettingsPanel = nil
            end
            timer.Simple(0, function()
                TarkovExtractZone_OpenToolSettings(fromSettings, editIndex)
            end)
        end

        local function BuildDestinationChoices()
            local choices = {}
            for i, zone in ipairs(TarkovExtractZones or {}) do
                if i ~= editIndex and zone.type == "transit" and zone.isDestination == true then
                    table.insert(choices, {
                        label = zone.name or Tr("destination_default_name", "Destination %d", i),
                        value = tostring(zone.id or ("zone_" .. i)),
                    })
                end
            end
            if #choices == 0 then
                table.insert(choices, { label = Tr("destination_none", "无可用目的地"), value = "_none" })
            end
            return choices
        end

        local function GetDestinationDefaultLabel(choices)
            for _, choice in ipairs(choices) do
                if choice.value == cfg.transferTargetId then
                    return choice.label
                end
            end
            return choices[1] and choices[1].label or Tr("destination_none", "无可用目的地")
        end

        -- Send config to server whenever it changes
        local function SyncConfigToServer()
            if editMode then
                SendZoneEdit("update", editIndex, { config = cfg })
            else
                local payload = util.TableToJSON(TarkovZoneNextConfig)
                net.Start("TarkovExtractZone_SetConfig")
                net.WriteString(payload)
                net.SendToServer()
            end
        end

        -- Sync existing config to server when panel opens
        SyncConfigToServer()

        -- Helper: create a text entry row (label left, control right-aligned)
        local function MakeTextRow(parent, labelText, default, onChange, descKey)
            local row = vgui.Create("DPanel", parent)
            row:SetPos(margin, y)
            row:SetSize(rowW, 28)
            row.Paint = function() end

            local lbl = vgui.Create("DLabel", row)
            lbl:SetPos(0, 4)
            lbl:SetSize(rowW - controlW - 20, 20)
            lbl:SetFont("TSettings_Label")
            lbl:SetTextColor(Color(205, 201, 175))
            lbl:SetText(labelText)
            lbl:SetContentAlignment(4)
            AttachZoneOptionTooltip(lbl, labelText, descKey)

            local entry = vgui.Create("DTextEntry", row)
            entry:SetPos(rowW - controlW, 0)
            entry:SetSize(controlW, 28)
            entry:SetFont("TSettings_Value")
            entry:SetTextColor(Color(205, 201, 175))
            entry:SetValue(default or "")
            entry:SetContentAlignment(5)
            entry.Paint = function(s, ew, eh)
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
            entry.OnChange = function(s)
                if onChange then onChange(s:GetValue()) end
            end

            y = y + spacing
            return entry, row, lbl
        end

        -- Helper: create a number entry row
        local function MakeNumberRow(parent, labelText, default, onChange, descKey)
            local row = vgui.Create("DPanel", parent)
            row:SetPos(margin, y)
            row:SetSize(rowW, 28)
            row.Paint = function() end

            local lbl = vgui.Create("DLabel", row)
            lbl:SetPos(0, 4)
            lbl:SetSize(rowW - controlW - 20, 20)
            lbl:SetFont("TSettings_Label")
            lbl:SetTextColor(Color(205, 201, 175))
            lbl:SetText(labelText)
            lbl:SetContentAlignment(4)
            AttachZoneOptionTooltip(lbl, labelText, descKey)

            local entry = vgui.Create("DTextEntry", row)
            entry:SetPos(rowW - controlW, 0)
            entry:SetSize(controlW, 28)
            entry:SetFont("TSettings_Value")
            entry:SetTextColor(Color(205, 201, 175))
            entry:SetNumeric(true)
            entry:SetValue(tostring(default or 0))
            entry:SetContentAlignment(5)
            entry.Paint = function(s, ew, eh)
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
            entry.OnChange = function(s)
                if onChange then onChange(tonumber(s:GetValue()) or 0) end
            end

            y = y + spacing
            return entry, row, lbl
        end

        local function DrawCheckmarkCentered(matCheckmark, w, h, alpha)
            if not matCheckmark or matCheckmark:IsError() then return end

            local texW = matCheckmark:GetInt("$realwidth") or matCheckmark:Width() or w
            local texH = matCheckmark:GetInt("$realheight") or matCheckmark:Height() or h
            if texW == 0 then texW = w end
            if texH == 0 then texH = h end

            surface.SetDrawColor(255, 255, 255, alpha or 255)
            surface.SetMaterial(matCheckmark)
            surface.DrawTexturedRect((w - texW) / 2, (h - texH) / 2, texW, texH)
        end

        -- Helper: create a checkbox row
        local function MakeCheckRow(parent, labelText, default, onChange, descKey)
            local matCheckbox = Material("tarkov_extraction/checkbox.png", "noclamp smooth")
            local matCheckmark = Material("tarkov_extraction/checkmark.png", "noclamp smooth")
            local boxSize = 18
            local isChecked = default

            local row = vgui.Create("DPanel", parent)
            row:SetPos(margin, y)
            row:SetSize(rowW, 24)
            row.Paint = function() end

            local lbl = vgui.Create("DLabel", row)
            lbl:SetPos(0, 2)
            lbl:SetSize(rowW - controlW - 20, 20)
            lbl:SetFont("TSettings_Label")
            lbl:SetTextColor(Color(205, 201, 175))
            lbl:SetText(labelText)
            lbl:SetContentAlignment(4)
            AttachZoneOptionTooltip(lbl, labelText, descKey)

            local btn = vgui.Create("DButton", row)
            btn:SetPos(rowW - controlW + (controlW - boxSize) / 2, 2)
            btn:SetSize(boxSize, boxSize)
            btn:SetText("")
            btn.Paint = function(s, bw, bh)
                if matCheckbox and not matCheckbox:IsError() then
                    surface.SetDrawColor(255, 255, 255, 255)
                    surface.SetMaterial(matCheckbox)
                    surface.DrawTexturedRect(0, 0, bw, bh)
                end
                if isChecked and matCheckmark and not matCheckmark:IsError() then
                    DrawCheckmarkCentered(matCheckmark, bw, bh, 255)
                end
            end
            btn.DoClick = function()
                isChecked = not isChecked
                surface.PlaySound("tarkov_extraction/menu_checkbox.wav")
                if onChange then onChange(isChecked) end
            end

            y = y + spacing
            return btn, function() return isChecked end
        end

        -- Helper: create a combo box row
        local function MakeComboRow(parent, labelText, choices, default, onChange, descKey)
            local row = vgui.Create("DPanel", parent)
            row:SetPos(margin, y)
            row:SetSize(rowW, 28)
            row.Paint = function() end

            local lbl = vgui.Create("DLabel", row)
            lbl:SetPos(0, 4)
            lbl:SetSize(rowW - controlW - 20, 20)
            lbl:SetFont("TSettings_Label")
            lbl:SetTextColor(Color(205, 201, 175))
            lbl:SetText(labelText)
            lbl:SetContentAlignment(4)
            AttachZoneOptionTooltip(lbl, labelText, descKey)

            local defaultLabel = default
            for _, c in ipairs(choices) do
                if c.value == default then defaultLabel = c.label break end
            end

            local combo = TarkovUI_StyledCombo(row, rowW - controlW, 0, controlW, 28, choices, defaultLabel, onChange)

            y = y + spacing
            return combo
        end

        -- ===== Settings Fields =====

        -- Zone Name
        MakeTextRow(scroll, Tr("zone_field_name", "撤离点名称"), cfg.name, function(val)
            cfg.name = val
            SyncConfigToServer()
        end, "zone_desc_name")

        if editMode then
            MakeComboRow(scroll, Tr("zone_field_mode", "模式"), {
                { label = Tr("zone_mode_extract", "撤离点"), value = "extract" },
                { label = Tr("zone_mode_transit", "转移点"), value = "transit" },
            }, cfg.type or "extract", function(val)
                cfg.type = (val == "transit") and "transit" or "extract"
                if cfg.type ~= "transit" then
                    cfg.isDestination = false
                    cfg.transferToDestination = false
                    cfg.transferTargetId = ""
                end
                SyncConfigToServer()
                RebuildToolSettings()
            end, "zone_desc_mode")
        end

        if cfg.type == "transit" then
            MakeCheckRow(scroll, Tr("zone_field_is_destination", "作为目的地"), cfg.isDestination or false, function(val)
                cfg.isDestination = val
                if val then
                    cfg.transferToDestination = false
                    cfg.transferTargetId = ""
                end
                SyncConfigToServer()
                RebuildToolSettings()
            end, "zone_desc_is_destination")

            if not cfg.isDestination then
                MakeCheckRow(scroll, Tr("zone_field_transfer_to_destination", "转移到目的地"), cfg.transferToDestination or false, function(val)
                    cfg.transferToDestination = val
                    if not val then
                        cfg.transferTargetId = ""
                    end
                    SyncConfigToServer()
                    RebuildToolSettings()
                end, "zone_desc_transfer_to_destination")

                if cfg.transferToDestination then
                    local destinationChoices = BuildDestinationChoices()
                    local destinationDefault = GetDestinationDefaultLabel(destinationChoices)
                    if (cfg.transferTargetId == "" or cfg.transferTargetId == "_none") and destinationChoices[1] and destinationChoices[1].value ~= "_none" then
                        cfg.transferTargetId = destinationChoices[1].value
                        SyncConfigToServer()
                    end
                    MakeComboRow(scroll, Tr("zone_field_destination", "目的地区域"), destinationChoices, destinationDefault, function(val)
                        if val == "_none" then return end
                        cfg.transferTargetId = tostring(val or "")
                        cfg.transferToDestination = cfg.transferTargetId ~= ""
                        SyncConfigToServer()
                    end, "zone_desc_destination")
                end
            end
        else
            cfg.isDestination = false
            cfg.transferToDestination = false
            cfg.transferTargetId = ""
        end

        local zoneSettingsLocked = cfg.type == "transit" and cfg.isDestination == true

        if zoneSettingsLocked then
            local msg = vgui.Create("DLabel", scroll)
            msg:SetPos(margin, y)
            msg:SetSize(rowW, 24)
            msg:SetFont("TSettings_Label")
            msg:SetTextColor(Color(120, 120, 120))
            msg:SetText(Tr("zone_destination_only_notice", "该区域仅作为传送目的地，不参与撤离列表或撤离判定。"))
            msg:SetContentAlignment(4)
            y = y + spacing
        else

        -- Extract Time
        MakeNumberRow(scroll, Tr("zone_field_extract_time", "撤离时间 (秒)"), cfg.extractTime, function(val)
            cfg.extractTime = val
            SyncConfigToServer()
        end, "zone_desc_extract_time")

        -- Open Time
        MakeNumberRow(scroll, Tr("zone_field_open_time", "开放延迟 (秒)"), cfg.openTime, function(val)
            cfg.openTime = val
            SyncConfigToServer()
        end, "zone_desc_open_time")

        -- Close Time
        MakeNumberRow(scroll, Tr("zone_field_close_time", "关闭延迟 (秒)"), cfg.closeTime, function(val)
            cfg.closeTime = val
            SyncConfigToServer()
        end, "zone_desc_close_time")

        local maxPlayersEntry, maxPlayersRow
        local function UpdateMaxPlayersState()
            if not IsValid(maxPlayersEntry) or not IsValid(maxPlayersRow) then return end

            local enabled = cfg.oneTime == true
            maxPlayersRow:SetAlpha(enabled and 255 or 80)
            maxPlayersEntry:SetMouseInputEnabled(enabled)
            maxPlayersEntry:SetKeyboardInputEnabled(enabled)
        end

        -- Faction availability (independent checkboxes)
        MakeCheckRow(scroll, Tr("zone_field_usec", "USEC可用"), cfg.condition.usec or false, function(val)
            if type(cfg.condition) ~= "table" then cfg.condition = {} end
            cfg.condition.usec = val
            SyncConfigToServer()
        end, "zone_desc_usec")

        MakeCheckRow(scroll, Tr("zone_field_bear", "BEAR可用"), cfg.condition.bear or false, function(val)
            if type(cfg.condition) ~= "table" then cfg.condition = {} end
            cfg.condition.bear = val
            SyncConfigToServer()
        end, "zone_desc_bear")

        MakeCheckRow(scroll, Tr("zone_field_scav", "Scav可用"), cfg.condition.scav or false, function(val)
            if type(cfg.condition) ~= "table" then cfg.condition = {} end
            cfg.condition.scav = val
            SyncConfigToServer()
        end, "zone_desc_scav")

        -- One-time extraction
        MakeCheckRow(scroll, Tr("zone_field_one_time", "一次性撤离点"), cfg.oneTime, function(val)
            cfg.oneTime = val
            UpdateMaxPlayersState()
            SyncConfigToServer()
        end, "zone_desc_one_time")

        -- Max players (for vehicle)
        maxPlayersEntry, maxPlayersRow = MakeNumberRow(scroll, Tr("zone_field_max_players", "最大可同时撤离人数"), cfg.maxPlayers, function(val)
            if not cfg.oneTime then return end
            cfg.maxPlayers = val
            SyncConfigToServer()
        end, "zone_desc_max_players")
        UpdateMaxPlayersState()

        -- Condition (master toggle + sub-options)
        -- Ensure condition is a table
        if type(cfg.condition) ~= "table" then
            cfg.condition = { enabled = false, key = false, pay = false, switch = false, usec = false, bear = false, scav = false, coop = false, payAmount = 0, healthBelow = 0, healthAbove = 0, armorBelow = 0, armorAbove = 0, levelBelow = 0, levelAbove = 0 }
        end
        if cfg.condition.enabled == nil then
            cfg.condition.enabled = false
        end
        local removedConditionChanged = cfg.condition.key or cfg.condition.pay or cfg.condition.switch or ((tonumber(cfg.condition.payAmount) or 0) ~= 0)
        cfg.condition.key = false
        cfg.condition.pay = false
        cfg.condition.switch = false
        cfg.condition.payAmount = 0
        if removedConditionChanged then
            SyncConfigToServer()
        end

        -- Track sub-option rows for enabling/disabling
        local condSubRows = {}

        -- Master toggle: "撤离条件"
        local matCheckbox = Material("tarkov_extraction/checkbox.png", "noclamp smooth")
        local matCheckmark = Material("tarkov_extraction/checkmark.png", "noclamp smooth")
        local boxSize = 18
        local condEnabled = cfg.condition.enabled or false

        local masterRow = vgui.Create("DPanel", scroll)
        masterRow:SetPos(margin, y)
        masterRow:SetSize(rowW, 24)
        masterRow.Paint = function() end

        local masterLbl = vgui.Create("DLabel", masterRow)
        masterLbl:SetPos(0, 2)
        masterLbl:SetSize(rowW - controlW - 20, 20)
        masterLbl:SetFont("TSettings_Label")
        masterLbl:SetTextColor(Color(205, 201, 175))
        local conditionLabel = Tr("zone_field_conditions", "撤离条件")
        masterLbl:SetText(conditionLabel)
        masterLbl:SetContentAlignment(4)
        AttachZoneOptionTooltip(masterLbl, conditionLabel, "zone_desc_conditions")

        local masterBtn = vgui.Create("DButton", masterRow)
        masterBtn:SetPos(rowW - controlW + (controlW - boxSize) / 2, 2)
        masterBtn:SetSize(boxSize, boxSize)
        masterBtn:SetText("")
        masterBtn.Paint = function(s, bw, bh)
            if matCheckbox and not matCheckbox:IsError() then
                surface.SetDrawColor(255, 255, 255, 255)
                surface.SetMaterial(matCheckbox)
                surface.DrawTexturedRect(0, 0, bw, bh)
            end
            if condEnabled and matCheckmark and not matCheckmark:IsError() then
                DrawCheckmarkCentered(matCheckmark, bw, bh, 255)
            end
        end

        local function UpdateCondSubState()
            for _, sub in ipairs(condSubRows) do
                if condEnabled then
                    sub.row:SetAlpha(255)
                    sub.btn:SetMouseInputEnabled(true)
                    sub.btn:SetKeyboardInputEnabled(true)
                    -- For number rows, also update entry state based on row checkbox
                    if sub.entry and sub.getRowEnabled then
                        local rowOn = sub.getRowEnabled()
                        sub.entry:SetMouseInputEnabled(rowOn)
                        sub.entry:SetKeyboardInputEnabled(rowOn)
                    end
                else
                    sub.row:SetAlpha(80)
                    sub.btn:SetMouseInputEnabled(false)
                    sub.btn:SetKeyboardInputEnabled(false)
                    if sub.entry then
                        sub.entry:SetMouseInputEnabled(false)
                        sub.entry:SetKeyboardInputEnabled(false)
                    end
                end
            end
        end

        masterBtn.DoClick = function()
            condEnabled = not condEnabled
            cfg.condition.enabled = condEnabled
            surface.PlaySound("tarkov_extraction/menu_checkbox.wav")
            UpdateCondSubState()
            SyncConfigToServer()
        end
        y = y + spacing

        -- Condition sub-option checkboxes
        local function MakeCondSubCheck(labelText, field, default, descKey)
            local isChecked = default

            local row = vgui.Create("DPanel", scroll)
            row:SetPos(margin, y)
            row:SetSize(rowW, 24)
            row.Paint = function() end

            local lbl = vgui.Create("DLabel", row)
            lbl:SetPos(0, 2)
            lbl:SetSize(rowW - controlW - 20, 20)
            lbl:SetFont("TSettings_Label")
            lbl:SetTextColor(Color(205, 201, 175))
            lbl:SetText(labelText)
            lbl:SetContentAlignment(4)
            AttachZoneOptionTooltip(lbl, labelText, descKey)

            local btn = vgui.Create("DButton", row)
            btn:SetPos(rowW - controlW + (controlW - boxSize) / 2, 2)
            btn:SetSize(boxSize, boxSize)
            btn:SetText("")
            btn.Paint = function(s, bw, bh)
                local alpha = condEnabled and 255 or 80
                if matCheckbox and not matCheckbox:IsError() then
                    surface.SetDrawColor(255, 255, 255, alpha)
                    surface.SetMaterial(matCheckbox)
                    surface.DrawTexturedRect(0, 0, bw, bh)
                end
                if isChecked and matCheckmark and not matCheckmark:IsError() then
                    DrawCheckmarkCentered(matCheckmark, bw, bh, alpha)
                end
            end
            btn.DoClick = function()
                if not condEnabled then return end
                isChecked = not isChecked
                cfg.condition[field] = isChecked
                surface.PlaySound("tarkov_extraction/menu_checkbox.wav")
                SyncConfigToServer()
            end

            table.insert(condSubRows, { row = row, btn = btn })
            y = y + spacing
        end

        MakeCondSubCheck(Tr("zone_field_coop", "合作撤离"), "coop", cfg.condition.coop or false, "zone_desc_coop")

        -- Sub-option: number input row with enable checkbox (label + checkbox + number entry, respects condEnabled)
        local exclusivePairs = {
            { "healthBelow", "healthAbove" },
            { "armorBelow", "armorAbove" },
            { "levelBelow", "levelAbove" },
        }
        for _, pair in ipairs(exclusivePairs) do
            local belowEnabled = pair[1] .. "Enabled"
            local aboveEnabled = pair[2] .. "Enabled"
            if cfg.condition[belowEnabled] and cfg.condition[aboveEnabled] then
                cfg.condition[belowEnabled] = false
            end
        end

        local condNumberRows = {}

        local function MakeCondNumberRow(labelText, field, default, oppositeField, descKey)
            local enabledField = field .. "Enabled"
            local isRowEnabled = cfg.condition[enabledField] or false

            local function IsBlockedByOpposite()
                return oppositeField and cfg.condition[oppositeField .. "Enabled"] == true
            end

            local function CanUseRow()
                return condEnabled and not IsBlockedByOpposite()
            end

            local row = vgui.Create("DPanel", scroll)
            row:SetPos(margin, y)
            row:SetSize(rowW, 28)
            row.Paint = function() end

            -- Checkbox on the left
            local chkBtn = vgui.Create("DButton", row)
            chkBtn:SetPos(0, 5)
            chkBtn:SetSize(boxSize, boxSize)
            chkBtn:SetText("")
            chkBtn.Paint = function(s, bw, bh)
                local alpha = CanUseRow() and 255 or 80
                if matCheckbox and not matCheckbox:IsError() then
                    surface.SetDrawColor(255, 255, 255, alpha)
                    surface.SetMaterial(matCheckbox)
                    surface.DrawTexturedRect(0, 0, bw, bh)
                end
                if isRowEnabled and matCheckmark and not matCheckmark:IsError() then
                    DrawCheckmarkCentered(matCheckmark, bw, bh, alpha)
                end
            end

            -- Label after checkbox
            local lbl = vgui.Create("DLabel", row)
            lbl:SetPos(boxSize + 6, 4)
            lbl:SetSize(rowW - controlW - boxSize - 26, 20)
            lbl:SetFont("TSettings_Label")
            lbl:SetTextColor(Color(205, 201, 175))
            lbl:SetText(labelText)
            lbl:SetContentAlignment(4)
            AttachZoneOptionTooltip(lbl, labelText, descKey)

            -- Number entry on the right
            local entry = vgui.Create("DTextEntry", row)
            entry:SetPos(rowW - controlW, 0)
            entry:SetSize(controlW, 28)
            entry:SetFont("TSettings_Value")
            entry:SetTextColor(Color(205, 201, 175))
            entry:SetNumeric(true)
            entry:SetValue(tostring(default or 0))
            entry:SetContentAlignment(5)
            entry.Paint = function(s, ew, eh)
                local alpha = (CanUseRow() and isRowEnabled) and 255 or 80
                surface.SetDrawColor(40, 40, 40, alpha)
                surface.DrawRect(0, 0, ew, eh)
                surface.SetDrawColor(80, 80, 80, alpha)
                surface.DrawOutlinedRect(0, 0, ew, eh, 1)
                if s:IsEditing() then
                    s:DrawTextEntryText(Color(205, 201, 175, alpha), Color(100, 150, 200, alpha), Color(205, 201, 175, alpha))
                else
                    draw.SimpleText(s:GetValue(), "TSettings_Value", ew / 2, eh / 2, Color(205, 201, 175, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
            end
            entry.OnChange = function(s)
                if not condEnabled or not isRowEnabled then return end
                cfg.condition[field] = tonumber(s:GetValue()) or 0
                SyncConfigToServer()
            end

            local function ApplyInputState()
                local enabled = isRowEnabled and CanUseRow()
                entry:SetMouseInputEnabled(enabled)
                entry:SetKeyboardInputEnabled(enabled)
            end

            local function SetRowEnabled(enabled)
                isRowEnabled = enabled
                cfg.condition[enabledField] = enabled
                ApplyInputState()
            end

            -- Toggle row enabled
            chkBtn.DoClick = function()
                if not condEnabled then return end

                if not isRowEnabled and IsBlockedByOpposite() then
                    if TarkovNotifyError then
                        TarkovNotifyError("error_cancel_opposite_condition", "请先取消对应的高于/低于条件")
                    else
                        surface.PlaySound("tarkov_extraction/error_message.wav")
                    end
                    return
                end

                isRowEnabled = not isRowEnabled
                cfg.condition[enabledField] = isRowEnabled
                if isRowEnabled and oppositeField and condNumberRows[oppositeField] then
                    condNumberRows[oppositeField].SetRowEnabled(false)
                end
                ApplyInputState()
                surface.PlaySound("tarkov_extraction/menu_checkbox.wav")
                SyncConfigToServer()
            end

            -- Initial entry state
            ApplyInputState()

            condNumberRows[field] = {
                SetRowEnabled = SetRowEnabled,
                Refresh = ApplyInputState,
            }
            table.insert(condSubRows, { row = row, btn = chkBtn, entry = entry, getRowEnabled = function() return isRowEnabled and not IsBlockedByOpposite() end })
            y = y + spacing
        end

        MakeCondNumberRow(Tr("zone_field_health_below", "低于血量值"), "healthBelow", cfg.condition.healthBelow or 0, "healthAbove", "zone_desc_health_below")
        MakeCondNumberRow(Tr("zone_field_health_above", "高于血量值"), "healthAbove", cfg.condition.healthAbove or 0, "healthBelow", "zone_desc_health_above")
        MakeCondNumberRow(Tr("zone_field_armor_below", "低于护甲值"), "armorBelow", cfg.condition.armorBelow or 0, "armorAbove", "zone_desc_armor_below")
        MakeCondNumberRow(Tr("zone_field_armor_above", "高于护甲值"), "armorAbove", cfg.condition.armorAbove or 0, "armorBelow", "zone_desc_armor_above")
        MakeCondNumberRow(Tr("zone_field_level_below", "低于等级"), "levelBelow", cfg.condition.levelBelow or 0, "levelAbove", "zone_desc_level_below")
        MakeCondNumberRow(Tr("zone_field_level_above", "高于等级"), "levelAbove", cfg.condition.levelAbove or 0, "levelBelow", "zone_desc_level_above")

        -- Apply initial state
        UpdateCondSubState()

        if editMode then
            y = y + 8
            MakeCheckRow(scroll, Tr("zone_field_highlight", "高亮显示"), cfg.highlighted or false, function(val)
                cfg.highlighted = val
                SyncConfigToServer()
            end, "zone_desc_highlight")
        end

        end

        -- Back/Close button
        local backBtnW = 210
        local backBtnH = 57
        local backY = panelY + panelH + 15
        if CreateTabBarButton then
            local btnText = (fromSettings or editMode) and Tr("btn_back", "Back") or Tr("btn_close", "Close")
            CreateTabBarButton(toolSettingsPanel, panelX, backY, backBtnW, backBtnH, btnText, function()
                toolSettingsPanel:Remove()
                toolSettingsPanel = nil
                if editMode then
                    TarkovExtractZone_OpenZoneList(fromSettings)
                elseif fromSettings then
                    RunConsoleCommand("tarkov_settings")
                end
            end)
        end
    end

    concommand.Add("tarkov_extract_tool_settings", function()
        TarkovExtractZone_OpenToolSettings()
    end)

    -- ==================== ZONE LIST PANEL ====================
    local zoneListPanel = nil

    function TarkovExtractZone_OpenZoneList(fromSettings)
        if IsValid(zoneListPanel) then
            zoneListPanel:Remove()
            zoneListPanel = nil
            return
        end

        local scrW, scrH = ScrW(), ScrH()
        local panelW = math.min(500, scrW * 0.35)
        local panelH = scrH * 0.6
        local panelX = (scrW - panelW) / 2
        local panelY = (scrH - panelH) / 2

        zoneListPanel = vgui.Create("DFrame")
        zoneListPanel:SetSize(scrW, scrH)
        zoneListPanel:SetPos(0, 0)
        zoneListPanel:SetTitle("")
        zoneListPanel:SetDraggable(false)
        zoneListPanel:ShowCloseButton(false)
        zoneListPanel:MakePopup()

        zoneListPanel.Paint = function(s, w, h)
            surface.SetDrawColor(15, 15, 15, 230)
            surface.DrawRect(0, 0, w, h)
        end

        zoneListPanel.OnKeyCodePressed = function(s, key)
            if key == KEY_ESCAPE then
                zoneListPanel:Remove()
                zoneListPanel = nil
            end
        end

        -- Title
        local titlePanel = vgui.Create("DPanel", zoneListPanel)
        titlePanel:SetSize(panelW, 50)
        titlePanel:SetPos(panelX, panelY - 60)
        titlePanel.Paint = function(s, w, h)
            draw.SimpleText(Tr("zone_list_title", "Zone List"), "TSettings_Tab", w / 2, h / 2, Color(205, 201, 175), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end

        -- Content area
        local content = vgui.Create("DPanel", zoneListPanel)
        content:SetPos(panelX, panelY)
        content:SetSize(panelW, panelH)
        content.Paint = function(s, w, h)
            surface.SetDrawColor(0, 0, 0, 230)
            surface.DrawRect(0, 0, w, h)
        end

        local y = 20
        local margin = 20
        local rowW = panelW - margin * 2
        local zones = TarkovExtractZones or {}
        local matZoneListButton = Material("tarkov_extraction/button_back_big.png", "noclamp smooth")

        local function CreateZoneListButton(parent, x, y, w, h, textOrFunc, onClick, isActiveFunc)
            local btn = vgui.Create("DButton", parent)
            btn:SetPos(x, y)
            btn:SetSize(w, h)
            btn:SetText("")
            btn.hoverAlpha = 0

            btn.OnCursorEntered = function()
                surface.PlaySound("tarkov_extraction/button_over.wav")
            end

            btn.Paint = function(s, bw, bh)
                local active = isActiveFunc and isActiveFunc() or false
                if s:IsHovered() or active then
                    s.hoverAlpha = math.min(255, s.hoverAlpha + FrameTime() * 1600)
                else
                    s.hoverAlpha = math.max(0, s.hoverAlpha - FrameTime() * 1200)
                end

                if active and not s:IsHovered() then
                    s.hoverAlpha = 255
                end

                if s.hoverAlpha > 0 then
                    if matZoneListButton and not matZoneListButton:IsError() then
                        surface.SetDrawColor(255, 255, 255, s.hoverAlpha)
                        surface.SetMaterial(matZoneListButton)
                        surface.DrawTexturedRect(0, 0, bw, bh)
                    end
                end

                local lerpFrac = s.hoverAlpha / 255
                local r = Lerp(lerpFrac, 205, 0)
                local g = Lerp(lerpFrac, 201, 0)
                local b = Lerp(lerpFrac, 175, 0)
                local label = isfunction(textOrFunc) and textOrFunc() or textOrFunc
                draw.SimpleText(tostring(label or ""), "TSettings_Section", bw / 2, bh / 2, Color(r, g, b), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end

            btn.DoClick = function(s)
                surface.PlaySound("tarkov_extraction/button_click.wav")
                if onClick then onClick(s) end
            end

            return btn
        end

        if #zones == 0 then
            local noZones = vgui.Create("DPanel", content)
            noZones:SetPos(0, 0)
            noZones:SetSize(panelW, panelH)
            noZones.Paint = function(s, pw, ph)
                draw.SimpleText(Tr("zone_list_empty", "No zones defined for this map."), "TSettings_Label", pw / 2, ph / 2, Color(120, 120, 120), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        else
            local zoneScroll = vgui.Create("DScrollPanel", content)
            zoneScroll:SetPos(margin, y)
            zoneScroll:SetSize(rowW, panelH - y * 2)

            -- Style scrollbar
            local zsbar = zoneScroll:GetVBar()
            zsbar:SetWide(4)
            zsbar.Paint = function() end
            zsbar.btnUp.Paint = function() end
            zsbar.btnDown.Paint = function() end
            zsbar.btnGrip.Paint = function(s, w, h)
                draw.RoundedBox(2, 0, 0, w, h, Color(171, 178, 184, 200))
            end

            local zy = 0
            for i, zone in ipairs(zones) do
                local entry = vgui.Create("DPanel", zoneScroll)
                entry:SetPos(0, zy)
                entry:SetSize(rowW, 60)
                entry.Paint = function(s, ew, eh)
                    if zone.highlighted then
                        surface.SetDrawColor(50, 60, 30, 220)
                    else
                        surface.SetDrawColor(30, 30, 30, 200)
                    end
                    surface.DrawRect(0, 0, ew, eh)
                    draw.SimpleText(zone.name or Tr("zone_default_name", "Zone %d", i), "TSettings_Label", 12, eh / 2, Color(205, 201, 175), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end

                -- Button positions from right to left
                local btnX = rowW
                local btnGap = 24
                local btnY = 10
                local btnH = 40

                -- Remove button
                btnX = btnX - 104
                CreateZoneListButton(entry, btnX, btnY, 98, btnH, Tr("zone_list_remove", "Remove"), function()
                    SendZoneEdit("remove", i)
                    timer.Simple(0.1, function()
                        if IsValid(zoneListPanel) then
                            zoneListPanel:Remove()
                            zoneListPanel = nil
                            TarkovExtractZone_OpenZoneList(fromSettings)
                        end
                    end)
                end)

                -- Edit button
                btnX = btnX - btnGap - 82
                CreateZoneListButton(entry, btnX, btnY, 82, btnH, Tr("zone_list_edit", "Edit"), function()
                    if IsValid(zoneListPanel) then
                        zoneListPanel:Remove()
                        zoneListPanel = nil
                    end
                    TarkovExtractZone_OpenToolSettings(fromSettings, i)
                end)

                zy = zy + 68
            end
        end

        -- Back button
        local backBtnW = 210
        local backBtnH = 57
        local backY = panelY + panelH + 15
        if CreateTabBarButton then
            local btnText = fromSettings and Tr("btn_back", "Back") or Tr("btn_close", "Close")
            CreateTabBarButton(zoneListPanel, panelX, backY, backBtnW, backBtnH, btnText, function()
                zoneListPanel:Remove()
                zoneListPanel = nil
                if fromSettings then
                    RunConsoleCommand("tarkov_settings")
                end
            end)
        end
    end

    concommand.Add("tarkov_extract_zone_list", function()
        TarkovExtractZone_OpenZoneList()
    end)
end
