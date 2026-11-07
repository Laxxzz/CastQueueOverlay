-- CastQueueOverlay: shared visual language for the standalone options window.
--
-- A flat, near-black canvas with a slight orange hue cast, lifted controls on
-- top of it, recessed black insets for anything typeable, hairline borders
-- rather than bevels, and ONE accent (#E0873A orange) used for state.
--
-- This palette and these widget contracts are SimpleLootCouncil's current
-- design language, hue-rotated from its blue to this addon's orange so the two
-- read as one suite. The neutrals carry 0.75x SLC's saturation; the accent ramp
-- (accent / accentDim / accentPale / knob) keeps SLC's relationships.
--
-- Everything is drawn with flat SetColorTexture rectangles instead of Blizzard's
-- BackdropTemplate. Backdrops bring gold beveled edges and tiled parchment that
-- would fight this look, their edgeFile scales with the frame so a "1px" edge is
-- not 1px at any other size, and flat rectangles with snapped hairline borders
-- are what makes a panel read as a tool rather than as game UI.
--
-- Two rules from reference/ui-design.md are load-bearing here and must not be
-- relaxed:
--
--   * A widget owns its own geometry. Callers pass CONTENT and BEHAVIOUR, and an
--     override only where the size genuinely varies. The test for whether a
--     widget is finished is whether a call site can render it wrong by omission.
--   * Everything that is not the canvas, a control surface or the accent is
--     white or black at an alpha, never a colour.

-- The namespace guard MUST be repeated in every file that touches it. See
-- decision #1 - this addon has been broken by its absence, in both directions.
CastQueueOverlay = CastQueueOverlay or {}
local addon = CastQueueOverlay

local S = {}
addon.Style = S

local P = addon.Pixel
local Snap = P.Snap

-- ---------------------------------------------------------------------
-- Palette
-- ---------------------------------------------------------------------
--
-- Hex is kept in the comments because that is how these were picked, and it is
-- the only way anyone can check them later.
--
-- Note how few of these are actually a colour. Borders, text, row stripes and
-- overlays are all { 1, 1, 1 } or { 0, 0, 0 } at a chosen alpha, which is why
-- they stay correctly contrasted across the whole ground - a hardcoded border
-- hex is correct against exactly one background.
S.color = {
    -- The panel. Near-black with a faint warm cast; the window's ground below
    -- falls from canvasTop to canvasBottom, so this is the midpoint stand-in
    -- for the few places that need one colour (small solid chips).
    canvas       = { 0.085, 0.070, 0.056 }, -- #16120E  panel

    -- Controls are RAISED, with hover and pressed steps either side.
    control      = { 0.111, 0.089, 0.070 }, -- #1C1712  button rest
    controlHover = { 0.174, 0.139, 0.109 }, -- #2C231C  button hover
    controlDown  = { 0.066, 0.052, 0.040 }, -- #110D0A  button pressed

    -- White, a step above the panel hairline.
    controlBorder      = { 1, 1, 1, 0.22 },
    controlBorderHover = { 1, 1, 1, 0.55 },

    -- Inputs are RECESSED: black at an alpha.
    inset        = { 0, 0, 0, 0.25 },
    insetDeep    = { 0, 0, 0, 0.35 },

    border       = { 1, 1, 1, 0.05 },       -- hairline
    borderBright = { 1, 1, 1, 0.20 },       -- focused / hovered edge

    text         = { 1, 1, 1, 1.00 },       -- primary
    textMuted    = { 0.845, 0.786, 0.736 }, -- #D7C8BC  secondary
    textFaint    = { 0.671, 0.608, 0.553 }, -- #AB9B8D  hints, disabled

    rowOdd       = { 0, 0, 0, 0.10 },       -- alternating list stripe
    rowEven      = { 0, 0, 0, 0.20 },
    rowHover     = { 1, 1, 1, 0.07 },

    -- The "not currently a control" fill: a disabled button, an inactive tab.
    controlOff   = { 0, 0, 0, 0.22 },

    -- The one hue. State, focus and the primary action are all this.
    accent       = { 0.878, 0.529, 0.227 }, -- #E0873A  orange
    accentDim    = { 0.583, 0.376, 0.197 }, -- #956032  pressed accent
    accentPale   = { 0.951, 0.706, 0.495 }, -- #F3B47E

    good         = { 0.400, 0.780, 0.541 }, -- #66C78A  success
    bad          = { 0.898, 0.451, 0.451 }, -- #E57373  error
}

-- A ticked checkbox is the accent.
S.color.check = S.color.accent

-- Two tiers of state used to exist (blue `on`, coral `accent`). There is one
-- hue now; the old names stay so call sites keep working.
S.color.on    = S.color.accent
S.color.onDim = S.color.accentDim

-- Kept as aliases so the palette swap did not have to be a call-site migration.
S.color.surface      = S.color.control
S.color.surfaceHover = S.color.controlHover

-- The window's three-stop ground (the fall is not linear). S.Window draws the
-- gradient between canvasTop and canvasBottom; canvasMid is the palette's
-- middle stop, kept for reference and for anything that needs a flat ground.
S.color.canvasTop    = { 0.089, 0.073, 0.060 } -- #17130F
S.color.canvasMid    = { 0.059, 0.046, 0.035 } -- #0F0C09
S.color.canvasBottom = { 0.048, 0.037, 0.027 } -- #0C0907

-- Surfaces that sit ON the canvas.
S.color.band         = { 0.074, 0.060, 0.048 } -- #130F0C  title band, footer
S.color.rail         = { 0.074, 0.058, 0.044 } -- #130F0B
S.color.railText     = { 0.469, 0.376, 0.296 } -- #78604B
S.color.card         = { 0.097, 0.079, 0.064 } -- #191410  a card on the canvas
S.color.cardRaised   = { 0.116, 0.097, 0.080 } -- #1D1914  a card on a card
S.color.cardLift     = { 1, 1, 1, 0.03 }       -- white at 3%

-- The divider ramp. Four steps, dimmest to brightest: a rule between rows, a
-- panel edge, a control edge, and the edge of something focused or selected.
S.color.rule         = { 0.172, 0.143, 0.119 } -- #2C251E
S.color.edge         = { 0.187, 0.159, 0.134 } -- #302922
S.color.edgeBright   = { 0.225, 0.190, 0.160 } -- #393029
S.color.steel        = { 0.277, 0.236, 0.201 } -- #473C33  control borders
S.color.steelBright  = { 0.293, 0.252, 0.217 } -- #4B4037  hover / focus

-- Destructive: its own dot, edge and label intensities.
S.color.danger       = { 0.769, 0.282, 0.353 } -- #C4485A  the dot
S.color.dangerEdge   = { 0.420, 0.200, 0.251 } -- #6B3340  the border
S.color.dangerText   = { 0.878, 0.541, 0.588 } -- #E08A96  the label
S.color.warn         = { 0.851, 0.627, 0.306 } -- #D9A04E

-- Neutrals for a switch's OFF state: a surface, not text alphas.
S.color.neutral600   = { 0.490, 0.463, 0.440 } -- #7D7670  the off knob
S.color.neutral700   = { 0.394, 0.363, 0.335 } -- #645C56  the off track

-- The ON knob: a pale tint of the accent rather than white.
S.color.knob         = { 0.981, 0.782, 0.609 } -- #FAC79B

-- The window's outer edge: the only thing separating it from the game UI.
S.color.windowEdge   = { 0.295, 0.260, 0.230 } -- #4B423B

-- The title band, its own small gradient sitting on the window's.
S.color.headerTop    = { 0.114, 0.103, 0.094 } -- #1D1A18
S.color.headerBottom = { 0.097, 0.081, 0.068 } -- #191511

-- ---------------------------------------------------------------------
-- Spacing scale
-- ---------------------------------------------------------------------
--
-- A short list of numbers, and they have names. The values are taste; the point
-- is that there are a dozen of them rather than forty literals scattered across
-- the file, half of them written as their own negative.
--
-- Where a number can be computed from other numbers, it is computed. ROW_H is
-- not an independent choice - a row whose height is picked separately from the
-- control inside it is a row that clips its own control the first time the
-- control grows by two pixels.
local size = {
    PAD       = 16,  -- window edge -> content
    ROW_PAD   = 12,  -- row edge -> label / control
    GAP       = 10,  -- label right bound -> control left
    ITEM_GAP  = 6,   -- between stacked items in a list
    SECTION   = 18,  -- above a section header

    HEADER_H  = 40,  -- window title band
    CLOSE     = 26,  -- the close button, square

    CTRL_H    = 22,  -- checkbox, compact edit box
    BTN_H     = 26,  -- standard button
    BTN_H_SM  = 22,  -- button living inside a row
    BTN_W     = 116, -- standard button
    BTN_W_SM  = 26,  -- the square "x"

    SWATCH_W  = 52,  -- the colour swatch on an overlay page
    TAB_H     = 24,  -- the overlay tab strip
}

size.VPAD     = 5                             -- row edge -> control, vertically
size.ROW_H    = size.CTRL_H + size.VPAD * 2   -- 32
size.ROW_H_SM = size.BTN_H_SM + size.VPAD     -- 27, for dense rows

S.size = size

local function Unpack(c, alpha)
    return c[1], c[2], c[3], alpha or c[4] or 1
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
--
-- Custom font objects rather than the Game* globals: those carry Blizzard's gold
-- and their own shadows, which is most of what makes an addon panel look like an
-- addon panel.
--
-- NOTE: CreateFont names are GLOBAL. They must not collide with
-- SimpleLootCouncil's, which is why every one here is prefixed with this addon's
-- name - and why that file's fonts are prefixed with its own.
local FONT_DIR = "Interface\\AddOns\\CastQueueOverlay\\fonts\\"
local FALLBACK = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local CLIENT_LOCALE = type(GetLocale) == "function" and GetLocale() or "enUS"
local CLIENT_FONT_ONLY = CLIENT_LOCALE == "koKR" or CLIENT_LOCALE == "zhCN"
    or CLIENT_LOCALE == "zhTW"

-- URW Gothic (Demi) for all text, as in SimpleLootCouncil: Latin, Cyrillic and
-- Greek. Licence: fonts/LICENSE-URW.txt. One cut, so weight cannot carry
-- hierarchy; size and colour do. Caps has +.14em tracking baked into the file,
-- since SetFont has no tracking argument.
local FONT_REGULAR  = FONT_DIR .. "URWGothic-Demi.ttf"
local FONT_TABULAR  = FONT_DIR .. "URWGothic-DemiTabular.ttf"
local FONT_CAPS     = FONT_DIR .. "URWGothic-DemiCaps.ttf"

-- Never probed: the client loads a font file in the background, so a first
-- SetFont on it returns false and a probe would send every font to Friz. The
-- client's own face is used only where URW Gothic has no glyphs (Korean and
-- Chinese clients).
local fontsLoaded = not CLIENT_FONT_ONLY
S.fontsLoaded = fontsLoaded

