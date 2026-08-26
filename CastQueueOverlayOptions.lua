-- CastQueueOverlay options: a standalone window, not a Settings canvas panel.
--
-- It lives outside Blizzard's Settings UI on purpose. `Settings.OpenToCategory`
-- forwards to `C_SettingsUtil.OpenSettingsPanel`, which is PROTECTED
-- (`HasRestrictions = true`), so `/cqo` in combat produced:
--
--   [ADDON_ACTION_BLOCKED] AddOn 'CastQueueOverlay' tried to call the protected
--   function 'OpenSettingsPanel()'.
--
-- A frame we create ourselves carries no such restriction, so this opens in
-- combat. The Settings entry still exists, but only as a button that hands off
-- to this window.
--
-- LAYOUT: this file contains no offset literals. Every row is built through the
-- cursor in CastQueueOverlayLayout.lua and reports the space it consumed, and
-- the window's height is taken from the cursor at the end. The previous version
-- anchored each section to the bottom of the one above it with a hand-picked
-- offset, and pinned the footer hint to the window's BOTTOM edge with a fixed
-- window height chosen to leave the status line room to wrap - two things
-- growing towards each other with a collision waiting for the next setting.
-- Everything now grows in one direction.

local ADDON_NAME = ...

-- The namespace guard MUST be repeated in every file that touches it. A `local`
-- captures the value at this instant, so if this file loads first and the table
-- does not exist yet, `addon` would capture nil forever. See decision #1.
CastQueueOverlay = CastQueueOverlay or {}
local addon = CastQueueOverlay
local S = addon.Style
local L = addon.Layout
local P = addon.Pixel
local size = S.size

local WINDOW_W = 460

-- ---------------------------------------------------------------------
-- Forward declarations
-- ---------------------------------------------------------------------
--
-- Everything the frame picker, the combat watcher and the refresh paths touch is
-- declared HERE, above every closure that reads it.
--
-- This is not tidiness. In 2.2.0 and earlier, `local pendingOptions = false` in
-- the core file sat BELOW the event handler that consumed it, so the handler
-- closed over the global of that name while the slash command set the local, and
-- the deferred open never fired. Same family as decision #1: an upvalue must be
-- declared above every closure that reads it. See decision #15.
local frame                              -- the options window, built lazily
local tabs, pages, activeTab
local frameNameEdit, statusText, pickerText
local selectButton
local channelToggleRow, channelSliderRow

local TAB_KEYS = { "queue", "latency", "custom" }
local TAB_TEXT = {
    queue   = "SpellQueueWindow",
    latency = "Latency",
    custom  = "Custom",
}

local CHANNEL_TOGGLE_LABEL = "Separate opacity while channelling"

local function CfgFor(key)
    return CastQueueOverlayDB.overlays[key]
end

local function Percent(a)
    return ("%d%%"):format(math.floor((a or 0) * 100 + 0.5))
end

local function HexOf(c)
    return ("#%02X%02X%02X"):format(
        math.floor(c.r * 255 + 0.5),
        math.floor(c.g * 255 + 0.5),
        math.floor(c.b * 255 + 0.5))
end

-- ---------------------------------------------------------------------
-- Colour picker
-- ---------------------------------------------------------------------
--
-- Our own, rather than skinning Blizzard's ColorPickerFrame. That frame is
-- SHARED: restyling it would silently change the colour picker for every other
-- addon the player has installed. Acceptable in a personal UI, not in something
-- distributed.
--
-- The wheel, value bar and alpha bar are engine-rendered - note Blizzard's XML
-- gives those textures no `file` attribute (ColorPickerFrame.xml:126-155). We
-- supply blank textures and the engine fills them, so this is a restyle of the
-- chrome only and the colour maths stays Blizzard's.
local PICKER_W = 300
local WHEEL    = 140
local BAR_W    = 20

local picker, pickerSel, pickerHex, pickerOpacityText
local pickerCfg, pickerOnChange, pickerRestore
local suppressCallback = false

local function PickerApply()
    if not pickerCfg or not pickerSel then return end
    local r, g, b = pickerSel:GetColorRGB()
    pickerCfg.r, pickerCfg.g, pickerCfg.b = r, g, b
    pickerCfg.a = pickerSel:GetColorAlpha()

    if not pickerHex:HasFocus() then
        pickerHex:SetText(("%02X%02X%02X"):format(
            math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)))
    end
    pickerOpacityText:SetText(("%s opacity"):format(Percent(pickerCfg.a)))

    if pickerOnChange then pickerOnChange() end
end

local function ClosePicker()
    if picker then picker:Hide() end
    pickerCfg, pickerOnChange, pickerRestore = nil, nil, nil
end

