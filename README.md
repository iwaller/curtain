# Curtain

English | [简体中文](README.zh-CN.md)

A macOS menu bar app that blacks out your physical screen while AI agents keep working behind the curtain.

Curtain keeps your desktop session active so tools such as Codex Computer Use can still capture and interact with apps. It uses display gamma controls rather than a black overlay window.

> **Experimental — use at your own risk.** Curtain may contain bugs and does not guarantee privacy or security. The screen may become visible or local input may reach apps unexpectedly. Use the macOS screen lock to protect sensitive content or prevent unauthorized access.

## Features

- Black out physical displays without hiding the desktop from compatible capture tools.
- Reveal the desktop with Touch ID or your macOS login password.
- Block physical keyboard and mouse input while the curtain is closed, with Accessibility permission.
- Prevent idle display sleep while active.
- Recover from an unresponsive app with an independent watchdog.

## Install a release

Supports **Apple Silicon (arm64) only**, on macOS 15 or later.

Download `Curtain-arm64.dmg` from [GitHub Releases](https://github.com/iwaller/curtain/releases), open it, and drag **Curtain** onto **Applications**. Eject the disk image and launch Curtain from Applications. The ZIP is also available for manual installation. Releases use a local code signature and are not notarized by Apple. If macOS blocks the first launch, go to **System Settings → Privacy & Security → Open Anyway**, then confirm **Open**. This option may be restricted on managed Macs.

Use **Check for Updates…** to download and install newer versions from [GitHub Releases](https://github.com/iwaller/curtain/releases). Updates are verified with an independent publisher signature, including ad-hoc signed releases. Accessibility permission is separate and may need to be granted again after an update.

## Build and run

Requires an Apple silicon Mac, macOS 15 or later, and Xcode with command-line tools selected. Tested on macOS 26; other versions remain unverified.

Available in English and Simplified Chinese, following your macOS language preferences. You can choose a language for Curtain in **System Settings → General → Language & Region → Applications**. Other languages fall back to English.

```bash
./scripts/build.sh
open build/Curtain.app
```

The build uses an available Apple Development signing identity, or falls back to ad-hoc signing. No third-party libraries are required.

To build a release without a signing certificate, run `CURTAIN_SIGN_IDENTITY=- ./scripts/build.sh`. The archive is written to `build/Curtain.zip`. Publishers should use the [release procedure](docs/operations/releasing.md) to produce its required update signature.

## Usage

1. Open Curtain and grant Accessibility permission to enable local input blocking. Without it, only the screen is hidden.
2. Choose **Enable Privacy Screen** from the menu bar.
3. Move the mouse or press a key to show the unlock screen, then use Touch ID or your login password. For remote access, choose **Unlock…** from the menu.

The curtain stays closed until unlocked or interrupted. The unlock screen returns to black after 20 seconds of inactivity. Passwords are verified locally and are not stored.

## Limits and recovery

**Curtain provides visual privacy; it does not replace the macOS screen lock.** Remote capture may still show your desktop. Use **Control–Command–Q** when you need the system lock.

Single-display fullscreen transitions and a mirrored dual-display Space configuration have been tested. Extended desktops, HDR, hot-plugging, overnight use, and full agent/remote input compatibility with input blocking enabled still need testing. See the [verification record](docs/verification.md).

If the app becomes unresponsive, the watchdog attempts to lock macOS before terminating Curtain to restore the display and input. Locking can fail; recovery takes priority. As a fallback, find the PID in `~/Library/Logs/Curtain/curtain.log` and run `kill -TERM <pid>`, then `kill -KILL <pid>` if needed. Terminating Curtain reveals the display unless macOS is locked.

## Development

- [Architecture](docs/architecture.md)
- [Subsystems](docs/subsystems/README.md)
- [Validation plan](docs/poc-plan.md)

The experimental CLI supports timed sessions of 1–300 seconds. It restores the display on exit:

```bash
./build/curtain-poc --gamma --duration 90
```

## Acknowledgments

The structure and practices used in `LESSONS.md`, `AGENTS.md`, and the `docs/` directory draw on [Magpie](https://github.com/yetone/magpie) by [yetone](https://github.com/yetone). Magpie is licensed under the [MIT License](https://github.com/yetone/magpie/blob/main/LICENSE).

The permission onboarding interaction, including the floating drag guide and its entrance animation, was inspired by [Permiso](https://github.com/zats/permiso) by [zats](https://github.com/zats), via Barlet.
