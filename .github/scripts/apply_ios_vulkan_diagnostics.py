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
