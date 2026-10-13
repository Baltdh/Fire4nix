# ROCKNIX devkit reference

These files are build-time references captured from the uploaded ROCKNIX environment. They are kept for Marco 2 / Marco 3 because they help with dependency detection, ABI matching, and cross-checking the Wayland/WPE build path.

## Captured layout

- `armhf/include/` — GLib and D-Bus headers used for compile-time matching.
- `armhf/pkgconfig/` — pkg-config files used by CMake and other build tooling to discover GLib, GModule, GIO, GObject Introspection, Cairo/XCB, Cairo fontconfig, Xwayland, and libdisplay-info.
- `python313/` — Python 3.13 build snapshot used for helper-tooling and script-compatibility reference.

## Why these files matter

- `dbus-arch-deps.h` and `glibconfig.h` help mirror the exact compile-time macros and architecture-specific assumptions from the captured runtime.
- `glib-2.0.pc`, `gmodule-2.0.pc`, and `gio-2.0.pc` are useful for GLib/GIO-based dependency discovery.
- `girepository-2.0.pc` helps if the project ever needs GObject Introspection probing in the build tooling.
- `cairo-xlib-xcb.pc`, `cairo-fc.pc`, and `cairo-script.pc` help keep the Cairo/XCB, fontconfig, and fallback rendering paths measurable.
- `xwayland.pc` helps keep the Wayland/XWayland fallback path measurable.
- `libdisplay-info.pc` is useful for display-mode and monitor capability detection.
- `python313/` is useful for future Python-based build helpers and makesetup-style compatibility checks.
- These files are reference-only and are not wired into the Fire4Nix runtime yet.

## Latest pkg-config expansion

The `armhf/pkgconfig/` snapshot was expanded with the newer `pkgconfig.zip` bundle. It now covers a wider probe set for the browser beta, including Cairo backends, GLib/GIO/GObject introspection, Wayland, EGL/GBM, Pango/HarfBuzz, PipeWire, JSON, DRM, input, and display-related pkg-config files.

The files remain reference-only and are used to keep compile-time probing aligned with the captured ROCKNIX environment.
