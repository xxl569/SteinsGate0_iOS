#!/usr/bin/env python3
"""
STEINS;GATE 0 SC3 脚本全量扫描与静态逆向分析工具。

基于对 Game.exe 调度表（TBL_00=0xD286F0、TBL_01=0xD28458、TBL_10=0xD29668）、
表达式求值器（0x41a740 / 0x41ac00）与字符串控制标签解析器（0x445790）的精确逆向结果，
对 script.mpk 内全部 .scx 文件执行控制流遍历、操作码统计、字符串标签与字形 ID 审计，
并识别 RINE/手机系统/TIPS/滤镜相关变量区间，输出 docs/sc3_opcodes_report.md。
"""

from __future__ import annotations

import argparse
import struct
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

# 允许直接从仓库根目录或 tools 目录导入同级模块
TOOLS_DIR = Path(__file__).resolve().parent
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

from mgs_mpk import MgsMpkVfs  # noqa: E402

# ---------------- 表达式操作符定义（来自 Game.exe 0x41a740 & 0x41acc0） ----------------
EXPR_OPS: dict[int, str] = {
    0x01: "*",
    0x02: "/",
    0x03: "+",
    0x04: "-",
    0x05: "%",
    0x06: "<<",
    0x07: ">>",
    0x08: "&",
    0x09: "^",
    0x0A: "|",
    0x0B: "~",
    0x0C: "==",
    0x0D: "!=",
    0x0E: "<=",
    0x0F: ">=",
    0x10: "<",
    0x11: ">",
    0x14: "=",
    0x15: "*=",
    0x16: "/=",
    0x17: "+=",
    0x18: "-=",
    0x19: "%=",
    0x1A: "<<=",
    0x1B: ">>=",
    0x1C: "&=",
    0x1D: "|=",
    0x1E: "^=",
    0x20: "++",
    0x21: "--",
    0x28: "ScrWork",
    0x29: "GetFlag",
    0x2A: "DataU32",
    0x2B: "LabelAddr",
    0x2C: "ScriptTbl",
    0x2D: "ThreadVar",
    0x2E: "ScriptVal",
    0x2F: "SysVarA",
    0x30: "SysVarB",
    0x33: "Random",
}

# ---------------- SC3 操作码助记符映射 ----------------
OP_NAMES: dict[str, str] = {
    "FE": "ExprStmt",
    "0000": "End",
    "0001": "CreateThread",
    "0002": "KillThread",
    "0003": "Reset",
    "0004": "ScriptLoad",
    "0005": "Wait",
    "0006": "Halt",
    "0007": "Jump",
    "0008": "JumpTable",
    "000a": "If",
    "000b": "Call",
    "000c": "JumpFarCond",
    "000d": "CallFar",
    "000e": "Return",
    "000f": "Loop",
    "0010": "JumpIfFlag",
    "0011": "SetFlag",
    "0012": "ResetFlag",
    "0013": "CopyFlag",
    "0014": "PlayBGM",
    "0015": "PlayBGMEx",
    "0016": "StopBGM",
    "0017": "FadeBGM",
    "0018": "PlaySE",
    "0019": "StopSE",
    "001a": "WaitBGM",
    "001b": "SwitchScript",
    "001f": "SetThreadGroup",
    "0020": "WaitThreadGroup",
    "0021": "BGMFadeOrSync",
    "0022": "SetFlagU8",
    "0023": "BGExControl",
    "0024": "TimerControl",
    "0025": "Audio3DControl",
    "0026": "WaitTimer",
    "0028": "ViewportOrCam",
    "0029": "SystemSub29",
    "002a": "ReturnIfWait",
    "002c": "KeyConfigOrPad",
    "002e": "SoundFadeCtrl",
    "002f": "ScreenFadeCtrl",
    "0030": "GlobalCtrl30",
    "0031": "WaitSE",
    "0032": "SyncWait32",
    "0033": "SetWorkOrWait",
    "0034": "YieldReset",
    "0035": "Sub35",
    "0037": "ScreenEffect37",
    "0038": "VoiceChannel",
    "003a": "Sub3A",
    "003b": "Sub3B",
    "003d": "Sub3D",
    "003e": "Sub3E",
    "003f": "Sub3F",
    "0042": "Sub42",
    "0043": "TitleOrSystem43",
    "0044": "Sub44",
    "0046": "Sub46",
    "0048": "WaitForever",
    "004b": "Sub4B",
    "004c": "Sub4C",
    "0050": "CondJump50",
    "0051": "Sub51",
    "0053": "Sub53Data",
    "0054": "CallIf54",
    "0056": "CallFarIf56",
    "0058": "DataLoad58",
    "0059": "JumpIf59",
    "005f": "Sub5F",
    "0100": "CreateSurf",
    "0101": "ReleaseSurf",
    "0102": "LoadPic",
    "0105": "DispCtrl",
    "0108": "BGSwapOrFade",
    "0109": "MesWindow",
    "010a": "MesMode",
    "010b": "MesClear",
    "010c": "Mes",
    "010d": "MesMain",
    "010e": "SetMesMacro",
    "010f": "MesFontLoad",
    "0110": "SetChoiceCtrl",
    "0111": "MesSync",
    "0112": "Select",
    "0113": "SelectWait",
    "0114": "MesVoiceWait",
    "0115": "ChaCtrl",
    "0121": "LoadMask",
    "0122": "MoviePlay",
    "0123": "MovieCtrl",
    "0124": "MovieWait",
    "0125": "Effect125",
    "0126": "MovieEx126",
    "012b": "Effect12B",
    "1000": "SG0_InitOrMode",
    "1001": "SG0_BgChaCtrl",
    "1002": "SG0_VoiceOrLip",
    "1004": "SG0_SpriteAnim",
    "1005": "SG0_ChaLoad",
    "1006": "SG0_ChaRelease",
    "100b": "SG0_ChaSync",
    "1010": "SG0_System1010",
    "1011": "SG0_System1011",
    "1013": "SG0_SaveLoadMenu",
    "1014": "SG0_SysMenu",
    "101a": "SG0_Sub101A",
    "101b": "SG0_Sub101B",
    "101d": "SG0_Sub101D",
    "101f": "SG0_Sub101F",
    "1020": "SG0_Sub1020",
    "1021": "SG0_Sub1021",
    "1022": "SG0_PhoneCtrl",
    "1023": "SG0_TipsCtrl",
    "1024": "SG0_Achievement",
    "1027": "SG0_Sub1027",
    "1028": "SG0_Sub1028",
    "1029": "SG0_SysCall1029",
    "102a": "SG0_Sub102A",
    "102d": "SG0_Sub102D",
    "1030": "SG0_GalleryOrMusic",
    "1033": "SG0_HelpCtrl",
    "1034": "SG0_AmadeusOrExtra",
    "1037": "SG0_RineCtrl",
    "1040": "SG0_Sub1040",
    "1041": "SG0_Sub1041",
}

