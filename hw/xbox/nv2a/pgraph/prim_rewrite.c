/*
 * Geforce NV2A PGRAPH primitive rewrite helpers
 *
 * Rewrites NV2A primitive assembly into explicit point, line, or triangle
 * lists for backends that need conservative host topologies.
 *
 * Copyright (c) 2026 Matt Borgerson
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 */

#include "qemu/osdep.h"
#include "prim_rewrite.h"

void pgraph_prim_rewrite_init(PrimRewriteBuf *buf)
{
    buf->data = NULL;
    buf->capacity = 0;
}

void pgraph_prim_rewrite_finalize(PrimRewriteBuf *buf)
{
    g_free(buf->data);
    buf->data = NULL;
    buf->capacity = 0;
}

static bool env_flag_enabled(const char *name, bool default_value)
{
    const char *env = getenv(name);

    if (!env || !env[0]) {
        return default_value;
    }

    return strcmp(env, "0") != 0 &&
           g_ascii_strcasecmp(env, "false") != 0 &&
           g_ascii_strcasecmp(env, "no") != 0 &&
           g_ascii_strcasecmp(env, "off") != 0;
}

bool pgraph_prim_rewrite_enabled(void)
{
    static int enabled = -1;

    if (enabled < 0) {
        enabled = env_flag_enabled("XEMU_NV2A_PRIM_REWRITE", true);
    }

    return enabled;
}

bool pgraph_prim_rewrite_debug_enabled(void)
{
    static int enabled = -1;

    if (enabled < 0) {
        enabled = env_flag_enabled("XEMU_NV2A_PRIM_REWRITE_DEBUG", false);
    }

    return enabled;
}

static void ensure_capacity(PrimRewriteBuf *buf, unsigned int needed)
{
    if (needed <= buf->capacity) {
        return;
    }

    unsigned int next = buf->capacity ? buf->capacity * 2 : 256;
    while (next < needed) {
        next *= 2;
    }

    buf->capacity = next;
    buf->data = g_realloc(buf->data, buf->capacity * sizeof(uint32_t));
}

enum ShaderPrimitiveMode
pgraph_prim_rewrite_get_output_mode(enum ShaderPrimitiveMode primitive_mode,
                                    enum ShaderPolygonMode polygon_mode)
{
    switch (primitive_mode) {
    case PRIM_TYPE_POINTS:
        return PRIM_TYPE_POINTS;
    case PRIM_TYPE_LINES:
    case PRIM_TYPE_LINE_STRIP:
    case PRIM_TYPE_LINE_LOOP:
        return PRIM_TYPE_LINES;
    case PRIM_TYPE_TRIANGLES:
    case PRIM_TYPE_TRIANGLE_STRIP:
    case PRIM_TYPE_TRIANGLE_FAN:
        return PRIM_TYPE_TRIANGLES;
    case PRIM_TYPE_QUADS:
    case PRIM_TYPE_QUAD_STRIP:
    case PRIM_TYPE_POLYGON:
        if (polygon_mode == POLY_MODE_POINT) {
            return PRIM_TYPE_POINTS;
        }
        return polygon_mode == POLY_MODE_LINE ? PRIM_TYPE_LINES :
                                                PRIM_TYPE_TRIANGLES;
    default:
        assert(!"Unexpected primitive mode");
        return primitive_mode;
    }
}

bool pgraph_prim_rewrite_needed(PrimAssemblyState state)
{
    if (!pgraph_prim_rewrite_enabled()) {
        return false;
    }

    switch (state.primitive_mode) {
    case PRIM_TYPE_POINTS:
        return false;
    case PRIM_TYPE_LINES:
    case PRIM_TYPE_TRIANGLES:
        return state.flat_shading && state.last_provoking;
    default:
        return true;
    }
}

