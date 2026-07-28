# Settings UI API
Source: https://warcraft.wiki.gg/wiki/Settings  
Last fetched: 2026-07-27 (Interface 120007, The War Within)

---

## Modern Settings API (10.0+ / TWW)

The old `InterfaceOptions_AddCategory` / `InterfaceOptionsFrame_OpenToCategory` system was **removed in Patch 10.0**. Use the new `Settings` API.

---

## Registering a Canvas (custom frame) category

Use this when your addon has a completely custom options panel (a `Frame` you built yourself):

```lua
-- panel is a Frame with panel.name set to the display name
local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
category.ID = ADDON_NAME   -- optional but useful for string-based lookups
Settings.RegisterAddOnCategory(category)
```

- `Settings.RegisterCanvasLayoutCategory(frame, displayName)` — registers the frame as a full-canvas options panel.
- `Settings.RegisterAddOnCategory(category)` — adds it to the AddOns section of the Settings UI.
- Store the returned `category` object globally if you need to open it via slash command.

---

## Opening the Settings panel

```lua
-- Preferred: use the category object directly (most reliable)
Settings.OpenToCategory(categoryObject)

-- Fallback: use string ID (less reliable, may need to be called twice)
Settings.OpenToCategory(ADDON_NAME)
```

> **Blizzard quirk:** `Settings.OpenToCategory` sometimes requires being called **twice** in succession for the panel to actually display on first open. This is a known engine behavior, not a bug in your code.

---

## ❌ Removed / Deprecated APIs (do NOT use)
```lua
-- REMOVED in 10.0 — do not use:
InterfaceOptions_AddCategory(panel)
InterfaceOptionsFrame_OpenToCategory(panel)
InterfaceOptionsFrame_OpenToCategory(ADDON_NAME)
```

---

## Slash command pattern for opening settings
```lua
-- Robust pattern used in this addon:
if CastQueueOverlayOptionsCategory and Settings and Settings.OpenToCategory then
    Settings.OpenToCategory(CastQueueOverlayOptionsCategory)
    Settings.OpenToCategory(CastQueueOverlayOptionsCategory)  -- called twice intentionally
elseif Settings and Settings.OpenToCategory then
    Settings.OpenToCategory(ADDON_NAME)
    Settings.OpenToCategory(ADDON_NAME)
end
```
