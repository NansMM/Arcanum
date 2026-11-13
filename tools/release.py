#!/usr/bin/env python3
"""Publishes a new version of Arcanum.

  python tools/release.py 1.7.2

1. updates the version number (Arcanum.toc and Core.lua);
2. checks that CHANGELOG.md has a "## 1.7.2" section;
3. runs the test suite (nothing is published if it fails);
4. creates the commit and the v1.7.2 tag, then pushes to GitHub.

GitHub Actions then builds the zip and the release (.github/workflows/release.yml),
and WowUp offers the update to everyone who installed Arcanum from the repository.

Options: --dry-run (everything except the commit and the push), --trailer "Line" (appended to the commit message).
"""
import argparse
import io
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run(cmd, **kw):
    print("> " + " ".join(cmd))
    return subprocess.run(cmd, cwd=ROOT, check=True, **kw)


def replace_in(path, pattern, repl):
    full = os.path.join(ROOT, path)
    text = io.open(full, encoding="utf-8").read()
    new, n = re.subn(pattern, repl, text, count=1, flags=re.M)
    if n != 1:
        sys.exit("ERROR: pattern not found in %s" % path)
    io.open(full, "w", encoding="utf-8", newline="").write(new)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("version")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--trailer", action="append", default=[])
    args = parser.parse_args()
    version = args.version
    if not re.match(r"^\d+\.\d+\.\d+$", version):
        sys.exit("ERROR: version must be in X.Y.Z format")

    tags = subprocess.run(["git", "tag", "--list", "v" + version], cwd=ROOT, capture_output=True, text=True).stdout
    if tags.strip():
        sys.exit("ERROR: version %s already exists" % version)
    changelog = io.open(os.path.join(ROOT, "CHANGELOG.md"), encoding="utf-8").read()
    if not re.search(r"^## %s\b" % re.escape(version), changelog, re.M):
        sys.exit('ERROR: add a "## %s" section to CHANGELOG.md first' % version)

    replace_in("Arcanum/Arcanum.toc", r"^## Version: .*$", "## Version: " + version)
    replace_in("Arcanum/Core.lua", r'or "\d+\.\d+\.\d+"$', 'or "%s"' % version)

    env = dict(os.environ, PYTHONIOENCODING="utf-8")
    run([sys.executable, os.path.join("tools", "test", "run_tests.py")], env=env)
    run([sys.executable, os.path.join("tools", "package.py"), version])

    if args.dry_run:
        print("Dry run complete: nothing was pushed.")
        return
    message = "Arcanum %s" % version
    if args.trailer:
        message += "\n\n" + "\n".join(args.trailer)
    run(["git", "add", "-A"])
    run(["git", "commit", "-m", message])
    run(["git", "tag", "-a", "v" + version, "-m", "Arcanum " + version])
    run(["git", "push", "origin", "HEAD"])
    run(["git", "push", "origin", "v" + version])
    print("Version %s pushed: GitHub Actions is publishing the release." % version)


if __name__ == "__main__":
    main()
