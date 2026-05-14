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

#include "hw/xbox/nv2a/nv2a_int.h"
#include "renderer.h"

#if HAVE_EXTERNAL_MEMORY
#include "gloffscreen.h"

static GloContext *g_gl_context;
#endif

#ifdef CONFIG_IOS
uint64_t xemu_ios_framebuffer_download_generation;
bool xemu_ios_vulkan_presenter_enabled(void);

static bool ios_vk_renderer_trace_enabled(const char *name)
{
    const char *env = getenv(name);

    return env && strcmp(env, "0") != 0;
}

static gint64 ios_present_download_min_interval_us(void)
{
    static int min_interval_us = -1;

    if (min_interval_us < 0) {
        const char *env = getenv("XEMU_IOS_PRESENT_DOWNLOAD_FPS");
        char *end = NULL;
        long fps = env && *env ? strtol(env, &end, 10) : 0;

        if (!env || !*env || end == env || fps <= 0) {
            min_interval_us = 0;
        } else {
            fps = MIN(fps, 60);
            min_interval_us = 1000000 / fps;
        }
    }

    return min_interval_us;
}

#define IOS_VK_RENDERER_INIT_LOG(stage) \
    do { \
        if (ios_vk_renderer_trace_enabled("XEMU_IOS_VK_RENDERER_TRACE")) { \
            fprintf(stderr, "xemu-ios: vk renderer init: %s\n", stage); \
        } \
    } while (0)
#define IOS_VK_MEMORY_LOG(...) \
    do { \
        if (ios_vk_renderer_trace_enabled("XEMU_IOS_VK_MEMORY_TRACE")) { \
            fprintf(stderr, "xemu_ios: vk memory: " __VA_ARGS__); \
            fputc('\n', stderr); \
            fflush(stderr); \
        } \
    } while (0)
#else
#define IOS_VK_RENDERER_INIT_LOG(stage) \
    do {                                \
    } while (0)
#define IOS_VK_MEMORY_LOG(...) \
    do { \
    } while (0)
#define ios_present_download_min_interval_us() 0
#endif

static void early_context_init(void)
{
#if HAVE_EXTERNAL_MEMORY
    g_gl_context = glo_context_create();
#endif
}

static void pgraph_vk_init(NV2AState *d, Error **errp)
{
    PGRAPHState *pg = &d->pgraph;

    pg->vk_renderer_state = (PGRAPHVkState *)g_malloc0(sizeof(PGRAPHVkState));

#if HAVE_EXTERNAL_MEMORY
    glo_set_current(g_gl_context);
#endif

    pgraph_vk_debug_init();

    IOS_VK_RENDERER_INIT_LOG("instance");
    pgraph_vk_init_instance(pg, errp);
    if (*errp) {
        return;
    }

    IOS_VK_RENDERER_INIT_LOG("command buffers");
    pgraph_vk_init_command_buffers(pg);
    IOS_VK_RENDERER_INIT_LOG("buffers");
    pgraph_vk_init_buffers(d);
    IOS_VK_RENDERER_INIT_LOG("surfaces");
    pgraph_vk_init_surfaces(pg);
    IOS_VK_RENDERER_INIT_LOG("shaders");
    pgraph_vk_init_shaders(pg);
    IOS_VK_RENDERER_INIT_LOG("pipelines");
    pgraph_vk_init_pipelines(pg);
    IOS_VK_RENDERER_INIT_LOG("textures");
    pgraph_vk_init_textures(pg);
    IOS_VK_RENDERER_INIT_LOG("reports");
    pgraph_vk_init_reports(pg);
    IOS_VK_RENDERER_INIT_LOG("compute");
    pgraph_vk_init_compute(pg);
    IOS_VK_RENDERER_INIT_LOG("display");
    pgraph_vk_init_display(pg);

    IOS_VK_RENDERER_INIT_LOG("vertex ram upload");
    pgraph_vk_update_vertex_ram_buffer(&d->pgraph, 0, d->vram_ptr,
                                   memory_region_size(d->vram));

    IOS_VK_RENDERER_INIT_LOG("gpu properties");
    pgraph_vk_determine_gpu_properties(d);
    IOS_VK_RENDERER_INIT_LOG("complete");
}

