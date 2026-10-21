# Fire4Nix: real libpng → zlib AArch64 dependency chain

## Goal and context

WPE WebKit needs libpng for PNG decoding and zlib for compression.
Prior ROCKNIX-target builds established that the GCC 15.2.0 / glibc 2.41
RK3326 toolchain can compile **individual** zlib 1.3.1 and SQLite 3.50.2
libraries. This experiment verifies a **linked dependency chain** using
one isolated DESTDIR; no target ELF is executed on the x86_64 runner.

### Source identity

- ROCKNIX/distribution commit `3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb`.
- Base package `packages/graphics/libpng/package.mk` declares **libpng 1.6.50**
  and SHA256 `4df396518620a7aa3651443e87d1b2862e4e88cad135a8b93423e01706232307`.
- **Important:** ROCKNIX's separate override
  `projects/ROCKNIX/packages/graphics/libpng/package.mk` declares **1.6.40**.
  This deliberately builds 1.6.50 as a standalone, experimental WPE dependency
  with the original base-package hash. It is **not** proof of conformity to
  the effective ROCKNIX project package (including its configure flags).
- Zlib 1.3.1 and SHA256
  `9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23`
  match the original ROCKNIX package.
- Compiler checkpoint comes only from successful genuine toolchain
  [run 39525819979](https://github.com/Baltdh/Fire4nix/actions/runs/39525819979)
  and is restored to its original checkout path.

## Criteria to declare test success

A successful [libpng/zlib workflow](https://github.com/Baltdh/Fire4nix/actions/workflows/r36h-rocknix-libpng-zlib-chain.yml)
must verify all of the following, not only return exit code 0:

1. Zlib and libpng are ELF64 AArch64, not Ubuntu x86_64 objects.
2. libpng is dynamically linked against `libz.so.1` from the private
   build, with no implicit fallback to host libraries during configure.
3. `libpng16.pc` is valid with isolated target pkg-config paths.
4. Neither library requires newer GLIBC than 2.41.
5. A cross-linked AArch64 test executable references both
   `libpng16.so` and `libz.so`, but is never executed on the runner.
6. A report explicitly says `R36H_INSTALLABLE=no` and
   `WPE_WEBKIT_BUILT=no`.

The output is a disposable host-build test archive of ELF/headers/.pc,
**not** a browser package. It cannot be copied directly to the R36H
for execution. A project-correct 1.6.40 build and full library closure
are still necessary for standard ROCKNIX integration.

## Next steps

Build remaining missing development modules against one coherent target
sysroot, then configure WPE WebKit 2.54.1 with GStreamer disabled.
Check every ELF `DT_NEEDED`, subprocess, GLIBC/Wayland/GL and GIO TLS
dependency. Only then stage an isolated runtime on the R36H internal ext4
and visually verify local HTML (colors, JS_OK, FRAME_OK, controls) before HTTPS.
