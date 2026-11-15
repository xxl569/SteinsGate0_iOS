#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
《命运石之门 0》(STEINS;GATE 0) iOS TrollStore 免越狱打包、PCK 导出与签名校验工具
支持在 Windows 无 Mac 环境下：
1. 调用 Godot 4.3 导出纯净运行时资源包 (.pck) 并校验无源码/测试/.mpk/.ogv 版权包泄露
2. 将新 .pck 热注入 macOS CI 产出的 .app / Shell.zip / .ipa 母包中
3. 修补 Info.plist（确保开启 UIFileSharingEnabled、LSSupportsOpeningDocumentsInPlace 与横屏支持）
4. 调用 ldid 注入 TrollStore 权限并回读验证（拦截任何会导致黑屏/破坏沙盒的私有权限）
5. 写入标准 UNIX +x 权限位 (0o100755) 后封装输出 TrollStore .ipa 并执行全项体检
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import plistlib
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path
from typing import Any

# 严禁出现在 TrollStore 权限中的私有键值（会导致 Metal/EAGL 黑屏或破坏 Documents 容器）
FORBIDDEN_ENTITLEMENTS = {
    "platform-application",
    "com.apple.private.security.no-container",
    "com.apple.private.security.container-required",
}

# 推荐并要求注入的 TrollStore 大内存与调试权限
REQUIRED_ENTITLEMENTS = {
    "get-task-allow",
    "com.apple.developer.kernel.increased-memory-limit",
    "com.apple.developer.kernel.extended-virtual-addressing",
}

# 不允许打入运行时 .pck 的工程内部前缀/后缀
FORBIDDEN_PCK_PREFIXES = (
    "res://godot_verify/",
    "res://native/",
    "res://tests/",
    "res://platforms/",
    "res://tools/",
    "res://docs/",
    "res://saves/",
    "res://build/",
)
FORBIDDEN_PCK_SUFFIXES = (
    ".mpk",
    ".bk2",
    ".wpk",
    ".scx",
    ".dds",
    ".lay",
    ".ogv",
    ".mpg",
    ".dat",
    ".ipa",
    ".c",
    ".h",
    ".py",
    ".bat",
    ".exe",
    ".dll",
)

DEFAULT_PROJECT_DIR = Path(__file__).resolve().parent.parent
DEFAULT_GODOT_EXE = DEFAULT_PROJECT_DIR / "tools" / "godot" / "Godot_v4.3-stable_win64_console.exe"
DEFAULT_LDID_EXE = DEFAULT_PROJECT_DIR / "tools" / "ldid" / ("ldid.exe" if os.name == "nt" else "ldid")
DEFAULT_ENTITLEMENTS = DEFAULT_PROJECT_DIR / "platforms" / "ios" / "Entitlements_TrollStore.plist"


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def find_ldid(explicit_ldid: str | None = None) -> Path:
    candidates: list[Path] = []
    if explicit_ldid:
        candidates.append(Path(explicit_ldid))
    candidates.append(DEFAULT_LDID_EXE)
    candidates.append(Path(r"U:\anti\projects\Fureraba_iOS\tools\ldid\ldid.exe"))
    candidates.append(Path(r"U:\anti\projects\HenPri_iOS\tools\ldid\ldid.exe"))
    which_ldid = shutil.which("ldid")
    if which_ldid:
        candidates.append(Path(which_ldid))
    for c in candidates:
        if c.is_file():
            return c
    raise FileNotFoundError(
        f"未找到 ldid 可执行文件，已检查: {[str(c) for c in candidates]}"
    )


def find_godot(explicit_godot: str | None = None) -> Path:
    candidates: list[Path] = []
    if explicit_godot:
        candidates.append(Path(explicit_godot))
    candidates.append(DEFAULT_GODOT_EXE)
    candidates.append(Path(r"U:\anti\projects\Fureraba_iOS\tools\godot\Godot_v4.3-stable_win64_console.exe"))
    for name in ("godot", "godot4", "Godot_v4.3-stable_win64_console.exe"):
        found = shutil.which(name)
        if found:
            candidates.append(Path(found))
    for c in candidates:
        if c.is_file():
            return c
    raise FileNotFoundError(
        f"未找到 Godot 4.3 命令行程序，已检查: {[str(c) for c in candidates]}"
    )


