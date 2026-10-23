#!/usr/bin/env python3
"""Audit a *built* WPE runtime against ROCKNIX SDK libraries without executing it.

Inputs are a private WPE runtime (lib/ and libexec/), the exact RK3326
ROCKNIX compiler sysroot, and optionally the build-only stage-1 overlay.

A successful result proves static SONAME presence, ELF class/machine, and
direct GLIBC floor only. It cannot validate symbol versions in providers,
Mali/Wayland behavior, HTTPS, process startup, or physical device support.
Libraries found ONLY in stage-1 are build inputs, not installed on the R36H.
"""
from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path
import re
import subprocess
import sys
from typing import Callable

SONAME = re.compile(r"\(SONAME\).*?\[([^\]]+)\]")
NEEDED = re.compile(r"\(NEEDED\).*?\[([^\]]+)\]")
RPATH = re.compile(r"\((?:RPATH|RUNPATH)\).*?\[([^\]]*)\]")
GLIBC = re.compile(r"\bName:\s*GLIBC_(\d+)\.(\d+)\b")
INTERP = re.compile(r"\[Requesting program interpreter:\s*([^\]]+)\]")
ROCKNIX_INTERPRETERS = frozenset((
    "/lib/ld-linux-aarch64.so.1",
    "/lib64/ld-linux-aarch64.so.1",
    "/usr/lib/ld-linux-aarch64.so.1",
))
SEARCH_DIRS = ("lib", "lib64", "usr/lib", "usr/lib64",
               "usr/lib/aarch64-rocknix-linux-gnu")
PROCESSES = ("WPEWebProcess", "WPENetworkProcess")
MAX_GLIBC = (2, 41)
HOST_PATH_SEGMENTS = ("/home/", "/tmp/", "/opt/", "/workspace/", "/runner/")


def readelf(flag: str, path: Path) -> str:
    # Versioned GCC exports are otherwise abbreviated (e.g. __at[...]@@...).
    # All downstream checks must see complete symbol names and ELF paths.
    cmd = ["readelf", "--wide", flag, str(path)]
    try:
        return subprocess.run(cmd, capture_output=True, check=True,
                              text=True, timeout=45).stdout
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
        raise ValueError(f"readelf {flag} failed: {path.name}: {type(e).__name__}") from e


def aarch64(header: str) -> bool:
    return all(re.search(pattern, header) for pattern in (
        r"Class:\s+ELF64\b", r"Machine:\s+AArch64\b",
        r"Data:\s+2's complement, little endian"))


def safe_file(path: Path, root: Path) -> bool:
    try:
        return path.is_file() and path.resolve(strict=True).is_relative_to(root.resolve())
    except (OSError, RuntimeError):
        return False


def index_libraries(root: Path) -> tuple[dict[str, Path], list[str]]:
    """Index only target lib directories and refuse symlinks escaping the input."""
    out: dict[str, Path] = {}
    unsafe: list[str] = []
    for subdir in SEARCH_DIRS:
        d = root / subdir
        if not d.is_dir():
            continue
        for path in sorted(d.rglob("*.so*")):
            if not (path.is_file() or path.is_symlink()):
                continue
            if not safe_file(path, root):
                unsafe.append(str(path.relative_to(root)))
                continue
            out.setdefault(path.name, path)
    return out, unsafe


def gpu_process_requirement(runtime: Path) -> tuple[bool, str]:
    report = runtime / "BUILD-REPORT.txt"
    if not report.exists() and not report.is_symlink():
        return True, "legacy_requires_gpu"
    if not safe_file(report, runtime) or report.is_symlink():
        raise ValueError("INVALID_BUILD_REPORT")
    lines = report.read_text(encoding="utf-8").splitlines()
    values = [x.partition("=")[2] for x in lines if x.startswith("GPU_PROCESS_PROFILE=")]
    if len(values) > 1:
        raise ValueError("CONFLICTING_GPU_PROFILES")
    value = values[0] if values else "required_unverified"
    if value == "disabled_verified_wayland":
        return False, value
    if value in ("required_unverified", "enabled_verified"):
        return True, value
    raise ValueError("UNKNOWN_GPU_PROFILE")



