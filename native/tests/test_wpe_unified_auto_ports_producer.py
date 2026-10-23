#!/usr/bin/env python3
"""Fail-closed proof that experimental Ports packages only trust named WPE runs."""
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[2]
WORK=ROOT/".github/workflows/r36h-first-offline-ports-candidate.yml"
SOURCE="Fire4Nix unified WPE2541 ROCKNIX GCC15 libatomic full link"
BRANCH="build/r36h-unified-wpe2541-gcc15-libatomic-real-20261023"
ARTIFACT="Fire4Nix-ROCKNIX-WPE2541-UNIFIED-GCC15-LIBATOMIC-REAL-STATIC-STAGE"

class VerifiedWpeProducer(unittest.TestCase):
 def setUp(self):
  self.w=WORK.read_text()
 def test_only_successful_same_repo_push_named_branch(self):
  self.assertEqual(self.w.count(SOURCE),2)
  self.assertEqual(self.w.count(BRANCH),2)
  self.assertEqual(self.w.count(ARTIFACT),1)
  for guard in ("data.conclusion !== 'success'","data.event === 'push'",
    "data.head_repository?.full_name !== context.repo.owner + '/' + context.repo.repo",
    "data.head_branch === '"+BRANCH+"'",
    "github.event.workflow_run.conclusion == 'success'",
    "github.event.workflow_run.head_repository.full_name == github.repository",
    "github.event.workflow_run.head_branch == '"+BRANCH+"'"):
   self.assertIn(guard,self.w)
 def test_no_packages_from_failed_or_mock_runs(self):
  self.assertIn("const unifiedAuthorized =",self.w)
  self.assertIn("!(oldAuthorized || gcc15Authorized || unifiedAuthorized)",self.w)
  self.assertIn("python3 scripts/resolve-wpe-runtime-download.py",self.w)
  self.assertIn("python3 scripts/package-first-r36h-ports-candidate.py",self.w)
  self.assertIn("R36H_HARDWARE_TESTED=no",self.w)

if __name__=="__main__": unittest.main(verbosity=2)
