#!/usr/bin/env python3
"""Bundle ONLY verified AArch64 WPE dependencies absent from the ROCKNIX sysroot.

The inputs are a real staged WPE runtime, the exact immutable ROCKNIX RK3326
toolchain sysroot, and the independently audited AArch64 SDK library stage.
Never execute target ELFs or read shared libraries from host /usr. Never modify
the input runtime, the SDK, the sysroot or the device. No installable claims.
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile

MAX_LIBRARIES = 128
MAX_ROUNDS = 24


def import_auditor():
    file = Path(__file__).resolve().with_name("audit-wpe-runtime-closure.py")
    if not file.is_file():
        raise ValueError("MISSING_PINNED_CLOSURE_AUDITOR")
    spec = importlib.util.spec_from_file_location("fire4nix_closure", file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as src:
        for chunk in iter(lambda: src.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def validated_stage_elf(mod, soname: str, source: Path, stage: Path) -> None:
    if not soname or "/" in soname or ".." in soname:
        raise ValueError("INVALID_NEEDED_NAME:" + soname)
    if not mod.safe_file(source, stage):
        raise ValueError("ESCAPING_OR_BROKEN_STAGE_ELF:" + soname)
    h = mod.readelf("-h", source)
    d = mod.readelf("-d", source)
    v = mod.readelf("-V", source)
    if not mod.aarch64(h) or not re.search(r"Type:\s+DYN\b", h):
        raise ValueError("FOREIGN_OR_NONSHARED_STAGE_ELF:" + soname)
    if mod.SONAME.findall(d) != [soname]:
        raise ValueError("STAGE_ELF_SONAME_MISMATCH:" + soname)
    if mod.check_rpath(mod.RPATH.findall(d)):
        raise ValueError("UNSAFE_STAGE_ELF_RPATH:" + soname)
    if re.search(r"\(TEXTREL\)", d):
        raise ValueError("STAGE_ELF_TEXTREL:" + soname)
    if any((int(a), int(b)) > mod.MAX_GLIBC for a, b in mod.GLIBC.findall(v)):
        raise ValueError("STAGE_ELF_GLIBC_ABOVE_2_41:" + soname)
    for needed in mod.NEEDED.findall(d):
        if not needed or "/" in needed or ".." in needed:
            raise ValueError("UNSAFE_STAGE_NEEDED:" + soname)
        if needed.startswith(("libgst", "libgstreamer")):
            raise ValueError("GSTREAMER_STAGE_NEEDED:" + soname)


def ensure_safe_paths(runtime: Path, sysroot: Path, stage: Path, output: Path) -> None:
    for p in (runtime, sysroot, stage):
        if not p.is_dir() or p.is_symlink() or p.resolve() == Path("/"):
            raise ValueError("UNSAFE_OR_MISSING_INPUT_DIRECTORY:" + str(p))
    if output.is_symlink() or output.exists():
        raise ValueError("REFUSE_TO_REPLACE_OUTPUT")
    if not output.parent.is_dir() or output.parent.is_symlink():
        raise ValueError("OUTPUT_PARENT_MUST_EXIST_AND_NOT_BE_LINK")
    all_roots = [p.resolve() for p in (runtime, sysroot, stage)]
    if len(set(all_roots)) != 3:
        raise ValueError("OVERLAPPING_INPUT_ROOTS")
    resolved_output = output.resolve()
    if any(resolved_output == p or resolved_output.is_relative_to(p)
           or p.is_relative_to(resolved_output) for p in all_roots):
        raise ValueError("OVERLAPPING_OUTPUT_AND_INPUT_ROOTS")


def bundle(runtime: Path, sysroot: Path, stage: Path, output: Path, mod=None) -> dict:
    ensure_safe_paths(runtime, sysroot, stage, output)
    mod = mod or import_auditor()
    indexed, unsafe = mod.index_libraries(stage)
    if unsafe:
        raise ValueError("UNSAFE_STAGE_SONAME_LINKS:" + ",".join(unsafe[:8]))
    copied: dict[str, tuple[str, str]] = {}
    rounds = 0
    with tempfile.TemporaryDirectory(prefix=".fire4nix-private-deps-", dir=output.parent) as scratch:
        working = Path(scratch) / "runtime"
        shutil.copytree(runtime, working, symlinks=True)
        while rounds < MAX_ROUNDS:
            rounds += 1
            result = mod.audit(working, sysroot, stage)
            if result["WPE_ABI_FINDINGS"] or result["WPE_MISSING_SONAMES"]:
                raise ValueError(
                    "STATIC_CLOSURE_ERRORS:"
                    + "|".join((result["WPE_ABI_FINDINGS"]
                                + result["WPE_MISSING_SONAMES"])[:12]))
            stage_only = result["WPE_STAGE_ONLY_DEPENDENCIES"]
            if not stage_only:
                if result["WPE_RUNTIME_CLOSURE"] != "SDK_STATIC_CANDIDATES_ONLY":
                    raise ValueError("CLOSURE_NOT_COMPLETE")
                break
            wanted = sorted({entry.rsplit(":", 1)[-1] for entry in stage_only})
            if len(copied) + len(wanted) > MAX_LIBRARIES:
                raise ValueError("SDK_DEPENDENCY_BUNDLE_TOO_LARGE")
            count = 0
            for name in wanted:
                if name in copied or (working / "lib" / name).exists():
                    raise ValueError("UNRESOLVED_OR_DUPLICATE_SDK_DEPENDENCY:" + name)
                src = indexed.get(name)
                if src is None:
                    raise ValueError("STAGE_ONLY_LIBRARY_NOT_INDEXED:" + name)
                validated_stage_elf(mod, name, src, stage)
                dest = working / "lib" / name
                shutil.copyfile(src.resolve(strict=True), dest)
                shutil.copymode(src.resolve(strict=True), dest)
                copied[name] = (str(src.relative_to(stage)), sha256(dest))
                count += 1
            if count == 0:
                raise ValueError("NO_BUNDLE_PROGRESS")
        else:
            raise ValueError("SDK_DEPENDENCY_BUNDLE_ITERATION_LIMIT")

        # Recheck the actual output after every copied SONAME (including
        # recursive SDK-only dependencies); never silently treat stage as device.
        final = mod.audit(working, sysroot, stage)
        if final["WPE_RUNTIME_CLOSURE"] != "SDK_STATIC_CANDIDATES_ONLY" \
                or final["WPE_STAGE_ONLY_DEPENDENCIES"] \
                or final["WPE_MISSING_SONAMES"] or final["WPE_ABI_FINDINGS"]:
            raise ValueError("BUNDLED_RUNTIME_DID_NOT_CLOSE")
        manifest = working / "SHA256SUMS.txt"
        if manifest.exists() and (not manifest.is_file() or manifest.is_symlink()):
            raise ValueError("UNSAFE_EXISTING_CHECKSUM_MANIFEST")
        with manifest.open("a", encoding="utf-8") as f:
            for name in sorted(copied):
                f.write(f"{copied[name][1]}  lib/{name}\n")
        report = [
            "ROCKNIX_PRIVATE_SDK_ELF_BUNDLE=PASS_STATIC_SONAMES_ONLY",
            f"ROCKNIX_SDK_BUNDLED_LIBRARIES={len(copied)}",
            f"ROCKNIX_SDK_BUNDLE_ROUNDS={rounds}",
            f"WPE_RUNTIME_CLOSURE={final['WPE_RUNTIME_CLOSURE']}",
            f"WPE_INJECTED_BUNDLE_ELF_AUDITED={final['WPE_INJECTED_BUNDLE_ELF_AUDITED']}",
            "WPE_REAL_DEVICE_ABI_PROVEN=no",
            "WEBKIT_RENDERED_ON_R36H=no",
            "R36H_INSTALLABLE=no",
            "TARGET_EXECUTED=no",
        ]
        for name in sorted(copied):
            origin, digest = copied[name]
            report.append(f"SDK_BUNDLED_LIBRARY={name}:sha256={digest}:source={origin}")
        (working / "SDK-BUNDLE-REPORT.txt").write_text("\n".join(report) + "\n")
        if output.exists():
            raise ValueError("REFUSE_RACED_OUTPUT_REPLACEMENT")
        os.rename(working, output)
    return {"copied": sorted(copied), "rounds": rounds, "closure": final["WPE_RUNTIME_CLOSURE"]}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--sysroot", type=Path, required=True)
    parser.add_argument("--sdk-stage", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        outcome = bundle(args.runtime, args.sysroot, args.sdk_stage, args.output)
    except (OSError, ValueError, RuntimeError) as exc:
        print(f"ROCKNIX_PRIVATE_SDK_ELF_BUNDLE=BLOCKED:{exc}", file=sys.stderr)
        return 6
    print("ROCKNIX_PRIVATE_SDK_ELF_BUNDLE=PASS_STATIC_SONAMES_ONLY")
    print("ROCKNIX_SDK_BUNDLED_LIBRARIES=" + str(len(outcome["copied"])))
    print("WPE_RUNTIME_CLOSURE=" + outcome["closure"])
    print("R36H_INSTALLABLE=no")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
