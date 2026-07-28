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

local statusText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
statusText:SetPoint("TOPLEFT", editBox, "BOTTOMLEFT", -6, -8)
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
-- Instead we poll GetMouseFoci() on an OnUpdate. For click detection,
-- we temporarily hook WorldFrame's OnMouseDown.
local currentTarget
local isSelecting = false
local originalWorldFrameOnMouseDown

local function FindFrameUnderCursor()
    -- GetMouseFoci() is plural and returns a TABLE (TWW+). The old singular
    -- GetMouseFocus() does not exist in 12.0.7 - verified absent from both the
    -- generated API docs and Blizzard's UI source - so there is no fallback to make.
    local foci = GetMouseFoci and GetMouseFoci() or {}
    for _, frame in ipairs(foci) do
        if frame ~= highlight then
            return frame
        end
    end
    return nil
end

-- Walk up to the nearest ancestor that has a global name, since many
-- frames (especially inner textures/statusbars) are anonymous and can't
-- be referenced by name after a reload.
local function GetNamedAncestor(frame)
    while frame do
        local ok, name = pcall(function() return frame.GetName and frame:GetName() end)
        if ok and name and name ~= "" then
            return frame, name
        end
        local ok2, parent = pcall(function() return frame.GetParent and frame:GetParent() end)
        frame = ok2 and parent or nil
    end
    return nil, nil
end

local function StopSelecting()
    isSelecting = false
    highlight:Hide()
    currentTarget = nil
    selectButton:SetText("Select Frame")
    -- Restore original WorldFrame OnMouseDown
    if originalWorldFrameOnMouseDown then
        WorldFrame:SetScript("OnMouseDown", originalWorldFrameOnMouseDown)
        originalWorldFrameOnMouseDown = nil
    end
end

-- Position the highlight frame to exactly cover the target frame using
-- absolute screen coordinates, since the highlight and target may have
-- different parents/strata.
local function PositionHighlight(target)
    if not target then return end
    highlight:ClearAllPoints()
    -- Use GetRect to get absolute screen coordinates
    local left, bottom, width, height = target:GetRect()
    if left and bottom and width and height then
        highlight:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
        highlight:SetSize(width, height)
        highlight:Show()
    else
        highlight:Hide()
    end
end

-- Polling frame for cursor tracking (no mouse capture, doesn't block anything)
local poller = CreateFrame("Frame")
poller:Hide()
poller:SetScript("OnUpdate", function()
    if not isSelecting then return end
    local target = FindFrameUnderCursor()
    if target ~= currentTarget then
        currentTarget = target
        PositionHighlight(target)
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

        local target = currentTarget
        StopSelecting()
        poller:Hide()

        if not target then
            statusText:SetText("|cffff5555No frame under cursor.|r")
            return
        end

        local namedFrame, name = GetNamedAncestor(target)
        if not namedFrame then
            statusText:SetText("|cffff5555That frame (and its parents) have no usable name - try a different one.|r")
            return
        end

        TrySetFrameByName(name)
    end)

    -- Hook Escape key via the panel's key handling
    panel:SetPropagateKeyboardInput(true)
    panel:SetScript("OnKeyDown", function(self, key)
        if not isSelecting then return end
        if key == "ESCAPE" then
            StopSelecting()
            poller:Hide()
            statusText:SetText("Selection cancelled.")
            self:SetPropagateKeyboardInput(false)
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
category.ID = ADDON_NAME
Settings.RegisterAddOnCategory(category)

-- Expose the category globally so the slash command can open it reliably
-- (Settings.OpenToCategory works best with the category object, not just the ID string)
CastQueueOverlayOptionsCategory = category
CastQueueOverlaySettingsCategory = category
