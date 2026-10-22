#!/usr/bin/env python3
"""Consolidate pinned ROCKNIX ARM64 SDK libraries for Fire4Nix step 1.

No host libraries; refuse collisions, unsafe symlinks and architectures. This
staging tree is NOT an installable firmware/browser image.
"""
from __future__ import annotations
import hashlib
from pathlib import Path
import re
import shutil
import subprocess
import sys

def check(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"ERROR: {message}")

def digest(path: Path) -> bytes:
    return hashlib.sha256(path.read_bytes()).digest()

def copy_source(source: Path, dest: Path) -> int:
    count=0
    for sub in ("usr/lib", "usr/include"):
        src = source/sub
        check(src.is_dir(), f"source tree is not a private usr/lib or usr/include: {src}")
        for obj in sorted(src.rglob("*")):
            p = dest/obj.relative_to(source)
            if obj.is_symlink():
                target=obj.readlink()
                check(not target.is_absolute() and '..' not in target.parts,
                      f"external symlink: {obj} -> {target}")
                if p.is_symlink():
                    check(p.readlink()==target, f"different symlink at {p}")
                    continue
                if p.is_file():
                    check(digest(p)==digest(obj), f"file/link collision at {p}")
                    continue
                check(not p.exists(),f"symlink/type collision at {p}")
                p.parent.mkdir(parents=True,exist_ok=True)
                p.symlink_to(target)
                count+=1
            elif obj.is_dir():
                check(not p.is_symlink() and (not p.exists() or p.is_dir()),
                      f"directory collision at {p}")
                p.mkdir(parents=True,exist_ok=True)
            elif obj.is_file():
                if p.is_symlink():
                    check(digest(p)==digest(obj),f"file/link collision at {p}")
                    continue
                check(not p.exists() or p.is_file(),f"file/type collision at {p}")
                if p.exists():
                    check(digest(p)==digest(obj), f"file content mismatch at {p}")
                else:
                    p.parent.mkdir(parents=True,exist_ok=True)
                    shutil.copy2(obj,p)
                    count+=1
            else:
                raise SystemExit(f"ERROR: unsupported target stage object {obj}")
    return count

def readelf(path: Path) -> str:
    out=subprocess.run(['readelf','-h',str(path)],
                       capture_output=True,text=True,check=False)
    check(out.returncode==0 and re.search(r"Class:\s+ELF64",out.stdout)
          and re.search(r"Machine:\s+AArch64",out.stdout),
          f"not a target ELF64/AArch64 object: {path}")
    return out.stdout

