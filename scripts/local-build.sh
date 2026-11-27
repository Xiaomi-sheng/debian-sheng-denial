#!/usr/bin/env bash
# ============================================================================
# 在 Ubuntu 24.04（arm64）里本地构建 / 缓存 / 安装 sheng 设备包
# Local builder for the Xiaomi Pad 6S Pro (sheng) device packages.
#
# 适用：Droidspaces 导入的 Ubuntu 24.04 容器、或任何 Ubuntu 24.04 arm64 系统。
# 在仓库根目录执行：  ./scripts/local-build.sh <命令>
#
#   check    检查环境（架构/发行版/依赖/网络）
#   debs     下载 + 编译全部设备包；下载缓存在 local-cache/，成品在 local-out/
#   install  把 local-out/debs 里的包装进当前系统（容器里测试用）
#   clean    清空 local-cache/ 与 local-out/
#
# 环境变量：
#   CACHE_DIR=...      缓存目录（默认 <repo>/local-cache）
#   OUT_DIR=...        产物目录（默认 <repo>/local-out）
#   WITH_KERNEL=1      install 时也装内核包（默认不装，容器里没意义）
#   WITH_FIRMWARE=1    install 时也装固件包（默认不装，会与 linux-firmware 冲突）
#
# 说明：内核用 ianchb/sm8550-mainline 的预构建包；fastrpc / libssc /
# iio-sensor-proxy / sheng-sensors / sheng-devauth / alsa / firmware 在本机编译打包。
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_DIR="${CACHE_DIR:-$ROOT/local-cache}"
OUT_DIR="${OUT_DIR:-$ROOT/local-out}"
DEB_DIR="$OUT_DIR/debs"
SRC_DIR="$CACHE_DIR/src"
DL_DIR="$CACHE_DIR/downloads"
JOBS="$(nproc 2>/dev/null || echo 4)"

WITH_KERNEL="${WITH_KERNEL:-0}"
WITH_FIRMWARE="${WITH_FIRMWARE:-0}"

info()  { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
die()   { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- environment
need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    die "请用 root 运行（Droidspaces 容器里默认就是 root）；否则 sudo 也可以。"
  fi
}

check_env() {
  local arch os_name ver_id
  arch="$(uname -m)"
  [ "$arch" = "aarch64" ] || die "需要 arm64 环境，当前是 $arch"
  if [ -r /etc/os-release ]; then
    . /etc/os-release
    os_name="${NAME:-unknown}"
    ver_id="${VERSION_ID:-0}"
  else
    die "读不到 /etc/os-release"
  fi
  info "系统：$os_name $ver_id ($arch)"
  case "$os_name" in
    Ubuntu)
      case "$ver_id" in
        24.*|25.*|26.*) ok "Ubuntu 版本满足 24.04+" ;;
        *) die "需要 Ubuntu 24.04 及以上（当前 $ver_id）" ;;
      esac ;;
    *) warn "不是 Ubuntu（$os_name），依赖名可能对不上，请自行确认" ;;
  esac
  [ -d "$ROOT/.github/workflows" ] || die "请在仓库根目录运行本脚本"
  [ -d "$ROOT/patches" ] || die "仓库缺少 patches/ 目录"
  ok "仓库目录：$ROOT"
  mkdir -p "$CACHE_DIR" "$OUT_DIR" "$DEB_DIR" "$SRC_DIR" "$DL_DIR"
  ok "缓存目录：$CACHE_DIR"
}

install_tools() {
  info "安装构建依赖（只装一次，之后走 apt 缓存）"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y --no-install-recommends \
    build-essential autoconf automake libtool pkg-config git wget curl unzip \
    dpkg-dev python3 python3-pip python3-venv \
    ninja-build meson \
    libyaml-dev linux-libc-dev \
    libglib2.0-dev libprotobuf-c-dev libqmi-glib-dev libmbim-glib-dev \
    libgudev-1.0-dev libpolkit-gobject-1-dev libsystemd-dev libdbus-1-dev \
    protobuf-compiler protobuf-c-compiler
  ok "构建依赖就绪"
}

