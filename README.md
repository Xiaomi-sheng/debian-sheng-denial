# debian-sheng

> **Project Status**  
> This project is still in its **early development stage**. Functionality may be incomplete and build results may contain unknown issues.  
> If you encounter any problems, please open an [Issue](https://github.com/ianchb/debian-sheng/issues).

---

## Overview

This project uses **GitHub Actions** to automatically build a Debian root filesystem for the Xiaomi Pad 6S Pro (sheng), providing a flashable `rootfs.img` and `boot.img`.  
Simply start a workflow in your own repository and you will have a ready-to-use Debian environment.

---

## Documentation

This fork targets the [Denial](https://github.com/denialwm/denial) Wayland desktop instead of the stock desktop environments. The **构建根文件系统（Debian）/ Build RootFS (Debian)** and **构建根文件系统（Ubuntu）/ Build RootFS (Ubuntu)** workflows have a dedicated `Denial 桌面 / Denial Desktop` desktop option; integration notes, in both languages:

- [Denial integration guide (English)](docs/denial-integration.md)
- [Denial 集成指南（简体中文）](docs/denial-integration.zh-CN.md)

---

## Getting Started

### 1. Fork & Enable Actions

Click the **Fork** button at the top right to copy the repository to your GitHub account.

> <img width="718" height="139" alt="image" src="https://github.com/user-attachments/assets/a4504501-fc6d-4dac-9306-0d80df909a2c" />

Navigate to the **Actions** tab of your forked repository.  
If Actions are disabled, click `I understand my workflows, go ahead and enable them`.

> <img width="853" height="94" alt="image" src="https://github.com/user-attachments/assets/2c478313-194c-4505-9d78-593e642e6f51" />

### 2. Run the Build Workflow

In the **Actions** page, select **构建根文件系统（Debian）/ Build RootFS (Debian)** or **构建根文件系统（Ubuntu）/ Build RootFS (Ubuntu)** from the left sidebar, then click the **Run workflow** dropdown on the right.

You will see a list of configurable options (see [Advanced Configuration](#advanced-configuration) for details).  
If you leave everything unchanged, the build will proceed with the **default settings**.

> <img width="546" height="256" alt="image" src="https://github.com/user-attachments/assets/b109244d-ed3c-4f83-b6d0-5434fae64e68" />

Click the green **Run workflow** button to start the build.

> <img width="588" height="1058" alt="image" src="https://github.com/user-attachments/assets/33515229-3f18-431d-8966-04f3d42c9ea7" />

### 3. Download Artifacts

Once the workflow finishes, open the summary page of that run.  
Under the **Artifacts** section, download `rootfs.img` and `boot.img`.

> <img width="1454" height="1141" alt="image" src="https://github.com/user-attachments/assets/5f750de4-f124-4913-bfa4-9432125f3906" />

---

## Advanced Configuration

The Debian and Ubuntu builds are **separate workflows with separate menus**, so their options never mix: pick the menu for the distribution you want. The Run workflow menus, step names and log messages are bilingual (中文 / English). Each menu exposes the following inputs; the Debian menu has `Debian Version`, while the Ubuntu menu has `Ubuntu Release`:

| Parameter | Description | Options | Default |
|-----------|-------------|---------|---------|
| **Debian Version** | Debian release number to install (Debian menu only). | `13` (trixie) / `14` (forky) | `13` |
| **Ubuntu Release** | Ubuntu release number to install (Ubuntu menu only; arm64 packages come from `ports.ubuntu.com`). | `24.04` (noble) / `24.10` (oracular) / `25.04` (plucky) / `25.10` (questing) / `26.04` (resolute) | `24.04` |
| **Desktop Environment** | Preinstalled desktop environment. Select `无桌面 / Headless` for a headless (no GUI) system. | `GNOME 桌面 / GNOME Desktop` / `KDE 桌面 / KDE Desktop` / `Denial 桌面 / Denial Desktop` / `无桌面 / Headless` | `KDE 桌面 / KDE Desktop` |
| **Plasma Mobile** | Install `plasma-mobile` instead of `plasma-desktop` when Desktop Environment is `KDE 桌面 / KDE Desktop`. | `true` / `false` | `false` |
| **Autologin** | Whether the created user should be logged in automatically. | `true` / `false` | `true` |
| **Username** | Username for the non-root user. | string | `username` |
| **Password** | Password for the non-root user and `root`. Leave empty to use the repository secret `ROOTFS_PASSWORD`, then the default `password`. | string | *(empty)* |
| **Hostname** | System hostname. | string | `xiaomi-sheng` |
| **System language** | System locale for the generated root filesystem. Selecting `None (C.UTF-8)` keeps the default locale; selecting another option generates that locale together with `en_US.UTF-8` and sets it as the system default. | `None (C.UTF-8)` / `en_US.UTF-8` / `zh_CN.UTF-8` / `zh_TW.UTF-8` / `ja_JP.UTF-8` / `ko_KR.UTF-8` / `de_DE.UTF-8` / `fr_FR.UTF-8` / `es_ES.UTF-8` / `ru_RU.UTF-8` | `None (C.UTF-8)` |
| **Boot mode** | Determines which partition the OS boots from. See the [Flashing](#flashing-to-your-device) section for details. | `单系统 userdata / Single userdata` – use the entire `userdata` partition; <br> `双系统 linux / Dual linux` – use a dedicated `linux` partition (dual boot); <br> `自定义分区 / Custom partition` – use a custom partition name (must be specified below) | `双系统 linux / Dual linux` |
| **Quiet boot** | Enables a quieter boot flow with Plymouth splash support. For prebuilt kernels, this selects the `_plymouth.img` boot image; for custom kernels, it appends `quiet splash plymouth.ignore-serial-consoles fbcon=map:1` to the boot cmdline. This is ignored when Desktop Environment is set to `无桌面 / Headless`. | `true` / `false` | `true` |
| **Custom partition** | Partition name to flash the rootfs to. **Required only when Boot mode is `custom`.** | any partition name (e.g. `debian`) | *(empty)* |
| **Kernel source** | How to obtain the kernel image. **`预构建内核 / Prebuilt kernel` is not available when Boot mode is `自定义分区 / Custom partition`.** | `预构建内核 / Prebuilt kernel` – use a prebuilt kernel from [ianchb/sm8550-mainline](https://github.com/ianchb/sm8550-mainline); <br> `自行编译内核 / Build from source` – clone and compile a custom kernel from the repo specified below | `预构建内核 / Prebuilt kernel` |
| **Kernel Repo URL** | Git repository URL for the custom kernel. **Required when kernel source is `自行编译内核 / Build from source`.** | valid Git URL | `https://github.com/ianchb/sm8550-mainline` |
| **Kernel Branch** | Branch to checkout from the kernel repository. **Required when kernel source is `自行编译内核 / Build from source`.** | branch name | `sheng-7.3.4` |
| **Kernel Config** | Kernel config file name inside the repository. **Required when kernel source is `自行编译内核 / Build from source`.** | file name (e.g. `sm8550.config`) | `sm8550.config` |
| **Firmware Repo URL** | Git repository URL for device firmware files. | valid Git URL | `https://github.com/ianchb/sheng-firmware` |
| **Firmware Branch** | Branch to checkout from the firmware repository. | branch name | `master` |

> **Notes**  
> - **Password** for the configured user and `root` comes from the `Password` input when it is filled, otherwise from the repository secret `ROOTFS_PASSWORD`, otherwise it falls back to the insecure default value: `password`.  
> - Prefer the `ROOTFS_PASSWORD` secret on public repositories: a `workflow_dispatch` input value is stored in the run's metadata and is only masked inside the job log. The input exists so forked copies can set a password without creating a secret.  
> - **Release numbers vs codenames**: both version menus show release numbers (`13`, `14`, `24.04`, `24.10`, ...); the workflow maps them to codenames (`trixie`, `noble`, ...) internally. To add a newer release, add its number to the matching menu and to the mapping in the **Resolve Distribution** step of `rootfs-build.yml`.  
> - **Ubuntu builds**: the Ubuntu menu builds any Ubuntu 24.04+ arm64 release from `http://ports.ubuntu.com/ubuntu-ports/`. Denial is validated by upstream only on Ubuntu 24.04 (noble); newer Ubuntu releases reuse the `noble` Denial packages as a best effort. Ubuntu has no `firefox-esr` (Firefox is a snap), so GNOME/KDE images come without a preinstalled browser, and occasional terminal renames (`kgx`/`ptyxis`) or missing optional KDE apps are handled with fallbacks and warnings. On Ubuntu the GNOME choice installs Ubuntu's own `ubuntu-desktop-minimal` metapackage (`ubuntu-session`, extensions, PipeWire, Xorg), and GDM autologin is written to `/etc/gdm3/custom.conf` with the session pinned through AccountsService. The fingerprint package's `fprintd`/`libgusb` version pins are relaxed on Ubuntu because Ubuntu 24.04 ships slightly older versions; whether the reader then works still needs on-device testing.  
> - **KDE on Ubuntu 24.04** is Plasma 5.27; Debian 13 ships Plasma 6.x.  
> - `qbootctl` (A/B slot switcher) is installed when the release packages it; otherwise the build warns and slot switching must be done from a PC (`fastboot`) or TWRP.  
> - If you choose **Boot mode = `自定义分区 / Custom partition`**, you **must** fill in the **Custom partition** field.  
> - If you choose **Kernel source = `自行编译内核 / Build from source`**, you **must** provide the **Kernel Repo URL**, **Kernel Branch**, and **Kernel Config** fields.  
### Install the prebuilt packages in a Droidspaces container (no build)

The simplest path, no compilation:

1. In Droidspaces: container tab → `+` → official rootfs repository → **Ubuntu 24.04** → import and start it.
2. Inside that container run one command:

```sh
curl -fsSL https://raw.githubusercontent.com/Xiaomi-sheng/debian-sheng-denial/master/scripts/install-debs.sh | bash
```

The script downloads `sheng-debs.tar.gz` from the
[`debs-latest` release](https://github.com/Xiaomi-sheng/debian-sheng-denial/releases/tag/debs-latest)
and installs every prebuilt device package with apt: fastrpc, libssc,
iio-sensor-proxy, sheng-sensors, sheng-devauth, alsa-xiaomi-sheng, the firmware
package and the Xiaomi extras. On Ubuntu it relaxes the fingerprint package's
`fprintd`/`libgusb` version pins automatically.

If the container's network is slow, download `sheng-debs.tar.gz` with a browser
first, put it in the current directory, and run the same script — it uses the
local file instead of downloading again.

Add `--with-firmware` / `--with-kernel` when preparing a flashable tree instead
of a test container:

```sh
./scripts/install-debs.sh --with-firmware --with-kernel
```

## About Some Packages

| Package | Description |
|---------|-------------|
| [xiaomi-mipps-auth](https://github.com/ianchb/xiaomi-mipps-auth) | Automatically negotiates MIPPS when a charger is connected, enabling fast charging up to 120 W and providing charging notifications. |
| [xiaomi-charger-mode](https://github.com/ianchb/xiaomi-charger-mode) | Shows a simple charging screen and prevents a full system boot when a charger is connected while the device is powered off. |
| [xiaomi-sheng-thp](https://github.com/ianchb/xiaomi-sheng-thp) | Processes touch data for finger input and stylus support. |
| [xiaomi-pen-status](https://github.com/ianchb/xiaomi-pen-status) | Shows stylus connection and battery status, and automatically attempts the initial Bluetooth connection. |
| [xiaomi-sheng-fingerprint](https://github.com/ianchb/xiaomi-sheng-fingerprint) | Provides TEE-based fingerprint reader support, including patches for `libfprint` and `fprintd`. |
| [xiaomi-sheng-keyboard-helper](https://github.com/ianchb/xiaomi-sheng-keyboard-helper) | Supports the microphone indicator on the official keyboard and disables keyboard input based on the hinge angle. |

---

## Flashing to Your Device

### Prerequisites

- Device with an **unlocked bootloader**.
- **TWRP** recovery installed.
- `fastboot` properly set up on your computer.

> **Warning**  
> The following steps modify device partitions and may brick your device or cause data loss. Back up your important data and make sure you understand each command.

### Partition Setup (Two Modes)

1. **Dual boot (keep existing OS)**  
   Inside TWRP, use `parted` to shrink the `userdata` partition and create a new partition at the end, named e.g. `linux`.  
   *The exact parted commands depend on your partition layout; only the concept is given here. You can refer to [alghiffaryfa19/Linux-xiaomi-sheng](https://github.com/alghiffaryfa19/Linux-xiaomi-sheng) for more information.*

2. **Single boot (replace OS completely)**  
   Use the `userdata` partition directly for Debian (erasing all previous data).

### Flashing the Images

The commands below assume:
- You will boot Debian using **slot B**
- The Debian partition is named **linux**

```bash
# 1. Erase dtbo
fastboot erase dtbo_b

# 2. Flash the boot image
fastboot flash boot_b boot.img

# 3. Flash the root filesystem to the linux partition
fastboot flash linux rootfs.img

# 4. Reboot
fastboot reboot
```

After rebooting, the device should start from slot B and boot into Debian.  

---

## Credits

This project benefits from the following outstanding work and community support:

- **map220v** – for TWRP, the mainline kernel port and many device-specific adaptations that make Linux run on the Xiaomi Pad 6S Pro (sheng).
- **alghiffaryfa19** – for providing the original build scripts, from which this project is derived and modified.
