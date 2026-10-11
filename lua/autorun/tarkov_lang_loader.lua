--[[
    Tarkov Series - Language Loader
    Loads all language files and provides global access

    ============================================================
    HOW TO ADD A NEW LANGUAGE:
    ============================================================
    
    1. Create a new file in one of these folders:
       - lua/tarkov_deploy/lang/
       - lua/tarkov_extraction/lang/
       Example: lua/tarkov_deploy/lang/jp.lua (for Japanese)
    
    2. In your new file, copy the structure from cn.lua or en.lua
       and translate all values. The file should look like:
       
       TarkovLang = TarkovLang or {}
       TarkovLang["jp"] = {
           title = "設定",
           tab_deploy = "デプロイ",
           -- ... all other keys ...
       }
    
    3. That's it! The loader will automatically find and load
       your new language file. No registration needed.
    
    4. The settings title language selector is built automatically
       from TarkovLang, so no manual registration is needed.
    
    5. The language code (e.g. "jp") must match:
       - The key in TarkovLang["jp"]
       - The "value" in the combo box choice
       - The value stored in TarkovSettings.Language
    
    ============================================================
]]

TarkovLang = TarkovLang or {}

-- Auto-discover and load all language files bundled by any Tarkov series addon.
local langDirs = {
    "tarkov_deploy/lang/",
    "tarkov_extraction/lang/",
}

local loadedLangFiles = {}
for _, dir in ipairs(langDirs) do
    local langFiles, _ = file.Find(dir .. "*.lua", "LUA")
    if langFiles then
        table.sort(langFiles)
        for _, f in ipairs(langFiles) do
            local path = dir .. f
            if not loadedLangFiles[path] then
                loadedLangFiles[path] = true
                if SERVER then
                    AddCSLuaFile(path)
                end
                include(path)
            end
        end
    end
end

-- Global helper to get current language table
function TarkovGetLang()
    local lang = "ru"
    if TarkovSettingsGetLanguage then
        lang = TarkovSettingsGetLanguage()
    elseif TarkovSettingsLanguage then
        lang = TarkovSettingsLanguage
    elseif TarkovSettings and TarkovSettings.Language then
        lang = TarkovSettings.Language
    elseif DEPLOY and DEPLOY.Config and DEPLOY.Config.Language then
        lang = DEPLOY.Config.Language
    end
    return TarkovLang[lang] or TarkovLang["cn"]
end

-- Global helper to get a specific text key
function TarkovGetText(key)
    local t = TarkovGetLang()
    return t[key] or key
end

-- Global helper with fallback text and string.format support.
-- Usage: TarkovLangText("hud_redeploy_notice", "Redeploy in %d", seconds)
function TarkovLangText(key, fallback, ...)
    local t = TarkovGetLang()
    local cn = TarkovLang and TarkovLang["cn"] or nil
    local text = t and t[key] or nil
    if text == nil and cn then
        text = cn[key]
    end
    text = text or fallback or key

    if select("#", ...) > 0 then
        local ok, formatted = pcall(string.format, text, ...)
        if ok then return formatted end
    end

    return text
end

print("[Tarkov Series] Language files loaded")
