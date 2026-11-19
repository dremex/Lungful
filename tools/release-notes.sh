#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
version="${1:?usage: tools/release-notes.sh <version>}"
version="${version#v}"

notes="$(awk -v v="$version" '
	/^## / { if (found) exit; found = ($2 == v); next }
	found { print }
' CHANGELOG.md | sed '/./,$!d')"
if [ -z "$notes" ]; then
	echo "CHANGELOG.md has no notes under a \"## $version\" heading" >&2
	exit 1
fi
printf '%s\n' "$notes"
