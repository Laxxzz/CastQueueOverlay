-- CastQueueOverlay
-- Paints a translucent overlay over the trailing portion of your cast bar
-- that corresponds to the current SpellQueueWindow CVar (in ms), relative
-- to the total length of the cast/channel currently in progress.

local ADDON_NAME = ...

-- ---------------------------------------------------------------------
-- Saved settings
-- ---------------------------------------------------------------------
-- Three independent overlays, each a time value painted onto the trailing end of
-- the bar. They are drawn stacked, so any combination can be on at once.
local defaults = {
    frameName = nil, -- nil/empty = use the default Blizzard player cast bar
    overlays = {
        queue   = { enabled = true,  r = 1.00, g = 1.00, b = 1.00, a = 0.35 },
        latency = { enabled = false, r = 0.35, g = 0.72, b = 1.00, a = 0.35 },
        custom  = { enabled = false, r = 0.85, g = 0.47, b = 0.34, a = 0.35, valueMS = 200 },
    },
}

-- `DB = DB or {}` alone only covers a first run. A user upgrading from a build
-- that predates a key keeps their saved table, that key stays nil, and the addon
-- breaks only for existing users - which never reproduces on a fresh install.
--
-- This MUST run inside ContinueOnAddOnLoaded, not at file scope. Saved variables
-- are restored before ADDON_LOADED fires but after this file executes, so a
-- file-scope merge builds a defaults table that the restore then replaces
-- wholesale - the merge is silently discarded and every key the saved table
-- lacks stays nil. Every read below (ResolveCastBar, ApplyOverlay's colour) runs
-- later than this callback, so nothing races it.
local function ApplyDefaults(db, src)
    for k, v in pairs(src) do
        if db[k] == nil then
            db[k] = (type(v) == "table") and CopyTable(v) or v
        elseif type(v) == "table" and type(db[k]) == "table" then
            ApplyDefaults(db[k], v) -- recurse, so nested keys are filled on upgrade
        end
    end
    return db
end

EventUtil.ContinueOnAddOnLoaded(ADDON_NAME, function()
    CastQueueOverlayDB = CastQueueOverlayDB or {}

    -- Migrate the pre-multi-overlay schema, where the single overlay's colour
    -- lived in flat r/g/b/a keys at the top level. Runs before ApplyDefaults so
    -- the user's existing colour becomes the queue overlay's colour rather than
    -- being replaced by the default white.
    if CastQueueOverlayDB.r ~= nil and CastQueueOverlayDB.overlays == nil then
        CastQueueOverlayDB.overlays = {
            queue = {
                enabled = true,
                r = CastQueueOverlayDB.r,
                g = CastQueueOverlayDB.g,
                b = CastQueueOverlayDB.b,
                a = CastQueueOverlayDB.a,
            },
        }
        CastQueueOverlayDB.r, CastQueueOverlayDB.g = nil, nil
        CastQueueOverlayDB.b, CastQueueOverlayDB.a = nil, nil
    end

    ApplyDefaults(CastQueueOverlayDB, defaults)
end)

-- Shared namespace so the options panel can drive the overlay without
-- reaching into locals.
CastQueueOverlay = CastQueueOverlay or {}
local addon = CastQueueOverlay
addon.DEFAULT_FRAME_NAME = "PlayerCastingBarFrame"

-- Fixed iteration order. `pairs` over the overlays table would vary run to run,
-- and these are drawn in a computed z-order that has to be reproducible.
--
-- These live HERE, below the namespace capture, and not up beside `defaults`
-- where they logically belong. `addon` is a local assigned on the line above; any
-- `addon.X = ...` placed earlier in the file indexes a nil global and aborts the
-- whole file at load - taking the slash command, the event handler and every
-- public function with it. See decision #1: this file has been broken this exact
-- way before.
-- Labels deliberately live in the options file, not here. This file loads LAST,
-- so the options file cannot read anything off `addon` at its own file scope -
-- a shared label table would have to be consumed lazily, and two constants that
-- must agree are worse than one owned by the file that draws them.
addon.OVERLAY_KEYS = { "queue", "latency", "custom" }

local overlays = {}   -- key -> texture
local overlay          -- the queue texture; kept so EnsureOverlay can report success
local castBar
local activeStartMS, activeEndMS
local hookedBars = {}   -- frames whose OnSizeChanged we have already hooked

-- ---------------------------------------------------------------------
-- Resolving / (re)building the overlay texture on whichever frame is
-- currently configured as the "cast bar".
-- ---------------------------------------------------------------------
-- Returns the frame the overlay SHOULD be on right now, or nil if the frame the
-- user configured does not exist yet.
--
-- There is deliberately NO fallback to the Blizzard bar when a name is
-- configured. That fallback was the bug: cast bar addons create their frames
-- lazily, usually later than our PLAYER_LOGIN. EllesmereUIResourceBars only
-- builds ERB_CastBar when its cast bar module runs
-- (EllesmereUIResourceBars.lua:6238) and suppresses PlayerCastingBarFrame in the
-- same function. So at login the name resolved to nil, we silently attached to
-- Blizzard's bar, EllesmereUI then hid that bar, and `castBar` stayed cached on
-- it for the rest of the session - an overlay painted onto a hidden frame.
-- Re-picking the bar in the options panel rebuilt it against the now-existing
-- frame, which is exactly why reapplying "fixed" it until the next reload.
--
-- If the user named a frame, that frame is the only correct answer. Returning
-- nil and retrying is honest; substituting a different bar is not.
local function ResolveCastBar()
    local name = CastQueueOverlayDB.frameName
    if name and name ~= "" then
        return _G[name]
    end
    return _G[addon.DEFAULT_FRAME_NAME]
end

local function DestroyOverlay()
    for key, tex in pairs(overlays) do
        tex:Hide()
        tex:ClearAllPoints()
        tex:SetParent(UIParent)
        overlays[key] = nil
    end
    overlay = nil
end

local function HideAllOverlays()
    for _, tex in pairs(overlays) do
        tex:Hide()
    end
end

-- Milliseconds represented by each overlay. All three are ms, matching
-- startTimeMs/endTimeMs, so the ratio in ApplyOverlay stays unit-free.
local function OverlayValueMS(key)
    if key == "queue" then
        -- GetCVar returns a STRING, always.
        return tonumber(GetCVar("SpellQueueWindow")) or 0

    elseif key == "latency" then
        -- GetNetStats returns in, out, latencyHome, latencyWorld
        -- (PerformanceBar.lua:60). Home is the realm connection and is the right
        -- number for spell queueing; world is the fallback when home reads 0,
        -- which happens briefly after login and on some connection changes.
        local _, _, latencyHome, latencyWorld = GetNetStats()
        latencyHome = tonumber(latencyHome) or 0
        if latencyHome > 0 then return latencyHome end
        return tonumber(latencyWorld) or 0

    elseif key == "custom" then
        return tonumber(CastQueueOverlayDB.overlays.custom.valueMS) or 0
    end
    return 0
end
addon.OverlayValueMS = OverlayValueMS

local function EnsureOverlay()
    local want = ResolveCastBar()
    if not want then return nil end

    -- Rebuild whenever the frame we should be on is not the frame we are on.
    -- This covers two cases with one check: the first successful resolve after a
    -- late-loading cast bar addon finally creates its frame, and a bar being torn
    -- down and recreated under the same global name (cast bar addons do this when
    -- their own settings change). Resolving once and caching the answer is what
    -- stranded the overlay on a hidden frame until the user re-picked it.
    if castBar ~= want then
        DestroyOverlay()
        castBar = want
    end

    if overlay then return overlay end

    for _, key in ipairs(addon.OVERLAY_KEYS) do
        local tex = castBar:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(1, 1, 1, 1)
        tex:Hide()
        overlays[key] = tex
    end
    overlay = overlays.queue

    -- Keep the overlay's width correct if the bar itself is resized (e.g. via
    -- Edit Mode). Hooks can never be removed, so track which bars we have already
    -- hooked - SetCastBarByName destroys and rebuilds the overlay, which would
    -- otherwise stack a new hook every time the user switches bars.
    if not hookedBars[castBar] then
        hookedBars[castBar] = true
        castBar:HookScript("OnSizeChanged", function()
            -- Keyed off a cast being in progress, not off one texture being
            -- visible: the queue overlay can be disabled while latency or custom
            -- are still drawn, and those would then never track a resize.
            if activeStartMS then
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
        HideAllOverlays()
        return
    end

    local castDuration = endMS - startMS
    if castDuration <= 0 then
        HideAllOverlays()
        return
    end

    activeStartMS, activeEndMS = startMS, endMS

    local barWidth = castBar:GetWidth()

    -- Collect what is actually going to be drawn, so the z-order can be decided
    -- from the real set rather than assumed from the config.
    local visible = {}
    for _, key in ipairs(addon.OVERLAY_KEYS) do
        local cfg = CastQueueOverlayDB.overlays[key]
        local tex = overlays[key]
        local valueMS = cfg.enabled and OverlayValueMS(key) or 0
        local pct = valueMS / castDuration

        if not cfg.enabled or pct <= 0 then
            tex:Hide()
        else
            if pct > 1 then pct = 1 end
            visible[#visible + 1] = { key = key, tex = tex, cfg = cfg, pct = pct }
        end
    end

    -- All three share the same right edge, so a wider one drawn on top would
    -- completely bury a narrower one. Sort widest first and give the narrower
    -- overlays higher sublevels, so every enabled overlay stays visible and the
    -- stack reads as bands from the end of the bar inward.
    table.sort(visible, function(a, b)
        if a.pct ~= b.pct then return a.pct > b.pct end
        return a.key < b.key -- total order; equal values must not shuffle per frame
    end)

    for i, entry in ipairs(visible) do
        local tex, cfg = entry.tex, entry.cfg
        tex:ClearAllPoints()
        tex:SetPoint("TOPRIGHT", castBar, "TOPRIGHT", 0, 0)
        tex:SetPoint("BOTTOMRIGHT", castBar, "BOTTOMRIGHT", 0, 0)
        tex:SetWidth(barWidth * entry.pct)
        tex:SetColorTexture(cfg.r, cfg.g, cfg.b, cfg.a)
        -- Sublevel accepts -8..7; three overlays never exhaust that.
        tex:SetDrawLayer("OVERLAY", i)
        tex:Show()
    end
end

-- Public: recompute using whatever cast is currently tracked (used after
-- color changes, CVAR_UPDATE, bar resize, etc).
function addon.Refresh()
    ApplyOverlay(activeStartMS, activeEndMS)
end

-- ---------------------------------------------------------------------
-- Waiting for a late-loading cast bar
-- ---------------------------------------------------------------------
-- We cannot know when another addon will create its bar - there is no event for
-- "some addon made a frame". Poll on a bounded ticker rather than an OnUpdate,
-- and stop the moment it resolves. If it never turns up, say so instead of
-- failing silently, because a missing frame is indistinguishable from a broken
-- addon from the player's side.
local RESOLVE_INTERVAL = 0.5
local RESOLVE_ATTEMPTS = 40 -- 20 seconds
local resolveTicker

local function StopResolveRetry()
    if resolveTicker then
        resolveTicker:Cancel()
        resolveTicker = nil
    end
end

local function StartResolveRetry()
    StopResolveRetry()
    if EnsureOverlay() then return end

    -- Cancel through the captured upvalue rather than a callback argument.
    -- Blizzard always drives tickers this way (TutorialRangeManager.lua:116-120)
    -- and never uses an argument, so the argument form is unverified here. The
    -- upvalue is assigned before the first tick can fire.
    local attempts = 0
    resolveTicker = C_Timer.NewTicker(RESOLVE_INTERVAL, function()
        attempts = attempts + 1
        if EnsureOverlay() then
            StopResolveRetry()
        elseif attempts >= RESOLVE_ATTEMPTS then
            StopResolveRetry()
            local name = CastQueueOverlayDB.frameName
            print(("|cff33ff99CastQueueOverlay:|r no frame named '%s' appeared after %d seconds. "):format(
                tostring(name), RESOLVE_INTERVAL * RESOLVE_ATTEMPTS)
                .. "If that cast bar addon was disabled or renamed its frame, pick a new bar with /cqo.")
        end
    end)
end

local function HideOverlay()
    activeStartMS, activeEndMS = nil, nil
    HideAllOverlays()
end

-- Public: switch which frame the overlay is attached to. `name` must be
-- a valid global frame name. Returns true/false for success.
function addon.SetCastBarByName(name)
    local f = name and _G[name]
    if not f or type(f.CreateTexture) ~= "function" then
        return false
    end

    StopResolveRetry()
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
        -- Not just EnsureOverlay(): the configured bar may belong to an addon
        -- that has not built its frames yet.
        StartResolveRetry()
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
    -- Opens our own frame. It deliberately does NOT go through
    -- `Settings.OpenToCategory`, which forwards to the PROTECTED
    -- `C_SettingsUtil.OpenSettingsPanel` and so was blocked in combat:
    --
    --   [ADDON_ACTION_BLOCKED] AddOn 'CastQueueOverlay' tried to call the
    --   protected function 'OpenSettingsPanel()'.
    --
    -- A frame we own carries no restriction, so this works in combat.
    if not addon.ToggleOptions then
        print("|cff33ff99CastQueueOverlay:|r options window failed to load - check for Lua errors (/console scriptErrors 1).")
        return
    end
    addon.ToggleOptions()
end
