-- CastQueueOverlay: pixel snapping, and the deferred-measurement queue.
--
-- Loads FIRST - before the style file - because every border, size and offset in
-- the options window is routed through Snap(). See reference/ui-design.md §8 in
-- the WoW-Addon-API-Ref repo, and decision #18 in docs/design-decisions.md.
--
-- The failure this exists to prevent: a 1px border is 1px only when one UI unit
-- maps to one physical pixel. At any other effective scale it lands between
-- pixels, one edge renders at 2px and the opposite edge vanishes. It gets
-- reported as "the border is clipped at the bottom", fixed by nudging, then
-- reported as "clipped at the top".
--
-- The namespace guard MUST be repeated in every file that touches it. A `local`
-- captures the value at this instant, so a file that loads before the table
-- exists would capture nil forever. See decision #1.

CastQueueOverlay = CastQueueOverlay or {}
local addon = CastQueueOverlay

local P = {}
addon.Pixel = P

-- ---------------------------------------------------------------------
-- One physical pixel
-- ---------------------------------------------------------------------
--
-- `perfect` is one physical pixel expressed in WoW's 768-based UI coordinates at
-- scale 1. Everything else is derived from it by dividing by whatever scale the
-- thing being measured is actually drawn at.
--
--     perfect  = 768 / physicalScreenHeight
--     onePixel = perfect / frame:GetEffectiveScale()
--
-- HEIGHT, not width. WoW's UI coordinate space is defined as 768 units tall
-- regardless of aspect ratio, so the height ratio is exact while a width ratio
-- only happens to agree at 4:3.
local perfect = 1     -- one physical pixel at scale 1
local mult    = 1     -- one physical pixel at UIParent's scale

-- GetEffectiveScale carries SecretReturnsForAspect = { Enum.SecretAspect.Scale },
-- so under restrictions it can hand back a secret - and a secret in this
-- arithmetic does not error, it silently poisons every offset in the window.
--
-- issecretvalue is SecretArguments = "AllowedWhenUntainted", so it must not be
-- used as a general probe. Guarding a value we are about to do arithmetic on is
-- the sanctioned use. See reference/security-model.md.
local function Secret(v)
    return issecretvalue ~= nil and issecretvalue(v) and true or false
end

-- A usable effective scale, or nil.
--
-- Wrapped in pcall as well as guarded for secrets: the call itself can fail on a
-- frame that has been torn down or is forbidden, and a border helper must not
-- take the whole window down with it. This addon's frame picker walks arbitrary
-- third-party regions, so "a frame we do not own" is a routine argument here.
local function EffectiveScale(frame)
    if not frame or not frame.GetEffectiveScale then return nil end

    local ok, scale = pcall(frame.GetEffectiveScale, frame)
    if not ok or Secret(scale) then return nil end
    if type(scale) ~= "number" or scale <= 0 then return nil end
    return scale
end
P.EffectiveScale = EffectiveScale

local function Recompute()
    local _, physH = GetPhysicalScreenSize()
    if Secret(physH) or type(physH) ~= "number" or physH <= 0 then return end

    perfect = 768 / physH
    mult = perfect / (EffectiveScale(UIParent) or 1)
end

function P.Multiplier() return mult end
function P.Perfect() return perfect end

-- One physical pixel in the coordinate space of THIS frame.
--
-- Falls back to the UIParent-derived multiplier when the frame cannot answer,
-- which is correct for anything parented to UIParent at the default scale.
function P.OnePixel(frame)
    local scale = EffectiveScale(frame)
    if not scale then return mult end
    return perfect / scale
end

-- The thickness of a hairline. Frame-aware; the no-argument form answers for
-- UIParent.
function P.Hairline(frame)
    local px = frame and P.OnePixel(frame) or mult
    return px > 0 and px or 1
end

-- Round a UI-unit value onto the physical pixel grid.
--
-- `frame` is optional and selects whose grid to round onto; without it the
-- rounding is against UIParent's, which is what every call site here means.
function P.Snap(x, frame)
    if type(x) ~= "number" or x == 0 then return x end

    local step = frame and P.OnePixel(frame) or mult
    if step <= 0 then return x end

    local pixels = math.floor(math.abs(x) / step + 0.5)
    return x < 0 and -pixels * step or pixels * step
