/*
 * MAGES. / 5pb. 原生资产解码核心 (MPK v2, DDS DXT1/DXT3/DXT5/BGRA/L8, PNG 识别, .lay 瓦片合成)
 * 纯 C11 零外部依赖实现，支持 Windows x86_64 DLL 与 iOS arm64 静态库。
 */

#include "mgs_core.h"

#include <ctype.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#include <dirent.h>
#include <sys/stat.h>
#endif

/* ==================== 基础字节序与路径工具 ==================== */

static inline uint16_t rd_u16(const uint8_t *p) {
    return (uint16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8));
}

static inline uint32_t rd_u32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static inline uint64_t rd_u64(const uint8_t *p) {
    uint64_t lo = (uint64_t)rd_u32(p);
    uint64_t hi = (uint64_t)rd_u32(p + 4);
    return lo | (hi << 32);
}

static inline uint32_t rd_u32_be(const uint8_t *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

static inline float rd_f32(const uint8_t *p) {
    uint32_t u = rd_u32(p);
    float f = 0.0f;
    memcpy(&f, &u, sizeof(f));
    return f;
}

static void str_to_lower_buf(const char *src, char *dst, size_t dst_cap) {
    if (!dst || dst_cap == 0) return;
    if (!src) {
        dst[0] = '\0';
        return;
    }
    size_t i = 0;
    for (; src[i] != '\0' && i + 1 < dst_cap; i++) {
        dst[i] = (char)tolower((unsigned char)src[i]);
    }
    dst[i] = '\0';
}

static int ci_strcmp(const char *a, const char *b) {
    for (;;) {
        int ca = tolower((unsigned char)*a);
        int cb = tolower((unsigned char)*b);
        if (ca != cb) return ca - cb;
        if (ca == 0) return 0;
        a++;
        b++;
    }
}

static int ends_with_ci(const char *s, const char *suffix) {
    size_t sl = strlen(s);
    size_t tl = strlen(suffix);
    if (sl < tl) return 0;
    return ci_strcmp(s + sl - tl, suffix) == 0;
}

static FILE *open_rb_utf8(const char *path_utf8) {
#ifdef _WIN32
    int wlen = MultiByteToWideChar(CP_UTF8, 0, path_utf8, -1, NULL, 0);
    if (wlen <= 0) return NULL;
    wchar_t *wpath = (wchar_t *)malloc((size_t)wlen * sizeof(wchar_t));
    if (!wpath) return NULL;
    MultiByteToWideChar(CP_UTF8, 0, path_utf8, -1, wpath, wlen);
    FILE *fp = _wfopen(wpath, L"rb");
    free(wpath);
    return fp;
#else
    return fopen(path_utf8, "rb");
#endif
}

static int seek_u64(FILE *fp, uint64_t offset) {
#ifdef _WIN32
    return _fseeki64(fp, (__int64)offset, SEEK_SET) == 0 ? 0 : -1;
#else
    return fseeko(fp, (off_t)offset, SEEK_SET) == 0 ? 0 : -1;
#endif
}

/* ==================== 极简 RFC1950/1951 Inflate 解压器（zlib 兜底） ==================== */

typedef struct {
    const uint8_t *src;
    size_t len;
    size_t byte_pos;
    uint32_t bit_buf;
    int32_t bit_cnt;
} BitStream;

typedef struct {
    int16_t count[16];
    int16_t symbol[288];
} HuffTable;

static int bs_need_bits(BitStream *bs, int n) {
    while (bs->bit_cnt < n) {
        if (bs->byte_pos >= bs->len) return -1;
        bs->bit_buf |= ((uint32_t)bs->src[bs->byte_pos++]) << bs->bit_cnt;
        bs->bit_cnt += 8;
    }
    return 0;
}

static int bs_read_bits(BitStream *bs, int n, uint32_t *out) {
    if (n == 0) {
        *out = 0;
        return 0;
    }
    if (bs_need_bits(bs, n) != 0) return -1;
    *out = bs->bit_buf & ((1u << n) - 1u);
    bs->bit_buf >>= n;
    bs->bit_cnt -= n;
    return 0;
}

static void bs_align_byte(BitStream *bs) {
    int drop = bs->bit_cnt & 7;
    bs->bit_buf >>= drop;
    bs->bit_cnt -= drop;
    while (bs->bit_cnt >= 8) {
        bs->bit_cnt -= 8;
        if (bs->byte_pos > 0) bs->byte_pos--;
    }
    bs->bit_buf = 0;
}

static int huff_build(HuffTable *t, const int16_t *lengths, int num) {
    int offs[16];
    for (int i = 0; i < 16; i++) t->count[i] = 0;
    for (int i = 0; i < num; i++) {
        if (lengths[i] < 0 || lengths[i] > 15) return -1;
        t->count[lengths[i]]++;
    }
    if (t->count[0] == num) return 0;
    int left = 1;
    for (int len = 1; len <= 15; len++) {
        left <<= 1;
        left -= t->count[len];
        if (left < 0) return -1;
    }
    offs[1] = 0;
    for (int len = 1; len < 15; len++) offs[len + 1] = offs[len] + t->count[len];
    for (int sym = 0; sym < num; sym++) {
        if (lengths[sym] != 0) t->symbol[offs[lengths[sym]]++] = (int16_t)sym;
    }
    return 0;
}

static int huff_decode(BitStream *bs, const HuffTable *t, int *out_sym) {
    int code = 0, first = 0, index = 0;
    for (int len = 1; len <= 15; len++) {
        uint32_t bit = 0;
        if (bs_read_bits(bs, 1, &bit) != 0) return -1;
        code |= (int)bit;
        int cnt = t->count[len];
        if (code - cnt < first) {
            *out_sym = t->symbol[index + (code - first)];
            return 0;
        }
        index += cnt;
        first += cnt;
        first <<= 1;
        code <<= 1;
    }
    return -1;
}

static int inflate_raw(const uint8_t *src, size_t src_len, uint8_t *dst, size_t dst_cap, size_t *out_len) {
    static const int16_t len_base[29] = {
        3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,
        35,43,51,59,67,83,99,115,131,163,195,227,258
    };
    static const int16_t len_ext[29] = {
        0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,
        3,3,3,3,4,4,4,4,5,5,5,5,0
    };
    static const int16_t dist_base[30] = {
        1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,
        257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577
    };
    static const int16_t dist_ext[30] = {
        0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,
        7,7,8,8,9,9,10,10,11,11,12,12,13,13
    };
    static const int16_t order[19] = {16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15};

    BitStream bs = {src, src_len, 0, 0, 0};
    size_t pos = 0;
    uint32_t bfinal = 0;

    do {
        uint32_t btype = 0;
        if (bs_read_bits(&bs, 1, &bfinal) != 0) return -1;
        if (bs_read_bits(&bs, 2, &btype) != 0) return -1;

        if (btype == 0) {
            bs_align_byte(&bs);
            if (bs.byte_pos + 4 > bs.len) return -1;
            uint16_t blen = rd_u16(bs.src + bs.byte_pos);
            uint16_t nlen = rd_u16(bs.src + bs.byte_pos + 2);
            bs.byte_pos += 4;
            if ((uint16_t)(~blen) != nlen) return -1;
            if (bs.byte_pos + blen > bs.len || pos + blen > dst_cap) return -1;
            memcpy(dst + pos, bs.src + bs.byte_pos, blen);
            bs.byte_pos += blen;
            pos += blen;
        } else if (btype == 1 || btype == 2) {
            HuffTable lit_t, dist_t;
            int16_t lengths[320];
            if (btype == 1) {
                int i = 0;
                for (; i < 144; i++) lengths[i] = 8;
                for (; i < 256; i++) lengths[i] = 9;
                for (; i < 280; i++) lengths[i] = 7;
                for (; i < 288; i++) lengths[i] = 8;
                huff_build(&lit_t, lengths, 288);
                for (i = 0; i < 30; i++) lengths[i] = 5;
                huff_build(&dist_t, lengths, 30);
            } else {
                uint32_t hlit = 0, hdist = 0, hclen = 0;
                if (bs_read_bits(&bs, 5, &hlit) != 0) return -1;
                if (bs_read_bits(&bs, 5, &hdist) != 0) return -1;
                if (bs_read_bits(&bs, 4, &hclen) != 0) return -1;
                hlit += 257; hdist += 1; hclen += 4;
                if (hlit > 286 || hdist > 30) return -1;
                for (int i = 0; i < 19; i++) lengths[i] = 0;
                for (uint32_t i = 0; i < hclen; i++) {
                    uint32_t v = 0;
                    if (bs_read_bits(&bs, 3, &v) != 0) return -1;
                    lengths[order[i]] = (int16_t)v;
                }
                HuffTable cl_t;
                if (huff_build(&cl_t, lengths, 19) != 0) return -1;
                uint32_t total = hlit + hdist;
                uint32_t idx = 0;
                while (idx < total) {
                    int sym = 0;
                    if (huff_decode(&bs, &cl_t, &sym) != 0) return -1;
                    if (sym < 16) {
                        lengths[idx++] = (int16_t)sym;
                    } else {
                        uint32_t rep = 0;
                        int16_t val = 0;
                        if (sym == 16) {
                            if (idx == 0 || bs_read_bits(&bs, 2, &rep) != 0) return -1;
                            val = lengths[idx - 1];
                            rep += 3;
                        } else if (sym == 17) {
                            if (bs_read_bits(&bs, 3, &rep) != 0) return -1;
                            rep += 3;
                        } else {
                            if (bs_read_bits(&bs, 7, &rep) != 0) return -1;
                            rep += 11;
                        }
                        if (idx + rep > total) return -1;
                        while (rep--) lengths[idx++] = val;
                    }
                }
                if (huff_build(&lit_t, lengths, (int)hlit) != 0) return -1;
                if (huff_build(&dist_t, lengths + hlit, (int)hdist) != 0) return -1;
            }

            for (;;) {
                int sym = 0;
                if (huff_decode(&bs, &lit_t, &sym) != 0) return -1;
                if (sym < 256) {
                    if (pos >= dst_cap) return -1;
                    dst[pos++] = (uint8_t)sym;
                } else if (sym == 256) {
                    break;
                } else {
                    int lidx = sym - 257;
                    if (lidx < 0 || lidx >= 29) return -1;
                    uint32_t extra = 0;
                    if (bs_read_bits(&bs, len_ext[lidx], &extra) != 0) return -1;
                    uint32_t length = (uint32_t)len_base[lidx] + extra;
                    int dsym = 0;
                    if (huff_decode(&bs, &dist_t, &dsym) != 0) return -1;
                    if (dsym < 0 || dsym >= 30) return -1;
                    uint32_t dextra = 0;
                    if (bs_read_bits(&bs, dist_ext[dsym], &dextra) != 0) return -1;
                    uint32_t dist = (uint32_t)dist_base[dsym] + dextra;
                    if (dist == 0 || dist > pos || pos + length > dst_cap) return -1;
                    for (uint32_t k = 0; k < length; k++) {
                        dst[pos] = dst[pos - dist];
                        pos++;
                    }
                }
            }
        } else {
            return -1;
        }
    } while (!bfinal);

    *out_len = pos;
    return 0;
}

static int inflate_zlib(const uint8_t *src, size_t src_len, uint8_t *dst, size_t dst_cap, size_t *out_len) {
    if (src_len >= 6 && (src[0] & 0x0F) == 8 && (((uint32_t)src[0] << 8 | src[1]) % 31u == 0)) {
        size_t hdr = 2;
        if (src[1] & 0x20) hdr += 4;
        if (hdr < src_len) {
            if (inflate_raw(src + hdr, src_len - hdr, dst, dst_cap, out_len) == 0) return 0;
        }
    }
    return inflate_raw(src, src_len, dst, dst_cap, out_len);
}

/* ==================== MPK v2.0 挂载与二分检索 ==================== */

static const MgsEntry *g_sort_entries = NULL;

static int cmp_entry_idx(const void *pa, const void *pb) {
    uint32_t ia = *(const uint32_t *)pa;
    uint32_t ib = *(const uint32_t *)pb;
    int c = strcmp(g_sort_entries[ia].name_lower, g_sort_entries[ib].name_lower);
    if (c != 0) return c;
    return (ia < ib) ? -1 : (ia > ib ? 1 : 0);
}

static int is_ignored_mpk_name(const char *lower_name) {
    if (!ends_with_ci(lower_name, ".mpk")) return 1;
    if (ends_with_ci(lower_name, "_bak.mpk")) return 1;
    if (strcmp(lower_name, "shader.mpk") == 0) return 1;
    if (strcmp(lower_name, "mgsshader.mpk") == 0) return 1;
    return 0;
}

static int parse_mpk_file(const char *file_path, const char *arch_name, MgsArchive *out_arch) {
    FILE *fp = open_rb_utf8(file_path);
    if (!fp) return -1;

    uint8_t hdr[64];
    if (fread(hdr, 1, 64, fp) != 64) {
        fclose(fp);
        return -2;
    }
    if (memcmp(hdr, "MPK\0", 4) != 0) {
        fclose(fp);
        return -3;
    }
    uint16_t ver_major = rd_u16(hdr + 6);
    uint32_t count = rd_u32(hdr + 8);
    if (ver_major != 2) {
        fclose(fp);
        return -4;
    }

    memset(out_arch, 0, sizeof(*out_arch));
    snprintf(out_arch->archive_name, sizeof(out_arch->archive_name), "%s", arch_name);
    str_to_lower_buf(arch_name, out_arch->archive_lower, sizeof(out_arch->archive_lower));
    snprintf(out_arch->file_path, sizeof(out_arch->file_path), "%s", file_path);

    if (count == 0) {
        fclose(fp);
        return 0;
    }

    uint8_t *toc = (uint8_t *)malloc((size_t)count * 256u);
    if (!toc) {
        fclose(fp);
        return -5;
    }
    if (fread(toc, 256u, count, fp) != count) {
        free(toc);
        fclose(fp);
        return -6;
    }
    fclose(fp);

    MgsEntry *entries = (MgsEntry *)calloc(count, sizeof(MgsEntry));
    uint32_t *sorted = (uint32_t *)malloc((size_t)count * sizeof(uint32_t));
    if (!entries || !sorted) {
        free(toc);
        free(entries);
        free(sorted);
        return -7;
    }

    uint32_t valid_count = 0;
    for (uint32_t i = 0; i < count; i++) {
        const uint8_t *rec = toc + (size_t)i * 256u;
        uint32_t comp = rd_u32(rec + 0);
        uint32_t idx = rd_u32(rec + 4);
        uint64_t off = rd_u64(rec + 8);
        uint64_t sz = rd_u64(rec + 16);
        uint64_t usz = rd_u64(rec + 24);
        char name_buf[225];
        memcpy(name_buf, rec + 32, 224);
        name_buf[224] = '\0';
        if (name_buf[0] == '\0') continue;

        MgsEntry *e = &entries[valid_count];
        e->index = idx;
        e->compression = comp;
        e->offset = off;
        e->size = sz;
        e->uncompressed_size = usz;
        memcpy(e->name, name_buf, sizeof(e->name));
        e->name[sizeof(e->name) - 1] = '\0';
        str_to_lower_buf(e->name, e->name_lower, sizeof(e->name_lower));
        sorted[valid_count] = valid_count;
        valid_count++;
    }
    free(toc);

    out_arch->entries = entries;
    out_arch->sorted_indices = sorted;
    out_arch->count = valid_count;
    if (valid_count > 1) {
        g_sort_entries = entries;
        qsort(sorted, valid_count, sizeof(uint32_t), cmp_entry_idx);
        g_sort_entries = NULL;
    }
    return 0;
}

void mgs_vfs_init(MgsVfsState *vfs) {
    if (!vfs) return;
    memset(vfs, 0, sizeof(*vfs));
}

static void free_archive_contents(MgsArchive *a) {
    if (!a) return;
    free(a->entries);
    free(a->sorted_indices);
    memset(a, 0, sizeof(*a));
}

void mgs_vfs_free(MgsVfsState *vfs) {
    if (!vfs) return;
    for (uint32_t i = 0; i < vfs->archive_count; i++) {
        free_archive_contents(&vfs->archives[i]);
    }
    free(vfs->archives);
    memset(vfs, 0, sizeof(*vfs));
}

static int mount_directory_mpks(MgsVfsState *vfs, const char *dir_utf8) {
    int mounted_here = 0;

#ifdef _WIN32
    char pattern[1152];
    snprintf(pattern, sizeof(pattern), "%s\\*.mpk", dir_utf8);
    int wlen = MultiByteToWideChar(CP_UTF8, 0, pattern, -1, NULL, 0);
    if (wlen <= 0) return 0;
    wchar_t *wpat = (wchar_t *)malloc((size_t)wlen * sizeof(wchar_t));
    if (!wpat) return 0;
    MultiByteToWideChar(CP_UTF8, 0, pattern, -1, wpat, wlen);

    WIN32_FIND_DATAW fd;
    HANDLE hFind = FindFirstFileW(wpat, &fd);
    free(wpat);
    if (hFind == INVALID_HANDLE_VALUE) return 0;

    do {
        if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) continue;
        char fname[256];
        int n = WideCharToMultiByte(CP_UTF8, 0, fd.cFileName, -1, fname, sizeof(fname), NULL, NULL);
        if (n <= 0) continue;
        char lower_name[256];
        str_to_lower_buf(fname, lower_name, sizeof(lower_name));
        if (is_ignored_mpk_name(lower_name)) continue;

        char full_path[1024];
        snprintf(full_path, sizeof(full_path), "%s\\%s", dir_utf8, fname);
        MgsArchive arch;
        if (parse_mpk_file(full_path, fname, &arch) == 0) {
            int replaced = 0;
            for (uint32_t i = 0; i < vfs->archive_count; i++) {
                if (strcmp(vfs->archives[i].archive_lower, arch.archive_lower) == 0) {
                    vfs->total_entries -= vfs->archives[i].count;
                    free_archive_contents(&vfs->archives[i]);
                    vfs->archives[i] = arch;
                    vfs->total_entries += arch.count;
                    replaced = 1;
                    break;
                }
            }
            if (!replaced) {
                MgsArchive *na = (MgsArchive *)realloc(
                    vfs->archives, (size_t)(vfs->archive_count + 1) * sizeof(MgsArchive)
                );
                if (na) {
                    vfs->archives = na;
                    vfs->archives[vfs->archive_count++] = arch;
                    vfs->total_entries += arch.count;
                } else {
                    free_archive_contents(&arch);
                }
            }
            mounted_here++;
        }
    } while (FindNextFileW(hFind, &fd));
    FindClose(hFind);
#else
    DIR *d = opendir(dir_utf8);
    if (!d) return 0;
    struct dirent *de;
    while ((de = readdir(d)) != NULL) {
        if (de->d_name[0] == '.') continue;
        char lower_name[256];
        str_to_lower_buf(de->d_name, lower_name, sizeof(lower_name));
        if (is_ignored_mpk_name(lower_name)) continue;

        char full_path[1024];
        snprintf(full_path, sizeof(full_path), "%s/%s", dir_utf8, de->d_name);
        struct stat st;
        if (stat(full_path, &st) != 0 || !S_ISREG(st.st_mode)) continue;

        MgsArchive arch;
        if (parse_mpk_file(full_path, de->d_name, &arch) == 0) {
            int replaced = 0;
            for (uint32_t i = 0; i < vfs->archive_count; i++) {
                if (strcmp(vfs->archives[i].archive_lower, arch.archive_lower) == 0) {
                    vfs->total_entries -= vfs->archives[i].count;
                    free_archive_contents(&vfs->archives[i]);
                    vfs->archives[i] = arch;
                    vfs->total_entries += arch.count;
                    replaced = 1;
                    break;
                }
            }
            if (!replaced) {
                MgsArchive *na = (MgsArchive *)realloc(
                    vfs->archives, (size_t)(vfs->archive_count + 1) * sizeof(MgsArchive)
                );
                if (na) {
                    vfs->archives = na;
                    vfs->archives[vfs->archive_count++] = arch;
                    vfs->total_entries += arch.count;
                } else {
                    free_archive_contents(&arch);
                }
            }
            mounted_here++;
        }
    }
    closedir(d);
#endif

    return mounted_here;
}

