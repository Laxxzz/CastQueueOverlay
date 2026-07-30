-- CastQueueOverlay: shared visual language for the standalone options window.
--
-- Palette and shapes approximate the Claude Code editor: a warm near-black
-- canvas, a slightly darker inset for anything you can type into or click, hairline
-- borders rather than bevels, and a single coral accent used sparingly.
--
-- Everything is drawn with flat SetColorTexture rectangles instead of Blizzard's
-- BackdropTemplate. Backdrops bring gold beveled edges and tiled parchment that
-- would fight this look, and flat rectangles with 1px borders are what makes an
-- editor read as an editor.

CastQueueOverlay = CastQueueOverlay or {}
local addon = CastQueueOverlay

local S = {}
addon.Style = S

-- ---------------------------------------------------------------------
-- Palette
-- ---------------------------------------------------------------------
-- Hex kept in the comments because that is how these were picked, and it is the
-- only way anyone will be able to check them against the editor later.
S.color = {
    canvas      = { 0.149, 0.149, 0.141 }, -- #262624  window body
    surface     = { 0.122, 0.118, 0.114 }, -- #1F1E1D  inputs, insets
    surfaceHover= { 0.180, 0.176, 0.169 }, -- #2E2D2B  hover state
    border      = { 0.239, 0.239, 0.227 }, -- #3D3D3A  hairline
    borderBright= { 0.333, 0.329, 0.310 }, -- #55544F  focused / hovered edge
    text        = { 0.980, 0.976, 0.961 }, -- #FAF9F5  primary
    textMuted   = { 0.639, 0.627, 0.600 }, -- #A3A099  secondary
    textFaint   = { 0.451, 0.443, 0.424 }, -- #73716C  hints
    accent      = { 0.851, 0.467, 0.341 }, -- #D97757  Claude coral
    accentDim   = { 0.612, 0.325, 0.231 }, -- #9C533B  pressed accent
    good        = { 0.400, 0.733, 0.416 }, -- #66BB6A  success text
    bad         = { 0.898, 0.451, 0.451 }, -- #E57373  error text
}

local function Unpack(c, alpha)
    return c[1], c[2], c[3], alpha or 1
end
S.Unpack = Unpack

-- Colour a string for use in FontStrings, from the same palette, so message text
-- cannot drift away from the rest of the window.
function S.Colorize(color, text)
    return ("|cff%02x%02x%02x%s|r"):format(
        math.floor(color[1] * 255 + 0.5),
        math.floor(color[2] * 255 + 0.5),
        math.floor(color[3] * 255 + 0.5),
        text)
end

-- ---------------------------------------------------------------------
-- Fonts
-- ---------------------------------------------------------------------
-- Custom font objects rather than the Game* globals: those carry Blizzard's
-- yellow/gold and their own shadows, which is most of what makes an addon panel
-- look like an addon panel.
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

local function MakeFont(name, size, color, flags)
    local f = CreateFont(name)
    f:SetFont(FONT, size, flags or "")
    f:SetTextColor(Unpack(color))
    f:SetShadowOffset(0, 0) -- shadows read as "game UI"; the editor look is flat
    return f
end

S.fontTitle   = MakeFont("CastQueueOverlayFontTitle",   15, S.color.text)
S.fontHeading = MakeFont("CastQueueOverlayFontHeading", 12, S.color.textMuted)
S.fontBody    = MakeFont("CastQueueOverlayFontBody",    12, S.color.text)
S.fontSmall   = MakeFont("CastQueueOverlayFontSmall",   11, S.color.textMuted)
S.fontHint    = MakeFont("CastQueueOverlayFontHint",    11, S.color.textFaint)

-- ---------------------------------------------------------------------
-- Primitives
-- ---------------------------------------------------------------------

-- Flat fill covering the whole region.
function S.Fill(frame, color, alpha)
    local t = frame:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints(frame)
    t:SetColorTexture(Unpack(color, alpha))
    return t
end

-- Hairline border as four 1px edges. Drawn as separate textures rather than a
-- backdrop edgeFile so it stays exactly one pixel at any frame size.
function S.Border(frame, color, layer)
    local edges = {}
    local function edge(p1, p2, w, h)
        local t = frame:CreateTexture(nil, layer or "BORDER")
        t:SetColorTexture(Unpack(color))
        t:SetPoint(p1)
        t:SetPoint(p2)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
        edges[#edges + 1] = t
        return t
    end
    edge("TOPLEFT", "TOPRIGHT", nil, 1)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
    edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)

    return {
        SetColor = function(_, c)
            for _, t in ipairs(edges) do t:SetColorTexture(Unpack(c)) end
        end,
    }
end

-- A recessed surface: darker fill plus hairline. Used for inputs and readouts.
function S.Inset(parent)
    local f = CreateFrame("Frame", nil, parent)
    S.Fill(f, S.color.surface)
    f.border = S.Border(f, S.color.border)
    return f
end

-- ---------------------------------------------------------------------
-- Controls
-- ---------------------------------------------------------------------

