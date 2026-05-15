/*
 * Geforce NV2A PGRAPH Vulkan Renderer
 *
 * Copyright (c) 2024-2025 Matt Borgerson
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, see <http://www.gnu.org/licenses/>.
 */

#include "renderer.h"
#include "ui/xemu-widescreen.h"
#include <math.h>

#ifdef CONFIG_IOS
bool xemu_ios_vulkan_presenter_enabled(void);

static bool ios_vk_swapchain_trace_enabled(void)
{
    static int enabled = -1;

    if (enabled < 0) {
        const char *env = getenv("XEMU_IOS_VK_SWAPCHAIN_TRACE");
        enabled = env && strcmp(env, "0") != 0;
    }

    return enabled;
}

#define IOS_SWAPCHAIN_LOG(...) \
    do { \
        if (ios_vk_swapchain_trace_enabled()) { \
            fprintf(stderr, "xemu_ios: vk swapchain: " __VA_ARGS__); \
            fputc('\n', stderr); \
            fflush(stderr); \
        } \
    } while (0)

static bool ios_pvideo_trace_enabled(void)
{
    static int enabled = -1;

    if (enabled < 0) {
        const char *env = getenv("XEMU_IOS_PVIDEO_TRACE");
        enabled = env && strcmp(env, "0") != 0;
    }

    return enabled;
}

#define IOS_PVIDEO_LOG(...) \
    do { \
        if (ios_pvideo_trace_enabled()) { \
            fprintf(stderr, "xemu_ios: pvideo: " __VA_ARGS__); \
            fputc('\n', stderr); \
            fflush(stderr); \
        } \
    } while (0)

typedef struct IOSDisplayPerfFrame {
    bool present_ready;
    bool native_present_command;
    bool pvideo_enabled;
    bool surface_upload_pending;
    bool finish_presenting;
    gint64 wait_present_us;
    gint64 finish_presenting_us;
    gint64 surface_upload_us;
    gint64 pvideo_upload_us;
    gint64 acquire_us;
    gint64 command_us;
    gint64 submit_us;
    gint64 present_us;
    gint64 total_us;
} IOSDisplayPerfFrame;

typedef struct IOSDisplayPerfWindow {
    uint64_t frames;
    uint64_t present_ready_frames;
    uint64_t present_missed_frames;
    uint64_t native_present_frames;
    uint64_t pvideo_frames;
    uint64_t surface_upload_pending_frames;
    uint64_t finish_presenting_frames;
    gint64 wait_present_us;
    gint64 finish_presenting_us;
    gint64 surface_upload_us;
    gint64 pvideo_upload_us;
    gint64 acquire_us;
    gint64 command_us;
    gint64 submit_us;
    gint64 present_us;
    gint64 total_us;
} IOSDisplayPerfWindow;

typedef struct DukeXDisplayStats {
    uint64_t sample_id;
    double presenter_fps;
    uint32_t nv2a_fps;
    int32_t mspf;
    uint64_t frames;
    uint64_t present_ready_frames;
    uint64_t present_missed_frames;
    uint64_t native_present_frames;
    uint64_t pvideo_frames;
    uint64_t surface_upload_pending_frames;
    uint64_t finish_presenting_frames;
    int64_t avg_total_us;
    int64_t avg_wait_present_us;
    int64_t avg_submit_us;
    int64_t avg_present_us;
    int32_t queue_submits;
    int32_t aux_submits;
    int32_t display_submits;
    int32_t shader_binds;
    int32_t surface_downloads;
    int32_t surface_to_texture;
    int32_t geometry_updates;
    int32_t geometry_ram_updates;
    int32_t geometry_index_updates;
    int32_t geometry_inline_updates;
    int32_t pipeline_generations;
    int32_t shader_generations;
    int32_t texture_uploads;
    int32_t surface_uploads;
} DukeXDisplayStats;

static DukeXDisplayStats ios_latest_display_stats;

int xemu_ios_copy_display_stats(DukeXDisplayStats *out_stats);

int xemu_ios_copy_display_stats(DukeXDisplayStats *out_stats)
{
    if (!out_stats || !ios_latest_display_stats.sample_id) {
        return 0;
    }

    *out_stats = ios_latest_display_stats;
    return 1;
}

static bool ios_display_perf_stats_enabled(void)
{
    static int enabled = -1;

    if (enabled < 0) {
        const char *env = getenv("XEMU_IOS_DISPLAY_PERF_STATS");
        enabled = env && strcmp(env, "0") != 0;
    }

    return enabled;
}

static gint64 ios_perf_avg_us(gint64 total_us, uint64_t frames)
{
    return frames ? total_us / (gint64)frames : 0;
}

static void ios_display_stats_update(PGRAPHState *pg,
                                     const IOSDisplayPerfFrame *frame)
{
    static gint64 window_start_us;
    static IOSDisplayPerfWindow window;

    gint64 now_us = g_get_monotonic_time();
    if (!window_start_us) {
        window_start_us = now_us;
    }

    window.frames++;
    window.present_ready_frames += frame->present_ready;
    window.present_missed_frames += !frame->present_ready;
    window.native_present_frames += frame->native_present_command;
    window.pvideo_frames += frame->pvideo_enabled;
    window.surface_upload_pending_frames += frame->surface_upload_pending;
    window.finish_presenting_frames += frame->finish_presenting;
    window.wait_present_us += frame->wait_present_us;
    window.finish_presenting_us += frame->finish_presenting_us;
    window.surface_upload_us += frame->surface_upload_us;
    window.pvideo_upload_us += frame->pvideo_upload_us;
    window.acquire_us += frame->acquire_us;
    window.command_us += frame->command_us;
    window.submit_us += frame->submit_us;
    window.present_us += frame->present_us;
    window.total_us += frame->total_us;

    gint64 elapsed_us = now_us - window_start_us;
    if (elapsed_us < 500000) {
        return;
    }

    unsigned int frame_idx =
        (g_nv2a_stats.frame_ptr + NV2A_PROF_NUM_FRAMES - 1) %
        NV2A_PROF_NUM_FRAMES;

    ios_latest_display_stats = (DukeXDisplayStats){
        .sample_id = ios_latest_display_stats.sample_id + 1,
        .presenter_fps =
            elapsed_us > 0 ? (double)window.frames * 1000000.0 / elapsed_us : 0.0,
        .nv2a_fps = g_nv2a_stats.increment_fps,
        .mspf = g_nv2a_stats.frame_history[frame_idx].mspf,
        .frames = window.frames,
        .present_ready_frames = window.present_ready_frames,
        .present_missed_frames = window.present_missed_frames,
        .native_present_frames = window.native_present_frames,
        .pvideo_frames = window.pvideo_frames,
        .surface_upload_pending_frames = window.surface_upload_pending_frames,
        .finish_presenting_frames = window.finish_presenting_frames,
        .avg_total_us = ios_perf_avg_us(window.total_us, window.frames),
        .avg_wait_present_us = ios_perf_avg_us(window.wait_present_us, window.frames),
        .avg_submit_us = ios_perf_avg_us(window.submit_us, window.frames),
        .avg_present_us = ios_perf_avg_us(window.present_us, window.frames),
        .queue_submits = nv2a_profile_get_counter_value(NV2A_PROF_QUEUE_SUBMIT),
        .aux_submits = nv2a_profile_get_counter_value(NV2A_PROF_QUEUE_SUBMIT_AUX),
        .display_submits = nv2a_profile_get_counter_value(NV2A_PROF_QUEUE_SUBMIT_5),
        .shader_binds = nv2a_profile_get_counter_value(NV2A_PROF_SHADER_BIND),
        .surface_downloads = nv2a_profile_get_counter_value(NV2A_PROF_SURF_DOWNLOAD),
        .surface_to_texture = nv2a_profile_get_counter_value(NV2A_PROF_SURF_TO_TEX),
        .geometry_updates =
            nv2a_profile_get_counter_value(NV2A_PROF_GEOM_BUFFER_UPDATE_1) +
            nv2a_profile_get_counter_value(NV2A_PROF_GEOM_BUFFER_UPDATE_2) +
            nv2a_profile_get_counter_value(NV2A_PROF_GEOM_BUFFER_UPDATE_3) +
            nv2a_profile_get_counter_value(NV2A_PROF_GEOM_BUFFER_UPDATE_4),
        .geometry_ram_updates =
            nv2a_profile_get_counter_value(NV2A_PROF_GEOM_BUFFER_UPDATE_1),
        .geometry_index_updates =
            nv2a_profile_get_counter_value(NV2A_PROF_GEOM_BUFFER_UPDATE_2),
        .geometry_inline_updates =
            nv2a_profile_get_counter_value(NV2A_PROF_GEOM_BUFFER_UPDATE_3),
        .pipeline_generations =
            nv2a_profile_get_counter_value(NV2A_PROF_PIPELINE_GEN),
        .shader_generations =
            nv2a_profile_get_counter_value(NV2A_PROF_SHADER_GEN),
        .texture_uploads =
            nv2a_profile_get_counter_value(NV2A_PROF_TEX_UPLOAD),
        .surface_uploads =
            nv2a_profile_get_counter_value(NV2A_PROF_SURF_UPLOAD),
    };

    memset(&window, 0, sizeof(window));
    window_start_us = now_us;
}

static void ios_display_perf_stats_log(PGRAPHState *pg,
                                       const IOSDisplayPerfFrame *frame)
{
    static gint64 window_start_us;
    static IOSDisplayPerfWindow window;

    if (!ios_display_perf_stats_enabled()) {
        return;
    }

    gint64 now_us = g_get_monotonic_time();
    if (!window_start_us) {
        window_start_us = now_us;
    }

    window.frames++;
    window.present_ready_frames += frame->present_ready;
    window.present_missed_frames += !frame->present_ready;
    window.native_present_frames += frame->native_present_command;
    window.pvideo_frames += frame->pvideo_enabled;
    window.surface_upload_pending_frames += frame->surface_upload_pending;
    window.finish_presenting_frames += frame->finish_presenting;
    window.wait_present_us += frame->wait_present_us;
    window.finish_presenting_us += frame->finish_presenting_us;
    window.surface_upload_us += frame->surface_upload_us;
    window.pvideo_upload_us += frame->pvideo_upload_us;
    window.acquire_us += frame->acquire_us;
    window.command_us += frame->command_us;
    window.submit_us += frame->submit_us;
    window.present_us += frame->present_us;
    window.total_us += frame->total_us;

    gint64 elapsed_us = now_us - window_start_us;
    if (elapsed_us < 2000000) {
        return;
    }

    unsigned int frame_idx =
        (g_nv2a_stats.frame_ptr + NV2A_PROF_NUM_FRAMES - 1) %
        NV2A_PROF_NUM_FRAMES;
    int mspf = g_nv2a_stats.frame_history[frame_idx].mspf;
    double presenter_fps =
        elapsed_us > 0 ? (double)window.frames * 1000000.0 / elapsed_us : 0.0;

    fprintf(stderr,
            "xemu_ios: display perf: presenter_fps=%.1f nv2a_fps=%u mspf=%d"
            " frames=%" PRIu64 " ready=%" PRIu64 " miss=%" PRIu64
            " native=%" PRIu64 " pvideo=%" PRIu64 " upload_pending=%" PRIu64
            " finish_presenting=%" PRIu64
            " avg_us total=%" PRId64 " wait_present=%" PRId64
            " finish_presenting=%" PRId64 " surface_upload=%" PRId64
            " pvideo_upload=%" PRId64 " acquire=%" PRId64
            " command=%" PRId64 " submit=%" PRId64 " present=%" PRId64
            " counters queue=%d aux=%d display=%d pipeline_gen=%d"
            " shader_gen=%d shader_bind=%d tex_upload=%d surf_upload=%d"
            " surf_download=%d surf_to_tex=%d geom=%d\n",
            presenter_fps,
            g_nv2a_stats.increment_fps,
            mspf,
            window.frames,
            window.present_ready_frames,
            window.present_missed_frames,
            window.native_present_frames,
            window.pvideo_frames,
            window.surface_upload_pending_frames,
            window.finish_presenting_frames,
            ios_perf_avg_us(window.total_us, window.frames),
            ios_perf_avg_us(window.wait_present_us, window.frames),
            ios_perf_avg_us(window.finish_presenting_us, window.frames),
            ios_perf_avg_us(window.surface_upload_us, window.frames),
            ios_perf_avg_us(window.pvideo_upload_us, window.frames),
            ios_perf_avg_us(window.acquire_us, window.frames),
            ios_perf_avg_us(window.command_us, window.frames),
            ios_perf_avg_us(window.submit_us, window.frames),
            ios_perf_avg_us(window.present_us, window.frames),
            nv2a_profile_get_counter_value(NV2A_PROF_QUEUE_SUBMIT),
            nv2a_profile_get_counter_value(NV2A_PROF_QUEUE_SUBMIT_AUX),
            nv2a_profile_get_counter_value(NV2A_PROF_QUEUE_SUBMIT_5),
            nv2a_profile_get_counter_value(NV2A_PROF_PIPELINE_GEN),
            nv2a_profile_get_counter_value(NV2A_PROF_SHADER_GEN),
            nv2a_profile_get_counter_value(NV2A_PROF_SHADER_BIND),
            nv2a_profile_get_counter_value(NV2A_PROF_TEX_UPLOAD),
            nv2a_profile_get_counter_value(NV2A_PROF_SURF_UPLOAD),
            nv2a_profile_get_counter_value(NV2A_PROF_SURF_DOWNLOAD),
            nv2a_profile_get_counter_value(NV2A_PROF_SURF_TO_TEX),
            nv2a_profile_get_counter_value(NV2A_PROF_GEOM_BUFFER_UPDATE_1) +
                nv2a_profile_get_counter_value(NV2A_PROF_GEOM_BUFFER_UPDATE_2) +
                nv2a_profile_get_counter_value(NV2A_PROF_GEOM_BUFFER_UPDATE_3) +
                nv2a_profile_get_counter_value(NV2A_PROF_GEOM_BUFFER_UPDATE_4));
    fflush(stderr);

    memset(&window, 0, sizeof(window));
    window_start_us = now_us;
}
#else
#define IOS_SWAPCHAIN_LOG(...) \
    do { \
    } while (0)
