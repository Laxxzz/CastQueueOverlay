-- CastQueueOverlay: the layout layer.
--
-- One rule, and everything here is a way of enforcing it:
--
--   EVERY BUILDER RETURNS THE VERTICAL SPACE IT CONSUMED.
--
-- A page owns a cursor and never does any other arithmetic. It cannot overlap
-- its own rows, because it never learns a row's height and never chooses one. A
-- widget whose internals change - a subtitle added, a control that grew -
-- reports a different height and everything below it moves, with no call site
-- touched.
--
-- The shape this replaces is what the old options file looked like throughout:
--
--     local channelHeading = S.Heading(win, "CHANNELING OPACITY")
--     channelHeading:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 0, -24)
--     channelHeading.Rule:SetPoint("RIGHT", win, "RIGHT", -PAD, 0)
--
-- Three separate things are wrong there and they compound. The widget is
-- incomplete without caller cooperation, so a call site that forgets to anchor
-- the rule renders a broken heading and nothing errors. The caller invented the
-- 24, and the four sections in that file each invented a different number. And
-- every offset is measured from the frame ABOVE it, so inserting a row means
-- re-anchoring the one after it.
--
-- Whitespace goes through the same channel. The moment a gap is written as a
-- bare offset at the call site, the cursor stops being the single source of
-- truth and hand-tuned exceptions start accreting.

-- The namespace guard MUST be repeated in every file that touches it. See
-- decision #1.
CastQueueOverlay = CastQueueOverlay or {}
local addon = CastQueueOverlay

local L = {}
addon.Layout = L

local P = addon.Pixel
local S = addon.Style
local size = S.size

-- ---------------------------------------------------------------------
-- How wide is this thing?
-- ---------------------------------------------------------------------

-- GetWidth() answers for the layout AS IT CURRENTLY STANDS, and a frame anchored
-- by two opposite corners has no resolved width until the engine has laid it out
-- - which has not happened in the frame that created it. Reading it there
-- returns 0, and 0 propagates silently: rows collapse, labels get a negative
-- bound and draw nothing.
--
-- So anything that is anchored rather than sized RECORDS the width it was built
-- to have, and this prefers the record. `S.Window` does it for f.Content; any
-- host frame stretched between two corners must do the same.
function L.WidthOf(frame)
    local recorded = frame.cqoWidth
    if type(recorded) == "number" and recorded > 0 then return recorded end

    local measured = frame:GetWidth()
    if type(measured) == "number" and measured > 0 then return measured end

    -- Loud rather than silent. A zero here is always a bug, and its symptom - a
    -- window that renders its headings and none of its content - looks nothing
    -- like a width problem from the outside.
    print("|cff33ff99CastQueueOverlay:|r layout: parent has no resolved width; "
        .. "set .cqoWidth on it")
    return 0
end

-- ---------------------------------------------------------------------
-- The cursor
-- ---------------------------------------------------------------------

local Cursor = {}
Cursor.__index = Cursor

-- L.Cursor(parent, opts)
--
--   opts.x       left inset within parent; defaults to 0, because the standard
--                parent is a window's Content frame, which is already inset
--   opts.width   defaults to the parent's width less twice the inset
--   opts.top     starting offset; defaults to 0
function L.Cursor(parent, opts)
    opts = opts or {}
    local x = opts.x or 0
    return setmetatable({
        parent = parent,
        x      = x,
        width  = opts.width or (L.WidthOf(parent) - x * 2),
        y      = -(opts.top or 0),
        start  = -(opts.top or 0),
    }, Cursor)
end

-- Build one thing at the cursor and advance past it.
--
-- The builder is called as builder(parent, x, width, y, ...) and must return
-- frame, height. A builder that returns no height advances nothing, which shows
-- up immediately as the next row drawn on top of it - loud, and therefore fine.
--
-- ONLY frame and height come back through here. A builder with more to hand over
-- - L.TabStrip and its tab table - must hang it off the frame it returns, or the
-- caller silently receives nil: `local _, _, tabs = cursor:Add(L.TabStrip, ...)`
-- reads a third return value this function never forwards.
function Cursor:Add(builder, ...)
    local frame, height = builder(self.parent, self.x, self.width, self.y, ...)
    self.y = self.y - (height or 0)
    return frame, height
