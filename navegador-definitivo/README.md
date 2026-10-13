# 🚀 Fire4Nix Browser

A lightweight browser shell for ROCKNIX on RK3326 handhelds, with automatic engine selection, a low-overhead start page, and a Wayland-first launch path that now carries Marco 2 bridge completion into Marco 3 start for native WPE runtime handoff, with a live bridge journal for shell and UI synchronization.

![Downloads](https://img.shields.io/github/downloads/Cheemsdoge28/fire4nix/total?style=for-the-badge&color=green)
![Release](https://img.shields.io/github/v/release/Cheemsdoge28/fire4nix?style=for-the-badge&color=blue)
[![Sponsors](https://img.shields.io/github/sponsors/Cheemsdoge28?style=for-the-badge&color=ea4aaa&logo=github-sponsors)](https://github.com/sponsors/Cheemsdoge28)

## 📱 Supported Devices
Fire4Nix is optimized specifically for **RK3326** based handhelds running **ROCKNIX**:
- **R36S** (Highly Recommended)
- **RG351MP / RG351P / RG351M**
- **Powkiddy RGB10 / RGB10S**
- **RK2020**
- **Gameforce Chi**
- Any other RK3326 device on ROCKNIX or similar OS

## 🛠️ Installation


### Reference Pack

This backup keeps a trimmed reference bundle: the useful ROCKNIX config files, the devkit pkg-config notes, the Python build snippets, and the WPE study notes that still help the browser beta. Bulky runtime snapshots, duplicate staging trees, and unused helper copies were removed in this pass.

See `SCAN_REPORT.md` for the cleanup list and the remaining work toward the first real ROCKNIX test.

**Compatibility note:** On systems without `/storage`, Fire4Nix now falls back to `XDG_CONFIG_HOME`, then `HOME/.config`, and finally a local `.fire4nix` folder.

**Functional launch** now resolves the best available browser engine at runtime, prioritizing the native WPE platform path, then Cog on Wayland, and falling back to Chromium, Firefox, or the local ARM64 binary when needed. The resolver also accepts WPE launcher aliases such as `wpe-launcher`, `wpe-browser`, `mini-browser`, and `wpe-native`, mapping them to the staged WPE platform path or to Cog when the native binary is not yet present so ROCKNIX installs can keep one entry point.

**Fire4Nix v0.83-beta-rocknix-marco3-start** keeps Marco 1 complete, marks Marco 2 complete, and starts Marco 3 with the WPE runtime handoff, and preserves synchronized stage/focus/next/acceptance reporting, a stronger runtime environment baseline, source-detail diagnostics, and the native WPE handoff path staged for the next pass.

### 1. Download & Prep

The shell managers now also expose `advance` snapshots so you can see the current browser step, stage name, next integration target, plan steps, the bridge journal path, and the acceptance line from the same package.
The progress context is exported once after bootstrap so the shell and GUI read the same live stage values.
It also includes `rocknix_reference/devkit/armhf/` expanded with `gio-2.0.pc`, `girepository-2.0.pc`, `cairo-xlib-xcb.pc`, and `cairo-script.pc`, plus `rocknix_reference/etc/NetworkManager/NetworkManager.conf` and `rocknix_reference/etc/tmpfiles.d/systemd-tmp.conf` as configuration snapshots that matter for Marco 2 / Marco 3 build and runtime matching.


## WPE source reference bundle

This backup also includes `third_party_reference/wpe_sources/`, containing the upstream WPE source snapshots and the package/build metadata needed for later Marcos.
Stage 1 of that study is captured in `third_party_reference/wpe_sources/WPE_STAGE1_SOURCE_MAP.md`, which maps the launcher, backend, platform, and WebKit build roles into the Fire4Nix modules.
