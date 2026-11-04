# GoodScroll

A tiny macOS menu bar app that makes your mouse wheel scroll like a mouse wheel and gives
your mouse and trackpad **separate** scroll directions.

- **Discrete mouse scrolling:** every wheel notch scrolls exactly *N* lines, with no acceleration.
- **Separate direction for each device:** keep *Natural* on the trackpad and *Traditional* on the mouse,
  whatever the system "Natural scrolling" checkbox says (macOS links the two).
- **Trackpad feel untouched:** trackpad speed, acceleration and momentum are never modified.
- **Doesn't die:** see [Why it doesn't time out](#why-it-doesnt-time-out).
- Menu bar controls plus a settings window. No Dock icon. Launch at login. Universal binary, macOS 13+.

## Settings

| Setting | What it does |
|---|---|
| Enable GoodScroll | Master switch. Off = every event passes through untouched. |
| Discrete scrolling | Mouse wheel notches become a fixed line count. Turn off to keep macOS acceleration on the mouse and only fix direction. |
| Lines per notch | 1–20 (default 3). |
| Discrete horizontal scrolling | Also apply to tilt wheels / Shift-scroll. |
| Mouse direction | Follow System / Natural / Traditional. |
| Trackpad direction | Follow System / Natural / Traditional. Direction only: speed and momentum are left alone. |
| Smooth scroll while holding | Hold ⌥ / ⌃ / ⌘ to get the original accelerated scroll for that moment. |
| Launch at login | Uses `SMAppService`; appears in System Settings → General → Login Items. |
| Show menu bar icon | Hide the icon. Open GoodScroll again from Finder or Spotlight to get Settings back. |

## Install

Download the zip from [Releases](https://github.com/vladjdk/goodscroll/releases), unzip it, and move
`GoodScroll.app` to `/Applications`. The build is ad-hoc signed and not notarized, so on first launch
right-click → **Open** (or run `xattr -dr com.apple.quarantine /Applications/GoodScroll.app`).

Grant **Accessibility** when prompted (System Settings → Privacy & Security → Accessibility). GoodScroll
starts working as soon as you grant it; no relaunch needed.

### Build from source

Needs Xcode or the Command Line Tools (Swift 5.9+).

```sh
make test      # unit tests
make install   # builds a universal GoodScroll.app, copies it to /Applications, launches it
```

> **Rebuilding resets the Accessibility permission.** Ad-hoc signatures change every build, so macOS
> treats each build as a new app. Remove the old GoodScroll entry from the Accessibility list and
> re-add it. Set `SIGN_IDENTITY="Developer ID Application: …"` to sign with a stable identity.

## Why it doesn't time out

Discrete-scroll tools sit on a `CGEventTap`. If the tap's callback is slow even once, macOS disables
the tap (`kCGEventTapDisabledByTimeout`) and scrolling silently goes back to normal until you relaunch.
GoodScroll defends against this in layers:

1. **Dedicated thread.** The tap runs on its own high-priority run loop, not the main thread, so the
   menu, the settings window, or a hiccup in AppKit can't stall it.
2. **Trivial hot path.** The callback reads an immutable config snapshot under an unfair lock and
   rewrites a few integer fields: no allocation, no `UserDefaults`, no logging.
3. **Immediate re-enable.** If macOS still disables the tap (timeout, secure input, user input), the
   callback re-enables it on the spot.
4. **Watchdog.** Every 3 seconds, and after wake, screen wake, or a fast-user-switch, the app checks that
   the tap is still enabled and valid, and rebuilds it if not. The menu shows how many times it recovered.

## How it works

For each scroll event:

- **Mouse wheels** send *non-continuous* events. In discrete mode GoodScroll keeps only the sign and
  writes `±N` into `kCGScrollWheelEventDeltaAxis1`, and CoreGraphics recomputes the pixel deltas from it.
  When only the direction changes, all three delta fields (line, fixed-point, pixel) are negated so the
  accelerated magnitude stays exact.
- **Trackpads and Magic Mouse** send *continuous* events. These are only ever negated, and only when the
  trackpad direction setting differs from the system setting.
- The system "Natural scrolling" value is read from `com.apple.swipescrolldirection` and kept current
  through the `SwipeScrollDirectionDidChangeNotification` broadcast.

The decision logic lives in `GoodScrollCore` (pure Swift, unit tested). The event tap and UI are in `GoodScroll`.

## Known limitations

- Magic Mouse sends continuous events, so it follows the **trackpad** direction setting.
- Mice whose vendor software (e.g. Logi Options+) turns on "smooth scrolling" also send continuous
  events and are treated like a trackpad. Turn that option off to get discrete scrolling.

## License

MIT
