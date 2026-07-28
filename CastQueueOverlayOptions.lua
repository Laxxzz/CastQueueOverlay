-- CastQueueOverlay options panel: color picker + frame selection (manual
-- entry or click-to-pick).

local ADDON_NAME = ...

-- The namespace guard MUST be repeated in every file that touches it. A `local`
-- captures the value at this instant, so if this file loads first (it does - see
-- the TOC) and the table does not exist yet, `addon` would capture nil forever,
-- and the first `function addon.X()` below would throw and abort this whole file.
CastQueueOverlay = CastQueueOverlay or {}
local addon = CastQueueOverlay

local panel = CreateFrame("Frame")
panel.name = "Cast Queue Overlay"

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("Cast Queue Overlay")

local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
subtitle:SetWidth(500)
subtitle:SetJustifyH("LEFT")
subtitle:SetText("Shades the trailing portion of your cast bar that falls within your current SpellQueueWindow.")

-- -----------------------------------------------------------------
-- Color picker
-- -----------------------------------------------------------------
local colorLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
colorLabel:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -24)
colorLabel:SetText("Overlay color")

local swatch = CreateFrame("Button", nil, panel, "BackdropTemplate")
swatch:SetSize(24, 24)
swatch:SetPoint("LEFT", colorLabel, "RIGHT", 12, 0)
swatch:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8x8",
    edgeFile = "Interface/Buttons/WHITE8x8",
    edgeSize = 1,
})
swatch:SetBackdropColor(0, 0, 0, 1)
swatch:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

local swatchTex = swatch:CreateTexture(nil, "ARTWORK")
swatchTex:SetPoint("TOPLEFT", 2, -2)
swatchTex:SetPoint("BOTTOMRIGHT", -2, 2)
swatchTex:SetColorTexture(1, 1, 1, 1)

local function UpdateSwatch()
    local c = CastQueueOverlayDB
    swatchTex:SetVertexColor(c.r, c.g, c.b, c.a)
end

local function OnColorChanged()
    local r, g, b = ColorPickerFrame:GetColorRGB()
    local a = ColorPickerFrame:GetColorAlpha()
    CastQueueOverlayDB.r, CastQueueOverlayDB.g, CastQueueOverlayDB.b, CastQueueOverlayDB.a = r, g, b, a
    UpdateSwatch()
    addon.Refresh()
end

swatch:SetScript("OnClick", function()
    local c = CastQueueOverlayDB
    -- Snapshot by value. `c` is the same table as CastQueueOverlayDB, so it is
    -- mutated live by swatchFunc while the picker is open and cannot serve as a
    -- restore point.
    local prevR, prevG, prevB, prevA = c.r, c.g, c.b, c.a

    ColorPickerFrame:SetupColorPickerAndShow({
        swatchFunc = OnColorChanged,
        opacityFunc = OnColorChanged,
        cancelFunc = function(prev)
            -- ColorPickerFrame builds this as {r=, g=, b=, a=} - note alpha is
            -- passed IN as `opacity` but comes BACK as `a`.
            CastQueueOverlayDB.r = (prev and prev.r) or prevR
            CastQueueOverlayDB.g = (prev and prev.g) or prevG
            CastQueueOverlayDB.b = (prev and prev.b) or prevB
            CastQueueOverlayDB.a = (prev and prev.a) or prevA
            UpdateSwatch()
            addon.Refresh()
        end,
        hasOpacity = 1,
        opacity = c.a,
        r = c.r, g = c.g, b = c.b,
    })
end)

-- Let the /cqo slash command's quick color set keep the swatch in sync
-- if the panel happens to be open.
function addon.OnColorChangedExternally()
    UpdateSwatch()
end

-- -----------------------------------------------------------------
-- Current frame: name field + manual entry
-- -----------------------------------------------------------------
local frameLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
frameLabel:SetPoint("TOPLEFT", colorLabel, "BOTTOMLEFT", 0, -32)
frameLabel:SetText("Cast bar frame (global frame name)")

local editBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
editBox:SetSize(240, 20)
editBox:SetAutoFocus(false)
editBox:SetPoint("TOPLEFT", frameLabel, "BOTTOMLEFT", 6, -8)

local okButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
okButton:SetSize(60, 22)
okButton:SetText("Okay")
okButton:SetPoint("LEFT", editBox, "RIGHT", 8, 0)