static unsigned int max_output_indices(enum ShaderPrimitiveMode mode,
                                       enum ShaderPolygonMode polygon_mode,
                                       unsigned int input_count)
{
    switch (mode) {
    case PRIM_TYPE_POINTS:
        return input_count;
    case PRIM_TYPE_LINES:
        return input_count;
    case PRIM_TYPE_LINE_STRIP:
        return input_count >= 2 ? (input_count - 1) * 2 : 0;
    case PRIM_TYPE_LINE_LOOP:
        return input_count >= 2 ? input_count * 2 : 0;
    case PRIM_TYPE_TRIANGLES:
        return input_count;
    case PRIM_TYPE_TRIANGLE_STRIP:
    case PRIM_TYPE_TRIANGLE_FAN:
        return input_count >= 3 ? (input_count - 2) * 3 : 0;
    case PRIM_TYPE_QUADS:
        if (polygon_mode == POLY_MODE_POINT) {
            return input_count;
        }
        return polygon_mode == POLY_MODE_LINE ? (input_count / 4) * 8 :
                                                (input_count / 4) * 6;
    case PRIM_TYPE_QUAD_STRIP:
        if (polygon_mode == POLY_MODE_POINT) {
            return input_count;
        }
        if (input_count < 4) {
            return 0;
        }
        return polygon_mode == POLY_MODE_LINE ? ((input_count - 2) / 2) * 8 :
                                                ((input_count - 2) / 2) * 6;
    case PRIM_TYPE_POLYGON:
        if (polygon_mode == POLY_MODE_POINT) {
            return input_count;
        }
        if (polygon_mode == POLY_MODE_LINE) {
            return input_count >= 2 ? input_count * 2 : 0;
        }
        return input_count >= 3 ? (input_count - 2) * 3 : 0;
    default:
        return 0;
    }
}

static inline uint32_t idx_at(const uint32_t *idx, unsigned int i,
                              uint32_t base)
{
    return idx ? idx[i] : base + i;
}

static inline void emit_vertex(PrimRewrite *r, uint32_t v)
{
    r->indices[r->num_indices++] = v;
}

static inline void emit_line(PrimRewrite *r, uint32_t a, uint32_t b)
{
    emit_vertex(r, a);
    emit_vertex(r, b);
}

static inline void emit_line_pv(PrimRewrite *r, uint32_t a, uint32_t b,
                                uint32_t p)
{
    if (p == a) {
        emit_line(r, a, b);
    } else {
        emit_line(r, b, a);
    }
}

static inline void emit_tri(PrimRewrite *r, uint32_t a, uint32_t b, uint32_t c)
{
    emit_vertex(r, a);
    emit_vertex(r, b);
    emit_vertex(r, c);
}

static inline void emit_tri_pv(PrimRewrite *r, uint32_t a, uint32_t b,
                               uint32_t c, uint32_t p)
{
    if (p == a) {
        emit_tri(r, a, b, c);
    } else if (p == b) {
        emit_tri(r, b, c, a);
    } else {
        emit_tri(r, c, a, b);
    }
}

static void rewrite_points(PrimRewrite *r, const uint32_t *idx, uint32_t base,
                           unsigned int count)
{
    for (unsigned int i = 0; i < count; i++) {
        emit_vertex(r, idx_at(idx, i, base));
    }
}

static void rewrite_lines(PrimRewrite *r, const uint32_t *idx, uint32_t base,
                          unsigned int count, bool last_provoking)
{
    for (unsigned int i = 0; i + 1 < count; i += 2) {
        uint32_t v0 = idx_at(idx, i, base);
        uint32_t v1 = idx_at(idx, i + 1, base);
        emit_line_pv(r, v0, v1, last_provoking ? v1 : v0);
    }
}

static void rewrite_line_strip(PrimRewrite *r, const uint32_t *idx,
                               uint32_t base, unsigned int count,
                               bool last_provoking)
{
    for (unsigned int i = 0; i + 1 < count; i++) {
        uint32_t v0 = idx_at(idx, i, base);
        uint32_t v1 = idx_at(idx, i + 1, base);
        emit_line_pv(r, v0, v1, last_provoking ? v1 : v0);
    }
}

