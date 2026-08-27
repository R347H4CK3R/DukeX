# iOS coroutine bootstrap workaround

The iOS build patches QEMU's `sigaltstack` coroutine bootstrap so the initial `SIGUSR2` trampoline is delivered synchronously on the emulator execution thread.

This avoids a startup deadlock observed in LiveContainer/StikDebug where the first coroutine creation remained blocked in `sigsuspend()` after the SDL/UIKit and CAMetalLayer presenter had initialized successfully.