end

-- ---------------------------------------------------------------------
-- Snapping wrappers
-- ---------------------------------------------------------------------
--
-- Routing sizes and offsets through wrappers is far more reliable than
-- remembering to call Snap() at each call site.
--
-- These snap against UIParent's grid rather than the target frame's, because a
-- frame is routinely sized BEFORE it is parented or anchored - so asking it for
-- its own effective scale here would answer for a position it does not have yet.
-- Border thickness, the one measurement that has to be exact, is computed per
-- frame at snap time instead.
local Snap = P.Snap

function P.Size(frame, w, h)
    if w and h then
        frame:SetSize(Snap(w), Snap(h))
    elseif w then
        frame:SetWidth(Snap(w))
    elseif h then
        frame:SetHeight(Snap(h))
    end
    return frame
end

-- Snaps every NUMERIC argument and passes everything else through untouched.
--
-- Doing it by type rather than by argument position is not laziness: SetPoint's
-- three-argument form is ambiguous - (point, x, y) and (point, relativeTo,
-- relativePoint) have the same arity - so any position-based rule has to guess,
-- and guessing wrong silently anchors to the wrong thing.
function P.Point(obj, ...)
    local n = select("#", ...)
    if n == 0 then return obj end

    local args = { ... }
    for i = 1, n do
        if type(args[i]) == "number" then args[i] = Snap(args[i]) end
    end
    obj:SetPoint(unpack(args, 1, n))
    return obj
end

-- Textures do their own snapping, and it fights ours: the engine rounds in texel
-- space while we round in UI space, and the two disagree by fractions that show
-- up as a shimmering edge.
function P.Crisp(tex)
    tex:SetSnapToPixelGrid(false)
    tex:SetTexelSnappingBias(0)
    return tex
end

-- A one-pixel line: Crisp, plus the engine's own pixel snapping while a window is
-- scaled, since our grid only holds at a scale of 1. Tracked weakly so the mode
-- can be flipped for every line at once. `forced` is a debugging override.
local edges = setmetatable({}, { __mode = "k" })
local edgeSnap, edgeForced = false, nil

local function ApplyEdgeSnap(on)
    if on == edgeSnap then return end
    edgeSnap = on
    for tex in pairs(edges) do
        tex:SetSnapToPixelGrid(on)
        tex:SetTexelSnappingBias(0)
    end
end

function P.Edge(tex)
    P.Crisp(tex)
    edges[tex] = true
    if edgeSnap then tex:SetSnapToPixelGrid(true) end
    return tex
end

-- nil hands the choice back to the scale.
function P.SetEdgeSnap(on)
    if on == nil then edgeForced = nil return end
    edgeForced = on and true or false
    ApplyEdgeSnap(edgeForced)
end

function P.AutoEdgeSnap(on)
    if edgeForced == nil then ApplyEdgeSnap(on and true or false) end
end

-- ---------------------------------------------------------------------
-- Window alignment
-- ---------------------------------------------------------------------

-- A window's edge sits this fraction of a pixel past the grid, so a child half a
-- pixel off always rounds the same way wherever the window is dragged to.
P.WINDOW_BIAS = 1 / 64

-- The window edge nearest `pixels` (a position counted in physical pixels).
function P.GridPixel(pixels)
    return math.floor(pixels - P.WINDOW_BIAS + 0.5) + P.WINDOW_BIAS
end