int32_t mgs_vfs_mount(MgsVfsState *vfs, const char *dir_utf8) {
    if (!vfs || !dir_utf8 || !dir_utf8[0]) return -1;

    char clean[1024];
    snprintf(clean, sizeof(clean), "%s", dir_utf8);
    size_t len = strlen(clean);
    while (len > 1 && (clean[len - 1] == '/' || clean[len - 1] == '\\')) {
        clean[--len] = '\0';
    }

    int mounted = mount_directory_mpks(vfs, clean);
    if (mounted == 0) {
        char sub[1040];
        snprintf(sub, sizeof(sub), "%s/USRDIR", clean);
        mounted = mount_directory_mpks(vfs, sub);
    }
    return mounted > 0 ? (int32_t)vfs->total_entries : -1;
}

const MgsArchive *mgs_vfs_find_archive(const MgsVfsState *vfs, const char *archive_name) {
    if (!vfs || !archive_name) return NULL;
    char low[64];
    str_to_lower_buf(archive_name, low, sizeof(low));
    for (uint32_t i = 0; i < vfs->archive_count; i++) {
        if (strcmp(vfs->archives[i].archive_lower, low) == 0) {
            return &vfs->archives[i];
        }
    }
    if (!ends_with_ci(low, ".mpk") && strlen(low) + 5 < sizeof(low)) {
        strcat(low, ".mpk");
        for (uint32_t i = 0; i < vfs->archive_count; i++) {
            if (strcmp(vfs->archives[i].archive_lower, low) == 0) {
                return &vfs->archives[i];
            }
        }
    }
    return NULL;
}