-- Anchored further down, once selectButton and the live picker readout exist.
-- It is positioned last on purpose: it wraps, so its height changes with the
-- message, and anything anchored below it would jump around.
local statusText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
statusText:SetWidth(420)
statusText:SetJustifyH("LEFT")

local function TrySetFrameByName(name)
    name = name and strtrim(name)
    if not name or name == "" then
        statusText:SetText("|cffff5555Enter a frame name.|r")
        return
    end
    if not _G[name] then
        statusText:SetText("|cffff5555No frame named '" .. name .. "' exists.|r")
        return
    end
    if addon.SetCastBarByName(name) then
        statusText:SetText("|cff33ff99Cast bar set to " .. name .. ".|r")
    else
        statusText:SetText("|cffff5555'" .. name .. "' isn't a usable frame.|r")
    end
end

okButton:SetScript("OnClick", function() TrySetFrameByName(editBox:GetText()) end)
editBox:SetScript("OnEnterPressed", function(self)
    TrySetFrameByName(self:GetText())
    self:ClearFocus()
end)
editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

-- Called by the core file whenever the cast bar frame changes, so the
-- field always reflects reality (including changes made via /cqo or the
-- picker below).
function addon.OnCastBarChanged(name)
    editBox:SetText(name or "")
end

-- -----------------------------------------------------------------
-- Click-to-select frame picker
-- -----------------------------------------------------------------
local selectButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
selectButton:SetSize(140, 22)
selectButton:SetText("Select Frame")
selectButton:SetPoint("TOPLEFT", editBox, "BOTTOMLEFT", 0, -16)

-- Live readout of what is under the cursor while picking. This shows the frame
-- that clicking would actually select, not merely the topmost region, so the
-- label, the green outline and the result of a click always agree.
local pickerText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
pickerText:SetPoint("TOPLEFT", selectButton, "BOTTOMLEFT", 0, -10)
pickerText:SetWidth(420)
pickerText:SetJustifyH("LEFT")
pickerText:SetText("")

statusText:SetPoint("TOPLEFT", pickerText, "BOTTOMLEFT", 0, -10)

-- Green outline drawn around whatever frame is currently under the cursor.
local highlight = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
highlight:SetBackdrop({
    edgeFile = "Interface/Buttons/WHITE8x8",
    edgeSize = 2,
})
highlight:SetBackdropBorderColor(0, 1, 0, 1)
highlight:SetFrameStrata("TOOLTIP")
highlight:EnableMouse(false)
highlight:Hide()

-- We don't use a full-screen catcher frame (it blocks mouse events).
-- Instead we poll C_System.GetFrameStack() on an OnUpdate. For click detection,
-- we temporarily hook WorldFrame's OnMouseDown.
local currentTarget
local currentTargetName
local isSelecting = false
local originalWorldFrameOnMouseDown
local poller -- created below; forward-declared so StopSelecting can stop it

-- Frames that are under the cursor almost everywhere and are never what anyone
-- means to pick. UIParent in particular was the whole problem: it is the common
-- ancestor of nearly everything, so walking up from an anonymous region landed
-- on it constantly.
local function IsUselessPick(region)
    return region == nil
        or region == highlight
        or region == UIParent
        or region == WorldFrame
end

local function RegionName(region)
    if not region or not region.GetName then return nil end
    local ok, name = pcall(region.GetName, region)
    if ok and name and name ~= "" then return name end
    return nil
end

-- A widget's size is SECRET when the addon that owns it derived that size from
-- secret data - EllesmereUIResourceBars sizes bar textures this way. Reading the
-- value back is fine; ORDERED COMPARISON on it throws:
--
--   attempt to compare local 'w' (a secret number value, while execution
--   tainted by 'CastQueueOverlay')
--
-- Truthiness is safe (`not w` on a secret is fine, which is why the old guard
-- got as far as the `<=`), and arithmetic is safe but propagates secrecy - so a
-- secret width silently poisons `area` and blows up later in table.sort instead,
-- far from the cause. Screen this out at the source.
--
-- Unknown is treated as secret on purpose: declining to rank a region is always
-- safe, comparing a secret never is.
local function IsSecret(value)
    if not issecretvalue then return false end
    local ok, secret = pcall(issecretvalue, value)
    if not ok then return true end
    return secret
end

