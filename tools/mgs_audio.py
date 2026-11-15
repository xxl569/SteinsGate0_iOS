# -*- coding: utf-8 -*-
"""MAGES. Ogg 循环点提取与 WAVTABLE.DAT 口型包络解析原型。"""

from __future__ import annotations

import re
import struct
from dataclasses import dataclass
from typing import List, Optional, Tuple


_LOOPSTART_RE = re.compile(rb"LOOPSTART=(\d+)", re.IGNORECASE)
_LOOPLENGTH_RE = re.compile(rb"LOOPLENGTH=(\d+)", re.IGNORECASE)


@dataclass(frozen=True)
class OggLoopInfo:
    sample_rate: int
    channels: int
    loop_start: int
    loop_length: int
    has_loop: bool


def parse_ogg_loop_info(ogg_bytes: bytes) -> OggLoopInfo:
    """从 Ogg Vorbis 头部与 VorbisComment 提取采样率、声道数与 LOOPSTART/LOOPLENGTH。"""
    if len(ogg_bytes) < 64 or ogg_bytes[:4] != b"OggS":
        raise ValueError("无效 Ogg 流")

    sample_rate = 44100
    channels = 2
    idx = ogg_bytes.find(b"\x01vorbis")
    if idx >= 0 and idx + 16 <= len(ogg_bytes):
        channels = ogg_bytes[idx + 11]
        sample_rate = struct.unpack("<I", ogg_bytes[idx + 12 : idx + 16])[0]

    head = ogg_bytes[: min(len(ogg_bytes), 16384)]
    m_start = _LOOPSTART_RE.search(head)
    m_len = _LOOPLENGTH_RE.search(head)
    loop_start = int(m_start.group(1)) if m_start else 0
    loop_length = int(m_len.group(1)) if m_len else 0
    has_loop = (m_start is not None) and (m_len is not None) and (loop_length > 0)
    return OggLoopInfo(
        sample_rate=sample_rate,
        channels=channels,
        loop_start=loop_start,
        loop_length=loop_length,
        has_loop=has_loop,
    )


class WavTable:
    """WAVTABLE.DAT 语音口型包络表解析器。"""

    def __init__(self, data: bytes) -> None:
        if len(data) < 4:
            raise ValueError("WAVTABLE.DAT 过短")
        self.count = struct.unpack(">H", data[:2])[0]
        table_end = (1 + self.count) * 4
        if len(data) < table_end:
            raise ValueError(f"WAVTABLE.DAT 目录截断: {len(data)} < {table_end}")
        self.records: List[Tuple[int, int]] = []
        for i in range(self.count):
            off = 4 + i * 4
            word_off, length_units = struct.unpack(">HH", data[off : off + 4])
            self.records.append((word_off, length_units))
        self.payload_offset = table_end
        self.data = data

    def get_lipsync_frames(self, voice_index: int) -> List[int]:
        """提取指定语音索引的 2-bit 口型张合度帧序列 (0..3，6Hz/约167ms一帧，LSB优先)。"""
        if voice_index < 0 or voice_index >= self.count:
            raise IndexError(f"语音索引越界: {voice_index}")
        word_off, sample_count = self.records[voice_index]
        byte_start = self.payload_offset + word_off * 4
        byte_len = ((sample_count + 15) // 16) * 4
        chunk = self.data[byte_start : min(len(self.data), byte_start + byte_len)]
        frames: List[int] = []
        for b in chunk:
            for shift in (0, 2, 4, 6):
                if len(frames) >= sample_count:
                    return frames
                frames.append((b >> shift) & 3)
        return frames[:sample_count]