-- Flat button. `primary` gives it the coral accent; everything else is a quiet
-- surface button, because a panel where everything is accented has no accent.
function S.Button(parent, text, width, height, primary)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, height)

    local base   = primary and S.color.accent or S.color.surface
    local hover  = primary and S.color.accentDim or S.color.surfaceHover
    local edge   = primary and S.color.accent or S.color.border

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(b)
    bg:SetColorTexture(Unpack(base))

    local border = S.Border(b, edge)

    local label = b:CreateFontString(nil, "OVERLAY")
    label:SetFontObject(S.fontBody)
    label:SetPoint("CENTER")
    label:SetText(text)
    if primary then
        -- Coral is light enough that white-on-coral is the readable pairing.
        label:SetTextColor(Unpack(S.color.canvas))
    end
    b.Label = label

    b:SetScript("OnEnter", function()
        bg:SetColorTexture(Unpack(hover))
        if not primary then border:SetColor(S.color.borderBright) end
    end)
    b:SetScript("OnLeave", function()
        bg:SetColorTexture(Unpack(base))
        if not primary then border:SetColor(S.color.border) end
    end)
    b:SetScript("OnMouseDown", function() label:SetPoint("CENTER", 0, -1) end)
    b:SetScript("OnMouseUp", function() label:SetPoint("CENTER", 0, 0) end)

    function b:SetLabel(t) label:SetText(t) end

    return b
end

-- Single-line text input on an inset surface.
function S.EditBox(parent, width, height)
    local holder = S.Inset(parent)
    holder:SetSize(width, height)

    local e = CreateFrame("EditBox", nil, holder)
    e:SetPoint("TOPLEFT", 8, 0)
    e:SetPoint("BOTTOMRIGHT", -8, 0)
    e:SetFontObject(S.fontBody)
    e:SetAutoFocus(false)
    e:SetTextInsets(0, 0, 0, 0)

    e:HookScript("OnEditFocusGained", function() holder.border:SetColor(S.color.accent) end)
    e:HookScript("OnEditFocusLost", function() holder.border:SetColor(S.color.border) end)

    holder.EditBox = e
    return holder, e
end

-- Tab button. Deliberately styled to match a section heading rather than a
-- button: same font object and same muted colour as S.Heading, with a border in
-- that same colour. The active tab is shown by a filled background only, so the
-- text and outline colours stay identical across all three.
function S.Tab(parent, text)
    local b = CreateFrame("Button", nil, parent)

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(b)
    bg:SetColorTexture(Unpack(S.color.canvas))

    S.Border(b, S.color.textMuted)

    local label = b:CreateFontString(nil, "OVERLAY")
    label:SetFontObject(S.fontHeading)
    label:SetPoint("CENTER")
    label:SetText(text)

    b:SetSize(label:GetStringWidth() + 24, 22)

    local active = false
    function b:SetActive(on)
        active = on
        bg:SetColorTexture(Unpack(on and S.color.surfaceHover or S.color.canvas))
    end
    function b:IsActive() return active end

    b:SetScript("OnEnter", function()
        if not active then bg:SetColorTexture(Unpack(S.color.surface)) end
    end)
    b:SetScript("OnLeave", function()
        bg:SetColorTexture(Unpack(active and S.color.surfaceHover or S.color.canvas))
    end)

    return b
end

-- Flat checkbox: hairline square, accent fill when checked. No tick glyph - at
-- this size a filled square reads faster and needs no art.
function S.Checkbox(parent, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)

    S.Fill(b, S.color.surface)
    local border = S.Border(b, S.color.border)

    local fill = b:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 3, -3)
    fill:SetPoint("BOTTOMRIGHT", -3, 3)
    fill:SetColorTexture(Unpack(S.color.accent))
    fill:Hide()

    local checked = false
    function b:SetChecked(on)
        checked = on and true or false
        if checked then fill:Show() else fill:Hide() end
    end
    function b:GetChecked() return checked end

    b:SetScript("OnEnter", function() border:SetColor(S.color.borderBright) end)
    b:SetScript("OnLeave", function() border:SetColor(S.color.border) end)

    return b
end

-- Horizontal slider: hairline groove with a coral thumb. Built from our own
-- textures rather than OptionsSliderTemplate, which brings Blizzard's metal
-- trough and gold-bordered thumb.
--
-- The groove is a separate frame behind the slider rather than a texture on it:
-- the slider itself has to be tall enough to be comfortable to grab, while the
-- groove should stay thin.
function S.Slider(parent, width)
    local groove = CreateFrame("Frame", nil, parent)
    groove:SetSize(width, 4)
    S.Fill(groove, S.color.surface)
    S.Border(groove, S.color.border)

    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(width, 18)
    s:SetPoint("CENTER", groove, "CENTER", 0, 0)
    s:SetHitRectInsets(0, 0, 0, 0)

    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(Unpack(S.color.accent))
    thumb:SetSize(8, 16)
    s:SetThumbTexture(thumb)

    s:SetScript("OnEnter", function() thumb:SetColorTexture(Unpack(S.color.text)) end)
    s:SetScript("OnLeave", function() thumb:SetColorTexture(Unpack(S.color.accent)) end)

    s.Groove = groove
    return s
end

-- Section heading: small muted label with a hairline rule running to the right,
-- which is what gives the window its structure without boxing everything in.
function S.Heading(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(S.fontHeading)
    fs:SetText(text)

    local rule = parent:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(Unpack(S.color.border))
    rule:SetHeight(1)
    rule:SetPoint("LEFT", fs, "RIGHT", 8, 0)

    fs.Rule = rule
    return fs
end
