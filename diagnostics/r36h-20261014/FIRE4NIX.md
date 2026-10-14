# Fire4Nix physical ROCKNIX findings — 2026-10-14

## Observed
- ROCKNIX official 20261001, branch next, build c445081a59518f37d9776e5412dd7b14910696f7, kernel 7.1.2, RK3326 AArch64, approximately 1 GiB RAM, swap disabled.
- Device GLIBC 2.41; bundled Debian WPE reported GLIBC floor 2.38: *minimum version comparison passes only*. Wayland socket /var/run/0-runtime-dir/wayland-1 exists.
- Native ELF64 ARM64 launcher depends on libWPEWebKit-2.0.so.1. Default system loader reports `libWPEWebKit-2.0.so.1 => not found`, even though a local ~174 MB file exists at `Fire4Nix/runtime/lib/libWPEWebKit-2.0.so.1`.
- Three local helpers exist at `Fire4Nix/runtime/libexec/wpe-webkit-2.0/{WPEWebProcess,WPENetworkProcess,WPEGPUProcess}`.
- Physical package layout is `runtime/lib` (legacy), while automatic activation formerly expected `runtime/aarch64/lib`.
- Segmentation faults (139) recorded at distinct attempts around 16:54, 17:02 and 17:04 (EDT per device logs). These are **not explained solely** by one separate attempt with missing library (127).
- Cog, bwrap and pkg-config absent in console inventory. Missing Cog transformed the final launcher status from original WPE 139 into 127.
- System inventory contains no WPE/WebKit or libsoup SONAMEs in inspected libraries. This does not prove no copies outside inspected paths. Further transitive `ldd` resolution needed for core lib and helpers.
- `mali_debug.config`: `MALI_WAYLAND_AFBC=0`, a supplied configuration file, not proof that it was applied.

## Implemented fixes
- Detect verified `runtime/lib` legacy layout as well as `runtime/aarch64/lib`.
- Apply scoped `LD_LIBRARY_PATH` and `WEBKIT_EXEC_PATH`; check missing transitive dependencies before launching.
- Preserve native WPE error if Cog is missing.
- Offer one-time SHA256 baseline builder for the installed runtime, explicitly noting this is not publisher authenticity validation.
- Keep system libc/loader and WebKit sandbox unchanged.

## Still outstanding
Validate the complete runtime dependency closure against ROCKNIX, provide missing ARM64 libs safely without overwriting graphics/system libraries, test sandbox and hardware WPE Wayland display. If 139 persists, capture a native backtrace. Do not claim the browser works on the R36H until a real page loads securely.
