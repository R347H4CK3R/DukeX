# DukeX ARMSX2 / XeniOS Renderer Approach

This note captures the current research direction after reverting to the pre-DukeX-GS baseline. The active DukeX presenter is a real Metal path through a `CAMetalLayer` and MoltenVK swapchain; the current goal is to improve correctness and speed without repeating the broad MeloNX-style geometry compute experiment that produced exploded geometry.

## Current DukeX Baseline

- Runtime identity is `com.mafty.DukeXGC` / `DukeX`.
- Gameplay rendering uses the native `CAMetalLayer` presenter when the bundle ID starts with `com.mafty.DukeX`.
- Swift creates the Metal layer on the app side and passes it into the core.
- Vulkan presentation is via `VK_EXT_metal_surface` / MoltenVK swapchain, with final blit into the swapchain image.
- Per-game Vulkan pipeline cache paths are already wired by Swift through `XEMU_IOS_VK_PIPELINE_CACHE_PATH`.
- The Vulkan renderer already has an in-memory shader module cache and a disk `VkPipelineCache`.
- When Vulkan geometry shaders are unavailable, the renderer already falls back to CPU primitive expansion for several primitive modes.

Important local files:

- `ios/XemuIOS/XemuIOS/EmulatorCoreRuntime.swift`
- `ios/XemuIOS/XemuIOS/XemuLaunchPlan.swift`
- `ios/XemuIOS/XemuIOS/EmulatorFileStore.swift`
- `hw/xbox/nv2a/pgraph/vk/display.c`
- `hw/xbox/nv2a/pgraph/vk/draw.c`
- `hw/xbox/nv2a/pgraph/vk/shaders.c`
- `hw/xbox/nv2a/pgraph/vk/surface-compute.c`

## XeniOS Takeaways

XeniOS points toward targeted primitive handling, not a blind renderer rewrite.

- Its presenter separates guest output from UI overlays. Persistent overlays are avoided because they hurt frame pacing.
- The Metal presenter keeps presentation narrowly scoped: acquire drawable, render/blit, present, track completion.
- Its primitive processor treats Metal as a backend with missing legacy primitive support and converts unsupported primitives into safer host primitives.
- For the SPIRV-Cross path, point sprites and rectangle lists are expanded before draw rather than relying on geometry shaders.
- It keeps a triangle-list fallback for primitive expansion to avoid strip-restart behavior differences on Metal.
- Its heavier geometry emulation is gated by feature support and falls back instead of forcing broken draws.

Relevant XeniOS reference files:

- `/tmp/dukex-research-xenios/src/xenia/gpu/metal/metal_primitive_processor.cc`
- `/tmp/dukex-research-xenios/src/xenia/gpu/metal/metal_command_processor.cc`
- `/tmp/dukex-research-xenios/src/xenia/gpu/metal/metal_shader_cache.cc`
- `/tmp/dukex-research-xenios/src/xenia/gpu/metal/metal_geometry_shader.cc`
- `/tmp/dukex-research-xenios/src/xenia/ui/metal/metal_presenter.mm`

## ARMSX2 Takeaways

ARMSX2 is more useful as a pacing, upload, and cache hygiene reference.

- It creates and attaches `CAMetalLayer` on the main thread before handing it to rendering code.
- Metal present mode is reduced to a practical FIFO-style path where needed.
- Upload buffers use ring-style reuse tracked by completed draw number, avoiding needless allocations and CPU/GPU stalls.
- It separates texture upload, late texture upload, and vertex upload encoders.
- Its Vulkan shader cache validates pipeline cache blobs against device/vendor/cache UUID before reuse.
- It treats presentation pacing and emulator throttling as one coordinated decision, not two competing throttles.

Relevant ARMSX2 reference files:

- `/tmp/dukex-research-armsx2/app/src/main/cpp/common/CocoaTools.mm`
- `/tmp/dukex-research-armsx2/app/src/main/cpp/pcsx2/GS/Renderers/Metal/GSDeviceMTL.mm`
- `/tmp/dukex-research-armsx2/app/src/main/cpp/pcsx2/GS/Renderers/Vulkan/VKShaderCache.cpp`
- `/tmp/dukex-research-armsx2/app/src/main/cpp/pcsx2/GS/Renderers/Vulkan/VKSwapChain.cpp`
- `/tmp/dukex-research-armsx2/app/src/main/cpp/pcsx2/VMManager.cpp`

## Recommended DukeX Direction

Do not restart the broad MeloNX geometry-compute rewrite right now. The better middle ground is:

1. Stabilize the current MoltenVK presenter.
2. Tighten frame pacing so either Vulkan/CAMetalLayer presentation paces the frame or the emulator delay does, but not both.
3. Strengthen the current per-game Vulkan pipeline cache with device/vendor/UUID validation and more reliable saves for graphics, compute, and display pipelines.
4. Add targeted primitive diagnostics around Halo 2:
   - primitive mode
   - polygon mode
   - CPU-expanded vs native topology
   - host depth interpolation on/off
   - aspect mode, especially forced 4:3 vs auto/16:9
5. Test XeniOS-style safer primitive expansion:
   - prefer triangle-list expansion for Metal/MoltenVK-sensitive paths
   - avoid geometry shader assumptions
   - avoid broad mesh/compute emulation until a single primitive failure is proven
6. Consider an upload-buffer/ring-buffer cleanup only after the artifact is understood, because that is more likely to affect performance than the missing radar/floor artifact.

## First Test Matrix

Start with Halo 2 because the artifact is easy to recognize.

- Baseline: current settings.
- Force `XEMU_IOS_PRESENTER_ASPECT=4:3`.
- Toggle `XEMU_IOS_HOST_DEPTH_INTERPOLATION=1`.
- Add logging for primitive expansion only around non-triangle primitives.
- Compare triangle-strip/fan/quad expansion paths with a triangle-list-only fallback.
- Keep cache enabled and do not clear it between every run unless shader changes require it.

Expected interpretation:

- If 4:3 fixes the radar interior, the bug is likely aspect/projection or widescreen-specific HUD behavior.
- If host depth interpolation changes floors/objects, the bug is likely the no-geometry-shader fallback losing a geometry-stage depth adjustment.
- If triangle-list expansion changes the artifact, the bug is likely primitive conversion order, winding, or strip/fan behavior.
- If none change it, the next suspect is texture/surface resolve or render target feedback rather than geometry.

## Immediate Candidate Changes

- Add an internal debug toggle for forced 4:3 presenter/game aspect.
- Add scoped primitive expansion trace counters, not full per-draw spam by default.
- Validate loaded pipeline cache headers before feeding MoltenVK.
- Call the pipeline-cache dirty/save path for compute and display pipeline creation too.
- Add a setting or env mode for triangle-list-only CPU expansion on iOS.

