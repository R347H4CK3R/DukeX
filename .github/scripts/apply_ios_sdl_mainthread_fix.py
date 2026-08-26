#!/usr/bin/env python3
import sys
from pathlib import Path

root = Path.cwd()
xemu_path = root / "ui" / "xemu.c"
swift_path = root / "ios" / "DukeX" / "DukeX" / "Runtime" / "Core" / "EmulatorCoreRuntime.swift"


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        fail(f"{label}: expected 1 match, found {count}")
    return text.replace(old, new, 1)


if not xemu_path.is_file() or not swift_path.is_file():
    fail("DukeX iOS source files not found")

xemu = xemu_path.read_text(encoding="utf-8")
swift = swift_path.read_text(encoding="utf-8")

# The host application owns the iOS entry point instead of SDL. SDL3 therefore
# needs SDL_MAIN_HANDLED plus SDL_SetMainReady() before the first SDL_Init().
if "#define SDL_MAIN_HANDLED 1" not in xemu:
    xemu = replace_once(
        xemu,
        "#include <math.h>\n#include <SDL3/SDL.h>",
        "#include <math.h>\n#ifdef CONFIG_IOS\n#define SDL_MAIN_HANDLED 1\n#include <SDL3/SDL_main.h>\n#endif\n#include <SDL3/SDL.h>",
        "SDL main handled header",
    )

# The emulator core is intentionally dispatched off the UIKit main thread. SDL's
# iOS video bootstrap, however, touches UIKit and must happen on the main thread.
if "xemu_ios_prepare_sdl_video" not in xemu:
    xemu = replace_once(
        xemu,
        "void xemu_ios_request_shutdown(void);\nvoid xemu_ios_set_application_active(int active);",
        "void xemu_ios_request_shutdown(void);\nint xemu_ios_prepare_sdl_video(void);\nvoid xemu_ios_set_application_active(int active);",
        "xemu SDL preflight declaration",
    )

    anchor = '''void xemu_ios_set_external_metal_layer(void *metal_layer)\n{\n    ios_external_metal_layer = metal_layer;\n    IOS_LOG(\"external CAMetalLayer %s %p\",\n            metal_layer ? \"set\" : \"cleared\", metal_layer);\n}\n'''
    replacement = anchor + '''\n__attribute__((visibility(\"default\")))\nint xemu_ios_prepare_sdl_video(void)\n{\n    uint32_t initialized = SDL_WasInit(SDL_INIT_VIDEO);\n    IOS_LOG(\"SDL video main-thread preflight begin was_init=0x%x\", initialized);\n\n    if (initialized & SDL_INIT_VIDEO) {\n        IOS_LOG(\"SDL video already initialized before core dispatch\");\n        return 1;\n    }\n\n    SDL_SetMainReady();\n    IOS_LOG(\"SDL main marked ready for host-owned iOS entry point\");\n\n    if (!SDL_Init(SDL_INIT_VIDEO)) {\n        IOS_LOG(\"SDL video main-thread preflight failed: %s\", SDL_GetError());\n        return 0;\n    }\n\n    IOS_LOG(\"SDL video main-thread preflight complete driver=%s\",\n            SDL_GetCurrentVideoDriver() ? SDL_GetCurrentVideoDriver() : \"<none>\");\n    return 1;\n}\n'''
    xemu = replace_once(xemu, anchor, replacement, "xemu SDL preflight implementation")
else:
    old = '''    if (!SDL_Init(SDL_INIT_VIDEO)) {\n        IOS_LOG(\"SDL video main-thread preflight failed: %s\", SDL_GetError());'''
    new = '''    SDL_SetMainReady();\n    IOS_LOG(\"SDL main marked ready for host-owned iOS entry point\");\n\n    if (!SDL_Init(SDL_INIT_VIDEO)) {\n        IOS_LOG(\"SDL video main-thread preflight failed: %s\", SDL_GetError());'''
    if "SDL main marked ready for host-owned iOS entry point" not in xemu:
        xemu = replace_once(xemu, old, new, "SDL_SetMainReady bootstrap")

