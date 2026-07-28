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

local ADDON_NAME = ...

-- The namespace guard MUST be repeated in every file that touches it. A `local`
-- captures the value at this instant, so if this file loads first and the table
-- does not exist yet, `addon` would capture nil forever.
CastQueueOverlay = CastQueueOverlay or {}
local addon = CastQueueOverlay
local S = addon.Style

-- ---------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------
-- Height leaves room for statusText to wrap to two lines without colliding with
-- the hint pinned to the bottom edge.
local WINDOW_W, WINDOW_H = 460, 404
local PAD = 20

local win = CreateFrame("Frame", "CastQueueOverlayOptionsFrame", UIParent)
win:SetSize(WINDOW_W, WINDOW_H)
win:SetPoint("CENTER")
win:SetFrameStrata("DIALOG")
win:SetToplevel(true)
win:EnableMouse(true)   -- also stops clicks falling through to the world
win:SetMovable(true)
win:SetClampedToScreen(true)
win:RegisterForDrag("LeftButton")
win:SetScript("OnDragStart", win.StartMoving)
win:SetScript("OnDragStop", win.StopMovingOrSizing)
win:Hide()

S.Fill(win, S.color.canvas)
S.Border(win, S.color.border)

-- Title bar: a coral hairline under the title is the whole accent budget for the
-- window chrome. Anything more and it stops reading as an editor.
local titleBar = CreateFrame("Frame", nil, win)
titleBar:SetPoint("TOPLEFT")
titleBar:SetPoint("TOPRIGHT")
titleBar:SetHeight(44)

local title = titleBar:CreateFontString(nil, "OVERLAY")
title:SetFontObject(S.fontTitle)
title:SetPoint("LEFT", PAD, 0)
title:SetText("Cast Queue Overlay")

local titleRule = win:CreateTexture(nil, "ARTWORK")
titleRule:SetColorTexture(S.Unpack(S.color.accent))
titleRule:SetHeight(1)
titleRule:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", PAD, 0)
titleRule:SetWidth(28)

local titleRuleRest = win:CreateTexture(nil, "ARTWORK")
titleRuleRest:SetColorTexture(S.Unpack(S.color.border))
titleRuleRest:SetHeight(1)
titleRuleRest:SetPoint("TOPLEFT", titleRule, "TOPRIGHT", 0, 0)
titleRuleRest:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", -PAD, 0)

local closeBtn = S.Button(win, "X", 24, 24)
closeBtn:SetPoint("TOPRIGHT", -PAD + 4, -10)
closeBtn:SetScript("OnClick", function() win:Hide() end)

-- ESC closes the window. While the frame picker is armed our OnKeyDown consumes
-- ESCAPE first, so it cancels picking instead - which is the behaviour you want.
tinsert(UISpecialFrames, "CastQueueOverlayOptionsFrame")

-- ---------------------------------------------------------------------
-- Overlay colour
-- ---------------------------------------------------------------------
-- One tab per overlay, each with its own colour, opacity and on/off. The tabs
-- sit where the OVERLAY COLOUR heading used to, and deliberately carry the
-- heading's font and colour so the row still reads as a section label.
local TAB_KEYS = { "queue", "latency", "custom" }
local TAB_TEXT = {
    queue   = "SpellQueueWindow",
    latency = "Latency",
    custom  = "Custom",
}

local tabs = {}
local pages = {}
local activeTab

local body = S.Inset(win)
-- Sized for the tallest page. Only `custom` has a second row, and a body that
-- resized per tab would make the whole window jump as you switch.
body:SetSize(WINDOW_W - PAD * 2, 82)

local function CfgFor(key)
    return CastQueueOverlayDB.overlays[key]
end

