#!/usr/bin/env python3
"""Merge pinned REAL ROCKNIX ARM64 development stages for a CMake probe only.

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
    check(len(sys.argv)==9,
          "usage: assemble-wpe-post-harfbuzz-stage.py DEST EIGHT FONT CAIRO ICU HARFBUZZ_ICU GLVND EPOXY")
    dest,*sources=map(Path,sys.argv[1:])
    check(not dest.exists() and not dest.is_symlink(), f"output exists: {dest}")
    dest.mkdir(parents=True)
    for src in sources:
        print(f"MERGE_SOURCE={src}")
        print(f"MERGED_FILES={copy_source(src,dest)}")
    required={
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
    for pc in ('harfbuzz','harfbuzz-icu','icu-uc','icu-i18n',
               'epoxy','egl','glesv2','cairo','fontconfig','freetype2','pixman-1',
               'glib-2.0','gio-2.0','libpng16','libjpeg','zlib'):
        check((dest/'usr/lib/pkgconfig'/f'{pc}.pc').is_file(),
              f"missing target metadata {pc}.pc")
    for hdr in ('harfbuzz/hb.h', 'harfbuzz/hb-icu.h', 'unicode/utypes.h',
                'epoxy/egl.h', 'EGL/eglplatform.h', 'GLES2/gl2.h'):
        check((dest/'usr/include'/hdr).is_file(),f'missing target SDK header {hdr}')
    print("WPE_HARFBUZZ_ICU_EPOXY_EGL_STAGE=PASS_REAL_ROCKNIX_AARCH64_COLLISION_SAFE")
    print("STAGE_INSTALLABLE=no")

if __name__=='__main__':
    main()