static void pgraph_vk_finalize(NV2AState *d)
{
    PGRAPHState *pg = &d->pgraph;

    pgraph_vk_finalize_display(pg);
    pgraph_vk_finalize_compute(pg);
    pgraph_vk_finalize_reports(pg);
    pgraph_vk_finalize_textures(pg);
    pgraph_vk_finalize_pipelines(pg);
    pgraph_vk_finalize_shaders(pg);
    pgraph_vk_finalize_surfaces(pg);
    pgraph_vk_finalize_buffers(d);
    pgraph_vk_finalize_command_buffers(pg);
    pgraph_vk_finalize_instance(pg);

    g_free(pg->vk_renderer_state);
    pg->vk_renderer_state = NULL;
}

static void pgraph_vk_flush(NV2AState *d)
{
    PGRAPHState *pg = &d->pgraph;

    pgraph_vk_finish(pg, VK_FINISH_REASON_FLUSH);
    pgraph_vk_surface_flush(d);
    pgraph_vk_mark_textures_possibly_dirty(d, 0, memory_region_size(d->vram));
    pgraph_vk_update_vertex_ram_buffer(&d->pgraph, 0, d->vram_ptr,
                                       memory_region_size(d->vram));
    for (int i = 0; i < 4; i++) {
        pg->texture_dirty[i] = true;
    }

    /* FIXME: Flush more? */

    qatomic_set(&d->pgraph.flush_pending, false);
    qemu_event_set(&d->pgraph.flush_complete);
}

static void pgraph_vk_sync(NV2AState *d)
{
    PGRAPHState *pg = &d->pgraph;
    pgraph_vk_render_display(pg);

    qatomic_set(&d->pgraph.sync_pending, false);
    qemu_event_set(&d->pgraph.sync_complete);
}

static void pgraph_vk_process_pending(NV2AState *d)
{
    PGRAPHVkState *r = d->pgraph.vk_renderer_state;

    if (qatomic_read(&r->downloads_pending) ||
        qatomic_read(&r->download_dirty_surfaces_pending) ||
        qatomic_read(&d->pgraph.sync_pending) ||
        qatomic_read(&d->pgraph.flush_pending)
    ) {
        qemu_mutex_unlock(&d->pfifo.lock);
        qemu_mutex_lock(&d->pgraph.lock);
        if (qatomic_read(&r->downloads_pending)) {
            pgraph_vk_process_pending_downloads(d);
        }
        if (qatomic_read(&r->download_dirty_surfaces_pending)) {
            pgraph_vk_download_dirty_surfaces(d);
        }
        if (qatomic_read(&d->pgraph.sync_pending)) {
            pgraph_vk_sync(d);
        }
        if (qatomic_read(&d->pgraph.flush_pending)) {
            pgraph_vk_flush(d);
        }
        qemu_mutex_unlock(&d->pgraph.lock);
        qemu_mutex_lock(&d->pfifo.lock);
    }
}

static void pgraph_vk_flip_stall(NV2AState *d)
{
    pgraph_vk_finish(&d->pgraph, VK_FINISH_REASON_FLIP_STALL);
    pgraph_vk_debug_frame_terminator();
}

static void pgraph_vk_pre_savevm_trigger(NV2AState *d)
{
    qatomic_set(&d->pgraph.vk_renderer_state->download_dirty_surfaces_pending, true);
    qemu_event_reset(&d->pgraph.vk_renderer_state->dirty_surfaces_download_complete);
}

static void pgraph_vk_pre_savevm_wait(NV2AState *d)
{
    qemu_event_wait(&d->pgraph.vk_renderer_state->dirty_surfaces_download_complete);
}

static void pgraph_vk_pre_shutdown_trigger(NV2AState *d)
{
    // qatomic_set(&d->pgraph.vk_renderer_state->shader_cache_writeback_pending, true);
    // qemu_event_reset(&d->pgraph.vk_renderer_state->shader_cache_writeback_complete);
}

static void pgraph_vk_pre_shutdown_wait(NV2AState *d)
{
    // qemu_event_wait(&d->pgraph.vk_renderer_state->shader_cache_writeback_complete);   
}

