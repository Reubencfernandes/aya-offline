/* Dump all GGUF metadata keys and types */
#include "gguf.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum gguf_vtype {
    GGUF_TYPE_UINT8=0, GGUF_TYPE_INT8=1, GGUF_TYPE_UINT16=2, GGUF_TYPE_INT16=3,
    GGUF_TYPE_UINT32=4, GGUF_TYPE_INT32=5, GGUF_TYPE_FLOAT32=6, GGUF_TYPE_BOOL=7,
    GGUF_TYPE_STRING=8, GGUF_TYPE_ARRAY=9, GGUF_TYPE_UINT64=10, GGUF_TYPE_INT64=11,
    GGUF_TYPE_FLOAT64=12,
};

typedef struct { uint8_t *p; } reader2_t;
static uint32_t rd2_u32(reader2_t *r) { uint32_t v; memcpy(&v, r->p, 4); r->p += 4; return v; }
static uint64_t rd2_u64(reader2_t *r) { uint64_t v; memcpy(&v, r->p, 8); r->p += 8; return v; }
static float    rd2_f32(reader2_t *r) { float    v; memcpy(&v, r->p, 4); r->p += 4; return v; }

static char *rd2_string(reader2_t *r) {
    uint64_t len = rd2_u64(r);
    char *s = malloc(len + 1);
    memcpy(s, r->p, len);
    s[len] = '\0';
    r->p += len;
    return s;
}

static void skip2_value(reader2_t *r, int type) {
    switch (type) {
        case GGUF_TYPE_UINT8: case GGUF_TYPE_INT8: case GGUF_TYPE_BOOL: r->p += 1; break;
        case GGUF_TYPE_UINT16: case GGUF_TYPE_INT16: r->p += 2; break;
        case GGUF_TYPE_UINT32: case GGUF_TYPE_INT32: case GGUF_TYPE_FLOAT32: r->p += 4; break;
        case GGUF_TYPE_UINT64: case GGUF_TYPE_INT64: case GGUF_TYPE_FLOAT64: r->p += 8; break;
        case GGUF_TYPE_STRING: { uint64_t len = rd2_u64(r); r->p += len; } break;
        case GGUF_TYPE_ARRAY: {
            uint32_t et = rd2_u32(r); uint64_t c = rd2_u64(r);
            for (uint64_t i = 0; i < c; i++) skip2_value(r, et);
        } break;
    }
}

int main(int argc, char **argv) {
    if (argc < 2) return 1;

#ifdef _WIN32
    #include <windows.h>
    HANDLE hf = CreateFileA(argv[1], GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
    LARGE_INTEGER sz; GetFileSizeEx(hf, &sz);
    HANDLE hm = CreateFileMappingA(hf, NULL, PAGE_READONLY, 0, 0, NULL);
    uint8_t *data = (uint8_t*)MapViewOfFile(hm, FILE_MAP_READ, 0, 0, 0);
    CloseHandle(hm); CloseHandle(hf);
#endif

    reader2_t r = { .p = data };
    uint32_t magic = rd2_u32(&r);
    printf("magic: 0x%08X\n", magic);
    uint32_t version = rd2_u32(&r);
    uint64_t n_tensors = rd2_u64(&r);
    uint64_t n_metadata = rd2_u64(&r);
    printf("version=%u tensors=%llu metadata=%llu\n", version,
           (unsigned long long)n_tensors, (unsigned long long)n_metadata);

    for (uint64_t i = 0; i < n_metadata; i++) {
        char *key = rd2_string(&r);
        uint32_t vtype = rd2_u32(&r);

        printf("[%llu] key='%s' type=%u", (unsigned long long)i, key, vtype);

        if (vtype == GGUF_TYPE_UINT32) {
            uint32_t v = rd2_u32(&r);
            printf(" value=%u\n", v);
        } else if (vtype == GGUF_TYPE_INT32) {
            int32_t v; memcpy(&v, r.p, 4); r.p += 4;
            printf(" value=%d\n", v);
        } else if (vtype == GGUF_TYPE_FLOAT32) {
            float v = rd2_f32(&r);
            printf(" value=%f\n", v);
        } else if (vtype == GGUF_TYPE_STRING) {
            char *v = rd2_string(&r);
            printf(" value='%.80s'\n", v);
            free(v);
        } else if (vtype == GGUF_TYPE_ARRAY) {
            uint32_t et = rd2_u32(&r);
            uint64_t cnt = rd2_u64(&r);
            printf(" array[%u x %llu]\n", et, (unsigned long long)cnt);
            for (uint64_t j = 0; j < cnt; j++) skip2_value(&r, et);
        } else if (vtype == GGUF_TYPE_UINT64) {
            uint64_t v = rd2_u64(&r);
            printf(" value=%llu\n", (unsigned long long)v);
        } else {
            printf("\n");
            skip2_value(&r, vtype);
        }
        free(key);
    }
    return 0;
}