# ---------------- 字符串控制标签定义（来自 Game.exe 0x445790） ----------------
STR_TAG_INFO: dict[int, tuple[str, str]] = {
    0x00: ("LineBreak", "none"),
    0x01: ("NameStart", "none"),
    0x02: ("NameEnd", "none"),
    0x03: ("WaitClick", "none"),
    0x04: ("SetColor", "expr"),
    0x05: ("Tag05", "none"),
    0x06: ("Tag06", "none"),
    0x07: ("SetMarginX", "u8"),
    0x08: ("AutoWait", "none"),
    0x09: ("RubyBaseStart", "none"),
    0x0A: ("RubyTextStart", "none"),
    0x0B: ("RubyTextEnd", "none"),
    0x0C: ("SetFontSize", "u16be"),
    0x0D: ("Tag0D", "none"),
    0x0E: ("Center", "none"),
    0x0F: ("RubyAlignStart", "none"),
    0x10: ("RubyAlignEnd", "none"),
    0x11: ("SetPosX", "u16be"),
    0x12: ("SetPosXY", "u16be"),
    0x13: ("PrintScrWork", "u16be"),
    0x14: ("PrintScrWorkAlt", "u16be"),
    0x15: ("EvalExpr", "expr"),
    0x16: ("Tag16", "u16be"),
    0x17: ("Tag17", "none"),
    0x18: ("Tag18", "none"),
    0x19: ("SetSpacing", "u16be"),
    0x1A: ("Tag1A", "u16be"),
    0x1B: ("SetByte1B", "u8"),
    0x1C: ("Tag1C", "none"),
    0x1D: ("Tag1D", "none"),
    0x1E: ("RubyDot", "none"),
    0x1F: ("AltLineEnd", "none"),
}


def u16_le(buf: bytes, pos: int) -> int:
    return struct.unpack_from("<H", buf, pos)[0]


def u32_le(buf: bytes, pos: int) -> int:
    return struct.unpack_from("<I", buf, pos)[0]


def skip_expr(buf: bytes, pos: int) -> tuple[int, list[int], list[int]]:
    """
    跳过并统计一段 SC3 后缀/中缀表达式字节流（遵循 Game.exe 0x41ac00 / 0x41a740）。
    返回 (结束位置, 操作符列表, 立即数常量列表)。
    """
    start = pos
    ops_seen: list[int] = []
    consts: list[int] = []
    n = len(buf)
    while pos < n:
        b0 = buf[pos]
        if b0 == 0x00:
            return pos + 1, ops_seen, consts
        if b0 & 0x80:
            sz_cls = b0 & 0x60
            if sz_cls == 0x00:
                val = b0 & 0x1F
                if b0 & 0x10:
                    val -= 32
                consts.append(val)
                pos += 2
            elif sz_cls == 0x20:
                val = ((b0 & 0x1F) << 8) | buf[pos + 1]
                if b0 & 0x10:
                    val -= 0x2000
                consts.append(val)
                pos += 3
            elif sz_cls == 0x40:
                val = ((b0 & 0x1F) << 16) | (buf[pos + 2] << 8) | buf[pos + 1]
                if b0 & 0x10:
                    val -= 0x200000
                consts.append(val)
                pos += 4
            else:
                val = struct.unpack_from("<i", buf, pos + 1)[0]
                consts.append(val)
                pos += 6
        else:
            ops_seen.append(b0 & 0x7F)
            pos += 2
    raise ValueError(f"表达式未以 0x00 结束 (起于 {start:#x})")


