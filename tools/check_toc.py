#!/usr/bin/env python3
"""Validates a WoW addon .toc file without a WoW client.

Checks:
  1. the file name == the parent directory name (client rule)
  2. ## Interface: is present, numeric, and >= an enforced minimum
  3. every expected ## directive is present
  4. every referenced file exists on disk (backslash or slash)

Usage: python3 tools/check_toc.py GideonRaid.toc
Output: exit 0 if OK, 1 otherwise (usable in CI).
"""

from __future__ import annotations

import os
import re
import sys

REQUIRED = ["Interface", "Title", "Notes", "Version"]
MIN_INTERFACE = 120100  # live 12.1.0 "Curse of Ula'tek" (August 2026)


def fail(msg: str) -> None:
    print(f"ECHEC: {msg}")


def main(path: str) -> int:
    errors: list[str] = []
    if not os.path.isfile(path):
        fail(f"{path} introuvable")
        return 1

    addon_dir = os.path.dirname(os.path.abspath(path))
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().splitlines()

    # 1. File name == 'package-as' of .pkgmeta (or parent directory name)
    expected = None
    for candidate in (
        os.path.join(addon_dir, ".pkgmeta"),
        os.path.join(os.path.dirname(addon_dir), ".pkgmeta"),
    ):
        if os.path.isfile(candidate):
            with open(candidate, encoding="utf-8") as fh:
                for line in fh:
                    if line.strip().startswith("package-as:"):
                        expected = line.split(":", 1)[1].strip()
                        break
            break
    if expected is None:
        expected = os.path.basename(addon_dir)
    if os.path.basename(path)[: -len(".toc")] != expected:
        errors.append(f"le nom du .toc doit etre '{expected}' (package-as / nom du dossier)")

    directives: dict[str, str] = {}
    files: list[str] = []
    for lineno, raw in enumerate(lines, 1):
        line = raw.strip()
        if not line:
            continue
        if line.startswith("##"):
            body = line[2:]
            if ":" not in body:
                errors.append(f"ligne {lineno}: directive sans ':' -> {line}")
                continue
            key, _, value = body.partition(":")
            directives[key.strip()] = value.strip()
        elif line.startswith("#"):
            continue
        else:
            files.append(line)

    # 2. Interface
    iface = directives.get("Interface", "")
    if not iface:
        errors.append("## Interface: manquant")
    else:
        for token in (t.strip() for t in iface.split(",")):
            if not token.isdigit():
                errors.append(f"## Interface: valeur non numerique -> '{token}'")
            elif int(token) < MIN_INTERFACE:
                errors.append(f"## Interface: {token} < {MIN_INTERFACE} (addon marque obsolete)")

    # 3. Required directives
    for key in REQUIRED:
        if key not in directives:
            errors.append(f"## {key}: manquant")

    # 4. Referenced files
    if not files:
        errors.append("aucun fichier liste dans le .toc")
    for entry in files:
        rel = entry.replace("\\", os.sep).replace("/", os.sep).strip()
        if re.search(r"\s\[", rel):  # conditional directives [AllowLoad...]
            rel = rel.split("[")[0].strip()
        if "[" in rel:  # [Family]-style variables: cannot be resolved without the client
            continue
        target = os.path.join(addon_dir, rel)
        if not os.path.isfile(target):
            errors.append(f"fichier liste introuvable: {entry}")

    if errors:
        for err in errors:
            fail(err)
        return 1

    print(f"OK {path}")
    print(f"  Interface  : {iface}")
    print(f"  Version    : {directives.get('Version')}")
    print(f"  SavedVar   : {directives.get('SavedVariables')}")
    print(f"  Fichiers   : {len(files)}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
