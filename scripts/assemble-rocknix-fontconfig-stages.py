#!/usr/bin/env python3
"""Assemble authenticated GitHub AArch64 stages; no host or R36H writes.

Artifact zips sometimes replace relative SONAME symlinks with identical ELF
files. Restore missing relative links ONLY after checking a real AArch64 ELF
DT_SONAME. Never accept path escapes or conflicting contents.
"""
from pathlib import Path
import hashlib
import re
import shutil
import subprocess
import sys

if len(sys.argv) < 3:
    raise SystemExit("usage: script OUT SOURCE_STAGE...")
out=Path(sys.argv[1])
sources=[Path(p) for p in sys.argv[2:]]
if out.exists() or out.is_symlink():
    raise SystemExit("ERROR: output exists")
for src in sources:
    if not (src/"usr/lib").is_dir():
        raise SystemExit(f"ERROR: missing source stage: {src}")
out.mkdir()
for src in sources:
    count=0
    for f in sorted((src/"usr").rglob("*")):
        rel=f.relative_to(src)
        d=out/rel
        if f.is_symlink():
            link=f.readlink()
            if link.is_absolute() or ".." in link.parts:
                raise SystemExit(f"ERROR: unsafe input symlink: {f}")
            if d.is_symlink():
                if d.readlink()!=link:
                    raise SystemExit(f"ERROR: conflicting symlink {d}")
            elif d.exists():
                raise SystemExit(f"ERROR: symlink collides with data {d}")
            else:
                d.parent.mkdir(parents=True,exist_ok=True)
                d.symlink_to(link)
        elif f.is_dir():
            if d.is_symlink() or (d.exists() and not d.is_dir()):
                raise SystemExit(f"ERROR: directory collision {d}")
            d.mkdir(parents=True,exist_ok=True)
        elif f.is_file():
            if d.is_symlink() or (d.exists() and not d.is_file()):
                raise SystemExit(f"ERROR: file type collision {d}")
            if d.exists():
                if hashlib.sha256(d.read_bytes()).digest()!=hashlib.sha256(f.read_bytes()).digest():
                    raise SystemExit(f"ERROR: different file collision {d}")
            else:
                d.parent.mkdir(parents=True,exist_ok=True)
                shutil.copy2(f,d)
                count+=1
        else:
            raise SystemExit(f"ERROR: unsupported file type {f}")
    print(f"FONTS_STAGE_FILES_ADDED={src.name}:{count}")

directory=out/"usr/lib"
for f in sorted(directory.glob("lib*.so*")):
    if f.is_symlink() or not f.is_file(): continue
    head=subprocess.run(["readelf","-h",str(f)],capture_output=True,text=True)
    if head.returncode or not re.search(r"Class:\s+ELF64",head.stdout) or not re.search(r"Machine:\s+AArch64",head.stdout):
        raise SystemExit(f"ERROR: non-AArch64 lib*.so ELF or invalid file: {f}")
    dyn=subprocess.run(["readelf","-d",str(f)],capture_output=True,text=True)
    if dyn.returncode: raise SystemExit(f"ERROR: not a shared object: {f}")
    names=re.findall(r"\(SONAME\).*\[([^\]]+)\]",dyn.stdout)
    if len(names)!=1: continue
    soname=names[0]
    if not soname.startswith("lib") or "/" in soname or ".." in soname:
        raise SystemExit(f"ERROR: unsafe DT_SONAME {soname}")
    if not f.name.startswith(soname): continue
    for link in (soname,soname.split(".so",1)[0]+".so"):
        dest=directory/link
        if dest==f: continue
        if dest.is_symlink():
            if dest.readlink()!=Path(f.name):
                raise SystemExit(f"ERROR: SONAME target mismatch: {dest}")
        elif dest.is_file():
            if hashlib.sha256(dest.read_bytes()).digest()!=hashlib.sha256(f.read_bytes()).digest():
                raise SystemExit(f"ERROR: SONAME binary mismatch: {dest}")
        elif dest.exists():
            raise SystemExit(f"ERROR: SONAME collision: {dest}")
        else:
            dest.symlink_to(f.name)
for name in ["libfreetype.so","libxml2.so","libpixman-1.so","libglib-2.0.so","libpng16.so","libz.so"]:
    if not (directory/name).is_file():
        raise SystemExit(f"ERROR: required target library missing: {name}")
print("FONTCONFIG_INPUT_STAGES=PASS_REAL_AARCH64_COLLISION_SAFE")
