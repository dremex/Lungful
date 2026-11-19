#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"

version="${1:-}"
if [ -z "$version" ]; then
	version="$(git describe --tags --match 'v[0-9]*' --exact-match 2> /dev/null ||
		git describe --tags --match 'v[0-9]*' --always --dirty 2> /dev/null ||
		echo dev)"
fi
version="${version#v}"
case "$version" in
*[!A-Za-z0-9._-]*)
	echo "not a version: $version" >&2
	exit 1
	;;
esac

zip="$root/dist/Lungful-$version.zip"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

mkdir -p "$stage/Lungful"
sed "s/@project-version@/$version/" Lungful/Lungful.toc > "$stage/Lungful/Lungful.toc"
cp LICENSE "$stage/Lungful/"
files_listed_in_toc() {
	grep -v -e '^#' -e '^[[:space:]]*$' Lungful/Lungful.toc | tr -d '\r'
}
files_listed_in_toc | while read -r file; do
	mkdir -p "$stage/Lungful/$(dirname "$file")"
	cp "Lungful/$file" "$stage/Lungful/$file"
done

mkdir -p dist
rm -f "$zip"
(cd "$stage" && zip -qr -X "$zip" Lungful)
echo "$(du -h "$zip" | cut -f1 | tr -d ' ') $zip (version $version)"