# ---------------------------------------------------------------- helpers
download() { # url dest
  local url="$1" dest="$2"
  if [ -s "$dest" ]; then ok "缓存命中：$(basename "$dest")"; return 0; fi
  info "下载：$url"
  curl -fL --retry 3 --retry-delay 5 -o "$dest.part" "$url"
  mv "$dest.part" "$dest"
}

gh_latest_asset() { # repo pattern dest
  local repo="$1" pattern="$2" dest="$3"
  if [ -s "$dest" ]; then ok "缓存命中：$(basename "$dest")"; return 0; fi
  local url
  url="$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
        | python3 -c 'import json,sys,re
d=json.load(sys.stdin)
pat=sys.argv[1]
for a in d.get("assets",[]):
    if re.search(pat, a["name"]):
        print(a["browser_download_url"]); break
' "$pattern")" || true
  [ -n "$url" ] || die "在 $repo 最新 release 里找不到匹配 $pattern 的资产"
  download "$url" "$dest"
}

repack_for_ubuntu() { # deb -> relaxed copy (for xiaomi-sheng-fingerprint)
  local deb="$1" out="${2:-$1}"
  local tmp
  tmp="$(mktemp -d)"
  dpkg-deb -R "$deb" "$tmp"
  sed -i \
    -e 's/fprintd (>= 1\.94\.5)/fprintd/' \
    -e 's/libgusb2 (>= 0\.4\.9) | libgusb2a (>= 0\.4\.9)/libgusb2/' \
    "$tmp/DEBIAN/control"
  dpkg-deb --root-owner-group -b "$tmp" "$out" >/dev/null
  rm -rf "$tmp"
  ok "已放宽依赖：$(basename "$out")（Ubuntu 24.04 的 fprintd/libgusb 版本较旧）"
}

# ---------------------------------------------------------------- package builds
build_fastrpc() {
  local out="$DEB_DIR/fastrpc_1.0.2-1_arm64.deb"
  [ -s "$out" ] && { ok "已存在：$(basename "$out")"; return 0; }
  ( set -e
    download "https://github.com/qualcomm/fastrpc/archive/refs/tags/v1.0.2.zip" "$DL_DIR/fastrpc-v1.0.2.zip"
    rm -rf "$SRC_DIR/fastrpc" && mkdir -p "$SRC_DIR/fastrpc"
    unzip -q "$DL_DIR/fastrpc-v1.0.2.zip" -d "$SRC_DIR/fastrpc"
    cd "$SRC_DIR/fastrpc/fastrpc-1.0.2"
    autoreconf -is >/dev/null
    ./configure --prefix=/usr >/dev/null
    make -j"$JOBS" >/dev/null
    mkdir -p stage
    make DESTDIR="$PWD/stage" install >/dev/null
    mkdir -p stage/usr/lib/systemd/system
    cp "$ROOT/patches/adsprpcd-sensorspd.service" stage/usr/lib/systemd/system/
    rm -rf deb && mkdir -p deb/DEBIAN
    cp -r stage/usr deb/
    cat > deb/DEBIAN/control <<'EOF'
Package: fastrpc
Version: 1.0.2-1
Section: libs
Priority: optional
Architecture: arm64
Maintainer: local-build <local-build@localhost>
Depends: libyaml-0-2, systemd
Description: Qualcomm FastRPC userspace library
 FastRPC implementation for Qualcomm DSP communication.
EOF
    find deb -type d -exec chmod 755 {} \;
    find deb -type f -exec chmod 644 {} \;
    chmod 755 deb/usr/bin/adsprpcd
    dpkg-deb --root-owner-group --build deb "$out" >/dev/null
  ) && ok "已编译：$(basename "$out")"
}