-- Builds the body content for one overlay. Every page is identical except that
-- `custom` gains a value field, since its milliseconds are not read from the game.
local function BuildPage(key)
    local page = CreateFrame("Frame", nil, body)
    page:SetAllPoints(body)
    page:Hide()

    local swatchHolder = S.Inset(page)
    swatchHolder:SetSize(52, 26)
    swatchHolder:SetPoint("TOPLEFT", 10, -10)

    local swatchTex = swatchHolder:CreateTexture(nil, "ARTWORK")
    swatchTex:SetPoint("TOPLEFT", 3, -3)
    swatchTex:SetPoint("BOTTOMRIGHT", -3, 3)
    swatchTex:SetColorTexture(1, 1, 1, 1)

    local swatchBtn = CreateFrame("Button", nil, swatchHolder)
    swatchBtn:SetAllPoints(swatchHolder)

    local colorValue = page:CreateFontString(nil, "OVERLAY")
    colorValue:SetFontObject(S.fontSmall)
    colorValue:SetPoint("LEFT", swatchHolder, "RIGHT", 12, 0)

    -- One anchor only. RIGHT plus TOP would over-constrain a FontString - each
    -- supplies both an x and a y - and stretch it. -23 is the vertical centre of
    -- the swatch row (10 inset + half of 26).
    local enableLabel = page:CreateFontString(nil, "OVERLAY")
    enableLabel:SetFontObject(S.fontSmall)
    enableLabel:SetText("Enabled")
    enableLabel:SetPoint("RIGHT", page, "TOPRIGHT", -12, -23)

    local check = S.Checkbox(page, 18)
    check:SetPoint("RIGHT", enableLabel, "LEFT", -8, 0)

    -- Custom is the only overlay whose value the player supplies.
    local msHolder, msEdit
    if key == "custom" then
        local msLabel = page:CreateFontString(nil, "OVERLAY")
        msLabel:SetFontObject(S.fontSmall)
        msLabel:SetText("Value")
        msLabel:SetPoint("TOPLEFT", swatchHolder, "BOTTOMLEFT", 0, -12)

        msHolder, msEdit = S.EditBox(page, 80, 24)
        msHolder:SetPoint("LEFT", msLabel, "RIGHT", 10, 0)
        msEdit:SetNumeric(true)

        local msUnit = page:CreateFontString(nil, "OVERLAY")
        msUnit:SetFontObject(S.fontHint)
        msUnit:SetText("ms")
        msUnit:SetPoint("LEFT", msHolder, "RIGHT", 8, 0)
    end

    function page:Refresh()
        local c = CfgFor(key)
        swatchTex:SetColorTexture(c.r, c.g, c.b, 1)

        local valueText = ""
        if key ~= "custom" then
            -- Show what this overlay currently resolves to, so "Latency" is not
            -- an abstraction the player has to take on trust.
            local ms = addon.OverlayValueMS and addon.OverlayValueMS(key) or 0
            valueText = ("   %dms"):format(math.floor(ms + 0.5))
        end

        colorValue:SetText(("#%02X%02X%02X   %d%% opacity%s"):format(
            math.floor(c.r * 255 + 0.5),
            math.floor(c.g * 255 + 0.5),
            math.floor(c.b * 255 + 0.5),
            math.floor((c.a or 0) * 100 + 0.5),
            valueText))

        check:SetChecked(c.enabled)
        if msEdit and not msEdit:HasFocus() then
            msEdit:SetText(tostring(c.valueMS or 0))
        end
    end

    check:SetScript("OnClick", function()
        local c = CfgFor(key)
        c.enabled = not c.enabled
        page:Refresh()
        addon.Refresh()
    end)

    if msEdit then
        local function CommitMS(self)
            local c = CfgFor(key)
            c.valueMS = math.max(0, tonumber(self:GetText()) or 0)
            self:ClearFocus()
            page:Refresh()
            addon.Refresh()
        end
        msEdit:SetScript("OnEnterPressed", CommitMS)
        msEdit:SetScript("OnEditFocusLost", CommitMS)
        msEdit:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            page:Refresh()
        end)
    end

    local function OnColorChanged()
        local c = CfgFor(key)
        c.r, c.g, c.b = ColorPickerFrame:GetColorRGB()
        c.a = ColorPickerFrame:GetColorAlpha()
        page:Refresh()
        addon.Refresh()
    end

    swatchBtn:SetScript("OnClick", function()
        local c = CfgFor(key)
        -- Snapshot by value. `c` is a live reference into the saved variables and
        -- is mutated by swatchFunc while the picker is open, so it cannot serve
        -- as its own restore point.
        local prevR, prevG, prevB, prevA = c.r, c.g, c.b, c.a

        ColorPickerFrame:SetupColorPickerAndShow({
            swatchFunc = OnColorChanged,
            opacityFunc = OnColorChanged,
            cancelFunc = function(prev)
                -- ColorPickerFrame builds this as {r=, g=, b=, a=} - alpha goes
                -- IN as `opacity` and comes BACK as `a`.
                local cfg = CfgFor(key)
                cfg.r = (prev and prev.r) or prevR
                cfg.g = (prev and prev.g) or prevG
                cfg.b = (prev and prev.b) or prevB
                cfg.a = (prev and prev.a) or prevA
                page:Refresh()
                addon.Refresh()
            end,
            hasOpacity = 1,
            opacity = c.a,
            r = c.r, g = c.g, b = c.b,
        })
    end)

    return page
