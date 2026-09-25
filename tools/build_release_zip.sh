#!/usr/bin/env bash
# Build the GideonRaid release zip locally, exactly like the BigWigs packager
# would (same layout as the previous releases): package-as GideonRaid/, the
# addon files only, @project-version@ substituted, and NO backup file ever.
#
# Usage: tools/build_release_zip.sh 0.13.4 [output-dir]
set -euo pipefail

VERSION="${1:?usage: build_release_zip.sh <version> [output-dir]}"
OUT_DIR="${2:-/root/Gideon/releases}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

DEST="$STAGE/GideonRaid"
mkdir -p "$DEST"

copy() {
    local rel="$1"
    case "$rel" in
        *.bak | *~ | *.orig | *.rej | *.swp | *.tmp)
            echo "REFUSED (backup/temp file): $rel" >&2
            exit 1
            ;;
    esac
    mkdir -p "$DEST/$(dirname "$rel")"
    cp "$ROOT/$rel" "$DEST/$rel"
}

# 1. the .toc itself, version substituted (this is what makes the shipped zip
#    declare 0.13.4 instead of the CI placeholder).
sed "s/@project-version@/$VERSION/g" "$ROOT/GideonRaid.toc" > "$DEST/GideonRaid.toc"
if grep -q "@project-version@" "$DEST/GideonRaid.toc"; then
    echo "the placeholder survived the substitution" >&2
    exit 1
fi

# 2. every file the .toc lists (lua, ogg, tga) - the ONLY source of truth of what
#    the client must load - plus Bindings.xml, the changelog and the metadata docs.
mapfile -t LISTED < <(awk '/^[^#]/ && NF { gsub(/\\/, "/"); print }' "$ROOT/GideonRaid.toc")
for rel in "${LISTED[@]}"; do
    copy "$rel"
done
# the .toc lists no Bindings.xml and no CHANGELOG.md: they are packaged anyway
# (the client reads Bindings.xml at the root, CurseForge reads the changelog).
copy "Bindings.xml"
copy "CHANGELOG.md"

# 3. a final safety net: nothing that looks like an editor leftover.
if find "$DEST" -name '*.bak' -o -name '*~' -o -name '*.orig' -o -name '*.rej' | grep -q .; then
    echo "a backup file slipped into the package" >&2
    exit 1
fi

mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR/GideonRaid-v$VERSION.zip"
( cd "$STAGE" && zip -q -r -X "$OUT_DIR/GideonRaid-v$VERSION.zip" GideonRaid )

echo "built: $OUT_DIR/GideonRaid-v$VERSION.zip"
