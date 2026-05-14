#include <stdio.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#import <Foundation/Foundation.h>

static bool xemu_ios_metal_hud_requested(void)
{
    const char *env = getenv("XEMU_IOS_METAL_HUD");
    return env && env[0] && strcmp(env, "0") != 0;
}

__attribute__((constructor))
static void xemu_ios_configure_metal_hud_early(void)
{
    /*
     * Metal reads HUD environment very early. Keep this in a constructor so
     * the variables exist before SwiftUI, MoltenVK, or CAMetalLayer startup.
     */
    if (!xemu_ios_metal_hud_requested()) {
        unsetenv("MTL_HUD_ENABLED");
        unsetenv("MTL_HUD_LOG_ENABLED");
        unsetenv("MTL_HUD_LOGGING_ENABLED");
        unsetenv("MTL_HUD_LOG_SHADER_ENABLED");
        unsetenv("MTL_HUD_ENCODER_TIMING_ENABLED");
        unsetenv("MTL_HUD_SHOW_ZERO_METRICS");
        unsetenv("MTL_HUD_OPACITY");

        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"MetalHudEnabled"];
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"MetalHUDForceEnabled"];
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"MetalForceHudEnabled"];
        [[NSUserDefaults standardUserDefaults] synchronize];

        fprintf(stderr, "xemu_ios: early Metal HUD environment disabled\n");
        fflush(stderr);
        return;
    }

    setenv("MTL_HUD_ENABLED", "1", 1);
    setenv("MTL_HUD_LOG_ENABLED", "1", 1);
    setenv("MTL_HUD_LOGGING_ENABLED", "1", 1);
    setenv("MTL_HUD_LOG_SHADER_ENABLED", "1", 1);
    setenv("MTL_HUD_ENCODER_TIMING_ENABLED", "1", 1);
    setenv("MTL_HUD_SHOW_ZERO_METRICS", "1", 1);
    setenv("MTL_HUD_OPACITY", "1.0", 1);

    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"MetalHudEnabled"];
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"MetalHUDForceEnabled"];
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"MetalForceHudEnabled"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    fprintf(stderr, "xemu_ios: early Metal HUD environment configured\n");
    fflush(stderr);
}
