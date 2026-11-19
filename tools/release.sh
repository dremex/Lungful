#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

die() {
	echo "$1" >&2
	exit 1
}

version="${1:?usage: tools/release.sh <major.minor.patch>}"
version="${version#v}"
tag="v$version"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "versions are major.minor.patch, like 1.0.1"
git rev-parse --git-dir > /dev/null 2>&1 || die "not a git repository"
[ -z "$(git status --porcelain)" ] || die "commit or stash your changes first: the release is built from the tagged commit"
! git rev-parse -q --verify "refs/tags/$tag" > /dev/null || die "$tag is already tagged"
tools/release-notes.sh "$version" > /dev/null

echo "Checking..."
tools/format.sh --check
luajit tests/run.lua > /dev/null || {
	luajit tests/run.lua | grep -E '^FAIL|passed'
	die "the addon tests failed"
}

git tag -a "$tag" -m "Lungful $version"
echo "Tagged $tag."
tools/package-addon.sh "$version"

if ! git remote get-url origin > /dev/null 2>&1; then
	echo "No GitHub remote yet: upload the zip to CurseForge by hand, and push $tag once the repo is up."
	exit 0
fi
branch="$(git rev-parse --abbrev-ref HEAD)"
read -r -p "Push $branch and $tag to origin? That publishes the release. [y/N] " answer
if [[ "$answer" == [yY]* ]]; then
	git push --atomic origin "$branch" "$tag"
	echo "Pushed. The release workflow posts the zip at $(git remote get-url origin | sed -E 's#^git@github.com:#https://github.com/#; s#\.git$##')/releases"
else
	echo "Not pushed. To publish later: git push --atomic origin $branch $tag"
	echo "To start over instead: git tag -d $tag"
fi
