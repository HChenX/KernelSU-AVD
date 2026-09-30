# KernelSU-AVD

A lightweight, automated toolkit to root Android Virtual Devices (AVD) using **KernelSU** via GKI Loadable Kernel Modules (LKM).

Inspired by the design of `rootAVD`, `KernelSU-AVD` isolates the KernelSU installation mechanism into a clean, modern, standalone workflow specifically optimized for official Android Studio emulators running Android 12 (API 31) through Android 16/17 (API 37+).

---

## Highlights

- **Kernel-Level Root**: Utilizes KernelSU's native LKM (Loadable Kernel Module) mechanism directly inside GKI (Generic Kernel Image) kernels.
- **16KB Page Size Compatible**: Fully supports Android 15, Android 16, and Baklava 16KB page-size emulator system images without native crash issues common to older legacy tools.
- **Zero Legacy Overhead**: Self-contained ramdisk patching via `ksud boot-patch --ramdisk`. No complex ash scripts, fake boot images, or custom bootloader hacks required.
- **Clean Su Isolation**: Apps do not gain root access by default. Privileges are strictly managed through the KernelSU Manager application.
- **Cross-Platform**: Includes dedicated scripts for Windows (`ksuAVD.bat`) and Linux / macOS (`ksuAVD.sh`).
- **Safe & Non-Destructive**: Automatically creates `.backup` files of original ramdisks and provides a one-click `restore` command.

---

## Prerequisites

1. **Android Studio Virtual Device (AVD)**:
   - Target emulator should use a GKI kernel (`android12-5.10`, `android13-5.15`, `android14-6.1`, `android15-6.6`, `android16-6.12`, or newer).
   - Architecture: `x86_64` or `arm64-v8a`.
2. **Android SDK Platform-Tools (`adb`)**:
   - Ensure `adb` is in your system `PATH` or located in standard Android SDK folders (`%LOCALAPPDATA%\Android\Sdk` on Windows or `~/Android/Sdk` on Linux/macOS).
3. **Emulator Running**:
   - Start the target AVD before running the patching script. Verify connection via `adb devices`.

---

## Directory Structure

```text
KernelSU-AVD/
├── ksuAVD.bat        # Windows entry script
├── ksuAVD.sh         # Linux / macOS / In-AVD entry script
├── Apps/             # Put APKs here (KernelSU.apk auto-downloaded if missing)
│   └── .gitkeep
├── LICENSE           # GPL-3.0
├── README.md         # English documentation
└── README_CN.md      # Chinese documentation
```

---

## Usage

### 1. Show Help & Auto-Detected System Images

Launch the script without arguments while your AVD is running. The script will automatically detect the running AVD's architecture, Android version, and kernel, and list ready-to-run command examples for all detected system images:

**Windows**:
```cmd
ksuAVD.bat
```

**Linux / macOS**:
```bash
chmod +x ksuAVD.sh
./ksuAVD.sh
```

Example output:
```text
==============================================================================
                    KernelSU-AVD: Root AVD with KernelSU
             GitHub: https://github.com/HChenX/KernelSU-AVD
==============================================================================

--- ADB Connected Device Status ---
  Model:           sdk_gphone16k_x86_64
  Android Version: 17 (API 37)
  Architecture:    x86_64
  Kernel:          6.12.81-android16-6-g4f69fc7b210c-ab16167562

Usage:
  ksuAVD.bat <path_to_ramdisk.img> [OPTIONS]
  ksuAVD.bat restore <path_to_ramdisk.img>
  ksuAVD.bat InstallApps

--- Available System Images / AVDs Detected on This Machine ---
  [1] ksuAVD.bat "system-images\android-35\google_apis\x86_64\ramdisk.img"
  [2] ksuAVD.bat "system-images\android-37.2\google_apis_playstore_ps16k\x86_64\ramdisk.img"
```

---

### 2. Patching the AVD

Copy the corresponding command from the list, or specify the exact path to your target `ramdisk.img` (supports relative paths from Android SDK or absolute paths):

**Windows**:
```cmd
ksuAVD.bat "system-images\android-37.2\google_apis_playstore_ps16k\x86_64\ramdisk.img"
```

