#!/usr/bin/env bash
# Sets the version of mapigrade and of flutter_mapigrade to <version>, and
# flutter_mapigrade's constraint on mapigrade to the range from <version> to
# the next patch version, which allows no other release of mapigrade (design
# D231 of the split-mapigrade-package change). For a prerelease, such as
# 0.2.0-beta.1, the range ends at the next prerelease, 0.2.0-beta.2, because
# the next patch version, 0.2.0, would allow the other prereleases of 0.2.0, and
# pub warns about a constraint that allows only one version (design D254 of the
# apple-only-beta-release change). The prerelease must end with a number.
# packages/flutter_mapigrade/test/version_test.dart fails while the three
# values disagree.
#
#   scripts/set_version.sh 0.2.0
#   scripts/set_version.sh 0.2.0-beta.1
set -euo pipefail

if [[ $# -ne 1 || ! "$1" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-[0-9A-Za-z.]+)?$ ]]; then
  echo "usage: $0 <major>.<minor>.<patch>[-<prerelease>], for example $0 0.2.0" >&2
  exit 2
fi
version="$1"
if [[ -n "${BASH_REMATCH[4]}" ]]; then
  if [[ ! "$version" =~ ^(.*[.-])([0-9]+)$ ]]; then
    echo "a prerelease must end with a number, for example 0.2.0-beta.1" >&2
    exit 2
  fi
  constraint="'>=$version <${BASH_REMATCH[1]}$((BASH_REMATCH[2] + 1))'"
else
  constraint="'>=$version <${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.$((BASH_REMATCH[3] + 1))'"
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mapigrade="$repo_root/packages/mapigrade/pubspec.yaml"
flutter_mapigrade="$repo_root/packages/flutter_mapigrade/pubspec.yaml"

sed -i.bak -E "s/^version: .*/version: $version/" "$mapigrade" "$flutter_mapigrade"
sed -i.bak -E "s/^  mapigrade: .*/  mapigrade: $constraint/" "$flutter_mapigrade"
rm "$mapigrade.bak" "$flutter_mapigrade.bak"

grep -H -E "^version: |^  mapigrade: " "$mapigrade" "$flutter_mapigrade"
