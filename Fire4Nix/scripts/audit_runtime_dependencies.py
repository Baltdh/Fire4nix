#!/usr/bin/env python3
"""Static dependency inventory. Does not execute target ELF binaries."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys


def inspect(path):
    result = subprocess.run(["readelf", "-h", "-d", "-V", "-l", str(path)],
                            capture_output=True, text=True, check=False)
    if result.returncode:
        raise ValueError("readelf rejected file: " + result.stderr.strip())
    text = result.stdout
    machine = re.search(r"Machine:\s*(.+)", text)
    return {
        "path": str(path),
        "machine": machine.group(1).strip() if machine else "unknown",
        "needed": sorted(set(re.findall(r"\(NEEDED\).*?\[(.*?)\]", text))),
        "soname": re.findall(r"\(SONAME\).*?\[(.*?)\]", text),
        "symbol_versions": sorted(set(re.findall(r"Name: ((?:GLIBC|GLIBCXX|CXXABI)_[\w.]+)", text))),
        "interpreter": re.findall(r"Requesting program interpreter: (.*?)\]", text),
    }


def audit(root, sysroot=None):
    errors, entries, providers = [], [], {}
    if not root.is_dir():
        return {"errors": ["runtime directory does not exist"], "elfs": [], "missing": []}
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.is_symlink():
            continue
        with path.open("rb") as stream:
            if stream.read(4) != b"\x7fELF":
                continue
        try:
            entry = inspect(path)
        except ValueError as error:
            errors.append(str(error))
            continue
        entries.append(entry)
        if entry["machine"] != "AArch64":
            errors.append("not AArch64: " + str(path))
        for name in [path.name] + entry["soname"]:
            providers[name] = str(path)
    # System-provided libraries are accepted only from an explicitly supplied
    # target sysroot, and must themselves identify as AArch64 ELF files.
    system = {}
    if sysroot:
        for folder in ("lib", "lib64", "usr/lib", "usr/lib64"):
            directory = sysroot / folder
            if not directory.is_dir():
                continue
            for path in sorted(directory.rglob("*.so*")):
                if not path.is_file():
                    continue
                resolved = path.resolve()
                if not resolved.is_relative_to(sysroot.resolve()):
                    continue
                try:
                    entry = inspect(resolved)
                except ValueError:
                    continue
                if entry["machine"] == "AArch64":
                    for name in [path.name] + entry["soname"]:
                        system[name] = str(path)
    missing = []
    for entry in entries:
        entry["dependencies"] = {}
        for name in entry["needed"]:
            provider = providers.get(name) or system.get(name)
            entry["dependencies"][name] = provider
            if not provider:
                missing.append({"binary": entry["path"], "library": name})
    if not entries:
        errors.append("no ELF files found")
    return {"scope": "static ELF inventory; dlopen modules, symbols and graphics behavior need separate checks",
            "errors": errors, "missing": missing, "elfs": entries}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("runtime", type=Path)
    parser.add_argument("--sysroot", type=Path)
    args = parser.parse_args()
    if args.sysroot and not args.sysroot.is_dir():
        parser.error("target sysroot does not exist")
    report = audit(args.runtime.resolve(), args.sysroot)
    print(json.dumps(report, indent=2))
    return 1 if report["errors"] or report["missing"] else 0


if __name__ == "__main__":
    sys.exit(main())
