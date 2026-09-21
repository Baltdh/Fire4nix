#!/bin/bash
set -euo pipefail

REAL_SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$0" 2>/dev/null || printf '%s\n' "$0")"
SCRIPT_DIR="$(cd "$(dirname "$REAL_SCRIPT_PATH")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$APP_DIR/scripts/fire4nix_env.sh"
fire4nix_bootstrap_environment "$APP_DIR"

printf 'Fire4Nix Marco 3 start audit\n'
printf 'app_dir=%s\n' "$APP_DIR"
printf 'config_dir=%s\n' "${FIRE4NIX_CONFIG_DIR:-unknown}"
printf 'runtime_dir=%s\n' "${FIRE4NIX_RUNTIME_DIR:-unknown}"
printf 'progress_stage=%s\n' "$(fire4nix_progress_stage_label)"
printf 'progress_stage_name=%s\n' "$(fire4nix_progress_stage_name)"
printf 'progress_stage_summary=%s\n' "$(fire4nix_progress_stage_summary)"
printf 'progress_next_action=%s\n' "$(fire4nix_progress_next_action)"
printf 'progress_acceptance=%s\n' "$(fire4nix_progress_acceptance)"
printf 'next_stage=%s\n' "phase3-wpe-runtime"
printf '\n'

python3 - "$APP_DIR" <<'PY'
import os
import re
import sys
import subprocess
from collections import Counter

app_dir = sys.argv[1]
targets = [
    "scripts/fire4nix_env.sh",
    "scripts/browser_manager.sh",
    "scripts/engine_manager.sh",
    "scripts/run_browser.sh",
    "scripts/wpe_cog_launch.sh",
    "scripts/wpe_platform_launch.sh",
]

