#!/usr/bin/env python3
"""Publie une nouvelle version d'Arcanum.

  python tools/release.py 1.7.2

1. met le numéro de version à jour (Arcanum.toc et Core.lua) ;
2. vérifie que CHANGELOG.md a une section « ## 1.7.2 » ;
3. lance le banc de test (rien n'est publié s'il échoue) ;
4. crée le commit et l'étiquette v1.7.2, puis pousse sur GitHub.

GitHub Actions fabrique alors le zip et la release (.github/workflows/release.yml),
et WowUp propose la mise à jour à tous ceux qui ont installé Arcanum depuis le dépôt.

Options : --dry-run (tout sauf le commit et l'envoi), --trailer "Ligne" (ajoutée au message du commit).
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
        sys.exit("ERREUR : motif introuvable dans %s" % path)
    io.open(full, "w", encoding="utf-8", newline="").write(new)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("version")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--trailer", action="append", default=[])
    args = parser.parse_args()
    version = args.version
    if not re.match(r"^\d+\.\d+\.\d+$", version):
        sys.exit("ERREUR : version attendue au format X.Y.Z")

    tags = subprocess.run(["git", "tag", "--list", "v" + version], cwd=ROOT, capture_output=True, text=True).stdout
    if tags.strip():
        sys.exit("ERREUR : la version %s existe déjà" % version)
    changelog = io.open(os.path.join(ROOT, "CHANGELOG.md"), encoding="utf-8").read()
    if not re.search(r"^## %s\b" % re.escape(version), changelog, re.M):
        sys.exit("ERREUR : ajoute d'abord une section « ## %s » dans CHANGELOG.md" % version)

    replace_in("Arcanum/Arcanum.toc", r"^## Version: .*$", "## Version: " + version)
    replace_in("Arcanum/Core.lua", r'or "\d+\.\d+\.\d+"$', 'or "%s"' % version)

    env = dict(os.environ, PYTHONIOENCODING="utf-8")
    run([sys.executable, os.path.join("tools", "test", "run_tests.py")], env=env)
    run([sys.executable, os.path.join("tools", "package.py"), version])

    if args.dry_run:
        print("Essai à blanc terminé : rien n'a été envoyé.")
        return
    message = "Arcanum %s" % version
    if args.trailer:
        message += "\n\n" + "\n".join(args.trailer)
    run(["git", "add", "-A"])
    run(["git", "commit", "-m", message])
    run(["git", "tag", "-a", "v" + version, "-m", "Arcanum " + version])
    run(["git", "push", "origin", "HEAD"])
    run(["git", "push", "origin", "v" + version])
    print("Version %s envoyée : GitHub Actions publie la release." % version)


if __name__ == "__main__":
    main()
