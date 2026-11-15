# -*- coding: utf-8 -*-
"""阶段一 Python 原型单元测试（MPK / DDS / LAY / WAVTABLE / Ogg / FontWidths）。"""

import os
import struct
import sys
import unittest

TOOLS_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "tools"))
sys.path.insert(0, TOOLS_DIR)

from generate_font_widths import generate_font_widths
from mgs_audio import WavTable, parse_ogg_loop_info
from mgs_dds import decode_dds_array, decode_dds_image
from mgs_lay import compose_lay_sprite, parse_lay
from mgs_mpk import MgsMpkVfs

USRDIR = r"U:\anti\projects\STEINS GATE 0\USRDIR"
FONT_BIN = r"U:\anti\projects\SteinsGate0_iOS\assets\tables\font_widths.bin"


class TestPhase1Tools(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.vfs = MgsMpkVfs(USRDIR)

    def test_active_mpk_counts(self) -> None:
        total = sum(len(a.entries) for a in self.vfs.archives.values())
        self.assertEqual(len(self.vfs.archives), 9)
        self.assertEqual(total, 17697)

    def test_dds_l8_and_rgba8(self) -> None:
        font_a = decode_dds_array(self.vfs.read("system.mpk", "FONT_A.DDS"), l8_alpha_only=True)
        self.assertEqual(font_a.shape, (4096, 3072))
        self.assertEqual(font_a.dtype.name, "uint8")
        # 槽位 0x1e ('T') 应有非零像素
        self.assertGreater(font_a[0:48, 30 * 48 : 31 * 48].max(), 200)

        help_im = decode_dds_image(self.vfs.read("system.mpk", "HELP.DDS"), l8_alpha_only=False)
        self.assertEqual(help_im.size, (1920, 1080))
        self.assertEqual(help_im.mode, "RGBA")

    def test_lay_both_variants_compose(self) -> None:
        lay_std = parse_lay(self.vfs.read("chara.mpk", "AKG_ALA_.lay"))
        self.assertFalse(lay_std.has_tail_hints)
        self.assertGreater(len(lay_std.groups), 10)

        lay_odd = parse_lay(self.vfs.read("chara.mpk", "AKG_ALC_.lay"))
        self.assertTrue(lay_odd.has_tail_hints)
        img, origin = compose_lay_sprite(
            self.vfs.read("chara.mpk", "AKG_ALC_.lay"),
            self.vfs.read("chara.mpk", "AKG_ALC.png"),
            (1,),
        )
        self.assertGreater(img.width, 100)
        self.assertGreater(img.height, 100)
        self.assertLess(origin[0], 0)

    def test_ogg_loop_and_wavtable(self) -> None:
        bgm = parse_ogg_loop_info(self.vfs.read("bgm.mpk", "bgm201.ogg"))
        self.assertTrue(bgm.has_loop)
        self.assertEqual(bgm.sample_rate, 48000)
        self.assertEqual(bgm.loop_start, 1863904)
        self.assertEqual(bgm.loop_length, 9207908)

        wt = WavTable(self.vfs.read("system.mpk", "WAVTABLE.DAT"))
        self.assertEqual(wt.count, 14847)
        frames = wt.get_lipsync_frames(1)
        self.assertEqual(len(frames), 28)
        self.assertTrue(all(0 <= v <= 3 for v in frames))

    def test_font_widths_bin(self) -> None:
        raw = generate_font_widths(USRDIR, FONT_BIN)
        magic, cell, a_slots, b_slots, total, _ = struct.unpack("<4sHHHHI", raw[:16])
        self.assertEqual(magic, b"FWT1")
        self.assertEqual(cell, 48)
        self.assertEqual(a_slots, 5440)
        self.assertEqual(b_slots, 2560)
        self.assertEqual(total, 8000)
        self.assertEqual(len(raw), 16 + 2 * 8000 * 3)

    def test_sc3_scanner_and_strings(self):
        from mgs_mpk import MgsMpkVfs
        import scan_sc3

        # 1. 验证内联控制标签 0x04 / 0x15 / 0x13 / 0x09-0x0b / 0xFF 解码
        vfs = MgsMpkVfs(USRDIR)
        d_m01 = vfs.read("script.mpk", "SG0_M01_07.scx")
        hdr_m01 = scan_sc3.parse_scx_header(d_m01)
        s270 = scan_sc3.decode_scx_string(d_m01, hdr_m01["str_offsets"][270])
        self.assertIn((0x15, "EvalExpr", "GetFlag 90 = 0"), s270["tags"])

        d_mac2 = vfs.read("script.mpk", "macrosys2.scx")
        hdr_mac2 = scan_sc3.parse_scx_header(d_mac2)
        s31 = scan_sc3.decode_scx_string(d_mac2, hdr_mac2["str_offsets"][31])
        self.assertEqual([t[2] for t in s31["tags"] if t[0] == 0x13], [12, 13, 11, 11])

        # 2. 验证全量 178 个 SCX 文件扫描无误且剧情文件零异常空洞
        res = scan_sc3.scan_archive(USRDIR, report_path=None)
        self.assertEqual(res["n_files"], 178)
        self.assertEqual(res["bad_files"], [])
        self.assertEqual(res["story_gaps"], [])
        self.assertEqual(res["n_strings"], 30580)
        self.assertEqual(res["glyph_range"], (0, 7440))


if __name__ == "__main__":
    unittest.main()
