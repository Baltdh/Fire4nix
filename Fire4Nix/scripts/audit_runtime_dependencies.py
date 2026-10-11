#!/usr/bin/env python3
"""Static dependency inventory. Does not execute target ELF binaries."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys


def version_sections(text):
    needs, definitions = {}, set()
    section, library = None, None
    for line in text.splitlines():
        if line.startswith("Version needs section"):
            section, library = "needs", None
        elif line.startswith("Version definition section"):
            section, library = "definitions", None
        elif line.startswith("Version symbols section"):
            section, library = None, None
        if section == "needs":
            match = re.search(r"File: (\S+)", line)
            if match:
                library = match.group(1)
                needs.setdefault(library, [])
            name = re.search(r"Name: (\S+).*Flags: (\S+)", line)
            # Weak requirements are optional according to the ELF version flags.
            if library and name and name.group(2) != "WEAK":
                needs[library].append(name.group(1))
        elif section == "definitions":
            name = re.search(r"Name: (\S+)", line)
            if name:
                definitions.add(name.group(1))
    return {key: sorted(set(value)) for key, value in needs.items()}, sorted(definitions)


def inspect(path):
    result = subprocess.run(["readelf", "-h", "-d", "-V", "-l", str(path)],
                            capture_output=True, text=True, check=False)
    if result.returncode:
        raise ValueError("readelf rejected file: " + result.stderr.strip())
    text = result.stdout
    needs, definitions = version_sections(text)
    machine = re.search(r"Machine:\s*(.+)", text)
    return {
        "path": str(path),
        "machine": machine.group(1).strip() if machine else "unknown",
        "needed": sorted(set(re.findall(r"\(NEEDED\).*?\[(.*?)\]", text))),
        "soname": re.findall(r"\(SONAME\).*?\[(.*?)\]", text),
        "symbol_versions": sorted(set(re.findall(r"Name: ((?:GLIBC|GLIBCXX|CXXABI)_[\w.]+)", text))),
        "version_needs": needs,
        "version_definitions": definitions,
        "interpreter": re.findall(r"Requesting program interpreter: (.*?)\]", text),
    }


def audit(root, sysroot=None, extra_elfs=()):
    errors, entries, providers = [], [], {}
    inspected = {}
    if not root.is_dir():
        return {"errors": ["runtime directory does not exist"], "elfs": [], "missing": []}
    for path in sorted(set(root.rglob("*")) | set(extra_elfs)):
        if not path.is_file() or path.is_symlink():
            if path in extra_elfs:
                errors.append("launcher must be a regular ELF file: " + str(path))
            continue
        with path.open("rb") as stream:
            if stream.read(4) != b"\x7fELF":
                if path in extra_elfs:
                    errors.append("launcher is not ELF: " + str(path))
                continue
        try:
            entry = inspect(path)
        except ValueError as error:
            errors.append(str(error))
            continue
        entries.append(entry)
        inspected[str(path)] = entry
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
                    inspected[str(path)] = entry
                    for name in [path.name] + entry["soname"]:
                        system[name] = str(path)
    missing, incompatible = [], []
    for entry in entries:
        entry["dependencies"] = {}
        for name in entry["needed"]:
            provider = providers.get(name) or system.get(name)
            entry["dependencies"][name] = provider
            if not provider:
                missing.append({"binary": entry["path"], "library": name})
            else:
                required = set(entry.get("version_needs", {}).get(name, []))
                available = set(inspected[provider].get("version_definitions", []))
                absent = sorted(required - available)
                if absent:
                    incompatible.append({"binary": entry["path"], "library": name,
                                         "provider": provider, "missing_versions": absent})
    if not entries:
        errors.append("no ELF files found")
    return {"scope": "static ELF dependencies and required version nodes; individual symbols, dlopen modules and graphics need separate checks",
            "errors": errors, "missing": missing, "incompatible_versions": incompatible, "elfs": entries}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("runtime", type=Path)
    parser.add_argument("--sysroot", type=Path)
    parser.add_argument("--launcher", type=Path, help="include native launcher dependencies")
    args = parser.parse_args()
    if args.sysroot and not args.sysroot.is_dir():
        parser.error("target sysroot does not exist")
    report = audit(args.runtime.resolve(), args.sysroot, (args.launcher.resolve(),) if args.launcher else ())
    print(json.dumps(report, indent=2))
    return 1 if report["errors"] or report["missing"] or report.get("incompatible_versions") else 0


if __name__ == "__main__":
    sys.exit(main())
