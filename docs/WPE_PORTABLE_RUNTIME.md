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
