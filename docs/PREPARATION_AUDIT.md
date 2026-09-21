# Fire4Nix preparation audit

Date: 2026-09-21

## Selected baseline

The source tree in `Fire4Nix/` was recovered from
`Fire4Nix_consolidated_latest_real_backup_wpe_integration_cleaned_with_launcher.zip`.
It identifies itself as `0.83-beta-rocknix-marco3-start` and is newer than the
`project_audit_v5` snapshot by both version metadata and code changes.

The four uploaded ZIP files passed an archive integrity test. Their SHA-256
values are:

| Archive | SHA-256 |
| --- | --- |
| `Fire4Nix_consolidated_latest_real_backup_gui_wpe_bridge_v2.zip` | `792fd341603e32c32a897b8f7c72d6ef59106a621af02c76eab677387d03bf2c` |
| `Fire4Nix_consolidated_latest_real_backup_project_audit_v5.zip` | `d45b2e91e46e04930257d1cddb00523dec807ccd28c27cc3d50fabd429870cd5` |
| `Fire4Nix_consolidated_latest_real_backup_wpe_integration_cleaned.zip` | `a35e77a09e5202fefd343d13f6a14370451fa0f4f3158e2e96be131847d10b3c` |
| `Fire4Nix_consolidated_latest_real_backup_wpe_integration_cleaned_with_launcher.zip` | `a414f432100ab760c7bb9f7569bd55d3647065a975eca08e4d891d39905c7c5c` |

## Verified locally

- The project audit script completes and validates the main shell scripts.
- Python helper files pass bytecode compilation.
- The SDL-only audit configuration builds and links successfully with a host
  C++17 compiler.
- The source contains a controller-oriented 640x480 UI, engine selection,
  configuration, EmulationStation integration, and WPE launch scaffolding.

## Known gaps

- The successful host build uses SDL compatibility stubs and is not an ARM64
  ROCKNIX release build.
- The native WPE launcher has not been built against the device's actual
  WPE/WebKit libraries.
- The packaged files named `browser.arm64` and `fire4nix-wpe-platform` are
  POSIX shell launchers rather than ELF ARM64 binaries.
- The code still contains stub implementations used by the audit build.
- Device-level validation is required for Wayland, input mapping, audio,
  networking, browser rendering, installation, update, and recovery.
- One older ZIP stores paths with a `../` prefix. It should not be extracted
  directly into an uncontrolled location.

## Next milestone

### GUI follow-up (2026-09-21)

Fixed the modular GUI input adapter: previously every action and text read
returned an empty value. `src/fire4nix_input.cpp` now consumes the actual
dispatcher queues. Event dispatch is also available with SDL compatibility
types, so the same mapping code can be tested without a display. This does
not make the compatibility renderer a real renderer.

Run `make test-gui` in `Fire4Nix/`. Regression assertions cover FIFO action
delivery, controller activation, text and composition input, analog deadzone,
focus wraparound, clearing focus, ignored quit events, and layout invalidation
at 640x480 and on resize. These are logic tests, not screenshot tests.

Additional blockers found by source inspection:

- `main.cpp` starts the legacy `App`; it does not start `GuiBootstrap` or call
  `initializeApplication`. Integrating modular chrome needs an explicit choice
  of event/render ownership to avoid duplicate input and overlapping UI.
- `fire4nix_stubs.cpp` still returns null native window/renderer handles and
  reports successful initialization. The modular browser chrome cannot be
  considered visually validated through that renderer.
- This host has no SDL development package or pkg-config. No real SDL window
  or on-device screenshot has been inspected in this follow-up.
- The archived Firefox profile disables sandbox and Safe Browsing settings.
  Review the profile and generated settings before any public browsing test;
  this source baseline must not be advertised as a secure release.

The legacy source was preserved apart from the input adapter fix. No final
ARM64 binary or installable release was generated.

Complete the real WPE runtime path:

1. define a reproducible aarch64/ROCKNIX toolchain and dependency check;
2. compile the WPE launcher as an ARM64 ELF executable;
3. connect navigation, load progress, URL, and focus state to the GUI bridge;
4. add automated host checks plus an on-device smoke-test script;
5. produce one installable ZIP only after the device acceptance checks pass.