const MgsEntry *mgs_vfs_find_entry(const MgsVfsState *vfs, const char *archive_name, const char *entry_name) {
    if (!vfs || !archive_name || !entry_name) return NULL;
    const MgsArchive *arch = mgs_vfs_find_archive(vfs, archive_name);
    if (!arch || arch->count == 0) return NULL;

    char key[224];
    str_to_lower_buf(entry_name, key, sizeof(key));

    int64_t lo = 0;
    int64_t hi = (int64_t)arch->count - 1;
    while (lo <= hi) {
        int64_t mid = lo + ((hi - lo) >> 1);
        const MgsEntry *e = &arch->entries[arch->sorted_indices[mid]];
        int c = strcmp(e->name_lower, key);
        if (c == 0) return e;
        if (c < 0) lo = mid + 1;
        else hi = mid - 1;
    }
    return NULL;
}

int32_t mgs_vfs_read_entry(
    const MgsVfsState *vfs,
    const char *archive_name,
    const char *entry_name,
    uint8_t **out_buf,
    size_t *out_size
) {
    if (!out_buf || !out_size) return -1;
    *out_buf = NULL;
    *out_size = 0;

    const MgsArchive *arch = mgs_vfs_find_archive(vfs, archive_name);
    if (!arch) return -2;
    const MgsEntry *entry = mgs_vfs_find_entry(vfs, archive_name, entry_name);
    if (!entry) return -3;

    if (entry->size == 0) {
        uint8_t *empty = (uint8_t *)malloc(1);
        if (!empty) return -4;
        *out_buf = empty;
        *out_size = 0;
        return 0;
    }

    FILE *fp = open_rb_utf8(arch->file_path);
    if (!fp) return -5;
    if (seek_u64(fp, entry->offset) != 0) {
        fclose(fp);
        return -6;
    }

    uint8_t *raw = (uint8_t *)malloc((size_t)entry->size);
    if (!raw) {
        fclose(fp);
        return -7;
    }
    if (fread(raw, 1, (size_t)entry->size, fp) != (size_t)entry->size) {
        free(raw);
        fclose(fp);
        return -8;
    }
    fclose(fp);

    if (entry->compression == 0) {
        *out_buf = raw;
        *out_size = (size_t)entry->size;
        return 0;
    }

    /* 兼容带 zlib 压缩的汉化补充封包条目 */
    size_t cap = (entry->uncompressed_size > 0) ? (size_t)entry->uncompressed_size : ((size_t)entry->size * 4u);
    uint8_t *uncomp = (uint8_t *)malloc(cap);
    if (!uncomp) {
        free(raw);
        return -9;
    }
    size_t real_len = 0;
    int irc = inflate_zlib(raw, (size_t)entry->size, uncomp, cap, &real_len);
    free(raw);
    if (irc != 0) {
        free(uncomp);
        return -10;
    }
    *out_buf = uncomp;
    *out_size = real_len;
    return 0;
}

