# Fire4Nix R36H: link-provider ELF audit for WPE 2.54.1

## Why this is necessary

The existing `audit-wpe-sysroot-pkgconfig.sh` checks 22 target development-module names and versions. But a valid `.pc` file may point to a missing, corrupt, x86-64 or unsafe shared library. The R36H requires AArch64 and the observed ROCKNIX runtime exposes glibc 2.41. These are separate checks, not interchangeable.

`audit-wpe-target-elf-providers.sh` is a second, read-only preflight for **seven critical link components**: GLib, GIO, Soup3, libtasn1, HarfBuzz, libepoxy and Wayland client. It expands their `pkg-config --libs` link flags under the selected sysroot, checks each first `lib*.so` candidate for regular-file ELF64 AArch64 shared object type, and rejects external symlinks, a greater required GLIBC than the target and direct GStreamer NEEDED entries in the first media-free profile.

`glib-networking` does not normally provide its own `.pc` development module. Instead the checker also requires an AArch64 `libgiognutls.so` GIO module within the target tree. Without a usable TLS backend, a browser can load local HTTP pages but fail HTTPS. A target trust store is a **separate** runtime requirement and must be checked on the real device.

## On a host with a verified ROCKNIX SDK

```sh
export FIRE4NIX_ROCKNIX_RELEASE=20260801
export FIRE4NIX_ROCKNIX_SYSROOT=/absolute/path/to/rocknix-aarch64-sysroot
sh rocknix-integration/audit-wpe-sysroot-pkgconfig.sh --pc-ready
sh rocknix-integration/audit-wpe-target-elf-providers.sh --inspect
sh rocknix-integration/audit-wpe-target-elf-providers.sh --strict
```

`--inspect` reports missing providers while exiting successfully when the sysroot directory exists. `--strict` exits 6 if providers or TLS are absent/incompatible. Neither mode runs target code, modifies the sysroot, downloads sources or touches the R36H.

The script is intentionally conservative and may reject a legitimate SDK that stores providers in an unfamiliar layout. Extend supported target-only search paths with evidence rather than allowing host fallback.

## Verification and limitations

`sh native/tests/test_wpe_target_elf_providers.sh` builds an actual tiny AArch64 ELF shared object with clang/lld in a temporary test sysroot. It also checks rejection of x86-64 libraries, an unsafe ELF symlink, missing GIO TLS module and host `PKG_CONFIG_PATH` contamination. **These are CI fixture results, not proof that the ROCKNIX SDK is complete.**

A passing static audit is not a finished browser, a full dependency closure, resolved versioned symbols, installed CA certificates, confirmed GPU operation or functional HTTPS. Next milestones are: finish the actual RK3326 ROCKNIX toolchain; compile/install all required target libraries and development metadata; run both audits; configure/link WPE with `USE_GSTREAMER=OFF`; stage private binaries, inspect all `DT_NEEDED` and test local HTML/HTTPS on the actual R36H. Never copy Ubuntu ARM64 build output into the console or alter `/usr/lib`.
