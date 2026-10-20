# Fire4Nix 1.13 — SDK/sysroot gate before compiling WebKit WPE 2.54.1

Context: R36H RK3326/AArch64, ROCKNIX. The physical unit reported glibc 2.41. The external exFAT became corrupted and later the unit showed a black screen; **no on-device testing should be attempted until the device and storage are recovered**.

## Why this change
The old source-build recipe required a CMake toolchain file, but did not check that the selected SDK root actually contained an **AArch64 libc.so.6 with the correct glibc release**. A host or newer ROCKNIX SDK can produce a successful WebKit compile that immediately fails on the R36H. This gate fails closed *before* the expensive WPE build.

## Required inputs on the Linux cross-build host
- `FIRE4NIX_ROCKNIX_TOOLCHAIN=/path/to/rocknix-toolchain.cmake`: an actual cross-toolchain CMake file (not merely an empty placeholder).
- `FIRE4NIX_ROCKNIX_SYSROOT=/absolute/path/to/target/sysroot`: **must not** be `/`.
- `FIRE4NIX_ROCKNIX_RELEASE=20260801` (default, expects GLIBC 2.41) or `20261001` (GLIBC 2.44; **not deployable to the observed 2.41 console without a firmware compatibility review**).

Read-only check:
```sh
sh rocknix-integration/build-wpe-2.54.1.sh --preflight
```
A passing check prints `SDK_PREFLIGHT=PASS`, `arch=AArch64`, `target_glibc=...`. It inspects `libc.so.6` using `readelf`, never executes foreign ELF, never downloads sources and never modifies ROCKNIX.

`--configure`, `--build`, and `--stage` now require passing the same gate. `--plan` still works without SDK and clearly lists the new requirement.

## Limitations
- A passed gate does **not** prove the CMake toolchain invokes an AArch64 compiler, that the toolchain uses this sysroot or that all transitive WPE dependencies match; the real compiler/CMake cache and ELF staging audit still need validation. This gate detects a common but costly class of wrong-rootfs builds.
- The regression test `native/tests/test_sdk_preflight.sh` uses a mock readelf with simulated target versions. It verifies refusal logic, **not** a real ROCKNIX SDK or compiled WebKit.
- The repo still **does not contain a functioning media-free WebKit 2.54.1 build**. The old rescue ZIP is GStreamer ABI-blocked, and the exFAT storage needs independent repair. Never claim browser success based on CI alone.
- Do not change ROCKNIX `/usr/lib`, kernel, glibc or Mali files while testing.

Next: obtain an audited ROCKNIX 20260801 sysroot/cross-toolchain; pass --preflight; run --configure/--build/--stage; audit native WPE dependencies; only then test `--check-platform`, Wayland 640x480 and HTTPS on the recovered R36H.