def decode_expr_tokens(buf: bytes, pos: int) -> tuple[int, list[str], list[int], list[int]]:
    """
    解码表达式中的变量引用：提取引用的 ScrWork 与 FlagWork 常量索引（启发式抓取相邻常量）。
    返回 (end_pos, tokens_str, scrwork_ids, flag_ids)。
    """
    tokens: list[str] = []
    scr_ids: list[int] = []
    flg_ids: list[int] = []
    start = pos
    last_op = None
    n = len(buf)
    while pos < n:
        b0 = buf[pos]
        if b0 == 0x00:
            return pos + 1, tokens, scr_ids, flg_ids
        if b0 & 0x80:
            sz_cls = b0 & 0x60
            if sz_cls == 0x00:
                val = b0 & 0x1F
                if b0 & 0x10:
                    val -= 32
                step = 2
            elif sz_cls == 0x20:
                val = ((b0 & 0x1F) << 8) | buf[pos + 1]
                if b0 & 0x10:
                    val -= 0x2000
                step = 3
            elif sz_cls == 0x40:
                val = ((b0 & 0x1F) << 16) | (buf[pos + 2] << 8) | buf[pos + 1]
                if b0 & 0x10:
                    val -= 0x200000
                step = 4
            else:
                val = struct.unpack_from("<i", buf, pos + 1)[0]
                step = 6
            tokens.append(str(val))
            if last_op == 0x28:
                scr_ids.append(val)
            elif last_op == 0x29:
                flg_ids.append(val)
            last_op = None
            pos += step
        else:
            op = b0 & 0x7F
            tokens.append(EXPR_OPS.get(op, f"Op_{op:02x}"))
            last_op = op
            pos += 2
    raise ValueError(f"表达式未以 0x00 结束 (起于 {start:#x})")


def parse_scx_header(data: bytes) -> dict[str, Any]:
    """解析 SC3 头部信息：标签表、返回地址表、字符串偏移表与代码区边界。"""
    if data[:4] != b"SC3\x00":
        raise ValueError("非 SC3 文件头")
    str_off, ret_off = struct.unpack_from("<2I", data, 4)
    lbl0 = u32_le(data, 12)
    n_labels = (lbl0 - 12) // 4
    labels = list(struct.unpack_from(f"<{n_labels}I", data, 12))
    n_str = (ret_off - str_off) // 4
    str_offsets = list(struct.unpack_from(f"<{n_str}I", data, str_off)) if n_str > 0 else []
    first_str = str_offsets[0] if str_offsets else len(data)
    n_ret = (first_str - ret_off) // 4 if first_str > ret_off else 0
    ret_addrs = list(struct.unpack_from(f"<{n_ret}I", data, ret_off)) if n_ret > 0 else []
    return {
        "str_off": str_off,
        "ret_off": ret_off,
        "code_start": lbl0,
        "code_end": str_off,
        "labels": labels,
        "str_offsets": str_offsets,
        "ret_addrs": ret_addrs,
    }


