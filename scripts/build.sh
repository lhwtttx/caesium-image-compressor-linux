#!/usr/bin/env bash
#
# 构建 Caesium Image Compressor 2.8.5 的 arm64 deb（Qt 5.12 移植版）
#
#   ./scripts/build.sh
#
# 流程：下载上游源码 -> 打 Qt5 补丁 -> SVG 图标转 PNG -> 编译 libcaesium
#       -> 编主程序 -> 组装 deb
#
# 可用环境变量：
#   BUILD_DIR   中间目录，默认 .build
#   DIST_DIR    输出目录，默认 dist
#   QT_PREFIX   Qt5 前缀，装了 qtbase5-dev 一般不用设
#   JOBS        并行数，默认 nproc
#
set -euo pipefail

VERSION=2.8.5
REVISION=3
LIBCAESIUM_VERSION=0.17.4
PKG=caesium-image-compressor
ARCH=arm64
MAINT="Huey Long <lhwtttx@users.noreply.github.com>"
HOMEPAGE="https://github.com/lhwtttx/caesium-image-compressor-linux"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="${BUILD_DIR:-$ROOT/.build}"
DIST="${DIST_DIR:-$ROOT/dist}"
SRC="$BUILD/src"
CMAKE_DIR="$BUILD/cmake"
STAGE="$BUILD/stage"
JOBS="${JOBS:-$(nproc)}"
LIBCAESIUM_SO="$BUILD/libcaesium/libcaesium-$LIBCAESIUM_VERSION/target/release/libcaesium.so"

# 部分国产系统 /tmp 只有 10MB，cmake 和 rust 会在那里失败
mkdir -p "$BUILD/tmp"
export TMPDIR="$BUILD/tmp"

for t in cmake make curl tar patch gcc g++ cargo python3 patchelf; do
    command -v "$t" >/dev/null || { echo "缺少 $t，请先安装构建依赖（见 README）" >&2; exit 1; }
done
python3 -c "import cairosvg" 2>/dev/null || { echo "缺少 cairosvg：pip3 install cairosvg" >&2; exit 1; }

# 1. 上游源码 + 补丁 + 图标
if [ ! -f "$SRC/.patched" ]; then
    echo "==> 下载上游 v$VERSION"
    rm -rf "$SRC"
    mkdir -p "$SRC"
    curl -fL --retry 3 -o "$BUILD/upstream.tar.gz" \
        "https://codeload.github.com/Lymphatus/caesium-image-compressor/tar.gz/refs/tags/v$VERSION"
    tar xzf "$BUILD/upstream.tar.gz" -C "$SRC" --strip-components=1

    echo "==> 应用 Qt5 补丁"
    patch -p1 -d "$SRC" --no-backup-if-mismatch \
        < "$ROOT/patches/0001-qt5-arm64-port.patch"

    echo "==> 图标转 PNG"
    python3 "$ROOT/tools/convert-icons.py" --root "$SRC/resources/icons"
    touch "$SRC/.patched"
else
    echo "==> 源码已就绪，跳过下载与打补丁"
fi

# 2. libcaesium
if [ ! -f "$LIBCAESIUM_SO" ]; then
    echo "==> 编译 libcaesium $LIBCAESIUM_VERSION"
    mkdir -p "$BUILD/libcaesium"
    if [ ! -d "$BUILD/libcaesium/libcaesium-$LIBCAESIUM_VERSION" ]; then
        curl -fL --retry 3 -o "$BUILD/libcaesium/libcaesium.crate" \
            "https://static.crates.io/crates/libcaesium/libcaesium-$LIBCAESIUM_VERSION.crate"
        tar xzf "$BUILD/libcaesium/libcaesium.crate" -C "$BUILD/libcaesium"
    fi
    ( cd "$BUILD/libcaesium/libcaesium-$LIBCAESIUM_VERSION" && cargo build --release )
else
    echo "==> libcaesium 已编译，跳过"
fi

# 3. 主程序
echo "==> 编译主程序"
cmake -S "$SRC" -B "$CMAKE_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_PREFIX_PATH="${QT_PREFIX:-/usr}" \
    -DLIBCAESIUM="$LIBCAESIUM_SO"
cmake --build "$CMAKE_DIR" -j"$JOBS"

# 4. 打包
echo "==> 组装 deb"
rm -rf "$STAGE"
mkdir -p "$STAGE"
DESTDIR="$STAGE" cmake --install "$CMAKE_DIR" >/dev/null

# 传了 -DLIBCAESIUM 上游就跳过它自己的安装规则，这里手动放进去
LIBS="$STAGE/usr/lib/aarch64-linux-gnu"
mkdir -p "$LIBS"
cp "$LIBCAESIUM_SO" "$LIBS/libcaesium.so"
patchelf --set-soname libcaesium.so "$LIBS/libcaesium.so"
strip --strip-unneeded "$STAGE/usr/bin/$PKG" "$LIBS/libcaesium.so" 2>/dev/null || true

mkdir -p "$STAGE/usr/share/applications" "$STAGE/usr/share/icons/hicolor/512x512/apps" \
         "$STAGE/DEBIAN"
install -m 644 "$SRC/resources/icons/logo.png" \
    "$STAGE/usr/share/icons/hicolor/512x512/apps/$PKG.png"

cat > "$STAGE/usr/share/applications/$PKG.desktop" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=Caesium Image Compressor
Name[zh_CN]=Caesium 图片压缩
GenericName=Image Compressor
Comment=Compress JPEG, PNG, WebP and TIFF images
Exec=$PKG
Icon=$PKG
Terminal=false
Categories=Graphics;Photography;
Keywords=image;compress;jpeg;png;webp;tiff;
EOF

SIZE=$(du -sk --exclude=DEBIAN "$STAGE" | cut -f1)
cat > "$STAGE/DEBIAN/control" <<EOF
Package: $PKG
Version: $VERSION-$REVISION
Section: graphics
Priority: optional
Architecture: $ARCH
Installed-Size: $SIZE
Depends: libc6 (>= 2.29), libgcc-s1 (>= 3.0), libstdc++6 (>= 5.2), libqt5core5a (>= 5.12.2), libqt5gui5 (>= 5.10.0), libqt5widgets5 (>= 5.12.2), libqt5concurrent5 (>= 5.6.0~rc), qt5-image-formats-plugins
Maintainer: $MAINT
Homepage: $HOMEPAGE
Description: Caesium Image Compressor (unofficial Qt 5 port)
 Lossy and lossless image compression for JPEG, PNG, WebP and TIFF.
 .
 Unofficial port built against Qt 5.12, for aarch64 systems that do not
 ship Qt 6 (Kylin V10, Ubuntu 20.04, Debian 11 and similar).
EOF

printf '#!/bin/sh\nset -e\nif [ "$1" = "configure" ]; then ldconfig; fi\n' \
    > "$STAGE/DEBIAN/postinst"
printf '#!/bin/sh\nset -e\nif [ "$1" = "remove" ] || [ "$1" = "purge" ]; then ldconfig; fi\n' \
    > "$STAGE/DEBIAN/postrm"
chmod 755 "$STAGE/DEBIAN/postinst" "$STAGE/DEBIAN/postrm"

mkdir -p "$DIST"
DEB="$DIST/${PKG}_${VERSION}-${REVISION}_${ARCH}.deb"
dpkg-deb --build --root-owner-group "$STAGE" "$DEB" >/dev/null

echo
dpkg-deb -f "$DEB" Package Version Architecture Installed-Size
ls -lh "$DEB"
echo
echo "安装：sudo dpkg -i $DEB"
