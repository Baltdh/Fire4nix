#!/usr/bin/env python3
"""Regression tests for the build-only WPE transitive dependency inventory."""
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile

MODULE = Path(__file__).with_name("audit_wpe_dependency_closure.py")
spec = importlib.util.spec_from_file_location("closure", MODULE)
closure = importlib.util.module_from_spec(spec)
spec.loader.exec_module(closure)


def check(condition, why):
    if not condition:
        raise AssertionError(why)


def main():
    sample = """
        linux-vdso.so.1 (0x0000)
        libwebkit.so.2 => /usr/lib/libwebkit.so.2 (0x000a)
        libc.so.6 => /usr/lib/libc.so.6 (0x0030)
        /lib/ld-linux-aarch64.so.1 (0x0091)
    """
    found, missing, unknown = closure.parse_ldd(sample)
    check(found["libwebkit.so.2"] == "/usr/lib/libwebkit.so.2", "ldd library parsing")
    check(found["ld-linux-aarch64.so.1"] == "/lib/ld-linux-aarch64.so.1",
          "dynamic loader parsing")
    check(not missing and not unknown, "valid ldd output treated as failure")
    found, missing, unknown = closure.parse_ldd("libmissing.so.9 => not found")
    check(missing == ["libmissing.so.9"], "missing library accepted")
    check(not found and not unknown, "missing output parse mismatch")
    try:
        closure.parse_ldd("libbad;rm => /usr/lib/libbad.so (0x20)")
    except ValueError:
        pass
    else:
        raise AssertionError("invalid SONAME accepted")

    with tempfile.TemporaryDirectory(prefix="wpe-dependency-test-") as tmp:
        root = Path(tmp)
        launcher = root / "launcher"
        webkit = root / "libWPEWebKit-2.0.so"
        proc = root / "libexec"
        proc.mkdir()
        roots = {"launcher": launcher, "WPEWebKit": webkit}
        for role in closure.PROCESSES:
            roots[role] = proc / role
        for path in roots.values():
            shutil.copy2("/bin/true", path)
        machine = int.from_bytes(launcher.read_bytes()[18:20], "little")
        manifest = {
            "schema": "fire4nix-wpe-abi-v1",
            "expected_elf_machine": machine,
            "components": {role: {"needed": ["libc.so.6"]} for role in closure.ROLES}
        }
        data = closure.inspect(roots, manifest, machine)
        check(data["schema"] == "fire4nix-wpe-dependency-closure-v1", "schema")
        check("libc.so.6" in data["all_system_sonames"], "libc dependency not recorded")
        check(len(data["components"]) == 5, "component inventory incomplete")
        check("UNVERIFIED" in data["qualification"], "device warning absent")
        check(len(data["build_provider_paths"]) == len(data["all_system_sonames"]),
              "unresolved dependency origin")
        mismatch = dict(manifest)
        mismatch["expected_elf_machine"] = -1
        try:
            closure.inspect(roots, mismatch, machine)
        except ValueError as exc:
            check("architecture" in str(exc), "wrong failure cause")
        else:
            raise AssertionError("ABI architecture mismatch passed")
        changed = dict(manifest)
        changed["components"] = {role: {"needed": ["libnotpresent.so.0"]}
                                 for role in closure.ROLES}
        try:
            closure.inspect(roots, changed, machine)
        except ValueError as exc:
            check("direct NEEDED" in str(exc), "missing required dependency not reported")
        else:
            raise AssertionError("missing DT_NEEDED silently accepted")
        (proc / "WPEGPUProcess").unlink()
        try:
            closure.inspect(roots, manifest, machine)
        except (OSError, ValueError):
            pass
        else:
            raise AssertionError("missing process was accepted")
    print("PASS: parsed ldd, dynamic loader, missing deps, ELF roles, machine and device disclaimer")


if __name__ == "__main__":
    main()
