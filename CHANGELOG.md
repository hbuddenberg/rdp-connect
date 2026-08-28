# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [2.0.0] — 2026-08-28

### Added

- **Native Quickshell Modal UI (`ui/shell.qml`)**: Modern standalone applet matching the Omarchy 4 design system with 4px border radius, 2px dynamic accent border reading live from `colors.toml`, visual profile picker, monitor checkboxes, and hardware feature toggles (Audio, Clipboard, Drive, USB, Webcam).
- **Interactive Quickshell Selector Engine**: `rdp-connect` automatically uses Quickshell as its primary graphical selector when run without arguments, applying configured options directly without duplicate prompts.
- **Multi-Launcher Hierarchy**: Graceful fallback across launchers: `Quickshell` → `Walker` → `Wofi` → `Rofi`.
- **Robust Autoinstaller (`install.sh`)**: Unified installer with dependency checking, user/system mode support, Quickshell UI deployment, and permission hardening.
- **Arch Linux & AUR Packaging (`PKGBUILD`, `rdp-connect.install`)**: Complete standard PKGBUILD recipe for AUR distribution with clean dependencies and license packaging.
- **`--version` / `-V` CLI Flags**: Added standard version display command.

### Security

- **Hardened Secret Isolation**: Verified strict stdin credential piping to FreeRDP (`/from-stdin:force`) preventing credential exposure in process tables (`ps aux`).
- **No Hardcoded Credentials**: Ensured all repositories, tests, and documentation are strictly clean of private data.