local function MakeFallbackFont(name, path, fontSize, color, flags)
    local f = CreateFont(name)
    local clientFont = path == FONT_CAPS
        and (UNIT_NAME_FONT or FALLBACK) or FALLBACK
    f:SetFont(fontsLoaded and path or clientFont, fontSize, flags or "")
    f:SetTextColor(Unpack(color))
    -- No shadow: all type sits on a flat dark panel.
    f:SetShadowColor(0, 0, 0, 0)
    f:SetShadowOffset(0, 0)
    return f
end

-- Blizzard's own faces for the alphabets URW Gothic does not cover, as its
-- FontFamily definitions in Blizzard_Fonts_Shared/Mainline/Fonts.xml name them.
local ALPHABET_FONTS = {
    korean             = "Fonts\\2002.TTF",
    simplifiedchinese  = "Fonts\\ARKai_T.ttf",
    traditionalchinese = "Fonts\\blei00d.TTF",
}

-- A font FAMILY: CreateFont + SetFont fills only the roman member, so an EditBox
-- draws Cyrillic as boxes. Ours for roman/russian, Blizzard's otherwise.
local function MakeFont(name, path, fontSize, color, flags)
    if type(CreateFontFamily) ~= "function" then
        return MakeFallbackFont(name, path, fontSize, color, flags)
    end
    flags = flags or ""
    local ours = fontsLoaded
    local members = {
        { alphabet = "roman", file = ours and path or FALLBACK,
          height = fontSize, flags = flags },
        { alphabet = "russian", file = ours and path or "Fonts\\FRIZQT___CYR.TTF",
          height = fontSize, flags = flags },
    }
    for alphabet, file in pairs(ALPHABET_FONTS) do
        members[#members + 1] = { alphabet = alphabet, file = file,
            height = fontSize, flags = flags }
    end
    local ok, f = pcall(CreateFontFamily, name, members)
    if not ok or not f then
        return MakeFallbackFont(name, path, fontSize, color, flags)
    end
    f:SetTextColor(Unpack(color))
    f:SetShadowColor(0, 0, 0, 0)
    f:SetShadowOffset(0, 0)
    return f
