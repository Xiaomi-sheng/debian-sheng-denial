# Denial 集成指南：Debian · Xiaomi Pad 6S Pro（sheng）

简体中文 | [English](denial-integration.md)

> **文档状态 v2（2026-11-26）**：本仓库是从 [`ianchb/debian-sheng`](https://github.com/ianchb/debian-sheng) fork 出来的 Denial 集成分支。`.github/workflows/rootfs.yml` 与 `rootfs-lite.yml` **已内置 `Denial` 桌面选项**（路线 B 已落地）；路线 A（刷好后手动装）仍可用于旧镜像或单机验证。

---

## 0. 先看结论

| 项 | 结论 |
| --- | --- |
| 设备 | Xiaomi Pad 6S Pro 12.4（sheng / SM8550） |
| 系统 | Debian 13 `trixie`（arm64），mainline 内核 `·sm8550-mainline`（`sheng-7.3.4` 分支） |
| 桌面 | Denial 0.6.10：Wayland 合成器 + Flutter 桌面外壳 |
| Denial 二进制 | 官方已发布 **arm64 `.deb`**（`denial`、`denial-flutter-engine`、可选 `denial-plugin-manager`），trixie APT 源可直接装 |
| 构建方式 | **只用 GitHub Actions 线上构建**（`ubuntu-24.04-arm` 原生 arm64 runner），本机不编译 |
| 最大坑 | 上游 `docs/DISTRIBUTION_SUPPORT.md` 的表格仍写「ARM64 无二进制」，已滞后；以 [`INSTALL.md`](https://github.com/denialwm/denial/blob/main/docs/INSTALL.md)、发布页和 apt 源为准 |

> 本仓库的构建工作流也支持 **Ubuntu 24.04 及更新版本**（`Distribution = Ubuntu`，arm64 走 `ports.ubuntu.com`）。Denial 上游只在 Debian 13 与 Ubuntu 24.04 做过验证；其他 Ubuntu 版本用 `noble` 包尽力支持，本文其余内容以 Debian 13 为准。

---

## 1. 前置条件

| 条件 | 要求 | 本仓库现状 |
| --- | --- | --- |
| Bootloader / 刷机 | 已解锁，装好 TWRP，电脑有 `fastboot` | 见 README「Flashing to Your Device」 |
| 内核图形栈 | 原子 KMS + GBM/EGL + GLES 3.0 以上（Denial 硬性要求） | `sm8550.config`：`CONFIG_DRM_MSM=y`、`CONFIG_DRM_SCHED=y`、`CONFIG_UDMABUF=y`、`CONFIG_DMABUF_HEAPS=y` 已开 |
| GPU 用户态 | Mesa freedreno 驱动（SM8550 / Adreno 740） | Debian trixie 自带 Mesa 25.0.7 |
| 设备固件 | GPU / DSP / Wi-Fi 等 firmware | 由 `firmware-xiaomi-sheng` 包在构建时装入 |
| glibc | Denial 包要求 `libc6 >= 2.39` | trixie 为 glibc 2.41，满足 |
| Debian 版本 | Denial 已验证 **Debian 13 (trixie)**；forky/sid 仅尽力支持、未验证 | 构建时选 `trixie` |
| 会话环境 | systemd + logind 兼容 seat + 用户 D-Bus | Debian 默认具备 |
| 面板 | 12.4 英寸 3048×2032；首次启动在 Denial 设置里调缩放 | — |

> 结论：sheng 的 mainline 内核与 trixie 用户态已经满足 Denial 的运行条件，不需要像 Android GKI 那样改内核配置或打 kABI 补丁。

---

## 2. 构建链：现在这套仓库是怎么出货的

`Build RootFS` 工作流在 **GitHub Actions** 上跑，整条链都在线上：

```
build-kernel ─┐
build-fastrpc ├─→ build-rootfs ─→ rootfs-<suite>-<desktop>-<label>.img
build-libssc  │                   boot-<suite>-<desktop>-<label>.img
build-iio-sensor-proxy │
build-sheng-sensors    │
build-sheng-devauth ───┘
```

`build-rootfs` 的关键步骤（`.github/workflows/rootfs.yml`）：

1. `debootstrap --arch=arm64 --components=main,contrib,non-free-firmware trixie http://deb.debian.org/debian/`；
2. bind `/dev`、`/proc`、`/sys`，装基础包（systemd、NetworkManager、dbus 等）；
3. 装入 6 个构建 job 的产物和仓库内打包的 `.deb`（内核、firmware、alsa、传感器、devauth、充电、触控笔、指纹等）；
4. 按 `desktop` 输入装 GNOME / KDE / 什么都不装（`server`）；
5. 建用户、设密码、locale、hostname；
6. 配显示管理器（GDM / SDDM）与自动登录；
7. 写 `fstab`、Wi-Fi MAC，清 apt 缓存，卸载；
8. 生成 10 GiB ext4 `rootfs.img`（固定 UUID）和 `boot.img`（`custom_build` 内核时才生成）；
9. 上传 artifact：`rootfs-…` / `boot-…`，保留 14 天。

**为什么坚持线上构建**：debootstrap 和 arm64 内核编译在手机 / proot 里既慢又不可复现；GitHub 的 arm64 runner 原生跑 arm64 chroot，产物出来就能直接下载、刷入。

---

## 3. 两条落地路线

| 路线 | 做什么 | 适用场景 |
| --- | --- | --- |
| **A. 刷机后手动安装** | 先刷一套 `server`/`GNOME` 镜像，开机联网后 `apt install denial` | 最快验证 GPU/DRM/会话是否正常；只改一个系统 |
| **B. 线上构建时集成（推荐）** | 在 `rootfs.yml` 加 `Denial` 桌面选项和安装/会话步骤，Actions 直接产出带 Denial 的镜像 | 想「一次构建、直接出货」，符合线上构建要求 |

> 不建议在本机或容器里自己 `debootstrap`（见第 7 节）。

---

## 4. 路线 A：刷好系统后手动安装

### 4.1 确认系统

```sh
. /etc/os-release && echo "$PRETTY_NAME"
uname -r                  # 应为 mainline 内核（如 6.x / 7.x）
ls /dev/dri               # 应看到 card0 和 renderD128
```

### 4.2 加 Denial 的签名 APT 源

官方推荐脚本（会显示并固定指纹 `AE4108FA5E91E26BE0EE331E0F5B3AD16E023091`，只配置源、不装包）：

```sh
curl -fsSL https://install.denialwm.org | sh
```

不想执行远程脚本时，手工等价配置：

```sh
sudo install -d -m 0755 /etc/apt/keyrings
sudo curl -fsSL https://packages.denialwm.org/denial-repo-key.asc \
  -o /etc/apt/keyrings/denial.asc
sudo tee /etc/apt/sources.list.d/denial.list >/dev/null <<'EOF'
deb [signed-by=/etc/apt/keyrings/denial.asc] https://packages.denialwm.org/apt trixie main
EOF
sudo apt update
```

### 4.3 安装

```sh
sudo apt install denial          # 会自动带上 denial-flutter-engine
sudo apt install denial-plugin-manager   # 可选：插件商店/开发
```

装完后应存在：

- `/usr/share/wayland-sessions/denial.desktop`（会话名 **Denial**）
- `/usr/bin/denial-session`（受支持的会话入口，不要直接跑 `deniald`）
- `/etc/denial/session.conf`、`/etc/denial/outputs.conf`（conffile，可预置默认值）
- `/usr/lib/denial/flutter/`（Flutter 引擎与 bundle）

### 4.4 配显示管理器 + 自动登录

三种都可行，按「改动最小」选一个：

**SDDM（推荐，和本仓库现有 KDE 自动登录写法一致）**

```sh
sudo apt install sddm
sudo mkdir -p /etc/sddm.conf.d
sudo tee /etc/sddm.conf.d/10-denial.conf >/dev/null <<'EOF'
[Autologin]
User=username
Session=denial
EOF
sudo systemctl enable sddm
sudo systemctl set-default graphical.target
```

**GDM（上游 Debian 13 验证时用的就是 GDM 48）**

```sh
sudo apt install gdm3
sudo tee /etc/gdm3/daemon.conf >/dev/null <<'EOF'
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=username
EOF
sudo mkdir -p /var/lib/AccountsService/users
sudo tee /var/lib/AccountsService/users/username >/dev/null <<'EOF'
[User]
Session=denial
XSession=denial
SystemAccount=false
EOF
sudo systemctl enable gdm3
sudo systemctl set-default graphical.target
```

**greetd（最轻量，适合只跑 Denial 的平板）**：`/etc/greetd/config.toml` 里把 `[initial_session]` 设为 `command = "denial-session"`、`user = "username"`，然后 `systemctl enable greetd`。

### 4.5 用户组

```sh
sudo usermod -aG video,render,input,audio,plugdev username
```

> `denial-session` 的退出码语义对 SDDM 有专门处理（会话失败返回 2 以重启 greeter），SDDM 路径是上游代码明确支持的。

### 4.6 重启并按下节验证

---

## 5. 路线 B：在线上构建里集成 Denial（已内置）

仓库的 `.github/workflows/rootfs.yml` 与 `rootfs-lite.yml` 已加入以下内容（2026-11-26）；本节保留为实现说明，方便升级或回滚。

### 5.1 `workflow_dispatch.inputs.desktop` 增加选项

```yaml
      desktop:
        description: 'Desktop Environment (server = no DE)'
        type: choice
        options:
          - GNOME
          - KDE Plasma
          - Denial          # 新增
          - server
        default: 'KDE Plasma'
```

### 5.2 安装与会话步骤（已在 `# Desktop Environment` 段落地）

```yaml
      - name: "Install Denial"
        if: ${{ inputs.desktop == 'Denial' }}
        run: |
          sudo chroot "$ROOTFS_MOUNT" bash -c '
            set -euo pipefail
            install -d -m 0755 /etc/apt/keyrings
            curl -fsSL https://packages.denialwm.org/denial-repo-key.asc \
              -o /etc/apt/keyrings/denial.asc
            chmod 0644 /etc/apt/keyrings/denial.asc
            echo "deb [signed-by=/etc/apt/keyrings/denial.asc] https://packages.denialwm.org/apt trixie main" \
              > /etc/apt/sources.list.d/denial.list
            apt-get update
            apt-get install -y denial
          '
          echo "✓ Denial installed"

      - name: "Configure Denial Session"
        if: ${{ inputs.desktop == 'Denial' }}
        run: |
          sudo chroot "$ROOTFS_MOUNT" apt-get install -y sddm
          sudo chroot "$ROOTFS_MOUNT" usermod -aG video,render,input,audio,plugdev \
            "${{ inputs.username }}"
          if [[ "${{ inputs.autologin }}" == "true" ]]; then
            sudo mkdir -p "$ROOTFS_MOUNT/etc/sddm.conf.d"
            printf '[Autologin]\nUser=%s\nSession=denial\n' "${{ inputs.username }}" | \
              sudo tee "$ROOTFS_MOUNT/etc/sddm.conf.d/10-denial.conf" >/dev/null
          fi
          sudo chroot "$ROOTFS_MOUNT" systemctl enable sddm
          sudo chroot "$ROOTFS_MOUNT" systemctl set-default graphical.target
          echo "✓ Denial session configured (SDDM, Session=denial)"
```

> 注意：Debian forky（`Debian Version = 14`）时 Denial 源仍指向 `trixie` suite（上游说明为尽力支持）。denial 包 `Depends` 里已包含 `libegl1/libgbm1/libgles2/libwayland-client0/libseat1/xwayland` 等，`apt` 会自动补齐。
>
> 如果改用 GDM，别走 `sddm` 分支：装 `gdm3`，按 4.4 节写 `/etc/gdm3/daemon.conf` 和 `/var/lib/AccountsService/users/<用户>`；`quiet_boot` 逻辑（`desktop != 'server'`）对 Denial 同样生效，Plymouth 会正常安装。

### 5.3 触发线上构建

Actions → **Build RootFS** → Run workflow，建议参数：

| 参数 | 建议值 | 说明 |
| --- | --- | --- |
| Distribution | `Debian`（或 `Ubuntu`） | Denial 上游验证 Debian 13 / Ubuntu 24.04 |
| Debian Version | `13` | Denial 已验证；`14`（forky）未验证 |
| Desktop Environment | `Denial` | 已内置；旧镜像仍可用 `server` + 路线 A |
| Autologin | `true` | 平板直进 Denial |
| Username / Hostname | 自定 | 用户名会写进 autologin |
| Password | 自定或留空 | 留空时用仓库 secret `ROOTFS_PASSWORD`，再退默认 `password`；公开仓库优先用 secret |
| Boot mode | `dual (linux)` | 保留原系统；`single` 会清空 userdata |
| Quiet boot | `true` | Plymouth 静默开机 |
| Kernel Source | `prebuilt` | 最快；`custom_build` 会先编内核，耗时更长 |

产物命名：`rootfs-trixie-Denial-linux.img`、`boot-trixie-Denial-linux.img`（保留 14 天）。

### 5.4 刷入（dual boot / slot B 示例）

```sh
fastboot erase dtbo_b
fastboot flash boot_b boot-trixie-Denial-linux.img
fastboot flash linux rootfs-trixie-Denial-linux.img
fastboot reboot
```

---

## 6. 验证清单

刷完开机后按顺序查（能定位 90% 的问题）：

| # | 检查项 | 命令 | 期望 |
| --- | --- | --- | --- |
| 1 | 内核图形栈 | `ls /dev/dri && dmesg \| grep -i 'msm\|adreno'` | `card0`、`renderD128`；无 -ENODEV |
| 2 | 包完整性 | `dpkg -l denial denial-flutter-engine` | 两包均为 `ii` |
| 3 | 会话入口 | `ls /usr/share/wayland-sessions/` | 有 `denial.desktop` |
| 4 | 会话预检 | `denial-session --check`（用普通用户在 tty 跑） | 通过，能解析 DRM 设备 |
| 5 | 合成器进程 | `ps -C deniald -o pid,cmd` | 有 `/usr/bin/deniald` |
| 6 | 会话类型 | 会话内终端 `echo $XDG_SESSION_TYPE` | `wayland` |
| 7 | 显示管理器 | `systemctl status sddm`（或 `gdm3`） | active (running) |
| 8 | 日志 | `journalctl -b -u sddm`、`journalctl --user -b` | 无 DRM/EGL 致命错误 |
| 9 | GPU 渲染 | `sudo apt install mesa-utils vulkan-tools` 后 `glxinfo -B` | renderer 为 freedreno/Adreno，非 llvmpipe |
| 10 | X11 兼容 | 运行任意 X11 程序（`xeyes`） | 出现在 Xwayland 窗口 |
| 11 | 音频/网络 | 播放声音、连 Wi-Fi | 正常 |
| 12 | 缩放入手 | Denial 设置 → 显示/外观 | 12.4" 面板比例合适 |

> 备用诊断：`denial-session --print-output-config` 打印输出配置；`/etc/denial/session.conf` 里的 `DENIAL_DRM_DEVICE`、`DENIAL_NO_VULKAN=1`、`LIBGL_ALWAYS_SOFTWARE=1` 可用于排查。

---

## 7. 不推荐：本机或容器里自行 debootstrap

- 手机 / proot 环境磁盘与内存都不够稳，`debootstrap trixie` 后还要 chroot 装 1GB+ 桌面；
- 本机不是 arm64 时得跨架构模拟，速度慢且容易掩盖问题；
- CI 已经有 `ubuntu-24.04-arm` runner，本机重建等于重复造轮子，还失去可复现性。

---

## 8. 已知问题与限制

1. **上游文档滞后**：`docs/DISTRIBUTION_SUPPORT.md` 仍写「first-party 只发 x86-64」；实际发布页和 APT 源自 0.6.10 起已含 `arm64` 的 `denial`、`denial-flutter-engine`、`denial-plugin-manager`。
2. **forky 未验证**：Denial 对 Debian Forky/Sid 是 best-effort，建议 `trixie`。
3. **KDE 残留**：上游明确警告「最初用 KDE 装的系统不保证兼容」——KDE 的服务/桌面集成会干扰 Denial 会话。用 `server` 或 GNOME 基础构建更稳；已经装过 KDE 的 rootfs 建议重刷干净镜像。
4. **亮度**：Denial 的 DDC/CI 亮度只对外接显示器；内屏亮度控制参见上游 [`KNOWN_ISSUES.md`](https://github.com/denialwm/denial/blob/main/docs/KNOWN_ISSUES.md)。
5. **glibc 基线**：Denial 包要求 `>= 2.39`，Debian 12 及更早不可用；trixie/forky 满足。
6. **公测阶段**：Denial 0.6.x 仍在快速迭代，升级用 `sudo apt upgrade` 即可，但注意会话配置的兼容性。
7. **镜像体积**：rootfs 固定 10 GiB（稀疏），Denial 本身约 +100 MB；artifact 较大，下载慢时用 `gh run download` 单独取。
8. **无 systemd 用户管理器**时 XDG autostart 不生效——Debian（systemd）不受影响。

---

## 9. 回滚

- **刷机层面**：刷入前备份原来的 `boot_b`/`linux` 分区与 `dtbo_b`；出问题用 `fastboot flash boot_b <原boot>.img`、`fastboot flash linux <原rootfs>.img`、`fastboot flash dtbo_b <原dtbo>.img` 恢复。
- **系统内回滚**：`sudo apt remove denial`（会话与源保留可再装）；把 `/etc/sddm.conf.d/10-denial.conf` 改回原来的 `Session=plasma` 或删掉，切回原桌面。
- **CI 层面**：改动只在 `rootfs.yml` 的一个分支提交里，回滚 = revert 该提交后重新跑 Actions。

---

## 10. 参考

- Denial 仓库：<https://github.com/denialwm/denial>
- Denial 安装：<https://github.com/denialwm/denial/blob/main/docs/INSTALL.md>
- 发行版支持：<https://github.com/denialwm/denial/blob/main/docs/DISTRIBUTION_SUPPORT.md>
- Debian 13 验证记录：<https://github.com/denialwm/denial/blob/main/packaging/debian/VALIDATION.md>
- Denial 手册（开发）：<https://manual.denialwm.org/zh-cn/docs/development/> ・ <https://manual.denialwm.org/docs/development/>
- Denial 包仓库：<https://packages.denialwm.org/>（APT：`https://packages.denialwm.org/apt`，suite `trixie`）
- 本仓库上游：<https://github.com/ianchb/debian-sheng>
- 内核：<https://github.com/ianchb/sm8550-mainline>（`sheng-7.3.4`）
- 本 fork：<https://github.com/Xiaomi-sheng/debian-sheng-denial>

---

[![](https://img.shields.io/badge/powered_by-dsh-4D6BFE?style=flat-square&logo=deepseek&logoColor=white)](https://github.com/deepseek-ai/deepseek-harness)