#define IOS_PVIDEO_LOG(...) \
    do { \
    } while (0)
#endif

static uint8_t *convert_texture_data__CR8YB8CB8YA8(uint8_t *data_out,
                                                   const uint8_t *data_in,
                                                   unsigned int width,
                                                   unsigned int height,
                                                   unsigned int pitch)
{
    int x, y;
    for (y = 0; y < height; y++) {
        const uint8_t *line = &data_in[y * pitch];
        const uint32_t row_offset = y * width;
        for (x = 0; x < width; x++) {
            uint8_t *pixel = &data_out[(row_offset + x) * 4];
            convert_yuy2_to_rgb(line, x, &pixel[0], &pixel[1], &pixel[2]);
            pixel[3] = 255;
        }
    }
    return data_out;
}

static float pvideo_calculate_scale(unsigned int din_dout,
                                    unsigned int output_size)
{
    float calculated_in = din_dout * (output_size - 1);
    calculated_in = floorf(calculated_in / (1 << 20) + 0.5f);
    return (calculated_in + 1.0f) / output_size;
}

static void destroy_pvideo_image(PGRAPHState *pg)
{
    PGRAPHVkState *r = pg->vk_renderer_state;
    PGRAPHVkDisplayState *d = &r->display;

    if (d->pvideo.sampler != VK_NULL_HANDLE) {
        vkDestroySampler(r->device, d->pvideo.sampler, NULL);
        d->pvideo.sampler = VK_NULL_HANDLE;
    }

    if (d->pvideo.image_view != VK_NULL_HANDLE) {
        vkDestroyImageView(r->device, d->pvideo.image_view, NULL);
        d->pvideo.image_view = VK_NULL_HANDLE;
    }

    if (d->pvideo.image != VK_NULL_HANDLE) {
        vmaDestroyImage(r->allocator, d->pvideo.image, d->pvideo.allocation);
        d->pvideo.image = VK_NULL_HANDLE;
        d->pvideo.allocation = VK_NULL_HANDLE;
    }
}

static void create_pvideo_image(PGRAPHState *pg, int width, int height)
{
    PGRAPHVkState *r = pg->vk_renderer_state;
    PGRAPHVkDisplayState *d = &r->display;

    if (d->pvideo.image == VK_NULL_HANDLE || d->pvideo.width != width ||
        d->pvideo.height != height) {
        destroy_pvideo_image(pg);
    }

    VkImageCreateInfo image_create_info = {
        .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = VK_IMAGE_TYPE_2D,
        .extent.width = width,
        .extent.height = height,
        .extent.depth = 1,
        .mipLevels = 1,
        .arrayLayers = 1,
        .format = VK_FORMAT_R8G8B8A8_UNORM,
        .tiling = VK_IMAGE_TILING_OPTIMAL,
        .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED,
        .usage = VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT,
        .samples = VK_SAMPLE_COUNT_1_BIT,
        .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
        .flags = 0,
    };
    VmaAllocationCreateInfo alloc_create_info = {
        .usage = VMA_MEMORY_USAGE_AUTO_PREFER_DEVICE,
    };
    VK_CHECK(vmaCreateImage(r->allocator, &image_create_info,
                            &alloc_create_info, &d->pvideo.image,
                            &d->pvideo.allocation, NULL));

    VkImageViewCreateInfo image_view_create_info = {
        .sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = d->pvideo.image,
        .viewType = VK_IMAGE_VIEW_TYPE_2D,
        .format = VK_FORMAT_R8G8B8A8_UNORM,
        .subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT,
        .subresourceRange.baseMipLevel = 0,
        .subresourceRange.levelCount = image_create_info.mipLevels,
        .subresourceRange.baseArrayLayer = 0,
        .subresourceRange.layerCount = image_create_info.arrayLayers,
    };
    VK_CHECK(vkCreateImageView(r->device, &image_view_create_info, NULL,
                               &d->pvideo.image_view));

    VkSamplerCreateInfo sampler_create_info = {
        .sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
        .magFilter = VK_FILTER_LINEAR,
        .minFilter = VK_FILTER_NEAREST,
        .addressModeU = VK_SAMPLER_ADDRESS_MODE_REPEAT,
        .addressModeV = VK_SAMPLER_ADDRESS_MODE_REPEAT,
        .addressModeW = VK_SAMPLER_ADDRESS_MODE_REPEAT,
        .borderColor = VK_BORDER_COLOR_INT_OPAQUE_WHITE,
        .mipmapMode = VK_SAMPLER_MIPMAP_MODE_NEAREST,
    };
    VK_CHECK(vkCreateSampler(r->device, &sampler_create_info, NULL,
                             &d->pvideo.sampler));
}

static void upload_pvideo_image(PGRAPHState *pg, PvideoState state)
{
    NV2AState *d = container_of(pg, NV2AState, pgraph);
    PGRAPHVkState *r = pg->vk_renderer_state;
    PGRAPHVkDisplayState *disp = &r->display;

    create_pvideo_image(pg, state.in_width, state.in_height);

    // FIXME: Dirty tracking. We don't necessarily need to upload so much.

    // Copy texture data to mapped device buffer
    uint8_t *mapped_memory_ptr;

    VK_CHECK(vmaMapMemory(r->allocator,
                          r->storage_buffers[BUFFER_STAGING_SRC].allocation,
                          (void *)&mapped_memory_ptr));

    convert_texture_data__CR8YB8CB8YA8(
        mapped_memory_ptr, d->vram_ptr + state.base + state.offset,
        state.in_width, state.in_height, state.pitch);

    vmaFlushAllocation(r->allocator,
                       r->storage_buffers[BUFFER_STAGING_SRC].allocation, 0,
                       VK_WHOLE_SIZE);

    vmaUnmapMemory(r->allocator,
                   r->storage_buffers[BUFFER_STAGING_SRC].allocation);

    // FIXME: Merge with display renderer command buffer

    VkCommandBuffer cmd = pgraph_vk_begin_single_time_commands(pg);

    VkBufferMemoryBarrier host_barrier = {
        .sType = VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
        .srcAccessMask = VK_ACCESS_HOST_WRITE_BIT,
        .dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT,
        .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
        .buffer = r->storage_buffers[BUFFER_STAGING_SRC].buffer,
        .size = VK_WHOLE_SIZE
    };
    vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_HOST_BIT,
                         VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, NULL, 1,
                         &host_barrier, 0, NULL);

    pgraph_vk_transition_image_layout(
        pg, cmd, disp->pvideo.image, VK_FORMAT_R8_UNORM,
        VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);

    VkBufferImageCopy region = {
        .bufferOffset = 0,
        .bufferRowLength = 0,
        .bufferImageHeight = 0,
        .imageSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT,
        .imageSubresource.mipLevel = 0,
        .imageSubresource.baseArrayLayer = 0,
        .imageSubresource.layerCount = 1,
        .imageOffset = (VkOffset3D){ 0, 0, 0 },
        .imageExtent = (VkExtent3D){ state.in_width, state.in_height, 1 },
    };
    vkCmdCopyBufferToImage(cmd, r->storage_buffers[BUFFER_STAGING_SRC].buffer,
                           disp->pvideo.image,
                           VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);

    pgraph_vk_transition_image_layout(pg, cmd, disp->pvideo.image,
                                      VK_FORMAT_R8G8B8A8_UNORM,
                                      VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                                      VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
    pgraph_vk_end_single_time_commands(pg, cmd);
}

static const char *display_frag_glsl =
    "#version 450\n"
    "layout(binding = 0) uniform sampler2D tex;\n"
    "layout(binding = 1) uniform sampler2D pvideo_tex;\n"
    "layout(push_constant, std430) uniform PushConstants {\n"
    "    float line_offset;\n"
    "    vec2 display_size;\n"
    "    bool pvideo_enable;\n"
    "    vec2 pvideo_in_pos;\n"
    "    vec4 pvideo_pos;\n"
    "    vec4 pvideo_scale;\n"
    "    bool pvideo_color_key_enable;\n"
    "    vec3 pvideo_color_key;\n"
    "};\n"
    "layout(location = 0) out vec4 out_Color;\n"
    "void main()\n"
    "{\n"
    "    vec2 tex_coord = gl_FragCoord.xy/display_size;\n"
    "    float rel = display_size.y/textureSize(tex, 0).y/line_offset;\n"
    "    tex_coord.y = 1 + rel*(tex_coord.y - 1);\n"
    "    tex_coord.y = 1 - tex_coord.y;\n" // GL compat
    "    out_Color.rgba = texture(tex, tex_coord);\n"
    "    if (pvideo_enable) {\n"
    "        vec2 screen_coord = vec2(gl_FragCoord.x, display_size.y - gl_FragCoord.y) * pvideo_scale.z;\n"
    "        vec4 output_region = vec4(pvideo_pos.xy, pvideo_pos.xy + pvideo_pos.zw);\n"
    "        bvec4 clip = bvec4(lessThan(screen_coord, output_region.xy),\n"
    "                           greaterThan(screen_coord, output_region.zw));\n"
    "        if (!any(clip) && (!pvideo_color_key_enable || out_Color.rgb == pvideo_color_key)) {\n"
    "            vec2 out_xy = screen_coord - pvideo_pos.xy;\n"
    "            vec2 in_st = (pvideo_in_pos + out_xy * pvideo_scale.xy) / textureSize(pvideo_tex, 0);\n"
    "            out_Color.rgba = texture(pvideo_tex, in_st);\n"
    "        }\n"
    "    }\n"
    "}\n";

#ifdef CONFIG_IOS
static const char *ios_presenter_vert_glsl =
    "#version 450\n"
    "layout(push_constant, std430) uniform PushConstants {\n"
    "    vec4 options;\n"
    "};\n"
    "layout(location = 0) out vec2 tex_coord;\n"
    "void main()\n"
    "{\n"
    "    vec2 pos[3] = vec2[](\n"
    "        vec2(-1.0, -1.0),\n"
    "        vec2( 3.0, -1.0),\n"
    "        vec2(-1.0,  3.0));\n"
    "    vec2 uv = (pos[gl_VertexIndex] + vec2(1.0)) * 0.5;\n"
    "    if (options.x != 0.0) {\n"
    "        uv.x = 1.0 - uv.x;\n"
    "    }\n"
    "    if (options.y != 0.0) {\n"
    "        uv.y = 1.0 - uv.y;\n"
    "    }\n"
    "    tex_coord = uv;\n"
    "    gl_Position = vec4(pos[gl_VertexIndex], 0.0, 1.0);\n"
    "}\n";

static const char *ios_presenter_frag_glsl =
    "#version 450\n"
    "layout(binding = 0) uniform sampler2D guest_output;\n"
    "layout(location = 0) in vec2 tex_coord;\n"
    "layout(location = 0) out vec4 out_color;\n"
    "void main()\n"
    "{\n"
    "    out_color = texture(guest_output, tex_coord);\n"
    "}\n";
#endif

static void create_descriptor_pool(PGRAPHState *pg)
{
    PGRAPHVkState *r = pg->vk_renderer_state;

    VkDescriptorPoolSize pool_sizes = {
        .type = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .descriptorCount = 2,
    };

    VkDescriptorPoolCreateInfo pool_info = {
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .poolSizeCount = 1,
        .pPoolSizes = &pool_sizes,
        .maxSets = 1,
        .flags = VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
    };
    VK_CHECK(vkCreateDescriptorPool(r->device, &pool_info, NULL,
                                    &r->display.descriptor_pool));
}

static void destroy_descriptor_pool(PGRAPHState *pg)
{
    PGRAPHVkState *r = pg->vk_renderer_state;

    vkDestroyDescriptorPool(r->device, r->display.descriptor_pool, NULL);
    r->display.descriptor_pool = VK_NULL_HANDLE;
}

static void create_descriptor_set_layout(PGRAPHState *pg)
{
    PGRAPHVkState *r = pg->vk_renderer_state;

    VkDescriptorSetLayoutBinding bindings[2];

    for (int i = 0; i < ARRAY_SIZE(bindings); i++) {
        bindings[i] = (VkDescriptorSetLayoutBinding){
            .binding = i,
            .descriptorCount = 1,
            .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT,
        };
    }
    VkDescriptorSetLayoutCreateInfo layout_info = {
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = ARRAY_SIZE(bindings),
        .pBindings = bindings,
    };
    VK_CHECK(vkCreateDescriptorSetLayout(r->device, &layout_info, NULL,
                                         &r->display.descriptor_set_layout));
}

static void destroy_descriptor_set_layout(PGRAPHState *pg)
{
    PGRAPHVkState *r = pg->vk_renderer_state;

    vkDestroyDescriptorSetLayout(r->device, r->display.descriptor_set_layout,
                                 NULL);
    r->display.descriptor_set_layout = VK_NULL_HANDLE;
}

static void create_descriptor_sets(PGRAPHState *pg)
{
    PGRAPHVkState *r = pg->vk_renderer_state;

    VkDescriptorSetLayout layout = r->display.descriptor_set_layout;

    VkDescriptorSetAllocateInfo alloc_info = {
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = r->display.descriptor_pool,
        .descriptorSetCount = 1,
        .pSetLayouts = &layout,
    };
    VK_CHECK(vkAllocateDescriptorSets(r->device, &alloc_info,
                                      &r->display.descriptor_set));
}