def injected_bundle_requirement(runtime: Path) -> tuple[bool, str]:
    """Fail closed on incomplete WPE 2.54 installed assets.

    The injected bundle is dlopen-loaded, so it may have no inbound DT_NEEDED
    edge from WebKit or subprocess ELFs. It must be an explicit audit root.
    """
    module = runtime / "lib/wpe-webkit-2.0/injected-bundle/libWPEInjectedBundle.so"
    inspector = runtime / "share/wpe-webkit-2.0/inspector.gresource"
    report = runtime / "BUILD-REPORT.txt"
    if not report.exists() and not report.is_symlink():
        if module.exists() or module.is_symlink() or inspector.exists() or inspector.is_symlink():
            raise ValueError("UNDECLARED_INSTALLED_WPE_ASSETS")
        return False, "legacy_assets_not_recorded"
    if report.is_symlink() or not safe_file(report, runtime):
        raise ValueError("INVALID_BUILD_REPORT")
    lines = report.read_text(encoding="utf-8").splitlines()
    profiles = [line.partition("=")[2] for line in lines
                if line.startswith("WPE_INSTALLED_ASSETS_PROFILE=")]
    states = [line.partition("=")[2] for line in lines
              if line.startswith("WPE_INSTALLED_ASSETS_STATUS=")]
    if not profiles and not states:
        if module.exists() or module.is_symlink() or inspector.exists() or inspector.is_symlink():
            raise ValueError("UNDECLARED_INSTALLED_WPE_ASSETS")
        return False, "legacy_assets_not_recorded"
    if len(profiles) != 1 or len(states) != 1:
        raise ValueError("AMBIGUOUS_INSTALLED_WPE_ASSETS")
    profile, state = profiles[0], states[0]
    if profile not in ("strict", "optional") or state not in (
            "not_installed", "copied_and_static_elf_checked"):
        raise ValueError("INVALID_WPE_ASSET_PROFILE_OR_STATE")
    if state == "not_installed":
        if profile == "strict":
            raise ValueError("STRICT_WPE_ASSETS_MISSING")
        if module.exists() or module.is_symlink() or inspector.exists() or inspector.is_symlink():
            raise ValueError("WPE_ASSETS_PRESENT_BUT_UNDECLARED")
        return False, "optional_assets_not_installed"
    # These files must not be accepted via links to host/device paths.
    if module.is_symlink() or inspector.is_symlink() or not safe_file(module, runtime) \
            or not safe_file(inspector, runtime):
        raise ValueError("MISSING_UNSAFE_WPE_MODULE_OR_RESOURCE")
    if module.stat().st_size == 0 or inspector.stat().st_size == 0:
        raise ValueError("EMPTY_WPE_MODULE_OR_RESOURCE")
    for dirname in ("lib/wpe-webkit-2.0/injected-bundle", "share/wpe-webkit-2.0"):
        tree = runtime / dirname
        if tree.is_symlink() or not tree.is_dir():
            raise ValueError("UNSAFE_WPE_ASSET_DIRECTORY")
        if tree.parent.is_symlink():
            raise ValueError("UNSAFE_WPE_ASSET_PARENT")
        for asset in tree.rglob("*"):
            if asset.is_symlink():
                raise ValueError("UNSAFE_WPE_ASSET_CONTENT")
            if asset.is_file():
                if not safe_file(asset, runtime):
                    raise ValueError("ESCAPING_WPE_ASSET_CONTENT")
            elif not asset.is_dir():
                raise ValueError("SPECIAL_WPE_ASSET_CONTENT")
    return True, "strict_assets_audited" if profile == "strict" else "optional_assets_audited"


def check_rpath(paths: list[str]) -> list[str]:
    errors: list[str] = []
    for entries in paths:
        for part in entries.split(":"):
            if (part == "" or "/../" in part or part.endswith("/..")
                    or part.startswith(HOST_PATH_SEGMENTS)):
                errors.append(part or "(empty)")
            elif part.startswith("$ORIGIN"):
                if part != "$ORIGIN" and not part.startswith("$ORIGIN/"):
                    errors.append(part)
            elif part not in ("/lib", "/lib64", "/usr/lib", "/usr/lib64"):
                # RPATH resolution on the handheld is not guaranteed.
                errors.append(part)
    return errors


