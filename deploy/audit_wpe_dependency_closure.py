#!/usr/bin/env python3
"""Inventory full ldd-resolved ELF dependency closure of the ARM64 WPE Core.

Build-environment evidence only. The binary and shared-library inputs must be
trusted CI build outputs: ldd may invoke the dynamic loader. Do NOT use this
script on untrusted uploads or on the ROCKNIX handheld.

The report is an inventory, not a portable runtime, sysroot, package install
plan, or evidence that ROCKNIX ships these libraries. dlopen modules (GIO,
TLS, WPEPlatform graphics, multimedia) are outside ldd's static closure.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

ROLES = ("launcher", "WPEWebKit", "WPEWebProcess", "WPENetworkProcess", "WPEGPUProcess")
PROCESSES = ROLES[2:]
SONAME = re.compile(r"^[A-Za-z0-9_.+\-]+$")
LINK_LINE = re.compile(r"^([^\s]+)\s+=>\s+(.*)$")
INTERPRETER_LINE = re.compile(r"^(/\S+)\s+\(0x[0-9a-fA-F]+\)$")


def parse_ldd(output):
    """Drop ASLR addresses, keep SONAME, absolute provider path and failures."""
    found = {}
    missing = set()
    unknown = []
    for raw in output.splitlines():
        line = raw.strip()
        if not line or line.startswith("linux-vdso."):
            continue
        match = LINK_LINE.match(line)
        if match:
            soname, destination = match.groups()
            if not SONAME.fullmatch(soname):
                raise ValueError(f"invalid SONAME in ldd output: {soname!r}")
            if destination.startswith("not found"):
                missing.add(soname)
            elif destination.startswith("/"):
                found[soname] = destination.split(" (", 1)[0]
            else:
                unknown.append(line)
            continue
        match = INTERPRETER_LINE.match(line)
        if match:
            provider = match.group(1)
            found[Path(provider).name] = provider
            continue
        unknown.append(line)
    return found, sorted(missing), unknown


def check_elf_machine(path, machine):
    if not path.is_file():
        raise ValueError(f"dependency provider missing: {path}")
    with path.open("rb") as stream:
        header = stream.read(20)
    if len(header) < 20 or header[:6] != b"\x7fELF\x02\x01":
        raise ValueError(f"dependency is not ELF64 little-endian: {path}")
    found = int.from_bytes(header[18:20], "little")
    if found != machine:
        raise ValueError(f"dependency architecture mismatch: {path} machine={found} expected={machine}")


def inspect(roots, manifest, machine):
    if manifest.get("schema") != "fire4nix-wpe-abi-v1":
        raise ValueError("matching build-origin ABI manifest required")
    if manifest.get("expected_elf_machine") != machine:
        raise ValueError("ABI manifest architecture disagrees with target")
    for role in ROLES:
        if role not in manifest.get("components", {}):
            raise ValueError(f"ABI manifest lacks {role}")

    report = {}
    all_sonames = {}
    direct = set()
    for role in ROLES:
        path = roots[role].resolve(strict=True)
        check_elf_machine(path, machine)
        process = subprocess.run(["ldd", str(path)], capture_output=True,
                                 text=True, timeout=40, check=False)
        if process.returncode:
            raise ValueError(f"ldd failed for {role}: {process.stderr.strip()}")
        found, missing, unknown = parse_ldd(process.stdout)
        if missing:
            raise ValueError(f"{role}: unresolved build libraries: {', '.join(missing)}")
        if unknown:
            raise ValueError(f"{role}: unsupported ldd output: {unknown}")
        providers = {}
        for soname, resolved in sorted(found.items()):
            real = Path(resolved).resolve(strict=True)
            check_elf_machine(real, machine)
            providers[soname] = str(real)
            if soname in all_sonames and all_sonames[soname] != str(real):
                raise ValueError(f"inconsistent provider for {soname} across processes")
            all_sonames[soname] = str(real)
        required = set(manifest["components"][role].get("needed", []))
        direct.update(required)
        # Every DT_NEEDED must be identified by ldd, except the dynamic
        # loader which is represented by an absolute interpreter entry.
        absent = required - providers.keys()
        if absent:
            raise ValueError(f"{role}: direct NEEDED entries not resolved: {sorted(absent)}")
        report[role] = {
            "input_filename": path.name,
            "needed": sorted(required),
            "resolved_providers": providers,
        }
    bundled = {"libWPEWebKit-2.0.so.1"}  # actual SONAME in DT_NEEDED
    # These are names to check on a matching device, NOT instructions to copy
    # Debian libraries onto ROCKNIX.
    closure = sorted(set(all_sonames) - bundled)
    transitive = sorted(set(all_sonames) - direct - bundled)
    return {
        "schema": "fire4nix-wpe-dependency-closure-v1",
        "qualification": "Debian ARM64 ldd build-only; ROCKNIX libraries, symbol ABI, dlopen and sandbox UNVERIFIED",
        "expected_elf_machine": machine,
        "components": report,
        "all_system_sonames": closure,
        "transitive_only_sonames": transitive,
        "build_provider_paths": {name: all_sonames[name] for name in closure},
        "warnings": [
            "Never replace ROCKNIX libc, dynamic loader, EGL or GPU drivers with Debian libraries",
            "ldd cannot find dynamic modules loaded by dlopen or validate target-side ABI",
        ],
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--launcher", type=Path, required=True)
    parser.add_argument("--webkit", type=Path, required=True)
    parser.add_argument("--process-dir", type=Path, required=True)
    parser.add_argument("--abi", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--machine", type=int, default=183)
    args = parser.parse_args(argv)
    roots = {"launcher": args.launcher, "WPEWebKit": args.webkit}
    roots.update({name: args.process_dir / name for name in PROCESSES})
    try:
        report = inspect(roots, json.loads(args.abi.read_text()), args.machine)
    except (ValueError, OSError, subprocess.TimeoutExpired) as exc:
        print(f"WPE dependency closure FAILED: {exc}", file=sys.stderr)
        return 1
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(f"Build-origin dependency closure: {len(report['all_system_sonames'])} SONAMEs")
    print(f"Transitive-only SONAMEs: {len(report['transitive_only_sonames'])}")
    print("Device compatibility: UNVERIFIED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
