-- CastQueueOverlay
-- Paints a translucent overlay over the trailing portion of your cast bar
-- that corresponds to the current SpellQueueWindow CVar (in ms), relative
-- to the total length of the cast/channel currently in progress.

local ADDON_NAME = ...

-- ---------------------------------------------------------------------
-- Saved settings
-- ---------------------------------------------------------------------
local defaults = {
    r = 1, g = 1, b = 1, a = 0.35,
    frameName = nil, -- nil/empty = use the default Blizzard player cast bar
}

-- `DB = DB or {}` alone only covers a first run. A user upgrading from a build
-- that predates a key keeps their saved table, that key stays nil, and the addon
-- breaks only for existing users - which never reproduces on a fresh install.
CastQueueOverlayDB = CastQueueOverlayDB or {}
for k, v in pairs(defaults) do
    if CastQueueOverlayDB[k] == nil then
        CastQueueOverlayDB[k] = v
    end
end

-- Shared namespace so the options panel can drive the overlay without
-- reaching into locals.
CastQueueOverlay = CastQueueOverlay or {}
local addon = CastQueueOverlay
addon.DEFAULT_FRAME_NAME = "PlayerCastingBarFrame"

local overlay
local castBar
local activeStartMS, activeEndMS
local hookedBars = {}   -- frames whose OnSizeChanged we have already hooked

-- ---------------------------------------------------------------------
-- Resolving / (re)building the overlay texture on whichever frame is
-- currently configured as the "cast bar".
-- ---------------------------------------------------------------------
local function ResolveCastBar()
    local name = CastQueueOverlayDB.frameName
    if name and name ~= "" then
        local f = _G[name]
        if f then return f end
    end
    return _G[addon.DEFAULT_FRAME_NAME]
end

local function DestroyOverlay()
    if overlay then
        overlay:Hide()
        overlay:ClearAllPoints()
        overlay:SetParent(UIParent)
        overlay = nil
    end
end

local function EnsureOverlay()
    if overlay and castBar then return overlay end
    if not castBar then
        castBar = ResolveCastBar()
    end
    if not castBar then return nil end

    overlay = castBar:CreateTexture(nil, "OVERLAY")
    overlay:SetColorTexture(1, 1, 1, 1)
    overlay:Hide()

    -- Keep the overlay's width correct if the bar itself is resized (e.g. via
    -- Edit Mode). Hooks can never be removed, so track which bars we have already
    -- hooked - SetCastBarByName destroys and rebuilds the overlay, which would
    -- otherwise stack a new hook every time the user switches bars.
    if not hookedBars[castBar] then
        hookedBars[castBar] = true
        castBar:HookScript("OnSizeChanged", function()
            if overlay and overlay:IsShown() then
                addon.Refresh()
            end
        end)
    end

    return overlay
end

-- ---------------------------------------------------------------------
-- Core update logic
-- ---------------------------------------------------------------------
local function ApplyOverlay(startMS, endMS)
    local bar = EnsureOverlay()
    if not bar then return end

    if not startMS or not endMS then
        activeStartMS, activeEndMS = nil, nil
        overlay:Hide()
        return
    end

    local castDuration = endMS - startMS
    if castDuration <= 0 then
        overlay:Hide()
        return
    end

    activeStartMS, activeEndMS = startMS, endMS

    local queueWindowMS = tonumber(GetCVar("SpellQueueWindow")) or 0
    local pct = queueWindowMS / castDuration
    if pct <= 0 then
        overlay:Hide()
        return
    end
    if pct > 1 then pct = 1 end

    local barWidth = castBar:GetWidth()

    overlay:ClearAllPoints()
    overlay:SetPoint("TOPRIGHT", castBar, "TOPRIGHT", 0, 0)
    overlay:SetPoint("BOTTOMRIGHT", castBar, "BOTTOMRIGHT", 0, 0)
    overlay:SetWidth(barWidth * pct)

    local c = CastQueueOverlayDB
    overlay:SetColorTexture(c.r, c.g, c.b, c.a)

    overlay:Show()
end

-- Public: recompute using whatever cast is currently tracked (used after
-- color changes, CVAR_UPDATE, bar resize, etc).
function addon.Refresh()
    ApplyOverlay(activeStartMS, activeEndMS)
end

local function HideOverlay()
    activeStartMS, activeEndMS = nil, nil
    if overlay then overlay:Hide() end
end