print("duplicate function scan")
for rel in targets:
    path = os.path.join(app_dir, rel)
    if not os.path.exists(path):
        print(f"- {rel}: missing")
        continue
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    names = re.findall(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(\)\s*\{', text, flags=re.M)
    counts = Counter(names)
    dups = {name: count for name, count in counts.items() if count > 1}
    if not dups:
        print(f"- {rel}: ok")
        continue
    print(f"- {rel}:")
    for name, count in sorted(dups.items()):
        print(f"    {name}: {count} definitions")
print()
print("shell syntax scan")
syntax_targets = [
    "scripts/fire4nix_env.sh",
    "scripts/browser_manager.sh",
    "scripts/engine_manager.sh",
    "scripts/run_browser.sh",
    "scripts/wpe_cog_launch.sh",
    "scripts/wpe_platform_launch.sh",
    "scripts/project_audit.sh",
]
for rel in syntax_targets:
    path = os.path.join(app_dir, rel)
    if not os.path.exists(path):
        print(f"- {rel}: missing")
        continue
    result = subprocess.run(["bash", "-n", path], capture_output=True, text=True)
    status = "ok" if result.returncode == 0 else "syntax error"
    print(f"- {rel}: {status}")

print()
print("progress context export scan")
required_exports = [
    "FIRE4NIX_PROGRESS_STAGE",
    "FIRE4NIX_PROGRESS_STAGE_NAME",
    "FIRE4NIX_PROGRESS_FOCUS",
    "FIRE4NIX_PROGRESS_STAGE_SUMMARY",
    "FIRE4NIX_PROGRESS_NEXT",
    "FIRE4NIX_PROGRESS_ACCEPTANCE",
    "FIRE4NIX_BRIDGE_JOURNAL",
    "FIRE4NIX_BRIDGE_JOURNAL_PATH",
    "FIRE4NIX_BRIDGE_JOURNAL_COUNT",
    "FIRE4NIX_BRIDGE_JOURNAL_STATE",
]
for var in required_exports:
    value = os.environ.get(var, "")
    if value:
        print(f"- {var}: ok ({value})")
    else:
        print(f"- {var}: missing")
print()

bridge_path = os.environ.get("FIRE4NIX_BRIDGE_JOURNAL_PATH") or os.environ.get("FIRE4NIX_BRIDGE_JOURNAL", "")
bridge_count = os.environ.get("FIRE4NIX_BRIDGE_JOURNAL_COUNT", "")
bridge_state = os.environ.get("FIRE4NIX_BRIDGE_JOURNAL_STATE", "")


print("reference snapshot scan")
ref_checks = [
    "rocknix_reference/runtime-libs/aarch64",
    "rocknix_reference/runtime-libs/armhf",
    "rocknix_reference/devkit/armhf/include",
    "rocknix_reference/devkit/armhf/pkgconfig",
    "rocknix_reference/devkit/armhf/pkgconfig/gio-2.0.pc",
    "rocknix_reference/devkit/armhf/pkgconfig/girepository-2.0.pc",
    "rocknix_reference/devkit/armhf/pkgconfig/cairo-xlib-xcb.pc",
    "rocknix_reference/devkit/armhf/pkgconfig/cairo-script.pc",
    "rocknix_reference/runtime-tools/armhf/gio-launch-desktop",
    "rocknix_reference/runtime-tools/armhf/dbus-daemon-launch-helper",
    "rocknix_reference/runtime-tools/armhf/hostname",
    "rocknix_reference/etc/NetworkManager/NetworkManager.conf",
    "rocknix_reference/etc/tmpfiles.d/systemd-tmp.conf",
    "third_party_reference/wpe_sources/WPE_STAGE1_SOURCE_MAP.md",
    "third_party_reference/wpe_sources/wpewebkit-2.52.5/Source/WebKit/PlatformWPE.cmake",
    "third_party_reference/wpe_sources/wpewebkit-2.52.5/Source/WTF/wtf/PlatformWPE.cmake",
    "third_party_reference/wpe_sources/wpewebkit-2.52.5/Source/WebKit/SourcesWPE.txt",
    "third_party_reference/wpe_sources/wpewebkit-2.52.5/Source/WebKit/WPEPlatform/wpe/wpe-platform.h",
    "third_party_reference/wpe_sources/wpewebkit-2.52.5/Source/WebKit/UIProcess/API/wpe/WPEWebView.h",
    "third_party_reference/wpe_sources/cog-0.18.5/launcher/cog.c",
    "third_party_reference/wpe_sources/libwpe-1.16.3/include/wpe/view-backend.h",
    "third_party_reference/wpe_sources/wpebackend-fdo-1.16.1/include/wpe/fdo.h",
]
for rel in ref_checks:
    path = os.path.join(app_dir, rel)
    if os.path.exists(path):
        print(f"- {rel}: present")
    else:
        print(f"- {rel}: missing")
print()
print("bridge journal")
if bridge_path:
    print(f"- path: {bridge_path}")
else:
    print("- path: missing")
print(f"- count: {bridge_count or '0'}")
print(f"- state: {bridge_state or 'missing'}")
print()

print("suspicious typo scan")
suspicious_patterns = [
    "pipefailo",
    "pipefailo pipefail",
]
for rel in syntax_targets:
    if rel == "scripts/project_audit.sh":
        continue
    path = os.path.join(app_dir, rel)
    if not os.path.exists(path):
        continue
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    matches = [pat for pat in suspicious_patterns if pat in text]
    if matches:
        print(f"- {rel}: " + ", ".join(matches))
    else:
        print(f"- {rel}: ok")
print("- scripts/project_audit.sh: skipped self-scan")
print()
print("WPE source reference bundle")
wpe_source_bundle = os.path.join(app_dir, "third_party_reference", "wpe_sources")
if os.path.isdir(wpe_source_bundle):
    print(f"- path: present ({wpe_source_bundle})")
    for rel in [
        "third_party_reference/wpe_sources/README.md",
        "third_party_reference/wpe_sources/WPE_SOURCE_ANALYSIS.md",
        "third_party_reference/wpe_sources/WPE_STAGE1_SOURCE_MAP.md",
        "third_party_reference/wpe_sources/WPE_STAGE1_DETAILED_NOTES.md",
        "third_party_reference/wpe_sources/manifest.json",
    ]:
        print(f"- {rel}: {'present' if os.path.exists(os.path.join(app_dir, rel)) else 'missing'}")
else:
    print("- path: missing")

print()
print("WPE source study anchors")
source_anchors = [
    "third_party_reference/wpe_sources/cog-0.18.5/launcher/cog.c",
    "third_party_reference/wpe_sources/cog-0.18.5/core/cog-platform.c",
    "third_party_reference/wpe_sources/cog-0.18.5/platform/wayland/cog-platform-wl.c",
    "third_party_reference/wpe_sources/libwpe-1.16.3/include/wpe/wpe.h",
    "third_party_reference/wpe_sources/libwpe-1.16.3/include/wpe/view-backend.h",
    "third_party_reference/wpe_sources/wpebackend-fdo-1.16.1/include/wpe/fdo.h",
    "third_party_reference/wpe_sources/wpebackend-fdo-1.16.1/include/wpe/initialize-egl.h",
    "third_party_reference/wpe_sources/wpewebkit-2.52.5/Source/WebKit/PlatformWPE.cmake",
    "third_party_reference/wpe_sources/wpewebkit-2.52.5/Source/WTF/wtf/PlatformWPE.cmake",
    "third_party_reference/wpe_sources/wpewebkit-2.52.5/Source/WebKit/SourcesWPE.txt",
    "third_party_reference/wpe_sources/wpewebkit-2.52.5/Source/WebKit/WPEPlatform/wpe/wpe-platform.h",
    "third_party_reference/wpe_sources/wpewebkit-2.52.5/Source/WebKit/UIProcess/API/wpe/WPEWebView.h",
]
for rel in source_anchors:
    path = os.path.join(app_dir, rel)
    print(f"- {rel}: {'present' if os.path.exists(path) else 'missing'}")


print()
print("key cleanup targets")
cleanup_targets = [
    "scripts/fire4nix_env.sh",
    "scripts/project_audit.sh",
    "scripts/run_browser.sh",
    "scripts/wpe_platform_launch.sh",
    "src/gui/browser_bridge.cpp",
    "src/gui/browser_chrome.cpp",
    "PHASE2_PROGRESS.md",
    "ENGINE_ROADMAP.md",
    "WPE_PLATFORM_CONTINUATION.md",
]
for rel in cleanup_targets:
    path = os.path.join(app_dir, rel)
    print(f"- {rel}: {'present' if os.path.exists(path) else 'missing'}")
PY