def parse_pck_entries(pck_path: Path) -> dict[str, Any]:
    """解析 Godot 4 .pck (GDPC) 文件头与条目清单，并检查是否存在禁打包文件泄露。"""
    if not pck_path.is_file():
        raise FileNotFoundError(f"PCK 文件不存在: {pck_path}")

    with pck_path.open("rb") as f:
        header = f.read(4 + 16 + 4 + 8 + 64)
        if len(header) < 96:
            raise ValueError(f"PCK 文件头长度不足: {len(header)} bytes")
        magic, fmt_ver, major, minor, patch, flags, file_base = struct.unpack_from(
            "<4sIIIIIQ", header, 0
        )
        if magic != b"GDPC":
            raise ValueError(f"非法 PCK 魔数: {magic!r} (期望 b'GDPC')")

        (file_count,) = struct.unpack("<I", f.read(4))
        paths: list[str] = []
        leaks: list[str] = []
        for _ in range(file_count):
            raw_len = f.read(4)
            if len(raw_len) < 4:
                raise ValueError("PCK 文件表意外截断")
            (path_len,) = struct.unpack("<I", raw_len)
            path_bytes = f.read(path_len)
            entry_tail = f.read(8 + 8 + 16 + 4)
            if len(path_bytes) < path_len or len(entry_tail) < 36:
                raise ValueError("PCK 条目元数据意外截断")
            rel_path = path_bytes.rstrip(b"\x00").decode("utf-8", errors="replace")
            paths.append(rel_path)
            lower_p = rel_path.lower()
            if lower_p.startswith(FORBIDDEN_PCK_PREFIXES) or lower_p.endswith(
                FORBIDDEN_PCK_SUFFIXES
            ):
                leaks.append(rel_path)

    return {
        "file": str(pck_path),
        "bytes": pck_path.stat().st_size,
        "sha256": sha256_file(pck_path),
        "format_version": fmt_ver,
        "engine": f"{major}.{minor}.{patch}",
        "flags": flags,
        "file_base": file_base,
        "file_count": file_count,
        "paths": paths,
        "leaks": leaks,
    }


def _inspect_macho_slice(data: bytes, offset: int) -> dict[str, Any]:
    if offset + 32 > len(data):
        return {"valid_arm64": False, "reason": "Mach-O slice 头截断"}
    magic, cputype, cpusubtype, filetype, ncmds, sizeofcmds, flags, _reserved = (
        struct.unpack_from("<IiiIIIII", data, offset)
    )
    if magic != 0xFEEDFACF:
        return {"valid_arm64": False, "magic": hex(magic)}
    valid_arm64 = cputype == 0x0100000C
    cmd_off = offset + 32
    has_cs = False
    min_os = None
    for _ in range(ncmds):
        if cmd_off + 8 > len(data):
            break
        cmd, cmdsize = struct.unpack_from("<II", data, cmd_off)
        if cmdsize < 8:
            break
        if cmd == 0x1D:  # LC_CODE_SIGNATURE
            has_cs = True
        elif cmd == 0x32 and cmd_off + 24 <= len(data):  # LC_BUILD_VERSION
            _platform, minos_raw, _sdk, _ntools = struct.unpack_from(
                "<IIII", data, cmd_off + 8
            )
            min_os = f"{minos_raw >> 16}.{(minos_raw >> 8) & 0xFF}.{minos_raw & 0xFF}"
        cmd_off += cmdsize
    return {
        "valid_arm64": valid_arm64,
        "cputype": hex(cputype),
        "cpusubtype": cpusubtype,
        "filetype": filetype,
        "has_code_signature": has_cs,
        "min_os": min_os,
    }