old_init = '''    if (!SDL_Init(SDL_INIT_VIDEO)) {\n        fprintf(stderr, \"Failed to initialize SDL video subsystem: %s\\n\",\n                SDL_GetError());\n        exit(1);\n    }'''
new_init = '''#ifdef CONFIG_IOS\n    uint32_t ios_video_init = SDL_WasInit(SDL_INIT_VIDEO);\n    IOS_LOG(\"display init SDL video state=0x%x driver=%s\",\n            ios_video_init,\n            SDL_GetCurrentVideoDriver() ? SDL_GetCurrentVideoDriver() : \"<none>\");\n    if (!(ios_video_init & SDL_INIT_VIDEO)) {\n        IOS_LOG(\"SDL video was not preinitialized on the UIKit main thread; refusing background SDL_Init\");\n        fprintf(stderr, \"DukeX iOS SDL video preflight was not completed\\n\");\n        exit(1);\n    }\n#else\n    if (!SDL_Init(SDL_INIT_VIDEO)) {\n        fprintf(stderr, \"Failed to initialize SDL video subsystem: %s\\n\",\n                SDL_GetError());\n        exit(1);\n    }\n#endif'''
if new_init not in xemu:
    xemu = replace_once(xemu, old_init, new_init, "background SDL_Init guard")

if "XemuPrepareSDLVideo" not in swift:
    swift = replace_once(swift, "    private typealias XemuRequestShutdown = @convention(c) () -> Void\n    private typealias XemuSetApplicationActive = @convention(c) (Int32) -> Void", "    private typealias XemuRequestShutdown = @convention(c) () -> Void\n    private typealias XemuPrepareSDLVideo = @convention(c) () -> Int32\n    private typealias XemuSetApplicationActive = @convention(c) (Int32) -> Void", "Swift SDL preflight typealias")
    swift = replace_once(swift, "    private var requestShutdown: XemuRequestShutdown?\n    private var setApplicationActive: XemuSetApplicationActive?", "    private var requestShutdown: XemuRequestShutdown?\n    private var prepareSDLVideo: XemuPrepareSDLVideo?\n    private var setApplicationActive: XemuSetApplicationActive?", "Swift SDL preflight property")
    swift = replace_once(swift, "            let requestShutdown = loadRequestShutdown()\n            let setApplicationActive = loadSetApplicationActive()", "            let requestShutdown = loadRequestShutdown()\n            let prepareSDLVideo = loadPrepareSDLVideo()\n            let setApplicationActive = loadSetApplicationActive()", "Swift SDL preflight loader call")
    task_anchor = '''            Task { @MainActor in\n                let notificationCenter = NotificationCenter.default\n'''
    task_replacement = '''            Task { @MainActor in\n                if let prepareSDLVideo {\n                    let sdlReady = prepareSDLVideo()\n                    NativeMetalDiagnostics.log(\"SDL_PREFLIGHT\", \"mainThread=\\(Thread.isMainThread ? 1 : 0) ready=\\(sdlReady)\")\n                    NSLog(\"DukeX SDL video preflight mainThread=%d ready=%d\", Thread.isMainThread ? 1 : 0, sdlReady)\n                    if sdlReady == 0 {\n                        self.state = .failed(\"SDL video initialization failed on the iOS main thread.\")\n                        return\n                    }\n                } else {\n                    NativeMetalDiagnostics.log(\"SDL_PREFLIGHT\", \"symbol unavailable\")\n                    NSLog(\"xemu_ios_prepare_sdl_video is not available\")\n                }\n\n                let notificationCenter = NotificationCenter.default\n'''
    swift = replace_once(swift, task_anchor, task_replacement, "Swift main-thread SDL preflight")
    loader_anchor = '''    private func loadSetApplicationActive() -> XemuSetApplicationActive? {\n'''
    loader_replacement = '''    private func loadPrepareSDLVideo() -> XemuPrepareSDLVideo? {\n        if let prepareSDLVideo { return prepareSDLVideo }\n        guard let handle else { return nil }\n        guard let symbol = dlsym(handle, \"xemu_ios_prepare_sdl_video\") else {\n            NSLog(\"xemu_ios_prepare_sdl_video is not available\")\n            return nil\n        }\n        NSLog(\"Resolved xemu_ios_prepare_sdl_video\")\n        let prepare = unsafeBitCast(symbol, to: XemuPrepareSDLVideo.self)\n        prepareSDLVideo = prepare\n        return prepare\n    }\n\n    private func loadSetApplicationActive() -> XemuSetApplicationActive? {\n'''
    swift = replace_once(swift, loader_anchor, loader_replacement, "Swift SDL preflight loader")

xemu_path.write_text(xemu, encoding="utf-8")
swift_path.write_text(swift, encoding="utf-8")
print("iOS SDL main-thread preflight patch applied or already present.")