/* ==================== PNG 识别与 DDS (DXT1/DXT3/DXT5/BGRA/L8) 解码 ==================== */

static void decode_dxt1_block_rgba(const uint8_t *blk, uint8_t out_rgba[16][4], int opaque_alpha_only) {
    uint16_t c0 = rd_u16(blk);
    uint16_t c1 = rd_u16(blk + 2);
    uint32_t bits = rd_u32(blk + 4);

    uint32_t r0 = ((c0 >> 11) & 0x1Fu) * 255u / 31u;
    uint32_t g0 = ((c0 >> 5) & 0x3Fu) * 255u / 63u;
    uint32_t b0 = (c0 & 0x1Fu) * 255u / 31u;

    uint32_t r1 = ((c1 >> 11) & 0x1Fu) * 255u / 31u;
    uint32_t g1 = ((c1 >> 5) & 0x3Fu) * 255u / 63u;
    uint32_t b1 = (c1 & 0x1Fu) * 255u / 31u;

    uint8_t pal[4][4];
    pal[0][0] = (uint8_t)r0; pal[0][1] = (uint8_t)g0; pal[0][2] = (uint8_t)b0; pal[0][3] = 255;
    pal[1][0] = (uint8_t)r1; pal[1][1] = (uint8_t)g1; pal[1][2] = (uint8_t)b1; pal[1][3] = 255;

    if (!opaque_alpha_only && c0 <= c1) {
        pal[2][0] = (uint8_t)((r0 + r1) / 2u);
        pal[2][1] = (uint8_t)((g0 + g1) / 2u);
        pal[2][2] = (uint8_t)((b0 + b1) / 2u);
        pal[2][3] = 255;
        pal[3][0] = 0; pal[3][1] = 0; pal[3][2] = 0; pal[3][3] = 0;
    } else {
        pal[2][0] = (uint8_t)((2u * r0 + r1) / 3u);
        pal[2][1] = (uint8_t)((2u * g0 + g1) / 3u);
        pal[2][2] = (uint8_t)((2u * b0 + b1) / 3u);
        pal[2][3] = 255;
        pal[3][0] = (uint8_t)((r0 + 2u * r1) / 3u);
        pal[3][1] = (uint8_t)((g0 + 2u * g1) / 3u);
        pal[3][2] = (uint8_t)((b0 + 2u * b1) / 3u);
        pal[3][3] = 255;
    }

    for (int i = 0; i < 16; i++) {
        uint32_t idx = (bits >> (2 * i)) & 3u;
        out_rgba[i][0] = pal[idx][0];
        out_rgba[i][1] = pal[idx][1];
        out_rgba[i][2] = pal[idx][2];
        out_rgba[i][3] = pal[idx][3];
    }
}