static void rewrite_line_loop(PrimRewrite *r, const uint32_t *idx,
                              uint32_t base, unsigned int count,
                              bool last_provoking)
{
    if (count < 2) {
        return;
    }

    rewrite_line_strip(r, idx, base, count, last_provoking);

    uint32_t v_last = idx_at(idx, count - 1, base);
    uint32_t v_first = idx_at(idx, 0, base);
    emit_line_pv(r, v_last, v_first, last_provoking ? v_first : v_last);
}

static void rewrite_triangles(PrimRewrite *r, const uint32_t *idx,
                              uint32_t base, unsigned int count,
                              bool last_provoking)
{
    for (unsigned int i = 0; i + 2 < count; i += 3) {
        uint32_t v0 = idx_at(idx, i, base);
        uint32_t v1 = idx_at(idx, i + 1, base);
        uint32_t v2 = idx_at(idx, i + 2, base);
        emit_tri_pv(r, v0, v1, v2, last_provoking ? v2 : v0);
    }
}

static void rewrite_triangle_strip(PrimRewrite *r, const uint32_t *idx,
                                   uint32_t base, unsigned int count,
                                   bool last_provoking)
{
    for (unsigned int i = 0; i + 2 < count; i++) {
        uint32_t v0 = idx_at(idx, i, base);
        uint32_t v1 = idx_at(idx, i + 1, base);
        uint32_t v2 = idx_at(idx, i + 2, base);
        uint32_t pv = last_provoking ? v2 : v0;

        if (i & 1) {
            emit_tri_pv(r, v1, v0, v2, pv);
        } else {
            emit_tri_pv(r, v0, v1, v2, pv);
        }
    }
}

static void rewrite_triangle_fan(PrimRewrite *r, const uint32_t *idx,
                                 uint32_t base, unsigned int count,
                                 bool last_provoking)
{
    if (count < 3) {
        return;
    }

    uint32_t hub = idx_at(idx, 0, base);

    for (unsigned int i = 0; i + 2 < count; i++) {
        uint32_t v1 = idx_at(idx, i + 1, base);
        uint32_t v2 = idx_at(idx, i + 2, base);
        emit_tri_pv(r, hub, v1, v2, last_provoking ? v2 : v1);
    }
}

static void rewrite_quads(PrimRewrite *r, const uint32_t *idx, uint32_t base,
                          unsigned int count, bool flat_shading)
{
    for (unsigned int i = 0; i + 3 < count; i += 4) {
        uint32_t v0 = idx_at(idx, i, base);
        uint32_t v1 = idx_at(idx, i + 1, base);
        uint32_t v2 = idx_at(idx, i + 2, base);
        uint32_t v3 = idx_at(idx, i + 3, base);

        if (flat_shading) {
            emit_tri(r, v3, v0, v1);
            emit_tri(r, v3, v1, v2);
        } else {
            emit_tri(r, v0, v1, v2);
            emit_tri(r, v0, v2, v3);
        }
    }
}

static void rewrite_quads_line(PrimRewrite *r, const uint32_t *idx,
                               uint32_t base, unsigned int count)
{
    for (unsigned int i = 0; i + 3 < count; i += 4) {
        uint32_t v0 = idx_at(idx, i, base);
        uint32_t v1 = idx_at(idx, i + 1, base);
        uint32_t v2 = idx_at(idx, i + 2, base);
        uint32_t v3 = idx_at(idx, i + 3, base);

        emit_line(r, v0, v1);
        emit_line(r, v1, v2);
        emit_line(r, v2, v3);
        emit_line(r, v3, v0);
    }
}

