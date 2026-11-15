# -*- coding: utf-8 -*-
"""MAGES. .lay 瓦片布局解析与立绘合成原型。"""

from __future__ import annotations

import io
import struct
from dataclasses import dataclass
from typing import Dict, Iterable, List, Optional, Sequence, Tuple
from PIL import Image


@dataclass(frozen=True)
class LayGroup:
    group_id: int
    start: int
    count: int


@dataclass(frozen=True)
class LayTile:
    dest_x: float
    dest_y: float
    src_u: float
    src_v: float
    opaque_hint: int


@dataclass
class LayData:
    groups: List[LayGroup]
    tiles: List[LayTile]
    has_tail_hints: bool

    def find_group(self, group_id: int) -> Optional[LayGroup]:
        for g in self.groups:
            if g.group_id == group_id:
                return g
        return None


def parse_lay(data: bytes) -> LayData:
    """解析 .lay 文件（同时兼容标准 16B 与末尾带 n_tiles 字节不透明掩码的变体）。"""
    if len(data) < 8:
        raise ValueError("无效 .lay 数据（不足 8 字节）")
    n_groups, n_tiles = struct.unpack("<II", data[:8])
    base_size = 8 + n_groups * 12 + n_tiles * 16
    if len(data) == base_size:
        has_tail = False
    elif len(data) == base_size + n_tiles:
        has_tail = True
    else:
        raise ValueError(
            f".lay 长度不匹配: size={len(data)}, n_groups={n_groups}, n_tiles={n_tiles}"
        )

    groups: List[LayGroup] = []
    off = 8
    for _ in range(n_groups):
        gid, start, cnt = struct.unpack("<III", data[off : off + 12])
        groups.append(LayGroup(gid, start, cnt))
        off += 12

    tiles: List[LayTile] = []
    tail_off = base_size
    for i in range(n_tiles):
        dx, dy, su, sv = struct.unpack("<ffff", data[off : off + 16])
        hint = data[tail_off + i] if has_tail else 0
        tiles.append(LayTile(dx, dy, su, sv, hint))
        off += 16

    return LayData(groups=groups, tiles=tiles, has_tail_hints=has_tail)


def compose_lay_sprite(
    lay_bytes: bytes,
    png_bytes: bytes,
    group_ids: Sequence[int] = (1,),
) -> Tuple[Image.Image, Tuple[int, int]]:
    """按指定 group_id 列表拼装立绘，返回 (RGBA Image, (origin_x, origin_y))。

    origin_x / origin_y 表示画布左上角在 .lay 坐标系下的原点偏移，
    实际舞台绘制位置 = anchor_pos + (origin_x, origin_y)。
    """
    lay = parse_lay(lay_bytes)
    atlas = Image.open(io.BytesIO(png_bytes)).convert("RGBA")

    selected_tiles: List[LayTile] = []
    for gid in group_ids:
        grp = lay.find_group(gid)
        if grp is None:
            continue
        selected_tiles.extend(lay.tiles[grp.start : grp.start + grp.count])

    if not selected_tiles:
        return Image.new("RGBA", (1, 1), (0, 0, 0, 0)), (0, 0)

    min_x = min(int(round(t.dest_x)) for t in selected_tiles)
    min_y = min(int(round(t.dest_y)) for t in selected_tiles)
    max_x = max(int(round(t.dest_x)) + 30 for t in selected_tiles)
    max_y = max(int(round(t.dest_y)) + 30 for t in selected_tiles)

    w = max(1, max_x - min_x)
    h = max(1, max_y - min_y)
    canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))

    aw, ah = atlas.size
    for t in selected_tiles:
        sx = int(round(t.src_u))
        sy = int(round(t.src_v))
        dx = int(round(t.dest_x)) - min_x
        dy = int(round(t.dest_y)) - min_y
        if sx < 0 or sy < 0 or sx + 30 > aw or sy + 30 > ah:
            continue
        tile_img = atlas.crop((sx, sy, sx + 30, sy + 30))
        if t.opaque_hint == 1:
            canvas.paste(tile_img, (dx, dy))
        else:
            canvas.alpha_composite(tile_img, (dx, dy))

    return canvas, (min_x, min_y)
