# DukeX / Xemu iOS Vulkan + MoltenVK Review Brief

Date: 2026-05-13

This bundle is intended for a developer reviewing the iOS Vulkan renderer path,
especially the MoltenVK integration, presentation path, and rendering artifacts.
It does not include BIOS, MCPX, EEPROM, HDD, ROMs, XISOs, or any user data.

## Current Working State

- App target: iOS 26.3-era iPhone testing.
- Runtime JIT: StikDebug / Universal.js is required for realistic performance.
- Renderer: Xemu NV2A Vulkan renderer running through MoltenVK.
- Known milestone: Halo 2 can boot, load menus, and reach gameplay at full speed
  in some builds. Cutscenes are mostly smooth.
- Current blocker: gameplay can be slow and show rendering artifacts. The most
  suspicious areas are the iOS presentation path, missing MoltenVK geometry
  shader support, and shader/depth fallback behavior.
- Experimental split: `com.michaelweekley.XemuIOS` remains the old-icon fallback
  build. `com.michaelweekley.DukeX` enables the experimental Vulkan swapchain
  presenter through `XEMU_IOS_VK_SWAPCHAIN=1`.

## What To Review First

1. `hw/xbox/nv2a/pgraph/vk/instance.c`
   - iOS dynamically loads `MoltenVK.framework/MoltenVK` with `dlopen`.
   - Uses `volkInitializeCustom(vkGetInstanceProcAddr)`.
   - Enables portability enumeration on iOS.
   - Treats `geometryShader` and `shaderTessellationAndGeometryPointSize` as
     optional on iOS because MoltenVK/Metal does not expose them like desktop
     Vulkan.

2. `hw/xbox/nv2a/pgraph/vk/renderer.c`
   - Renderer lifecycle and pending work pump.
   - In the fallback Xemu bundle, `pgraph_vk_get_framebuffer_surface()` still
     cannot hand the presenter a native Vulkan/Metal texture on iOS. With
     `HAVE_EXTERNAL_MEMORY` unavailable, it waits for a surface download and
     returns `0`, forcing the SDL/OpenGL fallback presenter in `ui/xemu.c`.
   - In the DukeX swapchain experiment, the same entry point triggers a renderer
     sync so `pgraph_vk_render_display()` can blit the composed Vulkan display
     image into a `VK_KHR_swapchain` image and present it through MoltenVK.
   - `XEMU_IOS_PRESENT_DOWNLOAD_FPS` can throttle forced downloads, but this is a
     workaround, not a real presentation path.

3. `ui/xemu.c`
   - Fallback mode creates an OpenGL ES 3 context through SDL.
   - DukeX mode creates the SDL window with `SDL_WINDOW_VULKAN`, loads MoltenVK
     through SDL Vulkan helpers, skips xemu HUD rendering, and creates the
     `VkSurfaceKHR` through `SDL_Vulkan_CreateSurface()`.
   - The Swift launcher gates this with bundle ID:
     `com.michaelweekley.DukeX` sets `XEMU_IOS_VK_SWAPCHAIN=1`; the Xemu bundle
     sets it to `0`.

4. `hw/xbox/nv2a/pgraph/vk/shaders.c` and `hw/xbox/nv2a/pgraph/glsl/*`
   - iOS can run without Vulkan geometry shaders.
   - When a geometry shader would be requested but unavailable, the code tries
     CPU primitive expansion and optional host-depth interpolation.
   - Runtime flag `XEMU_IOS_HOST_DEPTH_INTERPOLATION=0` is currently set by the
     Swift launcher because it restored some Halo 2 HUD/menu correctness.

5. `hw/xbox/nv2a/pgraph/vk/draw.c`
   - Contains the CPU expansion path for quads, strips, fans, line loops, and
     polygons when geometry shaders are unavailable on iOS.
   - Also contains iOS pipeline cache save throttling.

6. `hw/xbox/nv2a/pgraph/vk/display.c`
   - Composes the display image and PVIDEO overlay.
   - Has iOS guards to avoid asserts on transient invalid PVIDEO register state.
   - DukeX mode now creates a `VK_KHR_swapchain`, acquires an image, transitions
     the composed display image to transfer-src, blits into the swapchain image,
     transitions that image to present-src, and calls `vkQueuePresentKHR`.
   - Worth auditing for image layout correctness, MoltenVK-friendly barriers,
     supported swapchain usage flags, and whether direct render-to-swapchain
     would be cleaner than the current blit.

7. `hw/xbox/nv2a/pgraph/vk/surface.c`
   - Surface upload/download tracking.
   - iOS statistics are behind `XEMU_IOS_SURFACE_STATS`.
   - Surface downloads are central to the current fallback presentation path.

## MoltenVK Build And Embed Path

