/*
 * 32-bit Bink2 (bink2w32.dll) 原始帧提取桥接工具
 *
 * 将 PC 版 STEINS;GATE 0 的 .bk2 (KB2j) 视频逐帧解码为原始 32 位 BGRA/RGBA 字节流输出至 stdout，
 * 供上层 Python 脚本管道传入 ffmpeg.exe 编码为 Godot 4 原生支持的 Ogg Theora (.ogv)。
 *
 * 编译（32-bit MinGW）：
 *   i686-w64-mingw32-gcc -O2 tools/bink2_raw.c -o bink2_raw.exe
 */

#define _CRT_SECURE_NO_WARNINGS
#include <windows.h>
#include <fcntl.h>
#include <io.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* 经逆向 bink2w32.dll 校验的 BINK 句柄头部字段布局 */
typedef struct BinkHandle {
    uint32_t width;        /* +0x00 */
    uint32_t height;       /* +0x04 */
    uint32_t frames;       /* +0x08 */
    uint32_t frame_num;    /* +0x0C */
    uint32_t last_frame;   /* +0x10 */
    uint32_t frame_rate;   /* +0x14 */
    uint32_t frame_div;    /* +0x18 */
} BinkHandle;

typedef BinkHandle *(__stdcall *PFN_BinkOpen)(const char *name, uint32_t flags);
typedef void(__stdcall *PFN_BinkClose)(BinkHandle *bink);
typedef int32_t(__stdcall *PFN_BinkDoFrame)(BinkHandle *bink);
typedef void(__stdcall *PFN_BinkNextFrame)(BinkHandle *bink);
typedef int32_t(__stdcall *PFN_BinkCopyToBuffer)(
    BinkHandle *bink,
    void *dest,
    int32_t destpitch,
    uint32_t destheight,
    uint32_t destx,
    uint32_t desty,
    uint32_t flags
);
typedef int32_t(__stdcall *PFN_BinkSetSoundOnOff)(BinkHandle *bink, int32_t onoff);
typedef const char *(__stdcall *PFN_BinkGetError)(void);

/* Bink CopyToBuffer 常用表面格式标志 */
#define BINK_SURFACE_32BGRA 3
#define BINK_SURFACE_32RGBA 4

static void print_usage(const char *exe) {
    fprintf(stderr, "用法: %s --dll <bink2w32.dll> --input <movie.bk2> [--info] [--surface 3|4] [--max-frames N]\n", exe);
}

int main(int argc, char **argv) {
    const char *dll_path = NULL;
    const char *in_path = NULL;
    int info_only = 0;
    uint32_t surface_flag = BINK_SURFACE_32BGRA;
    uint32_t max_frames = 0;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--dll") == 0 && i + 1 < argc) {
            dll_path = argv[++i];
        } else if (strcmp(argv[i], "--input") == 0 && i + 1 < argc) {
            in_path = argv[++i];
        } else if (strcmp(argv[i], "--info") == 0) {
            info_only = 1;
        } else if (strcmp(argv[i], "--surface") == 0 && i + 1 < argc) {
            surface_flag = (uint32_t)strtoul(argv[++i], NULL, 0);
        } else if (strcmp(argv[i], "--max-frames") == 0 && i + 1 < argc) {
            max_frames = (uint32_t)strtoul(argv[++i], NULL, 0);
        } else {
            print_usage(argv[0]);
            return 2;
        }
    }

    if (!dll_path || !in_path) {
        print_usage(argv[0]);
        return 2;
    }

    HMODULE hDll = LoadLibraryA(dll_path);
    if (!hDll) {
        fprintf(stderr, "LoadLibraryA 失败 (%lu): %s\n", GetLastError(), dll_path);
        return 1;
    }

    PFN_BinkOpen pBinkOpen = (PFN_BinkOpen)GetProcAddress(hDll, "_BinkOpen@8");
    PFN_BinkClose pBinkClose = (PFN_BinkClose)GetProcAddress(hDll, "_BinkClose@4");
    PFN_BinkDoFrame pBinkDoFrame = (PFN_BinkDoFrame)GetProcAddress(hDll, "_BinkDoFrame@4");
    PFN_BinkNextFrame pBinkNextFrame = (PFN_BinkNextFrame)GetProcAddress(hDll, "_BinkNextFrame@4");
    PFN_BinkCopyToBuffer pBinkCopyToBuffer = (PFN_BinkCopyToBuffer)GetProcAddress(hDll, "_BinkCopyToBuffer@28");
    PFN_BinkSetSoundOnOff pBinkSetSoundOnOff = (PFN_BinkSetSoundOnOff)GetProcAddress(hDll, "_BinkSetSoundOnOff@8");
    PFN_BinkGetError pBinkGetError = (PFN_BinkGetError)GetProcAddress(hDll, "_BinkGetError@0");

    if (!pBinkOpen || !pBinkClose || !pBinkDoFrame || !pBinkNextFrame || !pBinkCopyToBuffer) {
        fprintf(stderr, "无法从 %s 解析必需的 Bink 导出函数\n", dll_path);
        FreeLibrary(hDll);
        return 1;
    }

    BinkHandle *bink = pBinkOpen(in_path, 0);
    if (!bink) {
        const char *err = pBinkGetError ? pBinkGetError() : "unknown";
        fprintf(stderr, "BinkOpen 失败: %s (%s)\n", in_path, err ? err : "null");
        FreeLibrary(hDll);
        return 1;
    }

    if (pBinkSetSoundOnOff) {
        pBinkSetSoundOnOff(bink, 0);
    }

    if (info_only) {
        printf("{\"width\":%u,\"height\":%u,\"frames\":%u,\"frame_rate\":%u,\"frame_div\":%u}\n",
               bink->width, bink->height, bink->frames, bink->frame_rate, bink->frame_div);
        pBinkClose(bink);
        FreeLibrary(hDll);
        return 0;
    }

    /* 必须将 stdout 切换为二进制模式，避免 0x0A 被转为 0x0D 0x0A */
    if (_setmode(_fileno(stdout), _O_BINARY) == -1) {
        fprintf(stderr, "_setmode(_O_BINARY) 失败\n");
        pBinkClose(bink);
        FreeLibrary(hDll);
        return 1;
    }

    uint32_t w = bink->width;
    uint32_t h = bink->height;
    int32_t pitch = (int32_t)(w * 4);
    size_t frame_bytes = (size_t)w * (size_t)h * 4;
    uint8_t *buf = (uint8_t *)malloc(frame_bytes);
    if (!buf) {
        fprintf(stderr, "分配帧缓冲失败 (%zu bytes)\n", frame_bytes);
        pBinkClose(bink);
        FreeLibrary(hDll);
        return 1;
    }

    uint32_t total = bink->frames;
    if (max_frames > 0 && max_frames < total) {
        total = max_frames;
    }

    for (uint32_t f = 0; f < total; f++) {
        pBinkDoFrame(bink);
        pBinkCopyToBuffer(bink, buf, pitch, h, 0, 0, surface_flag);
        size_t written = fwrite(buf, 1, frame_bytes, stdout);
        if (written != frame_bytes) {
            fprintf(stderr, "写入 stdout 在第 %u 帧中断 (written=%zu/%zu)\n", f, written, frame_bytes);
            free(buf);
            pBinkClose(bink);
            FreeLibrary(hDll);
            return 1;
        }
        if (f + 1 < total) {
            pBinkNextFrame(bink);
        }
    }

    fflush(stdout);
    free(buf);
    pBinkClose(bink);
    FreeLibrary(hDll);
    return 0;
}