-- Public: switch which frame the overlay is attached to. `name` must be
-- a valid global frame name. Returns true/false for success.
function addon.SetCastBarByName(name)
    local f = name and _G[name]
    if not f or type(f.CreateTexture) ~= "function" then
        return false
    end

    DestroyOverlay()
    castBar = f
    CastQueueOverlayDB.frameName = name
    activeStartMS, activeEndMS = nil, nil
    EnsureOverlay()

    if addon.OnCastBarChanged then
        addon.OnCastBarChanged(name)
    end
    return true
end

-- Public: name currently configured (falls back to the default name even
-- if nothing has been explicitly chosen yet).
function addon.GetCastBarName()
    return CastQueueOverlayDB.frameName or addon.DEFAULT_FRAME_NAME
end

-- ---------------------------------------------------------------------
-- Event handling
-- ---------------------------------------------------------------------
local f = CreateFrame("Frame")

local function OnCastUpdate(isChannel)
    local name, startMS, endMS

    if isChannel then
        local channelName, _, _, s, e, _, _, _, _, numStages = UnitChannelInfo("player")
        name, startMS, endMS = channelName, s, e

        -- An empowered cast (Evoker) reports numEmpowerStages > 0 and keeps
        -- running past endTimeMs while held at max stage. Blizzard's own bar
        -- lengthens itself by exactly that hold window before sizing anything
        -- (CastingBarFrame.lua:429-431), so measuring against the raw endTimeMs
        -- would size the overlay to a shorter bar than the one on screen.
        if name and numStages and numStages > 0 then
            endMS = endMS + GetUnitEmpowerHoldAtMaxTime("player")
        end
    else
        local castName, _, _, s, e = UnitCastingInfo("player")
        name, startMS, endMS = castName, s, e
    end

    if not name then
        HideOverlay()
        return
    end
    ApplyOverlay(startMS, endMS)
end

f:SetScript("OnEvent", function(self, event, unit, ...)
    if event == "PLAYER_LOGIN" then
        EnsureOverlay()
        return
    end

    if event == "CVAR_UPDATE" then
        -- CVAR_UPDATE fires for every CVar the client touches, not just ours.
        -- arg1 is the CVar name; Blizzard's own handlers filter on it
        -- (QuestMapFrame.lua:580, ArtifactBar.lua:70). The event's casing is not
        -- guaranteed to match the string we hand to GetCVar, so compare folded.
        if unit and strlower(unit) == "spellqueuewindow" and activeStartMS then
            addon.Refresh()
        end
        return
    end

    if unit ~= "player" then return end

    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_DELAYED" then
        OnCastUpdate(false)
    elseif event == "UNIT_SPELLCAST_CHANNEL_START"
        or event == "UNIT_SPELLCAST_CHANNEL_UPDATE"
        or event == "UNIT_SPELLCAST_EMPOWER_START"
        or event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
        -- Empowers are channels: Blizzard routes the EMPOWER events through the
        -- same branch as the CHANNEL ones and reads them with UnitChannelInfo
        -- (CastingBarFrame.lua:418, :487).
        OnCastUpdate(true)
    elseif event == "UNIT_SPELLCAST_STOP"
        or event == "UNIT_SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_INTERRUPTED"
        or event == "UNIT_SPELLCAST_CHANNEL_STOP"
        or event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        HideOverlay()
    end
end)

f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("CVAR_UPDATE")
f:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
f:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", "player")
f:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
f:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "player")
f:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
f:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
f:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
f:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
f:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", "player")
f:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_UPDATE", "player")
f:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", "player")

-- ---------------------------------------------------------------------
-- Slash command: "/cqo" opens the options panel. That is all it does -
-- arguments were removed deliberately, everything is configured in the panel.
-- ---------------------------------------------------------------------
SLASH_CASTQUEUEOVERLAY1 = "/cqo"
SlashCmdList["CASTQUEUEOVERLAY"] = function()
    -- `Settings.OpenToCategory` forwards straight to
    -- `C_SettingsUtil.OpenSettingsPanel(openToCategoryID)`, whose argument is
    -- typed `number` (Blizzard_Settings.lua:143). Passing the category TABLE
    -- raises a Lua error, and because the chat box calls slash handlers
    -- unprotected, that error aborts ChatEditBox:ParseText before it reaches
    -- `self:ClearChat()` (ChatFrameEditBox.lua:259-262) - which is why Enter
    -- appeared to do nothing at all. Pass the numeric ID.
    if not CastQueueOverlayOptionsCategory then
        print("|cff33ff99CastQueueOverlay:|r options panel failed to register - check for Lua errors (/console scriptErrors 1).")
        return
    end
    Settings.OpenToCategory(CastQueueOverlayOptionsCategory:GetID())
end
