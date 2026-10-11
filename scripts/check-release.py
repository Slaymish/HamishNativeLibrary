#!/usr/bin/env python3
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parent.parent
version = sys.argv[1] if len(sys.argv) == 2 else ''
if not re.fullmatch(r'\d+\.\d+\.\d+', version):
    sys.exit('Usage: check-release.py MAJOR.MINOR.PATCH')
if (root / 'VERSION').read_text().strip() != version:
    sys.exit('Tag/version mismatch: update VERSION before tagging')
changelog = (root / 'CHANGELOG.md').read_text()
match = re.search(r'^## \[' + re.escape(version) + r'\] - \d{4}-\d{2}-\d{2}\n(.*?)(?=^## |\Z)', changelog, re.M | re.S)
if not match or not match.group(1).strip():
    sys.exit('Release needs a dated, nonempty CHANGELOG.md section')
print(match.group(1).strip())