-- Can this client create a ColorSelect at all?
--
-- `ColorSelect` is a first-class widget type in Blizzard's UI schema
-- (UI.xsd:966,982), but Blizzard only ever instantiates it from XML - there is
-- not one `CreateFrame("ColorSelect")` in their entire shipping Lua source. The
-- type ought to be creatable, but "ought to" is not verification, and an error
-- here would abort this whole file at load and take the addon with it.
--
-- Probed ONCE, on a throwaway parent, exactly like the rounded-corner art in the
-- style file. Probing inside the picker's own build instead would mean
-- discovering the failure halfway through a window that is already registered in
-- UISpecialFrames - a hidden, empty frame that Escape still routes to.
local colorSelectSupported
do
    local scratch = CreateFrame("Frame")
    local ok, sel = pcall(CreateFrame, "ColorSelect", nil, scratch)
    colorSelectSupported = (ok and sel) and true or false
    scratch:Hide()
end

-- The wheel and its two bars, as a builder: it returns the space it consumed
-- like everything else, so the picker window's height comes off the same cursor
-- as its buttons.
local function BuildColorSelect(parent, x, width, y)
    local ok, sel = pcall(CreateFrame, "ColorSelect", nil, parent)
    if not ok or not sel then return nil, 0 end

    P.Point(sel, "TOPLEFT", parent, "TOPLEFT", x, y)
    P.Size(sel, WHEEL + size.SECTION + BAR_W + size.SECTION + BAR_W, WHEEL)

    local wheelTex = sel:CreateTexture()
    sel:SetColorWheelTexture(wheelTex)
    wheelTex:SetPoint("TOPLEFT")
    P.Size(wheelTex, WHEEL, WHEEL)

    -- Flat thumbs instead of Interface\Buttons\UI-ColorPicker-Buttons, which
    -- carries Blizzard's gold. White reads against every hue on the wheel.
    local wheelThumb = sel:CreateTexture(nil, "OVERLAY")
    sel:SetColorWheelThumbTexture(wheelThumb)
    P.Size(wheelThumb, 8, 8)
    wheelThumb:SetColorTexture(1, 1, 1, 1)

    local valueTex = sel:CreateTexture()
    sel:SetColorValueTexture(valueTex)
    P.Point(valueTex, "TOPLEFT", wheelTex, "TOPRIGHT", size.SECTION, 0)
    P.Size(valueTex, BAR_W, WHEEL)

    local valueThumb = sel:CreateTexture(nil, "OVERLAY")
    sel:SetColorValueThumbTexture(valueThumb)
    P.Size(valueThumb, BAR_W + 10, 6)
    valueThumb:SetColorTexture(S.Unpack(S.color.accent))

    local alphaTex = sel:CreateTexture()
    sel:SetColorAlphaTexture(alphaTex)
    P.Point(alphaTex, "TOPLEFT", valueTex, "TOPRIGHT", size.SECTION, 0)
    P.Size(alphaTex, BAR_W, WHEEL)

    local alphaThumb = sel:CreateTexture(nil, "OVERLAY")
    sel:SetColorAlphaThumbTexture(alphaThumb)
    P.Size(alphaThumb, BAR_W + 10, 6)
    alphaThumb:SetColorTexture(S.Unpack(S.color.accent))

    -- One handler covers the wheel, the value bar AND the alpha bar. There is no
    -- separate alpha event - Blizzard drives both swatchFunc and opacityFunc
    -- from this same script (ColorPickerFrame.lua:4-17).
    sel:SetScript("OnColorSelect", function()
        if suppressCallback then return end
        PickerApply()
    end)

    return sel, WHEEL
end

local function BuildPicker()
    if not colorSelectSupported then return nil end

    local f = S.Window("CastQueueOverlayColorPickerFrame", "colorPicker",
        PICKER_W, 320, "Overlay colour")
    -- FULLSCREEN_DIALOG, not merely a higher level: a popup launched from inside
    -- a window has to escape that window's strata, or it is clipped by it rather
    -- than drawn over it.
    f:SetFrameStrata("FULLSCREEN_DIALOG")

    local cursor = L.Cursor(f.Content)

    pickerSel = cursor:Add(BuildColorSelect)

    cursor:Gap(size.SECTION)

    local hexRow = cursor:Add(L.Input, {
        label = "Hex",
        width = 84,
        get = function() return "" end,
    })
    pickerHex = hexRow.EditBox

    -- The opacity readout is driven by the alpha bar, so it is reported rather
    -- than edited.
    local opacityRow = cursor:Add(L.Readout, { label = "Opacity", value = "" })
    pickerOpacityText = opacityRow.Value

    cursor:Gap(size.SECTION)

    cursor:Add(L.ButtonRow, {
        { text = "Done", key = "Done", opts = { primary = true, width = 84 },
          onClick = ClosePicker },
        { text = "Cancel", key = "Cancel", opts = { width = 84 },
          onClick = function()
              if pickerCfg and pickerRestore then
                  pickerCfg.r, pickerCfg.g = pickerRestore.r, pickerRestore.g
                  pickerCfg.b, pickerCfg.a = pickerRestore.b, pickerRestore.a
                  if pickerOnChange then pickerOnChange() end
              end
              ClosePicker()
          end },
    })

    -- The height IS the cursor. Header band, the top inset, everything built,
    -- and a bottom inset matching the top.
    f:SetHeight(P.Snap(size.HEADER_H + size.PAD + cursor:Consumed() + size.PAD))

    pickerHex:SetScript("OnEnterPressed", function(self)
        local text = (self:GetText() or ""):gsub("^#", "")
        local r, g, b = text:match("^(%x%x)(%x%x)(%x%x)$")
        if r then
            suppressCallback = true
            pickerSel:SetColorRGB(tonumber(r, 16) / 255, tonumber(g, 16) / 255,
                tonumber(b, 16) / 255)
            suppressCallback = false
            PickerApply()
        end
        self:ClearFocus()
    end)
    pickerHex:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    return f
