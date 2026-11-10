// Differential harness for roaring_bitmap_rank_many(): the header documents it as the bulk form of
// roaring_bitmap_rank ("puts rank value of each element in [begin .. end) to ans[]"), so every output
// slot must equal roaring_bitmap_rank() of the matching input.
//
// Input: byte 0 = bitmap word count (low 6 bits), bit 6 = add ranges instead of points, bit 7 = run_optimize;
// then little-endian uint32 words: the first `count` build the bitmap, the rest are the (sorted) queries.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "roaring/roaring.h"

#define MAX_QUERIES 1024

static int cmp_u32(const void *a, const void *b) {
    uint32_t x = *(const uint32_t *)a, y = *(const uint32_t *)b;
    return (x > y) - (x < y);
}

static uint32_t word_at(const uint8_t *p) {
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 |
           (uint32_t)p[3] << 24;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size < 1) return -1;
    uint8_t flags = data[0];
    size_t nwords = (size - 1) / 4;
    size_t nbuild = flags & 0x3f;
    if (nbuild > nwords) nbuild = nwords;
    size_t nq = nwords - nbuild;
    if (nq > MAX_QUERIES) nq = MAX_QUERIES;

    roaring_bitmap_t *bm = roaring_bitmap_create();
    for (size_t i = 0; i < nbuild; i++) {
        uint32_t w = word_at(data + 1 + 4 * i);
        if (flags & 0x40) {
            uint64_t len = (w >> 20) & 0xfff;
            roaring_bitmap_add_range_closed(bm, w, w + len < w ? UINT32_MAX : (uint32_t)(w + len));
        } else {
            roaring_bitmap_add(bm, w);
        }
    }
    if (flags & 0x80) roaring_bitmap_run_optimize(bm);

    uint32_t *queries = malloc((nq ? nq : 1) * sizeof(uint32_t));
    uint64_t *ranks = malloc((nq ? nq : 1) * sizeof(uint64_t));
    for (size_t i = 0; i < nq; i++)
        queries[i] = word_at(data + 1 + 4 * (nbuild + i));
    qsort(queries, nq, sizeof(uint32_t), cmp_u32);
    memset(ranks, 0xff, (nq ? nq : 1) * sizeof(uint64_t));  // rank <= 2^32, so this never reads as an answer

    roaring_bitmap_rank_many(bm, queries, queries + nq, ranks);

    for (size_t i = 0; i < nq; i++) {
        uint64_t want = roaring_bitmap_rank(bm, queries[i]);
        if (ranks[i] != want) {
            fprintf(stderr, "rank_many[%zu] of %u = %llu, rank = %llu\n", i,
                    queries[i], (unsigned long long)ranks[i],
                    (unsigned long long)want);
            abort();
        }
    }
    free(ranks);
    free(queries);
    roaring_bitmap_free(bm);
    return 0;
}
