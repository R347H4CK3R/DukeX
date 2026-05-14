# DukeX Performance Reference Findings

Date: 2026-05-13

Scope: notes from MeloNX, DolphiniOS, and XeniOS focused on shader cache/loading, smoothness, VSync/present pacing, and the shape of a proper iOS Metal-era presenter. The Halo 2 render artifact is intentionally parked for now, but the presenter notes below are relevant to fixing it later.

Primary references:

- MeloNX source provided by the user: `/tmp/MeloNX-XC-ios-ht/melonx`
- DolphiniOS source: `https://github.com/OatmealDome/dolphin-ios`
- XeniOS source: `https://github.com/xenios-jp/XeniOS`

## MeloNX / Ryujinx Patterns

- Uses a real CAMetalLayer-backed Vulkan surface on iOS through `VK_EXT_metal_surface`.
  - Swift side creates an `MTKView`/`CAMetalLayer` and passes the native layer pointer to the renderer.
  - Core side requires `VK_KHR_surface` and `VK_EXT_metal_surface`, then creates the Vulkan surface from the CAMetalLayer.
- Sets MoltenVK process knobs at app launch:
  - `MVK_USE_METAL_PRIVATE_API=1`
  - `MVK_CONFIG_USE_METAL_PRIVATE_API=1`
  - `MVK_DEBUG=0`
  - `MVK_CONFIG_MAX_ACTIVE_METAL_COMMAND_BUFFERS_PER_QUEUE=128`
  - Enables Metal argument buffers only when the device supports the needed tier.
- Uses a threaded renderer wrapper, so renderer work is separated from the emulation/frontend path.
- Shader cache is a first-class launch setting:
  - Swift exposes Shader Cache and VSync as settings.
  - Launch args include `--disable-shader-cache` only when the setting is off.
  - Shader/PTC cache progress is routed back to Swift UI.
- Shader module creation is asynchronous in the Vulkan backend (`Task.Run`), but final use can still wait on compile completion when the pipeline needs it.
- Vulkan swapchain present mode policy:
  - If VSync is disabled and `immediate` exists, use immediate.
  - Otherwise prefer `mailbox`.
  - Fall back to `fifo`.
- The iOS Metal layer path attempts private layer controls:
  - `setNominalFramesPerSecond: 60`
  - `setDisplaySyncEnabled: false`

## DolphiniOS / Dolphin Patterns

- iOS presenter uses a persistent `MTKView` with `preferredFramesPerSecond = 120`, then passes the backing `CAMetalLayer` into Dolphin through `WindowSystemInfo`.
- JIT affects rendering-side CPU work too:
  - With JIT available, DolphiniOS selects the native vertex loader.
  - Without JIT, it falls back to software vertex loading.
- Shader compilation is explicitly user-configurable:
  - Specialized: lowest GPU demand, but can stutter.
  - Exclusive ubershaders: nearly stutter-free, high GPU cost.
  - Hybrid ubershaders: use ubershaders while specialized shaders compile in the background.
  - Skip drawing: avoids shader stalls by dropping objects until shaders are ready, with visual risk.
- Optional “wait for shaders before starting” precompiles known shaders before gameplay, trading launch delay for fewer early hitches.
- Shader cache loading flow:
  - Load shader/pipeline caches from disk.
  - Load a per-game pipeline UID cache.
  - Queue ubershader pipeline compilation if the selected mode needs it.
  - Compile missing known pipelines.
  - Optionally wait for compile completion before starting.
  - Resize worker threads down for normal runtime compilation.
- Thread count policy is conservative:
  - Runtime shader compiler threads default to `cpu_cores - 3`, clamped to 1...4.
  - Precompiler threads default to `cpu_cores - 2`, leaving room for UI/OS.
- Vulkan pipeline cache is validated before reuse:
  - Checks cache header, vendor ID, device ID, and pipeline cache UUID.
  - Falls back to an empty cache if stale.
- VSync is not treated as always-on:
  - VSync is active only when the emulator is throttled at exactly 100%.
  - iOS UI warns VSync can hurt performance below 100% speed.
  - Vulkan uses FIFO when VSync is enabled, otherwise prefers immediate, then mailbox.
  - Metal backend toggles layer display sync with `setDisplaySyncEnabled:`.

