#!/usr/bin/env python3
from pathlib import Path

path = Path("hw/xbox/nv2a/pgraph/vk/instance.c")
s = path.read_text()

old = '''    uint32_t instance_version = VK_API_VERSION_1_0;
    if (vkEnumerateInstanceVersion) {
        vkEnumerateInstanceVersion(&instance_version);
        instance_version = MIN(instance_version, VK_API_VERSION_1_3);
    }
'''
new = '''    uint32_t instance_version = VK_API_VERSION_1_0;
    if (vkEnumerateInstanceVersion) {
        VkResult version_result = vkEnumerateInstanceVersion(&instance_version);
#ifdef CONFIG_IOS
        fprintf(stderr, "xemu-ios: vkEnumerateInstanceVersion result=%d raw=%u (%u.%u.%u)\\n",
                version_result, instance_version,
                VK_VERSION_MAJOR(instance_version), VK_VERSION_MINOR(instance_version),
                VK_VERSION_PATCH(instance_version));
#endif
        instance_version = MIN(instance_version, VK_API_VERSION_1_3);
    }
'''
if old not in s:
    raise SystemExit("instance version block not found")
s = s.replace(old, new, 1)

old = '''    g_autoptr(VkExtensionPropertiesArray) available_extensions =
        get_available_instance_extensions(pg);

    g_autoptr(StringArray) enabled_extension_names =
'''
new = '''    g_autoptr(VkExtensionPropertiesArray) available_extensions =
        get_available_instance_extensions(pg);

#ifdef CONFIG_IOS
    fprintf(stderr, "xemu-ios: available Vulkan instance extensions (%u):\\n",
            available_extensions ? available_extensions->len : 0);
    if (available_extensions) {
        for (int i = 0; i < available_extensions->len; i++) {
            VkExtensionProperties *e =
                &g_array_index(available_extensions, VkExtensionProperties, i);
            fprintf(stderr, "xemu-ios:   %s spec=%u\\n",
                    e->extensionName, e->specVersion);
        }
    }
#endif

    g_autoptr(StringArray) enabled_extension_names =
'''
if old not in s:
    raise SystemExit("available extension block not found")
s = s.replace(old, new, 1)

old = '''    result = vkCreateInstance(&create_info, NULL, &r->instance);
    if (result != VK_SUCCESS) {
        error_setg(errp, "Failed to create instance (%d)", result);
        return false;
    }
'''
new = '''#ifdef CONFIG_IOS
    fprintf(stderr,
            "xemu-ios: vkCreateInstance api=%u.%u.%u flags=0x%x extensions=%u layers=%u\\n",
            VK_VERSION_MAJOR(r->vk_api_version), VK_VERSION_MINOR(r->vk_api_version),
            VK_VERSION_PATCH(r->vk_api_version), (unsigned)create_info.flags,
            create_info.enabledExtensionCount, create_info.enabledLayerCount);
    for (uint32_t i = 0; i < create_info.enabledExtensionCount; i++) {
        fprintf(stderr, "xemu-ios: enabled instance extension[%u]=%s\\n", i,
                create_info.ppEnabledExtensionNames[i]);
    }
#endif
    result = vkCreateInstance(&create_info, NULL, &r->instance);
#ifdef CONFIG_IOS
    fprintf(stderr, "xemu-ios: vkCreateInstance returned %d instance=%p\\n",
            result, (void *)r->instance);
#endif
    if (result != VK_SUCCESS) {
        error_setg(errp,
                   "Failed to create instance (VkResult=%d, api=%u.%u.%u, flags=0x%x, extensions=%u)",
                   result, VK_VERSION_MAJOR(r->vk_api_version),
                   VK_VERSION_MINOR(r->vk_api_version), VK_VERSION_PATCH(r->vk_api_version),
                   (unsigned)create_info.flags, create_info.enabledExtensionCount);
        return false;
    }
'''
if old not in s:
    raise SystemExit("vkCreateInstance block not found")
s = s.replace(old, new, 1)

path.write_text(s)
print("Applied iOS Vulkan initialization diagnostics")

# Keep the QEMU core loop alive when another thread temporarily owns the
# dedicated GLib context. The old code ignored g_main_context_acquire()'s
# return value, which allowed prepare/check/release calls without ownership.
# A previous defensive variant skipped the whole poll iteration on contention,
# starving guest CPU/timers and producing an unbounded busy-spin on iOS.
main_loop_path = Path("util/main-loop.c")
main_loop = main_loop_path.read_text()

old_main_loop = '''static int os_host_main_loop_wait(int64_t timeout)
{
#ifdef XBOX
    GMainContext *context = qemu_main_context;
#else
    GMainContext *context = g_main_context_default();
#endif
    int ret;

    g_main_context_acquire(context);

    glib_pollfds_fill(&timeout);

    bql_unlock();
    replay_mutex_unlock();

#ifdef XBOX
    qemu_mutex_unlock_main_loop();
#endif
    ret = qemu_poll_ns((GPollFD *)gpollfds->data, gpollfds->len, timeout);
#ifdef XBOX
    qemu_mutex_lock_main_loop();
#endif

    replay_mutex_lock();
    bql_lock();

    glib_pollfds_poll();

    g_main_context_release(context);

    return ret;
}
'''

new_main_loop = '''static int os_host_main_loop_wait(int64_t timeout)
{
#ifdef XBOX
    GMainContext *context = qemu_main_context;
#else
    GMainContext *context = g_main_context_default();
#endif
    bool have_glib_context;
    int ret;

    have_glib_context = g_main_context_acquire(context);
    if (have_glib_context) {
        glib_pollfds_fill(&timeout);
    } else {
        /*
         * Do not skip the QEMU poll/timer iteration just because GLib is
         * temporarily owned by another thread. A short bounded timeout keeps
         * guest execution responsive without turning contention into a hot
         * spin. The owning thread remains responsible for GLib dispatch.
         */
        timeout = qemu_soonest_timeout((int64_t)SCALE_MS, timeout);
#ifdef XBOX
        static unsigned long long glib_contention_count;

        glib_contention_count++;
        if (glib_contention_count == 1 ||
            (glib_contention_count & (glib_contention_count - 1)) == 0) {
            fprintf(stderr,
                    "xemu-ios: GLib main context contention; QEMU loop remains live "
                    "(count=%llu)\\n",
                    glib_contention_count);
        }
#endif
    }

    bql_unlock();
    replay_mutex_unlock();

#ifdef XBOX
    qemu_mutex_unlock_main_loop();
#endif
    ret = qemu_poll_ns((GPollFD *)gpollfds->data, gpollfds->len, timeout);
#ifdef XBOX
    qemu_mutex_lock_main_loop();
#endif

    replay_mutex_lock();
    bql_lock();

    if (have_glib_context) {
        glib_pollfds_poll();
        g_main_context_release(context);
    }

    return ret;
}
'''

if "GLib main context contention; QEMU loop remains live" not in main_loop:
    if old_main_loop not in main_loop:
        raise SystemExit("main-loop ownership block not found")
    main_loop = main_loop.replace(old_main_loop, new_main_loop, 1)
    main_loop_path.write_text(main_loop)

print("Applied iOS GLib/QEMU main-loop starvation fix")