-- Align a UIParent child by its real screen edges (odd widths, post-drag offsets).
function P.AlignFrame(frame)
    local point, relativeTo, relativePoint, x, y = frame:GetPoint()
    if Secret(point) or Secret(relativeTo) or Secret(relativePoint) then return end
    if not point or (relativeTo and relativeTo ~= UIParent) then return end
    if type(x) ~= "number" or type(y) ~= "number" or Secret(x) or Secret(y) then return end

    local physW, physH = GetPhysicalScreenSize()
    if type(physW) ~= "number" or type(physH) ~= "number"
        or Secret(physW) or Secret(physH) or physW <= 0 or physH <= 0 then return end

    local width, height = frame:GetWidth(), frame:GetHeight()
    if type(width) ~= "number" or type(height) ~= "number"
        or Secret(width) or Secret(height) or width <= 0 or height <= 0 then return end

    local step = P.OnePixel(frame)
    local function position(part, extent)
        if part:find("LEFT", 1, true) or part:find("BOTTOM", 1, true) then return 0 end
        if part:find("RIGHT", 1, true) or part:find("TOP", 1, true) then return extent end
        return extent * 0.5
    end
    local relative = relativePoint or point
    local left = position(relative:match("LEFT") or relative:match("RIGHT") or "CENTER", physW)
        + x / step - position(point:match("LEFT") or point:match("RIGHT") or "CENTER", width / step)
    local bottom = position(relative:match("BOTTOM") or relative:match("TOP") or "CENTER", physH)
        + y / step - position(point:match("BOTTOM") or point:match("TOP") or "CENTER", height / step)
    local dx = (P.GridPixel(left) - left) * step
    local dy = (P.GridPixel(bottom) - bottom) * step
    if math.abs(dx) > step * 0.0001 or math.abs(dy) > step * 0.0001 then
        frame:SetPoint(point, relativeTo or UIParent, relative, x + dx, y + dy)
    end
end

-- ---------------------------------------------------------------------
-- Re-snapping when the ground moves
-- ---------------------------------------------------------------------
--
-- A panel that is pixel-perfect at login and wrong after the user drags the UI
-- scale slider is the same bug with a delay on it.

local resnap = {}

function P.OnRescale(fn)
    resnap[#resnap + 1] = fn
    return fn
end

local function Rescale()
    Recompute()
    for i = 1, #resnap do
        local fn = resnap[i]
        -- Hole-tolerant: one bad registrant must not stop the rest of the window
        -- from being re-snapped.
        if fn then pcall(fn) end
    end
end

-- A window's scale changed: every border and rule measures itself again.
P.Resnap = Rescale

-- ---------------------------------------------------------------------
-- Deferred measurement
-- ---------------------------------------------------------------------
--
-- GetLeft/GetWidth/GetStringWidth answer for the layout AS IT CURRENTLY STANDS.
-- Inside a builder, siblings that will be anchored a moment later do not exist
-- yet, and a parent sized by its own contents has not been sized. Anything that
-- measures has to run after layout settles.
--
-- Coalesced into ONE timer for the whole queue: a page build registers dozens of
-- these, and dozens of timers is dozens of layout passes.

local queue, queued = {}, false

local function Flush()
    queued = false
    local n = #queue
    for i = 1, n do
        local fn = queue[i]
        queue[i] = nil
        -- An error partway through leaves nil holes behind, and one bad row must
        -- not take the whole pass down with it - that unstyles the entire page.
        if fn then pcall(fn) end
    end
end

function P.AfterLayout(fn)
    queue[#queue + 1] = fn
    if not queued then
        queued = true
        C_Timer.After(0, Flush)
    end
end

-- Re-apply for the first couple of frames after creation.
--
-- The effective scale settles a frame or two after a frame is built, and a
-- single post-layout pass can land before it does. One shared watcher for every
-- registrant rather than a frame each - a page build registers a border per
-- widget, and a frame per border is a frame per widget forever.
--
-- Bounded and self-cancelling: two ticks after the LAST registration, then the
-- queue is dropped and the OnUpdate is removed.
local settleQueue, settleFrame, settleTicks = {}, nil, 0

local function SettleTick(self)
    settleTicks = settleTicks + 1
    for i = 1, #settleQueue do
        local fn = settleQueue[i]
        if fn then pcall(fn) end
    end
    if settleTicks >= 2 then
        self:SetScript("OnUpdate", nil)
        for i = #settleQueue, 1, -1 do settleQueue[i] = nil end
    end
end

function P.Settle(fn)
    settleQueue[#settleQueue + 1] = fn
    settleTicks = 0
    if not settleFrame then settleFrame = CreateFrame("Frame") end
    settleFrame:SetScript("OnUpdate", SettleTick)
end

-- ---------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------
--
-- Self-initialising, unlike SimpleLootCouncil's equivalent, which is driven from
-- an explicit UI Init phase. This addon has no such phase: the style file loads
-- next and creates its font objects immediately, so anything that had to wait
-- for a caller would be snapping against a multiplier of 1 by the time it ran.
Recompute()

do
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("UI_SCALE_CHANGED")
    watcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    watcher:SetScript("OnEvent", Rescale)
end