## XeniOS / Xenia Patterns

- XeniOS is a useful architectural reference, but not a direct renderer donor for DukeX right now.
  - It uses a native Metal graphics system on iOS.
  - That backend is designed around Xbox 360/Xenos behavior, not original Xbox/NV2A behavior.
  - A full native Metal backend would be a major rewrite and would risk losing the working MoltenVK path we already have.
- The valuable part is its presenter structure.
  - Guest output and UI overlays are separate layers.
  - Guest output can be refreshed from the GPU emulation thread.
  - UI overlays stay on the UI thread.
  - When no UI overlay is active, XeniOS allows guest output to present directly from the rendering path to reduce latency.
  - Persistent overlays are avoided because they can force presentation back through the UI thread and hurt pacing.
- XeniOS uses a guest-output mailbox model.
  - The renderer writes the latest guest image into a small rotating set.
  - Presentation consumes the latest ready image rather than queueing old frames.
  - This favors low latency and prevents a backlog of stale frames.
- XeniOS presents through a shader-driven output pass, not just a raw transfer.
  - It supports letterboxing, overscan-safe scaling, bilinear output, CAS, FSR, dithering, and gamma handling.
  - It calculates output placement based on guest aspect ratio and host surface dimensions.
  - This is the right conceptual direction for DukeX because it separates "what the emulated GPU produced" from "how iOS should display it."
- XeniOS has stronger per-title shader storage organization.
  - Shader storage is under a device-specific and title-specific cache root.
  - It caches translated Metal shader artifacts and pipeline data separately.
  - It can prewarm pipeline/binary archive data before gameplay when blocking startup is acceptable.
- XeniOS handles many texture-load and resolve cases on GPU.
  - The native Metal texture cache has dedicated load pipelines for guest formats, block compression, endian/layout conversion, scaled resolves, and depth cases.
  - This is likely relevant to the Halo 2 artifact class, but should be handled later as a targeted texture/resolve investigation rather than as part of the presenter pacing pass.

## Current DukeX State

- Default generated config already sets:
  - `[perf] cache_shaders = true`
- The Vulkan backend already has a driver pipeline cache:
  - Loads `shader_cache/vulkan_pipeline_cache.bin`.
  - Creates `VkPipelineCache` with prior blob data.
  - Passes that cache into graphics and compute pipeline creation.
  - Saves with `vkGetPipelineCacheData`.
- Current iOS save policy is likely too conservative for crash-heavy testing:
  - iOS dirty threshold is `2048` pipeline creations.
  - iOS save interval is `300000000us` / 300 seconds.
  - If the app crashes before either condition is met, most warm-up value can be lost.
- Current DukeX present mode is forced to:
  - `XEMU_IOS_VK_PRESENT_MODE=immediate`
  - `XEMU_IOS_VK_PRESENT_FPS=0`
- Current native CAMetalLayer setup:
  - Uses `.bgra8Unorm`
  - `framebufferOnly = false`
  - `presentsWithTransaction = false`
  - Does not currently apply `setDisplaySyncEnabled:` or `setNominalFramesPerSecond:`.
- Current presenter blits the emulator output image into the swapchain with `vkCmdBlitImage`.
  - MeloNX/Ryujinx often use helper shader blits/effects.
  - Dolphin uses backend presenter paths with swapchain images as render targets.
  - XeniOS strongly supports moving toward a shader/fullscreen-quad presenter rather than relying on transfer blit for final output.

## Best Middle Ground For DukeX

The best middle ground is not to replace our current renderer with XeniOS Metal, and not to keep stacking small patches on the raw blit presenter forever. We should preserve the working MoltenVK/Vulkan renderer, then rebuild the presenter around the proven pattern shared by these apps.

1. Keep Vulkan/MoltenVK as the main renderer for now.
   - This follows MeloNX and keeps us on the path that already boots and runs Halo 2 at viable speed.
   - It avoids the huge risk of a native Metal backend rewrite before the NV2A path is stable.

