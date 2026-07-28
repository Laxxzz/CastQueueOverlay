# CastQueueOverlay

A World of Warcraft addon that shades the trailing end of your cast bar to show
time values you normally have to guess at — chiefly your **spell queue window**,
the slice at the end of a cast during which your next spell is already accepted.

Retail only. Built and tested against **12.0.7 (Midnight)**, `## Interface: 120007`.

![overlay concept](https://img.shields.io/badge/Interface-120007-D97757)

## What it draws

Three independent overlays, each a coloured band measured backwards from the end
of the bar. Any combination can be on at once.

| Overlay | Value |
|---|---|
| **SpellQueueWindow** | The `SpellQueueWindow` CVar, in milliseconds |
| **Latency** | Your home latency from `GetNetStats`, falling back to world latency |
| **Custom** | Any millisecond value you enter |

Each band is scaled against the duration of the cast currently in progress, so
the same 400ms window covers proportionally more of a fast cast than a slow one.

When several are enabled they are drawn stacked, widest underneath, so a wider
band never hides a narrower one.

## Usage

```
/cqo
```

Opens the options window. It has no arguments — everything is configured in the
window. There is also an entry in the standard AddOns settings list, which simply
opens the same window.

**In combat**, `/cqo` defers: it prints a message and opens the window once
combat ends. This is deliberate — the frame picker needs to grab the keyboard,
and that is blocked in combat.

## Cast bar support

Works with the default Blizzard cast bar out of the box, and with third-party
cast bars by frame name.

The **Select Frame** button starts a picker: hover any frame and its name is
shown live, `TAB` cycles through overlapping frames under the cursor, left click
selects, `Esc` cancels. The picker deliberately searches every region under the
cursor rather than only mouse-enabled ones, since most cast bars disable mouse
input.

Third-party bars are often created *after* login, so the addon keeps retrying to
bind to the frame you named for a short window after you log in, rather than
resolving once and silently falling back to Blizzard's bar.

Verified against EllesmereUI's `ERB_CastBar`.

## Installation

Copy the `CastQueueOverlay` folder into:

```
World of Warcraft/_retail_/Interface/AddOns/
```

Then `/reload` or restart the client.

## Development

This addon is linted with `Test-WowAddon.ps1` from a separate, private WoW API
reference toolkit — it parse-checks with LuaJIT (the same Lua 5.1 dialect the
game uses), validates the `.toc`, and resolves every API call against Blizzard's
generated 12.0.7 documentation. That toolkit is not part of this repository.

Linting is not testing — there is no way to execute addon code outside the game.
A clean lint means the syntax parses and every API referenced exists in the
12.0.7 documentation, nothing more.

`CLAUDE.md` documents the design decisions that are load-bearing and the bugs
that resulted from "fixing" them. Read it before changing initialisation order,
the frame picker, or anything touching secret values.

## Licence

MIT — see [LICENSE](LICENSE).