end

-- Fallback for the case where ColorSelect could not be created. Blizzard's own
-- picker is unstyled but proven - it is what shipped in 2.0.0 - so the feature
-- degrades in appearance rather than breaking.
local function ShowBlizzardColorPicker(cfg, onChange)
    local prevR, prevG, prevB, prevA = cfg.r, cfg.g, cfg.b, cfg.a
    local function apply()
        cfg.r, cfg.g, cfg.b = ColorPickerFrame:GetColorRGB()
        cfg.a = ColorPickerFrame:GetColorAlpha()
        if onChange then onChange() end
    end
    ColorPickerFrame:SetupColorPickerAndShow({
        swatchFunc = apply,
        opacityFunc = apply,
        cancelFunc = function(prev)
            -- Alpha goes IN as `opacity` and comes BACK as `a`.
            cfg.r = (prev and prev.r) or prevR
            cfg.g = (prev and prev.g) or prevG
            cfg.b = (prev and prev.b) or prevB
            cfg.a = (prev and prev.a) or prevA
            if onChange then onChange() end
        end,
        hasOpacity = 1,
        opacity = cfg.a,
        r = cfg.r, g = cfg.g, b = cfg.b,
    })
end

local pickerUnavailable = false

local function ShowColorPicker(cfg, onChange)
    if not picker and not pickerUnavailable then
        picker = BuildPicker()
        pickerUnavailable = (picker == nil)
    end

    if not picker then
        ShowBlizzardColorPicker(cfg, onChange)
        return
    end

    pickerCfg, pickerOnChange = cfg, onChange
    -- Snapshot BY VALUE. cfg is a live reference into the saved variables and is
    -- mutated on every drag, so it cannot serve as its own restore point.
    pickerRestore = { r = cfg.r, g = cfg.g, b = cfg.b, a = cfg.a }

    -- Seed without firing the callback, or the first paint would write the
    -- pre-seed colour straight back over the saved one.
    suppressCallback = true
    pickerSel:SetColorRGB(cfg.r, cfg.g, cfg.b)
    pickerSel:SetColorAlpha(cfg.a or 1)
    suppressCallback = false

    picker:ClearAllPoints()
    picker:SetPoint("TOPLEFT", frame, "TOPRIGHT", size.PAD, 0)
    picker:Show()
    PickerApply()
end

-- ---------------------------------------------------------------------
-- Overlay pages
-- ---------------------------------------------------------------------

-- The colour row: label, a hex/opacity readout, and the swatch that opens the
-- picker. Three regions, each bounded by the next, so none can grow through
-- another however long the readout gets.
--
-- The swatch is SQUARE-cornered with a hairline border, like every other control
-- - only the window itself rounds. See the note on rounding in the style file.
local function ColorRow(parent, x, width, y, key, onChanged, stripe)
    local row = L.Row(parent, x, width, y)
    row:SetStripe(stripe)

    local swatch = CreateFrame("Button", nil, row)
    P.Size(swatch, size.SWATCH_W, size.CTRL_H)
    P.Point(swatch, "RIGHT", row, "RIGHT", -size.ROW_PAD, 0)
    row:AdoptHover(swatch)

    local fill = swatch:CreateTexture(nil, "ARTWORK")
    fill:SetAllPoints(swatch)
    P.Crisp(fill)
    local swatchBorder = S.Border(swatch, S.color.border, "OVERLAY")

    swatch:SetScript("OnEnter", function(self)
        swatchBorder:SetColor(S.color.borderBright)
        if self.cqoHoverIn then self.cqoHoverIn(self) end
    end)
    swatch:SetScript("OnLeave", function(self)
        swatchBorder:SetColor(S.color.border)
        if self.cqoHoverOut then self.cqoHoverOut(self) end
    end)

    local readout = S.Label(row, S.fontSmall, "RIGHT")
    P.Point(readout, "RIGHT", swatch, "LEFT", -size.GAP, 0)
    P.Size(readout, 120, size.CTRL_H)

    local label = L.BoundedLabel(row, readout, "Colour")

    function row:Refresh()
        local c = CfgFor(key)
        fill:SetColorTexture(c.r, c.g, c.b, 1)
        readout:SetText(("%s   %s"):format(HexOf(c), Percent(c.a)))
    end

    local function open()
        ShowColorPicker(CfgFor(key), function()
            row:Refresh()
            if onChanged then onChanged() end
        end)
    end
    swatch:SetScript("OnClick", open)
    row:SetScript("OnMouseUp", open)

    row.Label = label
    return row, size.ROW_H
