# Cast Info APIs
Source: https://warcraft.wiki.gg/wiki/API_UnitCastingInfo  
Source: https://warcraft.wiki.gg/wiki/API_UnitChannelInfo  
Last fetched: 2026-07-27 (Interface 120007, The War Within)

---

## UnitCastingInfo

Returns information about the spell currently being **cast** (not channeled) by a unit.

```lua
name, displayName, textureID, startTimeMs, endTimeMs, isTradeskill, castID, notInterruptible, castingSpellID, castBarID, delayTimeMs = UnitCastingInfo(unit)
```

### Arguments
- `unit` — UnitToken (string), e.g. `"player"`, `"target"`

### Returns
| Return | Type | Description |
|---|---|---|
| `name` | string | Spell name, or **nil** if nothing is being cast |
| `displayName` | string | Name to display (same as name except "Channeling" for channels) |
| `textureID` | fileID (number) | Spell icon texture |
| `startTimeMs` | number | Cast start time in **milliseconds** (= GetTime() × 1000) |
| `endTimeMs` | number | Cast end time in **milliseconds** (= GetTime() × 1000) |
| `isTradeskill` | boolean | True if this is a tradeskill cast |
| `castID` | string (GUID) | Unique cast identifier, e.g. `Cast-3-3890-1159-21205-8936-00014B7E7F` |
| `notInterruptible` | boolean? | True if uninterruptible (nil in Classic BC) |
| `castingSpellID` | number | The spell's numeric ID |
| `castBarID` | number | Added in Patch 12.0.0 |
| `delayTimeMs` | number | Added in Patch 12.0.1 |

### Details
- Returns `nil` for `name` (and all subsequent values) if the unit is not casting.
- For channeled spells after the warm-up period, use `UnitChannelInfo` instead — `UnitCastingInfo` returns nothing during the channel itself.
- `startTimeMs` and `endTimeMs` are in **milliseconds**, not seconds. Divide by 1000 to compare with `GetTime()`.

### Related Events
`UNIT_SPELLCAST_START`, `UNIT_SPELLCAST_STOP`, `UNIT_SPELLCAST_DELAYED`, `UNIT_SPELLCAST_FAILED`, `UNIT_SPELLCAST_INTERRUPTED`

---

## UnitChannelInfo

Returns information about the spell currently being **channeled** by a unit.

```lua
name, displayName, textureID, startTimeMs, endTimeMs, isTradeskill, notInterruptible, spellID, isEmpowered, numEmpowerStages, castBarID = UnitChannelInfo(unit)
```

### Arguments
- `unit` — UnitToken (string), e.g. `"player"`, `"target"`

### Returns
| Return | Type | Description |
|---|---|---|
| `name` | string | Spell name, or **nil** if not channeling |
| `displayName` | string | Name to display |
| `textureID` | fileID (number) | Spell icon texture |
| `startTimeMs` | number | Channel start in **milliseconds** |
| `endTimeMs` | number | Channel end in **milliseconds** |
| `isTradeskill` | boolean | True if tradeskill |
| `notInterruptible` | boolean? | True if uninterruptible |
| `spellID` | number | The spell's numeric ID |
| `isEmpowered` | boolean | True for Evoker empowered spells |
| `numEmpowerStages` | number | Number of empower stages |
| `castBarID` | number | Added in Patch 12.0.0 |

### ⚠️ Key differences from UnitCastingInfo
- Return order is **different** — `notInterruptible` is at position 7 here (not position 8).
- No `castID` (GUID) return value.
- Has `spellID` (position 8) instead of `castingSpellID` (position 9 in UnitCastingInfo).
- Has `isEmpowered` and `numEmpowerStages` (no equivalent in UnitCastingInfo).
- `castBarID` is the **last** return here (position 11), unlike UnitCastingInfo (position 10).

### Related Events
`UNIT_SPELLCAST_CHANNEL_START`, `UNIT_SPELLCAST_CHANNEL_STOP`, `UNIT_SPELLCAST_CHANNEL_UPDATE`
