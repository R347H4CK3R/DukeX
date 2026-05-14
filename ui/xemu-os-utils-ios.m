/*
 * iOS-specific helpers.
 *
 * Copyright (C) 2026
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>

#include "xemu-os-utils.h"

void xemu_ios_configure_presenter_metal_layer(void *metal_layer)
{
    if (!metal_layer) {
        return;
    }

    CAMetalLayer *layer = (__bridge CAMetalLayer *)metal_layer;
    if (![layer isKindOfClass:[CAMetalLayer class]]) {
        fprintf(stderr,
                "xemu_ios: presenter layer skipped for non-CAMetalLayer object %p\n",
                metal_layer);
        fflush(stderr);
        return;
    }

    CGFloat scale = [UIScreen mainScreen].scale;
    CGRect bounds = layer.bounds;

    layer.opaque = YES;
    layer.framebufferOnly = NO;
    layer.presentsWithTransaction = NO;
    layer.allowsNextDrawableTimeout = YES;
    layer.contentsGravity = kCAGravityResizeAspect;
    layer.contentsScale = scale;

    if (bounds.size.width > 0.0 && bounds.size.height > 0.0) {
        layer.drawableSize = CGSizeMake(MAX(1.0, bounds.size.width * scale),
                                        MAX(1.0, bounds.size.height * scale));
    }

    xemu_ios_configure_metal_layer_hud(metal_layer);
}

void xemu_ios_configure_metal_layer_hud(void *metal_layer)
{
    static unsigned int configure_count;

    if (!metal_layer) {
        return;
    }

    CAMetalLayer *layer = (__bridge CAMetalLayer *)metal_layer;
    if (![layer isKindOfClass:[CAMetalLayer class]]) {
        fprintf(stderr,
                "xemu_ios: Metal HUD skipped for non-CAMetalLayer object %p\n",
                metal_layer);
        fflush(stderr);
        return;
    }

    NSDictionary *properties = @{
        @"mode" : @"default",
        @"logging" : @"default",
    };

    layer.developerHUDProperties = properties;
    [[NSUserDefaults standardUserDefaults] setBool:YES
                                            forKey:@"MetalForceHudEnabled"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    configure_count++;
    if (configure_count <= 8 || (configure_count % 120) == 0) {
        id device = layer.device;
        NSString *deviceName =
            [device respondsToSelector:@selector(name)] ? [device name] : nil;
        CGSize drawableSize = layer.drawableSize;
        CGRect bounds = layer.bounds;

        fprintf(stderr,
                "xemu_ios: CAMetalLayer HUD config #%u main_thread=%d"
                " layer=%p device=%s drawable=%.0fx%.0f bounds=%.0fx%.0f"
                " scale=%.2f properties=%s\n",
                configure_count,
                [NSThread isMainThread] ? 1 : 0,
                metal_layer,
                deviceName ? [deviceName UTF8String] : "(nil)",
                drawableSize.width, drawableSize.height,
                bounds.size.width, bounds.size.height,
                layer.contentsScale,
                [[properties description] UTF8String]);
        fflush(stderr);
    }
}

const char *xemu_get_os_info(void)
{
    NSString *version = [[UIDevice currentDevice] systemVersion];
    NSString *model = [[UIDevice currentDevice] model];
    NSString *info = [NSString stringWithFormat:@"%@ %@", model, version];

    return [info UTF8String];
}