def parse_insn(buf: bytes, pc: int) -> dict[str, Any]:
    """
    解析单条 SC3 指令。
    返回字典含 pc, size, op, op_name, next_pcs, halt, lbl_refs, expr_ops, scr_ids, flg_ids, subop。
    """
    if pc >= len(buf):
        raise ValueError(f"PC 越界: {pc:#x}")
    b0 = buf[pc]
    if b0 == 0xFE:
        end_p, toks, sids, fids = decode_expr_tokens(buf, pc + 1)
        _, eops, _ = skip_expr(buf, pc + 1)
        return {
            "pc": pc,
            "size": end_p - pc,
            "op": "FE",
            "op_name": OP_NAMES["FE"],
            "next_pcs": [end_p],
            "halt": False,
            "lbl_refs": [],
            "expr_ops": eops,
            "scr_ids": sids,
            "flg_ids": fids,
            "subop": None,
        }

    if pc + 1 >= len(buf):
        raise ValueError(f"指令在 {pc:#x} 处截断")
    tbl = b0 & 0x7F
    b1 = buf[pc + 1]
    if tbl not in (0x00, 0x01, 0x10):
        raise ValueError(f"未知操作码表 {b0:#x} {b1:#x} @ {pc:#x}")

    op_hex = f"{tbl:02x}{b1:02x}"
    p = pc + 2
    eops_all: list[int] = []
    sids_all: list[int] = []
    fids_all: list[int] = []
    next_pcs: list[int] = []
    lbl_refs: list[tuple[str, int]] = []
    halt = False
    subop: int | None = None

    def rd_u8() -> int:
        nonlocal p
        v = buf[p]
        p += 1
        return v

    def rd_u16() -> int:
        nonlocal p
        v = u16_le(buf, p)
        p += 2
        return v

    def rd_expr() -> None:
        nonlocal p
        end_p, eo, _ = skip_expr(buf, p)
        _, _, sids, fids = decode_expr_tokens(buf, p)
        p = end_p
        eops_all.extend(eo)
        sids_all.extend(sids)
        fids_all.extend(fids)

    if tbl == 0x00:
        if b1 == 0x00:
            halt = True
        elif b1 == 0x01:
            rd_expr(); rd_expr(); lbl_refs.append(("far_code", rd_u16())); next_pcs.append(p)
        elif b1 == 0x02:
            rd_expr(); next_pcs.append(p)
        elif b1 == 0x03:
            next_pcs.append(p)
        elif b1 == 0x04:
            rd_expr(); rd_expr(); next_pcs.append(p)
        elif b1 == 0x05:
            rd_expr(); next_pcs.append(p)
        elif b1 == 0x06:
            halt = True
        elif b1 == 0x07:
            lbl_refs.append(("code", rd_u16())); halt = True
        elif b1 == 0x08:
            rd_expr(); lbl_refs.append(("jumptable", rd_u16())); halt = True
        elif b1 == 0x0A:
            rd_u8(); rd_expr(); lbl_refs.append(("code", rd_u16())); next_pcs.append(p)
        elif b1 == 0x0B:
            lbl_refs.append(("code", rd_u16())); lbl_refs.append(("ret", rd_u16())); next_pcs.append(p)
        elif b1 == 0x0C:
            rd_expr(); lbl_refs.append(("code", rd_u16())); next_pcs.append(p)
        elif b1 == 0x0D:
            rd_expr(); lbl_refs.append(("far_code", rd_u16())); lbl_refs.append(("ret", rd_u16())); next_pcs.append(p)
        elif b1 == 0x0E:
            halt = True
        elif b1 == 0x0F:
            lbl_refs.append(("code", rd_u16())); rd_expr(); next_pcs.append(p)
        elif b1 == 0x10:
            rd_u8(); rd_expr(); lbl_refs.append(("code", rd_u16())); next_pcs.append(p)
        elif b1 == 0x11:
            rd_u8(); rd_expr(); next_pcs.append(p)
        elif b1 in (0x12, 0x13, 0x1F, 0x26, 0x2C, 0x31, 0x42, 0x46):
            rd_expr(); next_pcs.append(p)
        elif b1 in (0x14, 0x18, 0x19, 0x33, 0x3D):
            rd_expr(); rd_expr(); next_pcs.append(p)
        elif b1 == 0x15:
            rd_u8(); rd_expr(); rd_expr(); lbl_refs.append(("code", rd_u16())); next_pcs.append(p)
        elif b1 == 0x16:
            rd_u8(); rd_expr(); rd_expr(); next_pcs.append(p)
        elif b1 == 0x17:
            rd_u8(); rd_expr(); rd_expr(); rd_expr(); next_pcs.append(p)
        elif b1 in (0x1A, 0x1C, 0x1D, 0x27, 0x2B, 0x32, 0x3E, 0x3F, 0x40, 0x45, 0x47, 0x4B, 0x4F, 0x52, 0x5F):
            next_pcs.append(p)
        elif b1 in (0x34, 0x48):
            halt = True
        elif b1 == 0x1B:
            rd_expr(); lbl_refs.append(("far_code", rd_u16())); halt = True
        elif b1 in (0x1E, 0x22, 0x24, 0x29, 0x2D, 0x30, 0x36, 0x39, 0x3B, 0x3C, 0x41, 0x44, 0x49, 0x4A):
            subop = rd_u8(); next_pcs.append(p)
        elif b1 == 0x20:
            rd_expr(); lbl_refs.append(("code", rd_u16())); next_pcs.append(p)
        elif b1 == 0x21:
            subop = rd_u8(); rd_expr()
            if subop == 2:
                rd_expr()
            next_pcs.append(p)
        elif b1 == 0x23:
            subop = rd_u8(); s1 = rd_u8()
            if s1 != 2:
                rd_expr(); rd_expr()
            next_pcs.append(p)
        elif b1 in (0x25, 0x4E):
            rd_expr(); rd_expr(); rd_expr(); next_pcs.append(p)
        elif b1 == 0x28:
            rd_expr(); rd_expr(); rd_expr(); rd_expr(); next_pcs.append(p)
        elif b1 == 0x2A:
            subop = rd_u8(); next_pcs.append(p)
        elif b1 in (0x2E, 0x2F, 0x38, 0x4D):
            subop = rd_u8(); rd_expr(); next_pcs.append(p)
        elif b1 == 0x35:
            subop = rd_u8()
            if subop == 0:
                p += 3
            next_pcs.append(p)
        elif b1 == 0x37:
            subop = rd_u8(); rd_expr(); rd_expr(); next_pcs.append(p)
        elif b1 == 0x3A:
            subop = rd_u8()
            if subop == 0:
                rd_expr(); rd_expr()
            elif subop in (2, 3):
                rd_expr()
            next_pcs.append(p)
        elif b1 == 0x43:
            subop = rd_u8(); s1 = rd_u8()
            if s1 in (0, 1):
                if subop == 2:
                    rd_expr()
                elif subop in (3, 4):
                    rd_u16()
            next_pcs.append(p)
        elif b1 == 0x4C:
            subop = rd_u8()
            if subop == 0:
                rd_expr()
            next_pcs.append(p)
        elif b1 == 0x50:
            subop = rd_u8()
            if subop in (0, 3):
                lbl_refs.append(("code", rd_u16()))
                halt = True
            else:
                next_pcs.append(p)
        elif b1 == 0x51:
            subop = rd_u8()
            if subop == 0:
                rd_expr()
            next_pcs.append(p)
        elif b1 == 0x53:
            subop = rd_u8(); rd_expr(); lbl_refs.append(("data", rd_u16())); next_pcs.append(p)
        elif b1 == 0x54:
            subop = rd_u8(); rd_expr(); lbl_refs.append(("code", rd_u16())); lbl_refs.append(("ret", rd_u16())); next_pcs.append(p)
        elif b1 == 0x55:
            subop = rd_u8(); rd_expr(); rd_expr(); lbl_refs.append(("code", rd_u16())); next_pcs.append(p)
        elif b1 == 0x56:
            subop = rd_u8(); rd_expr(); rd_expr(); lbl_refs.append(("far_code", rd_u16())); lbl_refs.append(("ret", rd_u16())); next_pcs.append(p)
        elif b1 == 0x57:
            subop = rd_u8(); rd_expr(); next_pcs.append(p)
        elif b1 == 0x58:
            subop = rd_u8()
            if subop in (2, 3):
                rd_expr(); rd_expr(); rd_expr(); rd_expr()
            else:
                rd_expr()
            lbl_refs.append(("data", rd_u16())); next_pcs.append(p)
        elif b1 == 0x59:
            subop = rd_u8(); rd_expr(); rd_expr(); lbl_refs.append(("code", rd_u16())); next_pcs.append(p)
        else:
            raise ValueError(f"未实现的 00xx 操作码: {op_hex} @ {pc:#x}")

    elif tbl == 0x01:
        if b1 in (0x00, 0x07):
            if b1 == 0x00:
                subop = rd_u8()
            rd_expr(); rd_expr(); rd_expr(); next_pcs.append(p)
        elif b1 in (0x01, 0x03, 0x20, 0x24):
            rd_expr(); next_pcs.append(p)
        elif b1 == 0x02:
            rd_expr(); rd_expr(); rd_expr(); next_pcs.append(p)
        elif b1 == 0x04:
            for _ in range(5):
                rd_expr()
            next_pcs.append(p)
        elif b1 == 0x05:
            subop = rd_u8()
            for _ in range({0: 2, 1: 2, 2: 3, 3: 4, 4: 4, 5: 4, 6: 4}.get(subop, 0)):
                rd_expr()
            next_pcs.append(p)
        elif b1 == 0x06:
            subop = rd_u8()
            rd_expr(); rd_expr()
            if subop == 0:
                rd_expr()
            next_pcs.append(p)
        elif b1 == 0x08:
            subop = rd_u8()
            if subop == 10:
                rd_expr()
            next_pcs.append(p)
        elif b1 == 0x09:
            subop = rd_u8()
            if subop == 0:
                rd_u16()
            elif subop == 1:
                rd_u16(); rd_expr()
            elif subop == 2:
                rd_expr()
            next_pcs.append(p)
        elif b1 == 0x0A:
            subop = rd_u8()
            if subop in (4, 5):
                rd_expr()
            next_pcs.append(p)
        elif b1 == 0x11:
            subop = rd_u8()
            if subop in (5, 6, 7):
                rd_expr()
            next_pcs.append(p)
        elif b1 == 0x13:
            subop = rd_u8()
            if subop == 2:
                rd_expr()
            next_pcs.append(p)
        elif b1 in (0x0B, 0x0D, 0x10, 0x23, 0x28, 0x2B):
            if b1 != 0x0B:
                subop = rd_u8()
            next_pcs.append(p)
        elif b1 == 0x0C:
            subop = rd_u8()
            if subop & 1:
                rd_expr()
            rd_expr()
            if subop & 2:
                rd_expr()
            rd_u16(); next_pcs.append(p)
        elif b1 == 0x0E:
            rd_expr(); lbl_refs.append(("data", rd_u16())); next_pcs.append(p)
        elif b1 == 0x0F:
            rd_u16(); rd_u16(); next_pcs.append(p)
        elif b1 == 0x12:
            subop = rd_u8()
            rd_u16()
            if subop in (0, 2):
                rd_expr()
            next_pcs.append(p)
        elif b1 == 0x14:
            subop = rd_u8()
            if subop not in (0, 1):
                rd_u16()
            next_pcs.append(p)
        elif b1 == 0x15:
            subop = rd_u8()
            if subop == 0:
                rd_expr(); rd_expr()
            elif subop in (2, 3):
                rd_expr()
            next_pcs.append(p)
        elif b1 == 0x21:
            rd_expr(); lbl_refs.append(("data", rd_u16())); next_pcs.append(p)
        elif b1 in (0x22, 0x27):
            subop = rd_u8()
            if subop == 99:
                rd_expr(); rd_expr()
            else:
                rd_u8()
            rd_expr(); rd_expr(); next_pcs.append(p)
        elif b1 == 0x25:
            subop = rd_u8()
            if subop == 0:
                rd_u16()
            elif subop == 1:
                rd_expr(); rd_expr(); rd_u16()
            elif subop == 2:
                rd_u16()
            elif subop == 3:
                rd_u16(); rd_expr(); rd_expr(); rd_expr()
            next_pcs.append(p)
        elif b1 in (0x26, 0x2A):
            subop = rd_u8()
            if subop == 99:
                rd_expr(); rd_expr()
            else:
                rd_u8()
            rd_expr(); next_pcs.append(p)
        else:
            raise ValueError(f"未实现的 01xx 操作码: {op_hex} @ {pc:#x}")

    elif tbl == 0x10:
        if b1 == 0x00:
            rd_expr(); next_pcs.append(p)
        elif b1 in (0x01, 0x02, 0x03, 0x06, 0x07, 0x08, 0x09, 0x0E, 0x16, 0x24):
            if b1 == 0x24:
                subop = rd_u8()
                if subop == 0:
                    rd_expr(); rd_expr()
            else:
                rd_expr(); rd_expr()
            next_pcs.append(p)
        elif b1 == 0x04:
            subop = rd_u8(); rd_expr(); rd_expr()
            if subop >= 4:
                rd_expr()
            rd_expr(); next_pcs.append(p)
        elif b1 == 0x05:
            subop = rd_u8(); rd_expr(); rd_expr(); next_pcs.append(p)
        elif b1 in (0x0A, 0x0B, 0x12, 0x1E, 0x2D, 0x2F, 0x40, 0x41):
            next_pcs.append(p)
        elif b1 in (0x0C, 0x13, 0x14, 0x15, 0x1A, 0x1B, 0x1C, 0x1D, 0x1F, 0x20, 0x21, 0x34, 0x36):
            subop = rd_u8(); next_pcs.append(p)
        elif b1 == 0x0D:
            subop = rd_u8()
            if subop == 1:
                rd_expr(); lbl_refs.append(("data", rd_u16()))
            elif subop == 2:
                rd_expr()
            elif subop == 4:
                rd_expr(); rd_expr()
            elif subop == 5:
                for _ in range(7):
                    rd_expr()
            next_pcs.append(p)
        elif b1 in (0x10, 0x11, 0x17, 0x28, 0x29, 0x2E):
            rd_expr(); next_pcs.append(p)
        elif b1 == 0x22:
            subop = rd_u8()
            if subop == 10:
                rd_u16()
            next_pcs.append(p)
        elif b1 == 0x23:
            subop = rd_u8()
            if subop in (0, 10):
                rd_u8()
            next_pcs.append(p)
        elif b1 == 0x27:
            subop = rd_u8(); rd_expr()
            if subop == 1:
                rd_expr()
            next_pcs.append(p)
        elif b1 == 0x2A:
            subop = rd_u8(); rd_expr(); rd_expr(); rd_expr(); next_pcs.append(p)
        elif b1 == 0x30:
            subop = rd_u8()
            for _ in range({1: 5, 3: 5, 4: 6, 5: 6, 11: 5, 12: 6}.get(subop, 0)):
                rd_expr()
            next_pcs.append(p)
        elif b1 in (0x32, 0x38, 0x33):
            subop = rd_u8()
            if subop == 0:
                lbl_refs.append(("data", rd_u16()))
            next_pcs.append(p)
        elif b1 == 0x37:
            subop = rd_u8()
            if subop == 0:
                for _ in range(7):
                    lbl_refs.append(("data", rd_u16()))
            elif subop in (0x0A, 0x32):
                rd_u16()
            elif subop == 12:
                rd_expr(); rd_expr()
            elif subop == 13:
                # 注: Game.exe 中 0x461b63 对 0x0c/0x0d 按废除存根处理；脚本实体中 0x0d 实为 (expr, u16_msg_id)
                rd_expr(); rd_u16()
            elif subop == 15:
                rd_expr(); rd_expr(); rd_expr()
            elif subop in (42, 43, 44, 45, 48):
                rd_expr()
            elif subop == 46:
                rd_expr(); rd_expr(); rd_expr()
            elif subop == 49:
                rd_expr(); rd_expr()
            next_pcs.append(p)
        else:
            raise ValueError(f"未实现的 10xx 操作码: {op_hex} @ {pc:#x}")

    return {
        "pc": pc,
        "size": p - pc,
        "op": op_hex,
        "op_name": OP_NAMES.get(op_hex, f"Op_{op_hex}"),
        "next_pcs": next_pcs,
        "halt": halt,
        "lbl_refs": lbl_refs,
        "expr_ops": eops_all,
        "scr_ids": sids_all,
        "flg_ids": fids_all,
        "subop": subop,
    }