static void create_render_pass(PGRAPHState *pg)
{
    PGRAPHVkState *r = pg->vk_renderer_state;

    VkAttachmentDescription attachment;

    VkAttachmentReference color_reference;
    attachment = (VkAttachmentDescription){
        .format = VK_FORMAT_R8G8B8A8_UNORM,
        .samples = VK_SAMPLE_COUNT_1_BIT,
        .loadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .storeOp = VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .finalLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };
    color_reference = (VkAttachmentReference){
        0, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
    };

    VkSubpassDependency dependency = {
        .srcSubpass = VK_SUBPASS_EXTERNAL,
    };

    dependency.srcStageMask |=
        VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    dependency.dstStageMask |=
        VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    dependency.dstAccessMask |= VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;

    VkSubpassDescription subpass = {
        .pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color_reference,
    };

    VkRenderPassCreateInfo renderpass_create_info = {
        .sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .attachmentCount = 1,
        .pAttachments = &attachment,
        .subpassCount = 1,
        .pSubpasses = &subpass,
        .dependencyCount = 1,
        .pDependencies = &dependency,
    };
    VK_CHECK(vkCreateRenderPass(r->device, &renderpass_create_info, NULL,
                                &r->display.render_pass));
}

static void destroy_render_pass(PGRAPHState *pg)
{
    PGRAPHVkState *r = pg->vk_renderer_state;
    vkDestroyRenderPass(r->device, r->display.render_pass, NULL);
    r->display.render_pass = VK_NULL_HANDLE;
}

static void create_display_pipeline(PGRAPHState *pg)
{
    PGRAPHVkState *r = pg->vk_renderer_state;

    r->display.display_frag =
        pgraph_vk_create_shader_module_from_glsl(
            r, VK_SHADER_STAGE_FRAGMENT_BIT, display_frag_glsl);

    VkPipelineShaderStageCreateInfo shader_stages[] = {
        (VkPipelineShaderStageCreateInfo){
            .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = VK_SHADER_STAGE_VERTEX_BIT,
            .module = r->quad_vert_module->module,
            .pName = "main",
        },
        (VkPipelineShaderStageCreateInfo){
            .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = VK_SHADER_STAGE_FRAGMENT_BIT,
            .module = r->display.display_frag->module,
            .pName = "main",
        },
     };

    VkPipelineVertexInputStateCreateInfo vertex_input = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
    };

    VkPipelineInputAssemblyStateCreateInfo input_assembly = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        .primitiveRestartEnable = VK_FALSE,
    };

    VkPipelineViewportStateCreateInfo viewport_state = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .viewportCount = 1,
        .scissorCount = 1,
    };

    VkPipelineRasterizationStateCreateInfo rasterizer = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .depthClampEnable = VK_FALSE,
        .rasterizerDiscardEnable = VK_FALSE,
        .polygonMode = VK_POLYGON_MODE_FILL,
        .lineWidth = 1.0f,
        .cullMode = VK_CULL_MODE_BACK_BIT,
        .frontFace = VK_FRONT_FACE_CLOCKWISE,
        .depthBiasEnable = VK_FALSE,
    };

    VkPipelineMultisampleStateCreateInfo multisampling = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .sampleShadingEnable = VK_FALSE,
        .rasterizationSamples = VK_SAMPLE_COUNT_1_BIT,
    };

    VkPipelineDepthStencilStateCreateInfo depth_stencil = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        .depthTestEnable = VK_FALSE,
        .depthCompareOp = VK_COMPARE_OP_ALWAYS,
        .depthBoundsTestEnable = VK_FALSE,
    };

    VkPipelineColorBlendAttachmentState color_blend_attachment = {
        .colorWriteMask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT |
                          VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT,
        .blendEnable = VK_FALSE,
    };

    VkPipelineColorBlendStateCreateInfo color_blending = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .logicOpEnable = VK_FALSE,
        .logicOp = VK_LOGIC_OP_COPY,
        .attachmentCount = 1,
        .pAttachments = &color_blend_attachment,
    };

    VkDynamicState dynamic_states[] = { VK_DYNAMIC_STATE_VIEWPORT,
                                        VK_DYNAMIC_STATE_SCISSOR };
    VkPipelineDynamicStateCreateInfo dynamic_state = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .dynamicStateCount = 2,
        .pDynamicStates = dynamic_states,
    };

    VkPushConstantRange push_constant_range = {
        .stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT,
        .offset = 0,
        .size = r->display.display_frag->push_constants.total_size,
    };

    VkPipelineLayoutCreateInfo pipeline_layout_info = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 1,
        .pSetLayouts = &r->display.descriptor_set_layout,
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = &push_constant_range,
    };
    VK_CHECK(vkCreatePipelineLayout(r->device, &pipeline_layout_info, NULL,
                                    &r->display.pipeline_layout));

    VkGraphicsPipelineCreateInfo pipeline_info = {
        .sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .stageCount = ARRAY_SIZE(shader_stages),
        .pStages = shader_stages,
        .pVertexInputState = &vertex_input,
        .pInputAssemblyState = &input_assembly,
        .pViewportState = &viewport_state,
        .pRasterizationState = &rasterizer,
        .pMultisampleState = &multisampling,
        .pDepthStencilState = r->zeta_binding ? &depth_stencil : NULL,
        .pColorBlendState = &color_blending,
        .pDynamicState = &dynamic_state,
        .layout = r->display.pipeline_layout,
        .renderPass = r->display.render_pass,
        .subpass = 0,
        .basePipelineHandle = VK_NULL_HANDLE,
    };
    VK_CHECK(vkCreateGraphicsPipelines(r->device, r->vk_pipeline_cache, 1,
                                       &pipeline_info, NULL,
                                       &r->display.pipeline));
}

static void destroy_display_pipeline(PGRAPHState *pg)
{
    PGRAPHVkState *r = pg->vk_renderer_state;

    vkDestroyPipeline(r->device, r->display.pipeline, NULL);
    r->display.pipeline = VK_NULL_HANDLE;

    vkDestroyPipelineLayout(r->device, r->display.pipeline_layout, NULL);
    r->display.pipeline_layout = VK_NULL_HANDLE;

    pgraph_vk_destroy_shader_module(r, r->display.display_frag);
    r->display.display_frag = NULL;
}

static void create_frame_buffer(PGRAPHState *pg)
{
    PGRAPHVkState *r = pg->vk_renderer_state;

    VkFramebufferCreateInfo create_info = {
        .sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
        .renderPass = r->display.render_pass,
        .attachmentCount = 1,
        .pAttachments = &r->display.image_view,
        .width = r->display.width,
        .height = r->display.height,
        .layers = 1,
    };
    VK_CHECK(vkCreateFramebuffer(r->device, &create_info, NULL,
                                 &r->display.framebuffer));
}

static void destroy_frame_buffer(PGRAPHState *pg)
{
    PGRAPHVkState *r = pg->vk_renderer_state;
    vkDestroyFramebuffer(r->device, r->display.framebuffer, NULL);
    r->display.framebuffer = NULL;
}

static void destroy_current_display_image(PGRAPHState *pg)
{
    PGRAPHVkState *r = pg->vk_renderer_state;
    PGRAPHVkDisplayState *d = &r->display;

    if (d->image == VK_NULL_HANDLE) {
        return;
    }

    destroy_frame_buffer(pg);

#if HAVE_EXTERNAL_MEMORY
    glDeleteTextures(1, &d->gl_texture_id);
    d->gl_texture_id = 0;

    glDeleteMemoryObjectsEXT(1, &d->gl_memory_obj);
    d->gl_memory_obj = 0;

#ifdef WIN32
    CloseHandle(d->handle);
    d->handle = 0;
#endif
#endif

    vkDestroyImageView(r->device, d->image_view, NULL);
    d->image_view = VK_NULL_HANDLE;

    vkDestroyImage(r->device, d->image, NULL);
    d->image = VK_NULL_HANDLE;

    vkFreeMemory(r->device, d->memory, NULL);
    d->memory = VK_NULL_HANDLE;

    d->draw_time = 0;
}

#ifdef CONFIG_IOS
static VkExtent2D ios_clamp_swapchain_extent(VkSurfaceCapabilitiesKHR caps,
                                             uint32_t width, uint32_t height)
{
    if (caps.currentExtent.width != UINT32_MAX) {
        return caps.currentExtent;
    }

    VkExtent2D extent = {
        .width = width,
        .height = height,
    };
    extent.width = MAX(caps.minImageExtent.width,
                       MIN(caps.maxImageExtent.width, extent.width));
    extent.height = MAX(caps.minImageExtent.height,
                        MIN(caps.maxImageExtent.height, extent.height));
    return extent;
}

static float ios_presenter_env_float(const char *name, float fallback,
                                     float min_value, float max_value)
{
    const char *env = getenv(name);
    char *end = NULL;
    float value;

    if (!env || !*env) {
        return fallback;
    }

    value = strtof(env, &end);
    if (end == env || !isfinite(value)) {
        return fallback;
    }

    return MIN(max_value, MAX(min_value, value));
}

static bool ios_presenter_env_bool(const char *name, bool fallback)
{
    const char *env = getenv(name);

    if (!env || !*env) {
        return fallback;
    }

    return strcmp(env, "0") != 0;
}

static float ios_presenter_aspect_ratio(PGRAPHVkDisplayState *d)
{
    const char *env = getenv("XEMU_IOS_PRESENTER_ASPECT");

    if (env && *env) {
        if (!strcmp(env, "16:9") || !strcmp(env, "16x9")) {
            return 16.0f / 9.0f;
        }
        if (!strcmp(env, "4:3") || !strcmp(env, "4x3")) {
            return 4.0f / 3.0f;
        }
        if (!strcmp(env, "native")) {
            return d->height ? (float)d->width / (float)d->height :
                               4.0f / 3.0f;
        }
    }

    return xemu_get_widescreen() ? 16.0f / 9.0f : 4.0f / 3.0f;
}

static VkRect2D ios_presenter_fit_rect(PGRAPHVkDisplayState *d)
{
    const bool landscape = d->swapchain_extent.width >= d->swapchain_extent.height;
    const float scale = landscape ?
        ios_presenter_env_float("XEMU_IOS_PRESENTER_LANDSCAPE_SCALE",
                                0.96f, 0.1f, 1.0f) :
        ios_presenter_env_float("XEMU_IOS_PRESENTER_PORTRAIT_SCALE",
                                0.96f, 0.1f, 1.0f);
    const float align_x = landscape ?
        ios_presenter_env_float("XEMU_IOS_PRESENTER_LANDSCAPE_ALIGN_X",
                                0.5f, 0.0f, 1.0f) :
        ios_presenter_env_float("XEMU_IOS_PRESENTER_PORTRAIT_ALIGN_X",
                                0.5f, 0.0f, 1.0f);
    const float align_y = landscape ?
        ios_presenter_env_float("XEMU_IOS_PRESENTER_LANDSCAPE_ALIGN_Y",
                                0.5f, 0.0f, 1.0f) :
        ios_presenter_env_float("XEMU_IOS_PRESENTER_PORTRAIT_ALIGN_Y",
                                0.5f, 0.0f, 1.0f);
    const float src_aspect = ios_presenter_aspect_ratio(d);
    const float max_width = (float)d->swapchain_extent.width * scale;
    const float max_height = (float)d->swapchain_extent.height * scale;
    float fit_width = max_width;
    float fit_height = max_width / src_aspect;

    if (fit_height > max_height) {
        fit_height = max_height;
        fit_width = fit_height * src_aspect;
    }

    VkRect2D rect = {
        .offset = {
            .x = (int32_t)(((float)d->swapchain_extent.width - fit_width) * align_x),
            .y = (int32_t)(((float)d->swapchain_extent.height - fit_height) * align_y),
        },
        .extent = {
            .width = MAX(1, (uint32_t)lroundf(fit_width)),
            .height = MAX(1, (uint32_t)lroundf(fit_height)),
        },
    };

    if ((uint32_t)rect.offset.x + rect.extent.width > d->swapchain_extent.width) {
        rect.offset.x = MAX(0, (int32_t)d->swapchain_extent.width -
                               (int32_t)rect.extent.width);
    }
    if ((uint32_t)rect.offset.y + rect.extent.height > d->swapchain_extent.height) {
        rect.offset.y = MAX(0, (int32_t)d->swapchain_extent.height -
                               (int32_t)rect.extent.height);
    }

    return rect;
}

static VkSurfaceFormatKHR ios_choose_swapchain_format(
    VkSurfaceFormatKHR *formats, uint32_t format_count)
{
    if (format_count == 1 && formats[0].format == VK_FORMAT_UNDEFINED) {
        return (VkSurfaceFormatKHR){
            .format = VK_FORMAT_B8G8R8A8_UNORM,
            .colorSpace = VK_COLOR_SPACE_SRGB_NONLINEAR_KHR,
        };
    }

    for (uint32_t i = 0; i < format_count; i++) {
        if ((formats[i].format == VK_FORMAT_B8G8R8A8_UNORM ||
             formats[i].format == VK_FORMAT_R8G8B8A8_UNORM) &&
            formats[i].colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
            return formats[i];
        }
    }

    return formats[0];
}

static VkCompositeAlphaFlagBitsKHR ios_choose_composite_alpha(
    VkCompositeAlphaFlagsKHR supported)
{
    const VkCompositeAlphaFlagBitsKHR candidates[] = {
        VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        VK_COMPOSITE_ALPHA_PRE_MULTIPLIED_BIT_KHR,
        VK_COMPOSITE_ALPHA_POST_MULTIPLIED_BIT_KHR,
        VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR,
    };

    for (uint32_t i = 0; i < ARRAY_SIZE(candidates); i++) {
        if (supported & candidates[i]) {
            return candidates[i];
        }
    }

    return VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
}

static const char *ios_present_mode_name(VkPresentModeKHR mode)
{
    switch (mode) {
    case VK_PRESENT_MODE_IMMEDIATE_KHR:
        return "immediate";
    case VK_PRESENT_MODE_MAILBOX_KHR:
        return "mailbox";
    case VK_PRESENT_MODE_FIFO_KHR:
        return "fifo";
    case VK_PRESENT_MODE_FIFO_RELAXED_KHR:
        return "fifo_relaxed";
    default:
        return "unknown";
    }
}

static bool ios_present_modes_contains(const VkPresentModeKHR *modes,
                                       uint32_t mode_count,
                                       VkPresentModeKHR mode)
{
    for (uint32_t i = 0; i < mode_count; i++) {
        if (modes[i] == mode) {
            return true;
        }
    }
    return false;
}