static void decode_dxt5_alpha(const uint8_t *blk, uint8_t out_a[16]) {
    uint32_t a0 = blk[0];
    uint32_t a1 = blk[1];
    uint64_t abits = 0;
    for (int k = 0; k < 6; k++) {
        abits |= ((uint64_t)blk[2 + k]) << (8 * k);
    }

    uint8_t apal[8];
    apal[0] = (uint8_t)a0;
    apal[1] = (uint8_t)a1;
    if (a0 > a1) {
        for (uint32_t i = 1; i <= 6; i++) {
            apal[i + 1] = (uint8_t)(((7u - i) * a0 + i * a1) / 7u);
        }
    } else {
        for (uint32_t i = 1; i <= 4; i++) {
            apal[i + 1] = (uint8_t)(((5u - i) * a0 + i * a1) / 5u);
        }
        apal[6] = 0;
        apal[7] = 255;
    }

    for (int i = 0; i < 16; i++) {
        uint32_t idx = (uint32_t)((abits >> (3 * i)) & 7u);
        out_a[i] = apal[idx];
    }
}

static void decode_dxt3_alpha(const uint8_t *blk, uint8_t out_a[16]) {
    for (int i = 0; i < 8; i++) {
        uint8_t b = blk[i];
        uint32_t lo = b & 0x0Fu;
        uint32_t hi = (b >> 4) & 0x0Fu;
        out_a[i * 2] = (uint8_t)(lo * 17u);
        out_a[i * 2 + 1] = (uint8_t)(hi * 17u);
    }
}

static int mask_shift(uint32_t mask) {
    if (mask == 0) return 0;
    int s = 0;
    while ((mask & 1u) == 0) {
        mask >>= 1;
        s++;
    }
    return s;
}

static int mask_bits(uint32_t mask) {
    int c = 0;
    while (mask) {
        c += (int)(mask & 1u);
        mask >>= 1;
    }
    return c;
}