def decode_scx_string(data: bytes, offset: int) -> dict[str, Any]:
    """
    依据 Game.exe 0x445790 跳转表解码单条 SC3 内联字符串。
    返回 {end_pos, glyph_ids, tags, tag_counts}。
    """
    p = offset
    n = len(data)
    glyphs: list[int] = []
    tags: list[tuple[int, str, Any]] = []
    tcounts: Counter[int] = Counter()

    while p < n:
        b = data[p]
        if b == 0xFF:
            return {
                "end_pos": p + 1,
                "glyph_ids": glyphs,
                "tags": tags,
                "tag_counts": tcounts,
            }
        if b & 0x80:
            if p + 1 >= n:
                raise ValueError(f"字形编码截断 @ {p:#x}")
            gid = ((b & 0x7F) << 8) | data[p + 1]
            glyphs.append(gid)
            p += 2
            continue
        if b not in STR_TAG_INFO:
            raise ValueError(f"未知字符串标签 {b:#x} @ {p:#x}")
        name, arg_kind = STR_TAG_INFO[b]
        tcounts[b] += 1
        p += 1
        arg_val: Any = None
        if arg_kind == "u8":
            arg_val = data[p]
            p += 1
        elif arg_kind == "u16be":
            arg_val = struct.unpack_from(">H", data, p)[0]
            p += 2
        elif arg_kind == "expr":
            end_p, toks, _, _ = decode_expr_tokens(data, p)
            arg_val = " ".join(toks)
            p = end_p
        tags.append((b, name, arg_val))

    raise ValueError(f"字符串未以 0xFF 结束 (起于 {offset:#x})")