end

-- Builds the body content for one overlay. Every page is the same three rows;
-- only the last differs, because `custom` is the one overlay whose milliseconds
-- the player supplies rather than the game.
local function BuildPage(body, key)
    local page = CreateFrame("Frame", nil, body)
    page:SetAllPoints(body)
    -- Anchored by two corners, so it has no resolved width in this frame. The
    -- cursor reads this rather than measuring; see L.WidthOf.
    page.cqoWidth = body.cqoWidth
    page:Hide()

    -- Inset from the top by the same gap the body reserves at the bottom, so the
    -- rows sit centred in the recess rather than flush against its top border.
    local cursor = L.Cursor(page, { top = size.ITEM_GAP })
    local rows = {}

    local function Changed()
        addon.Refresh()
    end

    rows[#rows + 1] = cursor:Add(L.Toggle, {
        label = "Enabled",
        tooltip = "Draw this overlay on the cast bar.",
        stripe = 1,
        get = function() return CfgFor(key).enabled end,
        set = function(v)
            CfgFor(key).enabled = v
            page:Refresh()
            Changed()
        end,
    })

    rows[#rows + 1] = cursor:Add(ColorRow, key, Changed, 2)

    if key == "custom" then
        rows[#rows + 1] = cursor:Add(L.Input, {
            label = "Value",
            tooltip = "How far back from the end of the bar this overlay reaches.",
            suffix = "ms",
            width = 70,
            numeric = true,
            stripe = 3,
            get = function() return CfgFor(key).valueMS or 0 end,
            set = function(text)
                CfgFor(key).valueMS = math.max(0, tonumber(text) or 0)
                page:Refresh()
                Changed()
            end,
        })
    else
        -- Show what this overlay currently resolves to, so "Latency" is not an
        -- abstraction the player has to take on trust.
        rows[#rows + 1] = cursor:Add(L.Readout, {
            label = "Current value",
            value = "",
            stripe = 3,
        })
    end

    function page:Refresh()
        for _, row in ipairs(rows) do
            if row.Refresh then row:Refresh() end
            if row.Box and row.Get then row.Box:SetChecked(row.Get()) end
        end

        local last = rows[#rows]
        if key == "custom" then
            local edit = last.EditBox
            if edit and not edit:HasFocus() then
                edit:SetText(tostring(CfgFor(key).valueMS or 0))
            end
        elseif last.Value then
            local ms = addon.OverlayValueMS and addon.OverlayValueMS(key) or 0
            last.Value:SetText(("%d ms"):format(math.floor(ms + 0.5)))
        end
    end

    return page, cursor:Consumed()
end

-- ---------------------------------------------------------------------
-- Frame picker
-- ---------------------------------------------------------------------

-- Green outline drawn around whatever frame is currently under the cursor.
local highlight = CreateFrame("Frame", nil, UIParent)
highlight:SetFrameStrata("TOOLTIP")
highlight:EnableMouse(false)
highlight:Hide()
S.Border(highlight, S.color.accent, "OVERLAY")

-- We don't use a full-screen catcher frame (it blocks mouse events). Instead we
-- poll C_System.GetFrameStack() on an OnUpdate. For click detection, we
-- temporarily hook WorldFrame's OnMouseDown.
local currentTarget
local currentTargetName
local isSelecting = false
local originalWorldFrameOnMouseDown
local poller -- created below; forward-declared so StopSelecting can stop it

local function IsUselessPick(region)
    return region == nil
        or region == highlight
        or region == UIParent
        or region == WorldFrame
        or region == frame
end

local function RegionName(region)
    if not region or not region.GetName then return nil end
    local ok, name = pcall(region.GetName, region)
    if ok and name and name ~= "" then return name end
    return nil
end

-- A widget's size is SECRET when the addon that owns it derived that size from
-- secret data. Reading it back is fine; ORDERED COMPARISON on it throws:
--
--   attempt to compare local 'w' (a secret number value, while execution
--   tainted by 'CastQueueOverlay')
--
-- Truthiness is safe, and arithmetic is safe but PROPAGATES - so a secret width
-- silently poisons a computed area and explodes later inside table.sort instead,
-- far from the cause. Unknown is treated as secret on purpose: declining to rank
-- a region is always safe, comparing a secret never is.
local function IsSecret(value)
    if not issecretvalue then return false end
    local ok, secret = pcall(issecretvalue, value)
    if not ok then return true end
    return secret
end

local function NormalisedSize(region)
    local ok, w, h = pcall(function() return region:GetWidth(), region:GetHeight() end)
    if not ok or not w or not h then return nil end
    if IsSecret(w) or IsSecret(h) then return nil end
    if w <= 0 or h <= 0 then return nil end

    local scale = 1
    if region.GetEffectiveScale then
        local s = P.EffectiveScale(region)
        local parentScale = P.EffectiveScale(UIParent)
        if s and parentScale and parentScale > 0 then
            scale = s / parentScale
        end
    end
    return w * scale, h * scale
end

local SCREEN_COVER_RATIO = 0.95

local function CoversScreen(region)
    local w, h = NormalisedSize(region)
    if not w then return false end
    local pw, ph = UIParent:GetWidth(), UIParent:GetHeight()
    if not pw or not ph or pw <= 0 or ph <= 0 then return false end
    return w >= pw * SCREEN_COVER_RATIO and h >= ph * SCREEN_COVER_RATIO
end

-- Decorative overlays live at TOOLTIP strata. EllesmereUIQoL alone puts four
-- mouse-disabled decorations there, one of which FOLLOWS the cursor and so is
-- both tiny and always under it. Demoted rather than excluded: excluding by name
-- would start an arms race with every UI suite.
local function IsDecorative(region)
    if not region.GetFrameStrata then return false end
    local ok, strata = pcall(region.GetFrameStrata, region)
    return ok and strata == "TOOLTIP"
end

local candidates = {}
local candidateIndex = 1

local function CollectCandidates()
    -- GetMouseFoci() only reports regions with mouse input ENABLED; cast bars
    -- call EnableMouse(false), so they never appear in it. C_System
    -- .GetFrameStack() returns every region under the cursor regardless
    -- (SlashCommands.lua:1350).
    local stack = C_System and C_System.GetFrameStack and C_System.GetFrameStack() or {}

    candidates = {}
    for _, region in ipairs(stack) do
        -- Name first: cheap, cannot involve secrets, and discards the anonymous
        -- inner textures that are most of a stack and where secret sizes live.
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

    table.sort(candidates, function(a, b)
        if a.decorative ~= b.decorative then return b.decorative end
        if a.area ~= b.area then return a.area < b.area end
        return a.name < b.name -- total order, so the list cannot jitter
    end)
end

local function CurrentCandidate()
    if #candidates == 0 then return nil, nil end
    -- Clamp rather than reset: the set changes constantly under a moving cursor.
    if candidateIndex > #candidates then candidateIndex = #candidates end
    if candidateIndex < 1 then candidateIndex = 1 end
    local entry = candidates[candidateIndex]
    return entry.region, entry.name
end

local function PositionHighlight(target)
    highlight:ClearAllPoints()
    if not target then
        highlight:Hide()
        return
    end

    -- Anchor directly to the target rather than converting GetRect() into
    -- UIParent-space. GetRect returns values in the target's OWN coordinate
    -- system, so anything at a different effective scale was outlined in the
    -- wrong place. Anchoring lets the engine resolve scale.
    local ok = pcall(function()
        highlight:SetPoint("TOPLEFT", target, "TOPLEFT", 0, 0)
        highlight:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 0, 0)
    end)

    local w, h = NormalisedSize(target)
    if not ok or not w or not h or w <= 0 or h <= 0 then
        highlight:ClearAllPoints()
        highlight:Hide()
        return
    end
    highlight:Show()