static uint8_t extract_channel(uint32_t px, uint32_t mask) {
    if (mask == 0) return 255;
    int s = mask_shift(mask);
    int b = mask_bits(mask);
    uint32_t v = (px & mask) >> s;
    if (b >= 8) return (uint8_t)(v >> (b - 8));
    uint32_t maxv = (1u << b) - 1u;
    return maxv ? (uint8_t)(v * 255u / maxv) : 0;
}

int32_t mgs_decode_image_buffer(const uint8_t *buf, size_t len, int32_t l8_alpha_only, MgsDdsImage *out) {
    if (!buf || !out) return -1;
    memset(out, 0, sizeof(*out));

    /* PNG 文件识别：保留原始字节交由引擎原生极速 libpng 解码 */
    static const uint8_t png_sig[8] = {0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A};
    if (len >= 24 && memcmp(buf, png_sig, 8) == 0 && memcmp(buf + 12, "IHDR", 4) == 0) {
        uint32_t w = rd_u32_be(buf + 16);
        uint32_t h = rd_u32_be(buf + 20);
        uint8_t *copy = (uint8_t *)malloc(len);
        if (!copy) return -2;
        memcpy(copy, buf, len);
        out->ok = 1;
        out->width = w;
        out->height = h;
        out->is_l8 = 0;
        out->is_png = 1;
        out->data = copy;
        out->data_size = len;
        return 0;
    }

    /* DDS 头解析 */
    if (len < 128 || memcmp(buf, "DDS ", 4) != 0) {
        return -3;
    }
    uint32_t height = rd_u32(buf + 12);
    uint32_t width = rd_u32(buf + 16);
    uint32_t pf_flags = rd_u32(buf + 80);
    const uint8_t *fourcc = buf + 84;
    uint32_t rgb_bits = rd_u32(buf + 88);
    uint32_t r_mask = rd_u32(buf + 92);
    uint32_t g_mask = rd_u32(buf + 96);
    uint32_t b_mask = rd_u32(buf + 100);
    uint32_t a_mask = rd_u32(buf + 104);

    if (width == 0 || height == 0 || width > 16384 || height > 16384) {
        return -4;
    }

    size_t hdr_size = 128;
    if ((pf_flags & 0x04u) && memcmp(fourcc, "DX10", 4) == 0) {
        hdr_size = 148;
        if (len < hdr_size) return -5;
    }
    const uint8_t *payload = buf + hdr_size;
    size_t plen = len - hdr_size;

    uint32_t bw = (width + 3u) / 4u;
    uint32_t bh = (height + 3u) / 4u;
    size_t px_count = (size_t)width * (size_t)height;

    if (pf_flags & 0x04u) {
        if (memcmp(fourcc, "DXT1", 4) == 0) {
            size_t need = (size_t)bw * bh * 8u;
            if (plen < need) return -6;
            size_t out_sz = l8_alpha_only ? px_count : (px_count * 4u);
            uint8_t *dst = (uint8_t *)malloc(out_sz);
            if (!dst) return -7;
            for (uint32_t by = 0; by < bh; by++) {
                for (uint32_t bx = 0; bx < bw; bx++) {
                    const uint8_t *blk = payload + ((size_t)by * bw + bx) * 8u;
                    if (l8_alpha_only) {
                        uint16_t c0 = rd_u16(blk);
                        uint16_t c1 = rd_u16(blk + 2);
                        uint32_t bits = rd_u32(blk + 4);
                        int punch_mode = (c0 <= c1);
                        for (int py = 0; py < 4; py++) {
                            uint32_t y = by * 4u + (uint32_t)py;
                            if (y >= height) break;
                            for (int px = 0; px < 4; px++) {
                                uint32_t x = bx * 4u + (uint32_t)px;
                                if (x >= width) break;
                                uint32_t idx = (bits >> (2 * (py * 4 + px))) & 3u;
                                dst[(size_t)y * width + x] = (punch_mode && idx == 3u) ? 0 : 255;
                            }
                        }
                    } else {
                        uint8_t block_px[16][4];
                        decode_dxt1_block_rgba(blk, block_px, 0);
                        for (int py = 0; py < 4; py++) {
                            uint32_t y = by * 4u + (uint32_t)py;
                            if (y >= height) break;
                            for (int px = 0; px < 4; px++) {
                                uint32_t x = bx * 4u + (uint32_t)px;
                                if (x >= width) break;
                                uint8_t *d = dst + ((size_t)y * width + x) * 4u;
                                const uint8_t *s = block_px[py * 4 + px];
                                d[0] = s[0]; d[1] = s[1]; d[2] = s[2]; d[3] = s[3];
                            }
                        }
                    }
                }
            }
            out->ok = 1;
            out->width = width;
            out->height = height;
            out->is_l8 = l8_alpha_only ? 1 : 0;
            out->data = dst;
            out->data_size = out_sz;
            return 0;
        }

        if (memcmp(fourcc, "DXT3", 4) == 0 || memcmp(fourcc, "DXT5", 4) == 0) {
            int is_dxt5 = (fourcc[3] == '5');
            size_t need = (size_t)bw * bh * 16u;
            if (plen < need) return -8;
            size_t out_sz = l8_alpha_only ? px_count : (px_count * 4u);
            uint8_t *dst = (uint8_t *)malloc(out_sz);
            if (!dst) return -9;

            for (uint32_t by = 0; by < bh; by++) {
                for (uint32_t bx = 0; bx < bw; bx++) {
                    const uint8_t *blk = payload + ((size_t)by * bw + bx) * 16u;
                    uint8_t alphas[16];
                    if (is_dxt5) decode_dxt5_alpha(blk, alphas);
                    else decode_dxt3_alpha(blk, alphas);

                    if (l8_alpha_only) {
                        for (int py = 0; py < 4; py++) {
                            uint32_t y = by * 4u + (uint32_t)py;
                            if (y >= height) break;
                            for (int px = 0; px < 4; px++) {
                                uint32_t x = bx * 4u + (uint32_t)px;
                                if (x >= width) break;
                                dst[(size_t)y * width + x] = alphas[py * 4 + px];
                            }
                        }
                    } else {
                        uint8_t block_px[16][4];
                        decode_dxt1_block_rgba(blk + 8, block_px, 1);
                        for (int py = 0; py < 4; py++) {
                            uint32_t y = by * 4u + (uint32_t)py;
                            if (y >= height) break;
                            for (int px = 0; px < 4; px++) {
                                uint32_t x = bx * 4u + (uint32_t)px;
                                if (x >= width) break;
                                uint8_t *d = dst + ((size_t)y * width + x) * 4u;
                                const uint8_t *s = block_px[py * 4 + px];
                                d[0] = s[0];
                                d[1] = s[1];
                                d[2] = s[2];
                                d[3] = alphas[py * 4 + px];
                            }
                        }
                    }
                }
            }
            out->ok = 1;
            out->width = width;
            out->height = height;
            out->is_l8 = l8_alpha_only ? 1 : 0;
            out->data = dst;
            out->data_size = out_sz;
            return 0;
        }
        return -10;
    }

    /* 未压缩 DDS（如 L8/A8/BGR8/BGRA8/RGBA8） */
    if (rgb_bits == 8) {
        if (plen < px_count) return -11;
        if (l8_alpha_only) {
            uint8_t *dst = (uint8_t *)malloc(px_count);
            if (!dst) return -12;
            memcpy(dst, payload, px_count);
            out->ok = 1;
            out->width = width;
            out->height = height;
            out->is_l8 = 1;
            out->data = dst;
            out->data_size = px_count;
            return 0;
        } else {
            uint8_t *dst = (uint8_t *)malloc(px_count * 4u);
            if (!dst) return -13;
            int is_alpha_only = (pf_flags & 0x02u) && !(pf_flags & 0x20000u);
            for (size_t i = 0; i < px_count; i++) {
                uint8_t v = payload[i];
                dst[i * 4 + 0] = is_alpha_only ? 255 : v;
                dst[i * 4 + 1] = is_alpha_only ? 255 : v;
                dst[i * 4 + 2] = is_alpha_only ? 255 : v;
                dst[i * 4 + 3] = is_alpha_only ? v : 255;
            }
            out->ok = 1;
            out->width = width;
            out->height = height;
            out->is_l8 = 0;
            out->data = dst;
            out->data_size = px_count * 4u;
            return 0;
        }
    }

    if (rgb_bits == 24 || rgb_bits == 32) {
        size_t bpp = rgb_bits / 8u;
        if (plen < px_count * bpp) return -14;
        if (r_mask == 0 && g_mask == 0 && b_mask == 0) {
            r_mask = 0x00FF0000u;
            g_mask = 0x0000FF00u;
            b_mask = 0x000000FFu;
            a_mask = (bpp == 4) ? 0xFF000000u : 0u;
        }
        size_t out_sz = l8_alpha_only ? px_count : (px_count * 4u);
        uint8_t *dst = (uint8_t *)malloc(out_sz);
        if (!dst) return -15;

        for (size_t i = 0; i < px_count; i++) {
            const uint8_t *sp = payload + i * bpp;
            uint32_t px = (bpp == 4)
                ? rd_u32(sp)
                : ((uint32_t)sp[0] | ((uint32_t)sp[1] << 8) | ((uint32_t)sp[2] << 16));
            uint8_t a = a_mask ? extract_channel(px, a_mask) : 255;
            if (l8_alpha_only) {
                dst[i] = a;
            } else {
                dst[i * 4 + 0] = extract_channel(px, r_mask);
                dst[i * 4 + 1] = extract_channel(px, g_mask);
                dst[i * 4 + 2] = extract_channel(px, b_mask);
                dst[i * 4 + 3] = a;
            }
        }
        out->ok = 1;
        out->width = width;
        out->height = height;
        out->is_l8 = l8_alpha_only ? 1 : 0;
        out->data = dst;
        out->data_size = out_sz;
        return 0;
    }

    return -16;
}

