#!/usr/bin/env python3
from pathlib import Path
import argparse
import os
import re
import sys
import tempfile

SYSTEM_BLOCK = """  <system>
    <name>{system_name}</name>
    <fullname>{fullname}</fullname>
    <path>{install_dir}</path>
    <extension>.f4a</extension>
    <command>bash %ROM%</command>
    <platform>{platform_tag}</platform>
    <theme>{theme_name}</theme>
  </system>
"""

SYSTEM_NAME_PATTERNS = (
    r"fire4nix",
    r"fire4arkos",
)

def _remove_blocks(ctx, names):
    if not names:
        return ctx
    name_alt = "|".join(re.escape(name) for name in names)
    pattern = re.compile(
        rf"\s*<system>\s*<name>(?:{name_alt})</name>.*?</system>",
        flags=re.IGNORECASE | re.DOTALL,
    )
    return re.sub(pattern, "", ctx)

def _upsert_system(ctx, block):
    if "</systemList>" not in ctx:
        raise RuntimeError("Failed to find </systemList> in configuration")
    return ctx.replace("</systemList>", block + "</systemList>", 1)

def _normalize_install_dir(install_dir):
    path = Path(install_dir).expanduser()
    try:
        return path.resolve(strict=False).as_posix()
    except Exception:
        return path.as_posix()

def _atomic_write(path, content, backup_suffix):
    backup = path.with_name(path.name + backup_suffix)
    if path.exists() and not backup.exists():
        try:
            backup.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")
        except Exception:
            pass

    fd, tmp_path = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(content)
        os.replace(tmp_path, path)
    finally:
        try:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
        except OSError:
            pass

def insert_system(filename, install_dir, system_name="fire4nix", fullname="Fire4Nix Browser", platform_tag="fire4nix", theme_name="fire4nix"):
    path = Path(filename)
    if not path.exists():
        raise FileNotFoundError(f"{path} does not exist")

    ctx = path.read_text(encoding="utf-8", errors="replace")
    ctx = _remove_blocks(ctx, SYSTEM_NAME_PATTERNS)

    normalized_install_dir = _normalize_install_dir(install_dir)

    block = SYSTEM_BLOCK.format(
        system_name=system_name,
        fullname=fullname,
        install_dir=normalized_install_dir,
        platform_tag=platform_tag,
        theme_name=theme_name,
    )

    ctx = _upsert_system(ctx, block)
    _atomic_write(path, ctx, ".bak.fire4nix")
    print(f"Successfully modified {path}")
    return True

def remove_system(filename, system_name="fire4nix"):
    path = Path(filename)
    if not path.exists():
        return False

    ctx = path.read_text(encoding="utf-8", errors="replace")
    before = ctx
    ctx = _remove_blocks(ctx, (system_name, "fire4nix"))
    if ctx == before:
        print(f"No Fire4Nix/Fire4ArkOS entry found in {path}")
        return False

    _atomic_write(path, ctx, ".bak.fire4nix")
    print(f"Successfully removed Fire4Nix/Fire4ArkOS entries from {path}")
    return True

def main():
    parser = argparse.ArgumentParser(description="Insert or remove Fire4Nix from EmulationStation config")
    parser.add_argument("--cfg-file", dest="cfg_file", action="store", type=str, default="/etc/emulationstation/es_systems.cfg")
    parser.add_argument("--install-dir", dest="install_dir", action="store", type=str, default="/storage/roms/tools/fire4nix")
    parser.add_argument("--platform-tag", dest="platform_tag", action="store", type=str, default="fire4nix")
    parser.add_argument("--theme-name", dest="theme_name", action="store", type=str, default="fire4nix")
    parser.add_argument("--system-name", dest="system_name", action="store", type=str, default="fire4nix")
    parser.add_argument("--fullname", dest="fullname", action="store", type=str, default="Fire4Nix Browser")
    parser.add_argument("--remove", dest="remove", action="store_true")
    args = parser.parse_args()

    try:
        if args.remove:
            remove_system(args.cfg_file, system_name=args.system_name)
        else:
            insert_system(
                args.cfg_file,
                install_dir=args.install_dir,
                system_name=args.system_name,
                fullname=args.fullname,
                platform_tag=args.platform_tag,
                theme_name=args.theme_name,
            )
    except Exception as exc:
        print(f"Failed to modify {args.cfg_file}: {exc}", file=sys.stderr)
        return 1
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