end

-- Whitespace, through the same channel as everything else.
function Cursor:Gap(amount)
    self.y = self.y - (amount or size.ITEM_GAP)
    return self
end

-- Vertical space consumed so far.
function Cursor:Consumed()
    return self.start - self.y
end

-- The current offset, for the rare thing that has to anchor itself.
function Cursor:Y() return self.y end

-- The width this cursor lays out into.
function Cursor:Width() return self.width end

-- The height a container needs to hold everything built so far, including a
-- bottom pad equal to the top one.
--
--   frame:SetHeight(cursor:Height(pad))   -- height IS the cursor
--
-- Never precompute a container's height in one place and lay out in another.
-- They drift the first time either changes.
function Cursor:Height(padBottom)
    return -self.y + (padBottom or 0)
end

-- ---------------------------------------------------------------------
-- Builders
-- ---------------------------------------------------------------------
--
-- Every one of these takes (parent, x, width, y, ...) and returns frame, height.
-- Nothing below ever reads a literal offset out of a call site.

-- A section header with a rule running to the right edge of its column.
function L.Section(parent, x, width, y, text)
    return S.Heading(parent, x, width, y, text)
end

-- Bare vertical space, as a builder, so it goes through the cursor like
-- everything else.
function L.Spacer(parent, x, width, y, height)
    return nil, height or size.ITEM_GAP
end

-- The row primitive: a fixed-height, full-width frame that lights on hover.
--
-- Its label anchors LEFT and its control anchors RIGHT, and neither knows the
-- other's size. The failing alternative - anchoring the control at a measured
-- x-offset from the left - is correct for exactly one panel width and one
-- string, and collides the moment either changes.
function L.Row(parent, x, width, y, height)
    local f = CreateFrame("Frame", nil, parent)
    f:SetFrameLevel(parent:GetFrameLevel() + 1)
    P.Size(f, width, height or size.ROW_H)
    P.Point(f, "TOPLEFT", parent, "TOPLEFT", x, y)

    local hover = f:CreateTexture(nil, "BACKGROUND")
    hover:SetAllPoints(f)
    hover:SetColorTexture(S.Unpack(S.color.rowHover))
    P.Crisp(hover)
    hover:Hide()
    f.Hover = hover

    f:EnableMouse(true)
    f:SetScript("OnEnter", function() hover:Show() end)
    f:SetScript("OnLeave", function() hover:Hide() end)

    -- Hovering a CHILD control fires the row's OnLeave, so the row flickers dark
    -- as the cursor crosses onto the very control it was advertising. Children
    -- keep the row lit by chaining through these.
    function f:AdoptHover(child)
        child.cqoHoverIn  = function() hover:Show() end
        child.cqoHoverOut = function() hover:SetShown(f:IsMouseOver()) end
        return child
    end

    -- Alternating stripes do more for scannability than any border. Parity is
    -- passed in rather than counted here, so a page can reset it at each section
    -- header and every section starts the same way.
    function f:SetStripe(index)
        if not index then return end
        local stripe = f:CreateTexture(nil, "BACKGROUND", nil, -1)
        stripe:SetAllPoints(f)
        stripe:SetColorTexture(S.Unpack(index % 2 == 0 and S.color.rowEven or S.color.rowOdd))
        P.Crisp(stripe)
    end

    return f, height or size.ROW_H
end

-- A label bounded against a control on its right.
--
-- Anchored on both sides the FontString has a finite width and the engine
-- ellipsises overflow. Anchored on ONE side it is unbounded in that direction
-- and will draw straight through whatever is next to it - silently, with no
-- error and no clipping.
local function BoundedLabel(row, control, text, fontObject)
    local fs = S.Label(row, fontObject or S.fontBody, "LEFT")
    fs:SetText(text)
    P.Point(fs, "LEFT", row, "LEFT", size.ROW_PAD, 0)
    P.Point(fs, "RIGHT", control, "LEFT", -size.GAP, 0)
    return fs
end
L.BoundedLabel = BoundedLabel

