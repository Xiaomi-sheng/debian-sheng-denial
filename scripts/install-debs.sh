#!/usr/bin/env bash
# ============================================================================
# 一键安装 sheng 设备二进制包（预编译好的 .deb，不需要编译）
# One-command installer for the prebuilt sheng device packages (no build).
#
# 用法（Ubuntu 24.04 arm64 容器 / 系统里，root 运行）：
#   curl -fsSL https://raw.githubusercontent.com/Xiaomi-sheng/debian-sheng-denial/master/scripts/install-debs.sh | bash
#   或者 git clone 后：./scripts/install-debs.sh
#
# 参数：
#   --with-firmware   连固件包一起装（会替换 linux-firmware，准备刷机树时用）
#   --with-kernel     连内核包一起装（从 ianchb/sm8550-mainline 的 release 下载）
#   --help            显示帮助
#
# 包来源：本仓库 GitHub Release “debs-latest” 里的 sheng-debs.tar.gz
# 流程：下载 → 解包 → （Ubuntu）放宽指纹包依赖 → apt 安装 → 校验
# ============================================================================
set -euo pipefail

REPO="${REPO:-Xiaomi-sheng/debian-sheng-denial}"
TAG="${TAG:-debs-latest}"
ASSET="${ASSET:-sheng-debs.tar.gz}"
WITH_FIRMWARE=0
WITH_KERNEL=0

for arg in "$@"; do
  case "$arg" in
    --with-firmware) WITH_FIRMWARE=1 ;;
    --with-kernel)   WITH_KERNEL=1 ;;
    -h|--help)       sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "未知参数：$arg（--help 查看用法）" >&2; exit 1 ;;
  esac
done

info() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -m)" = "aarch64" ] || die "需要 arm64 环境（当前 $(uname -m)）"
[ "$(id -u)" = "0" ] || die "需要 root 运行"
command -v curl >/dev/null || die "缺少 curl"
command -v dpkg-deb >/dev/null || die "缺少 dpkg（不是 Debian 系？）"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------- 1. 下载
info "[1/4] 获取预编译包：$TAG/$ASSET"
if [ -s "./$ASSET" ]; then
  # 网络慢时可以先用浏览器/下载工具把 sheng-debs.tar.gz 放到当前目录
  info "使用当前目录下已有的 $ASSET"
  cp "./$ASSET" "$TMP/$ASSET"
else
  curl -fL --retry 3 --retry-delay 5 \
    "https://github.com/$REPO/releases/download/$TAG/$ASSET" \
    -o "$TMP/$ASSET" || die "下载失败，检查网络（或 release 是否已发布）"
fi
tar -xzf "$TMP/$ASSET" -C "$TMP"
DEBS=("$TMP"/debs/*.deb)
[ "${#DEBS[@]}" -gt 0 ] || die "压缩包里没有 .deb"

# ---------------------------------------------------------------- 2. Ubuntu 适配
# Ubuntu 24.04 的 fprintd / libgusb 版本比 Debian 13 旧，放宽指纹包下限才能装
fp="$TMP/debs/xiaomi-sheng-fingerprint.deb"
if [ -s "$fp" ] && dpkg-deb -f "$fp" Depends 2>/dev/null | grep -q 'fprintd (>= 1.94.5)'; then
  work="$(mktemp -d)"
  dpkg-deb -R "$fp" "$work"
  sed -i \
    -e 's/fprintd (>= 1\.94\.5)/fprintd/' \
    -e 's/libgusb2 (>= 0\.4\.9) | libgusb2a (>= 0\.4\.9)/libgusb2/' \
    "$work/DEBIAN/control"
  dpkg-deb --root-owner-group -b "$work" "$fp" >/dev/null
  rm -rf "$work"
  info "已放宽指纹包依赖（Ubuntu 24.04 的 fprintd/libgusb 较旧）"
fi

# ---------------------------------------------------------------- 3. 安装
info "[2/4] 安装设备包"
LIST=()
for d in "${DEBS[@]}"; do
  case "$(basename "$d")" in
    firmware-xiaomi-sheng*)
      if [ "$WITH_FIRMWARE" = "1" ]; then LIST+=("$d"); else warn "跳过固件包（--with-firmware 可启用）"; fi ;;
    *) LIST+=("$d") ;;
  esac
done

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
if ! apt-get install -y -f "${LIST[@]}"; then
  warn "批量安装失败，逐个重试（两轮）"
  failed=("${LIST[@]}")
  for pass in 1 2; do
    next=()
    for d in "${failed[@]}"; do
      apt-get install -y "$d" >/dev/null 2>&1 || next+=("$d")
    done
    failed=("${next[@]}")
    [ "${#failed[@]}" -eq 0 ] && break
  done
  for d in "${failed[@]}"; do warn "装不上: $(basename "$d")"; done
fi
apt-get -f install -y >/dev/null 2>&1 || true

# 可选：内核包
if [ "$WITH_KERNEL" = "1" ]; then
  info "[*] 下载内核包（ianchb/sm8550-mainline 最新 release）"
  url="$(curl -fsSL "https://api.github.com/repos/ianchb/sm8550-mainline/releases/latest" \
        | python3 -c 'import json,sys,re
for a in json.load(sys.stdin).get("assets",[]):
    if re.search(r"linux-xiaomi-sheng.*\.deb$", a["name"]):
        print(a["browser_download_url"]); break')"
  [ -n "$url" ] || die "找不到内核 .deb"
  curl -fL --retry 3 "$url" -o "$TMP/linux-xiaomi-sheng.deb"
  apt-get install -y "$TMP/linux-xiaomi-sheng.deb" || warn "内核包装不上（在容器里属正常）"
fi

# ---------------------------------------------------------------- 4. 校验
info "[3/4] 校验安装结果"
for p in fastrpc libssc iio-sensor-proxy sheng-sensors sheng-devauth alsa-xiaomi-sheng \
         xiaomi-sheng-thp xiaomi-pen-status xiaomi-sheng-fingerprint \
         xiaomi-mipps-auth xiaomi-charger-mode xiaomi-sheng-keyboard-helper; do
  if dpkg -s "$p" >/dev/null 2>&1; then
    ok "$p $(dpkg-query -W -f='${Version}' "$p")"
  else
    warn "$p 未安装"
  fi
done

info "[4/4] 完成"
cat <<'EOF'
说明：
- 容器里能用这些包，但指纹/传感器等外设要刷到平板上才真正生效。
- 准备刷机树时用：./scripts/install-debs.sh --with-firmware --with-kernel
- 需要重新生成刷机镜像（rootfs.img / boot.img）时告诉我，我可以补一个打包脚本。
EOF