def inspect_macho(binary_path: Path) -> dict[str, Any]:
    """校验二进制文件为合法的 iOS arm64 Mach-O（支持单体与 Universal FAT）。"""
    data = binary_path.read_bytes()
    if len(data) < 32:
        raise ValueError(f"Mach-O 文件过小: {binary_path}")

    be_magic = struct.unpack_from(">I", data, 0)[0]
    le_magic = struct.unpack_from("<I", data, 0)[0]

    if le_magic == 0xFEEDFACF:
        info = _inspect_macho_slice(data, 0)
        info["is_fat"] = False
        info["bytes"] = len(data)
        return info

    if be_magic in (0xCAFEBABE, 0xCAFEBABF):
        is_fat64 = be_magic == 0xCAFEBABF
        nfat = struct.unpack_from(">I", data, 4)[0]
        slices: list[dict[str, Any]] = []
        off = 8
        for _ in range(nfat):
            if is_fat64:
                cputype, _sub, slice_off, _slice_size, _align, _res = (
                    struct.unpack_from(">IIQQII", data, off)
                )
                off += 32
            else:
                cputype, _sub, slice_off, _slice_size, _align = struct.unpack_from(
                    ">IIIII", data, off
                )
                off += 20
            if cputype == 0x0100000C:
                slices.append(_inspect_macho_slice(data, slice_off))
        arm64_slices = [s for s in slices if s.get("valid_arm64")]
        if arm64_slices:
            best = dict(arm64_slices[0])
            best["is_fat"] = True
            best["bytes"] = len(data)
            return best
        return {"valid_arm64": False, "is_fat": True, "bytes": len(data)}

    raise ValueError(
        f"非合法 64 位 Mach-O / FAT 文件 ({binary_path}): magic=0x{le_magic:08X}"
    )


def validate_entitlements_dict(ent: dict[str, Any], source_desc: str) -> None:
    forbidden_hit = sorted(k for k in ent.keys() if k in FORBIDDEN_ENTITLEMENTS)
    if forbidden_hit:
        raise ValueError(
            f"{source_desc} 包含会导致 GPU 黑屏或沙盒失效的禁止权限: {forbidden_hit}"
        )
    missing = sorted(
        k for k in REQUIRED_ENTITLEMENTS if not bool(ent.get(k, False))
    )
    if missing:
        raise ValueError(
            f"{source_desc} 缺少 TrollStore 必需/推荐大内存权限: {missing}"
        )