-- Truncated text that cannot be recovered is a worse bug than overlap, so a
-- label that had to ellipsise says so on hover.
--
-- Runs deferred, because a string's width is not final in the frame it was set
-- in, and coalesced, because a page build registers dozens of these.
function L.RevealIfTruncated(owner, fs, fullText)
    P.AfterLayout(function()
        local natural, bounded = fs:GetStringWidth(), fs:GetWidth()

        -- GetStringWidth is SecretWhenAnchoringSecret: anchored to something
        -- secret it returns a secret, and comparing a secret silently poisons
        -- the result rather than erroring.
        if issecretvalue and (issecretvalue(natural) or issecretvalue(bounded)) then
            return
        end
        if type(natural) ~= "number" or type(bounded) ~= "number" then return end
        -- Epsilon: these are floats.
        if natural <= bounded + 0.5 then return end

        owner:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(fullText or fs:GetText(), 1, 1, 1, true)
            GameTooltip:Show()
        end)
        owner:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end)
end

-- Attach a label/description tooltip to a row and to one of its children, so
-- crossing onto the control does not lose the explanation.
local function RowTooltip(row, child, label, tooltip)
    if not tooltip then return end
    local function show(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(label, 1, 1, 1)
        GameTooltip:AddLine(tooltip, 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end
    row:HookScript("OnEnter", show)
    row:HookScript("OnLeave", function() GameTooltip:Hide() end)
    if child then
        child:HookScript("OnEnter", show)
        child:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
end
L.RowTooltip = RowTooltip

-- opts: label, tooltip, get, set, stripe
function L.Toggle(parent, x, width, y, opts)
    local row = L.Row(parent, x, width, y)
    row:SetStripe(opts.stripe)

    local box = S.Checkbox(row, size.CTRL_H, opts.set)
    P.Point(box, "RIGHT", row, "RIGHT", -size.ROW_PAD, 0)
    box:SetChecked(opts.get and opts.get() or false)
    row:AdoptHover(box)
    row.Box = box
    row.Get = opts.get

    local label = BoundedLabel(row, box, opts.label)
    L.RevealIfTruncated(row, label, opts.tooltip and (opts.label .. "\n" .. opts.tooltip))
    row.LabelText = label

    -- The whole row is the click target, not just the 22px box. A checkbox you
    -- have to hit exactly is a checkbox people miss.
    row:SetScript("OnMouseUp", function()
        if not opts.set then return end
        local value = not box:GetChecked()
        box:SetChecked(value)
        opts.set(value)
    end)

    RowTooltip(row, box, opts.label, opts.tooltip)

    return row, size.ROW_H
end

-- opts: label, tooltip, get, set, width (of the input), numeric, suffix, stripe
function L.Input(parent, x, width, y, opts)
    local row = L.Row(parent, x, width, y)
    row:SetStripe(opts.stripe)

    -- A trailing unit ("ms") is part of the row, not of the value, so it lives
    -- outside the edit box and the box's right edge is bounded against it.
    local anchor = row
    local anchorPoint, anchorOffset = "RIGHT", -size.ROW_PAD
    if opts.suffix then
        local unit = S.Label(row, S.fontHint, "LEFT")
        unit:SetText(opts.suffix)
        P.Point(unit, "RIGHT", row, "RIGHT", -size.ROW_PAD, 0)
        row.Suffix = unit
        anchor, anchorPoint, anchorOffset = unit, "LEFT", -size.ITEM_GAP
    end

    local holder, edit = S.EditBox(row, opts.width or 70)
    P.Point(holder, "RIGHT", anchor, anchorPoint, anchorOffset, 0)
    row:AdoptHover(edit)
    row.Holder, row.EditBox = holder, edit

    edit:SetNumeric(opts.numeric and true or false)
    edit:SetText(tostring(opts.get and opts.get() or ""))
    edit:SetScript("OnEnterPressed", function(self)
        if opts.set then opts.set(self:GetText()) end
        self:ClearFocus()
    end)
    edit:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(opts.get and opts.get() or ""))
        self:ClearFocus()
    end)

    local label = BoundedLabel(row, holder, opts.label)
    L.RevealIfTruncated(row, label, opts.tooltip and (opts.label .. "\n" .. opts.tooltip))
    row.LabelText = label

    RowTooltip(row, nil, opts.label, opts.tooltip)

    return row, size.ROW_H
