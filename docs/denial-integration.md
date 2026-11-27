# Denial integration: Debian on the Xiaomi Pad 6S Pro (sheng)

[简体中文](denial-integration.zh-CN.md) | English

> **Document status v2 (2026-11-26)**: this repository is a fork of
> [`ianchb/debian-sheng`](https://github.com/ianchb/debian-sheng) that adds Denial
> integration. Builds are split into two independent workflows: `.github/workflows/build-debian.yml` (Debian menu) and `build-ubuntu.yml` (Ubuntu menu), both sharing the reusable `.github/workflows/rootfs-build.yml`; `rootfs-lite.yml` **now include
> a `Denial 桌面 / Denial Desktop` desktop option** (path B has landed); path A (install after flashing)
> still works for existing images and single-device validation.

---

## 0. Summary

| Item | Value |
| --- | --- |
| Device | Xiaomi Pad 6S Pro 12.4 (sheng / SM8550) |
| System | Debian 13 `trixie` (arm64), mainline kernel from `sm8550-mainline` (`sheng-7.3.4`) |
| Desktop | Denial 0.6.10: Wayland compositor + Flutter desktop shell |
| Denial binaries | Official **arm64 `.deb`** packages (`denial`, `denial-flutter-engine`, optional `denial-plugin-manager`) are published and installable from the signed APT repository |
| Build | **GitHub Actions only** (`ubuntu-24.04-arm` native arm64 runner); nothing is built locally |
| Main pitfall | The upstream `docs/DISTRIBUTION_SUPPORT.md` table still says ARM64 has no binaries; it is out of date. Trust [`INSTALL.md`](https://github.com/denialwm/denial/blob/main/docs/INSTALL.md), the release page and the APT repository |

> The build workflow also supports **Ubuntu 24.04 and newer** (`Distribution = Ubuntu`; arm64 packages come from `ports.ubuntu.com`). Upstream validates Denial on Debian 13 and Ubuntu 24.04 only; newer Ubuntu releases reuse the `noble` packages on a best-effort basis, and the rest of this document assumes Debian 13.

---

## 1. Prerequisites

| Requirement | Detail | Status in this repository |
| --- | --- | --- |
| Bootloader / flashing | Unlocked bootloader, TWRP, `fastboot` on a computer | See README "Flashing to Your Device" |
| Kernel graphics stack | Atomic KMS + GBM/EGL + GLES 3.0 or newer (hard requirement) | `sm8550.config` already sets `CONFIG_DRM_MSM=y`, `CONFIG_DRM_SCHED=y`, `CONFIG_UDMABUF=y`, `CONFIG_DMABUF_HEAPS=y` |
| GPU userspace | Mesa freedreno for SM8550 / Adreno 740 | Debian trixie ships Mesa 25.0.7 |
| Device firmware | GPU / DSP / Wi-Fi firmware | Installed by the `firmware-xiaomi-sheng` package during the build |
| glibc | Denial requires `libc6 >= 2.39` | trixie has glibc 2.41 |
| Debian release | Denial is validated on **Debian 13 (trixie)**; forky/sid are best-effort and unvalidated | Choose Debian version `13` |
| Session environment | systemd + a logind-compatible seat + user D-Bus | Standard on Debian |
| Panel | 12.4-inch 3048×2032; adjust scale in Denial Settings after first boot | — |

> sheng's mainline kernel and the trixie userspace already satisfy Denial. Unlike
> Android GKI, no kernel config change or kABI patch is needed here.

---

## 2. How this repository builds images today

`构建根文件系统` (Build RootFS) runs entirely on **GitHub Actions**:

```
build-kernel ─┐
build-fastrpc ├─→ build-rootfs ─→ rootfs-<suite>-<desktop>-<label>.img
build-libssc  │                   boot-<suite>-<desktop>-<label>.img
build-iio-sensor-proxy │
build-sheng-sensors    │
build-sheng-devauth ───┘
```

Key steps of `build-rootfs` (`.github/workflows/rootfs-build.yml`, called by the Debian and Ubuntu menus):

1. `debootstrap --arch=arm64 --components=main,contrib,non-free-firmware trixie http://deb.debian.org/debian/`;
2. bind `/dev`, `/proc`, `/sys` and install base packages (systemd, NetworkManager, dbus, …);
3. install the six build-job artifacts and the in-repo `.deb` packages (kernel, firmware, ALSA, sensors, devauth, charger, pen, fingerprint, …);
4. install GNOME, KDE, Denial, or nothing according to the `desktop` input;
5. create the user, password, locale, hostname;
6. configure the display manager (GDM / SDDM) and autologin;
7. write `fstab`, the Wi-Fi MAC setup, clean apt, unmount;
8. create the 10 GiB ext4 `rootfs.img` (fixed UUID) and, for `自行编译内核 / Build from source`, `boot.img`;
9. upload artifacts `rootfs-…` / `boot-…`, kept for 14 days.

**Why online builds**: debootstrap plus arm64 kernel compilation is slow and
non-reproducible on a phone or inside proot. GitHub's arm64 runner executes the
arm64 chroot natively, and its artifacts can be downloaded and flashed directly.

---

## 3. Two ways to land Denial

| Path | What it does | When to use |
| --- | --- | --- |
| **A. Install after flashing** | Flash a `无桌面 / Headless` or `GNOME 桌面 / GNOME Desktop` image, boot, `apt install denial` | Fastest way to validate GPU/DRM/session on one device |
| **B. Integrate in CI (recommended)** | Add a `Denial 桌面 / Denial Desktop` desktop option plus install/session steps to `rootfs-build.yml`; Actions ships an image with Denial | "Build once, ship it" — the online-build path |

> Building a rootfs yourself on the host or in a container is not recommended (see §7).

---

## 4. Path A: install on the running system

### 4.1 Check the system

```sh
. /etc/os-release && echo "$PRETTY_NAME"
uname -r                  # mainline kernel (e.g. 6.x / 7.x)
ls /dev/dri               # expect card0 and renderD128
```

### 4.2 Add Denial's signed APT repository

Official setup script (it prints and pins the key fingerprint
`AE4108FA5E91E26BE0EE331E0F5B3AD16E023091`; it configures the repository only and
installs no package):

```sh
curl -fsSL https://install.denialwm.org | sh
```

Manual equivalent if you prefer not to pipe a remote script:

```sh
sudo install -d -m 0755 /etc/apt/keyrings
sudo curl -fsSL https://packages.denialwm.org/denial-repo-key.asc \
  -o /etc/apt/keyrings/denial.asc
sudo tee /etc/apt/sources.list.d/denial.list >/dev/null <<'EOF'
deb [signed-by=/etc/apt/keyrings/denial.asc] https://packages.denialwm.org/apt trixie main
EOF
sudo apt update
```

### 4.3 Install

```sh
sudo apt install denial                    # pulls denial-flutter-engine
sudo apt install denial-plugin-manager     # optional: plugin store / development
```

After installation you should find:

- `/usr/share/wayland-sessions/denial.desktop` (session name **Denial**)
- `/usr/bin/denial-session` (supported session entry point; do not run `deniald` directly)
- `/etc/denial/session.conf`, `/etc/denial/outputs.conf` (conffiles, can be pre-seeded)
- `/usr/lib/denial/flutter/` (Flutter engine and bundle)

### 4.4 Display manager + autologin

All three work; pick the smallest diff:

**SDDM (recommended; matches this repository's existing KDE autologin pattern)**

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

**GDM (the path used for upstream's Debian 13 validation, GDM 48)**

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

**greetd (lightest; suitable for a Denial-only tablet)**: in
`/etc/greetd/config.toml` set `[initial_session]` to
`command = "denial-session"`, `user = "username"`, then `systemctl enable greetd`.

### 4.5 User groups

```sh
sudo usermod -aG video,render,input,audio,plugdev username
```

> `denial-session` handles the SDDM exit-status semantics explicitly (a failed
> session returns 2 so SDDM restarts the greeter); the SDDM path is supported by
> upstream code.

### 4.6 Reboot and verify with §6

---

## 5. Path B: integrate into the online build (now built in)

`.github/workflows/rootfs-build.yml` (called by `build-debian.yml` / `build-ubuntu.yml`) and `rootfs-lite.yml` already contain the changes
below (2026-11-26); this section is kept as the implementation reference for
future upgrades and rollbacks.

### 5.1 Add the option to `workflow_dispatch.inputs.desktop`

```yaml
      desktop:
        description: 'Desktop Environment (server = no DE)'
        type: choice
        options:
          - 'GNOME 桌面 / GNOME Desktop'
          - 'KDE 桌面 / KDE Desktop'
          - 'Denial 桌面 / Denial Desktop'          # new
          - '无桌面 / Headless'
        default: 'KDE 桌面 / KDE Desktop'
```

### 5.2 Install and session steps (added to the `# Desktop Environment` section)

```yaml
      - name: "安装 Denial 桌面 / Install Denial"
        if: ${{ inputs.desktop == 'Denial 桌面 / Denial Desktop' }}
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
          echo "✓ Denial 桌面已安装 / Denial installed"

      - name: "配置 Denial 会话 / Configure Denial Session"
        if: ${{ inputs.desktop == 'Denial 桌面 / Denial Desktop' }}
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
          echo "✓ Denial 会话已配置（SDDM，Session=denial） / Denial session configured (SDDM, Session=denial)"
```

> With Debian forky (`Debian Version = 14`) the Denial repository still points at the `trixie`
> suite (upstream calls this best-effort). The `denial` package's `Depends`
> already covers `libegl1/libgbm1/libgles2/libwayland-client0/libseat1/xwayland`
> and friends, so `apt` resolves them.
>
> For GDM instead: install `gdm3` and follow §4.4; the `quiet_boot` condition
> (`desktop != '无桌面 / Headless'`) also applies to Denial, so Plymouth is installed normally.

### 5.3 Trigger the online build

The Actions sidebar now has two menus: **构建根文件系统（Debian）/ Build RootFS (Debian)** and **构建根文件系统（Ubuntu）/ Build RootFS (Ubuntu)**; pick the one for your target. Suggested inputs for the Denial example (bilingual UI; the values below are the exact dropdown strings):

| Input | Value | Why |
| --- | --- | --- |
| Workflow | `构建根文件系统（Debian）` or `构建根文件系统（Ubuntu）` | Denial is validated on Debian 13 / Ubuntu 24.04 |
| Debian Version | `13` | Denial is validated; `14` (forky) is not |
| Desktop Environment | `Denial 桌面 / Denial Desktop` | Built in; existing images can still use `无桌面 / Headless` + path A |
| Autologin | `true` | Tablet boots straight into Denial |
| Username / Hostname | your choice | The username is written into autologin |
| Password | your choice, or empty | Empty falls back to the `ROOTFS_PASSWORD` secret, then to `password`; prefer the secret on public repos |
| Boot mode | `双系统 linux / Dual linux` | Keeps the existing OS; `单系统` wipes userdata |
| Quiet boot | `true` | Plymouth splash |
| Kernel Source | `预构建内核 / Prebuilt kernel` | Fastest; `自行编译内核 / Build from source` compiles the kernel first |

Artifacts: `rootfs-trixie-Denial-linux.img`, `boot-trixie-Denial-linux.img`
(kept 14 days).

### 5.4 Flash (dual boot / slot B example)

```sh
fastboot erase dtbo_b
fastboot flash boot_b boot-trixie-Denial-linux.img
fastboot flash linux rootfs-trixie-Denial-linux.img
fastboot reboot
```

---

## 6. Verification checklist

After the first boot, check in this order (this locates most failures):

| # | Check | Command | Expected |
| --- | --- | --- | --- |
| 1 | Kernel graphics | `ls /dev/dri && dmesg \| grep -i 'msm\|adreno'` | `card0`, `renderD128`; no -ENODEV |
| 2 | Packages | `dpkg -l denial denial-flutter-engine` | both `ii` |
| 3 | Session entry | `ls /usr/share/wayland-sessions/` | `denial.desktop` present |
| 4 | Session preflight | `denial-session --check` (as a normal user on a tty) | passes, DRM device resolved |
| 5 | Compositor | `ps -C deniald -o pid,cmd` | `/usr/bin/deniald` running |
| 6 | Session type | `echo $XDG_SESSION_TYPE` inside the session | `wayland` |
| 7 | Display manager | `systemctl status sddm` (or `gdm3`) | active (running) |
| 8 | Logs | `journalctl -b -u sddm`, `journalctl --user -b` | no fatal DRM/EGL errors |
| 9 | GPU rendering | `sudo apt install mesa-utils vulkan-tools`, then `glxinfo -B` | renderer is freedreno/Adreno, not llvmpipe |
| 10 | X11 compatibility | run any X11 app (`xeyes`) | appears via Xwayland |
| 11 | Audio/network | play sound, join Wi-Fi | works |
| 12 | Scaling | Denial Settings → display/appearance | right scale for the 12.4" panel |

> Diagnostics: `denial-session --print-output-config` prints the output config;
> `/etc/denial/session.conf` offers `DENIAL_DRM_DEVICE`, `DENIAL_NO_VULKAN=1` and
> `LIBGL_ALWAYS_SOFTWARE=1` for troubleshooting.

---

## 7. Not recommended: building the rootfs yourself

- Phone/proot environments lack the disk and memory headroom to debootstrap then
  chroot-install a 1 GB+ desktop;
- a non-arm64 host needs cross-architecture emulation, which is slow and masks bugs;
- CI already has the `ubuntu-24.04-arm` runner; a local rebuild loses reproducibility.

---

## 8. Known issues and limitations

1. **Upstream docs lag**: `docs/DISTRIBUTION_SUPPORT.md` still says first-party
   binaries are x86-64 only; since 0.6.10 the release page and APT repository
   include `arm64` `denial`, `denial-flutter-engine` and `denial-plugin-manager`.
2. **forky unvalidated**: Denial supports Debian Forky/Sid only best-effort; use `trixie`.
3. **KDE leftovers**: upstream warns systems originally installed with KDE are not
   guaranteed compatible — KDE services and desktop integrations can break a Denial
   session. Prefer a `server` or GNOME base; if the rootfs already had KDE, reflash a
   clean image.
4. **Brightness**: Denial's DDC/CI brightness targets external monitors only; internal
   panel brightness is covered by upstream
   [`KNOWN_ISSUES.md`](https://github.com/denialwm/denial/blob/main/docs/KNOWN_ISSUES.md).
5. **glibc baseline**: Denial requires `>= 2.39`; Debian 12 and older are out. trixie/forky are fine.
6. **Public beta**: Denial 0.6.x iterates quickly; update with `sudo apt upgrade`, but
   watch for session-config compatibility.
7. **Image size**: the rootfs is a fixed 10 GiB sparse image; Denial adds roughly
   100 MB. Artifacts are large — use `gh run download` if a browser download stalls.
8. **No systemd user manager** means XDG autostart does not run — Debian is unaffected.

---

## 9. Rollback

- **Flashing**: back up `boot_b`, the `linux` partition and `dtbo_b` before flashing;
  restore with `fastboot flash boot_b <orig>.img`, `fastboot flash linux <orig-rootfs>.img`,
  `fastboot flash dtbo_b <orig-dtbo>.img`.
- **In-system**: `sudo apt remove denial` (the repository/session stay and can be
  reinstalled); restore `/etc/sddm.conf.d/10-denial.conf` to the previous session or
  delete it.
- **CI**: the build logic is one reusable file (`rootfs-build.yml`); revert the commit and re-run Actions.

---

## 10. References

- Denial repository: <https://github.com/denialwm/denial>
- Denial install guide: <https://github.com/denialwm/denial/blob/main/docs/INSTALL.md>
- Distribution support: <https://github.com/denialwm/denial/blob/main/docs/DISTRIBUTION_SUPPORT.md>
- Debian 13 validation: <https://github.com/denialwm/denial/blob/main/packaging/debian/VALIDATION.md>
- Denial manual (development): <https://manual.denialwm.org/docs/development/> ・ <https://manual.denialwm.org/zh-cn/docs/development/>
- Denial package repositories: <https://packages.denialwm.org/> (APT: `https://packages.denialwm.org/apt`, suite `trixie`)
- Upstream project: <https://github.com/ianchb/debian-sheng>
- Kernel: <https://github.com/ianchb/sm8550-mainline> (`sheng-7.3.4`)
- This fork: <https://github.com/Xiaomi-sheng/debian-sheng-denial>

---

[![](https://img.shields.io/badge/powered_by-dsh-4D6BFE?style=flat-square&logo=deepseek&logoColor=white)](https://github.com/deepseek-ai/deepseek-harness)