def walk_scx_cfg(data: bytes) -> dict[str, Any]:
    """对单个 .scx 文件执行完整 CFG 与二级代码标签遍历分析。"""
    hdr = parse_scx_header(data)
    code_start = hdr["code_start"]
    code_end = hdr["code_end"]
    labels = hdr["labels"]
    ret_addrs = hdr["ret_addrs"]
    n_labels = len(labels)

    visited: set[int] = set()
    covered = bytearray(max(0, code_end - code_start))
    insns: dict[int, dict[str, Any]] = {}
    data_labels: set[int] = set()
    jt_labels: set[int] = set()

    def walk_from(start_pc: int) -> tuple[bool, dict[int, dict[str, Any]], set[int], set[int]]:
        q = [start_pc]
        lvis: set[int] = set()
        linsns: dict[int, dict[str, Any]] = {}
        ldat: set[int] = set()
        ljt: set[int] = set()
        while q:
            pc = q.pop(0)
            while pc not in visited and pc not in lvis and pc < code_end:
                if pc < code_start:
                    return False, {}, set(), set()
                lvis.add(pc)
                try:
                    info = parse_insn(data, pc)
                except Exception:
                    return False, {}, set(), set()
                if pc + info["size"] > code_end:
                    return False, {}, set(), set()
                linsns[pc] = info
                for kind, lid in info["lbl_refs"]:
                    if kind == "far_code":
                        continue
                    if kind == "ret":
                        if lid < len(ret_addrs) and ret_addrs[lid] not in visited and ret_addrs[lid] not in lvis:
                            q.append(ret_addrs[lid])
                        continue
                    if lid >= n_labels:
                        return False, {}, set(), set()
                    if kind == "code":
                        if labels[lid] not in visited and labels[lid] not in lvis:
                            q.append(labels[lid])
                    elif kind == "jumptable":
                        ljt.add(lid)
                    else:
                        ldat.add(lid)
                if info["halt"]:
                    break
                for npc in info["next_pcs"][1:]:
                    if npc not in visited and npc not in lvis:
                        q.append(npc)
                pc = info["next_pcs"][0]
        return True, linsns, ldat, ljt

    def commit(linsns: dict[int, dict[str, Any]], ldat: set[int], ljt: set[int]) -> None:
        for pc, info in linsns.items():
            visited.add(pc)
            insns[pc] = info
            for k in range(info["size"]):
                covered[pc - code_start + k] = 1
        data_labels.update(ldat)
        jt_labels.update(ljt)

    ok, li, ld, lj = walk_from(labels[0])
    if not ok:
        raise ValueError("主入口 label[0] 解析失败")
    commit(li, ld, lj)

    for ra in ret_addrs:
        if ra not in visited and code_start <= ra < code_end and not covered[ra - code_start]:
            ok, li, ld, lj = walk_from(ra)
            if ok and li:
                commit(li, ld, lj)

    data_tbl_labels: list[int] = []
    for lid, off in sorted(enumerate(labels), key=lambda x: x[1]):
        if lid == 0 or lid in data_labels or lid in jt_labels or off in visited or off >= code_end:
            continue
        if covered[off - code_start]:
            continue
        ok, li, ld, lj = walk_from(off)
        if ok and li and not any(covered[pc - code_start + k] for pc, inf in li.items() for k in range(inf["size"])):
            commit(li, ld, lj)
        else:
            data_tbl_labels.append(lid)

    return {
        "hdr": hdr,
        "insns": insns,
        "code_size": code_end - code_start,
        "uncov_bytes": sum(1 for b in covered if b == 0),
        "data_tbl_labels": data_tbl_labels,
    }