Or target a specific AVD hardware instance directory directly:
```cmd
ksuAVD.bat "D:\Android\AVD\Pixel_10_Pro.avd\ramdisk.img"
```

**Linux / macOS**:
```bash
./ksuAVD.sh "system-images/android-34/google_apis/x86_64/ramdisk.img"
```

#### What happens during patching:
1. Pushes the input `ramdisk.img` and `KernelSU.apk` to `/data/local/tmp/ksuAVD/` on the running emulator.
2. Extracts `ksud` matching the AVD architecture.
3. Automatically queries the running kernel's KMI (e.g. `android16-6.12`).
4. Injects the corresponding pre-compiled KernelSU LKM module and chainloads `ksuinit` via `ksud boot-patch --ramdisk --allow-shell`.
5. Backs up the host's original `ramdisk.img` to `ramdisk.img.backup`.
6. Pulls the patched `ramdiskpatched4AVD.img` back to replace `ramdisk.img`.
7. Installs the `KernelSU.apk` Manager application on the AVD.
8. Cleans up temporary files in `/data/local/tmp/ksuAVD/`.

---

### 3. Applying the Root (Cold Boot)

After the script finishes:
1. **Fully close** the emulator instance.
2. In Android Studio **Device Manager**, click the drop-down menu on the emulator and select **"Cold Boot Now"** (or launch from command line with `-no-snapshot-load`).
3. Open the **KernelSU** application on the emulator home screen.
4. The status will display **Working (LKM Mode)**.

---

### 4. Granting Root Permissions (Shell & Apps)

By default, KernelSU denies root access to all applications including ADB Shell unless granted.

To enable root for `adb shell`:
1. Launch the **KernelSU** app on the emulator.
2. Navigate to the **Superuser** tab.
3. Tap the top-right menu and ensure **"Show system apps"** is enabled.
4. Locate **Shell** (`com.android.shell`) and toggle the permission to **Grant**.
5. Run `adb shell su` from your host terminal; you will now have full `uid=0(root)` privileges.

---

### 5. Restoring Original Ramdisk

If you ever wish to revert your emulator back to its stock, unrooted state:

**Windows**:
```cmd
ksuAVD.bat restore "path\to\ramdisk.img"
```

**Linux / macOS**:
```bash
./ksuAVD.sh restore "path/to/ramdisk.img"
```

---

### 6. Installing Additional Apps

Place any APK files into the `Apps/` directory and run:

**Windows**:
```cmd
ksuAVD.bat InstallApps
```

**Linux / macOS**:
```bash
./ksuAVD.sh InstallApps
```

---

## Technical Details

### Why KernelSU on Modern AVD?
Traditional root solutions for Android emulators frequently run into compatibility bottlenecks on modern Android versions (Android 14+), specifically:
1. **16KB Page Size**: Starting with Android 15, Android emulators support and often default to 16KB memory page sizes. Legacy binaries compiled only for 4KB page sizes crash immediately with memory alignment errors (`mprotect failed`). `ksud` and KernelSU natively support 16KB page sizes.
2. **GKI Integration**: Android 12+ Virtual Devices run standard Google Generic Kernel Images (GKI). KernelSU modules are loaded natively as kernel modules (`.ko`) into `/lib/modules` without needing to modify kernel binaries or hijack zygote.

---

## Credits & Acknowledgements

This project is built upon the invaluable work of the Android open-source community:

- **[rootAVD](https://gitlab.com/newbit/rootAVD)** by **newbit**: Pioneered the automated ramdisk extraction, patching, and replacement workflow for Android Studio AVDs.
- **[KernelSU](https://github.com/tiann/KernelSU)** by **tiann**, **weishu**, and contributors: The revolutionary kernel-based root solution for Android, providing the LKM modules and the `ksud` boot patching engine.
- **[Magisk](https://github.com/topjohnwu/Magisk)** by **topjohnwu**: Foundation of modern systemless Android customization.

---

## License

This project is open-sourced under the terms of the [GNU General Public License v3.0](LICENSE).