end

-- `EnableKeyboard` and `SetPropagateKeyboardInput` are protected in combat EVEN
-- ON OUR OWN FRAME, because they alter global keyboard routing:
--
--   [ADDON_ACTION_BLOCKED] ... tried to call the protected function
--   'CastQueueOverlayOptionsFrame:SetPropagateKeyboardInput()'
--
-- Clearing the OnKeyDown script is NOT protected and is what actually stops us
-- consuming keys, so that happens unconditionally. Only the two protected calls
-- are deferred, and combat end drains them.
local deferredKeyboardRelease = false

local function ReleaseKeyboard()
    if not frame then return end
    frame:SetScript("OnKeyDown", nil)
    if InCombatLockdown() then
        deferredKeyboardRelease = true
        return
    end
    deferredKeyboardRelease = false
    frame:EnableKeyboard(false)
    frame:SetPropagateKeyboardInput(true)
end

-- Every exit path must go through here. Selecting installs a WorldFrame script,
-- an OnUpdate poller and a keyboard grab; leaking any one outlives the picker.
local function StopSelecting()
    isSelecting = false
    highlight:Hide()
    currentTarget = nil
    currentTargetName = nil
    if selectButton then selectButton:SetLabel("Select frame") end

    if poller then poller:Hide() end
    if pickerText then pickerText:SetText("") end
    candidates = {}
    candidateIndex = 1

    -- The original is usually nil, so this must be unconditional - keying it off
    -- a truthy check would leave our handler installed forever.
    WorldFrame:SetScript("OnMouseDown", originalWorldFrameOnMouseDown)
    originalWorldFrameOnMouseDown = nil

    ReleaseKeyboard()
