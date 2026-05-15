# Renderer Overview

The current iOS renderer path keeps Xemu's Vulkan renderer active and presents
through MoltenVK into a native `CAMetalLayer`.

## Presenter Path

1. Swift creates a fullscreen native presenter window.
2. `NativeMetalPresenterView` owns a `CAMetalLayer`.
3. `EmulatorCoreRuntime` passes that layer to the core through
   `xemu_ios_set_external_metal_layer`.
4. The Vulkan display path creates a MoltenVK surface/swapchain against the
   external layer.
5. The guest display output is copied through the iOS swapchain presenter.

The primary Swift entry points are:

- `ios/DukeX/DukeX/EmulatorCoreRuntime.swift`
- `ios/DukeX/DukeX/NativeMetalPresenter.swift`

The primary renderer files are:

- `hw/xbox/nv2a/pgraph/vk/display.c`
- `hw/xbox/nv2a/pgraph/vk/renderer.h`
- `hw/xbox/nv2a/pgraph/vk/shaders.c`
- `hw/xbox/nv2a/pgraph/vk/texture.c`

## Runtime Controls

Important runtime toggles are passed through `XEMU_IOS_*` environment variables.
These are set in `EmulatorCoreRuntime.invoke` before calling `xemu_ios_main`.

Current user-facing controls include:

- Present pacing mode.
- Optional 30 FPS lock.
- Metal HUD request toggle.
- Stats HUD toggle.
- TB cache size: 64 MB, 128 MB, or 256 MB.

## Known Issues

- Apple Metal HUD does not currently appear reliably, even on the native Metal
  presenter layer.
- Some games still expose HUD and depth/primitive artifacts.
- The current stats HUD is app-provided and should not be treated as a
  substitute for full GPU capture.

## Review Suggestions

Renderer review should focus on:

- Swapchain image ownership and layout transitions.
- Host depth interpolation and depth format behavior.
- Surface-to-texture compatibility rules.
- Shader module/pipeline cache lifetime.
- Whether problematic HUD effects require targeted primitive handling rather
  than broad geometry-shader emulation.
