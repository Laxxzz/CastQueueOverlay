# ColorPickerFrame API
Source: https://warcraft.wiki.gg/wiki/ColorPickerFrame  
Last fetched: 2026-07-27 (Interface 120007, The War Within)

---

## ColorPickerFrame (TWW / Retail Modern API)

The color picker was refactored in **Patch 10.0**. The old API using separate `swatchFunc`, `opacityFunc`, and `cancelFunc` set as direct frame properties is **deprecated and removed**.

### ✅ Correct TWW-era usage (10.0+)

```lua
ColorPickerFrame:SetupColorPickerAndShow({
    swatchFunc  = mySwatchFunc,    -- called while color/opacity is changing
    opacityFunc = mySwatchFunc,    -- called while opacity slider changes (can be same as swatchFunc)
    cancelFunc  = myCancelFunc,    -- called if the user clicks Cancel
    hasOpacity  = true,            -- show the opacity/alpha slider
    opacity     = currentAlpha,    -- initial opacity value (0–1, where 0=transparent, 1=opaque)
    r = currentR,
    g = currentG,
    b = currentB,
})
```

### Getting current color/opacity inside swatchFunc
```lua
local function OnColorChanged()
    local r, g, b = ColorPickerFrame:GetColorRGB()
    local a = ColorPickerFrame:GetColorAlpha()  -- returns 0 (transparent) to 1 (opaque)
    -- apply r, g, b, a
end
```

### cancelFunc signature
The `cancelFunc` receives a table of the **previous** color values when the picker was opened:
```lua
cancelFunc = function(previousValues)
    if previousValues then
        local r = previousValues.r
        local g = previousValues.g
        local b = previousValues.b
        local a = previousValues.opacity  -- NOTE: key is "opacity", not "a"
    end
end
```

### ⚠️ Important notes
- `GetColorAlpha()` returns `0` = fully transparent, `1` = fully opaque.  
  This is the **opposite** of WoW's normal alpha convention in some older APIs where 0 = opaque.
- The `opacity` key in `previousValues` is named `opacity`, NOT `a` or `alpha`.
- Do **not** set `ColorPickerFrame.swatchFunc`, `ColorPickerFrame.opacityFunc`, or  
  `ColorPickerFrame.cancelFunc` directly — that's the pre-10.0 pattern and no longer works.
- Do **not** call `ColorPickerFrame:Show()` directly — use `SetupColorPickerAndShow`.