def scan_archive(usrdir: Path, report_path: Path | None = None) -> dict[str, Any]:
    """扫描 script.mpk 内全部 .scx 文件并生成统计报告。"""
    vfs = MgsMpkVfs(usrdir)
    mpk = vfs.archives["script.mpk"]

    op_counts: Counter[str] = Counter()
    eop_counts: Counter[int] = Counter()
    tag_counts: Counter[int] = Counter()
    subop_counts: Counter[str] = Counter()
    scr_ids: Counter[int] = Counter()
    flg_ids: Counter[int] = Counter()
    special_files: dict[str, dict[str, Any]] = {}

    n_files = 0
    n_strings = 0
    min_glyph = 999999
    max_glyph = -1
    bad_files: list[str] = []
    story_gaps: list[tuple[str, int]] = []

    for e in sorted(mpk.entries, key=lambda x: x.index):
        data = vfs.read("script.mpk", e.name)
        if data[:4] != b"SC3\x00":
            continue
        n_files += 1
        try:
            res = walk_scx_cfg(data)
        except Exception as exc:
            bad_files.append(f"{e.name}: {exc}")
            continue

        for info in res["insns"].values():
            op = info["op"]
            op_counts[op] += 1
            for eo in info["expr_ops"]:
                eop_counts[eo] += 1
            for s in info["scr_ids"]:
                scr_ids[s] += 1
            for f in info["flg_ids"]:
                flg_ids[f] += 1
            if info["subop"] is not None and op in (
                "0035", "0043", "0050", "0105", "0108", "0109", "0110", "0111", "0112", "0113",
                "0115", "0122", "0123", "0125", "1000", "1004", "1005", "1022", "1023", "1030", "1033", "1037"
            ):
                subop_counts[f"{op}:{info['subop']:02x}"] += 1

        if e.name.startswith("SG0_") and res["uncov_bytes"] > 3:
            story_gaps.append((e.name, res["uncov_bytes"]))

        if e.name in ("_phone.scx", "_rndrine.scx", "_tips.scx", "_Startup_win.scx", "macrosys.scx", "macrosys2.scx"):
            f_ops = Counter(i["op"] for i in res["insns"].values())
            special_files[e.name] = {
                "size": len(data),
                "labels": len(res["hdr"]["labels"]),
                "strings": len(res["hdr"]["str_offsets"]),
                "insns": len(res["insns"]),
                "top_ops": f_ops.most_common(12),
            }

        for off in res["hdr"]["str_offsets"]:
            n_strings += 1
            sres = decode_scx_string(data, off)
            for k, v in sres["tag_counts"].items():
                tag_counts[k] += v
            for g in sres["glyph_ids"]:
                if g < min_glyph:
                    min_glyph = g
                if g > max_glyph:
                    max_glyph = g

    summary = {
        "n_files": n_files,
        "total_insns": sum(op_counts.values()),
        "unique_ops": len(op_counts),
        "n_strings": n_strings,
        "glyph_range": (min_glyph, max_glyph),
        "bad_files": bad_files,
        "story_gaps": story_gaps,
        "op_counts": op_counts,
        "eop_counts": eop_counts,
        "tag_counts": tag_counts,
        "subop_counts": subop_counts,
        "scr_ids": scr_ids,
        "flg_ids": flg_ids,
        "special_files": special_files,
    }

    if report_path is not None:
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(_render_markdown_report(summary), encoding="utf-8")

    return summary