end

S.fontTitle   = MakeFont("CastQueueOverlayFontTitle",   FONT_REGULAR, 16,   S.color.text)
S.fontHeading = MakeFont("CastQueueOverlayFontHeading", FONT_CAPS,    11,   S.color.textFaint)
S.fontBody    = MakeFont("CastQueueOverlayFontBody",    FONT_REGULAR, 12,   S.color.text)
S.fontSmall   = MakeFont("CastQueueOverlayFontSmall",   FONT_REGULAR, 11,   S.color.textMuted)
S.fontHint    = MakeFont("CastQueueOverlayFontHint",    FONT_REGULAR, 11,   S.color.textFaint)
S.fontNum     = MakeFont("CastQueueOverlayFontNum",     FONT_TABULAR, 12,   S.color.text)

-- Every FontString in this addon's UI goes through here. A FontString wraps by
-- default, and a cell one pixel too narrow becomes three lines inside a
-- fixed-height row: the text is not clipped, it is centred out of the row, and
-- it reads as corruption rather than as a layout bug.
function S.Label(parent, fontObject, justify, lines)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(fontObject or S.fontBody)
    fs:SetJustifyH(justify or "LEFT")
    if lines == "wrap" then
        fs:SetWordWrap(true)
    else
        fs:SetWordWrap(false)
        fs:SetMaxLines(lines or 1)
    end
    return fs
end

-- ---------------------------------------------------------------------
-- Rounded corners
-- ---------------------------------------------------------------------
--
-- Two 32x32 textures, white, with the shape carried entirely in the alpha
-- channel so they can be tinted to anything. Generated by dev/make_art.py, which
-- is checked in alongside them - a binary blob nobody can regenerate is a blob
-- whose radius can never be adjusted.
--
-- Both are NINE-SLICED at RADIUS. That is the whole reason this works: the four
-- corners are drawn at their native size and only the straight edges stretch, so
-- the radius is identical on a 460px window and on a 22px checkbox. A plainly
-- stretched texture cannot do that - its corners turn into ellipses the moment
-- the frame is not square.
--
-- RADIUS must match the value in dev/make_art.py.
--
-- ⚠️ ROUNDING IS FOR WINDOW SURFACES ONLY.
--
-- A window is a surface the UI sits on; a button, an edit box and a checkbox are
-- objects sitting on it. Rounding both makes everything read as the same kind of
-- thing, and at control sizes the curve eats most of the edge - a 16px button is
-- twice the radius tall, so it stops looking like a button and starts looking
-- like a pill. Controls are square with a one-pixel border, and the difference
-- in shape is doing real work: it is what separates the container from its
-- contents.
--
-- So: S.Window rounds. S.Button, S.Checkbox, S.Inset and the colour swatch do
-- not.
local ART = "Interface\\AddOns\\CastQueueOverlay\\art\\"
local ROUND_FILL    = ART .. "rounded"
local ROUND_OUTLINE = ART .. "rounded-outline"
local RADIUS = 8

-- Whether the art actually loaded.
--
-- SetTexture returns a success flag, and this is exactly what it is for. A
-- missing or unreadable .tga would otherwise take every window in the addon with
-- it - a mask that fails to load masks everything - and the failure would
-- present as a completely blank options window, which is a far worse outcome
-- than square corners. Everything below falls back to the flat path when this is
-- false.
local rounded = false
do
    -- On a throwaway frame, not on UIParent. A probe texture parented to
    -- UIParent outlives the check and sits in Blizzard's frame for the session.
    local scratch = CreateFrame("Frame")
    local probe = scratch:CreateTexture(nil, "BACKGROUND")
    rounded = probe:SetTexture(ROUND_FILL) and true or false
    probe:SetTexture(nil)
    scratch:Hide()
end
S.rounded = rounded

local function SliceNine(tex, asset)
    tex:SetTexture(asset)
    tex:SetTextureSliceMargins(RADIUS, RADIUS, RADIUS, RADIUS)
    tex:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
    return tex
end