-- Size in UIParent-space. A region's own width/height are in ITS coordinate
-- system, so they have to be scaled before being compared to anything else.
local function NormalisedSize(region)
    local ok, w, h = pcall(function() return region:GetWidth(), region:GetHeight() end)
    if not ok or not w or not h then return nil end
    if IsSecret(w) or IsSecret(h) then return nil end
    if w <= 0 or h <= 0 then return nil end

    local scale = 1
    if region.GetEffectiveScale then
        local ok2, s = pcall(region.GetEffectiveScale, region)
        local parentScale = UIParent:GetEffectiveScale()
        -- A secret scale would make the returned size secret too, and the poison
        -- would only surface when the sort compares areas.
        if ok2 and s and not IsSecret(s) and parentScale and parentScale > 0 then
            scale = s / parentScale
        end
    end
    return w * scale, h * scale
end

-- Full-screen overlays are never what someone is pointing AT, but they sit on
-- top of everything and win any "topmost" contest. Concrete case:
-- EllesmereUIQoL's cursor-trail parent ECL_TrailContainer is SetAllPoints(UIParent)
-- at TOOLTIP strata, frame level 9998 (EllesmereUIQoL_Cursor.lua:148-153), so it
-- was returned for every single hover.
local SCREEN_COVER_RATIO = 0.95

local function CoversScreen(region)
    local w, h = NormalisedSize(region)
    if not w then return false end
    local pw, ph = UIParent:GetWidth(), UIParent:GetHeight()
    if not pw or not ph or pw <= 0 or ph <= 0 then return false end
    return w >= pw * SCREEN_COVER_RATIO and h >= ph * SCREEN_COVER_RATIO
end

-- Decorative overlays live at TOOLTIP strata. Blizzard treats that strata as a
-- special case itself (Menu.lua:2121). EllesmereUIQoL alone puts four
-- mouse-disabled decorations there - ECL_TrailContainer, ECL_GCDRoot,
-- ECL_CastRoot and EllesmereUICursorFrame, the last of which FOLLOWS the cursor
-- and so is both tiny and always under it. No size or depth heuristic survives
-- that, which is why these are demoted rather than excluded: demoting keeps them
-- reachable if someone genuinely wants one, and excluding by name would just
-- start an arms race with every UI suite.
local function IsDecorative(region)
    if not region.GetFrameStrata then return false end
    local ok, strata = pcall(region.GetFrameStrata, region)
    return ok and strata == "TOOLTIP"
end

-- Rebuilt each poll. Ranked best-guess first, but the user can cycle, because no
-- ranking is going to be right for every UI.
local candidates = {}
local candidateIndex = 1

local function CollectCandidates()
    -- GetMouseFoci() was the wrong primitive and is why the picker kept landing
    -- on WorldFrame. It only reports regions with mouse input ENABLED; cast bars
    -- and most display-only frames call EnableMouse(false), so they are never in
    -- that list, and with nothing else eligible the cursor resolves to WorldFrame
    -- across most of the screen.
    --
    -- C_System.GetFrameStack() returns every region under the cursor regardless
    -- of mouse state - it is what Blizzard's own /framestack is built on
    -- (SlashCommands.lua:1350, Blizzard_DebugTools.lua:140).
    local stack = C_System and C_System.GetFrameStack and C_System.GetFrameStack() or {}

    -- Search the stack itself for something NAMED rather than taking the topmost
    -- region and walking up its parents. Most regions under the cursor are
    -- anonymous textures and inner bars; a parent-walk escapes straight to
    -- UIParent for nearly all of them. A sibling in the stack is a far better
    -- answer than a distant ancestor, and it can only ever return something the
    -- cursor is genuinely over.
    --
    -- Of those candidates, take the SMALLEST rather than the topmost. Stack order
    -- is confirmed topmost-first, but topmost is the wrong question: a
    -- screen-covering overlay is always topmost and never the intended target,
    -- while the thing you are actually pointing at is the most specific region
    -- containing the cursor. Smallest-area is also independent of stack order, so
    -- it cannot silently rot if that ordering ever changes.
    candidates = {}
    for _, region in ipairs(stack) do
        -- Name first: it is cheap, cannot involve secrets, and discards the
        -- anonymous inner textures that make up most of a stack - which is
        -- exactly where secret sizes live. CoversScreen does size maths, so it
        -- must not run on regions we were going to reject anyway.
        if not IsUselessPick(region) then
            local name = RegionName(region)
            if name and not CoversScreen(region) then
                local w, h = NormalisedSize(region)
                if w then
                    candidates[#candidates + 1] = {
                        region = region,
                        name = name,
                        area = w * h,
                        decorative = IsDecorative(region),
                    }
                end
            end
        end
    end

    -- Real UI first, then most specific. Sorting rather than picking means a
    -- wrong guess costs a keypress instead of a bug report.
    table.sort(candidates, function(a, b)
        if a.decorative ~= b.decorative then return b.decorative end
        if a.area ~= b.area then return a.area < b.area end
        return a.name < b.name -- stable, so the list does not jitter while hovering
    end)

    if #candidates > 0 then return end

    -- Nothing in the stack is named. Fall back to a bounded parent walk from the
    -- topmost usable region, stopping BEFORE the catch-alls so a miss reports as
    -- a miss instead of silently selecting UIParent.
    for _, region in ipairs(stack) do
        if not IsUselessPick(region) and not CoversScreen(region) then
            local node = region
            while node and not IsUselessPick(node) do
                local name = RegionName(node)
                -- Same exclusion on the way up: a screen-covering ancestor is no
                -- more useful than a screen-covering sibling.
                if name and not CoversScreen(node) then
                    local w, h = NormalisedSize(node)
                    candidates[1] = {
                        region = node,
                        name = name,
                        area = (w and h) and (w * h) or 0,
                        decorative = IsDecorative(node),
                    }
                    return
                end
                local ok, parent = pcall(node.GetParent, node)
                node = ok and parent or nil
            end
            break
        end
    end
