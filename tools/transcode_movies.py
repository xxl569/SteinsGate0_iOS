#!/usr/bin/env python3
"""
STEINS;GATE 0 过场视频批量转码工具 (.bk2 -> .ogv)

工作原理：
1. 使用 i686-w64-mingw32-gcc 编译 32 位 tools/bink2_raw.c，调用原版 bink2w32.dll 解码 KB2j 视频帧；
2. 利用 ffprobe 检测每部 .bk2 的原始帧率与是否包含音频轨 (binkaudio_dct)；
3. 将原始 BGRA 视频流通过管道直传 ffmpeg.exe（缩放至宽度不超过 1600px、yuv420p、libtheora -qscale:v 7），
   若有音轨则同步混流原 .bk2 的 binkaudio_dct -> libvorbis (-qscale:a 5)，原子写入为 .ogv；
4. 支持多进程并发转码及全量 ffprobe 校验。
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any


def find_exe(name: str) -> str:
    """查找可执行程序路径（支持 PATH 与 Windows WinGet Links）。"""
    found = shutil.which(name)
    if found:
        return found
    local_app = os.environ.get("LOCALAPPDATA", "")
    if local_app:
        cand = Path(local_app) / "Microsoft" / "WinGet" / "Links" / (name if name.endswith(".exe") else f"{name}.exe")
        if cand.exists():
            return str(cand)
    raise FileNotFoundError(f"未找到可执行文件: {name}")


def ensure_bink2_bridge(src_c: Path, out_exe: Path) -> Path:
    """按需编译 32 位 bink2_raw.exe 桥接工具。"""
    out_exe.parent.mkdir(parents=True, exist_ok=True)
    if out_exe.exists() and out_exe.stat().st_mtime >= src_c.stat().st_mtime:
        return out_exe
    gcc = find_exe("i686-w64-mingw32-gcc")
    cmd = [gcc, "-O2", str(src_c), "-o", str(out_exe)]
    subprocess.run(cmd, check=True)
    return out_exe


def probe_media(ffprobe: str, path: Path) -> dict[str, Any]:
    """调用 ffprobe 获取媒体流元信息。"""
    cmd = [
        ffprobe,
        "-v", "error",
        "-show_entries", "format=duration,size:stream=index,codec_type,codec_name,width,height,r_frame_rate,avg_frame_rate,nb_frames",
        "-of", "json",
        str(path),
    ]
    res = subprocess.run(cmd, capture_output=True, text=True, check=True)
    return json.loads(res.stdout)


def query_bink_info(bridge: Path, dll: Path, bk2: Path) -> dict[str, Any]:
    """调用 bink2_raw.exe --info 读取视频宽、高、总帧数及帧率。"""
    cmd = [str(bridge), "--dll", str(dll), "--input", str(bk2), "--info"]
    res = subprocess.run(cmd, capture_output=True, text=True, check=True)
    return json.loads(res.stdout.strip())


def transcode_one(
    bk2: Path,
    out_ogv: Path,
    bridge: Path,
    dll: Path,
    ffmpeg: str,
    ffprobe: str,
    surface: int,
    max_width: int,
    v_quality: int,
    a_quality: int,
    force: bool,
) -> tuple[str, bool, str]:
    """转码单个 .bk2 文件为 .ogv，返回 (文件名, 是否成功, 详情)。"""
    try:
        src_probe = probe_media(ffprobe, bk2)
        src_streams = src_probe.get("streams", [])
        has_audio = any(s.get("codec_type") == "audio" for s in src_streams)

        if out_ogv.exists() and not force:
            try:
                dst_probe = probe_media(ffprobe, out_ogv)
                dst_streams = dst_probe.get("streams", [])
                v_ok = any(s.get("codec_type") == "video" and s.get("codec_name") == "theora" for s in dst_streams)
                a_ok = (not has_audio) or any(s.get("codec_type") == "audio" and s.get("codec_name") == "vorbis" for s in dst_streams)
                dur = float(dst_probe.get("format", {}).get("duration", 0.0) or 0.0)
                if v_ok and a_ok and dur > 0.1:
                    return bk2.name, True, f"跳过已存在且有效 ({dur:.2f}s)"
            except Exception:
                pass

        info = query_bink_info(bridge, dll, bk2)
        w, h = int(info["width"]), int(info["height"])
        fr_num, fr_den = int(info["frame_rate"]), int(info["frame_div"])
        fps_str = f"{fr_num}/{fr_den}"

        out_ogv.parent.mkdir(parents=True, exist_ok=True)
        tmp_ogv = out_ogv.with_suffix(".tmp.ogv")
        if tmp_ogv.exists():
            tmp_ogv.unlink()

        bridge_cmd = [
            str(bridge),
            "--dll", str(dll),
            "--input", str(bk2),
            "--surface", str(surface),
        ]

        pix_fmt_in = "bgra" if surface == 3 else "rgba"
        vf = f"scale='min({max_width},iw)':-2:flags=lanczos,format=yuv420p"

        ff_cmd = [
            ffmpeg, "-y", "-v", "error",
            "-f", "rawvideo",
            "-pix_fmt", pix_fmt_in,
            "-s", f"{w}x{h}",
            "-r", fps_str,
            "-i", "pipe:0",
        ]
        if has_audio:
            ff_cmd.extend(["-vn", "-sn", "-dn", "-i", str(bk2)])
            ff_cmd.extend(["-map", "0:v:0", "-map", "1:a:0"])
        else:
            ff_cmd.extend(["-map", "0:v:0", "-an"])

        ff_cmd.extend([
            "-vf", vf,
            "-c:v", "libtheora",
            "-qscale:v", str(v_quality),
        ])
        if has_audio:
            ff_cmd.extend(["-c:a", "libvorbis", "-qscale:a", str(a_quality)])
        ff_cmd.extend(["-f", "ogg", str(tmp_ogv)])

        p_bridge = subprocess.Popen(bridge_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        p_ff = subprocess.Popen(ff_cmd, stdin=p_bridge.stdout, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert p_bridge.stdout is not None
        p_bridge.stdout.close()

        _, ff_err = p_ff.communicate()
        b_err = p_bridge.stderr.read() if p_bridge.stderr else b""
        b_rc = p_bridge.wait()

        if b_rc != 0 or p_ff.returncode != 0 or not tmp_ogv.exists():
            if tmp_ogv.exists():
                tmp_ogv.unlink()
            return (
                bk2.name,
                False,
                f"bridge_rc={b_rc} ({b_err.decode(errors='ignore').strip()}), "
                f"ffmpeg_rc={p_ff.returncode} ({ff_err.decode(errors='ignore').strip()})",
            )

        os.replace(tmp_ogv, out_ogv)
        dst_probe = probe_media(ffprobe, out_ogv)
        dst_v = [s for s in dst_probe["streams"] if s["codec_type"] == "video"][0]
        dur = float(dst_probe["format"].get("duration", 0.0) or 0.0)
        return (
            bk2.name,
            True,
            f"{dst_v['width']}x{dst_v['height']} theora{'+vorbis' if has_audio else ''}, {dur:.2f}s, {out_ogv.stat().st_size // 1024} KB",
        )
    except Exception as exc:
        return bk2.name, False, str(exc)


def verify_all_ogv(src_dir: Path, out_dir: Path, ffprobe: str) -> int:
    """逐一核对目标目录内所有 .ogv 是否与源 .bk2 一一对应且流完整。"""
    bk2s = sorted(src_dir.glob("*.bk2"))
    if not bk2s:
        print(f"错误: {src_dir} 中未找到 .bk2 文件")
        return 1
    bad = 0
    total_bytes = 0
    for bk2 in bk2s:
        ogv = out_dir / f"{bk2.stem}.ogv"
        if not ogv.exists():
            print(f"[MISSING] {ogv.name}")
            bad += 1
            continue
        src_p = probe_media(ffprobe, bk2)
        dst_p = probe_media(ffprobe, ogv)
        src_audio = any(s.get("codec_type") == "audio" for s in src_p.get("streams", []))
        dst_v = [s for s in dst_p.get("streams", []) if s.get("codec_type") == "video"]
        dst_a = [s for s in dst_p.get("streams", []) if s.get("codec_type") == "audio"]
        dur_src = float(src_p["format"].get("duration", 0.0) or 0.0)
        dur_dst = float(dst_p["format"].get("duration", 0.0) or 0.0)
        if (
            len(dst_v) != 1
            or dst_v[0].get("codec_name") != "theora"
            or (src_audio and (len(dst_a) != 1 or dst_a[0].get("codec_name") != "vorbis"))
            or abs(dur_src - dur_dst) > 1.5
        ):
            print(f"[BAD] {ogv.name}: v={dst_v} a={dst_a} dur={dur_dst:.2f}/{dur_src:.2f}")
            bad += 1
        else:
            sz = ogv.stat().st_size
            total_bytes += sz
            print(f"[OK] {ogv.name}: {dst_v[0]['width']}x{dst_v[0]['height']} dur={dur_dst:.2f}s audio={len(dst_a)} ({sz//1024} KB)")
    print(f"Verify summary: total={len(bk2s)}, ok={len(bk2s)-bad}, bad={bad}, total_size={total_bytes/(1024*1024):.1f} MB")
    return 0 if bad == 0 else 1


def main() -> int:
    parser = argparse.ArgumentParser(description="STEINS;GATE 0 批量转码 .bk2 -> .ogv")
    parser.add_argument("--src-dir", type=Path, default=Path(r"U:\anti\projects\STEINS GATE 0\USRDIR\movie\1920x1080"))
    parser.add_argument("--out-dir", type=Path, default=Path(r"U:\anti\temp\SteinsGate0_iOS\SteinsGate0_iOS_Documents\movie"))
    parser.add_argument("--dll", type=Path, default=Path(r"U:\anti\projects\STEINS GATE 0\bink2w32.dll"))
    parser.add_argument("--bridge-exe", type=Path, default=Path(r"U:\anti\temp\SteinsGate0_iOS\bink2_raw.exe"))
    parser.add_argument("--surface", type=int, default=3, help="3=BINKSURFACE32(BGRA), 4=BINKSURFACE32R(RGBA)")
    parser.add_argument("--max-width", type=int, default=1600)
    parser.add_argument("--v-quality", type=int, default=7)
    parser.add_argument("--a-quality", type=int, default=5)
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--only", nargs="*", help="仅转码指定文件名（如 OP.bk2 IMV011.bk2）")
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()

    ffprobe = find_exe("ffprobe")
    if args.verify_only:
        return verify_all_ogv(args.src_dir, args.out_dir, ffprobe)

    ffmpeg = find_exe("ffmpeg")
    tools_dir = Path(__file__).resolve().parent
    bridge = ensure_bink2_bridge(tools_dir / "bink2_raw.c", args.bridge_exe)

    bk2s = sorted(args.src_dir.glob("*.bk2"))
    if args.only:
        wanted = set(args.only)
        bk2s = [p for p in bk2s if p.name in wanted]
    if not bk2s:
        print("未找到任何待转码的 .bk2 文件")
        return 1

    print(f"开始批量转码: {len(bk2s)} 个 .bk2 -> {args.out_dir} (jobs={args.jobs}, surface={args.surface})")
    failed: list[tuple[str, str]] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futs = {
            pool.submit(
                transcode_one,
                bk2,
                args.out_dir / f"{bk2.stem}.ogv",
                bridge,
                args.dll,
                ffmpeg,
                ffprobe,
                args.surface,
                args.max_width,
                args.v_quality,
                args.a_quality,
                args.force,
            ): bk2.name
            for bk2 in bk2s
        }
        for idx, fut in enumerate(concurrent.futures.as_completed(futs), 1):
            name, ok, msg = fut.result()
            status = "OK" if ok else "FAIL"
            print(f"[{idx:02d}/{len(bk2s):02d}] [{status}] {name}: {msg}", flush=True)
            if not ok:
                failed.append((name, msg))

    if failed:
        print(f"转码失败 {len(failed)} 个:", failed)
        return 1
    return verify_all_ogv(args.src_dir, args.out_dir, ffprobe) if not args.only else 0


if __name__ == "__main__":
    raise SystemExit(main())