- Core build script: `ios/scripts/build-core-ios.sh`
  - Requires `MOLTENVK_ROOT`.
  - Adds `-DVK_ENABLE_BETA_EXTENSIONS=1`.
  - Adds `-DVK_USE_PLATFORM_METAL_EXT=1`.
  - Creates a local `vulkan.pc` for Meson/pkg-config.

- App embed script: `ios/scripts/embed-core-ios.sh`
  - Copies `MoltenVK.framework` into the app's `Frameworks` directory.
  - Codesigns MoltenVK, `libxemu-ios-core.dylib`, and `libslirp.0.dylib`.

- Runtime diagnostics: `ios/XemuIOS/XemuIOS/XemuIOSApp.swift`
  - Sets MoltenVK diagnostic environment variables.

- Runtime renderer flags: `ios/XemuIOS/XemuIOS/EmulatorCoreRuntime.swift`
  - Sets `XEMU_IOS_HOST_DEPTH_INTERPOLATION=0`.
  - Sets `XEMU_IOS_SURFACE_STATS=1`.
  - Sets `XEMU_IOS_FALLBACK_GENERATION_FILTER=1`.
  - Sets `XEMU_IOS_SKIP_GL_FINISH=1`.
  - Leaves most trace flags disabled unless manually changed.

## Presentation Architecture

There are now two installed app variants for A/B testing:

- `com.michaelweekley.XemuIOS`: fallback path. NV2A renders through
  Vulkan/MoltenVK, the current framebuffer surface is downloaded back to
  CPU-visible memory, and the SDL/OpenGL ES presenter uploads it into a
  persistent GL texture.
- `com.michaelweekley.DukeX`: experimental path. NV2A renders through
  Vulkan/MoltenVK, display composition stays in Vulkan, then a blit presents
  into a MoltenVK swapchain created from SDL's Vulkan surface.

The DukeX path is a first implementation, not proven-good yet. Review whether
SDL's Vulkan surface is creating the expected CAMetalLayer-backed MoltenVK
surface and whether the acquire/blit/present synchronization is correct.

## Known Rendering Symptoms

- Halo 2 menu tint/HUD/radar correctness changed with depth/interpolation
  experiments. Current launcher disables host-depth interpolation.
- Gameplay is still slow compared with cutscenes.
- Visual artifacts appear during gameplay.
- PVIDEO has been made more tolerant on iOS to avoid crashes/asserts from
  transient invalid sizes/formats.

## Important Caveat

`hw/xbox/nv2a/pgraph/glsl/psh.h` currently contains an experimental
`use_host_depth_for_perspective` field that is not fully wired through all shader
generation code. Review or remove/finish that before doing a clean core rebuild.

## Useful Runtime Flags

- `XEMU_IOS_MOLTENVK_PATH`: override runtime MoltenVK dylib path.
- `XEMU_IOS_MVK_DIAGNOSTICS=1`: enables MoltenVK performance diagnostics in the
  Swift app startup.
- `XEMU_IOS_VK_RENDERER_TRACE=1`: renderer lifecycle logging.
- `XEMU_IOS_VK_SUBMIT_TRACE=1`: queue submit/fence logging.
- `XEMU_IOS_VK_MEMORY_TRACE=1`: VMA/memory budget logging.
- `XEMU_IOS_FRAMEBUFFER_TRACE=1`: framebuffer surface hit/miss logging.
- `XEMU_IOS_SURFACE_STATS=1`: periodic surface upload/download counters.
- `XEMU_IOS_PVIDEO_TRACE=1`: PVIDEO validation and overlay logging.
- `XEMU_IOS_RENDER_TRACE=1`: SDL/OpenGL fallback presenter logging.
- `XEMU_IOS_PRESENT_DOWNLOAD_FPS=<n>`: throttle forced present downloads.
- `XEMU_IOS_VK_SWAPCHAIN=1`: enable the experimental DukeX Vulkan swapchain
  presenter.
- `XEMU_IOS_VK_SWAPCHAIN_TRACE=1`: log swapchain creation/acquire/present events.
- `XEMU_IOS_HOST_DEPTH_INTERPOLATION=0|1`: toggle iOS fallback depth behavior.

## High-Level Ask For Reviewer

Please focus on whether the current MoltenVK renderer/presenter architecture is
sound for iOS, and especially:

- How to eliminate the CPU framebuffer download + GL upload presentation path.
- Whether a CAMetalLayer/MoltenVK swapchain path can replace the fallback.
- Whether CPU primitive expansion correctly replaces geometry shader behavior
  on MoltenVK.
- Whether image layout transitions/barriers in `display.c`, `surface.c`, and
  `draw.c` are safe and performant under MoltenVK.
- Whether the current shader/depth fallback explains Halo 2 HUD/menu/artifact
  differences.
