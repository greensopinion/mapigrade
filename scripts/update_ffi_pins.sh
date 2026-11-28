#!/usr/bin/env bash
# Writes MAPLIBRE_FFI_XCFRAMEWORK_URL and MAPLIBRE_FFI_XCFRAMEWORK_CHECKSUM from
# packages/mapigrade/maplibre_ffi.lock into the remote binary target of
# packages/mapigrade/darwin/mapigrade/Package.swift (design D99
# and D102 of the publish-readiness change). Run it after changing either value
# in the lock file; packages/mapigrade/test/ffi_pins_test.dart fails
# while the two files disagree. While the lock names no release, both values
# are empty, and Package.swift then fails without a local FFI build, with a
# message that names scripts/build_maplibre_ffi.sh.
#
#   scripts/update_ffi_pins.sh
#
# The checksum is the output of `swift package compute-checksum` on the zip.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../packages/mapigrade/maplibre_ffi.lock
source "$repo_root/packages/mapigrade/maplibre_ffi.lock"
package_swift="$repo_root/packages/mapigrade/darwin/mapigrade/Package.swift"

if [[ -z "$MAPLIBRE_FFI_XCFRAMEWORK_URL" && -z "$MAPLIBRE_FFI_XCFRAMEWORK_CHECKSUM" ]]; then
  echo "The lock file names no FFI release; writing an empty URL and checksum"
elif [[ ! "$MAPLIBRE_FFI_XCFRAMEWORK_URL" =~ ^https://[^\"\|]+$ ]]; then
  echo "MAPLIBRE_FFI_XCFRAMEWORK_URL in the lock file isn't an https URL: '$MAPLIBRE_FFI_XCFRAMEWORK_URL'" >&2
  exit 1
elif [[ ! "$MAPLIBRE_FFI_XCFRAMEWORK_CHECKSUM" =~ ^[0-9a-f]{64}$ ]]; then
  echo "MAPLIBRE_FFI_XCFRAMEWORK_CHECKSUM in the lock file isn't 64 hex digits: '$MAPLIBRE_FFI_XCFRAMEWORK_CHECKSUM'" >&2
  exit 1
fi

# Package.swift has one `url:` and one `checksum:` argument, those of the
# release.
for key in url checksum; do
  count=$(grep -cE "^ *$key: \"[^\"]*\"" "$package_swift" || true)
  if [[ "$count" != 1 ]]; then
    echo "expected one '$key: \"...\"' line in $package_swift, found $count" >&2
    exit 1
  fi
done
sed -i '' -E \
  -e "s|^( *url: )\"[^\"]*\"|\1\"$MAPLIBRE_FFI_XCFRAMEWORK_URL\"|" \
  -e "s|^( *checksum: )\"[^\"]*\"|\1\"$MAPLIBRE_FFI_XCFRAMEWORK_CHECKSUM\"|" \
  "$package_swift"
echo "Wrote the xcframework URL and checksum into $package_swift"
