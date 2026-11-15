# -*- coding: utf-8 -*-
"""阶段一资产全库校验脚本：遍历 9 个活跃 MPK 共 17,697 条目并验证解码无误。"""

from __future__ import annotations

import io
import os
import sys
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mgs_audio import WavTable, parse_ogg_loop_info
from mgs_dds import decode_dds_array, parse_dds_header
from mgs_lay import compose_lay_sprite, parse_lay
from mgs_mpk import MgsMpkVfs


def verify_all(usrdir: str) -> dict:
    vfs = MgsMpkVfs(usrdir, include_pc_shaders=False)
    stats = {}

    # 1. bg.mpk (709 PNG)
    bg_arc = vfs.get_archive("bg.mpk")
    bg_non1080 = 0
    for e in bg_arc.entries:
        raw = bg_arc.read_by_entry(e)
        if not raw.startswith(b"\x89PNG\r\n\x1a\n"):
            raise AssertionError(f"bg 非 PNG: {e.name}")
        im = Image.open(io.BytesIO(raw))
        im.verify()
        if im.size != (1920, 1080):
            bg_non1080 += 1
    stats["bg"] = (len(bg_arc.entries), bg_non1080)

    # 2. chara.mpk (769 .lay + 769 .png)
    ch_arc = vfs.get_archive("chara.mpk")
    lays = [e for e in ch_arc.entries if e.name.lower().endswith(".lay")]
    pngs = [e for e in ch_arc.entries if e.name.lower().endswith(".png")]
    # 全量验证 769 组 .lay <-> .png 一一对应，并抽检标准与带 tail 变体拼图
    std_sample = None
    odd_sample = None
    for e in lays:
        stem = e.name[:-5]  # 去掉 "_.lay"
        assert ch_arc.get_entry(f"{stem}.png") is not None, f"缺少对应 PNG: {stem}.png"
        lay_obj = parse_lay(ch_arc.read_by_entry(e))
        if lay_obj.has_tail_hints and odd_sample is None:
            odd_sample = stem
        elif not lay_obj.has_tail_hints and std_sample is None:
            std_sample = stem
    for stem in (std_sample, odd_sample, "AKG_ALA", "AKG_ALC", "CRS_ALA"):
        assert stem is not None
        lay_raw = ch_arc.read_entry(f"{stem}_.lay")
        png_raw = ch_arc.read_entry(f"{stem}.png")
        lay_obj = parse_lay(lay_raw)
        gids = [g.group_id for g in lay_obj.groups[:2]]
        img, origin = compose_lay_sprite(lay_raw, png_raw, gids)
        assert img.width > 10 and img.height > 10, f"拼图失败: {stem}"
    stats["chara"] = (len(lays), len(pngs))

    # 3. system.mpk + manual.mpk (32 DDS + WAVTABLE.DAT)
    dds_count = 0
    for arc_name in ("system.mpk", "manual.mpk"):
        arc = vfs.get_archive(arc_name)
        for e in arc.entries:
            raw = arc.read_by_entry(e)
            if e.name.lower().endswith(".dds"):
                w, h, fourcc = parse_dds_header(raw)
                is_font = "FONT" in e.name.upper()
                arr = decode_dds_array(raw, l8_alpha_only=is_font)
                assert arr.shape[0] == h and arr.shape[1] == w
                dds_count += 1
            elif e.name.upper() == "WAVTABLE.DAT":
                wt = WavTable(raw)
                voice_cnt = len(vfs.get_archive("voice.mpk").entries)
                assert wt.count == voice_cnt, f"WAVTABLE 计数不一致: {wt.count} != {voice_cnt}"
                for vi in (0, 1, 100, wt.count - 1):
                    frames = wt.get_lipsync_frames(vi)
                    assert len(frames) == wt.records[vi][1]
                stats["wavtable"] = wt.count
    stats["dds"] = dds_count

    # 4. mask.mpk (20 PNG)
    mk_arc = vfs.get_archive("mask.mpk")
    for e in mk_arc.entries:
        raw = mk_arc.read_by_entry(e)
        im = Image.open(io.BytesIO(raw))
        im.verify()
    stats["mask"] = len(mk_arc.entries)

    # 5. bgm.mpk + se.mpk + voice.mpk (Ogg 全量校验)
    ogg_total = 0
    bgm_loops = 0
    for arc_name in ("bgm.mpk", "se.mpk", "voice.mpk"):
        arc = vfs.get_archive(arc_name)
        for e in arc.entries:
            raw = arc.read_by_entry(e)
            info = parse_ogg_loop_info(raw)
            assert info.sample_rate > 0 and info.channels in (1, 2)
            if arc_name == "bgm.mpk" and info.has_loop:
                bgm_loops += 1
            ogg_total += 1
    stats["ogg_total"] = ogg_total
    stats["bgm_loops"] = bgm_loops

    # 6. script.mpk
    sc_arc = vfs.get_archive("script.mpk")
    for e in sc_arc.entries:
        raw = sc_arc.read_by_entry(e)
        assert raw[:4] == b"SC3\x00", f"非 SC3 头: {e.name}"
    stats["script"] = len(sc_arc.entries)
    stats["total_entries"] = sum(len(a.entries) for a in vfs.archives.values())
    return stats


if __name__ == "__main__":
    usr = r"U:\anti\projects\STEINS GATE 0\USRDIR"
    res = verify_all(usr)
    print("全库校验通过:", res)
