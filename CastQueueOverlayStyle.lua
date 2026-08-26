-- CastQueueOverlay: shared visual language for the standalone options window.
--
-- A dark-blue-to-light-blue gradient canvas, raised light-blue controls sitting
-- on top of it, recessed black insets for anything typeable, hairline borders
-- rather than bevels, and one warm accent used only for state.
--
-- This palette and these widget contracts are SimpleLootCouncil's, adopted
-- deliberately so the two addons read as one suite. The previous look here was a
-- warm near-black "editor" palette that shared only the coral accent; two
-- addons by the same author that agree on the accent and nothing else look like
-- a coincidence rather than a family.
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
--   * Everything that is not the canvas or a control surface is white or black
--     at an alpha, never a colour. That is what lets the canvas gradient be
--     retinted without re-picking forty hex values.

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
-- they stay correctly contrasted at every point along the canvas gradient - a
-- hardcoded border hex is correct against exactly one background, and this
-- window does not have one background.
S.color = {
    -- The canvas gradient. Light at the top, dark at the bottom, because that is
    -- where ambient light comes from and because it puts the lightest band
    -- behind the title where the header sits.
    canvasTop    = { 0.141, 0.251, 0.369 }, -- #24405E  light blue
    canvasBottom = { 0.047, 0.086, 0.145 }, -- #0C1625  dark blue

    -- A single flat stand-in for the gradient, for the few places that need one
    -- colour rather than two: primary button label text, small solid chips.
    canvas       = { 0.075, 0.145, 0.231 }, -- #13253B  the gradient's midpoint

    -- Controls are RAISED, so they are a blue of their own rather than the
    -- canvas. This is the one place a hue is spent on something that is not
    -- state: a button that is white-at-alpha over this gradient reads grey, and
    -- a panel of grey buttons on a blue window looks like two addons stapled
    -- together.
    --
    -- They sit DARKER than the canvas gradient's upper half, and the separation
    -- is carried by the white border below rather than by the fill. A fill light
    -- enough to read as raised against the top of the gradient washes out
    -- against the bottom of it - the hazard of putting a flat colour on a
    -- background that is not one colour.
    control      = { 0.145, 0.243, 0.349 }, -- #253E59  button rest
    controlHover = { 0.208, 0.333, 0.463 }, -- #355576  button hover
    controlDown  = { 0.106, 0.176, 0.255 }, -- #1B2D41  button pressed

    -- A button's border is WHITE, not the panel hairline. It is what actually
    -- separates a control from the canvas now that the fill is dark, so it is a
    -- deliberate step brighter than every other edge in the addon - and it is
    -- still one physical pixel.
    controlBorder      = { 1, 1, 1, 0.65 },
    controlBorderHover = { 1, 1, 1, 1.00 },

    -- Inputs are RECESSED, so they are darker than whatever is behind them.
    -- Black at an alpha rather than a hex, so an edit box reads as a hole in the
    -- panel at any point on the gradient.
    inset        = { 0, 0, 0, 0.34 },
    insetDeep    = { 0, 0, 0, 0.46 },

    border       = { 1, 1, 1, 0.11 },       -- hairline
    borderBright = { 1, 1, 1, 0.26 },       -- focused / hovered edge

    text         = { 1, 1, 1, 1.00 },       -- primary
    textMuted    = { 1, 1, 1, 0.62 },       -- secondary
    textFaint    = { 1, 1, 1, 0.40 },       -- hints, disabled

    rowOdd       = { 0, 0, 0, 0.10 },       -- alternating list stripe
    rowEven      = { 0, 0, 0, 0.20 },
    rowHover     = { 1, 1, 1, 0.07 },

    -- The "not currently a control" fill: a disabled button, an inactive tab.
    -- Black at an alpha rather than a darker blue, so it recedes into whatever
    -- point of the gradient it happens to sit on instead of reading as a
    -- differently-coloured control.
    controlOff   = { 0, 0, 0, 0.22 },

    -- Two tiers of state, and which is which is a rule rather than a taste:
    --
    --   `on`     a SETTING's state - checked, selected, the primary action.
    --            Blue, because these are the controls themselves and a coral
    --            control on a blue panel reads as belonging to another addon.
    --   `accent` where the cursor or keyboard is RIGHT NOW - a focused edit box,
    --            the frame picker's outline. Coral, and rare enough to stay loud.
    --
    -- Before this, both jobs were coral, so a ticked checkbox and a focused field
    -- shouted equally hard and the panel had no quiet resting state.
    --
    -- `on` is deliberately LIGHTER than every other blue here. It has to read as
    -- lit against the control fill it sits on (#253E59) and against both ends of
    -- the canvas gradient, and the only axis left for that is brightness.
    on           = { 0.427, 0.639, 0.847 }, -- #6DA3D8  checked, selected, primary
    onDim        = { 0.290, 0.478, 0.667 }, -- #4A7AAA  pressed

    accent       = { 0.851, 0.467, 0.341 }, -- #D97757  coral
    accentDim    = { 0.612, 0.325, 0.231 }, -- #9C533B  pressed accent
    good         = { 0.400, 0.780, 0.541 }, -- #66C78A  success
    bad          = { 0.898, 0.451, 0.451 }, -- #E57373  error
}

-- Kept as aliases so the palette swap did not have to be a call-site migration
-- as well. `surface` was doing two contradictory jobs in the old palette - it
-- was both the button base and the edit-box inset - which is why raised and
-- recessed looked identical and nothing read as clickable.
S.color.surface      = S.color.control
S.color.surfaceHover = S.color.controlHover

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
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

local function MakeFont(name, fontSize, color, flags)
    local f = CreateFont(name)
    f:SetFont(FONT, fontSize, flags or "")
    f:SetTextColor(Unpack(color))
    -- A one-pixel black shadow, unlike Blizzard's offset-2 gold one, and unlike
    -- the old flat no-shadow rule here. On a gradient canvas the same text
    -- crosses light and dark ground, and unshadowed white loses its edges
    -- against the lighter band at the top.
    f:SetShadowColor(0, 0, 0, 0.75)
    f:SetShadowOffset(1, -1)
    return f
end

S.fontTitle   = MakeFont("CastQueueOverlayFontTitle",   15, S.color.text)
S.fontHeading = MakeFont("CastQueueOverlayFontHeading", 11, S.color.textMuted)
S.fontBody    = MakeFont("CastQueueOverlayFontBody",    12, S.color.text)
S.fontSmall   = MakeFont("CastQueueOverlayFontSmall",   11, S.color.textMuted)
S.fontHint    = MakeFont("CastQueueOverlayFontHint",    11, S.color.textFaint)

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
        P.Crisp(t)
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
--   opts.primary   the coral accent, for the one action a window is FOR
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

    -- `primary` is the blue "on" tone, not the coral accent. Apply and Done are
    -- the action a window is FOR, which is a state of the panel, not a focus
    -- marker - and a coral button was the one thing on screen that did not look
    -- like it came with the rest of the addon.
    local base  = opts.primary and S.color.on or S.color.control
    local hover = opts.primary and S.color.onDim or S.color.controlHover
    local down  = opts.primary and S.color.onDim or S.color.controlDown

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(b)
    bg:SetColorTexture(Unpack(base))
    P.Crisp(bg)

    -- SQUARE, with a one-pixel white border - four snapped edges, not the
    -- nine-sliced ring. Buttons are objects on a rounded surface, and keeping
    -- them square is what makes the window read as the container.
    --
    -- White on primary and plain alike. "Which of these is a button" should not
    -- be a question the fill alone has to answer.
    local border = S.Border(b, S.color.controlBorder)

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
    setInk(opts.primary and S.color.canvas or S.color.text)

    local enabled = true

    local function paint(colour)
        bg:SetColorTexture(Unpack(colour))
    end

    b:SetScript("OnEnter", function(self)
        if not enabled then return end
        paint(hover)
        border:SetColor(S.color.controlBorderHover)
        if self.cqoHoverIn then self.cqoHoverIn(self) end
    end)
    b:SetScript("OnLeave", function(self)
        if not enabled then return end
        paint(base)
        border:SetColor(S.color.controlBorder)
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
            setInk(opts.primary and S.color.canvas or S.color.text)
            border:SetColor(S.color.controlBorder)
            b:EnableMouse(true)
        else
            bg:SetColorTexture(Unpack(S.color.controlOff))
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

-- Horizontal slider: recessed groove with a coral thumb. Built from our own
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

    -- The travelled part of the groove, in the same "on" blue as the thumb. An
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
    P.Crisp(rule)
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

    -- The active marker: a rule along the bottom edge, in the "on" blue. Which
    -- tab you are on is a selection, the same class of state as a ticked box, so
    -- it takes the same colour - not the coral, which is reserved for where the
    -- keyboard or cursor is right now.
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

    -- The title band. A subtle white wash plus a hairline rule beneath it, which
    -- is enough to separate chrome from content without spending a second colour
    -- on it.
    local header = CreateFrame("Frame", nil, f)
    header:SetFrameLevel(f:GetFrameLevel() + 1)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    P.Size(header, nil, size.HEADER_H)
    local headerFill = S.Fill(header, { 1, 1, 1, 0.05 })
    -- Clipped by the WINDOW's corners, not its own. The header spans the top of
    -- the window, so masking it against itself would round its bottom corners
    -- (wrong) while leaving its top ones to poke out past the window's (also
    -- wrong). The mask is positional, so pointing the header's texture at the
    -- window's mask clips exactly the two corners it shares.
    if windowMask then headerFill:AddMaskTexture(windowMask) end
    f.Header = header

    local headerRule = header:CreateTexture(nil, "ARTWORK")
    headerRule:SetColorTexture(Unpack(S.color.border))
    P.Crisp(headerRule)
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
    end

    if globalName then
        -- Escape closes it, like every other panel in the game.
        tinsert(UISpecialFrames, globalName)
    end

    return f
end
