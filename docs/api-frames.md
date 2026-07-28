# Frame / Widget APIs
Source: https://warcraft.wiki.gg/wiki/Widget_API  
Last fetched: 2026-07-27 (Interface 120007, The War Within)

---

## GetMouseFoci (TWW / Retail)

Returns a list of all frames currently under the mouse cursor.

```lua
local foci = GetMouseFoci()  -- returns a table (array) of frames
```

> ⚠️ **TWW-era API.** This replaced the old `GetMouseFocus()` (singular) which returned only one frame.
> `GetMouseFoci()` (plural) returns a **table**, not a single frame.

```lua
-- Correct pattern:
local foci = GetMouseFoci()
for _, frame in ipairs(foci) do
    -- frame is a widget reference
end

-- WRONG — old API, removed:
-- local f = GetMouseFocus()
```

---

## Frame:GetRect()

Returns the absolute screen coordinates and dimensions of a frame.

```lua
local left, bottom, width, height = frame:GetRect()
```

- Returns coordinates in **screen pixels**, relative to the bottom-left of the screen.
- `left` — x position of the left edge.
- `bottom` — y position of the bottom edge.
- `width`, `height` — dimensions in pixels.
- Returns `nil` for all values if the frame has no valid size/position (e.g. not yet laid out).

> Useful for positioning one frame to exactly overlap another when they have different parents or strata. Use `UIParent` as the anchor:
> ```lua
> highlight:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
> highlight:SetSize(width, height)
> ```

---

## CreateTexture

Creates a texture layer on a frame.

```lua
local tex = frame:CreateTexture(name, layer, inheritsFrom, sublevel)
```

- `name` — string global name, or `nil` for anonymous.
- `layer` — draw layer: `"BACKGROUND"`, `"BORDER"`, `"ARTWORK"`, `"OVERLAY"`, `"HIGHLIGHT"`.
- `inheritsFrom` — optional template name.
- `sublevel` — optional integer (-8 to 7) for ordering within the layer.

### SetColorTexture
```lua
tex:SetColorTexture(r, g, b, a)  -- solid color fill, all values 0-1
```

### SetVertexColor (swatch tinting)
```lua
tex:SetVertexColor(r, g, b, a)   -- tints a texture by multiplying its RGBA values
```

---

## BackdropTemplate

Used to give a frame a background/border.

```lua
local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
f:SetBackdrop({
    bgFile   = "Interface/Buttons/WHITE8x8",   -- solid background
    edgeFile = "Interface/Buttons/WHITE8x8",   -- solid border
    edgeSize = 1,
})
f:SetBackdropColor(r, g, b, a)         -- background color
f:SetBackdropBorderColor(r, g, b, a)   -- border color
```

> ⚠️ `"BackdropTemplate"` must be included in `CreateFrame`'s 4th argument. Frames without it will error when you call `SetBackdrop`.

---

## Frame:HookScript

Adds an additional handler to a script without replacing the original.

```lua
frame:HookScript("OnSizeChanged", function(self, width, height)
    -- called after the original OnSizeChanged handler
end)
```

Safe to use on Blizzard frames where you don't own the original script.