static void rewrite_quad_strip(PrimRewrite *r, const uint32_t *idx,
                               uint32_t base, unsigned int count,
                               bool flat_shading)
{
    for (unsigned int i = 0; i + 3 < count; i += 2) {
        uint32_t v0 = idx_at(idx, i, base);
        uint32_t v1 = idx_at(idx, i + 1, base);
        uint32_t v2 = idx_at(idx, i + 2, base);
        uint32_t v3 = idx_at(idx, i + 3, base);

        if (flat_shading) {
            emit_tri(r, v3, v2, v0);
            emit_tri(r, v3, v0, v1);
        } else {
            emit_tri(r, v0, v1, v2);
            emit_tri(r, v2, v1, v3);
        }
    }
}

static void rewrite_quad_strip_line(PrimRewrite *r, const uint32_t *idx,
                                    uint32_t base, unsigned int count)
{
    for (unsigned int i = 0; i + 3 < count; i += 2) {
        uint32_t v0 = idx_at(idx, i, base);
        uint32_t v1 = idx_at(idx, i + 1, base);
        uint32_t v2 = idx_at(idx, i + 2, base);
        uint32_t v3 = idx_at(idx, i + 3, base);

        emit_line(r, v0, v1);
        emit_line(r, v1, v3);
        emit_line(r, v3, v2);
        emit_line(r, v2, v0);
    }
}

static void rewrite_polygon(PrimRewrite *r, const uint32_t *idx,
                            uint32_t base, unsigned int count)
{
    if (count < 3) {
        return;
    }

    uint32_t hub = idx_at(idx, 0, base);

    for (unsigned int i = 0; i + 2 < count; i++) {
        emit_tri(r, hub, idx_at(idx, i + 1, base),
                 idx_at(idx, i + 2, base));
    }
}

static void rewrite_polygon_line(PrimRewrite *r, const uint32_t *idx,
                                 uint32_t base, unsigned int count)
{
    if (count < 2) {
        return;
    }

    rewrite_line_strip(r, idx, base, count, false);
    emit_line(r, idx_at(idx, count - 1, base), idx_at(idx, 0, base));
}

static void rewrite_indices(PrimRewrite *r, const PrimAssemblyState *state,
                            const uint32_t *idx, uint32_t base,
                            unsigned int count)
{
    switch (state->primitive_mode) {
    case PRIM_TYPE_POINTS:
        rewrite_points(r, idx, base, count);
        break;
    case PRIM_TYPE_LINES:
        rewrite_lines(r, idx, base, count, state->last_provoking);
        break;
    case PRIM_TYPE_LINE_STRIP:
        rewrite_line_strip(r, idx, base, count, state->last_provoking);
        break;
    case PRIM_TYPE_LINE_LOOP:
        rewrite_line_loop(r, idx, base, count, state->last_provoking);
        break;
    case PRIM_TYPE_TRIANGLES:
        rewrite_triangles(r, idx, base, count, state->last_provoking);
        break;
    case PRIM_TYPE_TRIANGLE_STRIP:
        rewrite_triangle_strip(r, idx, base, count, state->last_provoking);
        break;
    case PRIM_TYPE_TRIANGLE_FAN:
        rewrite_triangle_fan(r, idx, base, count, state->last_provoking);
        break;
    case PRIM_TYPE_QUADS:
        if (state->polygon_mode == POLY_MODE_POINT) {
            rewrite_points(r, idx, base, count);
        } else if (state->polygon_mode == POLY_MODE_LINE) {
            rewrite_quads_line(r, idx, base, count);
        } else {
            rewrite_quads(r, idx, base, count, state->flat_shading);
        }
        break;
    case PRIM_TYPE_QUAD_STRIP:
        if (state->polygon_mode == POLY_MODE_POINT) {
            rewrite_points(r, idx, base, count);
        } else if (state->polygon_mode == POLY_MODE_LINE) {
            rewrite_quad_strip_line(r, idx, base, count);
        } else {
            rewrite_quad_strip(r, idx, base, count, state->flat_shading);
        }
        break;
    case PRIM_TYPE_POLYGON:
        if (state->polygon_mode == POLY_MODE_POINT) {
            rewrite_points(r, idx, base, count);
        } else if (state->polygon_mode == POLY_MODE_LINE) {
            rewrite_polygon_line(r, idx, base, count);
        } else {
            rewrite_polygon(r, idx, base, count);
        }
        break;
    default:
        assert(!"Unexpected primitive mode");
        break;
    }
}