build_libssc() {
  local out="$DEB_DIR/libssc_0.3.0-1_arm64.deb"
  [ -s "$out" ] && { ok "已存在：$(basename "$out")"; return 0; }
  ( set -e
    rm -rf "$SRC_DIR/libssc" && mkdir -p "$SRC_DIR/libssc/src"
    local okclone=0
    for attempt in 1 2 3; do
      if git clone --depth 1 https://codeberg.org/DylanVanAssche/libssc.git "$SRC_DIR/libssc/src" 2>/dev/null; then okclone=1; break; fi
      warn "codeberg 克隆失败，第 $attempt 次；15 秒后重试"
      sleep 15
    done
    if [ "$okclone" != 1 ]; then
      warn "改用 Debian 源码包 libssc 0.3.0"
      download "https://deb.debian.org/debian/pool/main/libs/libssc/libssc_0.3.0.orig.tar.gz" "$DL_DIR/libssc_0.3.0.orig.tar.gz"
      tar -xzf "$DL_DIR/libssc_0.3.0.orig.tar.gz" -C "$SRC_DIR/libssc/src" --strip-components=1
    fi
    cd "$SRC_DIR/libssc/src"
    cp "$ROOT/patches/wait_for_qmi_service.patch" . 2>/dev/null || true
    patch -Np1 --batch < wait_for_qmi_service.patch >/dev/null 2>&1 || true
    meson setup build --prefix=/usr >/dev/null
    meson compile -C build >/dev/null
    DESTDIR="$PWD/stage" meson install -C build >/dev/null
    rm -rf "$SRC_DIR/libssc/deb" && mkdir -p "$SRC_DIR/libssc/deb/DEBIAN"
    cp -r stage/usr "$SRC_DIR/libssc/deb/"
    cat > "$SRC_DIR/libssc/deb/DEBIAN/control" <<'EOF'
Package: libssc
Version: 0.3.0-1
Section: libs
Priority: optional
Architecture: arm64
Maintainer: local-build <local-build@localhost>
Depends: libglib2.0-0, libprotobuf-c1, libqmi-glib5
Description: Library to expose Qualcomm Sensor Core sensors
 libssc userspace library for Qualcomm SSC.
EOF
    chmod 755 "$SRC_DIR/libssc/deb/usr/bin/ssccli"
    dpkg-deb --root-owner-group --build "$SRC_DIR/libssc/deb" "$out" >/dev/null
  ) && ok "已编译：$(basename "$out")"
}

build_iio_sensor_proxy() {
  local out="$DEB_DIR/iio-sensor-proxy_99993.9-6_arm64.deb"
  [ -s "$out" ] && { ok "已存在：$(basename "$out")"; return 0; }
  [ -s "$DEB_DIR/libssc_0.3.0-1_arm64.deb" ] || build_libssc
  ( set -e
    dpkg -i "$DEB_DIR/libssc_0.3.0-1_arm64.deb" >/dev/null || true
    ldconfig
    download "https://gitlab.freedesktop.org/hadess/iio-sensor-proxy/-/archive/3.9/iio-sensor-proxy-3.9.tar.gz" "$DL_DIR/iio-sensor-proxy-3.9.tar.gz"
    rm -rf "$SRC_DIR/iio" && mkdir -p "$SRC_DIR/iio"
    tar -xzf "$DL_DIR/iio-sensor-proxy-3.9.tar.gz" -C "$SRC_DIR/iio"
    cd "$SRC_DIR/iio/iio-sensor-proxy-3.9"
    meson setup output --prefix=/usr -Db_lto=true -Dssc-support=enabled -Dsystemdsystemunitdir=/usr/lib/systemd/system >/dev/null
    meson compile -C output >/dev/null
    DESTDIR="$PWD/stage" meson install --no-rebuild -C output >/dev/null
    rm -rf deb && mkdir -p deb/DEBIAN
    cp -r stage/usr deb/
    cat > deb/DEBIAN/control <<'EOF'
Package: iio-sensor-proxy
Version: 99993.9-6
Section: misc
Priority: optional
Architecture: arm64
Maintainer: local-build <local-build@localhost>
Depends: dbus, libglib2.0-0, libgudev-1.0-0, libpolkit-gobject-1-0
Description: IIO sensors to D-Bus proxy (SSC patched)
 iio-sensor-proxy with Qualcomm SSC support patches.
EOF
    find deb -type d -exec chmod 755 {} \;
    find deb -type f -exec chmod 644 {} \;
    chmod 755 deb/usr/bin/monitor-sensor deb/usr/libexec/iio-sensor-proxy 2>/dev/null || true
    dpkg-deb --root-owner-group --build deb "$out" >/dev/null
  ) && ok "已编译：$(basename "$out")"
}