-- A mask that clips whatever it is applied to down to the rounded rectangle.
--
-- `bounds` is the frame the CORNERS should follow, which is not always the frame
-- owning the texture: a window's header band is a child that has to be clipped
-- by the WINDOW's corners, or its own square top corners poke out past them.
-- Masks are positional, so anchoring the mask to the window and applying it to
-- the header's texture does exactly that.
function S.RoundMask(bounds)
    if not rounded then return nil end
    local mask = bounds:CreateMaskTexture()
    mask:SetAllPoints(bounds)
    -- CLAMPTOBLACKADDITIVE, or the mask tiles and clips nothing outside its own
    -- rect.
    mask:SetTexture(ROUND_FILL, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetTextureSliceMargins(RADIUS, RADIUS, RADIUS, RADIUS)
    mask:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
    return mask
end

-- ---------------------------------------------------------------------
-- Primitives
-- ---------------------------------------------------------------------

function S.Fill(frame, color, alpha, layer)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND")
    t:SetAllPoints(frame)
    t:SetColorTexture(Unpack(color, alpha))
    P.Crisp(t)
    return t
end

-- Hairline border as four edges, rather than a backdrop edgeFile, so it stays
-- exactly one PHYSICAL pixel at any frame size and any UI scale.
--
-- `thickness` is counted in physical pixels and defaults to 1.
--
-- Anchoring both corners on one side and setting only the cross dimension is the
-- idiom: the edge then tracks the frame's size with no per-resize maintenance.
--
-- Three things here are deliberate and were not in the previous version:
--
--   * The edges live in a CONTAINER frame of their own rather than on the host.
--     That gives one object to show, hide and re-snap, instead of four loose
--     textures the caller has to keep track of.
--   * The container sits at the host's OWN frame level, not one above it. A
--     child frame outranks every draw layer of its parent, so a border container
--     at +1 draws its edges over the host's own label. At equal levels the two
--     interleave by draw layer instead, and a BORDER edge stays under an OVERLAY
--     label where it belongs.
--   * Calling it twice on the same frame returns the border that is already
--     there. Four more textures stacked on the previous four is invisible until
--     someone recolours one set and wonders why nothing changed.
local borders = setmetatable({}, { __mode = "k" })

function S.Border(frame, color, layer, thickness)
    local existing = borders[frame]
    if existing then
        if color then existing:SetColor(color) end
        if thickness then existing:SetThickness(thickness) end
        return existing
    end

    local px = thickness or 1

    local ring = CreateFrame("Frame", nil, frame)
    ring:EnableMouse(false)
    ring:SetAllPoints()
    ring:SetFrameLevel(frame:GetFrameLevel())

    local edges = {}
    local function edge(p1, p2, horizontal)
        local t = ring:CreateTexture(nil, layer or "BORDER")
        t:SetColorTexture(Unpack(color))
        P.Edge(t)
        t:SetPoint(p1)
        t:SetPoint(p2)
        t.cqoHorizontal = horizontal
        edges[#edges + 1] = t
        return t
    end

    local function applyThickness()
        -- Measured against the CONTAINER, so a host with a scale of its own gets
        -- a hairline in its own coordinate space rather than in UIParent's.
        local w = P.Hairline(ring) * px
        for i = 1, #edges do
            local t = edges[i]
            if t.cqoHorizontal then t:SetHeight(w) else t:SetWidth(w) end
        end
    end

    edge("TOPLEFT", "TOPRIGHT", true)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    edge("TOPLEFT", "BOTTOMLEFT", false)
    edge("TOPRIGHT", "BOTTOMRIGHT", false)
    applyThickness()

    -- The effective scale is not final in the frame the border is created in,
    -- and it does not settle in one pass either. Three chances at it: the
    -- coalesced post-layout flush, the first couple of frames after that, and
    -- every subsequent UI scale change.
    P.AfterLayout(applyThickness)
    P.Settle(applyThickness)
    P.OnRescale(applyThickness)

    local handle = {
        SetColor = function(_, c)
            for i = 1, #edges do edges[i]:SetColorTexture(Unpack(c)) end
        end,
        SetShown = function(_, on)
            ring:SetShown(on and true or false)
        end,
        SetThickness = function(_, n)
            px = n or 1
            applyThickness()
        end,
        Frame = ring,
    }

    borders[frame] = handle
    return handle
end

-- The rounded counterpart of S.Border, with the same SetColor/SetShown handle so
-- the two are interchangeable at a call site.
--
-- One nine-sliced ring rather than four edges. It is derived from the same shape
-- as the mask, so the outline and the fill it sits on are concentric by
-- construction - an outline drawn independently drifts from its fill, and the
-- gap shows at exactly the corners this exists to make look deliberate.
function S.RoundBorder(frame, color, layer)
    if not rounded then return S.Border(frame, color, layer) end

    local ring = frame:CreateTexture(nil, layer or "BORDER")
    ring:SetAllPoints(frame)
    SliceNine(ring, ROUND_OUTLINE)
    ring:SetVertexColor(Unpack(color))

    return {
        SetColor = function(_, c) ring:SetVertexColor(Unpack(c)) end,
        SetShown = function(_, on) ring:SetShown(on and true or false) end,
    }
end

-- The canvas gradient.
--
-- SetGradient MODULATES the texture, so the texture underneath has to be white
-- at full alpha or the gradient is multiplied into whatever colour was there.
--
-- Orientation "VERTICAL" takes minColor at the BOTTOM and maxColor at the TOP.
-- If a window comes up dark at the top, swap the two arguments HERE and nowhere
-- else - every window in the addon is drawn through this one function.
--
-- The corners are clipped with a MASK rather than by drawing the gradient onto
-- the rounded texture itself. Nine-slicing splits a texture into nine quads, and
-- a vertex gradient across nine quads is nine gradients with visible seams at
-- the slice boundaries. Masking keeps the gradient on one flat quad spanning the
-- whole frame, which is the only way it stays smooth.
function S.GradientFill(frame, topColor, bottomColor, alpha, layer)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND")
    t:SetAllPoints(frame)
    t:SetColorTexture(1, 1, 1, 1)
    P.Crisp(t)
    t:SetGradient("VERTICAL",
        CreateColor(bottomColor[1], bottomColor[2], bottomColor[3], alpha or 1),
        CreateColor(topColor[1], topColor[2], topColor[3], alpha or 1))

    local mask = S.RoundMask(frame)
    if mask then t:AddMaskTexture(mask) end
    return t, mask
end

-- A recessed panel: anything typeable, or any readout that should read as a hole
-- cut in the window rather than as something sitting on it.
function S.Inset(parent, deep)
    local f = CreateFrame("Frame", nil, parent)
    S.Fill(f, deep and S.color.insetDeep or S.color.inset)
    -- Square, with a one-pixel border. An edit box is an object on the window,
    -- not a window.
    f.border = S.Border(f, S.color.border)
    return f
end

-- ---------------------------------------------------------------------
-- Disabled state
-- ---------------------------------------------------------------------

-- Why a control is dead, phrased the same way every time.
--
-- A control that looks live and does nothing is the most common complaint about
-- addons in restricted content, and the reason is never guessable from the UI.
-- Naming the requirement is the whole fix. Templating it is what stops several
-- call sites each inventing their own wording for the same idea - and wording
-- that varies reads as several different problems rather than one rule.
--
-- A string that already ends in a full stop passes through untouched, so a
-- genuinely one-off explanation is not forced through the template.
--
--   S.Requires("you to be out of combat")
--     -> "Requires you to be out of combat."
--   S.Requires("Separate opacity while channelling", "enabled")
--     -> "Requires \"Separate opacity while channelling\" to be enabled."
function S.Requires(requirement, state)
    if type(requirement) ~= "string" or requirement == "" then return nil end
    if requirement:find("%.%s*$") then return requirement end

    if state then
        return ('Requires "%s" to be %s.'):format(requirement, state)
    end
    return ("Requires %s."):format(requirement)
end

-- ---------------------------------------------------------------------
-- Controls
-- ---------------------------------------------------------------------

-- The close X, DRAWN rather than typed.
--
-- Two bars rotated a quarter-turn apart about their own centres, anchored at the
-- button's CENTER. The result is centred by construction - at any size, in any
-- locale, with no dependence on font metrics.
--
-- A text "x" cannot manage that. A FontString centred in a button centres its
-- LINE BOX, and a lowercase x sits on the baseline with the descender space
-- still reserved below it, so the ink lands below the button's true centre no
-- matter how large the button gets. It could also ellipsise, which is what made
-- the equivalent button in SimpleLootCouncil render ".." at 18px - and this
-- addon's old close button was a FontString "X" with the same latent fault.
local function CloseGlyph(button, extent)
    local bars = {}
    -- Thickness scales with the button, with a hairline floor so it never
    -- disappears at a small size or on a low-DPI display.
    local thickness = math.max(P.Hairline(), extent / 9)

    for i = 1, 2 do
        local bar = button:CreateTexture(nil, "OVERLAY")
        bar:SetColorTexture(1, 1, 1, 1)
        P.Size(bar, extent, thickness)
        bar:SetPoint("CENTER")
        bar:SetRotation(i == 1 and (math.pi / 4) or -(math.pi / 4))
        bars[i] = bar
    end

    return {
        SetColor = function(_, c)
            for i = 1, #bars do bars[i]:SetVertexColor(Unpack(c)) end
        end,
    }
end

-- S.Button(parent, text, opts)
--
--   opts.width     override; defaults to size.BTN_W
--   opts.height    override; defaults to size.BTN_H
--   opts.compact   a button living inside a row (size.BTN_H_SM)
--   opts.primary   the accent edge and ink, for the one action a window is FOR
--   opts.glyph     "close" draws the X instead of setting text
--   opts.font      override font object
--
-- The size is an OVERRIDE, not a parameter. The previous signature was
-- S.Button(parent, text, width, height, primary), and every call site invented
-- its own numbers - 24, 26 and 74 all appeared for buttons doing the same job.
function S.Button(parent, text, opts)
    opts = opts or {}

    local b = CreateFrame("Button", nil, parent)
    local h = opts.height or (opts.compact and size.BTN_H_SM or size.BTN_H)
    local w = opts.width or size.BTN_W

    -- A size that cannot fit its own contents is raised, here, by the widget.
    --
    -- The size is an OVERRIDE, and an override too small for its label is a
    -- rendering fault the call site cannot see: it surfaces as an ellipsis, or
    -- as a glyph clipped by its own border, never as an error. So the floor is
    -- enforced where the geometry is owned rather than trusted to every call
    -- site. 1.6 x the font height is the line box plus room to breathe.
    local _, fontHeight = (opts.font or S.fontBody):GetFont()
    fontHeight = tonumber(fontHeight) or 12
    h = math.max(h, math.ceil(fontHeight * 1.6))

    -- Never narrower than it is tall. A square is the floor for any button, so a
    -- single-character label always has symmetric room around it - which is what
    -- "centred" actually requires.
    w = math.max(w, h)

    P.Size(b, w, h)

    -- Outline buttons, as in SimpleLootCouncil: the variant is the EDGE hue and the
    -- fill is only a hover surface (white alphas). `primary` is the action a
    -- window is FOR: accent edge and ink. Hover brightens the edge, never the ink.
    local edge, ink, brightEdge
    if opts.primary then
        edge, ink, brightEdge = S.color.accent, S.color.accent, S.color.knob
    else
        edge, ink, brightEdge = S.color.steel, S.color.text, S.color.steelBright
    end

    local base  = { 1, 1, 1, 0.00 }
    local hover = { 1, 1, 1, 0.06 }
    local down  = { 0, 0, 0, 0.20 }

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(b)
    bg:SetColorTexture(Unpack(base))
    P.Crisp(bg)

    -- SQUARE, with a one-pixel border - four snapped edges, not the nine-sliced
    -- ring. Buttons are objects on a rounded surface, and keeping them square is
    -- what makes the window read as the container.
    local border = S.Border(b, edge)

    -- Bounded on both sides. A label anchored only at CENTER is free to grow
    -- straight out through the button's own edges - silently, with no error and
    -- no clipping - the first time a label is longer than the button. The old
    -- S.Button anchored at CENTER only, i.e. carried exactly that bug.
    --
    -- The inset is DERIVED FROM THE WIDTH. Bounding the label is what makes it
    -- ellipsise instead of overflow, and ellipsising is correct for a word - but
    -- a one-character button is not a text button, and an ellipsis with no room
    -- for three dots renders as TWO.
    local pad = opts.labelPad or (w <= 24 and 1 or 4)

    local label = S.Label(b, opts.font or S.fontBody, "CENTER")
    local function placeLabel(dy)
        label:SetPoint("LEFT", b, "LEFT", Snap(pad), dy)
        label:SetPoint("RIGHT", b, "RIGHT", Snap(-pad), dy)
    end
    placeLabel(0)
    label:SetText(text)
    b.Label = label

    -- An icon button draws its glyph instead of setting text, but still carries
    -- the FontString so SetLabel stays valid on every button.
    local glyph
    if opts.glyph == "close" then
        label:Hide()
        glyph = CloseGlyph(b, math.floor(math.min(w, h) * 0.42))
    end
    b.Glyph = glyph

    -- One place that colours whatever this button uses for ink, so hover,
    -- pressed and disabled never have to know which kind of button they are on.
    local function setInk(colour)
        label:SetTextColor(Unpack(colour))
        if glyph then glyph:SetColor(colour) end
    end
    setInk(ink)

    local enabled = true

    local function paint(colour)
        bg:SetColorTexture(Unpack(colour))
    end

    b:SetScript("OnEnter", function(self)
        if not enabled then return end
        paint(hover)
        border:SetColor(brightEdge)
        if self.cqoHoverIn then self.cqoHoverIn(self) end
    end)
    b:SetScript("OnLeave", function(self)
        if not enabled then return end
        paint(base)
        border:SetColor(edge)
        if self.cqoHoverOut then self.cqoHoverOut(self) end
    end)
    b:SetScript("OnMouseDown", function()
        if not enabled then return end
        paint(down)
        label:ClearAllPoints()
        placeLabel(-1)
    end)
    b:SetScript("OnMouseUp", function(self)
        if not enabled then return end
        paint(self:IsMouseOver() and hover or base)
        label:ClearAllPoints()
        placeLabel(0)
    end)

    function b:SetLabel(t) label:SetText(t) end

    -- Disabled has to be VISIBLE, not merely inert.
    function b:SetEnabled(on)
        enabled = on and true or false
        if enabled then
            paint(base)
            setInk(ink)
            border:SetColor(edge)
            b:EnableMouse(true)
        else
            bg:SetColorTexture(Unpack(base))
            setInk(S.color.textFaint)
            -- Dropped to the panel hairline. A disabled control keeping the
            -- white edge would still read as the brightest thing in the row.
            border:SetColor(S.color.border)
            -- Mouse stays ENABLED when there is a reason to show, or the tooltip
            -- explaining why the button is dead never fires.
            b:EnableMouse(b.cqoReason ~= nil)
        end
    end

    -- Names the upstream requirement rather than leaving the user to guess.
    --
    -- The hooks are installed ONCE, here, and the setter only stores a string.
    -- Hooking inside the setter stacks a new pair of handlers on every call, and
    -- the natural call site for this is a refresh that runs on every state
    -- change - so a window left open would accumulate thousands.
    b:HookScript("OnEnter", function(self)
        if enabled or not self.cqoReason then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.cqoReason, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:HookScript("OnLeave", function(self)
        if not self.cqoReason then return end
        GameTooltip:Hide()
    end)

    function b:SetDisabledReason(reason)
        b.cqoReason = reason
        if not enabled then b:EnableMouse(reason ~= nil) end
    end

    return b
end

function S.EditBox(parent, width, height)
    local holder = S.Inset(parent)
    P.Size(holder, width, height or size.CTRL_H)

    local e = CreateFrame("EditBox", nil, holder)
    P.Point(e, "TOPLEFT", 6, 0)
    P.Point(e, "BOTTOMRIGHT", -6, 0)
    e:SetFontObject(S.fontBody)
    e:SetAutoFocus(false)
    e:SetTextInsets(0, 0, 0, 0)

    e:HookScript("OnEditFocusGained", function() holder.border:SetColor(S.color.accent) end)
    e:HookScript("OnEditFocusLost", function() holder.border:SetColor(S.color.border) end)
    e:HookScript("OnEnter", function() holder.border:SetColor(S.color.borderBright) end)
    e:HookScript("OnLeave", function()
        holder.border:SetColor(e:HasFocus() and S.color.accent or S.color.border)
    end)

    holder.EditBox = e
    return holder, e
end

-- The checkbox owns its own click behaviour when handed a handler.
--
-- No tick glyph: at this size a filled accent square reads faster than art, and
-- it is the same accent as the progress fill and the focused edit box, so the
-- three read as the same UI.
function S.Checkbox(parent, boxSize, onToggle)
    local b = CreateFrame("Button", nil, parent)
    P.Size(b, boxSize or size.CTRL_H, boxSize or size.CTRL_H)

    S.Fill(b, S.color.insetDeep)
    local border = S.Border(b, S.color.border)

    local fill = b:CreateTexture(nil, "ARTWORK")
    P.Point(fill, "TOPLEFT", 3, -3)
    P.Point(fill, "BOTTOMRIGHT", -3, 3)
    fill:SetColorTexture(Unpack(S.color.on))
    P.Crisp(fill)
    fill:Hide()

    local checked = false
    function b:SetChecked(on)
        checked = on and true or false
        fill:SetShown(checked)
    end
    function b:GetChecked() return checked end

    b:SetScript("OnEnter", function(self)
        border:SetColor(S.color.borderBright)
        if self.cqoHoverIn then self.cqoHoverIn(self) end
    end)
    b:SetScript("OnLeave", function(self)
        border:SetColor(S.color.border)
        if self.cqoHoverOut then self.cqoHoverOut(self) end
    end)

    if onToggle then
        b:SetScript("OnClick", function(self)
            local value = not self:GetChecked()
            self:SetChecked(value)
            onToggle(value)
        end)
    end

    return b
end

-- Horizontal slider: recessed groove with an accent thumb. Built from our own
-- textures rather than OptionsSliderTemplate, which brings Blizzard's metal
-- trough and gold-bordered thumb.
--
-- The groove is a separate frame behind the slider rather than a texture on it:
-- the slider itself has to be tall enough to be comfortable to grab, while the
-- groove should stay thin. The groove is anchored to the slider here rather than
-- being handed back for the caller to place - the old version returned an
-- unanchored `Groove` and the call site had to remember to position it, which is
-- the canonical "widget incomplete without caller cooperation" failure.
function S.Slider(parent, width, height)
    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    P.Size(s, width, height or 18)
    s:SetHitRectInsets(0, 0, 0, 0)

    local groove = CreateFrame("Frame", nil, s)
    groove:SetFrameLevel(s:GetFrameLevel())
    P.Size(groove, nil, 4)
    groove:SetPoint("LEFT")
    groove:SetPoint("RIGHT")
    S.Fill(groove, S.color.insetDeep)
    local grooveBorder = S.Border(groove, S.color.border)

    -- The thumb is created BEFORE the filled part of the groove, because that
    -- fill anchors to it.
    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(Unpack(S.color.on))
    P.Size(thumb, 8, 16)
    P.Crisp(thumb)
    s:SetThumbTexture(thumb)

    -- The travelled part of the groove, in the same accent as the thumb. An
    -- unfilled groove makes a slider read as a decoration with a knob on it; the
    -- fill is what says "this is a value, and it is this far along".
    --
    -- Anchored to the THUMB's centre rather than computed from the value, so it
    -- tracks whatever the engine actually did with the thumb - including the
    -- half-thumb inset at each end, which a width computed from the fraction
    -- gets wrong at exactly the two positions anyone checks first.
    local progress = groove:CreateTexture(nil, "ARTWORK")
    progress:SetColorTexture(Unpack(S.color.on))
    P.Crisp(progress)
    progress:SetPoint("TOPLEFT")
    progress:SetPoint("BOTTOMLEFT")
    progress:SetPoint("RIGHT", thumb, "CENTER", 0, 0)

    local enabled = true

    s:SetScript("OnEnter", function()
        if not enabled then return end
        thumb:SetColorTexture(Unpack(S.color.text))
        grooveBorder:SetColor(S.color.borderBright)
    end)
    s:SetScript("OnLeave", function()
        if not enabled then return end
        thumb:SetColorTexture(Unpack(S.color.on))
        grooveBorder:SetColor(S.color.border)
    end)

    -- Disabled must LOOK disabled. A slider that still shows a lit thumb and a
    -- bright bar but refuses to move is the exact complaint S.Requires exists to
    -- answer - so the FILL is greyed along with the thumb. Greying only the
    -- thumb leaves the loudest part of the control still lit.
    function s:SetEnabled(on)
        enabled = on and true or false
        s:EnableMouse(enabled)
        local ink = enabled and S.color.on or S.color.textFaint
        thumb:SetColorTexture(Unpack(ink))
        progress:SetColorTexture(Unpack(ink, enabled and 1 or 0.35))
        grooveBorder:SetColor(S.color.border)
    end

    s.Groove = groove
    return s
end

-- A section header, complete.
--
-- The rule anchors ITSELF to its own parent's inset and exposes nothing. The
-- previous version handed `heading.Rule` back unanchored on one side, so the
-- widget was only correct because every call site remembered to finish it with
-- its own `Rule:SetPoint("RIGHT", win, "RIGHT", -PAD, 0)` - and one that forgot
-- rendered a zero-width or full-bleed rule with no error. That exact line
-- appeared four times in the old options file.
--
-- Returns frame, height, like every other builder.
function S.Heading(parent, x, width, y, text)
    local f = CreateFrame("Frame", nil, parent)
    local H = 20
    P.Size(f, width, H)
    P.Point(f, "TOPLEFT", parent, "TOPLEFT", x, y)

    local fs = S.Label(f, S.fontHeading, "LEFT")
    fs:SetText(text and text:upper() or "")
    fs:SetPoint("LEFT", f, "LEFT", 0, 0)

    local rule = f:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(Unpack(S.color.border))
    P.Edge(rule)
    rule:SetPoint("LEFT", fs, "RIGHT", Snap(size.GAP), 0)
    rule:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    local function ruleThickness() rule:SetHeight(P.Hairline()) end
    ruleThickness()
    P.OnRescale(ruleThickness)

    f.Text = fs
    f.Rule = rule
    return f, H
end

-- One tab in a strip.
--
-- The tab's WIDTH is passed in by L.TabStrip, which divides the available width
-- between them, rather than measured from the label. That is not a shortcut: a
-- FontString's width is not final in the frame it is created in, so a tab sized
-- from GetStringWidth at build time - which is what the old S.Tab did - is sized
-- against a string the engine has not laid out yet.
--
-- State is carried by the fill and by an accent underline, not by the text
-- colour alone. An inactive tab keeps the muted heading colour so the strip
-- still reads as a section label rather than as a row of buttons.
function S.Tab(parent, text, width, height)
    local b = CreateFrame("Button", nil, parent)
    P.Size(b, width, height or size.TAB_H)

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(b)
    bg:SetColorTexture(Unpack(S.color.controlOff))
    P.Crisp(bg)

    local border = S.Border(b, S.color.border)

    -- The active marker: a rule along the bottom edge, in the accent. Which
    -- tab you are on is a selection, the same class of state as a ticked box, so
    -- it takes the same colour.
    local marker = b:CreateTexture(nil, "OVERLAY")
    marker:SetColorTexture(Unpack(S.color.on))
    P.Crisp(marker)
    marker:SetPoint("BOTTOMLEFT")
    marker:SetPoint("BOTTOMRIGHT")
    local function markerThickness() marker:SetHeight(P.Hairline() * 2) end
    markerThickness()
    P.OnRescale(markerThickness)
    marker:Hide()

    -- Bounded on both sides, so a long tab label ellipsises rather than drawing
    -- through its neighbour.
    local label = S.Label(b, S.fontHeading, "CENTER")
    P.Point(label, "LEFT", b, "LEFT", 4, 0)
    P.Point(label, "RIGHT", b, "RIGHT", -4, 0)
    label:SetText(text)
    b.Label = label

    local active = false

    local function paint()
        if active then
            bg:SetColorTexture(Unpack(S.color.control))
            border:SetColor(S.color.controlBorder)
            label:SetTextColor(Unpack(S.color.text))
        elseif b:IsMouseOver() then
            bg:SetColorTexture(Unpack(S.color.rowHover))
            border:SetColor(S.color.borderBright)
            label:SetTextColor(Unpack(S.color.text))
        else
            bg:SetColorTexture(Unpack(S.color.controlOff))
            border:SetColor(S.color.border)
            label:SetTextColor(Unpack(S.color.textMuted))
        end
        marker:SetShown(active)
    end

    function b:SetActive(on)
        active = on and true or false
        paint()
    end
    function b:IsActive() return active end

    b:SetScript("OnEnter", paint)
    b:SetScript("OnLeave", paint)
    paint()

    return b
end

-- ---------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------

-- Movable frame with a gradient canvas, a title band, a close button, remembered
-- position and Escape handling.
--
-- Position persistence is not a nicety - every user moves these windows, and
-- losing it on every reload is immediately irritating. The old options window
-- was movable and forgot where it was put.
--
-- The important part is `f.Content`: a frame inset below the title band, which
-- the page builds into. Before this, every section anchored itself at a
-- hand-written offset from the one above it, so the title-band height existed
-- implicitly in half a dozen places and could not be changed in any of them.
function S.Window(globalName, key, width, height, title)
    local f = CreateFrame("Frame", globalName, UIParent)
    P.Size(f, width, height)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)   -- also stops clicks falling through to the world
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:Hide()

    local _, windowMask = S.GradientFill(f, S.color.canvasTop, S.color.canvasBottom, 0.96)
    S.RoundBorder(f, S.color.border, "OVERLAY")

    -- The title band: its own small gradient (headerTop to headerBottom) plus a
    -- hairline rule beneath it.
    local header = CreateFrame("Frame", nil, f)
    header:SetFrameLevel(f:GetFrameLevel() + 1)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    P.Size(header, nil, size.HEADER_H)
    local headerFill = S.Fill(header, { 1, 1, 1, 1 })
    headerFill:SetGradient("VERTICAL",
        CreateColor(S.color.headerBottom[1], S.color.headerBottom[2], S.color.headerBottom[3], 1),
        CreateColor(S.color.headerTop[1], S.color.headerTop[2], S.color.headerTop[3], 1))
    -- Clipped by the WINDOW's corners, not its own. The header spans the top of
    -- the window, so masking it against itself would round its bottom corners
    -- (wrong) while leaving its top ones to poke out past the window's (also
    -- wrong). The mask is positional, so pointing the header's texture at the
    -- window's mask clips exactly the two corners it shares.
    if windowMask then headerFill:AddMaskTexture(windowMask) end
    f.Header = header

    local headerRule = header:CreateTexture(nil, "ARTWORK")
    headerRule:SetColorTexture(Unpack(S.color.border))
    P.Edge(headerRule)
    headerRule:SetPoint("BOTTOMLEFT")
    headerRule:SetPoint("BOTTOMRIGHT")
    local function ruleThickness() headerRule:SetHeight(P.Hairline()) end
    ruleThickness()
    P.OnRescale(ruleThickness)

    local close = S.Button(f, "", { width = size.CLOSE, height = size.CLOSE,
        glyph = "close" })
    close:SetFrameLevel(header:GetFrameLevel() + 2)
    -- Centred in the title band by construction: the same inset top and right,
    -- derived from the band's height rather than chosen.
    local closeInset = (size.HEADER_H - size.CLOSE) * 0.5
    P.Point(close, "TOPRIGHT", f, "TOPRIGHT", -closeInset, -closeInset)
    close:SetScript("OnClick", function() f:Hide() end)
    f.Close = close

    -- A slot between the title and the close button, for a version string or any
    -- other short annotation that belongs to the window rather than to the page.
    -- Right-justified and hugging the close button, with the title bounded
    -- against IT, so the two can never collide however long either gets.
    local badge = S.Label(header, S.fontSmall, "RIGHT")
    P.Point(badge, "RIGHT", close, "LEFT", -size.GAP, 0)
    P.Size(badge, 70, size.CLOSE)
    f.Badge = badge

    local titleText = S.Label(header, S.fontTitle, "LEFT")
    P.Point(titleText, "LEFT", header, "LEFT", size.PAD, 0)
    -- Bounded on both sides, so a long title ellipsises instead of drawing
    -- straight through whatever is next to it.
    P.Point(titleText, "RIGHT", badge, "LEFT", -size.GAP, 0)
    titleText:SetText(title)
    f.Title = titleText

    -- Every page anchors into here and never needs to know the header exists.
    local content = CreateFrame("Frame", nil, f)
    content:SetFrameLevel(f:GetFrameLevel() + 1)
    P.Point(content, "TOPLEFT", f, "TOPLEFT", size.PAD, -(size.HEADER_H + size.PAD))
    P.Point(content, "BOTTOMRIGHT", f, "BOTTOMRIGHT", -size.PAD, size.PAD)

    -- The content width, RECORDED rather than measured.
    --
    -- Content is anchored by two corners so it tracks the window, and a frame
    -- anchored that way reports GetWidth() == 0 until the engine has resolved
    -- the layout - which has not happened in the frame that created it. The page
    -- builds immediately after S.Window returns, so it would be laying itself
    -- out against a width of zero.
    --
    -- The symptom is not an error. Section headings still draw, because a
    -- FontString anchored on one point is unbounded; every ROW collapses to zero
    -- width, so its label is bounded between two offsets that cross and renders
    -- nothing at all.
    content.cqoWidth = width - size.PAD * 2
    f.Content = content

    -- Drag from the title band only. Making the whole window draggable means
    -- every miss-click on a row moves the window instead.
    local grip = CreateFrame("Frame", nil, header)
    grip:SetPoint("TOPLEFT")
    grip:SetPoint("BOTTOMRIGHT", close, "BOTTOMLEFT")
    grip:EnableMouse(true)
    grip:RegisterForDrag("LeftButton")
    grip:SetScript("OnDragStart", function() f:StartMoving() end)
    grip:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        P.AlignFrame(f)
        -- Store point/relative/offsets rather than GetRect, so the saved
        -- position survives a UI scale change.
        local point, _, relPoint, x, y = f:GetPoint()
        local db = CastQueueOverlayDB
        if not db then return end
        db.windows = db.windows or {}
        db.windows[key] = { point = point, relPoint = relPoint, x = x, y = y }
    end)

    function f:RestorePosition()
        local db = CastQueueOverlayDB
        local pos = db and db.windows and db.windows[key]
        f:ClearAllPoints()
        if pos and pos.point then
            f:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
        else
            f:SetPoint("CENTER")
        end
        P.AlignFrame(f)
    end

    if globalName then
        -- Escape closes it, like every other panel in the game.
        tinsert(UISpecialFrames, globalName)
    end

    return f
end