void mgs_free_image(MgsDdsImage *img) {
    if (!img) return;
    free(img->data);
    memset(img, 0, sizeof(*img));
}

/* ==================== .lay 30x30 瓦片合成 ==================== */

typedef struct {
    uint32_t group_id;
    uint32_t start;
    uint32_t count;
} LayGroupRec;

typedef struct {
    int32_t dest_x;
    int32_t dest_y;
    int32_t src_u;
    int32_t src_v;
    uint8_t opaque_hint;
} LayTileRec;

int32_t mgs_compose_lay_rgba(
    const uint8_t *lay_buf,
    size_t lay_len,
    const uint8_t *atlas_rgba,
    int32_t atlas_w,
    int32_t atlas_h,
    const int32_t *group_ids,
    int32_t group_count,
    MgsLayResult *out
) {
    if (!lay_buf || lay_len < 8 || !atlas_rgba || atlas_w <= 0 || atlas_h <= 0 || !out) {
        return -1;
    }
    memset(out, 0, sizeof(*out));

    uint32_t n_groups = rd_u32(lay_buf);
    uint32_t n_tiles = rd_u32(lay_buf + 4);
    size_t base_size = 8u + (size_t)n_groups * 12u + (size_t)n_tiles * 16u;
    int has_tail = 0;
    if (lay_len == base_size) {
        has_tail = 0;
    } else if (lay_len == base_size + n_tiles) {
        has_tail = 1;
    } else {
        return -2;
    }

    const uint8_t *gptr = lay_buf + 8;
    const uint8_t *tptr = gptr + (size_t)n_groups * 12u;
    const uint8_t *hptr = lay_buf + base_size;

    /* 预统计总选定瓦片数量与包围盒 */
    int32_t min_x = 0x7FFFFFFF, min_y = 0x7FFFFFFF;
    int32_t max_x = -0x7FFFFFFF, max_y = -0x7FFFFFFF;
    uint32_t total_selected = 0;

    for (int32_t gi = 0; gi < group_count; gi++) {
        uint32_t target_gid = (uint32_t)group_ids[gi];
        for (uint32_t g = 0; g < n_groups; g++) {
            uint32_t gid = rd_u32(gptr + (size_t)g * 12u);
            if (gid != target_gid) continue;
            uint32_t start = rd_u32(gptr + (size_t)g * 12u + 4);
            uint32_t cnt = rd_u32(gptr + (size_t)g * 12u + 8);
            if ((uint64_t)start + cnt > n_tiles) continue;
            for (uint32_t k = 0; k < cnt; k++) {
                const uint8_t *tp = tptr + (size_t)(start + k) * 16u;
                int32_t dx = (int32_t)llround((double)rd_f32(tp + 0));
                int32_t dy = (int32_t)llround((double)rd_f32(tp + 4));
                if (dx < min_x) min_x = dx;
                if (dy < min_y) min_y = dy;
                if (dx + 30 > max_x) max_x = dx + 30;
                if (dy + 30 > max_y) max_y = dy + 30;
                total_selected++;
            }
            break;
        }
    }

    if (total_selected == 0) {
        uint8_t *empty = (uint8_t *)calloc(1, 4);
        if (!empty) return -3;
        out->ok = 1;
        out->width = 1;
        out->height = 1;
        out->origin_x = 0;
        out->origin_y = 0;
        out->rgba = empty;
        out->rgba_size = 4;
        return 0;
    }

    int32_t w = max_x - min_x;
    int32_t h = max_y - min_y;
    if (w <= 0 || h <= 0 || w > 8192 || h > 8192) return -4;

    size_t rgba_sz = (size_t)w * (size_t)h * 4u;
    uint8_t *canvas = (uint8_t *)calloc(1, rgba_sz);
    if (!canvas) return -5;

    for (int32_t gi = 0; gi < group_count; gi++) {
        uint32_t target_gid = (uint32_t)group_ids[gi];
        for (uint32_t g = 0; g < n_groups; g++) {
            uint32_t gid = rd_u32(gptr + (size_t)g * 12u);
            if (gid != target_gid) continue;
            uint32_t start = rd_u32(gptr + (size_t)g * 12u + 4);
            uint32_t cnt = rd_u32(gptr + (size_t)g * 12u + 8);
            if ((uint64_t)start + cnt > n_tiles) continue;

            for (uint32_t k = 0; k < cnt; k++) {
                uint32_t tidx = start + k;
                const uint8_t *tp = tptr + (size_t)tidx * 16u;
                int32_t dx0 = (int32_t)llround((double)rd_f32(tp + 0)) - min_x;
                int32_t dy0 = (int32_t)llround((double)rd_f32(tp + 4)) - min_y;
                int32_t sx0 = (int32_t)llround((double)rd_f32(tp + 8));
                int32_t sy0 = (int32_t)llround((double)rd_f32(tp + 12));
                uint8_t hint = has_tail ? hptr[tidx] : 0;

                if (sx0 < 0 || sy0 < 0 || sx0 + 30 > atlas_w || sy0 + 30 > atlas_h) continue;

                for (int32_t py = 0; py < 30; py++) {
                    int32_t cy = dy0 + py;
                    if (cy < 0 || cy >= h) continue;
                    const uint8_t *srow = atlas_rgba + ((size_t)(sy0 + py) * (size_t)atlas_w + (size_t)sx0) * 4u;
                    uint8_t *drow = canvas + ((size_t)cy * (size_t)w + (size_t)dx0) * 4u;

                    if (hint == 1) {
                        for (int32_t px = 0; px < 30; px++) {
                            int32_t cx = dx0 + px;
                            if (cx < 0 || cx >= w) continue;
                            uint8_t *d = drow + (size_t)px * 4u;
                            const uint8_t *s = srow + (size_t)px * 4u;
                            d[0] = s[0]; d[1] = s[1]; d[2] = s[2]; d[3] = s[3];
                        }
                    } else {
                        for (int32_t px = 0; px < 30; px++) {
                            int32_t cx = dx0 + px;
                            if (cx < 0 || cx >= w) continue;
                            const uint8_t *s = srow + (size_t)px * 4u;
                            uint32_t sa = s[3];
                            if (sa == 0) continue;
                            uint8_t *d = drow + (size_t)px * 4u;
                            if (sa == 255 || d[3] == 0) {
                                d[0] = s[0]; d[1] = s[1]; d[2] = s[2]; d[3] = (uint8_t)sa;
                            } else {
                                uint32_t da = d[3];
                                uint32_t inv_sa = 255u - sa;
                                uint32_t out_a = sa + (da * inv_sa + 127u) / 255u;
                                if (out_a == 0) {
                                    d[0] = d[1] = d[2] = d[3] = 0;
                                } else {
                                    uint32_t w_src = sa * 255u;
                                    uint32_t w_dst = da * inv_sa;
                                    uint32_t denom = out_a * 255u;
                                    d[0] = (uint8_t)((s[0] * w_src + d[0] * w_dst + denom / 2u) / denom);
                                    d[1] = (uint8_t)((s[1] * w_src + d[1] * w_dst + denom / 2u) / denom);
                                    d[2] = (uint8_t)((s[2] * w_src + d[2] * w_dst + denom / 2u) / denom);
                                    d[3] = (uint8_t)out_a;
                                }
                            }
                        }
                    }
                }
            }
            break;
        }
    }

    out->ok = 1;
    out->width = w;
    out->height = h;
    out->origin_x = min_x;
    out->origin_y = min_y;
    out->rgba = canvas;
    out->rgba_size = rgba_sz;
    return 0;
}

void mgs_free_lay(MgsLayResult *res) {
    if (!res) return;
    free(res->rgba);
    memset(res, 0, sizeof(*res));
}