static bool ios_present_mode_from_name(const char *name,
                                       VkPresentModeKHR *mode_out)
{
    if (!name || !*name) {
        return false;
    }

    if (!strcasecmp(name, "immediate")) {
        *mode_out = VK_PRESENT_MODE_IMMEDIATE_KHR;
        return true;
    }
    if (!strcasecmp(name, "mailbox")) {
        *mode_out = VK_PRESENT_MODE_MAILBOX_KHR;
        return true;
    }
    if (!strcasecmp(name, "fifo_relaxed") || !strcasecmp(name, "relaxed")) {
        *mode_out = VK_PRESENT_MODE_FIFO_RELAXED_KHR;
        return true;
    }
    if (!strcasecmp(name, "fifo")) {
        *mode_out = VK_PRESENT_MODE_FIFO_KHR;
        return true;
    }

    return false;
}

static VkPresentModeKHR ios_choose_present_mode(PGRAPHState *pg,
                                                VkSurfaceKHR surface)
{
    PGRAPHVkState *r = pg->vk_renderer_state;
    uint32_t mode_count = 0;
    VkResult result = vkGetPhysicalDeviceSurfacePresentModesKHR(
        r->physical_device, surface, &mode_count, NULL);
    if (result != VK_SUCCESS || mode_count == 0) {
        IOS_SWAPCHAIN_LOG("present modes unavailable result=%d count=%u; using fifo",
                          result, mode_count);
        return VK_PRESENT_MODE_FIFO_KHR;
    }

    g_autofree VkPresentModeKHR *modes =
        g_malloc_n(mode_count, sizeof(VkPresentModeKHR));
    result = vkGetPhysicalDeviceSurfacePresentModesKHR(
        r->physical_device, surface, &mode_count, modes);
    if (result != VK_SUCCESS || mode_count == 0) {
        IOS_SWAPCHAIN_LOG("present mode query failed result=%d count=%u; using fifo",
                          result, mode_count);
        return VK_PRESENT_MODE_FIFO_KHR;
    }

    if (ios_vk_swapchain_trace_enabled()) {
        fprintf(stderr, "xemu_ios: vk swapchain: present modes:");
        for (uint32_t i = 0; i < mode_count; i++) {
            fprintf(stderr, " %s", ios_present_mode_name(modes[i]));
        }
        fputc('\n', stderr);
        fflush(stderr);
    }

    VkPresentModeKHR forced_mode;
    const char *forced_name = getenv("XEMU_IOS_VK_PRESENT_MODE");
    if (ios_present_mode_from_name(forced_name, &forced_mode)) {
        if (ios_present_modes_contains(modes, mode_count, forced_mode)) {
            IOS_SWAPCHAIN_LOG("using requested present mode %s",
                              ios_present_mode_name(forced_mode));
            return forced_mode;
        }
        IOS_SWAPCHAIN_LOG("requested present mode %s not available",
                          forced_name);
    }

    const VkPresentModeKHR preferred[] = {
        VK_PRESENT_MODE_IMMEDIATE_KHR,
        VK_PRESENT_MODE_MAILBOX_KHR,
        VK_PRESENT_MODE_FIFO_RELAXED_KHR,
        VK_PRESENT_MODE_FIFO_KHR,
    };

    for (uint32_t i = 0; i < ARRAY_SIZE(preferred); i++) {
        if (ios_present_modes_contains(modes, mode_count, preferred[i])) {
            IOS_SWAPCHAIN_LOG("selected present mode %s",
                              ios_present_mode_name(preferred[i]));
            return preferred[i];
        }
    }

    return VK_PRESENT_MODE_FIFO_KHR;
}

static bool ios_xenios_presenter_enabled(void)
{
    static int enabled = -1;

    if (enabled < 0) {
        const char *env = getenv("XEMU_IOS_XENIOS_PRESENTER");
        enabled = !env || strcmp(env, "0") != 0;
    }

    return enabled;
}

static void ios_destroy_xenios_presenter_resources(PGRAPHState *pg)
{
    PGRAPHVkState *r = pg->vk_renderer_state;
    PGRAPHVkDisplayState *d = &r->display;

    for (uint32_t i = 0; i < XEMU_IOS_MAX_SWAPCHAIN_IMAGES; i++) {
        if (d->presenter_framebuffers[i] != VK_NULL_HANDLE) {
            vkDestroyFramebuffer(r->device, d->presenter_framebuffers[i], NULL);
            d->presenter_framebuffers[i] = VK_NULL_HANDLE;
        }
    }

    if (d->presenter_pipeline != VK_NULL_HANDLE) {
        vkDestroyPipeline(r->device, d->presenter_pipeline, NULL);
        d->presenter_pipeline = VK_NULL_HANDLE;
    }
    if (d->presenter_pipeline_layout != VK_NULL_HANDLE) {
        vkDestroyPipelineLayout(r->device, d->presenter_pipeline_layout, NULL);
        d->presenter_pipeline_layout = VK_NULL_HANDLE;
    }
    if (d->presenter_render_pass != VK_NULL_HANDLE) {
        vkDestroyRenderPass(r->device, d->presenter_render_pass, NULL);
        d->presenter_render_pass = VK_NULL_HANDLE;
    }
    if (d->presenter_descriptor_pool != VK_NULL_HANDLE) {
        vkDestroyDescriptorPool(r->device, d->presenter_descriptor_pool, NULL);
        d->presenter_descriptor_pool = VK_NULL_HANDLE;
        d->presenter_descriptor_set = VK_NULL_HANDLE;
    }
    if (d->presenter_descriptor_set_layout != VK_NULL_HANDLE) {
        vkDestroyDescriptorSetLayout(r->device,
                                     d->presenter_descriptor_set_layout,
                                     NULL);
        d->presenter_descriptor_set_layout = VK_NULL_HANDLE;
    }
    if (d->presenter_frag != NULL) {
        pgraph_vk_destroy_shader_module(r, d->presenter_frag);
        d->presenter_frag = NULL;
    }
    if (d->presenter_vert != NULL) {
        pgraph_vk_destroy_shader_module(r, d->presenter_vert);
        d->presenter_vert = NULL;
    }

    d->presenter_format = VK_FORMAT_UNDEFINED;
}

static void ios_create_xenios_presenter_resources(PGRAPHState *pg)
{
    PGRAPHVkState *r = pg->vk_renderer_state;
    PGRAPHVkDisplayState *d = &r->display;

    if (d->presenter_pipeline != VK_NULL_HANDLE &&
        d->presenter_format == d->swapchain_format) {
        return;
    }

    ios_destroy_xenios_presenter_resources(pg);

    d->presenter_vert = pgraph_vk_create_shader_module_from_glsl(
        r, VK_SHADER_STAGE_VERTEX_BIT, ios_presenter_vert_glsl);
    d->presenter_frag = pgraph_vk_create_shader_module_from_glsl(
        r, VK_SHADER_STAGE_FRAGMENT_BIT, ios_presenter_frag_glsl);

    VkDescriptorPoolSize pool_size = {
        .type = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .descriptorCount = 1,
    };
    VkDescriptorPoolCreateInfo pool_info = {
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .poolSizeCount = 1,
        .pPoolSizes = &pool_size,
        .maxSets = 1,
    };
    VK_CHECK(vkCreateDescriptorPool(r->device, &pool_info, NULL,
                                    &d->presenter_descriptor_pool));

    VkDescriptorSetLayoutBinding binding = {
        .binding = 0,
        .descriptorCount = 1,
        .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT,
    };
    VkDescriptorSetLayoutCreateInfo set_layout_info = {
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = 1,
        .pBindings = &binding,
    };
    VK_CHECK(vkCreateDescriptorSetLayout(r->device, &set_layout_info, NULL,
                                         &d->presenter_descriptor_set_layout));

    VkDescriptorSetAllocateInfo set_alloc_info = {
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = d->presenter_descriptor_pool,
        .descriptorSetCount = 1,
        .pSetLayouts = &d->presenter_descriptor_set_layout,
    };
    VK_CHECK(vkAllocateDescriptorSets(r->device, &set_alloc_info,
                                      &d->presenter_descriptor_set));

    VkAttachmentDescription attachment = {
        .format = d->swapchain_format,
        .samples = VK_SAMPLE_COUNT_1_BIT,
        .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .finalLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };
    VkAttachmentReference color_reference = {
        0, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
    };
    VkSubpassDescription subpass = {
        .pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color_reference,
    };
    VkSubpassDependency dependency = {
        .srcSubpass = VK_SUBPASS_EXTERNAL,
        .dstSubpass = 0,
        .srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
    };
    VkRenderPassCreateInfo render_pass_info = {
        .sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .attachmentCount = 1,
        .pAttachments = &attachment,
        .subpassCount = 1,
        .pSubpasses = &subpass,
        .dependencyCount = 1,
        .pDependencies = &dependency,
    };
    VK_CHECK(vkCreateRenderPass(r->device, &render_pass_info, NULL,
                                &d->presenter_render_pass));

    VkPipelineShaderStageCreateInfo shader_stages[] = {
        {
            .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = VK_SHADER_STAGE_VERTEX_BIT,
            .module = d->presenter_vert->module,
            .pName = "main",
        },
        {
            .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = VK_SHADER_STAGE_FRAGMENT_BIT,
            .module = d->presenter_frag->module,
            .pName = "main",
        },
    };
    VkPipelineVertexInputStateCreateInfo vertex_input = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
    };
    VkPipelineInputAssemblyStateCreateInfo input_assembly = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
    };
    VkPipelineViewportStateCreateInfo viewport_state = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .viewportCount = 1,
        .scissorCount = 1,
    };
    VkPipelineRasterizationStateCreateInfo rasterizer = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .polygonMode = VK_POLYGON_MODE_FILL,
        .cullMode = VK_CULL_MODE_NONE,
        .frontFace = VK_FRONT_FACE_CLOCKWISE,
        .lineWidth = 1.0f,
    };
    VkPipelineMultisampleStateCreateInfo multisampling = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .rasterizationSamples = VK_SAMPLE_COUNT_1_BIT,
    };
    VkPipelineColorBlendAttachmentState color_blend_attachment = {
        .colorWriteMask = VK_COLOR_COMPONENT_R_BIT |
                          VK_COLOR_COMPONENT_G_BIT |
                          VK_COLOR_COMPONENT_B_BIT |
                          VK_COLOR_COMPONENT_A_BIT,
        .blendEnable = VK_FALSE,
    };
    VkPipelineColorBlendStateCreateInfo color_blending = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .attachmentCount = 1,
        .pAttachments = &color_blend_attachment,
    };
    VkDynamicState dynamic_states[] = {
        VK_DYNAMIC_STATE_VIEWPORT,
        VK_DYNAMIC_STATE_SCISSOR,
    };
    VkPipelineDynamicStateCreateInfo dynamic_state = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .dynamicStateCount = ARRAY_SIZE(dynamic_states),
        .pDynamicStates = dynamic_states,
    };
    VkPushConstantRange push_constant_range = {
        .stageFlags = VK_SHADER_STAGE_VERTEX_BIT,
        .offset = 0,
        .size = sizeof(float) * 4,
    };
    VkPipelineLayoutCreateInfo pipeline_layout_info = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 1,
        .pSetLayouts = &d->presenter_descriptor_set_layout,
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = &push_constant_range,
    };
    VK_CHECK(vkCreatePipelineLayout(r->device, &pipeline_layout_info, NULL,
                                    &d->presenter_pipeline_layout));

    VkGraphicsPipelineCreateInfo pipeline_info = {
        .sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .stageCount = ARRAY_SIZE(shader_stages),
        .pStages = shader_stages,
        .pVertexInputState = &vertex_input,
        .pInputAssemblyState = &input_assembly,
        .pViewportState = &viewport_state,
        .pRasterizationState = &rasterizer,
        .pMultisampleState = &multisampling,
        .pColorBlendState = &color_blending,
        .pDynamicState = &dynamic_state,
        .layout = d->presenter_pipeline_layout,
        .renderPass = d->presenter_render_pass,
        .subpass = 0,
    };
    VK_CHECK(vkCreateGraphicsPipelines(r->device, r->vk_pipeline_cache, 1,
                                       &pipeline_info, NULL,
                                       &d->presenter_pipeline));

    for (uint32_t i = 0; i < d->swapchain_image_count; i++) {
        VkFramebufferCreateInfo framebuffer_info = {
            .sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .renderPass = d->presenter_render_pass,
            .attachmentCount = 1,
            .pAttachments = &d->swapchain_image_views[i],
            .width = d->swapchain_extent.width,
            .height = d->swapchain_extent.height,
            .layers = 1,
        };
        VK_CHECK(vkCreateFramebuffer(r->device, &framebuffer_info, NULL,
                                     &d->presenter_framebuffers[i]));
    }

    d->presenter_format = d->swapchain_format;
    IOS_SWAPCHAIN_LOG("iOS shader presenter created format=%d",
                      d->swapchain_format);
}

static void ios_destroy_swapchain(PGRAPHState *pg)
{
    PGRAPHVkState *r = pg->vk_renderer_state;
    PGRAPHVkDisplayState *d = &r->display;

    if (d->swapchain == VK_NULL_HANDLE &&
        d->swapchain_acquire_fence == VK_NULL_HANDLE) {
        return;
    }

    vkDeviceWaitIdle(r->device);

    ios_destroy_xenios_presenter_resources(pg);

    if (d->swapchain_acquire_fence != VK_NULL_HANDLE) {
        vkDestroyFence(r->device, d->swapchain_acquire_fence, NULL);
        d->swapchain_acquire_fence = VK_NULL_HANDLE;
    }

    for (uint32_t i = 0; i < d->swapchain_image_count; i++) {
        if (d->swapchain_image_views[i] != VK_NULL_HANDLE) {
            vkDestroyImageView(r->device, d->swapchain_image_views[i], NULL);
            d->swapchain_image_views[i] = VK_NULL_HANDLE;
        }
        d->swapchain_images[i] = VK_NULL_HANDLE;
        d->swapchain_image_layouts[i] = VK_IMAGE_LAYOUT_UNDEFINED;
    }
    d->swapchain_image_count = 0;

    if (d->swapchain != VK_NULL_HANDLE) {
        vkDestroySwapchainKHR(r->device, d->swapchain, NULL);
        d->swapchain = VK_NULL_HANDLE;
    }
}

