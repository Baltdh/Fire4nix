# Fire4Nix

Fire4Nix is a controller-first browser shell for RK3326 handhelds running
ROCKNIX. The target device is the R36H/R36S class at 640x480, using the
system's Wayland/Sway session and an ARM64 browser engine.

## Repository status

The original uploads are preserved as ZIP backups in the repository root.
Active source development lives in [`Fire4Nix/`](Fire4Nix/).

The current source snapshot is `0.83-beta-rocknix-marco3-start`. It builds in
the SDL-only audit configuration, but it is not yet a production browser:

- the native WPE runtime handoff still needs to be completed and tested;
- `bin/browser.arm64` and `bin/fire4nix-wpe-platform` are launcher scripts,
  not compiled ARM64 executables;
- the final install flow must be validated on real ROCKNIX/RK3326 hardware;
- large upstream WPE source snapshots are intentionally not tracked here.

See [`docs/PREPARATION_AUDIT.md`](docs/PREPARATION_AUDIT.md) for the verified
baseline and next development milestone.

## Quick audit build

```sh
cd Fire4Nix
bash scripts/project_audit.sh
make AUDIT_MODE=1 BUILD_MODE=SDL_ONLY
```

The audit build validates source integration on a development machine. It is
not a substitute for an aarch64 build or a device test.
