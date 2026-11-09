# Curtain

English | [简体中文](README.zh-CN.md)

A macOS menu bar app that blacks out your physical screen while AI agents keep working behind the curtain.

Curtain keeps your desktop session active and uses display gamma controls to hide the physical output. Compatible tools, including tested Codex Computer Use capture and click paths, can still access the desktop. Compatibility depends on the display, capture method and input tool; see [Limits and recovery](#limits-and-recovery).

> **Curtain is a visual privacy tool, not a system screen lock. It must not be used as a substitute for a secure screen lock.** Your desktop session remains active, and compatible capture and automation tools can still access it. Touch ID/password prompts and local input blocking do not provide the security guarantees of the macOS screen lock. To protect sensitive content or prevent unauthorized access, use **Control–Command–Q** to lock macOS.
>
> **Experimental — use at your own risk.** Curtain may contain bugs and does not guarantee privacy or security. The screen may become visible or local input may reach apps unexpectedly.

## Features

- Black out physical displays without hiding the desktop from compatible capture tools.
- Reveal the desktop with Touch ID or your macOS login password.
- Block physical keyboard and mouse input while the curtain is closed, with Accessibility permission.
- Prevent idle display sleep while active.
- Recover from an unresponsive app with an independent watchdog.

## Install a release

Targets **Apple Silicon (arm64) only**, on macOS 15 or later. Physical-display testing has been on macOS 26. Limited macOS 27 VM testing covered permissions, password unlock, session cleanup and renderer regressions; it does not verify physical-screen blackout. macOS 15 remains unverified. See the [verification record](docs/verification.md#2026-11-09-macos-27-virtual-machine-validation).

When a packaged release is available, download `Curtain-arm64.dmg` from [GitHub Releases](https://github.com/iwaller/curtain/releases), open it, and drag **Curtain** onto **Applications**. Eject the disk image and launch Curtain from Applications. The ZIP is also available for manual installation. Releases use a local code signature and are not notarized by Apple. If macOS blocks the first launch, go to **System Settings → Privacy & Security → Open Anyway**, then confirm **Open**. This option may be restricted on managed Macs.

If no packaged release is listed, [build from source](#build-and-run). GitHub’s automatically generated source archives are not installable apps.

While the curtain is open, use **Check for Updates…** to check for newer stable versions on [GitHub Releases](https://github.com/iwaller/curtain/releases) and confirm installation. The updater requires both `Curtain.zip` and `Curtain.zip.sig` on the release. Updates are verified with an independent publisher signature, including ad-hoc signed releases. Accessibility permission is separate and may need to be granted again after an update.

## Build and run

Build on an Apple Silicon Mac using a native terminal and a full Xcode installation with support for Icon Composer `.icon` assets. The standalone Command Line Tools package is insufficient. The verified toolchain is Xcode 27.1 / Swift 6.4 on macOS 26.7.1; older toolchains are unverified. Select that Xcode installation in **Xcode → Settings → Locations → Command Line Tools**. The macOS 15 deployment target describes the app’s runtime target, not the build host requirement.

Available in English and Simplified Chinese, following your macOS language preferences. You can choose a language for Curtain in **System Settings → General → Language & Region → Applications**. Other languages fall back to English.

From the repository root, build and launch the app:

```bash
./scripts/build.sh
open build/Curtain.app
```

If another copy is running, open the curtain and quit it before launching the build. For installation to `/Applications` and restart, use `./scripts/install.sh` after building; it refuses to replace a running instance unless the curtain is open.

The build uses an available Apple Development signing identity, or falls back to ad-hoc signing. No third-party libraries are required. Builds use release optimization by default; use `CURTAIN_BUILD_CONFIGURATION=debug ./scripts/build.sh` for a debug build.

To build a release without a signing certificate, run `CURTAIN_SIGN_IDENTITY=- ./scripts/build.sh`. The archive is written to `build/Curtain.zip`. Publishers should use the [release procedure](docs/operations/releasing.md) to produce the installer DMG and required update signature.

## Usage

1. Open Curtain and follow its permission guide to enable local input blocking. The permission is called **Accessibility** on macOS 26 and earlier; the app uses **Device Control and Data Access** wording on macOS 27 and later. Without permission, the screen can be hidden but local input is not blocked.
2. Choose **Enable Privacy Screen** from the menu bar. A two-second grace period prevents the activation click from immediately opening the unlock screen.
3. Move the mouse or press a key to show the unlock screen, then use Touch ID or your login password. For remote access, choose **Unlock…** from the menu.

The menu bar app has no default session time limit. The unlock screen returns to black after 20 seconds of inactivity. Login passwords are verified locally through macOS OpenDirectory; Touch ID uses LocalAuthentication. Curtain does not save or log the password.

The permission guide stays outside System Settings when space permits and uses a compact card on the left when space is limited. Its **×** button hides the guide; the back arrow returns to the setup window.

System lock, sleep or session switching ends the privacy session and restores display output. Unlocking macOS does not automatically enable Curtain again. The idle-display-sleep assertion does not override lid closure or forced sleep; keep a laptop open and connected to power for unattended use.

## Limits and recovery

**Curtain provides visual privacy; it does not replace the macOS screen lock.** Remote capture may still show your desktop. Use **Control–Command–Q** when you need the system lock.

During unlocking, Curtain restores gamma and covers the desktop with windows so you can see the authentication controls. Space/fullscreen transitions during this interval may expose content, and the panel may interrupt agent input.

Single-display fullscreen transitions and a mirrored dual-display Space configuration have been tested. Extended desktops, HDR, hot-plugging, overnight use, and full agent/remote input compatibility with input blocking enabled still need testing. See the [verification record](docs/verification.md).

If the main thread stops sending heartbeats for about 10 seconds, the watchdog attempts to lock macOS before terminating Curtain to restore the display and input. It waits up to three seconds for lock confirmation. This recovery uses a private macOS lock API; locking can fail and recovery takes priority. An ordinary app crash or forced termination does not guarantee a system lock. As a fallback, find the PID in `~/Library/Logs/Curtain/curtain.log` and run `kill -TERM <pid>`, then `kill -KILL <pid>` if needed. Terminating Curtain reveals the display unless macOS is locked.

## Development

- [Architecture](docs/architecture.md)
- [Subsystems](docs/subsystems/README.md)
- [Validation plan](docs/poc-plan.md)

The experimental CLI is a separate visual-only probe: it has no input blocking, password/Touch ID unlock UI or watchdog. Its default duration is 90 seconds, configurable from 1–300 seconds. Before starting, note that it exits automatically at the deadline; press **Control–C** in the launching terminal to stop early, or use `kill -TERM <pid>` with the PID printed at startup. Exit restores the display. Run it only when no Curtain privacy session is active:

```bash
./build/curtain-poc --gamma --duration 90
```

The build also packages `CurtainWatchdog` for active-session recovery and a short-lived `CurtainRenderer` for unlock wallpaper preparation. Neither is installed as a persistent service. Renderer failure uses a dark gradient. Component memory measurements and their limits are in the [verification record](docs/verification.md#2026-11-07-disposable-wallpaper-renderer-integration).

## Acknowledgments

The structure and practices used in `LESSONS.md`, `AGENTS.md`, and the `docs/` directory draw on [Magpie](https://github.com/yetone/magpie) by [yetone](https://github.com/yetone). Magpie is licensed under the [MIT License](https://github.com/yetone/magpie/blob/main/LICENSE).

The permission onboarding interaction, including the floating drag guide and its entrance animation, was inspired by [Permiso](https://github.com/zats/permiso) by [zats](https://github.com/zats), via Barlet.
