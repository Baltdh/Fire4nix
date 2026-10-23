#!/usr/bin/env python3
"""Unit regressions for SHA256-only recovery after GitHub artifact download."""
import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest

SCRIPT=Path(__file__).resolve().parents[2]/"scripts/materialize-wpe-artifact-sonames.py"
spec=importlib.util.spec_from_file_location("wpe_recover",SCRIPT)
wpe=importlib.util.module_from_spec(spec)
spec.loader.exec_module(wpe)


class DownloadedRuntimeAliasTests(unittest.TestCase):
    def setUp(self):
        tmp=tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root=Path(tmp.name)
        self.download=self.root/"download"
        self.download.mkdir()
        self.runtime=self.download/"private-wpe-runtime-sdk-closed"
        for relative in wpe.REQUIRED:
            target=self.runtime/relative
            target.parent.mkdir(parents=True,exist_ok=True)
            if relative!="lib/libWPEWebKit-2.0.so.1":
                target.write_bytes(("fixture for "+relative).encode())
        self.versioned=self.runtime/"lib/libWPEWebKit-2.0.so.1.11.4"
        self.versioned.write_bytes(b"genuine-hashed-libwebkit-content-fixture")
        self.manifest=self.runtime/"SHA256SUMS.txt"
        entries=["lib/libWPEWebKit-2.0.so.1",
                 "libexec/wpe-webkit-2.0/WPEWebProcess",
                 "libexec/wpe-webkit-2.0/WPENetworkProcess",
                 "lib/wpe-webkit-2.0/injected-bundle/libWPEInjectedBundle.so",
                 "share/wpe-webkit-2.0/inspector.gresource"]
        rows=[]
        for path in entries:
            data=(self.versioned if path=="lib/libWPEWebKit-2.0.so.1"
                  else self.runtime/path).read_bytes()
            rows.append(hashlib.sha256(data).hexdigest()+"  "+path)
        self.manifest.write_text("\n".join(rows)+"\n")
        self.out=self.root/"independent-verified-runtime"

    def test_rebuilds_only_alias_matching_manifest_exactly(self):
        result=wpe.materialize(self.download,self.out)
        self.assertEqual(result["repaired"],["lib/libWPEWebKit-2.0.so.1"])
        self.assertEqual((self.out/"lib/libWPEWebKit-2.0.so.1").read_bytes(),
                         self.versioned.read_bytes())
        self.assertFalse((self.runtime/"lib/libWPEWebKit-2.0.so.1").exists())
        self.assertEqual(len(wpe.manifest_entries(self.out)),5)

    def test_flattened_artifact_already_contains_alias(self):
        (self.runtime/"lib/libWPEWebKit-2.0.so.1").write_bytes(
            self.versioned.read_bytes())
        self.assertEqual(wpe.materialize(self.download,self.out)["repaired"],[])

    def test_legacy_prefixed_artifact_layout(self):
        old=self.download/"wpe-unified-sdk-build"
        old.mkdir()
        self.runtime.rename(old/self.runtime.name)
        self.assertEqual(len(wpe.materialize(self.download,self.out)["repaired"]),1)

    def test_corrupted_versioned_target_rejected_without_output(self):
        self.versioned.write_bytes(b"tampered content")
        with self.assertRaisesRegex(ValueError,"NO_UNIQUE_SHA256_PROVEN_SONAME"):
            wpe.materialize(self.download,self.out)
        self.assertFalse(self.out.exists())

    def test_multiple_same_digest_candidates_are_ambiguous(self):
        (self.runtime/"lib/libWPEWebKit-2.0.so.1.42").write_bytes(
            self.versioned.read_bytes())
        with self.assertRaisesRegex(ValueError,"NO_UNIQUE_SHA256_PROVEN_SONAME"):
            wpe.materialize(self.download,self.out)
        self.assertFalse(self.out.exists())

    def test_missing_process_is_not_reconstructed(self):
        (self.runtime/"libexec/wpe-webkit-2.0/WPEWebProcess").unlink()
        with self.assertRaisesRegex(ValueError,"UNRECOVERABLE_MISSING_HASHED_FILE"):
            wpe.materialize(self.download,self.out)

    def test_symlink_to_host_is_rejected(self):
        self.versioned.unlink()
        self.versioned.symlink_to("/etc/passwd")
        with self.assertRaisesRegex(ValueError,"SYMLINKED_DOWNLOADED_RUNTIME"):
            wpe.materialize(self.download,self.out)

    def test_duplicate_artifact_layout_is_rejected(self):
        prefixed=self.download/"wpe-unified-sdk-build/private-wpe-runtime-sdk-closed"
        prefixed.mkdir(parents=True)
        with self.assertRaisesRegex(ValueError,"EXPECTED_EXACTLY_ONE"):
            wpe.materialize(self.download,self.out)

    def test_manifest_traversal_is_rejected(self):
        self.manifest.write_text(hashlib.sha256(b"x").hexdigest()+"  ../etc/passwd\n")
        with self.assertRaisesRegex(ValueError,"UNSAFE_OR_DUPLICATE_RUNTIME_HASH_PATH"):
            wpe.materialize(self.download,self.out)

    def test_never_overwrites_prior_output(self):
        self.out.mkdir()
        with self.assertRaisesRegex(ValueError,"REFUSE_TO_OVERWRITE"):
            wpe.materialize(self.download,self.out)


if __name__=="__main__":
    unittest.main(verbosity=2)