def _render_markdown_report(s: dict[str, Any]) -> str:
    lines: list[str] = []
    lines.append("# STEINS;GATE 0 SC3 脚本逆向与全量扫描报告\n")
    lines.append("## 1. 扫描总览\n")
    lines.append(f"- **脚本文件总数**：`{s['n_files']}` 个（来自 `USRDIR/script.mpk`）")
    lines.append(f"- **累计解析指令数**：`{s['total_insns']}` 条")
    lines.append(f"- **实际使用操作码种类**：`{s['unique_ops']}` 种（解析错误：`{len(s['bad_files'])}`；剧情文件 `SG0_*` 异常未覆盖：`{len(s['story_gaps'])}`）")
    lines.append(f"- **内联字符串总数**：`{s['n_strings']}` 条")
    lines.append(f"- **字形 ID 范围**：`{s['glyph_range'][0]} .. {s['glyph_range'][1]}`（与 `assets/tables/font_widths.bin` 的 8000 槽位匹配情况需在文本渲染器做越界保护）\n")

    lines.append("## 2. SC3 字符串控制标签分布（依据 Game.exe `0x445790`）\n")
    lines.append("| 标签 | 名称 | 参数格式 | 出现次数 |")
    lines.append("| --- | --- | --- | ---: |")
    for tag_id, cnt in sorted(s["tag_counts"].items()):
        name, arg = STR_TAG_INFO[tag_id]
        lines.append(f"| `0x{tag_id:02x}` | `{name}` | `{arg}` | {cnt} |")
    lines.append("")

    lines.append("## 3. 表达式操作符统计（依据 Game.exe `0x41a740` / `0x41acc0`）\n")
    lines.append("| 操作符 ID | 语义 | 出现次数 |")
    lines.append("| --- | --- | ---: |")
    for eop, cnt in sorted(s["eop_counts"].items()):
        lines.append(f"| `0x{eop:02x}` | `{EXPR_OPS.get(eop, 'Unknown')}` | {cnt} |")
    lines.append("")

    lines.append("## 4. 核心系统脚本审计（手机 / RINE / TIPS / 启动控制）\n")
    for fname, info in s["special_files"].items():
        lines.append(f"### `{fname}`")
        lines.append(f"- 体积：`{info['size']}` B，标签：`{info['labels']}`，字符串：`{info['strings']}`，解析指令：`{info['insns']}`")
        top_str = ", ".join(f"`{op}`({OP_NAMES.get(op, op)}): {c}" for op, c in info["top_ops"])
        lines.append(f"- 高频指令：{top_str}\n")

    lines.append("## 5. 关键系统子操作码分布（Sub-opcodes）\n")
    lines.append("| 操作码:子号 | 出现次数 | 说明 |")
    lines.append("| --- | ---: | --- |")
    for k, cnt in sorted(s["subop_counts"].items()):
        op, sub = k.split(":")
        lines.append(f"| `{k}` | {cnt} | `{OP_NAMES.get(op, op)}` (sub=0x{sub}) |")
    lines.append("")

    lines.append("## 6. 全部 117 种操作码频次表\n")
    lines.append("| Opcode | 助记符 | 出现次数 |")
    lines.append("| --- | --- | ---: |")
    for op, cnt in sorted(s["op_counts"].items()):
        lines.append(f"| `0x{op}` | `{OP_NAMES.get(op, op)}` | {cnt} |")
    lines.append("")

    lines.append("## 7. 高频 ScrWork 与 FlagWork 引用（前 30 项）\n")
    lines.append("- **ScrWork 高频索引**：" + ", ".join(f"`{k}`({v})" for k, v in s["scr_ids"].most_common(30)))
    lines.append("- **FlagWork 高频索引**：" + ", ".join(f"`{k}`({v})" for k, v in s["flg_ids"].most_common(30)))
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="STEINS;GATE 0 SC3 全量扫描工具")
    parser.add_argument("--usrdir", type=Path, default=Path(r"U:\anti\projects\STEINS GATE 0\USRDIR"))
    parser.add_argument("--report", type=Path, default=Path(r"U:\anti\projects\SteinsGate0_iOS\docs\sc3_opcodes_report.md"))
    args = parser.parse_args()

    res = scan_archive(args.usrdir, args.report)
    print(
        f"SC3 scan ok: files={res['n_files']}, insns={res['total_insns']}, "
        f"unique_ops={res['unique_ops']}, strings={res['n_strings']}, "
        f"glyphs={res['glyph_range'][0]}..{res['glyph_range'][1]}, "
        f"bad={len(res['bad_files'])}, story_gaps={len(res['story_gaps'])}"
    )
    if args.report:
        print(f"Report written -> {args.report}")
    return 0 if not res["bad_files"] and not res["story_gaps"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