build_sheng_sensors() {
  local out="$DEB_DIR/sheng-sensors_20240917-1_arm64.deb"
  [ -s "$out" ] && { ok "已存在：$(basename "$out")"; return 0; }
  ( set -e
    rm -rf "$SRC_DIR/sheng-sensors" && mkdir -p "$SRC_DIR/sheng-sensors/deb/DEBIAN"
    cp -r "$ROOT/sheng-sensors-files/usr" "$SRC_DIR/sheng-sensors/deb/"
    cat > "$SRC_DIR/sheng-sensors/deb/DEBIAN/control" <<'EOF'
Package: sheng-sensors
Version: 20240917-1
Section: misc
Priority: optional
Architecture: arm64
Maintainer: local-build <local-build@localhost>
Description: Sensor files for Xiaomi Mi Pad 6s Pro
 Proprietary sensor configuration files.
EOF
    cat > "$SRC_DIR/sheng-sensors/deb/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if command -v udevadm >/dev/null 2>&1; then
  udevadm control --reload || true
  if [ -e /sys/devices/virtual/misc/fastrpc-adsp ]; then
    udevadm trigger /sys/devices/virtual/misc/fastrpc-adsp || true
  fi
fi
if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload || true
  if [ -d /run/systemd/system ]; then
    systemctl try-restart iio-sensor-proxy.service || true
  fi
fi
exit 0
EOF
    chmod 755 "$SRC_DIR/sheng-sensors/deb/DEBIAN/postinst"
    find "$SRC_DIR/sheng-sensors/deb" -type d -exec chmod 755 {} \;
    find "$SRC_DIR/sheng-sensors/deb" -type f -exec chmod 644 {} \;
    chmod 755 "$SRC_DIR/sheng-sensors/deb/DEBIAN/postinst"
    dpkg-deb --root-owner-group --build "$SRC_DIR/sheng-sensors/deb" "$out" >/dev/null
  ) && ok "已打包：$(basename "$out")"
}

build_sheng_devauth() {
  local out="$DEB_DIR/sheng-devauth_1.0_arm64.deb"
  [ -s "$out" ] && { ok "已存在：$(basename "$out")"; return 0; }
  ( set -e
    rm -rf "$SRC_DIR/sheng-devauth" && mkdir -p "$SRC_DIR/sheng-devauth"
    for attempt in 1 2 3; do
      git clone --depth 1 https://github.com/ianchb/sheng_devauth.git "$SRC_DIR/sheng-devauth/source" 2>/dev/null && break
      warn "devauth 克隆失败，第 $attempt 次；10 秒后重试"; sleep 10
    done
    [ -d "$SRC_DIR/sheng-devauth/source" ] || die "sheng_devauth 源码拉取失败"
    cd "$SRC_DIR/sheng-devauth/source" && make -j"$JOBS" >/dev/null
    cd "$SRC_DIR/sheng-devauth"
    rm -rf pkg && cp -r "$ROOT/sheng-devauth" pkg
    mkdir -p pkg/usr/bin
    cp source/xiaomi_devauth pkg/usr/bin/
    cat > pkg/DEBIAN/postinst <<'EOF'
#!/bin/sh
set -e
if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload || true
  systemctl enable sheng-devauth.service || true
  systemctl start sheng-devauth.service || true
fi
exit 0
EOF
    chmod 755 pkg/DEBIAN/postinst pkg/usr/bin/xiaomi_devauth
    dpkg-deb --root-owner-group --build pkg "$out" >/dev/null
  ) && ok "已打包：$(basename "$out")"
}

