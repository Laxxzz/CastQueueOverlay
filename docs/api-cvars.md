# CVar APIs
Source: https://warcraft.wiki.gg/wiki/API_GetCVar  
Source: https://warcraft.wiki.gg/wiki/SpellQueueWindow  
Last fetched: 2026-07-27 (Interface 120007, The War Within)

---

## GetCVar

Returns the value of a console variable (CVar).

```lua
value = GetCVar(name)
```

### Arguments
- `name` — string, the CVar name (case-insensitive)

### Returns
- `value` — string, the current value of the CVar, or nil if not found.

> **Always returns a string**, even for numeric CVars. Use `tonumber()` when you need a number.

---

## SpellQueueWindow

The `SpellQueueWindow` CVar controls how many milliseconds before the end of a cast/GCD the game will accept and queue the next spell input.

```lua
local queueWindowMS = tonumber(GetCVar("SpellQueueWindow")) or 0
```

### Details
- **Units:** milliseconds (ms)
- **Default:** 400ms
- **Range:** typically 0–400ms (user-configurable)
- The value represents how far from the end of a cast a new spell can be queued.
- A larger value = the "queue zone" starts earlier in the cast = larger overlay on the cast bar.

### Related CVar Event
When the user changes `SpellQueueWindow`, the event `CVAR_UPDATE` fires with:
```lua
-- event args: variableName, value
-- variableName will be "SpellQueueWindow" (exact string, case-sensitive in the event payload)
```

Use this to refresh the overlay after the player adjusts their queue window in settings.
