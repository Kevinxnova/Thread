#!/usr/bin/env python3
"""Exercise publication safeguards using disposable synthetic Git repositories."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile
import unittest

CHECKER = Path(__file__).with_name('check-repository.py').resolve()

class RepositoryCheckTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='thread-repository-test-')
        self.root = Path(self.temp.name)
        self.git('init', '-q')
        self.git('config', 'user.name', 'Synthetic Test')
        self.git('config', 'user.email', 'test@example.invalid')
        self.git('config', 'core.hooksPath', str(self.root/'no-hooks'))
        self.git('config', 'commit.gpgsign', 'false')

    def tearDown(self):
        self.temp.cleanup()

    def git(self, *args):
        return subprocess.run(['git', *args], cwd=self.root, check=True, capture_output=True)

    def stage(self, name, body):
        path = self.root/name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(body.encode() if isinstance(body, str) else body)
        self.git('add', '--', name)
        return path

    def check(self, ok, *args):
        result = subprocess.run([sys.executable, str(CHECKER), *args], cwd=self.root, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0 if ok else 1, result.stdout+result.stderr)
        return result

    def test_reviewed_source_and_documentation_pass(self):
        self.stage('Sources/ThreadCore/Example.swift', 'import Foundation\n')
        self.stage('README.md', '# Synthetic project\n')
        self.check(True)

    def test_personal_notes_and_logs_rejected(self):
        for name in ['Thread_kevin/笔记/000001.md', '验证/runtime.log', 'docs/private.md', 'Sources/ThreadCore/笔记/Note.swift']:
            self.stage(name, 'Synthetic private data')
        self.check(False)

    def test_staged_content_checked_even_if_worktree_is_clean(self):
        path = self.stage('Sources/ThreadCore/Example.swift', '// ' + '/Users/' + 'synthetic-private/' + 'note.md')
        path.write_text('import Foundation\n')
        self.check(False)

    def test_credential_rejected_without_echoing_value(self):
        token = 'ghp_' + 'A'*36
        self.stage('README.md', token)
        result = self.check(False)
        self.assertNotIn(token, result.stdout+result.stderr)

    def test_binary_and_symlink_rejected(self):
        self.stage('Sources/ThreadCore/Example.swift', b'\x00\x01')
        self.check(False)
        self.git('rm', '-q', '-f', '--', 'Sources/ThreadCore/Example.swift')
        path = self.root/'Sources/ThreadCore/Link.swift'
        path.parent.mkdir(parents=True, exist_ok=True)
        os.symlink('missing-target', path)
        self.git('add', '--', str(path.relative_to(self.root)))
        self.check(False)

    def test_deleted_historical_data_still_rejected(self):
        self.stage('README.md', '# Safe introduction\n')
        self.git('commit', '-qm', 'Safe baseline')
        self.stage('笔记/000001.md', 'Synthetic private note')
        self.git('commit', '-qm', 'Synthetic bad commit')
        self.git('rm', '-q', '--', '笔记/000001.md')
        self.git('commit', '-qm', 'Remove synthetic note')
        self.check(True)
        self.check(False, '--all-history')

    def test_serialized_note_disguised_as_source_rejected(self):
        self.stage('Sources/ThreadCore/Example.swift', '---\n{"schemaVersion":1,"goal":"synthetic"}\n---\nsynthetic')
        self.check(False)

    def test_oversized_file_rejected(self):
        self.stage('README.md', 'a'*(1024*1024+1))
        self.check(False)

    def test_empty_index_does_not_claim_success(self):
        self.check(False)

if __name__ == '__main__':
    unittest.main()