end

local POLL_INTERVAL = 0.1
local sinceLastPoll = 0

local function RefreshPicker()
    CollectCandidates()
    local target, name = CurrentCandidate()

    currentTarget = target
    currentTargetName = name
    PositionHighlight(target)

    if not name then
        pickerText:SetText(S.Colorize(S.color.textFaint, "no named frame under cursor"))
        return
    end

    local suffix = ""
    if #candidates > 1 then
        suffix = S.Colorize(S.color.textFaint,
            ("   %d/%d  TAB to cycle"):format(candidateIndex, #candidates))
    end
    pickerText:SetText(S.Colorize(S.color.accent, name) .. suffix)
end

poller = CreateFrame("Frame")
poller:Hide()
poller:SetScript("OnUpdate", function(self, elapsed)
    if not isSelecting then return end
    sinceLastPoll = sinceLastPoll + elapsed
    if sinceLastPoll < POLL_INTERVAL then return end
    sinceLastPoll = 0
    RefreshPicker()
end)

local function TrySetFrameByName(name)
    name = name and strtrim(name)
    if not name or name == "" then
        statusText:SetText(S.Colorize(S.color.bad, "Enter a frame name."))
        return
    end
    if not _G[name] then
        statusText:SetText(S.Colorize(S.color.bad, "No frame named '" .. name .. "' exists."))
        return
    end
    if addon.SetCastBarByName(name) then
        statusText:SetText(S.Colorize(S.color.good, "Cast bar set to " .. name .. "."))
    else
        statusText:SetText(S.Colorize(S.color.bad, "'" .. name .. "' isn't a usable frame."))
    end
end

local function StartSelecting()
    isSelecting = true
    currentTarget = nil
    candidateIndex = 1
    statusText:SetText(S.Colorize(S.color.textMuted,
        "Click a frame to select it. TAB cycles, Esc cancels."))
    selectButton:SetLabel("Selecting...")
    poller:Show()

    originalWorldFrameOnMouseDown = WorldFrame:GetScript("OnMouseDown")
    WorldFrame:SetScript("OnMouseDown", function(self, button)
        if not isSelecting then return end
        if button ~= "LeftButton" then return end

        -- Use the name the readout was already showing, so the label, the
        -- outline and the result of a click can never disagree.
        local name = currentTargetName
        StopSelecting()

        if not name then
            statusText:SetText(S.Colorize(S.color.bad, "Nothing selectable there."))
            return
        end
        TrySetFrameByName(name)
    end)

    -- TAB rather than the mouse wheel: while picking, the cursor is over
    -- arbitrary frames, and catching the wheel globally would need the very
    -- full-screen mouse-enabled catcher this design avoids. Propagation is
    -- suppressed for exactly the two keys we consume.
    frame:EnableKeyboard(true)
    frame:SetPropagateKeyboardInput(true)
    frame:SetScript("OnKeyDown", function(self, key)
        if not isSelecting then
            self:SetPropagateKeyboardInput(true)
            return
        end
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            StopSelecting()
            statusText:SetText(S.Colorize(S.color.textMuted, "Selection cancelled."))
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
end

-- ---------------------------------------------------------------------
-- Refresh
-- ---------------------------------------------------------------------

local function SelectTab(key)
    activeTab = key
    for _, k in ipairs(TAB_KEYS) do
        tabs[k]:SetActive(k == key)
        if k == key then
            pages[k]:Refresh()
            pages[k]:Show()
        else
            pages[k]:Hide()
        end
    end
end

-- The channelling slider is meaningless while the toggle above it is off, so it
-- is DISABLED rather than merely ignored - and it names the setting that is
-- holding it down. A control that looks live and does nothing is the complaint
-- S.Requires exists to answer.
local function RefreshChannelControls()
    if not channelToggleRow then return end
    local ch = CastQueueOverlayDB.channelAlpha
    channelToggleRow.Box:SetChecked(ch.enabled)
    channelSliderRow:SetValue(ch.a or 0.7)
    channelSliderRow:SetEnabled(ch.enabled,
        S.Requires(CHANNEL_TOGGLE_LABEL, "enabled"))
end

-- The frame picker needs the keyboard for TAB and Escape, and both calls that
-- grab it are blocked in combat. The button says so rather than failing when
-- pressed.
local function RefreshPickerAvailability()
    if not selectButton then return end
    local combat = InCombatLockdown()
    selectButton:SetDisabledReason(combat and S.Requires("you to be out of combat") or nil)
    selectButton:SetEnabled(not combat)
end

local function RefreshAll()
    if not frame then return end
    for _, key in ipairs(TAB_KEYS) do
        pages[key]:Refresh()
    end
    RefreshChannelControls()
    RefreshPickerAvailability()
end

-- ---------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------

local function Build()
    -- The height is a starting value only; it is replaced from the cursor at the
    -- end of this function. It matters solely because the Content frame needs a
    -- width before the first builder can measure against it.
    frame = S.Window("CastQueueOverlayOptionsFrame", "options", WINDOW_W, 600,
        "Cast Queue Overlay")

    local content = frame.Content
    local cursor = L.Cursor(content)

    cursor:Add(L.Section, "Overlays")
    cursor:Gap(size.ITEM_GAP)

    -- `.Tabs` off the strip, not a third return value: Cursor:Add forwards only
    -- frame and height, so reading a third here would silently be nil and the
    -- first SelectTab would error on indexing it.
    local strip = cursor:Add(L.TabStrip, TAB_KEYS, TAB_TEXT,
        function(key) SelectTab(key) end)
    tabs = strip.Tabs

    cursor:Gap(size.ITEM_GAP)

    -- The body is a recessed panel holding one page per tab, all the same size.
    -- A body that resized per tab would make the whole window jump as you switch
    -- - so every page is built, the tallest wins, and the body is sized to it.
    pages = {}
    cursor:Add(function(parent, x, width, y)
        local body = S.Inset(parent)
        P.Point(body, "TOPLEFT", parent, "TOPLEFT", x, y)
        P.Size(body, width, size.ROW_H) -- replaced below, once the pages exist
        body.cqoWidth = width

        local tallest = 0
        for _, key in ipairs(TAB_KEYS) do
            local page, consumed = BuildPage(body, key)
            pages[key] = page
            if consumed > tallest then tallest = consumed end
        end

        -- Height IS the content. The page cursor already started one gap down,
        -- so this adds only the matching gap at the bottom.
        local h = tallest + size.ITEM_GAP
        P.Size(body, width, h)
        return body, h
    end)

    cursor:Gap(size.SECTION)

    cursor:Add(L.Section, "Channelling")
    cursor:Gap(size.ITEM_GAP)

    channelToggleRow = cursor:Add(L.Toggle, {
        label = CHANNEL_TOGGLE_LABEL,
        tooltip = "A channel starts with the bar full, so the overlay begins "
            .. "underneath the fill - which is exactly when it needs to be "
            .. "readable. This gives that case its own opacity.",
        stripe = 1,
        get = function() return CastQueueOverlayDB.channelAlpha.enabled end,
        set = function(v)
            CastQueueOverlayDB.channelAlpha.enabled = v
            RefreshChannelControls()
            addon.Refresh()
        end,
    })

    channelSliderRow = cursor:Add(L.SliderRow, {
        label = "Opacity while channelling",
        stripe = 2,
        min = 0, max = 1, step = 0.01,
        format = function(v) return Percent(v) end,
        get = function() return CastQueueOverlayDB.channelAlpha.a or 0.7 end,
        set = function(v)
            CastQueueOverlayDB.channelAlpha.a = v
            addon.Refresh()
        end,
    })

    cursor:Gap(size.SECTION)

    cursor:Add(L.Section, "Cast bar")
    cursor:Gap(size.ITEM_GAP)

    local frameRow = cursor:Add(L.Input, {
        label = "Frame name",
        tooltip = "The global name of the frame to draw on. Leave empty for "
            .. "Blizzard's own cast bar.",
        width = 220,
        stripe = 1,
        get = function() return addon.GetCastBarName() end,
        set = function(text) TrySetFrameByName(text) end,
    })
    frameNameEdit = frameRow.EditBox

    cursor:Gap(size.ITEM_GAP)

    local buttons = cursor:Add(L.ButtonRow, {
        { text = "Apply", key = "Apply", opts = { primary = true, width = 96 },
          onClick = function() TrySetFrameByName(frameNameEdit:GetText()) end },
        { text = "Select frame", key = "Select", opts = { width = 130 },
          onClick = function()
              if isSelecting then
                  StopSelecting()
                  return
              end
              -- Refuse up front rather than starting a picker whose cycling and
              -- cancel keys would silently not work.
              if InCombatLockdown() then
                  RefreshPickerAvailability()
                  return
              end
              StartSelecting()
          end },
    })
    selectButton = buttons.Select

    cursor:Gap(size.ITEM_GAP)

    -- The live readout for the picker: a recessed strip, because it reports
    -- rather than accepts.
    cursor:Add(function(parent, x, width, y)
        local holder = S.Inset(parent)
        P.Point(holder, "TOPLEFT", parent, "TOPLEFT", x, y)
        P.Size(holder, width, size.ROW_H_SM)

        pickerText = S.Label(holder, S.fontSmall, "LEFT")
        P.Point(pickerText, "LEFT", holder, "LEFT", size.ITEM_GAP, 0)
        P.Point(pickerText, "RIGHT", holder, "RIGHT", -size.ITEM_GAP, 0)
        pickerText:SetText("")

        return holder, size.ROW_H_SM
    end)

    cursor:Gap(size.ITEM_GAP)

    -- Two reserved lines. The status message changes long after the layout is
    -- fixed, so measuring whichever string happened to be set at build time
    -- would size the window to it and force a resize on every message.
    statusText = cursor:Add(L.MessageLine, 2)

    cursor:Gap(size.SECTION)

    cursor:Add(L.Paragraph,
        "Shades the trailing end of your cast bar to show the time values you "
        .. "would otherwise have to guess at.", S.fontHint)

    -- The height IS the cursor. Header band, the top inset, everything built,
    -- and a bottom inset matching the top.
    frame:SetHeight(P.Snap(size.HEADER_H + size.PAD + cursor:Consumed() + size.PAD))

    frame.Badge:SetText(S.Colorize(S.color.textMuted,
        "v" .. (C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "")))

    frame:SetScript("OnShow", function()
        SelectTab(activeTab or "queue")
        RefreshAll()
        frameNameEdit:SetText(addon.GetCastBarName())
        statusText:SetText("")
    end)

    -- Closing the window by any route must tear the picker down. Previously only
    -- Escape did: closing via the button left isSelecting true, so the outline
    -- kept tracking the cursor over a closed window, Escape did nothing because
    -- the keyboard grab had gone with the frame, and clicks did nothing because
    -- the WorldFrame hook was still installed but the panel could not respond.
    frame:SetScript("OnHide", function()
        if isSelecting then StopSelecting() end
        -- The colour picker is parented to UIParent so it can float outside this
        -- window, so it does not inherit the hide. Leaving it behind would strand
        -- a picker with no visible owner and a Cancel that writes to a panel you
        -- can no longer see.
        if picker and picker:IsShown() then picker:Hide() end
    end)

    frame:RestorePosition()
end

-- ---------------------------------------------------------------------
-- Public entry points
-- ---------------------------------------------------------------------
--
-- These are called from the core file, which loads LAST, so they must exist at
-- this file's scope even though the window itself is built lazily.

function addon.ShowOptions()
    if not frame then Build() end
    frame:Show()
end

function addon.ToggleOptions()
    if not frame then Build() end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

-- Kept as a documented extension point rather than pruned as dead code: nothing
-- currently changes an overlay colour from outside this window, because `/cqo`
-- takes no arguments. See decision #4.
function addon.OnColorChangedExternally()
    RefreshAll()
end

function addon.OnCastBarChanged(name)
    if frameNameEdit then frameNameEdit:SetText(name or "") end
end

-- Combat can start while the window is open and the picker is armed. Shut the
-- picker down rather than let it run with keys it can no longer grab or release,
-- and drain any cleanup that combat forced us to postpone.
local combatWatcher = CreateFrame("Frame")
combatWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
combatWatcher:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        if isSelecting then
            StopSelecting()
            statusText:SetText(S.Colorize(S.color.textMuted,
                "Frame picker stopped - combat started."))
        end
    elseif deferredKeyboardRelease then
        ReleaseKeyboard()
    end
    RefreshPickerAvailability()
end)

-- ---------------------------------------------------------------------
-- Settings entry: a handoff button, nothing more
-- ---------------------------------------------------------------------
--
-- Left in Blizzard's chrome deliberately. This is one paragraph and one button
-- inside a panel we do not own and cannot style; dressing it in the addon's
-- palette would make a Blizzard-framed page look half-reskinned, which reads
-- worse than a plain one.
local stub = CreateFrame("Frame")
stub.name = "Cast Queue Overlay"

local stubText = stub:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
stubText:SetPoint("TOPLEFT", 16, -16)
stubText:SetWidth(500)
stubText:SetJustifyH("LEFT")
stubText:SetText("Cast Queue Overlay uses its own options window, which also works during combat.")

local stubButton = CreateFrame("Button", nil, stub, "UIPanelButtonTemplate")
stubButton:SetSize(220, 24)
stubButton:SetPoint("TOPLEFT", stubText, "BOTTOMLEFT", 0, -14)
stubButton:SetText("Open Cast Queue Overlay options")
stubButton:SetScript("OnClick", function()
    -- Close Settings first so the two windows are never stacked.
    if SettingsPanel and SettingsPanel:IsShown() then
        HideUIPanel(SettingsPanel)
    end
    addon.ShowOptions()
end)

-- DO NOT set `category.ID`. SettingsCategoryMixin:Init assigns self.ID =
-- idCounter(), a NUMBER the registry uses to find the category
-- (Blizzard_Category.lua:8-14). Overwriting it orphans the category.
local category = Settings.RegisterCanvasLayoutCategory(stub, stub.name)
Settings.RegisterAddOnCategory(category)
CastQueueOverlayOptionsCategory = category