build_alsa() {
  local out="$DEB_DIR/alsa-xiaomi-sheng.deb"
  [ -s "$out" ] && { ok "已存在：$(basename "$out")"; return 0; }
  ( set -e
    rm -rf "$SRC_DIR/alsa" && mkdir -p "$SRC_DIR/alsa"
    cp -r "$ROOT/alsa-xiaomi-sheng/." "$SRC_DIR/alsa/"
    dpkg-deb --root-owner-group --build "$SRC_DIR/alsa" "$out" >/dev/null
  ) && ok "已打包：$(basename "$out")"
}

build_firmware() {
  local out="$DEB_DIR/firmware-xiaomi-sheng.deb"
  [ -s "$out" ] && { ok "已存在：$(basename "$out")"; return 0; }
  ( set -e
    rm -rf "$SRC_DIR/firmware" && mkdir -p "$SRC_DIR/firmware/pkg"
    for attempt in 1 2 3; do
      git clone --depth 1 https://github.com/ianchb/sheng-firmware.git "$SRC_DIR/firmware/src" 2>/dev/null && break
      warn "firmware 克隆失败，第 $attempt 次"; sleep 10
    done
    [ -d "$SRC_DIR/firmware/src" ] || die "固件仓库拉取失败"
    cp -r "$ROOT/firmware-xiaomi-sheng/." "$SRC_DIR/firmware/pkg/"
    mkdir -p "$SRC_DIR/firmware/pkg/usr/lib/firmware"
    cp -r "$SRC_DIR/firmware/src/." "$SRC_DIR/firmware/pkg/usr/lib/firmware/"
    rm -rf "$SRC_DIR/firmware/pkg/usr/lib/firmware/.git"
    dpkg-deb --root-owner-group --build "$SRC_DIR/firmware/pkg" "$out" >/dev/null
  ) && ok "已打包：$(basename "$out")"
}

fetch_prebuilt_debs() {
  # 内核包（推荐镜像/目标根文件系统时使用）
  if [ "$WITH_KERNEL" = "1" ]; then
    gh_latest_asset ianchb/sm8550-mainline 'linux-xiaomi-sheng.*\.deb$' \
      "$DEB_DIR/linux-xiaomi-sheng.deb"
  else
    info "跳过内核包（WITH_KERNEL=1 可启用）"
  fi
  # 各种小米配件包
  gh_latest_asset ianchb/xiaomi-mipps-auth '\.deb$' "$DEB_DIR/xiaomi-mipps-auth.deb"
  gh_latest_asset ianchb/xiaomi-charger-mode '\.deb$' "$DEB_DIR/xiaomi-charger-mode.deb"
  gh_latest_asset ianchb/xiaomi-sheng-thp '\.deb$' "$DEB_DIR/xiaomi-sheng-thp.deb"
  gh_latest_asset ianchb/xiaomi-pen-status '\.deb$' "$DEB_DIR/xiaomi-pen-status.deb"
  gh_latest_asset ianchb/xiaomi-sheng-fingerprint '\.deb$' "$DEB_DIR/xiaomi-sheng-fingerprint.deb"
  gh_latest_asset ianchb/xiaomi-sheng-keyboard-helper '\.deb$' "$DEB_DIR/xiaomi-sheng-keyboard-helper.deb"
}

# ---------------------------------------------------------------- commands
cmd_check() {
  need_root
  check_env
  info "检查可用命令"
  for c in git curl python3 dpkg-deb gcc make meson ninja; do
    command -v "$c" >/dev/null || warn "缺少命令：$c（先跑 install-tools：./scripts/local-build.sh debs 会自动装）"
  done
  ok "环境检查完成"
}