end

-- A read-only "name: value" row, for state the panel reports rather than edits.
-- opts: label, value, font, height, stripe
function L.Readout(parent, x, width, y, opts)
    local row = L.Row(parent, x, width, y, opts.height or size.ROW_H)
    row:SetStripe(opts.stripe)
    row:EnableMouse(false)

    local value = S.Label(row, opts.font or S.fontSmall, "RIGHT")
    P.Point(value, "RIGHT", row, "RIGHT", -size.ROW_PAD, 0)
    value:SetText(opts.value or "")
    row.Value = value

    local label = BoundedLabel(row, value, opts.label, S.fontSmall)
    row.LabelText = label

    return row, row:GetHeight()
end

-- A slider row: label on the left, slider on the right, value read out between
-- them. opts: label, tooltip, min, max, step, get, set, format, width, stripe
--
-- The slider's width is an override; it defaults to a fixed share of the row so
-- the label always has room. The value readout sits immediately left of the
-- slider and bounds the label, so all three can never collide.
function L.SliderRow(parent, x, width, y, opts)
    local row = L.Row(parent, x, width, y)
    row:SetStripe(opts.stripe)

    local slider = S.Slider(row, opts.width or 130)
    P.Point(slider, "RIGHT", row, "RIGHT", -size.ROW_PAD, 0)
    row:AdoptHover(slider)
    row.Slider = slider

    local value = S.Label(row, S.fontSmall, "RIGHT")
    P.Point(value, "RIGHT", slider, "LEFT", -size.GAP, 0)
    P.Size(value, 48, size.CTRL_H)
    row.Value = value

    local label = BoundedLabel(row, value, opts.label)
    row.LabelText = label

    local format = opts.format or function(v) return tostring(v) end

    slider:SetMinMaxValues(opts.min or 0, opts.max or 1)
    slider:SetValueStep(opts.step or 0.01)
    slider:SetObeyStepOnDrag(true)

    -- Seeded before the handler is attached, so the seed cannot round-trip
    -- through the saved variable. OnValueChanged fires from SetValue as well as
    -- from a drag, and there is no way to tell them apart from inside it.
    local current = opts.get and opts.get() or 0
    slider:SetValue(current)
    value:SetText(format(current))

    slider:SetScript("OnValueChanged", function(_, v)
        value:SetText(format(v))
        if opts.set then opts.set(v) end
    end)

    -- Refreshing from outside must not fire the setter either.
    function row:SetValue(v)
        slider:SetScript("OnValueChanged", nil)
        slider:SetValue(v)
        value:SetText(format(v))
        slider:SetScript("OnValueChanged", function(_, nv)
            value:SetText(format(nv))
            if opts.set then opts.set(nv) end
        end)
    end

    -- Disabled must be visible AND explain itself. The label and readout drop to
    -- the faint level along with the thumb, so the whole row reads as inert
    -- rather than just the control.
    function row:SetEnabled(on, reason)
        slider:SetEnabled(on)
        label:SetTextColor(S.Unpack(on and S.color.text or S.color.textFaint))
        value:SetTextColor(S.Unpack(on and S.color.textMuted or S.color.textFaint))
        row.cqoReason = (not on) and reason or nil
    end

    row:HookScript("OnEnter", function(self)
        if not self.cqoReason then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.cqoReason, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    row:HookScript("OnLeave", function() GameTooltip:Hide() end)

    RowTooltip(row, nil, opts.label, opts.tooltip)

    return row, size.ROW_H
end

-- A wrapped paragraph, measured.
--
-- The width is set EXPLICITLY rather than by two anchors before measuring:
-- GetStringHeight is only meaningful once the string knows how wide it may be,
-- and a FontString sized by anchors does not know that until layout settles.
function L.Paragraph(parent, x, width, y, text, fontObject)
    local fs = S.Label(parent, fontObject or S.fontBody, "LEFT", "wrap")
    fs:SetWidth(P.Snap(width))
    P.Point(fs, "TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetText(text or "")

    local h = fs:GetStringHeight()
    if issecretvalue and issecretvalue(h) then h = nil end
    if type(h) ~= "number" or h <= 0 then
        -- A fallback, not a guess dressed up as a measurement: one line of body
        -- text, so the paragraph is at worst cramped rather than overlapped.
        h = 14
    end

    return fs, math.ceil(h)
end

-- A fixed-height wrapped paragraph, for text that CHANGES after the layout is
-- fixed - a status line, a validation message.
--
-- Measuring one of those would size the window to whichever string happened to
-- be set at build time, and the window would then have to resize every time the
-- message changed. Reserving the space up front is the honest trade: the height
-- is stated, and a longer message ellipsises rather than pushing the footer off
-- the bottom.
function L.MessageLine(parent, x, width, y, lines, fontObject)
    lines = lines or 2
    local fs = S.Label(parent, fontObject or S.fontSmall, "LEFT", lines)
    fs:SetWordWrap(true)
    fs:SetWidth(P.Snap(width))
    P.Point(fs, "TOPLEFT", parent, "TOPLEFT", x, y)

    local _, fontHeight = (fontObject or S.fontSmall):GetFont()
    fontHeight = tonumber(fontHeight) or 11
    local h = math.ceil(fontHeight * 1.35) * lines

    P.Size(fs, width, h)
    return fs, h
end

-- A right-aligned strip of buttons.
--
-- `specs` is an array of { text, opts, onClick, key }, laid out right to left in
-- the order given, so specs[1] is the rightmost - the primary action sits where
-- the eye and the cursor already are.
function L.ButtonRow(parent, x, width, y, specs)
    local row = L.Row(parent, x, width, y, size.BTN_H)
    row:EnableMouse(false)

    local previous
    for i = 1, #specs do
        local spec = specs[i]
        local b = S.Button(row, spec.text, spec.opts)
        if previous then
            P.Point(b, "RIGHT", previous, "LEFT", -size.GAP, 0)
        else
            P.Point(b, "RIGHT", row, "RIGHT", 0, 0)
        end
        if spec.onClick then b:SetScript("OnClick", spec.onClick) end
        row[spec.key or i] = b
        previous = b
    end

    return row, size.BTN_H
end

-- A strip of tabs that divides the available width between them.
--
-- The width comes from the cursor rather than from each label's string width,
-- which is what makes this correct in the frame it is built in - see the note on
-- S.Tab. n tabs separated by GAP have n-1 gaps, not n; that missing subtraction
-- is the most commonly forgotten term in addon layout and shows up as a strip
-- whose last tab hangs past the right edge.
--
-- `keys` is the ordered list, `labels` maps key -> text, `onSelect` is called
-- with the key. The tab table is hung off the strip as `.Tabs` rather than
-- returned third, because Cursor:Add forwards only frame and height.
function L.TabStrip(parent, x, width, y, keys, labels, onSelect)
    local strip = CreateFrame("Frame", nil, parent)
    strip:SetFrameLevel(parent:GetFrameLevel() + 1)
    P.Size(strip, width, size.TAB_H)
    P.Point(strip, "TOPLEFT", parent, "TOPLEFT", x, y)

    local n = #keys
    local each = (width - size.ITEM_GAP * (n - 1)) / n

    local tabs = {}
    for i = 1, n do
        local key = keys[i]
        local tab = S.Tab(strip, labels[key] or key, each)
        P.Point(tab, "TOPLEFT", strip, "TOPLEFT", (each + size.ITEM_GAP) * (i - 1), 0)
        tab:SetScript("OnClick", function() onSelect(key) end)
        tabs[key] = tab
    end

    strip.Tabs = tabs
    return strip, size.TAB_H
end

-- ---------------------------------------------------------------------
-- Frame levels
-- ---------------------------------------------------------------------

-- Absolute frame levels collide. A child takes its parent's level plus a small
-- delta, so a whole subtree can be re-based by moving its root.
function L.Above(child, parent, delta)
    child:SetFrameLevel(parent:GetFrameLevel() + (delta or 1))
    return child
end
