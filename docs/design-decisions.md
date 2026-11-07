# Critical Design Decisions — Do NOT "Fix" These

Moved out of `CLAUDE.md`, which keeps a one-line index. Numbers are cited from code
comments (`decision #18`); never renumber.

1. **Load order:** `CastQueueOverlayOptions.lua` loads before `CastQueueOverlay.lua` in the TOC.
   **Both files must repeat `CastQueueOverlay = CastQueueOverlay or {}` before taking a local
   reference.** `local addon = CastQueueOverlay` captures the value *at that instant*; a guard
   only in the second-loading file leaves the first capturing `nil`, which throws at its first
   `function addon.X()` and aborts the rest of that file (the options panel never registered,
   `/cqo` opened nothing).

   **In every file, no `addon.X` of any kind above the namespace capture.** Constants that
   "belong" beside `defaults` go below it. Indexing the nil global aborts the file at load,
   taking the slash command, the event handler and every public function with it; the tell in
   the error's locals is `addon=<table>{ Style=<table> }` (only what the style file put there).
   `Test-WowAddon.ps1` does NOT catch this — its namespace check looks for an unguarded
   capture, not use-before-capture.

2. **The frame picker uses `C_System.GetFrameStack()`, NOT `GetMouseFoci()`.** `GetMouseFoci`
   is the correct plural TWW API (`GetMouseFocus` is gone; iterate with `ipairs`) but it only
   reports regions with **mouse input enabled**. Cast bars and most display-only frames call
   `EnableMouse(false)`, so it resolves to `WorldFrame` across most of the screen.
   `C_System.GetFrameStack()` returns every region under the cursor regardless of mouse state
   and is what Blizzard's own `/framestack` is built on (`SlashCommands.lua:1350`).

3. **`WorldFrame:SetScript("OnMouseDown", ...)` hook** for click detection in the frame picker
   — deliberate. A full-screen catch frame would block mouse events; the WorldFrame hook fires
   for world/background clicks without blocking UI frames.