static int pgraph_vk_get_framebuffer_surface(NV2AState *d)
{
    PGRAPHState *pg = &d->pgraph;
#if HAVE_EXTERNAL_MEMORY
    PGRAPHVkState *r = pg->vk_renderer_state;
#endif

    qemu_mutex_lock(&d->pfifo.lock);

    VGADisplayParams vga_display_params;
    d->vga.get_params(&d->vga, &vga_display_params);

    SurfaceBinding *surface = pgraph_vk_surface_get_within(
        d, d->pcrtc.start + vga_display_params.line_offset);
    if (surface == NULL || !surface->color) {
#ifdef CONFIG_IOS
    bool trace_framebuffer =
        ios_vk_renderer_trace_enabled("XEMU_IOS_FRAMEBUFFER_TRACE");
    static uint64_t ios_fb_miss_count;
    uint64_t miss = ++ios_fb_miss_count;
        if (trace_framebuffer && (miss <= 16 || (miss % 300) == 0)) {
            fprintf(stderr,
                    "xemu_ios: vk framebuffer miss #%" PRIu64
                    " start=0x%08" PRIx32 " line_offset=%d surface=%p color=%d\n",
                    miss, (uint32_t)d->pcrtc.start, vga_display_params.line_offset,
                    surface, surface != NULL && surface->color);
        }
#endif
        qemu_mutex_unlock(&d->pfifo.lock);
        return 0;
    }

    assert(surface->color);

#ifdef CONFIG_IOS
    bool trace_framebuffer =
        ios_vk_renderer_trace_enabled("XEMU_IOS_FRAMEBUFFER_TRACE");
    static uint64_t ios_fb_hit_count;
    uint64_t hit = ++ios_fb_hit_count;
    if (trace_framebuffer && (hit <= 16 || (hit % 120) == 0)) {
        fprintf(stderr,
                "xemu_ios: vk framebuffer hit #%" PRIu64
                " tex pending start=0x%08" PRIx32 " line_offset=%d surface=%p"
                " color=%d size=%ux%u pitch=%u vram=0x%08" HWADDR_PRIx "\n",
                hit, (uint32_t)d->pcrtc.start, vga_display_params.line_offset,
                surface, surface->color, surface->width, surface->height,
                surface->pitch, surface->vram_addr);
    }
#endif

    surface->frame_time = pg->frame_time;

#ifdef CONFIG_IOS
    if (xemu_ios_vulkan_presenter_enabled()) {
        qemu_event_reset(&d->pgraph.sync_complete);
        qatomic_set(&pg->sync_pending, true);
        pfifo_kick(d);
        qemu_mutex_unlock(&d->pfifo.lock);
        qemu_event_wait(&d->pgraph.sync_complete);
        return 0;
    }
#endif

#if HAVE_EXTERNAL_MEMORY
    qemu_event_reset(&d->pgraph.sync_complete);
    qatomic_set(&pg->sync_pending, true);
    pfifo_kick(d);
    qemu_mutex_unlock(&d->pfifo.lock);
    qemu_event_wait(&d->pgraph.sync_complete);
    return r->display.gl_texture_id;
#else
    bool downloaded = qatomic_read(&surface->draw_dirty);
#ifdef CONFIG_IOS
    static gint64 last_present_download_us;
    gint64 min_interval_us = ios_present_download_min_interval_us();

    if (downloaded && min_interval_us > 0) {
        gint64 now = g_get_monotonic_time();
        if (last_present_download_us &&
            now - last_present_download_us < min_interval_us) {
            qemu_mutex_unlock(&d->pfifo.lock);
            return 0;
        }
        last_present_download_us = now;
    }
#endif
    qemu_mutex_unlock(&d->pfifo.lock);
    pgraph_vk_wait_for_surface_download(surface);
    if (downloaded) {
        qatomic_inc(&xemu_ios_framebuffer_download_generation);
    }
    return 0;
#endif
}

static PGRAPHRenderer pgraph_vk_renderer = {
    .type = CONFIG_DISPLAY_RENDERER_VULKAN,
    .name = "Vulkan",
    .ops = {
        .init = pgraph_vk_init,
        .early_context_init = early_context_init,
        .finalize = pgraph_vk_finalize,
        .clear_report_value = pgraph_vk_clear_report_value,
        .clear_surface = pgraph_vk_clear_surface,
        .draw_begin = pgraph_vk_draw_begin,
        .draw_end = pgraph_vk_draw_end,
        .flip_stall = pgraph_vk_flip_stall,
        .flush_draw = pgraph_vk_flush_draw,
        .get_report = pgraph_vk_get_report,
        .image_blit = pgraph_vk_image_blit,
        .pre_savevm_trigger = pgraph_vk_pre_savevm_trigger,
        .pre_savevm_wait = pgraph_vk_pre_savevm_wait,
        .pre_shutdown_trigger = pgraph_vk_pre_shutdown_trigger,
        .pre_shutdown_wait = pgraph_vk_pre_shutdown_wait,
        .process_pending = pgraph_vk_process_pending,
        .process_pending_reports = pgraph_vk_process_pending_reports,
        .surface_update = pgraph_vk_surface_update,
        .set_surface_scale_factor = pgraph_vk_set_surface_scale_factor,
        .get_surface_scale_factor = pgraph_vk_get_surface_scale_factor,
        .get_framebuffer_surface = pgraph_vk_get_framebuffer_surface,
        .get_gpu_properties = pgraph_vk_get_gpu_properties,
    }
};

