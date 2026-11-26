#!/usr/bin/env python3
"""把 resources/icons 下的 SVG 图标栅格化为 256x256 PNG。

为什么需要这一步
----------------
Qt 5.12 的 SVG 解析器（QtSvg）会截断 Caesium 2.8.5 这批图标的路径数据，运行时
不断输出 "Invalid path data; path truncated"，工具栏图标残缺。Qt5 移植版因此把
图标预渲染为 PNG，并从 CMake 中移除 QtSvg 依赖。

用法
----
在解压后的上游源码根目录执行，且在应用补丁**之后**：

    python3 tools/convert-icons.py

补丁会把 resources/resources.qrc 里的引用改成 .png，但不会凭空生成位图，
所以这个脚本负责生成 PNG 并删除原 SVG。

依赖（任选其一）
----------------
1. cairosvg      : pip install cairosvg      （推荐，纯 Python + libcairo2）
2. rsvg-convert  : apt install librsvg2-bin  （librsvg 的 CLI）
"""

import argparse
import pathlib
import shutil
import subprocess
import sys

DEFAULT_SIZE = 256


def render_with_cairosvg(svg: pathlib.Path, out: pathlib.Path, size: int) -> bool:
    try:
        import cairosvg
    except ImportError:
        return False
    cairosvg.svg2png(
        url=str(svg), write_to=str(out), output_width=size, output_height=size
    )
    return True


def render_with_rsvg(svg: pathlib.Path, out: pathlib.Path, size: int) -> bool:
    exe = shutil.which("rsvg-convert")
    if not exe:
        return False
    subprocess.run(
        [exe, "-w", str(size), "-h", str(size), "-o", str(out), str(svg)],
        check=True,
    )
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description="SVG -> PNG icon rasterizer")
    parser.add_argument("--size", type=int, default=DEFAULT_SIZE, help="输出边长，默认 256")
    parser.add_argument("--keep-svg", action="store_true", help="保留原始 SVG（仅调试）")
    parser.add_argument("--root", default="resources/icons", help="图标目录，默认 resources/icons")
    args = parser.parse_args()

    root = pathlib.Path(args.root)
    if not root.is_dir():
        print(f"错误：找不到 {root.resolve()}", file=sys.stderr)
        print("请在 Caesium 源码根目录执行（应能看到 CMakeLists.txt）", file=sys.stderr)
        return 1

    svgs = sorted(root.rglob("*.svg"))
    if not svgs:
        print(f"{root} 下没有 SVG，可能已转换过，跳过")
        return 0

    renderer = None
    for probe in (render_with_cairosvg, render_with_rsvg):
        if probe is render_with_rsvg and shutil.which("rsvg-convert"):
            renderer = probe
            break
        if probe is render_with_cairosvg:
            try:
                import cairosvg  # noqa: F401
            except ImportError:
                continue
            renderer = probe
            break
    if renderer is None:
        print(
            "错误：需要 cairosvg 或 rsvg-convert 之一\n"
            "  pip install cairosvg\n"
            "  # 或\n"
            "  sudo apt install librsvg2-bin",
            file=sys.stderr,
        )
        return 1

    failed = []
    for svg in svgs:
        out = svg.with_suffix(".png")
        try:
            if not renderer(svg, out, args.size):
                failed.append(svg)
                continue
        except Exception as exc:  # noqa: BLE001 - 单个图标失败不应中断整批
            print(f"  失败 {svg}: {exc}", file=sys.stderr)
            failed.append(svg)
            continue
        if not args.keep_svg:
            svg.unlink()
        print(f"  {svg.relative_to(root)} -> {out.name}")

    ok = len(svgs) - len(failed)
    print(f"完成：{ok}/{len(svgs)} 个图标已转换为 {args.size}x{args.size} PNG")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
