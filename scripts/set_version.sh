#!/usr/bin/env bash
# Sets the version of mapigrade and of flutter_mapigrade to <version>, and
# flutter_mapigrade's constraint on mapigrade to the range from <version> to
# the next patch version, which allows no other release of mapigrade (design
# D231 of the split-mapigrade-package change).
# packages/flutter_mapigrade/test/version_test.dart fails while the three
# values disagree.
#
#   scripts/set_version.sh 0.2.0
set -euo pipefail

if [[ $# -ne 1 || ! "$1" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "usage: $0 <major>.<minor>.<patch>, for example $0 0.2.0" >&2
  exit 2
fi
version="$1"
next_patch="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.$((BASH_REMATCH[3] + 1))"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mapigrade="$repo_root/packages/mapigrade/pubspec.yaml"
flutter_mapigrade="$repo_root/packages/flutter_mapigrade/pubspec.yaml"

sed -i.bak -E "s/^version: .*/version: $version/" "$mapigrade" "$flutter_mapigrade"
sed -i.bak -E "s/^  mapigrade: .*/  mapigrade: '>=$version <$next_patch'/" "$flutter_mapigrade"
rm "$mapigrade.bak" "$flutter_mapigrade.bak"

grep -H -E "^version: |^  mapigrade: " "$mapigrade" "$flutter_mapigrade"
