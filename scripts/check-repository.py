#!/usr/bin/env python3
"""Review Git blobs, never runtime data. This complements manual content review."""
import argparse
from pathlib import PurePosixPath
import re
import subprocess
import sys

EXACT = {
    '.gitignore', 'AGENTS.md', 'Package.swift', 'README.md', 'README.en.md',
    'CONTRIBUTING.md', 'CHANGELOG.md', 'docs/REQUIREMENTS.md',
    'scripts/build.sh', 'scripts/make-icon.swift', 'scripts/check-repository.py',
    'scripts/test-repository-check.py', '.githooks/pre-commit', '.githooks/pre-push',
    '.github/workflows/ci.yml',
}
PRIVATE_PARTS = {'Thread_kevin', 'Jev_kevin', '.thread', '笔记', '验证', 'dist', '.build', '.swiftpm', '__pycache__'}
PATTERNS = [
    ('personal absolute path', re.compile(r'/(?:Users|home)/[A-Za-z0-9._-]+/')),
    ('private key', re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----')),
    ('GitHub credential', re.compile(r'\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{30,})\b')),
    ('AWS access key', re.compile(r'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b')),
    ('service credential', re.compile(r'\b(?:sk-(?:proj-)?[A-Za-z0-9_-]{24,}|xox[baprs]-[A-Za-z0-9-]{20,})\b')),
    ('serialized personal task', re.compile(r'\A\s*---\s*\n\s*\{[\s\S]*?"(?:activeOrder|schemaVersion)"\s*:')),
]

def git(*args):
    return subprocess.check_output(['git', *args], stderr=subprocess.PIPE)

def allowed(path):
    p = PurePosixPath(path)
    if any(part in PRIVATE_PARTS for part in p.parts):
        return False
    if p.name == '总览.md' or re.fullmatch(r'\d{6,}\.md', p.name):
        return False
    if path in EXACT:
        return True
    return len(p.parts) >= 3 and p.parts[0] in {'Sources', 'Tests'} and p.suffix == '.swift'

def entries(history):
    if not history:
        for row in git('ls-files', '--stage', '-z').split(b'\0'):
            if not row:
                continue
            info, raw_path = row.split(b'\t', 1)
            mode, oid, stage = info.decode().split()
            yield mode, oid, raw_path.decode('utf-8'), stage
    else:
        seen = set()
        for revision in git('rev-list', '--all').decode().splitlines():
            for row in git('ls-tree', '-r', '-z', revision).split(b'\0'):
                if not row:
                    continue
                info, raw_path = row.split(b'\t', 1)
                mode, kind, oid = info.decode().split()
                entry = (mode, oid, raw_path.decode('utf-8'), '0')
                if entry not in seen:
                    seen.add(entry)
                    yield entry

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--all-history', action='store_true', help='Check every tree reachable from local refs, including deleted historical files.')
    args = parser.parse_args()
    failures = []
    inspected = 0
    cache = {}
    try:
        for mode, oid, path, stage in entries(args.all_history):
            inspected += 1
            # repr escapes control characters; never print offending content.
            label = repr(path)
            if not allowed(path):
                failures.append(label + ': unapproved or private path')
                continue
            if stage != '0' or mode not in {'100644', '100755'}:
                failures.append(label + ': unresolved entry, symlink, or submodule')
                continue
            if oid not in cache:
                reasons = []
                size = int(git('cat-file', '-s', oid))
                if size > 1024 * 1024:
                    reasons.append('file exceeds 1 MiB review limit')
                else:
                    data = git('cat-file', 'blob', oid)
                    try:
                        content = data.decode('utf-8')
                        if '\0' in content:
                            reasons.append('binary content')
                        reasons.extend(name for name, pattern in PATTERNS if pattern.search(content))
                    except UnicodeDecodeError:
                        reasons.append('non-UTF-8 content')
                cache[oid] = reasons
            failures.extend(label + ': ' + reason for reason in cache[oid])
    except (subprocess.CalledProcessError, ValueError, UnicodeError) as error:
        print('Repository check could not complete: ' + type(error).__name__, file=sys.stderr)
        return 2
    if failures:
        print('Repository check FAILED (contents withheld):', file=sys.stderr)
        for failure in sorted(set(failures)):
            print(' - ' + failure, file=sys.stderr)
        return 1
    if inspected == 0:
        print('Repository check FAILED: no Git files inspected.', file=sys.stderr)
        return 1
    scope = 'all reachable history' if args.all_history else 'staged index'
    print(f'Repository check passed: {inspected} file versions in {scope}. Manual content review is still required.')
    return 0

if __name__ == '__main__':
    sys.exit(main())
