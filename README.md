# Caesium Image Compressor · Linux arm64 (Qt 5.12)

Caesium Image Compressor 2.8.5 的 arm64 deb 包，编译时把 Qt 依赖降到了 5.12。

非官方移植，与 SaeraSoft 和原作者无关。

## 为什么需要它

上游从 2.8 开始要求 Qt 6.5 以上。Qt 官方给 arm64 的预编译包要求 glibc 2.38+，
而麒麟 V10、Ubuntu 20.04、Debian 11 这些系统上是 glibc 2.31 加 Qt 5.12，
官方包装上打不开，源码也编不过。

这个仓库把上游源码适配回 Qt 5.12 再编译打包，这些系统就能直接用了。

## 安装

从 Releases 下载 deb：

```bash
sudo dpkg -i caesium-image-compressor_2.8.5-1_arm64.deb
```

装完在开始菜单里搜 Caesium。

运行需要 glibc 2.29+、Qt 5.12.2+。WebP 支持依赖 `qt5-image-formats-plugins`，
多数发行版默认已装。

## 自己编译

以 Debian/Ubuntu 系为例：

```bash
sudo apt install build-essential cmake patch curl qtbase5-dev \
                 qtbase5-dev-tools qttools5-dev-tools patchelf
pip3 install cairosvg
```

编译 libcaesium 还要 Rust：

```bash
curl https://sh.rustup.rs -sSf | sh -s -- -y
```

然后：

```bash
./scripts/build.sh
```

产物在 `dist/`。脚本会自己下载上游 v2.8.5 源码和 libcaesium 0.17.4 的 crate。

## 改了什么

改动都在 `patches/0001-qt5-arm64-port.patch` 里，主要是几类：

- Qt 6 专有 API 换成 Qt 5 的等价写法（主题、屏幕、`QVariant::type`、图片大小上限等）
- 重载信号加 `qOverload`，补上 Qt 6 里隐含的头文件
- 16 个 SVG 图标转成 256px PNG。Qt 5.12 的 SVG 解析器会截断这批图标的路径，
  工具栏会缺图标，所以干脆去掉 QtSvg 依赖
- 去掉使用统计上报（`NetworkOperations`），压缩过程不再联网

## 已知问题

- 不跟随系统暗色主题，程序里可以手动切
- 窗口分隔条位置不保存（Qt 5 序列化 `QList<int>` 的兼容问题），启动会打一条警告，不影响使用
- 图标是 256px 位图，高分屏下略糊

## 许可

上游是 GPL-3.0-or-later，本仓库同样。压缩引擎 libcaesium 是 Apache-2.0。