static void __attribute__((constructor)) register_renderer(void)
{
    pgraph_renderer_register(&pgraph_vk_renderer);
}

void pgraph_vk_check_memory_budget(PGRAPHState *pg)
{
#ifdef CONFIG_IOS
    PGRAPHVkState *r = pg->vk_renderer_state;
    static gint64 last_log_us;
    static gint64 last_trim_us;

    if (r == NULL || r->allocator == VK_NULL_HANDLE) {
        return;
    }

    gint64 now = g_get_monotonic_time();
    bool should_log = (last_log_us == 0) || (now - last_log_us > 2000000);

    VkPhysicalDeviceMemoryProperties const *props;
    vmaGetMemoryProperties(r->allocator, &props);

    g_autofree VmaBudget *budgets =
        g_malloc_n(props->memoryHeapCount, sizeof(VmaBudget));
    vmaGetHeapBudgets(r->allocator, budgets);

    int max_heap = -1;
    double max_ratio = 0.0;
    unsigned long long max_used = 0;
    unsigned long long max_budget = 0;

    for (uint32_t i = 0; i < props->memoryHeapCount; i++) {
        VmaBudget *b = &budgets[i];
        if (b->budget == 0) {
            continue;
        }

        double ratio = (double)b->statistics.allocationBytes /
                       (double)b->budget;
        if (ratio > max_ratio) {
            max_ratio = ratio;
            max_heap = (int)i;
            max_used = (unsigned long long)b->statistics.allocationBytes;
            max_budget = (unsigned long long)b->budget;
        }
    }

    bool near_budget = max_ratio > 0.70;
    bool texture_pressure = r->texture_cache.num_used > 768;
    bool can_trim = (last_trim_us == 0) || (now - last_trim_us > 1000000);

    if ((near_budget || texture_pressure) && can_trim) {
        IOS_VK_MEMORY_LOG("trim begin heap=%d used=%lluMB budget=%lluMB %.1f%% "
                          "textures=%d/%d pipelines=%d shaders=%d modules=%d",
                          max_heap, max_used / (1024 * 1024),
                          max_budget / (1024 * 1024), max_ratio * 100.0,
                          r->texture_cache.num_used,
                          r->texture_cache.num_used + r->texture_cache.num_free,
                          r->pipeline_cache.num_used,
                          r->shader_cache.num_used,
                          r->shader_module_cache.num_used);
        pgraph_vk_trim_texture_cache(pg);
        last_trim_us = now;
        should_log = true;
    }

    if (should_log) {
        IOS_VK_MEMORY_LOG("heap=%d used=%lluMB budget=%lluMB %.1f%% "
                          "textures=%d/%d pipelines=%d shaders=%d modules=%d",
                          max_heap, max_used / (1024 * 1024),
                          max_budget / (1024 * 1024), max_ratio * 100.0,
                          r->texture_cache.num_used,
                          r->texture_cache.num_used + r->texture_cache.num_free,
                          r->pipeline_cache.num_used,
                          r->shader_cache.num_used,
                          r->shader_module_cache.num_used);
        last_log_us = now;
    }
    return;
#endif

#if 0 // FIXME
    PGRAPHVkState *r = pg->vk_renderer_state;

    VkPhysicalDeviceMemoryProperties const *props;
    vmaGetMemoryProperties(r->allocator, &props);

    g_autofree VmaBudget *budgets = g_malloc_n(props->memoryHeapCount, sizeof(VmaBudget));
    vmaGetHeapBudgets(r->allocator, budgets);

    const float budget_threshold = 0.8;
    bool near_budget = false;

    for (int i = 0; i < props->memoryHeapCount; i++) {
        VmaBudget *b = &budgets[i];
        float use_to_budget_ratio =
            (double)b->statistics.allocationBytes / (double)b->budget;
        NV2A_VK_DPRINTF("Heap %d: used %lu/%lu MiB (%.2f%%)", i,
                        b->statistics.allocationBytes / (1024 * 1024),
                        b->budget / (1024 * 1024), use_to_budget_ratio * 100);
        near_budget |= use_to_budget_ratio > budget_threshold;
    }

    // If any heaps are near budget, free up some resources
    if (near_budget) {
        pgraph_vk_trim_texture_cache(pg);
    }
#endif

#if 0
    char *s;
    vmaBuildStatsString(r->allocator, &s, VK_TRUE);
    puts(s);
    vmaFreeStatsString(r->allocator, s);
#endif
}