end

local function CurrentCandidate()
    if #candidates == 0 then return nil, nil end
    -- Clamp rather than reset. The set changes constantly as the cursor moves, and
    -- resetting to 1 on every change would make cycling impossible to hold onto.
    if candidateIndex > #candidates then candidateIndex = #candidates end
    if candidateIndex < 1 then candidateIndex = 1 end
    local entry = candidates[candidateIndex]
    return entry.region, entry.name
end

-- Every exit path must go through here. Selecting installs three things - a
-- WorldFrame script, an OnUpdate poller and a keyboard grab - and leaking any
-- one of them outlives the picker.
local function StopSelecting()
    isSelecting = false
    highlight:Hide()
    currentTarget = nil
    selectButton:SetText("Select Frame")

    if poller then poller:Hide() end
    currentTargetName = nil
    pickerText:SetText("")
    candidates = {}
    candidateIndex = 1

    -- Restore original WorldFrame OnMouseDown. Note the original is usually nil,
    -- so this has to be unconditional - keying it off a truthy check would leave
    -- our handler installed forever.
    WorldFrame:SetScript("OnMouseDown", originalWorldFrameOnMouseDown)
    originalWorldFrameOnMouseDown = nil

    -- Release the keyboard. A frame with an OnKeyDown script and propagation
    -- turned off swallows every key it receives, so leaving this installed after
    -- the picker exits breaks typing while the panel is up.
    panel:SetScript("OnKeyDown", nil)
    panel:EnableKeyboard(false)
    panel:SetPropagateKeyboardInput(true)
end

-- Position the highlight frame to exactly cover the target frame using
-- absolute screen coordinates, since the highlight and target may have
-- different parents/strata.
local function PositionHighlight(target)
    highlight:ClearAllPoints()
    if not target then
        highlight:Hide()
        return
    end

    -- Anchor directly to the target instead of converting GetRect() into
    -- UIParent-space coordinates. GetRect returns values in the target's OWN
    -- coordinate system, so any frame whose effective scale differs from
    -- UIParent's - which is most of a custom UI, and all of EllesmereUI - was
    -- outlined at the wrong place and size, or off-screen entirely. Anchoring
    -- lets the engine resolve the scale difference.
    local ok = pcall(function()
        highlight:SetPoint("TOPLEFT", target, "TOPLEFT", 0, 0)
        highlight:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 0, 0)
    end)

    -- A zero-sized region would draw as an invisible outline, which reads as
    -- "the picker is broken" rather than "there is nothing to see here".
    -- NormalisedSize rather than raw GetWidth/GetHeight: this comparison hits the
    -- same secret-value throw, and the highlight runs on every poll.
    local w, h = NormalisedSize(target)
    if not ok or not w or not h or w <= 0 or h <= 0 then
        highlight:ClearAllPoints()
        highlight:Hide()
        return
    end

    highlight:Show()
end

