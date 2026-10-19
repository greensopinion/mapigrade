#!/usr/bin/env bash
# Writes MAPLIBRE_FFI_XCFRAMEWORK_URL and MAPLIBRE_FFI_XCFRAMEWORK_CHECKSUM from
# packages/flutter_mapigrade/maplibre_ffi.lock into the remote binary target of
# packages/flutter_mapigrade/darwin/flutter_mapigrade/Package.swift (design D99
# and D102 of the publish-readiness change). Run it after changing either value
# in the lock file; packages/flutter_mapigrade/test/ffi_pins_test.dart fails
# while the two files disagree.
#
#   scripts/update_ffi_pins.sh
#
# The checksum is the output of `swift package compute-checksum` on the zip.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../packages/flutter_mapigrade/maplibre_ffi.lock
source "$repo_root/packages/flutter_mapigrade/maplibre_ffi.lock"
package_swift="$repo_root/packages/flutter_mapigrade/darwin/flutter_mapigrade/Package.swift"

if [[ ! "$MAPLIBRE_FFI_XCFRAMEWORK_URL" =~ ^https://[^\"\|]+$ ]]; then
  echo "MAPLIBRE_FFI_XCFRAMEWORK_URL in the lock file isn't an https URL: '$MAPLIBRE_FFI_XCFRAMEWORK_URL'" >&2
  exit 1
fi
if [[ ! "$MAPLIBRE_FFI_XCFRAMEWORK_CHECKSUM" =~ ^[0-9a-f]{64}$ ]]; then
  echo "MAPLIBRE_FFI_XCFRAMEWORK_CHECKSUM in the lock file isn't 64 hex digits: '$MAPLIBRE_FFI_XCFRAMEWORK_CHECKSUM'" >&2
  exit 1
fi

# Package.swift has one `url:` and one `checksum:` argument, those of the remote
# binary target.
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