static void ios_wait_present_command(PGRAPHState *pg)
{
    PGRAPHVkState *r = pg->vk_renderer_state;
    PGRAPHVkDisplayState *d = &r->display;

    if (!d->present_command_in_flight ||
        d->present_command_fence == VK_NULL_HANDLE) {
        return;
    }

    VK_CHECK(vkWaitForFences(r->device, 1, &d->present_command_fence,
                             VK_TRUE, UINT64_MAX));
    VK_CHECK(vkResetFences(r->device, 1, &d->present_command_fence));
    d->present_command_in_flight = false;
}

static void ios_create_present_command_resources(PGRAPHState *pg)
{
    PGRAPHVkState *r = pg->vk_renderer_state;
    PGRAPHVkDisplayState *d = &r->display;

    VkCommandBufferAllocateInfo alloc_info = {
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = r->command_pool,
        .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };
    VK_CHECK(vkAllocateCommandBuffers(r->device, &alloc_info,
                                      &d->present_command_buffer));

    VkFenceCreateInfo fence_info = {
        .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
    };
    VK_CHECK(vkCreateFence(r->device, &fence_info, NULL,
                           &d->present_command_fence));

    VkSemaphoreCreateInfo semaphore_info = {
        .sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    };
    VK_CHECK(vkCreateSemaphore(r->device, &semaphore_info, NULL,
                               &d->present_complete_semaphore));
}

static void ios_destroy_present_command_resources(PGRAPHState *pg)
{
    PGRAPHVkState *r = pg->vk_renderer_state;
    PGRAPHVkDisplayState *d = &r->display;

    ios_wait_present_command(pg);

    if (d->present_complete_semaphore != VK_NULL_HANDLE) {
        vkDestroySemaphore(r->device, d->present_complete_semaphore, NULL);
        d->present_complete_semaphore = VK_NULL_HANDLE;
    }
    if (d->present_command_fence != VK_NULL_HANDLE) {
        vkDestroyFence(r->device, d->present_command_fence, NULL);
        d->present_command_fence = VK_NULL_HANDLE;
    }
    if (d->present_command_buffer != VK_NULL_HANDLE) {
        vkFreeCommandBuffers(r->device, r->command_pool, 1,
                             &d->present_command_buffer);
        d->present_command_buffer = VK_NULL_HANDLE;
    }
}

static VkCommandBuffer ios_begin_present_command(PGRAPHState *pg)
{
    PGRAPHVkState *r = pg->vk_renderer_state;
    PGRAPHVkDisplayState *d = &r->display;

    ios_wait_present_command(pg);

    VK_CHECK(vkResetCommandBuffer(d->present_command_buffer, 0));

    VkCommandBufferBeginInfo begin_info = {
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };
    VK_CHECK(vkBeginCommandBuffer(d->present_command_buffer, &begin_info));

    return d->present_command_buffer;
}

static void ios_submit_present_command(PGRAPHState *pg, VkCommandBuffer cmd)
{
    PGRAPHVkState *r = pg->vk_renderer_state;
    PGRAPHVkDisplayState *d = &r->display;

    VK_CHECK(vkEndCommandBuffer(cmd));

    VkSubmitInfo submit_info = {
        .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .commandBufferCount = 1,
        .pCommandBuffers = &cmd,
        .signalSemaphoreCount = 1,
        .pSignalSemaphores = &d->present_complete_semaphore,
    };
    VK_CHECK(vkQueueSubmit(r->queue, 1, &submit_info,
                           d->present_command_fence));
    d->present_command_in_flight = true;
    nv2a_profile_inc_counter(NV2A_PROF_QUEUE_SUBMIT_AUX);
}

static bool ios_create_swapchain(PGRAPHState *pg, uint32_t width,
                                 uint32_t height)
{
    PGRAPHVkState *r = pg->vk_renderer_state;
    PGRAPHVkDisplayState *d = &r->display;
    VkSurfaceKHR surface = d->surface;

    if (surface == VK_NULL_HANDLE) {
        return false;
    }

    VkSurfaceCapabilitiesKHR caps;
    VkResult result = vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
        r->physical_device, surface, &caps);
    if (result != VK_SUCCESS) {
        IOS_SWAPCHAIN_LOG("surface capabilities failed result=%d", result);
        return false;
    }

    if (!(caps.supportedUsageFlags & VK_IMAGE_USAGE_TRANSFER_DST_BIT)) {
        IOS_SWAPCHAIN_LOG("surface does not support transfer-dst swapchain images");
        return false;
    }

    uint32_t format_count = 0;
    VK_CHECK(vkGetPhysicalDeviceSurfaceFormatsKHR(r->physical_device, surface,
                                                  &format_count, NULL));
    if (format_count == 0) {
        IOS_SWAPCHAIN_LOG("surface reported no formats");
        return false;
    }

    g_autofree VkSurfaceFormatKHR *formats =
        g_malloc_n(format_count, sizeof(VkSurfaceFormatKHR));
    VK_CHECK(vkGetPhysicalDeviceSurfaceFormatsKHR(r->physical_device, surface,
                                                  &format_count, formats));
    VkSurfaceFormatKHR surface_format =
        ios_choose_swapchain_format(formats, format_count);

    VkExtent2D extent = ios_clamp_swapchain_extent(caps, width, height);
    if (extent.width == 0 || extent.height == 0) {
        IOS_SWAPCHAIN_LOG("surface extent is empty");
        return false;
    }

    uint32_t image_count = caps.minImageCount + 1;
    if (caps.maxImageCount > 0) {
        image_count = MIN(image_count, caps.maxImageCount);
    }
    image_count = MIN(image_count, XEMU_IOS_MAX_SWAPCHAIN_IMAGES);

    VkImageUsageFlags usage = VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    if (caps.supportedUsageFlags & VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT) {
        usage |= VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    }
    VkPresentModeKHR present_mode = ios_choose_present_mode(pg, surface);

    VkSwapchainCreateInfoKHR create_info = {
        .sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = surface,
        .minImageCount = image_count,
        .imageFormat = surface_format.format,
        .imageColorSpace = surface_format.colorSpace,
        .imageExtent = extent,
        .imageArrayLayers = 1,
        .imageUsage = usage,
        .imageSharingMode = VK_SHARING_MODE_EXCLUSIVE,
        .preTransform = caps.currentTransform,
        .compositeAlpha = ios_choose_composite_alpha(caps.supportedCompositeAlpha),
        .presentMode = present_mode,
        .clipped = VK_TRUE,
    };

    ios_destroy_swapchain(pg);

    result = vkCreateSwapchainKHR(r->device, &create_info, NULL, &d->swapchain);
    if (result != VK_SUCCESS) {
        IOS_SWAPCHAIN_LOG("vkCreateSwapchainKHR failed result=%d", result);
        return false;
    }

    uint32_t actual_image_count = 0;
    VK_CHECK(vkGetSwapchainImagesKHR(r->device, d->swapchain,
                                     &actual_image_count, NULL));
    g_autofree VkImage *swapchain_images =
        g_malloc_n(actual_image_count, sizeof(VkImage));
    VK_CHECK(vkGetSwapchainImagesKHR(r->device, d->swapchain,
                                     &actual_image_count, swapchain_images));
    d->swapchain_image_count =
        MIN(actual_image_count, XEMU_IOS_MAX_SWAPCHAIN_IMAGES);
    memcpy(d->swapchain_images, swapchain_images,
           sizeof(VkImage) * d->swapchain_image_count);

    for (uint32_t i = 0; i < d->swapchain_image_count; i++) {
        VkImageViewCreateInfo view_info = {
            .sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = d->swapchain_images[i],
            .viewType = VK_IMAGE_VIEW_TYPE_2D,
            .format = surface_format.format,
            .subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT,
            .subresourceRange.levelCount = 1,
            .subresourceRange.layerCount = 1,
        };
        VK_CHECK(vkCreateImageView(r->device, &view_info, NULL,
                                   &d->swapchain_image_views[i]));
        d->swapchain_image_layouts[i] = VK_IMAGE_LAYOUT_UNDEFINED;
    }

    VkFenceCreateInfo fence_info = {
        .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
    };
    VK_CHECK(vkCreateFence(r->device, &fence_info, NULL,
                           &d->swapchain_acquire_fence));

    d->swapchain_format = surface_format.format;
    d->swapchain_color_space = surface_format.colorSpace;
    d->swapchain_extent = extent;
    if (ios_xenios_presenter_enabled()) {
        ios_create_xenios_presenter_resources(pg);
    }
    VkRect2D presenter_rect = ios_presenter_fit_rect(d);

    IOS_SWAPCHAIN_LOG("created images=%u extent=%ux%u display=%dx%d"
                      " aspect=%.4f widescreen=%d rect=%d,%d %ux%u"
                      " format=%d present=%s",
                      d->swapchain_image_count, extent.width, extent.height,
                      d->width, d->height, ios_presenter_aspect_ratio(d),
                      xemu_get_widescreen(),
                      presenter_rect.offset.x, presenter_rect.offset.y,
                      presenter_rect.extent.width, presenter_rect.extent.height,
                      surface_format.format,
                      ios_present_mode_name(present_mode));
    return true;
}

static void ios_transition_swapchain_image(VkCommandBuffer cmd, VkImage image,
                                           VkImageLayout old_layout,
                                           VkImageLayout new_layout)
{
    VkImageMemoryBarrier barrier = {
        .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
        .oldLayout = old_layout,
        .newLayout = new_layout,
        .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
        .image = image,
        .subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT,
        .subresourceRange.levelCount = 1,
        .subresourceRange.layerCount = 1,
    };
    VkPipelineStageFlags src_stage = VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
    VkPipelineStageFlags dst_stage = VK_PIPELINE_STAGE_TRANSFER_BIT;

    if (old_layout == VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL &&
        new_layout == VK_IMAGE_LAYOUT_PRESENT_SRC_KHR) {
        barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        barrier.dstAccessMask = 0;
        src_stage = VK_PIPELINE_STAGE_TRANSFER_BIT;
        dst_stage = VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT;
    } else if (old_layout == VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL &&
               new_layout == VK_IMAGE_LAYOUT_PRESENT_SRC_KHR) {
        barrier.srcAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
        barrier.dstAccessMask = 0;
        src_stage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
        dst_stage = VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT;
    } else if ((old_layout == VK_IMAGE_LAYOUT_UNDEFINED ||
                old_layout == VK_IMAGE_LAYOUT_PRESENT_SRC_KHR) &&
               new_layout == VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL) {
        barrier.srcAccessMask = 0;
        barrier.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        src_stage = old_layout == VK_IMAGE_LAYOUT_UNDEFINED ?
                        VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT :
                        VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT;
        dst_stage = VK_PIPELINE_STAGE_TRANSFER_BIT;
    } else if ((old_layout == VK_IMAGE_LAYOUT_UNDEFINED ||
                old_layout == VK_IMAGE_LAYOUT_PRESENT_SRC_KHR) &&
               new_layout == VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL) {
        barrier.srcAccessMask = 0;
        barrier.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
        src_stage = old_layout == VK_IMAGE_LAYOUT_UNDEFINED ?
                        VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT :
                        VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT;
        dst_stage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    } else {
        assert(!"unsupported swapchain layout transition");
    }

    vkCmdPipelineBarrier(cmd, src_stage, dst_stage, 0, 0, NULL, 0, NULL, 1,
                         &barrier);
}

static bool ios_swapchain_extent_matches(PGRAPHState *pg, uint32_t width,
                                         uint32_t height)
{
    PGRAPHVkState *r = pg->vk_renderer_state;
    PGRAPHVkDisplayState *d = &r->display;
    VkSurfaceCapabilitiesKHR caps;

    if (d->surface == VK_NULL_HANDLE || d->swapchain == VK_NULL_HANDLE) {
        return false;
    }

    VkResult result = vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
        r->physical_device, d->surface, &caps);
    if (result != VK_SUCCESS) {
        IOS_SWAPCHAIN_LOG("surface capabilities refresh failed result=%d", result);
        return true;
    }

    VkExtent2D extent = ios_clamp_swapchain_extent(caps, width, height);
    return extent.width == d->swapchain_extent.width &&
           extent.height == d->swapchain_extent.height;
}

static bool ios_begin_present_swapchain(PGRAPHState *pg, uint32_t *image_index)
{
    PGRAPHVkState *r = pg->vk_renderer_state;
    PGRAPHVkDisplayState *d = &r->display;

    if (!xemu_ios_vulkan_presenter_enabled() ||
        d->surface == VK_NULL_HANDLE ||
        d->image == VK_NULL_HANDLE) {
        return false;
    }

    if (d->swapchain != VK_NULL_HANDLE &&
        !ios_swapchain_extent_matches(pg, d->width, d->height)) {
        IOS_SWAPCHAIN_LOG("surface extent changed, recreating swapchain");
        ios_destroy_swapchain(pg);
    }

    if (d->swapchain == VK_NULL_HANDLE &&
        !ios_create_swapchain(pg, d->width, d->height)) {
        return false;
    }

    VkResult result = vkAcquireNextImageKHR(
        r->device, d->swapchain, UINT64_MAX, VK_NULL_HANDLE,
        d->swapchain_acquire_fence, image_index);

    if (result == VK_ERROR_OUT_OF_DATE_KHR) {
        ios_destroy_swapchain(pg);
        return false;
    }
    if (result != VK_SUCCESS && result != VK_SUBOPTIMAL_KHR) {
        IOS_SWAPCHAIN_LOG("vkAcquireNextImageKHR failed result=%d", result);
        return false;
    }

    VK_CHECK(vkWaitForFences(r->device, 1, &d->swapchain_acquire_fence,
                             VK_TRUE, UINT64_MAX));
    VK_CHECK(vkResetFences(r->device, 1, &d->swapchain_acquire_fence));

    if (*image_index >= d->swapchain_image_count) {
        IOS_SWAPCHAIN_LOG("acquired invalid image index=%u count=%u",
                          *image_index, d->swapchain_image_count);
        return false;
    }

    return true;
}

