--[[
    Tarkov Extraction Zone Tool - Network Strings & Give Handler
    Must be in autorun/server to ensure network strings are registered early
]]

util.AddNetworkString("TarkovExtractZone_Sync")
util.AddNetworkString("TarkovExtractZone_PlaceState")
util.AddNetworkString("TarkovExtractZone_GiveTool")
util.AddNetworkString("TarkovExtractZone_Notify")
util.AddNetworkString("TarkovExtractZone_SetConfig")
util.AddNetworkString("TarkovExtractZone_Edit")
util.AddNetworkString("TarkovExtract_ExtractState")
util.AddNetworkString("TarkovExtract_Complete")
util.AddNetworkString("TarkovExtract_ClearPostExtractProtection")

-- Send notification to player's HUD. Prefer sending language keys so the
-- client can render notifications in its currently selected language.
function TarkovZone_Notify(ply, keyOrText, fallback, ...)
    if not IsValid(ply) then return end
    local payload
    if fallback ~= nil or select("#", ...) > 0 then
        payload = util.TableToJSON({
            key = tostring(keyOrText or ""),
            fallback = tostring(fallback or ""),
            args = {...},
        })
    else
        payload = util.TableToJSON({
            text = tostring(keyOrText or ""),
        })
    end

    net.Start("TarkovExtractZone_Notify")
    net.WriteString(payload or tostring(keyOrText or ""))
    net.Send(ply)
end

-- Give the zone tool weapon when requested
net.Receive("TarkovExtractZone_GiveTool", function(len, ply)
    if not IsValid(ply) or not ply:IsSuperAdmin() then return end
    ply:Give("tarkov_zone_tool")
    ply:SelectWeapon("tarkov_zone_tool")
end)