-- Polling frame for cursor tracking (no mouse capture, doesn't block anything)
poller = CreateFrame("Frame")
poller:Hide()
-- Walking the frame stack and sorting it every single frame is real work for no
-- benefit; the cursor cannot move meaningfully in 16ms.
local POLL_INTERVAL = 0.1
local sinceLastPoll = 0

local function RefreshPicker()
    CollectCandidates()
    local target, name = CurrentCandidate()

    currentTarget = target
    currentTargetName = name
    PositionHighlight(target)

    if not name then
        -- Genuinely nothing selectable here, rather than a silent UIParent.
        pickerText:SetText("Under cursor: |cff999999(no named frame)|r")
        return
    end

    local suffix = ""
    if #candidates > 1 then
        suffix = ("  |cff999999(%d of %d - TAB to cycle)|r"):format(candidateIndex, #candidates)
    end
    pickerText:SetText("Under cursor: |cff33ff99" .. name .. "|r" .. suffix)
end

poller:SetScript("OnUpdate", function(self, elapsed)
    if not isSelecting then return end
    sinceLastPoll = sinceLastPoll + elapsed
    if sinceLastPoll < POLL_INTERVAL then return end
    sinceLastPoll = 0
    RefreshPicker()
end)

selectButton:SetScript("OnClick", function()
    if isSelecting then
        StopSelecting()
        return
    end
    isSelecting = true
    currentTarget = nil
    candidateIndex = 1
    statusText:SetText("Click a frame in your UI to select it. TAB cycles overlapping frames, Esc cancels.")
    selectButton:SetText("Selecting... (Esc to cancel)")
    poller:Show()

    -- Hook WorldFrame for click detection (doesn't block other frames)
    originalWorldFrameOnMouseDown = WorldFrame:GetScript("OnMouseDown")
    WorldFrame:SetScript("OnMouseDown", function(self, button)
        if not isSelecting then return end
        if button ~= "LeftButton" then return end

        -- Use the name the readout was already showing. Re-deriving it here is
        -- what let the click disagree with the outline and the label.
        local name = currentTargetName
        StopSelecting()

        if not name then
            statusText:SetText("|cffff5555Nothing selectable there - no named frame under the cursor.|r")
            return
        end

        TrySetFrameByName(name)
    end)

    -- Escape cancels. The frame has to actually accept keyboard input to see the
    -- key at all, and propagation must stay ON so every other key still reaches
    -- chat and the rest of the UI while the picker is armed. StopSelecting tears
    -- all of this back down.
    panel:EnableKeyboard(true)
    panel:SetPropagateKeyboardInput(true)
    -- TAB cycles rather than the mouse wheel: while picking, the cursor is over
    -- arbitrary frames, and catching the wheel globally would need the very
    -- full-screen mouse-enabled catcher this design avoids. Keyboard input is
    -- frame-local and works wherever the cursor happens to be.
    --
    -- Propagation is turned off for exactly the two keys we consume and left on
    -- for everything else, so chat and the rest of the UI keep working.
    panel:SetScript("OnKeyDown", function(self, key)
        if not isSelecting then
            self:SetPropagateKeyboardInput(true)
            return
        end

        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            StopSelecting()
            statusText:SetText("Selection cancelled.")
        elseif key == "TAB" then
            self:SetPropagateKeyboardInput(false)
            if #candidates > 1 then
                candidateIndex = candidateIndex + 1
                if candidateIndex > #candidates then candidateIndex = 1 end
                RefreshPicker()
            end
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
end)

-- -----------------------------------------------------------------
-- Keep the panel in sync whenever it's shown
-- -----------------------------------------------------------------
panel:SetScript("OnShow", function()
    UpdateSwatch()
    editBox:SetText(addon.GetCastBarName())
    statusText:SetText("")
end)

-- -----------------------------------------------------------------
-- Register with the Settings UI
-- -----------------------------------------------------------------
local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)

-- DO NOT set `category.ID`. It looks like a way to give the category a friendly
-- name, but `SettingsCategoryMixin:Init` assigns `self.ID = idCounter()` - a
-- NUMBER that the Settings registry uses to find this category
-- (Blizzard_Category.lua:8-14). Overwriting it with the addon name orphaned the
-- category for the whole session, so nothing could open it.
Settings.RegisterAddOnCategory(category)

-- Exposed for the slash command. It must pass `:GetID()`, not this table -
-- see the comment on the handler in CastQueueOverlay.lua.
CastQueueOverlayOptionsCategory = category
CastQueueOverlaySettingsCategory = category