static PrimRewrite empty_result(PrimAssemblyState state)
{
    PrimRewrite result = {
        .output_mode = pgraph_prim_rewrite_get_output_mode(
            state.primitive_mode, state.polygon_mode),
        .flat_provoking_rewrite = state.flat_shading &&
                                  pgraph_prim_rewrite_needed(state),
    };

    return result;
}

PrimRewrite pgraph_prim_rewrite_ranges(PrimRewriteBuf *buf,
                                       PrimAssemblyState state,
                                       const int32_t *starts,
                                       const int32_t *counts,
                                       unsigned int num_ranges)
{
    PrimRewrite result = empty_result(state);

    if (!pgraph_prim_rewrite_needed(state)) {
        return result;
    }

    uint64_t total_max_output = 0;
    for (unsigned int i = 0; i < num_ranges; i++) {
        if (counts[i] <= 0) {
            continue;
        }
        total_max_output += max_output_indices(state.primitive_mode,
                                               state.polygon_mode,
                                               counts[i]);
    }

    assert(total_max_output <= UINT_MAX);
    if (total_max_output == 0) {
        return result;
    }

    ensure_capacity(buf, (unsigned int)total_max_output);
    result.indices = buf->data;

    for (unsigned int i = 0; i < num_ranges; i++) {
        if (counts[i] <= 0) {
            continue;
        }
        assert(starts[i] >= 0);
        rewrite_indices(&result, &state, NULL, starts[i], counts[i]);
    }

    assert(result.num_indices <= total_max_output);
    return result;
}

PrimRewrite pgraph_prim_rewrite_indexed(PrimRewriteBuf *buf,
                                        PrimAssemblyState state,
                                        const uint32_t *input_indices,
                                        unsigned int num_input_indices)
{
    PrimRewrite result = empty_result(state);

    if (!pgraph_prim_rewrite_needed(state)) {
        return result;
    }

    unsigned int max_output = max_output_indices(
        state.primitive_mode, state.polygon_mode, num_input_indices);
    if (max_output == 0) {
        return result;
    }

    ensure_capacity(buf, max_output);
    result.indices = buf->data;
    rewrite_indices(&result, &state, input_indices, 0, num_input_indices);

    assert(result.num_indices <= max_output);
    return result;
}

static const char *primitive_name(enum ShaderPrimitiveMode mode)
{
    switch (mode) {
    case PRIM_TYPE_POINTS: return "points";
    case PRIM_TYPE_LINES: return "lines";
    case PRIM_TYPE_LINE_LOOP: return "line_loop";
    case PRIM_TYPE_LINE_STRIP: return "line_strip";
    case PRIM_TYPE_TRIANGLES: return "triangles";
    case PRIM_TYPE_TRIANGLE_STRIP: return "triangle_strip";
    case PRIM_TYPE_TRIANGLE_FAN: return "triangle_fan";
    case PRIM_TYPE_QUADS: return "quads";
    case PRIM_TYPE_QUAD_STRIP: return "quad_strip";
    case PRIM_TYPE_POLYGON: return "polygon";
    default: return "unknown";
    }
}

void pgraph_prim_rewrite_debug_log(const char *source,
                                   PrimAssemblyState state,
                                   const PrimRewrite *rewrite,
                                   unsigned int input_count)
{
    if (!pgraph_prim_rewrite_debug_enabled()) {
        return;
    }

    fprintf(stderr,
            "xemu: prim_rewrite: %s original=%s rewritten=%s "
            "in=%u out=%u flat_pv=%d enabled=%d\n",
            source, primitive_name(state.primitive_mode),
            primitive_name(rewrite->output_mode), input_count,
            rewrite->num_indices, rewrite->flat_provoking_rewrite,
            pgraph_prim_rewrite_enabled());
}