def main() -> None:
    check(len(sys.argv)==13,
          "usage: assemble-step1-rocknix-stages.py DEST EIGHT_JPEG FONT CAIRO ICU HARFBUZZ_ICU GLVND EPOXY GCRYPT WAYLAND WEBP SOUP_PREREQS")
    dest,*sources=map(Path,sys.argv[1:])
    check(not dest.exists() and not dest.is_symlink(), f"output exists: {dest}")
    dest.mkdir(parents=True)
    for src in sources:
        print(f"MERGE_SOURCE={src}")
        print(f"MERGED_FILES={copy_source(src,dest)}")
    required={
      'libgpg-error.so.0':'GpgError',
      'libgcrypt.so.20':'Gcrypt',
      'libharfbuzz.so.0':'HarfBuzz',
      'libharfbuzz-icu.so.0':'HarfBuzz ICU',
      'libicuuc.so.74':'ICU Unicode',
      'libicui18n.so.74':'ICU I18N',
      'libicudata.so.74':'ICU data',
      'libepoxy.so.0':'libepoxy EGL',
      'libEGL.so.1':'libglvnd EGL dispatcher',
      'libGLESv2.so.2':'libglvnd GLES2 dispatcher',
      'libcairo.so.2':'Cairo',
      'libfontconfig.so.1':'Fontconfig',
      'libfreetype.so.6':'FreeType',
      'libpixman-1.so.0':'Pixman',
      'libglib-2.0.so.0':'GLib',
      'libgio-2.0.so.0':'GIO',
      'libpng16.so.16':'PNG',
      'libjpeg.so.8':'JPEG',
      'libz.so.1':'zlib',
    }
    for filename,name in required.items():
        path=dest/'usr/lib'/filename
        check(path.is_file(),f"missing target {name}: {path}")
        readelf(path)
    for pc in ('libgcrypt','gpg-error','harfbuzz','harfbuzz-icu','icu-uc','icu-i18n',
               'epoxy','egl','glesv2','cairo','fontconfig','freetype2','pixman-1',
               'glib-2.0','gio-2.0','libpng16','libjpeg','zlib'):
        check((dest/'usr/lib/pkgconfig'/f'{pc}.pc').is_file(),
              f"missing target metadata {pc}.pc")
    for hdr in ('gcrypt.h','gpg-error.h','harfbuzz/hb.h', 'harfbuzz/hb-icu.h', 'unicode/utypes.h',
                'epoxy/egl.h', 'EGL/eglplatform.h', 'GLES2/gl2.h'):
        check((dest/'usr/include'/hdr).is_file(),f'missing target SDK header {hdr}')
    # Real target dependencies that were built in separate workflows.
    # These are not replacements for firmware libraries or the WPE engine.
    required_additional={
      'libwayland-client.so.0': 'Wayland 1.23.1 client',
      'libwayland-server.so.0': 'Wayland 1.23.1 server',
      'libwayland-cursor.so.0': 'Wayland 1.23.1 cursor',
      'libwayland-egl.so.1': 'Wayland EGL',
      'libwebp.so.7': 'WebP 1.6.0',
      'libwebpdemux.so.2': 'WebP demux',
      'libwebpmux.so.3': 'WebP mux',
      'libnghttp2.so.14': 'nghttp2',
      'libpsl.so.5': 'libpsl',
    }
    for filename,name in required_additional.items():
        candidate=dest/'usr/lib'/filename
        check(candidate.is_file(),f"missing target {name}: {candidate}")
        readelf(candidate)
    for pc in ('wayland-client','wayland-server','wayland-cursor',
               'libwebp','libwebpdemux','libwebpmux','libnghttp2','libpsl'):
        check((dest/'usr/lib/pkgconfig'/f'{pc}.pc').is_file(),
              f"missing target metadata {pc}.pc")
    check((dest/'usr/include/wayland-client.h').is_file(),
          'missing target Wayland header')
    # Verify complete lib*.so* collection, including duplicate symlink targets.
    inspected=0
    required_glibc=(2,41)
    for p in sorted((dest/'usr/lib').glob('*.so*')):
        if p.is_symlink():
            check(p.exists(),f"broken target SONAME link: {p}")
            continue
        if not p.is_file():
            continue
        header=readelf(p)
        check(bool(re.search(r"Data:\\s+2's complement, little endian",header)),
              f"target is not little-endian: {p}")
        version=subprocess.run(['readelf','-V',str(p)],capture_output=True,text=True,check=False)
        check(version.returncode==0,f"cannot read ELF symbol versions: {p}")
        for maj,minr in re.findall(r'Name: GLIBC_(\\d+)\\.(\\d+)',version.stdout):
            check((int(maj),int(minr))<=required_glibc,
                  f"requires GLIBC_{maj}.{minr} newer than R36H 2.41: {p}")
        inspected+=1
    check(inspected>10,"too few real AArch64 shared objects in unified stage")
    print(f"TARGET_SHARED_ELF_CHECKED={inspected}")
    print("TARGET_GLIBC_MAX=2.41")
    print("STAGE1_ROCKNIX_COMBINED=PASS_REAL_ELF64_AARCH64_COLLISION_SAFE")
    print("DT_NEEDED_TRANSITIVE_ABI=NOT_YET_VERIFIED")
    print("SYSROOT_GLIBC_COMPATIBILITY=REQUIRES_FULL_CLOSURE")

    print("STAGE_INSTALLABLE=no")
    print("WPE_WEBKIT_BUILT=no")

if __name__=='__main__':
    main()