4. **`Settings.OpenToCategory` takes a NUMBER and is called ONCE.** Pass `category:GetID()`.
   Never pass the category table (`Settings.OpenToCategory` forwards straight to
   `C_SettingsUtil.OpenSettingsPanel(openToCategoryID)`, typed `number`,
   `Blizzard_Settings.lua:143`; a table raises). Never assign `category.ID`
   (`SettingsCategoryMixin:Init` assigns `self.ID = idCounter()`, a number the registry uses,
   `Blizzard_Category.lua:8-14`; overwriting it orphans the category). There is no
   "call it twice" quirk — that was inferred from a call that always threw. If a second call
   is ever genuinely needed, record it only after seeing it with the correct ID.

   - A throw inside a slash handler looks like **Enter doing nothing in chat**: the chat box
     calls slash handlers unprotected and `self:ClearChat()` is the next line
     (`ChatFrameEditBox.lua:259-262`), so the edit box keeps its text and stays open.
   - The pre-10.0 `InterfaceOptionsFrame_OpenToCategory` fallback was **removed** (zero
     references in the generated docs and Blizzard's UI source at 12.1.0). That branch prints
     a diagnostic instead.
   - **`/cqo` takes no arguments.** The colour/alpha passthrough was removed 2026-07-28; the
     panel is the only configuration surface. `addon.OnColorChangedExternally` is
     consequently uncalled — a documented extension point, not dead code to prune.
   - **`/cqo` no longer touches `Settings.OpenToCategory` at all.**
     `C_SettingsUtil.OpenSettingsPanel` is **protected** (`HasRestrictions = true`), so
     opening the panel in combat produced `[ADDON_ACTION_BLOCKED] ... 'OpenSettingsPanel()'`
     with no workaround. The options are a standalone frame (decision #11). The Settings entry
     that remains is a stub button and must stay one; wiring it back to `OpenToCategory`
     re-introduces the combat block.

5. **`startTimeMs`/`endTimeMs` stay in milliseconds** — both `UnitCastingInfo` and
   `UnitChannelInfo` return ms, and the overlay calculation divides ms/ms. Do not convert to
   seconds.

6. **`ColorPickerFrame:SetupColorPickerAndShow({...})`** — TWW-era API (10.0+). Do not use
   the old `ColorPickerFrame.swatchFunc` property pattern. Verified in use by Blizzard at
   `Blizzard_SettingControls.lua:802` and `FloatingChatFrame.lua:482`.
   - **Alpha goes in as `opacity` and comes back as `a`.** `ColorPickerFrame.lua` builds
     `previousValues = {r=, g=, b=, a=info.opacity}` and calls `cancelFunc(previousValues)`.
     Reading `prev.opacity` is always nil (Cancel then restores RGB but not alpha).
   - `c = CastQueueOverlayDB` is a live reference, not a snapshot; capture the restore point
     by value before opening the picker.

7. **The overlay anchors to the end the cast FINISHES at, which is not always the right
   edge.** Normal casts fill left→right (`value = GetTime() - startTime`,
   `CastingBarFrame.lua:446`) and finish at the **right**. Channels drain right→left
   (`value = endTime - GetTime()`, `:448` and `:169`) and finish at the **left**; anchoring
   right for a channel marks the moment it *started*.
   - **Empowered casts make this three-way, not two.** They arrive on the CHANNEL/EMPOWER
     events but Blizzard fills them like a cast (`isChargeSpell`, `:445-446`), so they keep
     the right anchor. Ask "which way does it fill", never "is it a channel".
   - EllesmereUIResourceBars computes channels identically (`(endTime - now) / duration`,
     `EllesmereUIResourceBars.lua:6951`), so this holds for third-party bars following the
     same convention. A bar that fills channels forward would need this inverted; there is
     no option for that.

8. **Empowered casts are channels, and their duration is *not* `endTimeMs - startTimeMs`.**
   `UNIT_SPELLCAST_EMPOWER_START/_UPDATE/_STOP` route through the `CHANNEL_*` code path and
   are read with `UnitChannelInfo` (Blizzard's structure at `CastingBarFrame.lua:418` and
   `:487`). When `numEmpowerStages > 0`, the drawn bar runs past `endTimeMs` by
   `GetUnitEmpowerHoldAtMaxTime(unit)` (`CastingBarFrame.lua:429-431`), so the overlay adds
   the same hold window. The EMPOWER events must stay registered (without them Evoker
   empowers get no overlay at all).

9. **`CVAR_UPDATE` is filtered on arg1, case-insensitively** (via `strlower`). The event
   fires for every CVar the client touches; Blizzard filters the same way
   (`QuestMapFrame.lua:580`, `ArtifactBar.lua:70`). The event's casing is not guaranteed to
   match the string passed to `GetCVar`, and an exact-case compare that never matches looks
   identical to "no CVar changed".

10. **`ResolveCastBar()` must NOT fall back to the Blizzard bar when a frame name is
    configured, and `castBar` must never be cached as a one-time answer.** Third-party cast
    bars are created **lazily, after our `PLAYER_LOGIN`**: EllesmereUIResourceBars builds
    `ERB_CastBar` only when its cast bar module runs (`EllesmereUIResourceBars.lua:6238`) and
    calls `EllesmereUI.SetPlayerCastBarSuppressed(...)` in the same function, hiding
    `PlayerCastingBarFrame`. Resolving `_G["ERB_CastBar"]` → nil at login and falling back
    painted the overlay on a hidden frame all session ("reapply after every reload" was the
    apparent workaround).
    - **A configured name has no substitute** — return nil and retry; attaching to a different
      bar is worse than attaching to nothing.
    - **`EnsureOverlay` re-resolves every call** and rebuilds when `castBar ~= want` (also
      handles a bar destroyed and recreated under the same global name).
    - A bounded `C_Timer.NewTicker` (0.5s × 40) covers the window between our login and the
      other addon's bar appearing, and prints a diagnostic if it never does. Cancel via the
      captured upvalue, not a callback argument — Blizzard always drives tickers that way
      (`TutorialRangeManager.lua:116-120`); the argument form is unverified.

11. **The options window is a standalone frame, and every close path must tear the picker
    down.** Not a Settings canvas panel because `OpenSettingsPanel` is protected (no combat
    open, decision #4) and a Settings canvas cannot be styled (inherits Blizzard's chrome).
    `win:SetScript("OnHide", ...)` calling `StopSelecting` is **load-bearing**: closing the
    window while the picker is armed otherwise leaves `isSelecting` true — the outline keeps
    tracking the cursor, Escape does nothing (keyboard grab went with the frame), clicks do
    nothing (WorldFrame hook still installed with no panel to respond). Any new way to dismiss
    this window inherits that requirement.

12. **Styling uses flat `SetColorTexture` rectangles, never `BackdropTemplate`.** Backdrops
    bring gold bevels and tiled parchment. Borders are four textures so they stay hairline at
    any size. Fonts are custom `CreateFont` objects — the `GameFont*` globals carry Blizzard's
    gold and shadowing. Palette lives in one table in `CastQueueOverlayStyle.lua` with hex
    values in comments; add colours there, not inline.
    - The palette is SimpleLootCouncil's current one (since 2026-11-07), hue-rotated to this
      addon's orange #E0873A: a flat near-black canvas with a slight warm cast, raised
      controls, black-at-alpha insets, white-at-alpha neutrals, ONE accent. The window's ground
      still falls from `canvasTop` to `canvasBottom`. The earlier blue-gradient / coral look
      is retired.
    - Fonts are URW Gothic (`fonts/`, licence `LICENSE-URW.txt`) with **no shadow**, as in SLC:
      all type sits on a flat dark panel. They are font FAMILIES (`CreateFontFamily`) so an
      EditBox draws Cyrillic and CJK.
    - Borders are no longer literally 1px — see decision #18.
    - **`CreateFont` names are GLOBAL.** This addon's and SimpleLootCouncil's must not collide;
      both prefix every font object with their own addon name. Two addons creating
      `MyFontBody` silently share one object.

12b. **One accent for state.** `S.color.accent` (#E0873A) marks a ticked checkbox, the filled
    part of a slider and its thumb, the active tab's underline, a focused edit box's border,
    the frame picker's outline, and the primary button's edge and ink. The old `on`/`onDim`
    names survive as aliases of `accent`/`accentDim` so call sites kept working. Primary
    buttons are SLC's outline treatment: accent edge and ink, a faint white wash on hover.
    - The slider's fill anchors to the THUMB's centre rather than being computed from the
      value, so it tracks what the engine did with the thumb, including the half-thumb inset
      at each end (a fraction-derived width is wrong at exactly the two positions checked
      first). `SetEnabled` greys the fill as well as the thumb.

13. **Three overlays, drawn widest-first by sublevel.** `queue` (SpellQueueWindow CVar),
    `latency` (`GetNetStats` home, falling back to world when home reads 0), and `custom`
    (a player-supplied ms value). Each independently enable-able; all three can be on. They
    share a right edge, so `ApplyOverlay` sorts the *visible* set by width descending and
    assigns increasing `SetDrawLayer("OVERLAY", i)` sublevels, reading as bands inward from
    the end of the bar. The sort is a total order — equal values fall back to key — because an
    unstable comparator would reshuffle z-order between frames. `OVERLAY_KEYS` exists because
    `pairs` order is not reproducible and the z-order must be.

14. **Saved-variable defaults merge recursively via `ApplyDefaults`** (the
    `reference/patterns.md` recipe), and a migration moves the pre-2026-07-28 flat `r/g/b/a` keys into
    `overlays.queue` before defaults are applied, so an upgrading user keeps their colour.
    `Test-WowAddon.ps1` reports a **false positive** WARN here (it greps for a literal
    `DB[k] == nil` or `pairs(defaults`). Do not "fix" it by reverting to an inline loop — that
    loses the nested merge the overlay sub-tables need.

15. **`/cqo` is refused in combat and queued for combat end.** Showing our own frame in combat
    is **legal** (`Frame:Show`/`Hide` carry `IsProtectedFunction` only in the sense that
    they are blocked on *protected* frames). What is
    genuinely blocked, even on our own frame, is `EnableKeyboard` and
    `SetPropagateKeyboardInput`, because they alter global keyboard routing
    (`[ADDON_ACTION_BLOCKED] ... 'CastQueueOverlayOptionsFrame:SetPropagateKeyboardInput()'`).
    So the frame picker is the problem, not the window; blocking the whole window is a
    deliberate simplification — if revisited, only the picker needs gating.
    - Three parts, all needed: `/cqo` defers via `PLAYER_REGEN_ENABLED`; the picker refuses to
      start in combat; combat starting mid-pick stops the picker.
    - **`local pendingOptions = false` must be declared above the `OnEvent` handler that reads
      it.** Below it, the handler closes over the *global* `pendingOptions` while the slash
      command sets the local, and the deferred open never fires (invisible out of combat;
      shipped broken in 2.2.0 and earlier). Same family as #1: an upvalue must be declared
      above every closure that reads it; the linter's "assigns global" warning catches it.
    - **`ReleaseKeyboard`:** clearing the `OnKeyDown` script is *not* protected and is what
      actually stops us eating keys, so it runs unconditionally. Only the two protected calls
      are deferred to combat end. One combat check around the whole teardown would either leak
      a key handler or throw the error being avoided.

16. **Two `SetPoint` calls are only safe on OPPOSITE edges.** Every anchor supplies both an x
    and a y. `TOPLEFT` + `BOTTOMRIGHT`, or `LEFT` + `RIGHT`, define a rectangle (the title
    rule, hint text and picker highlight are built this way). `RIGHT` + `TOP`, or `TOPRIGHT`
    + `TOP`, over-constrain one axis and stretch or misplace the region (bit the "Enabled"
    label on the overlay tabs and the channelling opacity button). Vertical from one frame and
    horizontal from another is **one** anchor plus a deliberate offset, not two anchors.

17. **Channelling opacity is a separate, optional alpha applied only to draining channels.**
    A channel starts with the bar full, so the overlay sits *under* the fill exactly when it
    matters. `channelAlpha = { enabled, a }` overrides each overlay's own alpha for that case.
    Gated on `drainsLeft`, not on "is a channel" — an empowered cast fills left→right and must
    not be affected (decision #7).

18. **Every size, offset and border goes through `CastQueueOverlayPixel.lua`.** A 1px border
    is 1px only when one UI unit maps to one physical pixel; at any other effective scale one
    edge renders at 2px and the opposite edge vanishes (reported as "clipped at the bottom",
    nudged, then "clipped at the top").
    - `P.Size` and `P.Point` snap every numeric argument; `P.Crisp` defeats the engine's own
      texel snapping (which rounds in a different space); `S.Border` measures a hairline
      **per frame**, not from one global multiplier (wrong for a frame with its own scale).
    - **Re-snap when the ground moves.** Borders re-apply on `UI_SCALE_CHANGED`,
      `DISPLAY_SIZE_CHANGED` and `PLAYER_ENTERING_WORLD`. The effective scale does not settle
      in the frame a border is created in, so there are three chances: the coalesced
      post-layout flush, the first two `OnUpdate` ticks, then every scale change.
    - `GetEffectiveScale` carries `SecretReturnsForAspect = { Enum.SecretAspect.Scale }`. A
      secret in this arithmetic silently poisons every offset. `P.EffectiveScale` guards for
      it and pcalls the call itself, because the frame picker measures frames this addon does
      not own.

19. **Every builder returns the vertical space it consumed, and the window's height IS the
    cursor.** This is the one rule; if any of these is dropped, keep this one.
    `CastQueueOverlayOptions.lua` contains **no layout literals**. A page owns a cursor, calls
    `cursor:Add(builder, ...)`, and never learns or chooses a row's height. Whitespace goes
    through `cursor:Gap()` — a bare offset at a call site makes the cursor stop being the
    single source of truth. Never let a widget need caller cooperation to finish (a
    `h.Rule:SetPoint(...)` line the caller must remember renders zero-width or full-bleed with
    no error when forgotten), never let callers invent row heights, and never fix the window
    height as a constant with the footer pinned to the opposite edge.
    - **`Cursor:Add` forwards only `frame, height`.** A builder with more to hand back must
      hang it off the frame it returns. `L.TabStrip` exposes `.Tabs` for this;
      `local _, _, tabs = cursor:Add(L.TabStrip, ...)` reads a third return that is never
      forwarded, and the nil surfaces later as an index error inside `SelectTab`
      (`dev/test_ui.lua` caught it).

20. **A frame anchored by two corners has no width in the frame that created it.**
    `GetWidth()` answers for the layout as it currently stands. Anything stretched between two
    corners records the width it was built to have — `S.Window` sets `content.cqoWidth`, and
    `L.WidthOf` prefers the record over the measurement. The symptom is not an error: headings
    still draw (a one-point FontString is unbounded), every **row** collapses to zero width
    with crossed label offsets and renders nothing. Anything that genuinely must measure runs
    deferred through `P.AfterLayout`, coalesced into one `C_Timer.After(0)` for the whole
    queue and tolerant of nil holes (a page build registers dozens; one bad row must not
    unstyle the page).

21. **Rounding is for window surfaces only. Controls are square.** `S.Window` rounds via two
    nine-sliced 32x32 textures in `art/` whose shape lives in the alpha channel so they tint.
    `S.Button`, `S.Checkbox`, `S.Inset`, `S.Tab` and the colour swatch do not (the shape
    difference separates container from contents; at control sizes a button twice the radius
    tall reads as a pill).
    - **Nine-slicing is why it works:** corners draw at native size, only the straight edges
      stretch, so the radius is identical on a 460px window and a 22px control. A plainly
      stretched texture turns its corners into ellipses.
    - **The gradient is masked, not drawn onto the rounded texture** (nine quads = nine
      gradients with seams). Masking keeps it on one flat quad.
    - **The header band is clipped by the WINDOW's mask, not its own** (masks are positional;
      self-masking rounds the wrong corners).
    - `SetTexture` returns a success flag and the style file uses it: if the art fails to
      load, everything falls back to the flat path (a mask that fails to load masks
      **everything** — a blank window). `RADIUS` must match `dev/make_art.py`.
    - `*.tga binary` in `.gitattributes` is load-bearing. A line-ending filter corrupts a TGA
      quietly: `SetTexture` returns false and the corners silently go square.

22. **`dev/test_ui.lua` runs the UI offline.** `Test-WowAddon.ps1` proves the files parse and
    every API exists with the right arity; it cannot prove they **run** (an upvalue read
    before assignment, builder returns that do not line up with the cursor, a table indexed a
    frame too early — decisions #1 and #15 are that shape). The harness stubs the widget API,
    executes all five files, builds the window, fires every click handler twice, drives the
    frame picker's keyboard, and enters and leaves combat.
    - **An unknown key must read as `nil`**, as on a real widget. A chainable no-op for every
      unmodelled key makes `row.Box` truthy on a row with no Box, so
      `if row.Box and row.Get then` passes and the harness reports a fault the game cannot see.
    - **Methods the addon DEFINES on its own widgets must be subtracted** from the harvested
      no-op set. `page:Refresh()` is a call site; without the subtraction `Refresh` lands on
      the shared metatable and `if row.Refresh then` is true for every row.
    - A harness wrong in either direction is worse than none.
    - It must stay lint-clean: `Test-WowAddon.ps1` recurses over every `.lua` under the addon
      folder with no exclude. Stubs are installed through `_G` in a loop, not as thirty bare
      global assignments. Four warnings against it are permanent and correct: `io`, `arg`,
      `:read()` and `:close()` are standard Lua, outside the WoW API surface.