def read_entitlements_with_ldid(ldid_exe: Path, binary_path: Path) -> dict[str, Any]:
    proc = subprocess.run(
        [str(ldid_exe), "-e", str(binary_path)],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    out = proc.stdout.strip()
    if proc.returncode != 0 or not out:
        return {}
    try:
        parsed = plistlib.loads(out.encode("utf-8"))
        return parsed if isinstance(parsed, dict) else {}
    except Exception:
        return {}


def sign_with_ldid(
    ldid_exe: Path, binary_path: Path, entitlements_plist: Path
) -> dict[str, Any]:
    if not entitlements_plist.is_file():
        raise FileNotFoundError(f"权限文件不存在: {entitlements_plist}")
    with entitlements_plist.open("rb") as f:
        expected_ent = plistlib.load(f)
    if not isinstance(expected_ent, dict):
        raise ValueError(f"权限文件根节点不是 dict: {entitlements_plist}")
    validate_entitlements_dict(expected_ent, str(entitlements_plist))

    proc = subprocess.run(
        [str(ldid_exe), f"-S{entitlements_plist}", str(binary_path)],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(
            f"ldid 签名失败 (code={proc.returncode}): {proc.stderr or proc.stdout}"
        )

    actual_ent = read_entitlements_with_ldid(ldid_exe, binary_path)
    validate_entitlements_dict(actual_ent, f"ldid -e ({binary_path.name})")
    return actual_ent


def patch_info_plist(
    info_plist_path: Path,
    bundle_id: str | None = None,
    display_name: str | None = None,
) -> dict[str, Any]:
    if not info_plist_path.is_file():
        raise FileNotFoundError(f"未找到 Info.plist: {info_plist_path}")
    with info_plist_path.open("rb") as f:
        plist_data = plistlib.load(f)
    if not isinstance(plist_data, dict):
        raise ValueError(f"Info.plist 内容无效: {info_plist_path}")

    plist_data["UIFileSharingEnabled"] = True
    plist_data["LSSupportsOpeningDocumentsInPlace"] = True
    plist_data["UIRequiresFullScreen"] = True
    plist_data["UIStatusBarHidden"] = True
    plist_data.setdefault("ITSAppUsesNonExemptEncryption", False)

    device_family = plist_data.get("UIDeviceFamily")
    if not isinstance(device_family, list) or 1 not in device_family:
        plist_data["UIDeviceFamily"] = [1, 2]

    landscape_orientations = [
        "UIInterfaceOrientationLandscapeLeft",
        "UIInterfaceOrientationLandscapeRight",
    ]
    plist_data["UISupportedInterfaceOrientations"] = list(landscape_orientations)
    plist_data["UISupportedInterfaceOrientations~ipad"] = list(landscape_orientations)

    if bundle_id:
        plist_data["CFBundleIdentifier"] = bundle_id
    if display_name:
        plist_data["CFBundleDisplayName"] = display_name
        plist_data["CFBundleName"] = display_name

    with info_plist_path.open("wb") as f:
        plistlib.dump(plist_data, f, fmt=plistlib.FMT_XML)
    return plist_data


def _extract_shell_archive(archive_path: Path, dest_dir: Path) -> Path:
    """解压 .zip / .ipa 母包并寻找其中的唯一 .app 目录。"""
    with zipfile.ZipFile(archive_path, "r") as zf:
        for info in zf.infolist():
            mode = (info.external_attr >> 16) & 0o170000
            target = dest_dir / info.filename
            if info.is_dir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            if mode == stat.S_IFLNK and os.name != "nt":
                link_target = zf.read(info.filename).decode("utf-8")
                if target.exists() or target.is_symlink():
                    target.unlink()
                os.symlink(link_target, target)
            else:
                with zf.open(info, "r") as src, target.open("wb") as dst:
                    shutil.copyfileobj(src, dst)
                if os.name != "nt" and ((info.external_attr >> 16) & 0o111):
                    os.chmod(target, 0o755)

    app_candidates = sorted(
        p for p in dest_dir.rglob("*.app") if p.is_dir() and "__MACOSX" not in p.parts
    )
    if not app_candidates:
        raise FileNotFoundError(f"压缩包中未找到 *.app 目录: {archive_path}")
    app_candidates.sort(key=lambda p: len(p.parts))
    return app_candidates[0]


def _resolve_app_shell(shell_path: Path, work_dir: Path) -> Path:
    if shell_path.is_dir():
        if shell_path.suffix == ".app":
            dst = work_dir / "Payload" / shell_path.name
            shutil.copytree(shell_path, dst, symlinks=True)
            return dst
        apps = sorted(p for p in shell_path.rglob("*.app") if p.is_dir())
        if apps:
            dst = work_dir / "Payload" / apps[0].name
            shutil.copytree(apps[0], dst, symlinks=True)
            return dst
        raise FileNotFoundError(f"目录中未找到 *.app: {shell_path}")
    if shell_path.is_file() and shell_path.suffix.lower() in (".zip", ".ipa"):
        extract_root = work_dir / "extracted"
        extract_root.mkdir(parents=True, exist_ok=True)
        found_app = _extract_shell_archive(shell_path, extract_root)
        dst = work_dir / "Payload" / found_app.name
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(found_app), str(dst))
        return dst
    raise FileNotFoundError(f"不支持的 App 母包格式或路径不存在: {shell_path}")


def _is_macho_binary(path: Path) -> bool:
    try:
        with path.open("rb") as f:
            magic = f.read(4)
        return magic in (
            b"\xcf\xfa\xed\xfe",
            b"\xce\xfa\xed\xfe",
            b"\xca\xfe\xba\xbe",
            b"\xbe\xba\xfe\xca",
            b"\xca\xfe\xba\xbf",
        )
    except OSError:
        return False


def build_zip_ipa(
    app_dir: Path, out_ipa_path: Path, executable_name: str
) -> dict[str, Any]:
    """将 Payload/<App>.app 打包为 TrollStore 规范 .ipa，并在 Windows 上强制写入 UNIX +x 权限。"""
    out_ipa_path.parent.mkdir(parents=True, exist_ok=True)
    app_name = app_dir.name
    exec_rel = f"Payload/{app_name}/{executable_name}"
    file_count = 0

    with zipfile.ZipFile(out_ipa_path, "w") as zf:
        for dir_rel in ("Payload/", f"Payload/{app_name}/"):
            zi = zipfile.ZipInfo(dir_rel)
            zi.create_system = 3
            zi.external_attr = (0o040755 << 16) | 0x10
            zf.writestr(zi, b"")

        for root, dirs, files in os.walk(app_dir, followlinks=False):
            dirs.sort()
            files.sort()
            root_path = Path(root)
            rel_root = root_path.relative_to(app_dir)

            for dname in dirs:
                dpath = root_path / dname
                arc_dir = (Path("Payload") / app_name / rel_root / dname).as_posix() + "/"
                if os.path.islink(dpath):
                    zi = zipfile.ZipInfo(arc_dir.rstrip("/"))
                    zi.create_system = 3
                    zi.external_attr = 0o120777 << 16
                    zf.writestr(zi, os.readlink(dpath).encode("utf-8"))
                else:
                    zi = zipfile.ZipInfo(arc_dir)
                    zi.create_system = 3
                    zi.external_attr = (0o040755 << 16) | 0x10
                    zf.writestr(zi, b"")

            for fname in files:
                fpath = root_path / fname
                arc_name = (Path("Payload") / app_name / rel_root / fname).as_posix()
                zi = zipfile.ZipInfo(arc_name)
                zi.create_system = 3
                if os.path.islink(fpath):
                    zi.compress_type = zipfile.ZIP_DEFLATED
                    zi.external_attr = 0o120777 << 16
                    zf.writestr(zi, os.readlink(fpath).encode("utf-8"))
                else:
                    is_exec = (
                        arc_name == exec_rel
                        or fpath.suffix.lower() == ".dylib"
                        or _is_macho_binary(fpath)
                    )
                    mode = 0o100755 if is_exec else 0o100644
                    zi.external_attr = mode << 16
                    compress = (
                        zipfile.ZIP_STORED
                        if fpath.suffix.lower() == ".pck" or is_exec
                        else zipfile.ZIP_DEFLATED
                    )
                    zi.compress_type = compress
                    zf.writestr(zi, fpath.read_bytes(), compress_type=compress)
                file_count += 1

    return {
        "ipa": str(out_ipa_path),
        "bytes": out_ipa_path.stat().st_size,
        "sha256": sha256_file(out_ipa_path),
        "files": file_count,
        "exec_arc": exec_rel,
    }


def verify_ipa(
    ipa_path: Path, ldid_exe: Path | None = None, require_pck: bool = True
) -> dict[str, Any]:
    """对产出的 .ipa 执行全项自动化体检。"""
    if not ipa_path.is_file():
        raise FileNotFoundError(f"IPA 文件不存在: {ipa_path}")

    with zipfile.ZipFile(ipa_path, "r") as zf:
        bad = zf.testzip()
        if bad is not None:
            raise ValueError(f"IPA ZIP CRC 损坏，首个异常条目: {bad}")

        names = zf.namelist()
        plist_candidates = [
            n
            for n in names
            if n.startswith("Payload/") and n.endswith(".app/Info.plist") and n.count("/") == 2
        ]
        if len(plist_candidates) != 1:
            raise ValueError(f"IPA Payload/*.app/Info.plist 数量异常: {plist_candidates}")

        plist_arc = plist_candidates[0]
        app_prefix = plist_arc[: -len("Info.plist")]
        plist_data = plistlib.loads(zf.read(plist_arc))
        exec_name = str(plist_data.get("CFBundleExecutable", ""))
        if not exec_name:
            raise ValueError("Info.plist 缺少 CFBundleExecutable")

        if not bool(plist_data.get("UIFileSharingEnabled", False)):
            raise ValueError("Info.plist 未开启 UIFileSharingEnabled=true")
        if not bool(plist_data.get("LSSupportsOpeningDocumentsInPlace", False)):
            raise ValueError("Info.plist 未开启 LSSupportsOpeningDocumentsInPlace=true")

        orientations = plist_data.get("UISupportedInterfaceOrientations", [])
        if (
            "UIInterfaceOrientationLandscapeLeft" not in orientations
            and "UIInterfaceOrientationLandscapeRight" not in orientations
        ):
            raise ValueError("Info.plist 未包含横屏方向配置")

        device_family = plist_data.get("UIDeviceFamily")
        if isinstance(device_family, list) and device_family and 1 not in [int(x) for x in device_family]:
            raise ValueError(f"Info.plist UIDeviceFamily 未包含 iPhone (1): {device_family}")

        exec_arc = app_prefix + exec_name
        if exec_arc not in names:
            raise ValueError(f"IPA 中缺少主可执行文件: {exec_arc}")
        exec_info = zf.getinfo(exec_arc)
        perm_bits = (exec_info.external_attr >> 16) & 0o777
        if (perm_bits & 0o111) == 0:
            raise ValueError(
                f"主可执行文件缺少 UNIX +x 权限位 ({oct(perm_bits)}): {exec_arc}"
            )

        pck_entries = [
            n for n in names if n.startswith(app_prefix) and n.lower().endswith(".pck")
        ]
        if require_pck and not pck_entries:
            raise ValueError(f"IPA 中缺少 Godot 资源包 (.pck): {app_prefix}")
        expected_pck_arc = f"{app_prefix}{exec_name}.pck"
        if require_pck and (len(pck_entries) != 1 or pck_entries[0] != expected_pck_arc):
            raise ValueError(
                f"IPA 内 .pck 数量或命名异常（期望唯一 {expected_pck_arc}）: {pck_entries}"
            )

        junk_entries = [
            n
            for n in names
            if n.lower().endswith(".import")
            or n.endswith("/.DS_Store")
            or n == ".DS_Store"
            or "/__MACOSX/" in n
            or n.startswith("__MACOSX/")
        ]
        if junk_entries:
            raise ValueError(
                f"IPA 内包含未清理的编辑器/系统垃圾文件: {junk_entries[:5]}"
            )

        with tempfile.TemporaryDirectory(prefix="sg0_verify_") as td:
            td_path = Path(td)
            tmp_exec = td_path / exec_name
            tmp_exec.write_bytes(zf.read(exec_arc))
            macho_info = inspect_macho(tmp_exec)
            if not macho_info.get("valid_arm64"):
                raise ValueError(f"主可执行文件不是合法 arm64 Mach-O: {macho_info}")

            ent_info: dict[str, Any] = {}
            if ldid_exe is not None and ldid_exe.is_file():
                ent_info = read_entitlements_with_ldid(ldid_exe, tmp_exec)
                validate_entitlements_dict(ent_info, f"IPA({ipa_path.name})")

            pck_report: dict[str, Any] | None = None
            if pck_entries:
                tmp_pck = td_path / Path(pck_entries[0]).name
                tmp_pck.write_bytes(zf.read(pck_entries[0]))
                pck_report = parse_pck_entries(tmp_pck)
                if pck_report["leaks"]:
                    raise ValueError(
                        f"IPA 内 .pck 包含禁打包文件: {pck_report['leaks'][:5]}"
                    )

    return {
        "ipa": str(ipa_path),
        "bytes": ipa_path.stat().st_size,
        "sha256": sha256_file(ipa_path),
        "bundle_id": plist_data.get("CFBundleIdentifier"),
        "display_name": plist_data.get("CFBundleDisplayName")
        or plist_data.get("CFBundleName"),
        "executable": exec_arc,
        "executable_perm": oct(perm_bits),
        "macho": macho_info,
        "entitlements": ent_info,
        "pck": {
            "entries": pck_entries,
            "file_count": pck_report["file_count"] if pck_report else 0,
            "bytes": pck_report["bytes"] if pck_report else 0,
        },
    }


def export_pck(
    project_dir: Path,
    out_pck_path: Path,
    godot_exe: Path,
    preset: str = "iOS",
) -> dict[str, Any]:
    out_pck_path.parent.mkdir(parents=True, exist_ok=True)
    build_dir = (project_dir / "build").resolve()
    try:
        out_pck_path.resolve().relative_to(build_dir)
    except ValueError:
        pass
    else:
        gdignore = build_dir / ".gdignore"
        if not gdignore.exists():
            gdignore.write_text("", encoding="utf-8")

    cmd = [
        str(godot_exe),
        "--headless",
        "--path",
        str(project_dir),
        "--export-pack",
        preset,
        str(out_pck_path),
    ]
    proc = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(
            f"Godot --export-pack 失败 (code={proc.returncode}):\n{proc.stdout}\n{proc.stderr}"
        )
    if not out_pck_path.is_file():
        raise FileNotFoundError(f"Godot 未生成目标 PCK 文件: {out_pck_path}")
    report = parse_pck_entries(out_pck_path)
    if report["leaks"]:
        raise ValueError(f"导出的 PCK 包含禁打包文件泄露: {report['leaks'][:5]}")
    return report


def package_trollstore_ipa(
    app_shell: Path,
    out_ipa: Path,
    pck_path: Path | None = None,
    entitlements_path: Path = DEFAULT_ENTITLEMENTS,
    ldid_exe: Path | None = None,
    bundle_id: str | None = None,
    display_name: str | None = None,
    report_json: Path | None = None,
) -> dict[str, Any]:
    if ldid_exe is None:
        ldid_exe = find_ldid()

    if pck_path is not None:
        pck_info = parse_pck_entries(pck_path)
        if pck_info["leaks"]:
            raise ValueError(f"输入 PCK 包含禁打包文件泄露: {pck_info['leaks'][:5]}")

    with tempfile.TemporaryDirectory(prefix="sg0_pkg_") as td:
        work_dir = Path(td)
        app_dir = _resolve_app_shell(app_shell, work_dir)

        old_sig = app_dir / "_CodeSignature"
        if old_sig.exists():
            shutil.rmtree(old_sig)
        for macosx_dir in sorted(app_dir.rglob("__MACOSX"), reverse=True):
            if macosx_dir.is_dir():
                shutil.rmtree(macosx_dir)
        for junk in sorted(app_dir.rglob("*")):
            if junk.is_file() and (junk.name == ".DS_Store" or junk.suffix.lower() == ".import"):
                junk.unlink()

        plist_data = patch_info_plist(
            app_dir / "Info.plist",
            bundle_id=bundle_id,
            display_name=display_name,
        )
        exec_name = str(plist_data.get("CFBundleExecutable", ""))
        if not exec_name:
            raise ValueError(f"{app_dir / 'Info.plist'} 缺少 CFBundleExecutable")
        exec_path = app_dir / exec_name
        if not exec_path.is_file():
            raise FileNotFoundError(f"App 包内缺少主可执行文件: {exec_path}")

        macho_info = inspect_macho(exec_path)
        if not macho_info.get("valid_arm64"):
            raise ValueError(f"App 主二进制不是合法 arm64 Mach-O: {macho_info}")

        if pck_path is not None:
            for old_pck in sorted(app_dir.rglob("*"), reverse=True):
                if old_pck.suffix.lower() == ".pck":
                    if old_pck.is_file() or old_pck.is_symlink():
                        old_pck.unlink()
                    elif old_pck.is_dir():
                        shutil.rmtree(old_pck)
            target_pck = app_dir / f"{exec_name}.pck"
            shutil.copy2(pck_path, target_pck)

        for dylib in sorted(app_dir.rglob("*.dylib")):
            if dylib.is_file() and _is_macho_binary(dylib):
                subprocess.run(
                    [str(ldid_exe), "-S", str(dylib)],
                    capture_output=True,
                    check=True,
                )

        entitlements_signed = sign_with_ldid(ldid_exe, exec_path, entitlements_path)
        build_zip_ipa(app_dir, out_ipa, exec_name)

    has_pck_in_ipa = False
    with zipfile.ZipFile(out_ipa, "r") as zf:
        has_pck_in_ipa = any(n.lower().endswith(".pck") for n in zf.namelist())
    verify_report = verify_ipa(out_ipa, ldid_exe=ldid_exe, require_pck=has_pck_in_ipa)
    verify_report["signed_entitlements"] = entitlements_signed

    if report_json is not None:
        report_json.parent.mkdir(parents=True, exist_ok=True)
        report_json.write_text(
            json.dumps(verify_report, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
    return verify_report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="SteinsGate0_iOS TrollStore 打包、PCK 导出与签名验证工具"
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_exp = sub.add_parser("export-pck", help="使用 Godot 4.3 导出并校验运行时 .pck")
    p_exp.add_argument("--project", default=str(DEFAULT_PROJECT_DIR))
    p_exp.add_argument("--godot", default=None)
    p_exp.add_argument("--preset", default="iOS")
    p_exp.add_argument(
        "--output",
        default=str(DEFAULT_PROJECT_DIR / "build" / "ios" / "SteinsGate0_iOS.pck"),
    )

    p_pkg = sub.add_parser(
        "package", help="将 .pck 注入 iOS .app/.zip/.ipa 母包，ldid 签名并封装 TrollStore .ipa"
    )
    p_pkg.add_argument("--app-shell", required=True, help="iOS .app 目录、Shell.zip 或母包 .ipa")
    p_pkg.add_argument("--pck", default=None, help="要注入的 .pck 路径（可选）")
    p_pkg.add_argument("--entitlements", default=str(DEFAULT_ENTITLEMENTS))
    p_pkg.add_argument("--ldid", default=None)
    p_pkg.add_argument("--bundle-id", default=None)
    p_pkg.add_argument("--display-name", default=None)
    p_pkg.add_argument("--report-json", default=None)
    p_pkg.add_argument(
        "--output",
        default=str(DEFAULT_PROJECT_DIR / "build" / "ios" / "SteinsGate0_iOS_TrollStore.ipa"),
    )

    p_ver = sub.add_parser("verify-ipa", help="校验既有 .ipa 的签名、权限与结构完整性")
    p_ver.add_argument("--ipa", required=True)
    p_ver.add_argument("--ldid", default=None)
    p_ver.add_argument("--no-require-pck", action="store_true")

    args = parser.parse_args(argv)

    if args.cmd == "export-pck":
        godot_exe = find_godot(args.godot)
        rep = export_pck(Path(args.project), Path(args.output), godot_exe, args.preset)
        summary = {k: v for k, v in rep.items() if k != "paths"}
        print(json.dumps(summary, indent=2, ensure_ascii=False))
        return 0

    if args.cmd == "package":
        ldid_exe = find_ldid(args.ldid)
        rep = package_trollstore_ipa(
            app_shell=Path(args.app_shell),
            out_ipa=Path(args.output),
            pck_path=Path(args.pck) if args.pck else None,
            entitlements_path=Path(args.entitlements),
            ldid_exe=ldid_exe,
            bundle_id=args.bundle_id,
            display_name=args.display_name,
            report_json=Path(args.report_json) if args.report_json else None,
        )
        print(json.dumps(rep, indent=2, ensure_ascii=False))
        return 0

    if args.cmd == "verify-ipa":
        ldid_exe = None
        try:
            ldid_exe = find_ldid(args.ldid)
        except FileNotFoundError:
            pass
        rep = verify_ipa(
            Path(args.ipa),
            ldid_exe=ldid_exe,
            require_pck=not args.no_require_pck,
        )
        print(json.dumps(rep, indent=2, ensure_ascii=False))
        return 0

    return 1


if __name__ == "__main__":
    sys.exit(main())
