# DukeX Desktop Port

This tree is seeded from the DukeX experimental branch and is the new
frontend source for the PC/macOS app.

The intended split is:

- DukeX SwiftUI remains the product shell: Games, Profile, Settings,
  XB.Live login, achievements, messages, cloud saves, playtime tracking,
  covers, themes, and the SF Symbol tab icons used by the iOS app.
- xemu remains the emulator backend on desktop: SDL window creation,
  OpenGL renderer, desktop input/event handling, audio, networking,
  and presenter lifecycle.
- The iOS-only runtime pieces stay out of the desktop path: Universal.js
  JIT handoff, UIKit presenter windows, CAMetalLayer handoff, touch skins,
  and the Vulkan/Metal mobile presenter are not part of the macOS/Windows
  runtime.

Current desktop bridge files:

- `DukeX/Desktop/XemuDesktopLaunchPlan.swift` writes a desktop xemu TOML
  using user-supplied system files and games.
- `DukeX/Desktop/XemuDesktopRuntime.swift` launches a bundled xemu executable
  through xemu's SDL/OpenGL desktop path and tracks process lifecycle in a
  DukeX-style `RunState`.
- `../scripts/embed-xemu-desktop.sh` embeds `Embedded/Xemu/DukeX.app` into
  the macOS app bundle and keeps the sidecar branded as DukeX.

Repository split:

1. `ios/DukeX` remains the iOS/iPadOS project and continues to use the
   in-process iOS core runtime.
2. `desktop/DukeX` is the macOS desktop project. It reuses the DukeX SwiftUI
   shell and swaps runtime launch behavior to the bundled xemu sidecar.
3. The desktop path keeps XB.Live session and presence behavior aligned with
   DukeX while sending desktop sessions with `specialaccess=xemu`.
