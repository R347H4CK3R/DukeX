#!/usr/bin/env python3
import os
import stat
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


def patch_vcpkg_sdl(vcpkg_root: Path) -> None:
    port_dir = vcpkg_root / "ports" / "sdl3"
    portfile = port_dir / "portfile.cmake"
    if not portfile.is_file():
        fail(f"SDL3 vcpkg port not found at {portfile}")

    patch_name = "dukex-ios-uikit-main-thread.patch"
    patch_path = port_dir / patch_name
    patch_text = r'''diff --git a/src/video/uikit/SDL_uikitwindow.m b/src/video/uikit/SDL_uikitwindow.m
index 1111111..2222222 100644
--- a/src/video/uikit/SDL_uikitwindow.m
+++ b/src/video/uikit/SDL_uikitwindow.m
@@ -129,4 +129,16 @@ bool UIKit_CreateWindow(SDL_VideoDevice *_this, SDL_Window *window, SDL_PropertiesID create_props)
 {
+    /* DukeX runs the long-lived emulator loop on a worker queue so it does not
+     * block UIKit/CoreAnimation. SDL window creation still touches UIKit and
+     * must execute on the application main thread. Block the caller while the
+     * UIKit-only portion runs there, then continue the emulator on its worker. */
+    if (![NSThread isMainThread]) {
+        __block bool result = false;
+        dispatch_sync(dispatch_get_main_queue(), ^{
+            result = UIKit_CreateWindow(_this, window, create_props);
+        });
+        return result;
+    }
+
     @autoreleasepool {
         SDL_VideoDisplay *display = SDL_GetVideoDisplayForWindow(window);
         SDL_UIKitDisplayData *data = (__bridge SDL_UIKitDisplayData *)display->internal;
@@ -229,4 +241,11 @@ void UIKit_ShowWindow(SDL_VideoDevice *_this, SDL_Window *window)
 {
+    if (![NSThread isMainThread]) {
+        dispatch_sync(dispatch_get_main_queue(), ^{
+            UIKit_ShowWindow(_this, window);
+        });
+        return;
+    }
+
     @autoreleasepool {
         SDL_UIKitWindowData *data = (__bridge SDL_UIKitWindowData *)window->internal;
         [data.uiwindow makeKeyAndVisible];
@@ -249,4 +268,11 @@ void UIKit_HideWindow(SDL_VideoDevice *_this, SDL_Window *window)
 {
+    if (![NSThread isMainThread]) {
+        dispatch_sync(dispatch_get_main_queue(), ^{
+            UIKit_HideWindow(_this, window);
+        });
+        return;
+    }
+
     @autoreleasepool {
         SDL_UIKitWindowData *data = (__bridge SDL_UIKitWindowData *)window->internal;
         data.uiwindow.hidden = YES;
@@ -318,4 +344,11 @@ void UIKit_DestroyWindow(SDL_VideoDevice *_this, SDL_Window *window)
 {
+    if (![NSThread isMainThread]) {
+        dispatch_sync(dispatch_get_main_queue(), ^{
+            UIKit_DestroyWindow(_this, window);
+        });
+        return;
+    }
+
     @autoreleasepool {
         if (window->internal != NULL) {
             SDL_UIKitWindowData *data = (__bridge SDL_UIKitWindowData *)window->internal;
'''
    patch_path.write_text(patch_text, encoding="utf-8")

    port = portfile.read_text(encoding="utf-8")
    if patch_name not in port:
        anchor = "    PATCHES\n        fix-freebsd.patch\n"
        if anchor not in port:
            fail("Unexpected SDL3 vcpkg port layout; PATCHES block not found")
        port = port.replace(anchor, anchor + f"        {patch_name}\n", 1)
        portfile.write_text(port, encoding="utf-8")
    print(f"Patched vcpkg SDL3 port with {patch_name}")


def install_vcpkg_clone_wrapper() -> None:
    if os.environ.get("GITHUB_ACTIONS") != "true":
        return
    github_path = os.environ.get("GITHUB_PATH")
    runner_temp = os.environ.get("RUNNER_TEMP")
    if not github_path or not runner_temp:
        fail("GitHub Actions environment is missing GITHUB_PATH or RUNNER_TEMP")

    wrapper_dir = root / ".github" / ".dukex-tool-wrappers"
    wrapper_dir.mkdir(parents=True, exist_ok=True)
    wrapper = wrapper_dir / "git"
    script_path = Path(__file__).resolve()
    expected_vcpkg = Path(runner_temp) / "vcpkg"
    wrapper.write_text(
        "#!/bin/bash\n"
        "set +e\n"
        "/usr/bin/git \"$@\"\n"
        "status=$?\n"
        f"if [ $status -eq 0 ] && [ -d {expected_vcpkg!s}/ports/sdl3 ]; then\n"
        f"  python3 {script_path!s} --patch-vcpkg {expected_vcpkg!s} || exit $?\n"
        "fi\n"
        "exit $status\n",
        encoding="utf-8",
    )
    wrapper.chmod(wrapper.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    with open(github_path, "a", encoding="utf-8") as fh:
        fh.write(str(wrapper_dir) + "\n")
    print(f"Installed one-step vcpkg clone wrapper at {wrapper}")


if len(sys.argv) == 3 and sys.argv[1] == "--patch-vcpkg":
    patch_vcpkg_sdl(Path(sys.argv[2]))
    raise SystemExit(0)

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
install_vcpkg_clone_wrapper()
print("iOS SDL main-thread preflight and UIKit window-thread patch prepared.")
