-- Offline harness for the options UI.
--
--   luajit dev/test_ui.lua
--
-- Test-WowAddon.ps1 proves the files PARSE and that every API they name exists.
-- It cannot prove they RUN: an upvalue read before it is assigned, a builder
-- whose return values do not line up with what the cursor expects, or a table
-- indexed one frame too early are all valid Lua and all fatal in game.
--
-- This stubs enough of the widget API to actually execute the four UI files,
-- build the options window, switch every tab and drive every refresh path - the
-- work `/cqo` does on the first press. It is deliberately a LOGIC harness, not a
-- renderer: geometry is tracked well enough for the layout arithmetic to be
-- real, and nothing is drawn.
--
-- Unmodelled widget methods are recorded rather than silently swallowed, and
-- listed at the end, so a method this harness is lying about cannot hide.
--
-- NOTE: Test-WowAddon.ps1 lints this file too - it recurses over every .lua
-- under the addon folder and has no exclude - and reports four warnings against
-- it that are correct and permanent: `io`, `arg`, `:read()` and `:close()` are
-- standard Lua, and standard Lua is not part of the WoW API surface the linter
-- checks against. Everything else in here is kept lint-clean so those four stay
-- the only ones and a real warning cannot hide behind them.

local unknown = {}

-- ---------------------------------------------------------------------
-- Widget stubs
-- ---------------------------------------------------------------------

-- An unknown key reads as NIL, exactly as it does on a real widget.
--
-- The first version of this harness returned a chainable no-op for every
-- unmodelled key instead, and that was wrong in a way that mattered: it made
-- `row.Box` truthy on a row that has no Box, so `if row.Box and row.Get then`
-- passed and the harness reported a fault the game would never see. A field READ
-- and a method CALL are indistinguishable at the point of indexing, so the only
-- honest default is the one the real API has.
--
-- Methods are instead no-opped by NAME, harvested from the addon's own source
-- below, so calling one is fine while reading a field that does not exist is
-- nil - which is the distinction the game actually draws.
local Widget = {}
Widget.__index = Widget

