# Fire4NIX Browser - Project Audit & Reorganization

**Date**: 2026-10-11
**Target Platform**: ROCKNIX / RK3326 handhelds
**Repository**: Baltdh/Fire4nix
**Status**: Audit and organization phase

## 1. Backup inventory analysis

The repository currently contains a set of ZIP archives that look like historical snapshots of the project, likely created during iterative development.

### Existing archive files

| File | Approx. size | Assessment |
|---|---:|---|
| `Fire4Nix_consolidated_latest_real_backup_gui_wpe_bridge_v2.zip` | ~203 KB | GUI + WPE bridge-focused snapshot |
| `Fire4Nix_consolidated_latest_real_backup_project_audit_v5.zip` | ~194 KB | Project audit snapshot |
| `Fire4Nix_consolidated_latest_real_backup_wpe_integration_cleaned.zip` | ~2.4 MB | Cleaned WPE integration bundle |
| `Fire4Nix_consolidated_latest_real_backup_wpe_integration_cleaned_with_launcher.zip` | ~5.5 MB | Likely the richest and most complete bundle |

### Initial conclusion

- The largest and most complete snapshot appears to be:
  `Fire4Nix_consolidated_latest_real_backup_wpe_integration_cleaned_with_launcher.zip`
- This bundle likely contains the most complete runtime-launcher and WPE integration logic.
- The repository is currently a loose archive dump rather than a clean source tree.

## 2. Observed project signals

From the archive contents, the codebase appears to be centered on:

- A lightweight browser shell for ROCKNIX on RK3326 devices
- Automatic browser engine detection and fallback selection
- WPE / WebKit integration path
- Wayland-first launch flow with backup X11/Xvfb handling
- GUI bridge and launcher scripts
- Embedded performance tuning for low-power ARM devices

The included README excerpt indicates a version label:

- `Fire4Nix 0.83-beta-rocknix-marco3-start`

This suggests the project is at an intermediate integration stage, not a final stable deployment.

## 3. Reorganization recommendation

The repository should be reorganized into a clean project structure that preserves the historical backups while making the active code easy to understand and build.

### Proposed layout

```text
fire4nix/
├── backups/
│   ├── gui-wpe-bridge-v2/
│   ├── project-audit-v5/
│   ├── wpe-integration-cleaned/
│   └── wpe-integration-with-launcher/
├── docs/
│   ├── BUILD.md
│   ├── DEVELOPMENT.md
│   ├── ROCKNIX_DEPLOYMENT.md
│   ├── WPE_INTEGRATION.md
│   └── SCAN_REPORT.md
├── src/
│   ├── browser/
│   ├── launcher/
│   ├── gui/
│   ├── bridge/
│   ├── configuration/
│   └── platform/
├── scripts/
│   ├── install/
│   ├── build/
│   └── tools/
├── tests/
│   ├── unit/
│   ├── integration/
│   └── hardware/
├── build/
│   ├── cmake/
│   ├── toolchains/
│   └── assets/
├── README.md
├── LICENSE
├── CMakeLists.txt
├── Makefile
└── PROJECT_AUDIT.md
```

## 4. High-value technical areas to extract and audit

### Core runtime

- Browser startup and engine selection
- Wayland/X11 fallback logic
- Lifecycle and process management
- Error handling and recovery

### Browser integration

- Firefox wrapper behavior
- Xvfb and framebuffer capture
- Input injection via xdotool or alternative input stacks
- Shared-memory frame producer and C++ consumer interface

### WPE path

- WPEWebKit backend initialization
- Wayland platform support
- Web process and rendering pipeline
- ARM compatibility and performance tuning

### Platform support

- ROCKNIX config reference files
- `/storage` vs `XDG_CONFIG_HOME` fallback logic
- Device-specific handling for RK3326
- Audio setup and pulseaudio/apulse logic

## 5. Critical risks to watch

1. Several blobs appear to be runtime or build artifacts rather than source-of-truth code.
2. Historical snapshots may contain duplicated or conflicting implementations of the same feature.
3. Some code appears to be tuned for a specific embedded environment and may not be portable.
4. The repo needs a clean “authoritative source” to avoid drift across backup copies.

## 6. Recommended next steps

### Phase 1: Preservation

- Keep the ZIP archives under `backups/`
- Do not delete snapshots until a canonical source tree is available
- Record which archive is the source of truth for each subsystem

### Phase 2: Extraction and triage

- Extract the most complete WPE launcher bundle into a structured `src/` tree
- Separate runtime scripts from analysis docs and reference data
- Identify active modules vs. dead historical code

### Phase 3: Canonical source build

- Create a minimal buildable tree for the browser shell and launcher
- Keep reference/third-party material in `docs/` or `third_party/`
- Reduce duplication between bundled snapshots and runtime code

### Phase 4: Build verification

- Validate dependencies on ROCKNIX
- Confirm cross-compilation compatibility for ARM targets
- Test launch behavior in emulated or hardware environments

## 7. Best candidate for active source tree

At this stage, the strongest candidate appears to be:

- `Fire4Nix_consolidated_latest_real_backup_wpe_integration_cleaned_with_launcher.zip`

This archive contains the strongest combination of:

- launcher support
- WPE integration
- cleaned runtime logic
- embedded environment adaptation

## 8. Summary

The project should be treated as a historical backup collection that needs to be consolidated into a canonical source tree. The immediate goal is not to invent a new architecture, but to create a stable working structure from the most complete snapshot and then gradually reduce redundancy through targeted extraction and build validation.

This repository is currently archive-heavy and not yet in a clean development state. The next meaningful action is to extract the most complete launcher bundle into a real source layout and begin code-level verification.

---

Generated by GitHub Copilot during the repository audit pass.