def audit(runtime: Path, sysroot: Path, stage: Path | None = None,
          elf: Callable[[str, Path], str] = readelf) -> dict:
    runtime = runtime.resolve()
    sysroot = sysroot.resolve()
    if runtime == sysroot or runtime == Path("/") or sysroot == Path("/"):
        raise ValueError("REFUSE_ROOT_OR_OVERLAPPING_INPUTS")
    if stage is not None:
        stage = stage.resolve()
        if stage in (runtime, sysroot, Path("/")):
            raise ValueError("REFUSE_ROOT_OR_OVERLAPPING_INPUTS")
    if not (runtime / "lib").is_dir() or not (runtime / "libexec/wpe-webkit-2.0").is_dir():
        raise ValueError("MISSING_RUNTIME_LAYOUT")
    gpu_required, profile = gpu_process_requirement(runtime)
    injected_required, assets_status = injected_bundle_requirement(runtime)
    root_files = [runtime / "lib/libWPEWebKit-2.0.so.1"]
    if injected_required:
        # WPEInjectedBundle is dynamically loaded and has no guaranteed
        # inbound DT_NEEDED edge. Audit its complete dependency graph.
        root_files.append(runtime / "lib/wpe-webkit-2.0/injected-bundle/libWPEInjectedBundle.so")
    root_files.extend(runtime / f"libexec/wpe-webkit-2.0/{name}" for name in PROCESSES)
    if gpu_required:
        root_files.append(runtime / "libexec/wpe-webkit-2.0/WPEGPUProcess")
    if any(not safe_file(p, runtime) for p in root_files):
        raise ValueError("MISSING_OR_ESCAPING_REQUIRED_RUNTIME_ELF")
    rt_idx, unsafe_rt = index_libraries(runtime)
    sys_idx, unsafe_sys = index_libraries(sysroot)
    stage_idx, unsafe_stage = index_libraries(stage) if stage else ({}, [])
    bad = [f"UNSAFE_LINK:{x}" for x in unsafe_rt]
    bad += [f"UNSAFE_SYSROOT_LINK:{x}" for x in unsafe_sys]
    bad += [f"UNSAFE_STAGE_LINK:{x}" for x in unsafe_stage]
    missing: list[str] = []
    from_build_only: list[str] = []
    edge_count = 0
    symbols = 0
    interpreter_checks = 0
    scanned: set[Path] = set()
    stack = deque(root_files)
    while stack:
        path = stack.popleft()
        actual = path.resolve()
        if actual in scanned:
            continue
        scanned.add(actual)
        try:
            header, dynamic, versions = (elf("-h", path), elf("-d", path), elf("-V", path))
        except ValueError as e:
            bad.append(str(e))
            continue
        if not aarch64(header):
            bad.append(f"INVALID_AARCH64_ELF:{path.name}")
            continue
        if path.name.startswith("libWPEWebKit-2.0.so"):
            found = SONAME.findall(dynamic)
            if found != ["libWPEWebKit-2.0.so.1"]:
                bad.append(f"INVALID_WPE_SONAME:{found}")
        if re.search(r"\(TEXTREL\)", dynamic):
            bad.append(f"TEXTREL:{path.name}")
        # Shared objects have no program interpreter, but Web/Network helper
        # executables with DT_NEEDED must identify a valid target ELF loader.
        # AArch64 headers and NEEDED sonames alone cannot prove that execve()
        # can locate the correct loader on the physical ROCKNIX rootfs.
        if path in root_files and path.name in (*PROCESSES, "WPEGPUProcess"):
            try:
                phdrs = elf("-l", path)
            except ValueError as err:
                bad.append(f"UNREADABLE_PT_INTERP:{path.name}:{err}")
                phdrs = ""
            interpreters = INTERP.findall(phdrs)
            if len(interpreters) > 1:
                bad.append(f"AMBIGUOUS_PT_INTERP:{path.name}")
            elif not interpreters:
                if NEEDED.findall(dynamic):
                    bad.append(f"MISSING_DYNAMIC_PT_INTERP:{path.name}")
            else:
                interpreter_checks += 1
                name = interpreters[0]
                if name not in ROCKNIX_INTERPRETERS:
                    bad.append(f"FOREIGN_PT_INTERP:{path.name}:{name}")
                else:
                    provider = sysroot / name.lstrip("/")
                    if not safe_file(provider, sysroot):
                        bad.append(f"MISSING_SYSROOT_PT_INTERP:{path.name}:{name}")
                    else:
                        try:
                            loader_header = elf("-h", provider)
                            if not aarch64(loader_header):
                                bad.append(f"WRONG_ARCH_PT_INTERP:{path.name}:{name}")
                        except ValueError as err:
                            bad.append(f"UNREADABLE_PT_INTERP_ELF:{path.name}:{err}")
        for major, minor in GLIBC.findall(versions):
            symbols += 1
            if (int(major), int(minor)) > MAX_GLIBC:
                bad.append(f"NEWER_GLIBC:{path.name}:{major}.{minor}")
        for entry in check_rpath(RPATH.findall(dynamic)):
            bad.append(f"UNSAFE_RPATH:{path.name}:{entry}")
        for name in NEEDED.findall(dynamic):
            edge_count += 1
            if "/" in name or ".." in name or not name:
                bad.append(f"UNSAFE_NEEDED:{path.name}:{name}")
                continue
            if name.startswith(("libgst", "libgstreamer")):
                bad.append(f"MEDIA_DISABLED_BUT_GSTREAMER_LINKED:{path.name}:{name}")
            if name in rt_idx:
                stack.append(rt_idx[name])
            elif name in sys_idx:
                stack.append(sys_idx[name])
            elif name in stage_idx:
                from_build_only.append(f"{path.name}:{name}")
                stack.append(stage_idx[name])
            else:
                missing.append(f"{path.name}:{name}")
    # A SONAME available only in the build overlay is NOT a runtime edge.
    # Fail closed even when --strict is called directly outside the bundler.
    status = ("BLOCKED" if bad or missing or from_build_only
              else "SDK_STATIC_CANDIDATES_ONLY")
    return {
        "WPE_RUNTIME_CLOSURE": status,
        "WPE_REQUIRED_PROCESSES": ",".join(PROCESSES + (("WPEGPUProcess",) if gpu_required else ())),
        "WPE_GPU_PROFILE": profile,
        "WPE_INSTALLED_ASSETS_AUDIT": assets_status,
        "WPE_INJECTED_BUNDLE_ELF_AUDITED": "yes" if injected_required else "no",
        "WPE_SCANNED_ELFS": len(scanned),
        "WPE_NEEDED_EDGES": edge_count,
        "WPE_GLIBC_REFERENCES": symbols,
        "WPE_PT_INTERP_CHECKS": interpreter_checks,
        "WPE_PT_INTERP_PROVEN_ON_R36H": "no",
        "WPE_MISSING_SONAMES": sorted(set(missing)),
        "WPE_STAGE_ONLY_DEPENDENCIES": sorted(set(from_build_only)),
        "WPE_ABI_FINDINGS": sorted(set(bad)),
        "WPE_STAGE_ONLY_COUNTS_AS_BLOCKER": "yes",
        "WPE_REAL_DEVICE_LOADER_PROVEN": "no",
        "WPE_GRAPHICS_OR_HTTPS_PROVEN": "no",
        "R36H_INSTALLABLE": "no",
    }


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--runtime", type=Path, required=True)
    p.add_argument("--sysroot", type=Path, required=True)
    p.add_argument("--sdk-stage", type=Path)
    p.add_argument("--report", type=Path)
    p.add_argument("--strict", action="store_true")
    args = p.parse_args()
    for path in (args.runtime, args.sysroot, args.sdk_stage):
        if path is not None and not path.is_dir():
            p.error(f"missing input directory: {path}")
    try:
        findings = audit(args.runtime, args.sysroot, args.sdk_stage)
    except (ValueError, OSError, UnicodeError) as err:
        print(f"WPE_RUNTIME_CLOSURE=ERROR:{err}", file=sys.stderr)
        return 4
    output = []
    for key, value in findings.items():
        if isinstance(value, list):
            output.append(f"{key}_COUNT={len(value)}")
            output.extend(f"{key}={row}" for row in value)
        else:
            output.append(f"{key}={value}")
    report = "\n".join(output) + "\n"
    print(report, end="")
    if args.report:
        if not args.report.parent.is_dir() or args.report.is_symlink():
            p.error("report directory missing or report symlink")
        args.report.write_text(report, encoding="utf-8")
    return 6 if args.strict and findings["WPE_RUNTIME_CLOSURE"] == "BLOCKED" else 0


if __name__ == "__main__":
    sys.exit(main())