cmd_debs() {
  need_root
  check_env
  install_tools
  fetch_prebuilt_debs
  build_fastrpc
  build_libssc
  build_iio_sensor_proxy
  build_sheng_sensors
  build_sheng_devauth
  build_alsa
  build_firmware
  # Ubuntu 上放宽指纹包依赖
  if [ -s "$DEB_DIR/xiaomi-sheng-fingerprint.deb" ]; then
    local deb="$DEB_DIR/xiaomi-sheng-fingerprint.deb"
    if ! dpkg-deb -f "$deb" Depends | grep -q 'fprintd (>= 1.94.5)'; then
      ok "指纹包依赖已放宽"
    else
      repack_for_ubuntu "$deb"
    fi
  fi
  ok "全部产物在：$DEB_DIR"
  ls -lh "$DEB_DIR"
}

cmd_install() {
  need_root
  [ -d "$DEB_DIR" ] || die "还没有产物，先跑：./scripts/local-build.sh debs"
  check_env
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  local debs=()
  for d in "$DEB_DIR"/*.deb; do
    [ -e "$d" ] || continue
    case "$(basename "$d")" in
      linux-xiaomi-sheng.deb) [ "$WITH_KERNEL" = "1" ] && debs+=("$d") || warn "跳过 $d（WITH_KERNEL=1 可装）" ;;
      firmware-xiaomi-sheng.deb) [ "$WITH_FIRMWARE" = "1" ] && debs+=("$d") || warn "跳过 $d（WITH_FIRMWARE=1 可装）" ;;
      *) debs+=("$d") ;;
    esac
  done
  [ "${#debs[@]}" -gt 0 ] || die "没有可安装的 .deb"
  info "安装 ${#debs[@]} 个包"
  apt-get install -y -f "${debs[@]}" || {
    warn "批量安装失败，逐个安装（两轮，处理 pen-status 依赖 thp 的顺序）"
    for pass in 1 2; do
      local failed=()
      for d in "${debs[@]}"; do
        apt-get install -y "$d" >/dev/null 2>&1 || failed+=("$d")
      done
      [ "${#failed[@]}" -eq 0 ] && break
      if [ "$pass" = "2" ]; then
        for d in "${failed[@]}"; do warn "装不上：$(basename "$d")"; done
      fi
      debs=("${failed[@]}")
      [ "${#debs[@]}" -gt 0 ] || break
    done
  }
  apt-get -f install -y >/dev/null 2>&1 || true
  echo
  info "安装结果："
  for p in xiaomi-sheng-fingerprint xiaomi-pen-status xiaomi-sheng-thp iio-sensor-proxy libssc fastrpc sheng-sensors sheng-devauth alsa-xiaomi-sheng xiaomi-mipps-auth xiaomi-charger-mode xiaomi-sheng-keyboard-helper; do
    if dpkg -s "$p" >/dev/null 2>&1; then ok "$p $(dpkg-query -W -f='${Version}' "$p")"; else warn "$p 未安装"; fi
  done
  echo
  info "提示：容器里没有 sheng 硬件/内核模块，指纹等外设功能要刷到平板才能实测。"
}

cmd_clean() {
  need_root
  check_env
  rm -rf "$CACHE_DIR" "$OUT_DIR"
  ok "已清理 $CACHE_DIR 和 $OUT_DIR"
}

case "${1:-}" in
  check)   cmd_check ;;
  debs)    cmd_debs ;;
  install) cmd_install ;;
  clean)   cmd_clean ;;
  *)
    cat <<EOF
用法：$(basename "$0") <check|debs|install|clean>

  check    检查环境（架构 / 发行版 / 依赖 / 网络）
  debs     下载 + 编译全部设备包（缓存 local-cache/，成品 local-out/debs/）
  install  把 local-out/debs/ 里的包装进当前系统（容器测试用）
  clean    清空 local-cache/ 与 local-out/

环境变量：CACHE_DIR / OUT_DIR / WITH_KERNEL=1 / WITH_FIRMWARE=1
EOF
    exit 1 ;;
esac
