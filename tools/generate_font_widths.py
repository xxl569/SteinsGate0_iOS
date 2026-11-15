# -*- coding: utf-8 -*-
"""扫描 FONT_A/B.DDS 与 FONT2_A/B.DDS 字形边界并导出 assets/tables/font_widths.bin。

二进制格式 (little-endian):
  header (16 bytes):
    magic: 4s = b"FWT1"
    cell_size: uint16 = 48
    font_a_slots: uint16 = 5440  (64 * 85)
    font_b_slots: uint16 = 2560  (64 * 40)
    total_slots: uint16 = 8000
    reserved: uint32 = 0
  records (2 sets * 8000 slots * 3 bytes = 48,000 bytes):
    Set 0 (FONT_A + FONT_B): 8000 * (uint8 x0, uint8 x1, uint8 advance)
    Set 1 (FONT2_A + FONT2_B): 8000 * (uint8 x0, uint8 x1, uint8 advance)
"""

from __future__ import annotations

import os
import struct
import sys
from typing import List, Tuple
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mgs_dds import decode_dds_array
from mgs_mpk import MgsMpkVfs


CELL_SIZE = 48
COLS = 64
FONT_A_SLOTS = 64 * 85   # 5440
FONT_B_SLOTS = 64 * 40   # 2560
TOTAL_SLOTS = FONT_A_SLOTS + FONT_B_SLOTS  # 8000


def measure_font_set(alpha_a: np.ndarray, alpha_b: np.ndarray) -> List[Tuple[int, int, int]]:
    """测量单套字库 (A+B 共 8000 槽位) 的左右边界与推进步长。"""
    records: List[Tuple[int, int, int]] = []
    for gid in range(TOTAL_SLOTS):
        if gid < FONT_A_SLOTS:
            atlas = alpha_a
            local = gid
        else:
            atlas = alpha_b
            local = gid - FONT_A_SLOTS
        row, col = divmod(local, COLS)
        y0, x_off = row * CELL_SIZE, col * CELL_SIZE
        cell = atlas[y0 : y0 + CELL_SIZE, x_off : x_off + CELL_SIZE]
        if cell.max() <= 8:
            # 空白槽位：半角空格(0)按24，其余全角空白按48（或24）
            adv = 24 if gid < 128 else 48
            records.append((0, 0, adv))
            continue
        col_mask = cell.max(axis=0) > 8
        xs = np.where(col_mask)[0]
        x0 = int(xs[0])
        x1 = int(xs[-1])
        if gid < 128:
            # 0..127 为半角字符（原图已居中于 0..23 区域）
            adv = max(14, min(26, (x1 - x0 + 1) + 4))
        else:
            # 全角字符及标点：汉字固定 48，极窄标点如顿号/句号保留适度紧凑宽度或 48
            span = x1 - x0 + 1
            if span <= 22 and x1 <= 26:
                adv = max(24, min(48, x1 + 6))
            else:
                adv = 48
        records.append((x0, x1, adv))
    return records


def generate_font_widths(usrdir: str, out_path: str) -> bytes:
    """从 USRDIR/system.mpk 提取四张字库 DDS 并写出 font_widths.bin。"""
    vfs = MgsMpkVfs(usrdir)
    a1 = decode_dds_array(vfs.read("system.mpk", "FONT_A.DDS"), l8_alpha_only=True)
    b1 = decode_dds_array(vfs.read("system.mpk", "FONT_B.DDS"), l8_alpha_only=True)
    a2 = decode_dds_array(vfs.read("system.mpk", "FONT2_A.DDS"), l8_alpha_only=True)
    b2 = decode_dds_array(vfs.read("system.mpk", "FONT2_B.DDS"), l8_alpha_only=True)

    rec1 = measure_font_set(a1, b1)
    rec2 = measure_font_set(a2, b2)

    buf = bytearray()
    buf.extend(
        struct.pack(
            "<4sHHHHI",
            b"FWT1",
            CELL_SIZE,
            FONT_A_SLOTS,
            FONT_B_SLOTS,
            TOTAL_SLOTS,
            0,
        )
    )
    for x0, x1, adv in rec1:
        buf.extend(struct.pack("<BBB", x0, x1, adv))
    for x0, x1, adv in rec2:
        buf.extend(struct.pack("<BBB", x0, x1, adv))

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "wb") as f:
        f.write(buf)
    return bytes(buf)


if __name__ == "__main__":
    usr = r"U:\anti\projects\STEINS GATE 0\USRDIR"
    out = r"U:\anti\projects\SteinsGate0_iOS\assets\tables\font_widths.bin"
    raw = generate_font_widths(usr, out)
    print(f"已生成 {out} ({len(raw)} 字节)")