end

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

local prevTab
for _, key in ipairs(TAB_KEYS) do
    local tab = S.Tab(win, TAB_TEXT[key])
    if prevTab then
        tab:SetPoint("LEFT", prevTab, "RIGHT", 6, 0)
    else
        tab:SetPoint("TOPLEFT", PAD, -58)
    end
    tab:SetScript("OnClick", function() SelectTab(key) end)
    tabs[key] = tab
    prevTab = tab
end

body:SetPoint("TOPLEFT", tabs.queue, "BOTTOMLEFT", 0, -8)

for _, key in ipairs(TAB_KEYS) do
    pages[key] = BuildPage(key)
end

local function RefreshAllPages()
    for _, key in ipairs(TAB_KEYS) do
        pages[key]:Refresh()
    end
end

function addon.OnColorChangedExternally()
    RefreshAllPages()
end

-- ---------------------------------------------------------------------
-- Cast bar frame
-- ---------------------------------------------------------------------
local frameHeading = S.Heading(win, "CAST BAR FRAME")
frameHeading:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 0, -24)
frameHeading.Rule:SetPoint("RIGHT", win, "RIGHT", -PAD, 0)

local editHolder, editBox = S.EditBox(win, 268, 26)
editHolder:SetPoint("TOPLEFT", frameHeading, "BOTTOMLEFT", 0, -12)

local applyBtn = S.Button(win, "Apply", 76, 26, true)
applyBtn:SetPoint("LEFT", editHolder, "RIGHT", 10, 0)

local statusText = win:CreateFontString(nil, "OVERLAY")
statusText:SetFontObject(S.fontSmall)
statusText:SetWidth(WINDOW_W - PAD * 2)
statusText:SetJustifyH("LEFT")

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

applyBtn:SetScript("OnClick", function() TrySetFrameByName(editBox:GetText()) end)
editBox:SetScript("OnEnterPressed", function(self)
    TrySetFrameByName(self:GetText())
    self:ClearFocus()
end)
editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

function addon.OnCastBarChanged(name)
    editBox:SetText(name or "")
end

-- ---------------------------------------------------------------------
-- Click-to-select frame picker
-- ---------------------------------------------------------------------
local selectButton = S.Button(win, "Select Frame", 140, 26)
selectButton:SetPoint("TOPLEFT", editHolder, "BOTTOMLEFT", 0, -16)

local readoutHolder = S.Inset(win)
readoutHolder:SetSize(WINDOW_W - PAD * 2, 26)
readoutHolder:SetPoint("TOPLEFT", selectButton, "BOTTOMLEFT", 0, -12)

local pickerText = readoutHolder:CreateFontString(nil, "OVERLAY")
pickerText:SetFontObject(S.fontSmall)
pickerText:SetPoint("LEFT", 8, 0)
pickerText:SetPoint("RIGHT", -8, 0)
pickerText:SetJustifyH("LEFT")
pickerText:SetText("")

statusText:SetPoint("TOPLEFT", readoutHolder, "BOTTOMLEFT", 0, -12)

