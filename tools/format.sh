#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
exec npx --yes @johnnymorganz/stylua-bin@2.6.0 "$@" --glob '**/*.lua' .
