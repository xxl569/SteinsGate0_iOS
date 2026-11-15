# -*- coding: utf-8 -*-
"""MAGES. / 5pb. MPK v2.0 封包解析与多封包虚拟文件系统原型。"""

from __future__ import annotations

import os
import struct
from dataclasses import dataclass
from typing import Dict, List, Optional


MPK_MAGIC = b"MPK\x00"
MPK_HEADER_SIZE = 64
MPK_ENTRY_SIZE = 256


@dataclass(frozen=True)
class MpkEntry:
    """MPK 内部单条资源索引记录。"""

    archive: str
    index: int
    compressed: int
    offset: int
    size: int
    uncompressed_size: int
    name: str


class MpkArchive:
    """单个 MPK v2.0 封包读取器（支持零拷贝偏移流式读取）。"""

    def __init__(self, path: str) -> None:
        self.path = path
        self.archive_name = os.path.basename(path)
        self.entries: List[MpkEntry] = []
        self._by_lower: Dict[str, MpkEntry] = {}
        self._parse_toc()

    def _parse_toc(self) -> None:
        with open(self.path, "rb") as f:
            header = f.read(MPK_HEADER_SIZE)
            if len(header) < 12 or header[:4] != MPK_MAGIC:
                raise ValueError(f"无效 MPK 头: {self.path}")
            ver_minor, ver_major, count = struct.unpack("<HHI", header[4:12])
            if ver_major != 2:
                raise ValueError(f"不支持的 MPK 主版本 {ver_major}.{ver_minor}: {self.path}")
            toc_bytes = f.read(count * MPK_ENTRY_SIZE)
            if len(toc_bytes) != count * MPK_ENTRY_SIZE:
                raise ValueError(f"MPK 目录表截断: {self.path}")

            for i in range(count):
                rec = toc_bytes[i * MPK_ENTRY_SIZE : (i + 1) * MPK_ENTRY_SIZE]
                comp, idx, off, sz, usz = struct.unpack("<IIQQQ", rec[:32])
                raw_name = rec[32:MPK_ENTRY_SIZE].split(b"\x00", 1)[0]
                name = raw_name.decode("utf-8", errors="replace")
                entry = MpkEntry(
                    archive=self.archive_name,
                    index=idx,
                    compressed=comp,
                    offset=off,
                    size=sz,
                    uncompressed_size=usz,
                    name=name,
                )
                self.entries.append(entry)
                self._by_lower[name.lower()] = entry

    def get_entry(self, name: str) -> Optional[MpkEntry]:
        return self._by_lower.get(name.lower())

    def read_entry(self, name: str) -> bytes:
        entry = self.get_entry(name)
        if entry is None:
            raise KeyError(f"{self.archive_name} 中未找到条目: {name}")
        return self.read_by_entry(entry)

    def read_by_entry(self, entry: MpkEntry) -> bytes:
        if entry.compressed != 0:
            raise NotImplementedError(
                f"检测到压缩条目 comp={entry.compressed}: {entry.archive}:{entry.name}"
            )
        with open(self.path, "rb") as f:
            f.seek(entry.offset)
            data = f.read(entry.size)
        if len(data) != entry.size:
            raise IOError(
                f"短读错误 {entry.archive}:{entry.name}: 期望 {entry.size}, 实际 {len(data)}"
            )
        return data


class MgsMpkVfs:
    """挂载 USRDIR 下所有活跃 MPK（自动剔除 *_bak.mpk 与 PC shader 包）。"""

    ACTIVE_ARCHIVES = (
        "bg.mpk",
        "bgm.mpk",
        "chara.mpk",
        "manual.mpk",
        "mask.mpk",
        "script.mpk",
        "se.mpk",
        "system.mpk",
        "voice.mpk",
    )

    def __init__(self, usrdir: str, include_pc_shaders: bool = False) -> None:
        self.usrdir = usrdir
        self.archives: Dict[str, MpkArchive] = {}
        names = list(self.ACTIVE_ARCHIVES)
        if include_pc_shaders:
            names.extend(("shader.mpk", "mgsshader.mpk"))
        for fname in names:
            full = os.path.join(usrdir, fname)
            if os.path.isfile(full):
                self.archives[fname.lower()] = MpkArchive(full)

    def get_archive(self, archive: str) -> MpkArchive:
        key = archive.lower()
        if not key.endswith(".mpk"):
            key += ".mpk"
        if key not in self.archives:
            raise KeyError(f"未挂载封包: {archive}")
        return self.archives[key]

    def read(self, archive: str, entry_name: str) -> bytes:
        return self.get_archive(archive).read_entry(entry_name)

    def read_by_index(self, archive: str, index: int) -> bytes:
        arc = self.get_archive(archive)
        if index < 0 or index >= len(arc.entries):
            raise IndexError(f"{archive} 索引越界: {index}")
        return arc.read_by_entry(arc.entries[index])