-- Green outline drawn around whatever frame is currently under the cursor.
local highlight = CreateFrame("Frame", nil, UIParent)
highlight:SetFrameStrata("TOOLTIP")
highlight:EnableMouse(false)
highlight:Hide()
local highlightBorder = S.Border(highlight, S.color.accent, "OVERLAY")
highlightBorder:SetColor(S.color.accent)

-- We don't use a full-screen catcher frame (it blocks mouse events).
-- Instead we poll C_System.GetFrameStack() on an OnUpdate. For click detection,
-- we temporarily hook WorldFrame's OnMouseDown.
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
        or region == win
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
        local ok2, s = pcall(region.GetEffectiveScale, region)
        local parentScale = UIParent:GetEffectiveScale()
        if ok2 and s and not IsSecret(s) and parentScale and parentScale > 0 then
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
    -- call EnableMouse(false), so they never appear in it.
    -- C_System.GetFrameStack() returns every region under the cursor regardless
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

-- Every exit path must go through here. Selecting installs a WorldFrame script,
-- an OnUpdate poller and a keyboard grab; leaking any one outlives the picker.
local function StopSelecting()
    isSelecting = false
    highlight:Hide()
    currentTarget = nil
    currentTargetName = nil
    selectButton:SetLabel("Select Frame")

    if poller then poller:Hide() end
    pickerText:SetText("")
    candidates = {}
    candidateIndex = 1

    -- The original is usually nil, so this must be unconditional - keying it off
    -- a truthy check would leave our handler installed forever.
    WorldFrame:SetScript("OnMouseDown", originalWorldFrameOnMouseDown)
    originalWorldFrameOnMouseDown = nil

    win:SetScript("OnKeyDown", nil)
    win:EnableKeyboard(false)
    win:SetPropagateKeyboardInput(true)
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
        suffix = S.Colorize(S.color.textFaint, ("   %d/%d  TAB to cycle"):format(candidateIndex, #candidates))
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

selectButton:SetScript("OnClick", function()
    if isSelecting then
        StopSelecting()
        return
    end
    isSelecting = true
    currentTarget = nil
    candidateIndex = 1
    statusText:SetText(S.Colorize(S.color.textMuted, "Click a frame to select it. TAB cycles, Esc cancels."))
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

    -- TAB rather than the mouse wheel: while picking the cursor is over
    -- arbitrary frames, and catching the wheel globally would need the very
    -- full-screen mouse-enabled catcher this design avoids. Propagation is
    -- suppressed for exactly the two keys we consume.
    win:EnableKeyboard(true)
    win:SetPropagateKeyboardInput(true)
    win:SetScript("OnKeyDown", function(self, key)
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
end)

local hint = win:CreateFontString(nil, "OVERLAY")
hint:SetFontObject(S.fontHint)
hint:SetPoint("BOTTOMLEFT", PAD, PAD - 6)
hint:SetPoint("BOTTOMRIGHT", -PAD, PAD - 6)
hint:SetJustifyH("LEFT")
hint:SetText("Add a colored overlay to the end of your CastBar indicating various time values")

-- ---------------------------------------------------------------------
-- Show / hide
-- ---------------------------------------------------------------------
win:SetScript("OnShow", function()
    SelectTab(activeTab or "queue")
    editBox:SetText(addon.GetCastBarName())
    statusText:SetText("")
end)

-- Closing the window by any route must tear the picker down. Previously only
-- Escape did: closing via the button left isSelecting true, so the outline kept
-- tracking the cursor over a closed window, Escape did nothing because the
-- keyboard grab had gone with the frame, and clicks did nothing because the
-- WorldFrame hook was still installed but the panel could not respond.
win:SetScript("OnHide", function()
    if isSelecting then StopSelecting() end
end)

function addon.ToggleOptions()
    if win:IsShown() then
        win:Hide()
    else
        win:Show()
    end
end

function addon.ShowOptions()
    win:Show()
end

-- ---------------------------------------------------------------------
-- Settings entry: a handoff button, nothing more
-- ---------------------------------------------------------------------
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
