# Fire4Nix portable WPE runtime

## Why it is required

The Fire4Nix launcher is intentionally small, but WPE WebKit is a
multi-process browser engine. A portable ROCKNIX package needs the WPE shared
library and its helper processes as well as the Fire4Nix launcher.

Current ROCKNIX source-tree research did not find a WPE WebKit/Cog package for
the RK3326 base image. The Chrome addon in the tree is x86_64-only and the
ROCKNIX Qt 6 build disables QtWebEngine/QtWebView. Fire4Nix therefore treats
the browser engine runtime as part of the port, not as an assumed OS service.

## Runtime layout

```text
Fire4Nix/runtime/aarch64/
  lib/
    libWPEWebKit-2.0.so.*
    ...runtime dependency closure...
  libexec/wpe-webkit-2.0/
    WPEWebProcess
    WPENetworkProcess
    WPEGPUProcess
  share/                 # optional runtime data
  runtime.manifest
```

`scripts/verify_wpe_runtime.sh` validates the essential ARM64 pieces.
`scripts/package_one_file.sh` now refuses to emit a final One File ZIP when
this runtime is absent or incomplete.

## Relocatable helper processes

Upstream WPE WebKit normally compiles `PKGLIBEXECDIR` into release builds.
`WEBKIT_EXEC_PATH` is otherwise considered only in developer-mode builds.
That does not fit a PortMaster-style ZIP which may live under different ROM
mount paths.

Fire4Nix therefore carries:

`patches/wpewebkit/0001-fire4nix-relocatable-process-path.patch`

The patch permits a release WPE build to honor an absolute
`WEBKIT_EXEC_PATH`. Fire4Nix never inherits that value from an arbitrary
external environment: `fire4nix_prepare_bundled_wpe_runtime()` resolves the
package runtime directory and sets the variable to its own
`runtime/aarch64/libexec/wpe-webkit-2.0` path.

## Staging a prepared runtime

After building WPE WebKit for aarch64 with the relocatable patch and creating
a prepared runtime prefix containing the dependency closure:

```sh
sh scripts/stage_wpe_runtime.sh /path/to/prepared-runtime
sh scripts/verify_wpe_runtime.sh
sh scripts/package_one_file.sh
```

The staging script accepts either a prefix containing `lib/` + `libexec/` or
a DESTDIR-style root containing `usr/lib/` + `usr/libexec/`.

## Still required before release

The staged runtime must be tested on the actual R36H for dynamic dependencies,
Bubblewrap sandbox support, GL/EGL/GBM/Wayland behavior, GIO TLS modules,
GStreamer plugins, audio coexistence, memory use and controller input. The
runtime gate prevents a known-incomplete ZIP, but it is not a replacement for
that hardware acceptance test.

## ARM64 library construction — 2026-10-01

`.github/workflows/fire4nix-wpe-library.yml` now rebuilds the WPE library
from Debian sid source on a native ARM64 runner with Debian trixie build
dependencies. The earlier sid dependency installation failed due to incompatible
package transitions; the stable dependency base avoids that specific failure. It applies a guarded source
transformation to permit an absolute WEBKIT_EXEC_PATH in release builds,
keeps the WebKit sandbox enabled, and installs into an isolated DESTDIR.
Initial options disable video, WebAudio, WebRTC and speech synthesis.
Mandatory GStreamer base development components remain installed; the bad
plugin development package is avoided because its current dependency chain
could not be resolved. ATK, DRM and udev headers are explicit build inputs.

The job uploads build/configuration logs on failure. A successful build also
produces a library-prefix tarball and SHA256SUMS. Log-only artifacts do not
mean a library was built. This is a moving Debian build environment, not a
reproducible ROCKNIX sysroot build. No device ABI compatibility is claimed.

The One File packager now preserves execute permission for files in the
bundled libexec directory, so WebKit subprocesses remain executable after
extraction. Dependency closure, runtime data, relocation under sandboxing,
and the ROCKNIX acceptance checks above remain required.

## Static dependency gate

Run `python3 Fire4Nix/scripts/audit_runtime_dependencies.py Fire4Nix/runtime/aarch64`
after staging. An optional `--sysroot /path/to/rocknix-root` resolves system
libraries only from an explicit AArch64 target sysroot. The tool records
DT_NEEDED, SONAME, interpreters and GLIBC/GLIBCXX/CXXABI version requirements,
and exits nonzero for missing providers or foreign ELF architecture. It does
not execute binaries, validate symbol compatibility, or cover libraries loaded
with dlopen. Success is not an on-device acceptance result.
