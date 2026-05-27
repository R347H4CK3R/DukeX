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

#ifndef HW_XBOX_NV2A_PGRAPH_PRIM_REWRITE_H
#define HW_XBOX_NV2A_PGRAPH_PRIM_REWRITE_H

#include <stdbool.h>
#include <stdint.h>

#include "vsh_regs.h"

typedef struct PrimRewriteBuf {
    uint32_t *data;
    unsigned int capacity;
} PrimRewriteBuf;

typedef struct PrimRewrite {
    uint32_t *indices;
    unsigned int num_indices;
    enum ShaderPrimitiveMode output_mode;
    bool flat_provoking_rewrite;
} PrimRewrite;

typedef struct PrimAssemblyState {
    enum ShaderPrimitiveMode primitive_mode;
    enum ShaderPolygonMode polygon_mode;
    bool last_provoking;
    bool flat_shading;
} PrimAssemblyState;

void pgraph_prim_rewrite_init(PrimRewriteBuf *buf);
void pgraph_prim_rewrite_finalize(PrimRewriteBuf *buf);

bool pgraph_prim_rewrite_enabled(void);
bool pgraph_prim_rewrite_debug_enabled(void);

enum ShaderPrimitiveMode
pgraph_prim_rewrite_get_output_mode(enum ShaderPrimitiveMode primitive_mode,
                                    enum ShaderPolygonMode polygon_mode);
bool pgraph_prim_rewrite_needed(PrimAssemblyState state);

PrimRewrite pgraph_prim_rewrite_indexed(PrimRewriteBuf *buf,
                                        PrimAssemblyState state,
                                        const uint32_t *input_indices,
                                        unsigned int num_input_indices);

PrimRewrite pgraph_prim_rewrite_ranges(PrimRewriteBuf *buf,
                                       PrimAssemblyState state,
                                       const int32_t *starts,
                                       const int32_t *counts,
                                       unsigned int num_ranges);

static inline PrimRewrite pgraph_prim_rewrite_sequential(PrimRewriteBuf *buf,
                                                         PrimAssemblyState state,
                                                         int32_t start,
                                                         int32_t count)
{
    return pgraph_prim_rewrite_ranges(buf, state, &start, &count, 1);
}

void pgraph_prim_rewrite_debug_log(const char *source,
                                   PrimAssemblyState state,
                                   const PrimRewrite *rewrite,
                                   unsigned int input_count);

#endif
