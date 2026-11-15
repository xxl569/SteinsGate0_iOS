# -*- coding: utf-8 -*-
"""MAGES. DDS (DXT1 / DXT5) 纯 Python/NumPy 软解码原型（支持 L8 字库提取与局部裁剪）。"""

from __future__ import annotations

import struct
from typing import Optional, Tuple
import numpy as np
from PIL import Image


DDS_MAGIC = b"DDS "
DDSD_HEADER_SIZE = 128


def parse_dds_header(data: bytes) -> Tuple[int, int, bytes]:
    """解析 DDS 文件头，返回 (width, height, fourcc)。"""
    if len(data) < DDSD_HEADER_SIZE or data[:4] != DDS_MAGIC:
        raise ValueError("无效 DDS 文件头")
    height, width = struct.unpack("<II", data[12:20])
    fourcc = data[84:88]
    return width, height, fourcc


def _decode_rgb565_lut(c0: np.ndarray, c1: np.ndarray, has_alpha_punch: bool) -> np.ndarray:
    """向量化生成 4 色 RGB565 调色板 (bh, bw, 4, 4)。"""
    r0 = ((c0 >> 11) & 0x1F) * 255 // 31
    g0 = ((c0 >> 5) & 0x3F) * 255 // 63
    b0 = (c0 & 0x1F) * 255 // 31

    r1 = ((c1 >> 11) & 0x1F) * 255 // 31
    g1 = ((c1 >> 5) & 0x3F) * 255 // 63
    b1 = (c1 & 0x1F) * 255 // 31

    bh, bw = c0.shape
    pal = np.zeros((bh, bw, 4, 4), dtype=np.uint8)
    pal[:, :, 0, 0] = r0
    pal[:, :, 0, 1] = g0
    pal[:, :, 0, 2] = b0
    pal[:, :, 0, 3] = 255

    pal[:, :, 1, 0] = r1
    pal[:, :, 1, 1] = g1
    pal[:, :, 1, 2] = b1
    pal[:, :, 1, 3] = 255

    if has_alpha_punch:
        gt = c0 > c1
        pal[:, :, 2, 0] = np.where(gt, (2 * r0 + r1) // 3, (r0 + r1) // 2)
        pal[:, :, 2, 1] = np.where(gt, (2 * g0 + g1) // 3, (g0 + g1) // 2)
        pal[:, :, 2, 2] = np.where(gt, (2 * b0 + b1) // 3, (b0 + b1) // 2)
        pal[:, :, 2, 3] = 255

        pal[:, :, 3, 0] = np.where(gt, (r0 + 2 * r1) // 3, 0)
        pal[:, :, 3, 1] = np.where(gt, (g0 + 2 * g1) // 3, 0)
        pal[:, :, 3, 2] = np.where(gt, (b0 + 2 * b1) // 3, 0)
        pal[:, :, 3, 3] = np.where(gt, 255, 0)
    else:
        pal[:, :, 2, 0] = (2 * r0 + r1) // 3
        pal[:, :, 2, 1] = (2 * g0 + g1) // 3
        pal[:, :, 2, 2] = (2 * b0 + b1) // 3
        pal[:, :, 2, 3] = 255

        pal[:, :, 3, 0] = (r0 + 2 * r1) // 3
        pal[:, :, 3, 1] = (g0 + 2 * g1) // 3
        pal[:, :, 3, 2] = (b0 + 2 * b1) // 3
        pal[:, :, 3, 3] = 255

    return pal


def decode_dds_array(data: bytes, l8_alpha_only: bool = False) -> np.ndarray:
    """解码 DXT1/DXT5 DDS 为 RGBA8 (H,W,4) 或 L8 Alpha (H,W)。"""
    width, height, fourcc = parse_dds_header(data)
    bw, bh = (width + 3) // 4, (height + 3) // 4
    payload = data[DDSD_HEADER_SIZE:]

    if fourcc == b"DXT1":
        need = bw * bh * 8
        if len(payload) < need:
            raise ValueError(f"DXT1 数据不足: {len(payload)} < {need}")
        if l8_alpha_only:
            # DXT1 仅在 c0<=c1 且 idx==3 时透明，其余为 255
            blocks = np.frombuffer(payload[:need], dtype=np.uint8).reshape(bh, bw, 8)
            c0 = blocks[:, :, 0].astype(np.uint16) | (blocks[:, :, 1].astype(np.uint16) << 8)
            c1 = blocks[:, :, 2].astype(np.uint16) | (blocks[:, :, 3].astype(np.uint16) << 8)
            bits = (
                blocks[:, :, 4].astype(np.uint32)
                | (blocks[:, :, 5].astype(np.uint32) << 8)
                | (blocks[:, :, 6].astype(np.uint32) << 16)
                | (blocks[:, :, 7].astype(np.uint32) << 24)
            )
            idx = np.stack([((bits >> (2 * k)) & 3) for k in range(16)], axis=-1)
            punch = (c0 <= c1)[:, :, None] & (idx == 3)
            alpha = np.where(punch, 0, 255).astype(np.uint8)
            return alpha.reshape(bh, bw, 4, 4).transpose(0, 2, 1, 3).reshape(bh * 4, bw * 4)[:height, :width]

        blocks = np.frombuffer(payload[:need], dtype=np.uint8).reshape(bh, bw, 8)
        c0 = blocks[:, :, 0].astype(np.int32) | (blocks[:, :, 1].astype(np.int32) << 8)
        c1 = blocks[:, :, 2].astype(np.int32) | (blocks[:, :, 3].astype(np.int32) << 8)
        pal = _decode_rgb565_lut(c0, c1, has_alpha_punch=True)
        bits = (
            blocks[:, :, 4].astype(np.uint32)
            | (blocks[:, :, 5].astype(np.uint32) << 8)
            | (blocks[:, :, 6].astype(np.uint32) << 16)
            | (blocks[:, :, 7].astype(np.uint32) << 24)
        )
        idx = np.stack([((bits >> (2 * k)) & 3) for k in range(16)], axis=-1).astype(np.int32)
        rgba = np.take_along_axis(pal, idx[:, :, :, None], axis=2)
        return (
            rgba.reshape(bh, bw, 4, 4, 4)
            .transpose(0, 2, 1, 3, 4)
            .reshape(bh * 4, bw * 4, 4)[:height, :width]
        )

    if fourcc == b"DXT5":
        need = bw * bh * 16
        if len(payload) < need:
            raise ValueError(f"DXT5 数据不足: {len(payload)} < {need}")
        blocks = np.frombuffer(payload[:need], dtype=np.uint8).reshape(bh, bw, 16)
        a0 = blocks[:, :, 0].astype(np.int32)
        a1 = blocks[:, :, 1].astype(np.int32)
        abits = np.zeros((bh, bw), dtype=np.uint64)
        for k in range(6):
            abits |= blocks[:, :, 2 + k].astype(np.uint64) << (8 * k)
        apal = np.zeros((bh, bw, 8), dtype=np.uint8)
        apal[:, :, 0] = a0
        apal[:, :, 1] = a1
        gt = a0 > a1
        for i in range(1, 7):
            v_gt = ((7 - i) * a0 + i * a1) // 7
            if i <= 4:
                v_le = ((5 - i) * a0 + i * a1) // 5
            elif i == 5:
                v_le = np.zeros_like(a0)
            else:
                v_le = np.full_like(a0, 255)
            apal[:, :, i + 1] = np.where(gt, v_gt, v_le)
        aidx = np.stack([((abits >> (3 * k)) & 7) for k in range(16)], axis=-1).astype(np.int32)
        alpha = np.take_along_axis(apal, aidx, axis=-1)
        alpha_img = alpha.reshape(bh, bw, 4, 4).transpose(0, 2, 1, 3).reshape(bh * 4, bw * 4)[:height, :width]
        if l8_alpha_only:
            return alpha_img

        c0 = blocks[:, :, 8].astype(np.int32) | (blocks[:, :, 9].astype(np.int32) << 8)
        c1 = blocks[:, :, 10].astype(np.int32) | (blocks[:, :, 11].astype(np.int32) << 8)
        pal = _decode_rgb565_lut(c0, c1, has_alpha_punch=False)
        cbits = (
            blocks[:, :, 12].astype(np.uint32)
            | (blocks[:, :, 13].astype(np.uint32) << 8)
            | (blocks[:, :, 14].astype(np.uint32) << 16)
            | (blocks[:, :, 15].astype(np.uint32) << 24)
        )
        cidx = np.stack([((cbits >> (2 * k)) & 3) for k in range(16)], axis=-1).astype(np.int32)
        rgba = np.take_along_axis(pal, cidx[:, :, :, None], axis=2)
        rgba_img = (
            rgba.reshape(bh, bw, 4, 4, 4)
            .transpose(0, 2, 1, 3, 4)
            .reshape(bh * 4, bw * 4, 4)[:height, :width]
            .copy()
        )
        rgba_img[:, :, 3] = alpha_img
        return rgba_img

    raise NotImplementedError(f"不支持的 DDS FourCC: {fourcc!r}")


def decode_dds_image(
    data: bytes,
    l8_alpha_only: bool = False,
    crop: Optional[Tuple[int, int, int, int]] = None,
) -> Image.Image:
    """将 DDS 解码为 PIL Image（可选裁剪矩形 x, y, w, h）。"""
    arr = decode_dds_array(data, l8_alpha_only=l8_alpha_only)
    if crop is not None:
        x, y, w, h = crop
        arr = arr[y : y + h, x : x + w]
    mode = "L" if l8_alpha_only else "RGBA"
    return Image.fromarray(arr, mode=mode)
