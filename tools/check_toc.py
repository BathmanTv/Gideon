#!/usr/bin/env python3
"""Valide un fichier .toc d'addon WoW sans client WoW.

Verifie :
  1. le nom du fichier == nom du dossier parent (regle du client)
  2. ## Interface: est present, numerique, et >= un minimum impose
  3. chaque directive ## attendue est presente
  4. chaque fichier reference existe sur le disque (avec backslash ou slash)

Usage: python3 tools/check_toc.py GideonRaid/GideonRaid.toc
Sortie: exit 0 si OK, 1 sinon (utilisable en CI).
"""

from __future__ import annotations

import os
import re
import sys

REQUIRED = ["Interface", "Title", "Notes", "Version"]
MIN_INTERFACE = 120100  # live 12.1.0 "Curse of Ula'tek" (aout 2026)


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

    # 1. Nom du fichier == dossier parent
    if os.path.basename(path)[: -len(".toc")] != os.path.basename(addon_dir):
        errors.append("le nom du .toc doit etre identique au nom du dossier parent")

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

    # 3. Directives obligatoires
    for key in REQUIRED:
        if key not in directives:
            errors.append(f"## {key}: manquant")

    # 4. Fichiers references
    if not files:
        errors.append("aucun fichier liste dans le .toc")
    for entry in files:
        rel = entry.replace("\\", os.sep).replace("/", os.sep).strip()
        if re.search(r"\s\[", rel):  # directives conditionnelles [AllowLoad...]
            rel = rel.split("[")[0].strip()
        if "[" in rel:  # variables type [Family] : on ne peut pas resoudre hors client
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