local function NewWidget(kind, parent)
    local o = {
        __kind = kind,
        __parent = parent,
        __w = 0, __h = 0,
        __points = {},
        __scripts = {},
        __shown = true,
        __level = parent and (parent.__level or 0) + 1 or 0,
        __text = "",
        __children = {},
    }
    if parent and parent.__children then
        parent.__children[#parent.__children + 1] = o
    end
    return setmetatable(o, Widget)
end

function Widget:SetSize(w, h)
    assert(type(w) == "number", self.__kind .. ":SetSize got " .. tostring(w))
    assert(type(h) == "number", self.__kind .. ":SetSize got " .. tostring(h))
    self.__w, self.__h = w, h
end
function Widget:SetWidth(w)
    assert(type(w) == "number", self.__kind .. ":SetWidth got " .. tostring(w))
    self.__w = w
end
function Widget:SetHeight(h)
    assert(type(h) == "number", self.__kind .. ":SetHeight got " .. tostring(h))
    self.__h = h
end
function Widget:GetWidth() return self.__w end
function Widget:GetHeight() return self.__h end
function Widget:GetSize() return self.__w, self.__h end
function Widget:GetEffectiveScale() return 1 end
function Widget:GetFrameLevel() return self.__level end
function Widget:SetFrameLevel(n) self.__level = n end
function Widget:GetFrameStrata() return self.__strata or "MEDIUM" end
function Widget:SetFrameStrata(s) self.__strata = s end
function Widget:GetName() return self.__name end

function Widget:SetPoint(...)
    local n = select("#", ...)
    assert(n >= 1, "SetPoint with no arguments")
    for i = 1, n do
        local v = select(i, ...)
        assert(v ~= nil, self.__kind .. ":SetPoint got a nil argument at " .. i)
    end
    self.__points[#self.__points + 1] = { ... }
    -- Two opposite anchors define a rectangle; approximate the resulting width
    -- from the parent so bounded labels have something plausible to measure.
    if self.__parent and self.__w == 0 then
        self.__w = math.max(0, (self.__parent.__w or 0) - 24)
    end
end
function Widget:ClearAllPoints() self.__points = {} end
function Widget:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function Widget:SetAllPoints(other)
    other = other or self.__parent
    if other then self.__w, self.__h = other.__w, other.__h end
end

function Widget:Show() self.__shown = true end
function Widget:Hide() self.__shown = false end
function Widget:IsShown() return self.__shown end
function Widget:IsVisible() return self.__shown end
function Widget:SetShown(v) self.__shown = v and true or false end
function Widget:IsMouseOver() return false end

function Widget:SetScript(name, fn) self.__scripts[name] = fn end
function Widget:GetScript(name) return self.__scripts[name] end
function Widget:HookScript(name, fn)
    local prev = self.__scripts[name]
    if prev then
        self.__scripts[name] = function(...) prev(...) fn(...) end
    else
        self.__scripts[name] = fn
    end
end
function Widget:Fire(name, ...)
    local fn = self.__scripts[name]
    if fn then return fn(self, ...) end
end

function Widget:SetText(t) self.__text = t == nil and "" or tostring(t) end
function Widget:GetText() return self.__text end
function Widget:GetStringWidth() return #tostring(self.__text) * 6 end
function Widget:GetStringHeight() return 12 end
function Widget:HasFocus() return false end
function Widget:GetChecked() return self.__checked end
function Widget:SetChecked(v) self.__checked = v end

function Widget:CreateTexture(name, layer)
    local t = NewWidget("Texture", self)
    t.__name = name
    t.__layer = layer
    return t
end
function Widget:CreateMaskTexture()
    return NewWidget("MaskTexture", self)
end
function Widget:CreateFontString(name, layer)
    local fs = NewWidget("FontString", self)
    fs.__name = name
    fs.__layer = layer
    return fs
end
function Widget:SetTexture(path) return path ~= nil end
function Widget:GetFont() return "Fonts\\FRIZQT__.TTF", self.__fontSize or 12, "" end
function Widget:SetFont(_, s) self.__fontSize = s end

-- Slider
function Widget:SetMinMaxValues(lo, hi) self.__min, self.__max = lo, hi end
function Widget:GetValue() return self.__value or 0 end
function Widget:SetValue(v)
    assert(type(v) == "number", "SetValue got " .. tostring(v))
    self.__value = v
    self:Fire("OnValueChanged", v)
end

-- ColorSelect
function Widget:GetColorRGB() return self.__r or 1, self.__g or 1, self.__b or 1 end
function Widget:SetColorRGB(r, g, b)
    self.__r, self.__g, self.__b = r, g, b
    self:Fire("OnColorSelect")
end
function Widget:GetColorAlpha() return self.__a or 1 end
function Widget:SetColorAlpha(a) self.__a = a end

-- Every ENGINE method the addon calls on a widget, no-opped unless modelled
-- above.
--
-- Harvested from the source rather than hand-listed, so the harness cannot drift
-- behind the code it is testing. Method-name typos are NOT this harness's job -
-- Test-WowAddon.ps1 -StrictMethods checks every call site against the real API.
--
-- Methods the addon DEFINES on its own widgets are subtracted, and that
-- subtraction is the whole correctness of this function. `page:Refresh()` and
-- `row:Refresh()` appear as call sites, so without it `Refresh` would be
-- installed on the shared metatable and `if row.Refresh then` would be true for
-- every row - including the ones that have no Refresh, which is precisely the
-- branch the addon relies on being false. The harness would then exercise a code
-- path the game never takes, in both directions: reporting faults that cannot
-- happen and skipping the guard that stops them.
local function RegisterNoOps(sources)
    local callSites, defined = {}, {}

    for _, path in ipairs(sources) do
        local handle = assert(io.open(path, "r"))
        local text = handle:read("*a")
        handle:close()

        for name in text:gmatch("[:%.]([A-Za-z_][%w_]*)%s*%(") do
            callSites[name] = true
        end
        -- `function obj:Name(` and `function obj.Name(` - the addon's own.
        for name in text:gmatch("function%s+[%w_%.]+[:%.]([A-Za-z_][%w_]*)%s*%(") do
            defined[name] = true
        end
        -- `obj.Name = function(` - the same thing written the other way.
        for name in text:gmatch("[:%.]([A-Za-z_][%w_]*)%s*=%s*function%s*%(") do
            defined[name] = true
        end
    end

    for name in pairs(callSites) do
        if not defined[name] and not rawget(Widget, name) then
            Widget[name] = function(obj, ...)
                local key = (obj and obj.__kind or "?") .. ":" .. name
                unknown[key] = (unknown[key] or 0) + 1
                return obj
            end
        end
    end
end

-- ---------------------------------------------------------------------
-- Globals
-- ---------------------------------------------------------------------

local frameTypes = {
    Frame = true, Button = true, EditBox = true, Slider = true,
    ColorSelect = true, StatusBar = true, CheckButton = true,
}

-- Installed through _G in one loop rather than as thirty bare global
-- assignments.
--
-- Not style: Test-WowAddon.ps1 recurses over every .lua under the addon folder
-- and has no exclude, so this harness gets linted as if it were addon code. Each
-- `CreateFrame = ...` at file scope is reported as a stray global, and thirty of
-- those permanently bury the two or three warnings that would actually matter.
-- Assigning through _G keeps the stubs out of the bytecode's global-write set.
local stubs = {}

local UIParent = NewWidget("Frame")
UIParent.__w, UIParent.__h = 1920, 1080
UIParent.__name = "UIParent"
stubs.UIParent = UIParent

local WorldFrame = NewWidget("Frame")
WorldFrame.__name = "WorldFrame"
stubs.WorldFrame = WorldFrame

local frameTypes = {
    Frame = true, Button = true, EditBox = true, Slider = true,
    ColorSelect = true, StatusBar = true, CheckButton = true,
}

local createdFrames = {}

stubs.CreateFrame = function(kind, name, parent, template)
    assert(frameTypes[kind], "CreateFrame with unmodelled type " .. tostring(kind))
    local f = NewWidget(kind, parent)
    f.__name = name
    if name then _G[name] = f end
    createdFrames[#createdFrames + 1] = f
    return f
end

stubs.CreateFont = function(name)
    local f = NewWidget("Font")
    f.__name = name
    return f
end

stubs.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end

stubs.GetPhysicalScreenSize = function() return 2560, 1440 end
stubs.InCombatLockdown = function() return false end
stubs.strtrim = function(str) return (tostring(str):gsub("^%s+", ""):gsub("%s+$", "")) end
stubs.tinsert = function(t, v) t[#t + 1] = v end

local function CopyTableStub(t)
    local c = {}
    for k, v in pairs(t) do c[k] = type(v) == "table" and CopyTableStub(v) or v end
    return c
end
stubs.CopyTable = CopyTableStub

stubs.UISpecialFrames = {}
stubs.STANDARD_TEXT_FONT = [[Fonts\FRIZQT__.TTF]]
stubs.Enum = { UITextureSliceMode = { Stretched = 0, Tiled = 1 } }

-- Coalesced deferred work. C_Timer.After(delay, fn) is called with a dot, not a
-- colon, so the delay really is the first argument.
local timerQueue = {}
stubs.C_Timer = { After = function(_, fn) timerQueue[#timerQueue + 1] = fn end }

stubs.C_System = { GetFrameStack = function() return {} end }
stubs.C_AddOns = {
    GetAddOnMetadata = function(_, key) return key == "Version" and "2.3.0" or nil end,
}

stubs.GameTooltip = NewWidget("Frame")

stubs.Settings = {
    RegisterCanvasLayoutCategory = function(_, name) return { name = name } end,
    RegisterAddOnCategory = function() end,
}
stubs.SettingsPanel = false
stubs.HideUIPanel = function() end

local colorPickerStub = NewWidget("Frame")
colorPickerStub.SetupColorPickerAndShow = function() end
stubs.ColorPickerFrame = colorPickerStub

local addOnLoadedCallbacks = {}
stubs.EventUtil = {
    ContinueOnAddOnLoaded = function(_, fn)
        addOnLoadedCallbacks[#addOnLoadedCallbacks + 1] = fn
    end,
}

stubs.GetCVar = function() return "400" end
stubs.GetNetStats = function() return 0, 0, 42, 51 end
stubs.UnitCastingInfo = function() return nil end
stubs.UnitChannelInfo = function() return nil end
stubs.GetUnitEmpowerHoldAtMaxTime = function() return 0 end
stubs.GetTime = function() return 1000 end
stubs.SlashCmdList = {}

for name, value in pairs(stubs) do
    -- `false` is how a nil-valued stub is spelled above, since pairs skips nil.
    _G[name] = (value ~= false) and value or nil
end

-- ---------------------------------------------------------------------
-- Load
-- ---------------------------------------------------------------------

local files = {
    "CastQueueOverlayPixel.lua",
    "CastQueueOverlayStyle.lua",
    "CastQueueOverlayLayout.lua",
    "CastQueueOverlayOptions.lua",
    "CastQueueOverlay.lua",
}

local root = arg[0]:match("^(.*)[/\\]dev[/\\][^/\\]+$") or "."

do
    local paths = {}
    for i, file in ipairs(files) do paths[i] = root .. "/" .. file end
    RegisterNoOps(paths)
end

for _, file in ipairs(files) do
    local chunk, err = loadfile(root .. "/" .. file)
    assert(chunk, "load " .. file .. ": " .. tostring(err))
    local ok, runErr = pcall(chunk, "CastQueueOverlay")
    assert(ok, "run " .. file .. ": " .. tostring(runErr))
    print("  loaded " .. file)
end

-- ---------------------------------------------------------------------
-- Exercise
-- ---------------------------------------------------------------------

local addon = assert(CastQueueOverlay, "the addon namespace was never created")

-- Saved variables are restored between file load and ADDON_LOADED.
CastQueueOverlayDB = {}
for _, fn in ipairs(addOnLoadedCallbacks) do fn() end
assert(CastQueueOverlayDB.overlays, "defaults were not merged")
assert(CastQueueOverlayDB.windows, "the windows table is missing from defaults")
print("  defaults merged")

-- The first /cqo: build the window and show it.
addon.ShowOptions()
local win = _G.CastQueueOverlayOptionsFrame
assert(win, "the options window was never created")
win:Fire("OnShow")
print(("  window built: %dx%d"):format(win:GetWidth(), win:GetHeight()))
assert(win:GetHeight() > 200, "window height was not taken from the cursor")

-- Every tab, and every refresh path behind them.
for _, key in ipairs(addon.OVERLAY_KEYS) do
    addon.OnColorChangedExternally()
    win:Fire("OnShow")
end
print("  all tabs refreshed")

-- Press everything.
--
-- Rather than hunting for one button by shape, every clickable built inside the
-- options window is fired: the swatches (which build the colour picker), the
-- toggle rows, Apply, and Select frame - which arms the frame picker, installs
-- the WorldFrame hook and grabs the keyboard, then disarms on the second press.
--
-- The window's own Close is skipped, because a hidden window stops being a
-- useful thing to keep clicking.
local function Clickables()
    local out = {}
    for _, f in ipairs(createdFrames) do
        if f ~= win.Close and (f.__scripts.OnClick or f.__scripts.OnMouseUp) then
            out[#out + 1] = f
        end
    end
    return out
end

local pressed = 0
local function Press(pass)
    for _, f in ipairs(Clickables()) do
        if f.__scripts.OnClick then
            local ok, err = pcall(f.__scripts.OnClick, f, "LeftButton")
            assert(ok, ("OnClick on a %s (pass %d): %s"):format(f.__kind, pass, tostring(err)))
            pressed = pressed + 1
        end
        if f.__scripts.OnMouseUp then
            local ok, err = pcall(f.__scripts.OnMouseUp, f, "LeftButton")
            assert(ok, ("OnMouseUp on a %s (pass %d): %s"):format(f.__kind, pass, tostring(err)))
            pressed = pressed + 1
        end
    end
end

-- ONE pass first, and the keyboard test goes between the two.
--
-- Select frame toggles: an even number of presses leaves the picker disarmed and
-- ReleaseKeyboard has already cleared OnKeyDown, so testing the keys after two
-- passes silently tests nothing. Odd, then keys, then even.
Press(1)

-- The frame picker's keyboard grab, on the window itself, while it is armed.
assert(win.__scripts.OnKeyDown,
    "the frame picker did not grab the keyboard, so TAB and Escape went untested")
-- ESCAPE goes LAST, and that ordering is an assertion in itself: cancelling the
-- picker runs StopSelecting, which clears OnKeyDown, so any key tested after it
-- would be calling a nil handler. Cycle and pass-through first, then cancel.
for _, key in ipairs({ "TAB", "W", "ESCAPE" }) do
    local handler = win.__scripts.OnKeyDown
    assert(handler, "OnKeyDown was cleared before " .. key .. " could be tested")
    local ok, err = pcall(handler, win, key)
    assert(ok, "OnKeyDown " .. key .. ": " .. tostring(err))
end
assert(win.__scripts.OnKeyDown == nil,
    "Escape did not release the keyboard - the picker would keep eating keys "
    .. "over a window that is no longer picking")
print("  frame picker handled TAB and a pass-through key, and Escape released it")

Press(2)
print(("  %d click handlers fired over two passes"):format(pressed))

local colorPicker = _G.CastQueueOverlayColorPickerFrame
assert(colorPicker, "the colour picker window was never built")
assert(colorPicker:GetHeight() > 200, "picker height was not taken from the cursor")
print(("  colour picker built: %dx%d"):format(colorPicker:GetWidth(), colorPicker:GetHeight()))

-- The hex field, and the wheel behind it.
local hexEdit
for _, f in ipairs(createdFrames) do
    if f.__kind == "EditBox" and f.__scripts.OnEnterPressed then hexEdit = hexEdit or f end
end
assert(hexEdit, "no edit box accepted Enter")

-- Combat starting and ending while the window is open.
for _, f in ipairs(createdFrames) do
    if f.__scripts.OnEvent then
        for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
            local ok, err = pcall(f.__scripts.OnEvent, f, event)
            assert(ok, event .. ": " .. tostring(err))
        end
    end
end
print("  combat entered and left")

addon.OnCastBarChanged("ERB_CastBar")

-- Deferred measurement, which is where truncation checks and border re-snaps run.
local pending = timerQueue
timerQueue = {}
for _, fn in ipairs(pending) do
    local ok, err = pcall(fn)
    assert(ok, "deferred pass: " .. tostring(err))
end
print(("  %d deferred callbacks flushed"):format(#pending))

-- Closing must tear the picker down.
win:Fire("OnHide")
addon.ToggleOptions()
addon.ToggleOptions()
print("  open/close cycled")

-- ---------------------------------------------------------------------
-- Report
-- ---------------------------------------------------------------------

local names = {}
for name in pairs(unknown) do names[#names + 1] = name end
table.sort(names)
if #names > 0 then
    print("\n  unmodelled methods (no-ops in this harness):")
    for _, name in ipairs(names) do
        print(("    %-46s x%d"):format(name, unknown[name]))
    end
end

print("\nPASSED")