static void ios_record_present_swapchain(PGRAPHState *pg, VkCommandBuffer cmd,
                                         uint32_t image_index)
{
    PGRAPHVkState *r = pg->vk_renderer_state;
    PGRAPHVkDisplayState *d = &r->display;
    VkRect2D dst_rect = ios_presenter_fit_rect(d);
    bool full_frame =
        dst_rect.offset.x == 0 && dst_rect.offset.y == 0 &&
        dst_rect.extent.width == d->swapchain_extent.width &&
        dst_rect.extent.height == d->swapchain_extent.height;
    bool flip_x = ios_presenter_env_bool("XEMU_IOS_PRESENTER_FLIP_X", true);
    bool flip_y = ios_presenter_env_bool("XEMU_IOS_PRESENTER_FLIP_Y", true);

    pgraph_vk_transition_image_layout(pg, cmd, d->image,
                                      VK_FORMAT_R8G8B8A8_UNORM,
                                      VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                                      VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL);
    ios_transition_swapchain_image(cmd, d->swapchain_images[image_index],
                                   d->swapchain_image_layouts[image_index],
                                   VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);

    if (!full_frame) {
        VkClearColorValue clear_color = {
            .float32 = { 0.0f, 0.0f, 0.0f, 1.0f },
        };
        VkImageSubresourceRange clear_range = {
            .aspectMask = VK_IMAGE_ASPECT_COLOR_BIT,
            .levelCount = 1,
            .layerCount = 1,
        };
        vkCmdClearColorImage(cmd, d->swapchain_images[image_index],
                             VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                             &clear_color, 1, &clear_range);
    }

    VkImageBlit blit = {
        .srcSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT,
        .srcSubresource.layerCount = 1,
        .srcOffsets[0] = {
            flip_x ? d->width : 0,
            flip_y ? d->height : 0,
            0,
        },
        .srcOffsets[1] = {
            flip_x ? 0 : d->width,
            flip_y ? 0 : d->height,
            1,
        },
        .dstSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT,
        .dstSubresource.layerCount = 1,
        .dstOffsets[0] = { dst_rect.offset.x, dst_rect.offset.y, 0 },
        .dstOffsets[1] = {
            dst_rect.offset.x + (int32_t)dst_rect.extent.width,
            dst_rect.offset.y + (int32_t)dst_rect.extent.height,
            1,
        },
    };
    VkFilter filter =
        ios_presenter_env_bool("XEMU_IOS_PRESENTER_LINEAR_FILTER", true) ?
            VK_FILTER_LINEAR : VK_FILTER_NEAREST;

    vkCmdBlitImage(cmd,
                   d->image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                   d->swapchain_images[image_index],
                   VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                   1, &blit, filter);

    ios_transition_swapchain_image(cmd, d->swapchain_images[image_index],
                                   VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                                   VK_IMAGE_LAYOUT_PRESENT_SRC_KHR);
    pgraph_vk_transition_image_layout(pg, cmd, d->image,
                                      VK_FORMAT_R8G8B8A8_UNORM,
                                      VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                                      VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);

    d->swapchain_image_layouts[image_index] = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
}

static void ios_update_xenios_presenter_descriptor(PGRAPHState *pg)
{
    PGRAPHVkState *r = pg->vk_renderer_state;
    PGRAPHVkDisplayState *d = &r->display;

    VkDescriptorImageInfo image_info = {
        .imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        .imageView = d->image_view,
        .sampler = d->sampler,
    };
    VkWriteDescriptorSet descriptor_write = {
        .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = d->presenter_descriptor_set,
        .dstBinding = 0,
        .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .descriptorCount = 1,
        .pImageInfo = &image_info,
    };

    vkUpdateDescriptorSets(r->device, 1, &descriptor_write, 0, NULL);
}

static void ios_record_xenios_presenter(PGRAPHState *pg, VkCommandBuffer cmd,
                                        uint32_t image_index)
{
    PGRAPHVkState *r = pg->vk_renderer_state;
    PGRAPHVkDisplayState *d = &r->display;
    VkRect2D dst_rect = ios_presenter_fit_rect(d);
    bool flip_x = ios_presenter_env_bool("XEMU_IOS_PRESENTER_FLIP_X", true);
    bool flip_y = ios_presenter_env_bool("XEMU_IOS_PRESENTER_FLIP_Y", true);
    const float options[4] = {
        flip_x ? 1.0f : 0.0f,
        flip_y ? 1.0f : 0.0f,
        0.0f,
        0.0f,
    };

    ios_create_xenios_presenter_resources(pg);
    ios_update_xenios_presenter_descriptor(pg);

    ios_transition_swapchain_image(cmd, d->swapchain_images[image_index],
                                   d->swapchain_image_layouts[image_index],
                                   VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL);

    VkClearValue clear_value = {
        .color.float32 = { 0.0f, 0.0f, 0.0f, 1.0f },
    };
    VkRenderPassBeginInfo render_pass_begin_info = {
        .sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
        .renderPass = d->presenter_render_pass,
        .framebuffer = d->presenter_framebuffers[image_index],
        .renderArea.extent = d->swapchain_extent,
        .clearValueCount = 1,
        .pClearValues = &clear_value,
    };
    vkCmdBeginRenderPass(cmd, &render_pass_begin_info,
                         VK_SUBPASS_CONTENTS_INLINE);
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS,
                      d->presenter_pipeline);
    vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS,
                            d->presenter_pipeline_layout, 0, 1,
                            &d->presenter_descriptor_set, 0, NULL);
    vkCmdPushConstants(cmd, d->presenter_pipeline_layout,
                       VK_SHADER_STAGE_VERTEX_BIT, 0, sizeof(options),
                       options);

    VkViewport viewport = {
        .x = (float)dst_rect.offset.x,
        .y = (float)dst_rect.offset.y,
        .width = (float)dst_rect.extent.width,
        .height = (float)dst_rect.extent.height,
        .minDepth = 0.0f,
        .maxDepth = 1.0f,
    };
    vkCmdSetViewport(cmd, 0, 1, &viewport);

    VkRect2D scissor = {
        .offset = dst_rect.offset,
        .extent = dst_rect.extent,
    };
    vkCmdSetScissor(cmd, 0, 1, &scissor);

    vkCmdDraw(cmd, 3, 1, 0, 0);
    vkCmdEndRenderPass(cmd);

    ios_transition_swapchain_image(cmd, d->swapchain_images[image_index],
                                   VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                                   VK_IMAGE_LAYOUT_PRESENT_SRC_KHR);
    d->swapchain_image_layouts[image_index] = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
}

static void ios_end_present_swapchain(PGRAPHState *pg, uint32_t image_index,
                                      VkSemaphore wait_semaphore)
{
    PGRAPHVkState *r = pg->vk_renderer_state;
    PGRAPHVkDisplayState *d = &r->display;
    VkResult result;

    VkPresentInfoKHR present_info = {
        .sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .swapchainCount = 1,
        .pSwapchains = &d->swapchain,
        .pImageIndices = &image_index,
    };
    if (wait_semaphore != VK_NULL_HANDLE) {
        present_info.waitSemaphoreCount = 1;
        present_info.pWaitSemaphores = &wait_semaphore;
    }

    result = vkQueuePresentKHR(r->queue, &present_info);
    if (result == VK_ERROR_OUT_OF_DATE_KHR || result == VK_SUBOPTIMAL_KHR) {
        ios_destroy_swapchain(pg);
    } else if (result != VK_SUCCESS) {
        IOS_SWAPCHAIN_LOG("vkQueuePresentKHR failed result=%d", result);
    }
}
#endif

// FIXME: We may need to use two images. One for actually rendering display,
// and another for GL in the correct tiling mode

static void create_display_image(PGRAPHState *pg, int width, int height)
{
    PGRAPHVkState *r = pg->vk_renderer_state;
    PGRAPHVkDisplayState *d = &r->display;

    if (r->display.image != VK_NULL_HANDLE) {
        destroy_current_display_image(pg);
    }

    bool use_optimal_tiling = true;

#if HAVE_EXTERNAL_MEMORY
    const GLint gl_internal_format = GL_RGBA8;
    GLint num_tiling_types;
    glGetInternalformativ(GL_TEXTURE_2D, gl_internal_format,
                          GL_NUM_TILING_TYPES_EXT, 1, &num_tiling_types);
    // XXX: Apparently on AMD GL_OPTIMAL_TILING_EXT is reported to be
    // supported, but doesn't work? On nVidia, GL_LINEAR_TILING_EXT may not
    // be supported so we must use optimal. Default to optimal unless
    // linear is explicitly specified...
    GLint tiling_types[num_tiling_types];
    glGetInternalformativ(GL_TEXTURE_2D, gl_internal_format,
                          GL_TILING_TYPES_EXT, num_tiling_types, tiling_types);
    for (int i = 0; i < num_tiling_types; i++) {
        if (tiling_types[i] == GL_LINEAR_TILING_EXT) {
            use_optimal_tiling = false;
            break;
        }
    }
#endif

    VkImageUsageFlags image_usage =
        VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
#ifdef CONFIG_IOS
    if (xemu_ios_vulkan_presenter_enabled()) {
        image_usage |= VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
    }
#endif

    // Create image
    VkImageCreateInfo image_create_info = {
        .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = VK_IMAGE_TYPE_2D,
        .extent.width = width,
        .extent.height = height,
        .extent.depth = 1,
        .mipLevels = 1,
        .arrayLayers = 1,
        .format = VK_FORMAT_R8G8B8A8_UNORM,
        .tiling = use_optimal_tiling ? VK_IMAGE_TILING_OPTIMAL : VK_IMAGE_TILING_LINEAR,
        .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED,
        .usage = image_usage,
        .samples = VK_SAMPLE_COUNT_1_BIT,
        .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
    };

#if HAVE_EXTERNAL_MEMORY
    VkExternalMemoryImageCreateInfo external_memory_image_create_info = {
        .sType = VK_STRUCTURE_TYPE_EXTERNAL_MEMORY_IMAGE_CREATE_INFO,
#ifdef WIN32
        .handleTypes = VK_EXTERNAL_MEMORY_HANDLE_TYPE_OPAQUE_WIN32_BIT,
#else
        .handleTypes = VK_EXTERNAL_MEMORY_HANDLE_TYPE_OPAQUE_FD_BIT_KHR,
#endif
    };
    image_create_info.pNext = &external_memory_image_create_info;
#endif

    VK_CHECK(vkCreateImage(r->device, &image_create_info, NULL, &d->image));

    // Allocate and bind image memory
    VkMemoryRequirements memory_requirements;
    vkGetImageMemoryRequirements(r->device, d->image, &memory_requirements);

    VkMemoryAllocateInfo alloc_info = {
        .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = memory_requirements.size,
        .memoryTypeIndex =
            pgraph_vk_get_memory_type(pg, memory_requirements.memoryTypeBits,
                                      VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT),
    };

#if HAVE_EXTERNAL_MEMORY
    VkExportMemoryAllocateInfo export_memory_alloc_info = {
        .sType = VK_STRUCTURE_TYPE_EXPORT_MEMORY_ALLOCATE_INFO,
        .handleTypes =
#ifdef WIN32
            VK_EXTERNAL_MEMORY_HANDLE_TYPE_OPAQUE_WIN32_BIT_KHR
#else
            VK_EXTERNAL_MEMORY_HANDLE_TYPE_OPAQUE_FD_BIT
#endif
            ,
    };
    alloc_info.pNext = &export_memory_alloc_info;
#endif

    VK_CHECK(vkAllocateMemory(r->device, &alloc_info, NULL, &d->memory));
    VK_CHECK(vkBindImageMemory(r->device, d->image, d->memory, 0));

    // Create Image View
    VkImageViewCreateInfo image_view_create_info = {
        .sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = d->image,
        .viewType = VK_IMAGE_VIEW_TYPE_2D,
        .format = image_create_info.format,
        .subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT,
        .subresourceRange.levelCount = 1,
        .subresourceRange.layerCount = 1,
    };
    VK_CHECK(vkCreateImageView(r->device, &image_view_create_info, NULL,
                               &d->image_view));

#if HAVE_EXTERNAL_MEMORY

#ifdef WIN32

    VkMemoryGetWin32HandleInfoKHR handle_info = {
        .sType = VK_STRUCTURE_TYPE_MEMORY_GET_WIN32_HANDLE_INFO_KHR,
        .memory = d->memory,
        .handleType = VK_EXTERNAL_MEMORY_HANDLE_TYPE_OPAQUE_WIN32_BIT_KHR
    };
    VK_CHECK(vkGetMemoryWin32HandleKHR(r->device, &handle_info, &d->handle));

    glCreateMemoryObjectsEXT(1, &d->gl_memory_obj);
    glImportMemoryWin32HandleEXT(d->gl_memory_obj, memory_requirements.size, GL_HANDLE_TYPE_OPAQUE_WIN32_EXT, d->handle);
    assert(glGetError() == GL_NO_ERROR);

#else

    VkMemoryGetFdInfoKHR fd_info = {
        .sType = VK_STRUCTURE_TYPE_MEMORY_GET_FD_INFO_KHR,
        .memory = d->memory,
        .handleType = VK_EXTERNAL_MEMORY_HANDLE_TYPE_OPAQUE_FD_BIT,
    };
    VK_CHECK(vkGetMemoryFdKHR(r->device, &fd_info, &d->fd));

    glCreateMemoryObjectsEXT(1, &d->gl_memory_obj);
    glImportMemoryFdEXT(d->gl_memory_obj, memory_requirements.size,
                        GL_HANDLE_TYPE_OPAQUE_FD_EXT, d->fd);
    assert(glIsMemoryObjectEXT(d->gl_memory_obj));
    assert(glGetError() == GL_NO_ERROR);

#endif // WIN32

    glGenTextures(1, &d->gl_texture_id);
    glBindTexture(GL_TEXTURE_2D, d->gl_texture_id);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_TILING_EXT,
                    use_optimal_tiling ? GL_OPTIMAL_TILING_EXT :
                                         GL_LINEAR_TILING_EXT);
    glTexStorageMem2DEXT(GL_TEXTURE_2D, 1, gl_internal_format,
                         image_create_info.extent.width,
                         image_create_info.extent.height, d->gl_memory_obj, 0);
    assert(glGetError() == GL_NO_ERROR);