2. Replace the final-output blit with a real presenter pass.
   - Use the current CAMetalLayer-backed Vulkan swapchain.
   - Present by rendering a fullscreen triangle/quad into the swapchain image.
   - Start with bilinear sampling and correct aspect/letterbox handling.
   - Add optional CAS/FSR-style sharpening later, after correctness is stable.
   - This borrows XeniOS's presenter model without porting its Xbox 360 renderer.

3. Split "guest output" from "host display."
   - Treat the emulated Xbox output as an intermediate guest image.
   - Let the presenter decide scaling, rotation, aspect fit, safe area, and orientation.
   - Keep Swift UI separate from the game surface so it does not interfere with frame pacing.

4. Add a low-latency guest-output mailbox.
   - Do not queue multiple stale frames for presentation.
   - Always prefer the newest completed guest image.
   - This is the practical XeniOS lesson that fits DukeX without taking its whole renderer.

5. Adopt Dolphin-style shader/pipeline cache policy.
   - Persist pipeline cache much more aggressively on iOS.
   - Track per-game pipeline keys later so common pipelines can be warmed before launch.
   - Eventually expose per-game cache settings in the DukeX gear menu.

6. Keep MeloNX-style MoltenVK tuning.
   - Continue using a real CAMetalLayer-backed Vulkan surface.
   - Keep argument buffer tuning device-gated.
   - Use MoltenVK command buffer and queue tuning cautiously, then test one variable at a time.

7. Add present pacing presets instead of one hardcoded mode.
   - Speed: immediate present, display sync off.
   - Smooth: mailbox present, display sync off.
   - Accurate: FIFO/FIFO relaxed, display sync on.
   - For now, default to Speed for Halo 2 performance testing, then A/B with Smooth.

8. Leave the Halo 2 artifact fix as a separate renderer correctness track.
   - The artifact returning alongside the blue tint/radar suggests a real texture/resolve/format path issue.
   - XeniOS points toward GPU-side guest texture conversion/resolve handling as the likely long-term direction.
   - Do not hide that artifact with postprocessing; fix the underlying guest rendering path.

## Recommended Next Experiments

1. Make shader/pipeline cache persistence more aggressive on iOS.
   - Save after roughly 32-64 dirty pipeline creations or 15-30 seconds.
   - Keep final save on shutdown.
   - This is low risk and directly helps crashy test sessions.

2. Add lightweight cache diagnostics.
   - Log cache file load size.
   - Log pipeline cache dirty count.
   - Log saves with elapsed time.
   - Keep noisy per-surface/per-texture tracing off during performance tests.

3. Add a DukeX present mode test matrix.
   - Performance baseline: `immediate`, display sync off.
   - Smoothness baseline: `mailbox`, display sync off.
   - Fidelity/pacing baseline: `fifo_relaxed` or `fifo`, display sync on.

4. Add CAMetalLayer display sync controls.
   - Try `setNominalFramesPerSecond: 60` or 120.
   - Try `setDisplaySyncEnabled: false` for immediate/mailbox testing.
   - Try `setDisplaySyncEnabled: true` for FIFO/fidelity testing.

5. Prototype the XeniOS-style presenter pass.
   - Keep the existing Vulkan swapchain.
   - Replace `vkCmdBlitImage` final presentation with a render pass and sampled fullscreen output.
   - Preserve current aspect/orientation fixes.
   - Add simple letterbox fit before adding sharpening or FSR/CAS.

6. Eventually add game-level performance settings.
   - Shader cache: on/off/clear.
   - Present mode: immediate/mailbox/fifo/fifo relaxed.
   - Warm-up policy: start immediately vs wait for known pipelines.
   - Presenter scaling: integer/native fit, aspect fit, fill with safe-area crop.

## Likely Best First Patch

Before larger renderer rewrites, do this first:

- Disable noisy surface texture trace for normal testing.
- Lower the iOS pipeline-cache save threshold/time.
- Add a log line showing the selected present mode and whether the pipeline cache loaded/saved.
- Keep `immediate` mode for raw performance testing, then A/B with `mailbox`.

This mirrors the practical parts of Dolphin and MeloNX without bringing in their larger renderer architectures yet. After that, the first presenter-side patch should be the shader/fullscreen output pass inspired by XeniOS.
