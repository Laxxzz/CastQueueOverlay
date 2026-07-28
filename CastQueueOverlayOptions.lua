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

-- Size in UIParent-space. A region's own width/height are in ITS coordinate
-- system, so they have to be scaled before being compared to anything else.
local function NormalisedSize(region)
    local ok, w, h = pcall(function() return region:GetWidth(), region:GetHeight() end)
    if not ok or not w or not h or w <= 0 or h <= 0 then return nil end

    local scale = 1
    if region.GetEffectiveScale then
        local ok2, s = pcall(region.GetEffectiveScale, region)
        local parentScale = UIParent:GetEffectiveScale()
        if ok2 and s and parentScale and parentScale > 0 then
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

local function FindFrameUnderCursor()
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
    local best, bestName, bestArea
    for _, region in ipairs(stack) do
        if not IsUselessPick(region) and not CoversScreen(region) then
            local name = RegionName(region)
            if name then
                local w, h = NormalisedSize(region)
                if w then
                    local area = w * h
                    if not bestArea or area < bestArea then
                        best, bestName, bestArea = region, name, area
                    end
                end
            end
        end
    end
    if best then return best, bestName end

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
                if name and not CoversScreen(node) then return node, name end
                local ok, parent = pcall(node.GetParent, node)
                node = ok and parent or nil
            end
            break
        end
    end

    return nil, nil
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
    local w, h = target:GetWidth(), target:GetHeight()
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
poller:SetScript("OnUpdate", function()
    if not isSelecting then return end
    local target, name = FindFrameUnderCursor()
    if target == currentTarget then return end

    currentTarget = target
    currentTargetName = name
    PositionHighlight(target)

    if name then
        pickerText:SetText("Under cursor: |cff33ff99" .. name .. "|r")
    else
        -- Genuinely nothing selectable here, rather than a silent UIParent.
        pickerText:SetText("Under cursor: |cff999999(no named frame)|r")
    end
end)

selectButton:SetScript("OnClick", function()
    if isSelecting then
        StopSelecting()
        return
    end
    isSelecting = true
    currentTarget = nil
    statusText:SetText("Click a frame in your UI to select it. (Esc to cancel)")
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
    panel:SetScript("OnKeyDown", function(self, key)
        if not isSelecting then return end
        if key == "ESCAPE" then
            StopSelecting()
            statusText:SetText("Selection cancelled.")
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
