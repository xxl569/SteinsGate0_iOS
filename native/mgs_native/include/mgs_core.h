#ifndef MGS_CORE_H
#define MGS_CORE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct MgsEntry {
    uint32_t index;
    uint32_t compression;
    uint64_t offset;
    uint64_t size;
    uint64_t uncompressed_size;
    char name[224];
    char name_lower[224];
} MgsEntry;

typedef struct MgsArchive {
    char archive_name[64];
    char archive_lower[64];
    char file_path[1024];
    uint32_t count;
    MgsEntry *entries;
    uint32_t *sorted_indices; /* 按 name_lower 字典序排序，支持二分检索 */
} MgsArchive;

typedef struct MgsVfsState {
    MgsArchive *archives;
    uint32_t archive_count;
    uint32_t total_entries;
} MgsVfsState;

typedef struct MgsDdsImage {
    int32_t ok;
    uint32_t width;
    uint32_t height;
    int32_t is_l8;
    int32_t is_png;
    uint8_t *data;
    size_t data_size;
} MgsDdsImage;

typedef struct MgsLayResult {
    int32_t ok;
    int32_t width;
    int32_t height;
    int32_t origin_x;
    int32_t origin_y;
    uint8_t *rgba;
    size_t rgba_size;
} MgsLayResult;

void mgs_vfs_init(MgsVfsState *vfs);
void mgs_vfs_free(MgsVfsState *vfs);
int32_t mgs_vfs_mount(MgsVfsState *vfs, const char *dir_utf8);
const MgsArchive *mgs_vfs_find_archive(const MgsVfsState *vfs, const char *archive_name);
const MgsEntry *mgs_vfs_find_entry(const MgsVfsState *vfs, const char *archive_name, const char *entry_name);
int32_t mgs_vfs_read_entry(
    const MgsVfsState *vfs,
    const char *archive_name,
    const char *entry_name,
    uint8_t **out_buf,
    size_t *out_size
);

int32_t mgs_decode_image_buffer(const uint8_t *buf, size_t len, int32_t l8_alpha_only, MgsDdsImage *out);
void mgs_free_image(MgsDdsImage *img);

int32_t mgs_compose_lay_rgba(
    const uint8_t *lay_buf,
    size_t lay_len,
    const uint8_t *atlas_rgba,
    int32_t atlas_w,
    int32_t atlas_h,
    const int32_t *group_ids,
    int32_t group_count,
    MgsLayResult *out
);
void mgs_free_lay(MgsLayResult *res);

#ifdef __cplusplus
}
#endif

#endif /* MGS_CORE_H */