#endif // HAVE_EXTERNAL_MEMORY

    d->width = image_create_info.extent.width;
    d->height = image_create_info.extent.height;

    create_frame_buffer(pg);
}

static void update_descriptor_set(PGRAPHState *pg, SurfaceBinding *surface)
{
    PGRAPHVkState *r = pg->vk_renderer_state;

    VkDescriptorImageInfo image_infos[2];
    VkWriteDescriptorSet descriptor_writes[2];

    // Display surface
    image_infos[0] = (VkDescriptorImageInfo){
        .imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        .imageView = surface->image_view,
        .sampler = r->display.sampler,
    };
    descriptor_writes[0] = (VkWriteDescriptorSet){
        .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = r->display.descriptor_set,
        .dstBinding = 0,
        .dstArrayElement = 0,
        .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .descriptorCount = 1,
        .pImageInfo = &image_infos[0],
    };

    // FIXME: PVIDEO Overlay
    if (r->display.pvideo.state.enabled) {
        assert(r->display.pvideo.image_view != VK_NULL_HANDLE);
        assert(r->display.pvideo.sampler != VK_NULL_HANDLE);
        image_infos[1] = (VkDescriptorImageInfo){
            .imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            .imageView = r->display.pvideo.image_view,
            .sampler = r->display.pvideo.sampler,
        };
    } else {
        image_infos[1] = (VkDescriptorImageInfo){
            .imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            .imageView = r->dummy_texture.image_view,
            .sampler = r->dummy_texture.sampler,
        };
    }
    descriptor_writes[1] = (VkWriteDescriptorSet){
        .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = r->display.descriptor_set,
        .dstBinding = 1,
        .dstArrayElement = 0,
        .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .descriptorCount = 1,
        .pImageInfo = &image_infos[1],
    };

    vkUpdateDescriptorSets(r->device, ARRAY_SIZE(descriptor_writes),
                           descriptor_writes, 0, NULL);
}

static PvideoState get_pvideo_state(PGRAPHState *pg)
{
    NV2AState *d = container_of(pg, NV2AState, pgraph);
    PGRAPHVkState *r = pg->vk_renderer_state;
    PvideoState state = { 0 };

    // FIXME: This check against PVIDEO_SIZE_IN does not match HW behavior.
    // Many games seem to pass this value when initializing or tearing down
    // PVIDEO. On its own, this generally does not result in the overlay being
    // hidden, however there are certain games (e.g., Ultimate Beach Soccer)
    // that use an unknown mechanism to hide the overlay without explicitly
    // stopping it.
    // Since the value seems to be set to 0xFFFFFFFF only in cases where the
    // content is not valid, it is probably good enough to treat it as an
    // implicit stop.
    state.enabled = (d->pvideo.regs[NV_PVIDEO_BUFFER] & NV_PVIDEO_BUFFER_0_USE)
        && d->pvideo.regs[NV_PVIDEO_SIZE_IN] != 0xFFFFFFFF;
    if (!state.enabled) {
        return state;
    }

    state.base = d->pvideo.regs[NV_PVIDEO_BASE];
    state.limit = d->pvideo.regs[NV_PVIDEO_LIMIT];
    state.offset = d->pvideo.regs[NV_PVIDEO_OFFSET];

    state.pitch =
        GET_MASK(d->pvideo.regs[NV_PVIDEO_FORMAT], NV_PVIDEO_FORMAT_PITCH);
    state.format =
        GET_MASK(d->pvideo.regs[NV_PVIDEO_FORMAT], NV_PVIDEO_FORMAT_COLOR);

    /* TODO: support other color formats */
#ifdef CONFIG_IOS
    if (state.format != NV_PVIDEO_FORMAT_COLOR_LE_CR8YB8CB8YA8) {
        static uint64_t invalid_format_count;
        if (invalid_format_count++ < 32 || (invalid_format_count % 120) == 0) {
            IOS_PVIDEO_LOG(
                "disable unsupported format=0x%x base=0x%08" HWADDR_PRIx
                " limit=0x%08" HWADDR_PRIx " offset=0x%08" HWADDR_PRIx,
                state.format, state.base, state.limit, state.offset);
        }
        state.enabled = false;
        return state;
    }
#else
    assert(state.format == NV_PVIDEO_FORMAT_COLOR_LE_CR8YB8CB8YA8);
#endif

    state.in_width =
        GET_MASK(d->pvideo.regs[NV_PVIDEO_SIZE_IN], NV_PVIDEO_SIZE_IN_WIDTH);
    state.in_height =
        GET_MASK(d->pvideo.regs[NV_PVIDEO_SIZE_IN], NV_PVIDEO_SIZE_IN_HEIGHT);

    state.out_width =
        GET_MASK(d->pvideo.regs[NV_PVIDEO_SIZE_OUT], NV_PVIDEO_SIZE_OUT_WIDTH);
    state.out_height =
        GET_MASK(d->pvideo.regs[NV_PVIDEO_SIZE_OUT], NV_PVIDEO_SIZE_OUT_HEIGHT);

#ifdef CONFIG_IOS
    if (state.in_width <= 0 || state.in_height <= 0 ||
        state.out_width <= 0 || state.out_height <= 0 ||
        state.pitch <= 0) {
        static uint64_t invalid_size_count;
        if (invalid_size_count++ < 32 || (invalid_size_count % 120) == 0) {
            IOS_PVIDEO_LOG(
                "disable invalid raw size pitch=%d in=%dx%d out=%dx%d "
                "base=0x%08" HWADDR_PRIx " offset=0x%08" HWADDR_PRIx,
                state.pitch, state.in_width, state.in_height,
                state.out_width, state.out_height, state.base, state.offset);
        }
        state.enabled = false;
        return state;
    }
#endif

    state.in_s = GET_MASK(d->pvideo.regs[NV_PVIDEO_POINT_IN],
                        NV_PVIDEO_POINT_IN_S);
    state.in_t = GET_MASK(d->pvideo.regs[NV_PVIDEO_POINT_IN],
                        NV_PVIDEO_POINT_IN_T);

    uint32_t ds_dx = d->pvideo.regs[NV_PVIDEO_DS_DX];
    uint32_t dt_dy = d->pvideo.regs[NV_PVIDEO_DT_DY];
    state.scale_x = ds_dx == NV_PVIDEO_DIN_DOUT_UNITY ?
                        1.0f :
                        pvideo_calculate_scale(ds_dx, state.out_width);
    state.scale_y = dt_dy == NV_PVIDEO_DIN_DOUT_UNITY ?
                        1.0f :
                        pvideo_calculate_scale(dt_dy, state.out_height);

    // On HW, setting NV_PVIDEO_SIZE_IN larger than NV_PVIDEO_SIZE_OUT results
    // in them being capped to the output size, content is not scaled. This is
    // particularly important as NV_PVIDEO_SIZE_IN may be set to 0xFFFFFFFF
    // during initialization or teardown.
    if (state.in_width > state.out_width) {
        state.in_width = floorf((float)state.out_width * state.scale_x + 0.5f);
    }
    if (state.in_height > state.out_height) {
        state.in_height = floorf((float)state.out_height * state.scale_y + 0.5f);
    }

#ifdef CONFIG_IOS
    if (state.in_width <= 0 || state.in_height <= 0 ||
        state.out_width <= 0 || state.out_height <= 0 ||
        state.pitch <= 0) {
        static uint64_t invalid_size_count;
        if (invalid_size_count++ < 32 || (invalid_size_count % 120) == 0) {
            IOS_PVIDEO_LOG(
                "disable invalid size pitch=%d in=%dx%d out=%dx%d "
                "base=0x%08" HWADDR_PRIx " offset=0x%08" HWADDR_PRIx,
                state.pitch, state.in_width, state.in_height,
                state.out_width, state.out_height, state.base, state.offset);
        }
        state.enabled = false;
        return state;
    }

    uint64_t row_bytes = (uint64_t)state.in_width * 2;
    if ((uint64_t)state.pitch < row_bytes) {
        static uint64_t invalid_pitch_count;
        if (invalid_pitch_count++ < 32 || (invalid_pitch_count % 120) == 0) {
            IOS_PVIDEO_LOG(
                "disable short pitch pitch=%d row_bytes=%" PRIu64
                " in=%dx%d base=0x%08" HWADDR_PRIx
                " offset=0x%08" HWADDR_PRIx,
                state.pitch, row_bytes, state.in_width, state.in_height,
                state.base, state.offset);
        }
        state.enabled = false;
        return state;
    }

    if ((uint64_t)state.pitch > UINT64_MAX / (uint64_t)state.in_height) {
        static uint64_t overflow_count;
        if (overflow_count++ < 32 || (overflow_count % 120) == 0) {
            IOS_PVIDEO_LOG("disable span overflow pitch=%d height=%d",
                           state.pitch, state.in_height);
        }
        state.enabled = false;
        return state;
    }

    uint64_t span = (uint64_t)state.pitch * (uint64_t)state.in_height;
    uint64_t offset = (uint64_t)state.offset;
    uint64_t limit = (uint64_t)state.limit;
    if (offset > limit || span > limit - offset) {
        static uint64_t dma_bounds_count;
        if (dma_bounds_count++ < 32 || (dma_bounds_count % 120) == 0) {
            IOS_PVIDEO_LOG(
                "disable dma bounds base=0x%08" HWADDR_PRIx
                " limit=0x%08" HWADDR_PRIx " offset=0x%08" HWADDR_PRIx
                " span=%" PRIu64 " pitch=%d in=%dx%d",
                state.base, state.limit, state.offset, span, state.pitch,
                state.in_width, state.in_height);
        }
        state.enabled = false;
        return state;
    }

    uint64_t base = (uint64_t)state.base;
    uint64_t vram_size = memory_region_size(d->vram);
    if (base > vram_size || offset > vram_size - base ||
        span > vram_size - base - offset) {
        static uint64_t vram_bounds_count;
        if (vram_bounds_count++ < 32 || (vram_bounds_count % 120) == 0) {
            IOS_PVIDEO_LOG(
                "disable vram bounds base=0x%08" HWADDR_PRIx
                " offset=0x%08" HWADDR_PRIx " span=%" PRIu64
                " vram=%" PRIu64 " pitch=%d in=%dx%d",
                state.base, state.offset, span, vram_size, state.pitch,
                state.in_width, state.in_height);
        }
        state.enabled = false;
        return state;
    }

    if ((uint64_t)state.in_width > UINT64_MAX / (uint64_t)state.in_height ||
        (uint64_t)state.in_width * (uint64_t)state.in_height >
            UINT64_MAX / 4) {
        static uint64_t rgba_overflow_count;
        if (rgba_overflow_count++ < 32 || (rgba_overflow_count % 120) == 0) {
            IOS_PVIDEO_LOG("disable rgba overflow in=%dx%d",
                           state.in_width, state.in_height);
        }
        state.enabled = false;
        return state;
    }

    uint64_t rgba_size =
        (uint64_t)state.in_width * (uint64_t)state.in_height * 4;
    if (rgba_size > r->storage_buffers[BUFFER_STAGING_SRC].buffer_size) {
        static uint64_t staging_bounds_count;
        if (staging_bounds_count++ < 32 ||
            (staging_bounds_count % 120) == 0) {
            IOS_PVIDEO_LOG(
                "disable staging overflow rgba=%" PRIu64 " staging=%zu "
                "pitch=%d in=%dx%d",
                rgba_size, r->storage_buffers[BUFFER_STAGING_SRC].buffer_size,
                state.pitch, state.in_width, state.in_height);
        }
        state.enabled = false;
        return state;
    }
#endif

    state.out_x =
        GET_MASK(d->pvideo.regs[NV_PVIDEO_POINT_OUT], NV_PVIDEO_POINT_OUT_X);
    state.out_y =
        GET_MASK(d->pvideo.regs[NV_PVIDEO_POINT_OUT], NV_PVIDEO_POINT_OUT_Y);

    state.color_key_enabled =
        GET_MASK(d->pvideo.regs[NV_PVIDEO_FORMAT], NV_PVIDEO_FORMAT_DISPLAY);

    // Note: PVIDEO color keying ignores alpha.
    state.color_key = d->pvideo.regs[NV_PVIDEO_COLOR_KEY] & 0xFFFFFF;

#ifdef CONFIG_IOS
    static uint64_t enabled_log_count;
    if (enabled_log_count++ < 16 || (enabled_log_count % 120) == 0) {
        IOS_PVIDEO_LOG(
            "enabled #%llu base=0x%08" HWADDR_PRIx
            " limit=0x%08" HWADDR_PRIx " offset=0x%08" HWADDR_PRIx
            " pitch=%d format=0x%x in=%dx%d out=%dx%d pos=%d,%d "
            "scale=%.3f,%.3f",
            (unsigned long long)enabled_log_count, state.base, state.limit,
            state.offset, state.pitch, state.format, state.in_width,
            state.in_height, state.out_width, state.out_height, state.out_x,
            state.out_y, state.scale_x, state.scale_y);
    }
#endif

    assert(state.offset + state.pitch * state.in_height <= state.limit);
    hwaddr end = state.base + state.offset + state.pitch * state.in_height;
    assert(end <= memory_region_size(d->vram));

    return state;
}

