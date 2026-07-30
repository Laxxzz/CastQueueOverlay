# Changelog

## 2.2.0

- Channelled casts now draw the overlays at the **left** end of the bar, which is
  where a channel finishes. They previously sat on the right, marking the moment
  the channel started.
- Empowered casts keep the right-hand end. They arrive on the channel events but
  fill left to right like a normal cast.
- New **Channeling Opacity** option: a separate opacity applied only while
  channelling, because a channel starts with the bar full and the overlay begins
  underneath the fill. Off by default.

## 2.1.0

- Colour picker restyled to match the options window, with an editable hex field
  and a live opacity readout. Blizzard's shared colour picker is left untouched,
  so other addons are unaffected.
- CurseForge project ID added to the `.toc`, so manual installs are recognised
  for updates.
- Closing the options window now also closes the colour picker.

## 2.0.0

- Options moved out of Blizzard's Settings UI into a standalone window. The old
  route could not open during combat.
- One overlay became three, each independently toggleable with its own colour and
  opacity: spell queue window, latency, and a custom millisecond value.
- Overlays draw stacked, widest underneath, so none hides another.
- Frame picker shows the frame under the cursor live, cycles overlapping frames
  with TAB, and finds cast bars that disable mouse input.
- Third-party cast bars created after login are now bound correctly instead of
  silently falling back to Blizzard's bar.
- `/cqo` in combat defers and opens when combat ends.
- Existing settings migrate automatically.
