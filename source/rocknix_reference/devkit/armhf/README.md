# ARMHF devkit reference

This directory stores ARMhf build-time references captured from the uploaded ROCKNIX environment.

## Captured files

### Headers
- `include/dbus-arch-deps.h`
- `include/glibconfig.h`

### pkg-config files
- `pkgconfig/glib-2.0.pc`
- `pkgconfig/gmodule-2.0.pc`
- `pkgconfig/gio-2.0.pc`
- `pkgconfig/girepository-2.0.pc`
- `pkgconfig/cairo-xlib-xcb.pc`
- `pkgconfig/cairo-script.pc`
- `pkgconfig/xwayland.pc`
- `pkgconfig/libdisplay-info.pc`
- `pkgconfig/cairo-fc.pc`

## Notes

- These files are useful for CMake / pkg-config probing during Marco 2 and Marco 3.
- `pkgconfig/cairo-fc.pc` helps with Cairo + fontconfig probing in the build path.
- They are reference-only and are not used by the browser at runtime.

## Latest upload pass

This directory now also reflects the newer `pkgconfig.zip` snapshot. The added files broaden the compile-time probe set beyond the original GLib/Cairo/Xwayland baseline so the Fire4Nix beta can stay closer to the real ROCKNIX environment.

The important new areas are:
- Cairo rendering backends and targets;
- GIO / GModule / GObject / GThread;
- Wayland, EGL, GBM, DRM, and OpenGL-related probes;
- Pango / Harfbuzz text stack;
- PipeWire, JSON, input, display, and desktop integration probes.