static void update_uniforms(PGRAPHState *pg, SurfaceBinding *surface)
{
    NV2AState *d = container_of(pg, NV2AState, pgraph);
    PGRAPHVkState *r = pg->vk_renderer_state;
    ShaderUniformLayout *l = &r->display.display_frag->push_constants;

    int display_size_loc = uniform_index(l, "display_size");  // FIXME: Cache
    uniform2f(l, display_size_loc, r->display.width, r->display.height);

    VGADisplayParams vga_display_params;
    d->vga.get_params(&d->vga, &vga_display_params);
    int line_offset = vga_display_params.line_offset ?
                          surface->pitch / vga_display_params.line_offset :
                          1;
    int line_offset_loc = uniform_index(l, "line_offset");
    uniform1f(l, line_offset_loc, line_offset);

    PvideoState *pvideo = &r->display.pvideo.state;
    uniform1i(l, uniform_index(l, "pvideo_enable"), pvideo->enabled);
    if (pvideo->enabled) {
        uniform1i(l, uniform_index(l, "pvideo_color_key_enable"),
                  pvideo->color_key_enabled);
        uniform3f(
            l, uniform_index(l, "pvideo_color_key"),
            GET_MASK(pvideo->color_key, NV_PVIDEO_COLOR_KEY_RED) / 255.0,
            GET_MASK(pvideo->color_key, NV_PVIDEO_COLOR_KEY_GREEN) / 255.0,
            GET_MASK(pvideo->color_key, NV_PVIDEO_COLOR_KEY_BLUE) / 255.0);
        uniform2f(l, uniform_index(l, "pvideo_in_pos"), pvideo->in_s / 16.f,
                  pvideo->in_t / 8.f);
        uniform4f(l, uniform_index(l, "pvideo_pos"), pvideo->out_x,
                  pvideo->out_y, pvideo->out_width, pvideo->out_height);
        uniform4f(l, uniform_index(l, "pvideo_scale"), pvideo->scale_x,
                  pvideo->scale_y, 1.0f / pg->surface_scale_factor, 1.0);
    }
}

static void render_display(PGRAPHState *pg, SurfaceBinding *surface)
{
    NV2AState *d = container_of(pg, NV2AState, pgraph);
    PGRAPHVkState *r = pg->vk_renderer_state;
    PGRAPHVkDisplayState *disp = &r->display;

#ifdef CONFIG_IOS
    IOSDisplayPerfFrame perf = { 0 };
    bool perf_enabled = ios_display_perf_stats_enabled();
    gint64 perf_total_start_us = g_get_monotonic_time();

    if (xemu_ios_vulkan_presenter_enabled()) {
        gint64 wait_start_us = perf_enabled ? g_get_monotonic_time() : 0;
        ios_wait_present_command(pg);
        if (perf_enabled) {
            perf.wait_present_us += g_get_monotonic_time() - wait_start_us;
        }
    }
#endif

    if (r->in_command_buffer &&
        surface->draw_time >= r->command_buffer_start_time) {
#ifdef CONFIG_IOS
        perf.finish_presenting = true;
        gint64 finish_start_us = perf_enabled ? g_get_monotonic_time() : 0;
#endif
        pgraph_vk_finish(pg, VK_FINISH_REASON_PRESENTING);
#ifdef CONFIG_IOS
        if (perf_enabled) {
            perf.finish_presenting_us += g_get_monotonic_time() - finish_start_us;
        }
#endif
    }

#ifdef CONFIG_IOS
    perf.surface_upload_pending = qatomic_read(&surface->upload_pending);
    gint64 upload_surface_start_us = perf_enabled ? g_get_monotonic_time() : 0;
#endif
    pgraph_vk_upload_surface_data(d, surface, !tcg_enabled());
#ifdef CONFIG_IOS
    if (perf_enabled) {
        perf.surface_upload_us += g_get_monotonic_time() - upload_surface_start_us;
    }
#endif

    disp->pvideo.state = get_pvideo_state(pg);
    if (disp->pvideo.state.enabled) {
#ifdef CONFIG_IOS
        perf.pvideo_enabled = true;
        gint64 pvideo_start_us = perf_enabled ? g_get_monotonic_time() : 0;
#endif
        upload_pvideo_image(pg, disp->pvideo.state);
#ifdef CONFIG_IOS
        if (perf_enabled) {
            perf.pvideo_upload_us += g_get_monotonic_time() - pvideo_start_us;
        }
#endif
    }

    update_uniforms(pg, surface);
    update_descriptor_set(pg, surface);

#ifdef CONFIG_IOS
    bool ios_present_ready = false;
    uint32_t ios_present_image_index = 0;
    bool ios_native_present_command = false;
    if (xemu_ios_vulkan_presenter_enabled()) {
        gint64 acquire_start_us = perf_enabled ? g_get_monotonic_time() : 0;
        ios_present_ready =
            ios_begin_present_swapchain(pg, &ios_present_image_index);
        if (perf_enabled) {
            perf.acquire_us += g_get_monotonic_time() - acquire_start_us;
        }
        ios_native_present_command =
            ios_present_ready &&
            disp->present_command_buffer != VK_NULL_HANDLE &&
            disp->present_complete_semaphore != VK_NULL_HANDLE &&
            disp->present_command_fence != VK_NULL_HANDLE;
        perf.present_ready = ios_present_ready;
        perf.native_present_command = ios_native_present_command;
    }
#endif

#ifdef CONFIG_IOS
    gint64 command_start_us = perf_enabled ? g_get_monotonic_time() : 0;
    VkCommandBuffer cmd = ios_native_present_command ?
        ios_begin_present_command(pg) :
        pgraph_vk_begin_single_time_commands(pg);
#else
    VkCommandBuffer cmd = pgraph_vk_begin_single_time_commands(pg);
#endif
    pgraph_vk_begin_debug_marker(r, cmd, RGBA_YELLOW,
        "Display Surface %08"HWADDR_PRIx, surface->vram_addr);

    pgraph_vk_transition_image_layout(pg, cmd, surface->image,
                                      surface->host_fmt.vk_format,
                                      VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                                      VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
    pgraph_vk_transition_image_layout(
        pg, cmd, disp->image, VK_FORMAT_R8G8B8A8_UNORM,
        VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL);

    VkRenderPassBeginInfo render_pass_begin_info = {
        .sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
        .renderPass = disp->render_pass,
        .framebuffer = disp->framebuffer,
        .renderArea.extent.width = disp->width,
        .renderArea.extent.height = disp->height,
    };
    vkCmdBeginRenderPass(cmd, &render_pass_begin_info,
                         VK_SUBPASS_CONTENTS_INLINE);
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS,
                      disp->pipeline);

    vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS,
                            disp->pipeline_layout, 0, 1, &disp->descriptor_set,
                            0, NULL);

    VkViewport viewport = {
        .width = disp->width,
        .height = disp->height,
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };
    vkCmdSetViewport(cmd, 0, 1, &viewport);

    VkRect2D scissor = {
        .extent.width = disp->width,
        .extent.height = disp->height,
    };
    vkCmdSetScissor(cmd, 0, 1, &scissor);

    vkCmdPushConstants(cmd, disp->pipeline_layout, VK_SHADER_STAGE_FRAGMENT_BIT,
                       0, disp->display_frag->push_constants.total_size,
                       disp->display_frag->push_constants.allocation);

    vkCmdDraw(cmd, 3, 1, 0, 0);

    vkCmdEndRenderPass(cmd);

#if 0
    VkImageCopy region = {
        .srcSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT,
        .srcSubresource.layerCount = 1,
        .dstSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT,
        .dstSubresource.layerCount = 1,
        .extent.width = surface->width,
        .extent.height = surface->height,
        .extent.depth = 1,
    };
    pgraph_apply_scaling_factor(pg, &region.extent.width,
                                &region.extent.height);

    vkCmdCopyImage(cmd, surface->image,
                   VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, disp->image,
                   VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);
#endif

    pgraph_vk_transition_image_layout(pg, cmd, surface->image,
                                      surface->host_fmt.vk_format,
                                      VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                                      VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL);

    pgraph_vk_transition_image_layout(pg, cmd, disp->image,
                                      VK_FORMAT_R8G8B8_UNORM,
                                      VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                                      VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);

#ifdef CONFIG_IOS
    if (ios_present_ready) {
        if (ios_xenios_presenter_enabled()) {
            ios_record_xenios_presenter(pg, cmd, ios_present_image_index);
        } else {
            ios_record_present_swapchain(pg, cmd, ios_present_image_index);
        }
    }
#endif

    pgraph_vk_end_debug_marker(r, cmd);

#ifdef CONFIG_IOS
    if (ios_native_present_command) {
        if (perf_enabled) {
            perf.command_us += g_get_monotonic_time() - command_start_us;
        }
        gint64 submit_start_us = perf_enabled ? g_get_monotonic_time() : 0;
        ios_submit_present_command(pg, cmd);
        if (perf_enabled) {
            perf.submit_us += g_get_monotonic_time() - submit_start_us;
        }
    } else {
        if (perf_enabled) {
            perf.command_us += g_get_monotonic_time() - command_start_us;
        }
        gint64 submit_start_us = perf_enabled ? g_get_monotonic_time() : 0;
        pgraph_vk_end_single_time_commands(pg, cmd);
        if (perf_enabled) {
            perf.submit_us += g_get_monotonic_time() - submit_start_us;
        }
    }

    if (ios_present_ready) {
        VkSemaphore wait_semaphore = ios_native_present_command ?
            disp->present_complete_semaphore : VK_NULL_HANDLE;
        gint64 present_start_us = perf_enabled ? g_get_monotonic_time() : 0;
        ios_end_present_swapchain(pg, ios_present_image_index, wait_semaphore);
        if (perf_enabled) {
            perf.present_us += g_get_monotonic_time() - present_start_us;
        }
    }
    perf.total_us = g_get_monotonic_time() - perf_total_start_us;
    ios_display_stats_update(pg, &perf);
    if (perf_enabled) {
        ios_display_perf_stats_log(pg, &perf);
    }
#else
    pgraph_vk_end_single_time_commands(pg, cmd);
#endif

    nv2a_profile_inc_counter(NV2A_PROF_QUEUE_SUBMIT_5);

    disp->draw_time = surface->draw_time;
}

static void create_surface_sampler(PGRAPHState *pg)
{
    PGRAPHVkState *r = pg->vk_renderer_state;

    VkSamplerCreateInfo sampler_create_info = {
        .sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
        .magFilter = VK_FILTER_NEAREST,
        .minFilter = VK_FILTER_NEAREST,
        .addressModeU = VK_SAMPLER_ADDRESS_MODE_REPEAT,
        .addressModeV = VK_SAMPLER_ADDRESS_MODE_REPEAT,
        .addressModeW = VK_SAMPLER_ADDRESS_MODE_REPEAT,
        .anisotropyEnable = VK_FALSE,
        .borderColor = VK_BORDER_COLOR_INT_OPAQUE_WHITE,
        .unnormalizedCoordinates = VK_FALSE,
        .compareEnable = VK_FALSE,
        .compareOp = VK_COMPARE_OP_ALWAYS,
        .mipmapMode = VK_SAMPLER_MIPMAP_MODE_NEAREST,
    };

    VK_CHECK(vkCreateSampler(r->device, &sampler_create_info, NULL,
                             &r->display.sampler));
}

static void destroy_surface_sampler(PGRAPHState *pg)
{
    PGRAPHVkState *r = pg->vk_renderer_state;

    vkDestroySampler(r->device, r->display.sampler, NULL);
    r->display.sampler = VK_NULL_HANDLE;
}

void pgraph_vk_init_display(PGRAPHState *pg)
{
    create_descriptor_pool(pg);
    create_descriptor_set_layout(pg);
    create_descriptor_sets(pg);
    create_render_pass(pg);
    create_display_pipeline(pg);
    create_surface_sampler(pg);
#ifdef CONFIG_IOS
    ios_create_present_command_resources(pg);
#endif
}

void pgraph_vk_finalize_display(PGRAPHState *pg)
{
    PGRAPHVkState *r = pg->vk_renderer_state;

#ifdef CONFIG_IOS
    ios_destroy_present_command_resources(pg);
    ios_destroy_swapchain(pg);
#endif

    destroy_pvideo_image(pg);

    if (r->display.image != VK_NULL_HANDLE) {
        destroy_current_display_image(pg);
    }

    destroy_surface_sampler(pg);
    destroy_display_pipeline(pg);
    destroy_render_pass(pg);
    destroy_descriptor_set_layout(pg);
    destroy_descriptor_pool(pg);
}

void pgraph_vk_render_display(PGRAPHState *pg)
{
    NV2AState *d = container_of(pg, NV2AState, pgraph);
    PGRAPHVkState *r = pg->vk_renderer_state;

    VGADisplayParams vga_display_params;
    d->vga.get_params(&d->vga, &vga_display_params);

    SurfaceBinding *surface = pgraph_vk_surface_get_within(
        d, d->pcrtc.start + vga_display_params.line_offset);
    if (surface == NULL || !surface->color || !surface->width ||
        !surface->height) {
        return;
    }

    unsigned int width = 0, height = 0;
    d->vga.get_resolution(&d->vga, (int *)&width, (int *)&height);

    /* Adjust viewport height for interlaced mode, used only in 1080i */
    if (d->vga.cr[NV_PRMCIO_INTERLACE_MODE] != NV_PRMCIO_INTERLACE_MODE_DISABLED) {
        height *= 2;
    }

    pgraph_apply_scaling_factor(pg, &width, &height);

    PGRAPHVkDisplayState *disp = &r->display;
    bool display_image_recreated = false;
    if (!disp->image || disp->width != width || disp->height != height) {
        create_display_image(pg, width, height);
        display_image_recreated = true;
    }

#ifdef CONFIG_IOS
    PvideoState pvideo_state = get_pvideo_state(pg);
    if (xemu_ios_vulkan_presenter_enabled() &&
        !display_image_recreated &&
        disp->draw_time == surface->draw_time &&
        !pvideo_state.enabled) {
        return;
    }
#endif

    render_display(pg, surface);
}
