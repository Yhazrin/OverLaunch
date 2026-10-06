#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
ARCHIVE="Vendor/dxmt-ow2-pack-v0.2.tar.gz"
EXPECTED="8d4e778ff9868883a064d7b9bfb372ed6e286e4233f60c053075ca983b2bc256"
mkdir -p Vendor
if [[ ! -f "$ARCHIVE" ]]; then
  PARTIAL="$(mktemp Vendor/dxmt-download.XXXXXX)"
  trap 'rm -f "$PARTIAL"' EXIT
  curl --fail --location --retry 2 --proto '=https' --tlsv1.2 'https://github.com/NerRobDog/dxmt/releases/download/v0.80-ow2-0.2/dxmt-ow2-pack-v0.2.tar.gz' -o "$PARTIAL"
  ACTUAL="$(shasum -a 256 "$PARTIAL")"
  [[ "${ACTUAL%% *}" == "$EXPECTED" ]] || { print -u2 'DXMT checksum mismatch'; exit 1; }
  mv "$PARTIAL" "$ARCHIVE"
  trap - EXIT
fi
ACTUAL="$(shasum -a 256 "$ARCHIVE")"
[[ "${ACTUAL%% *}" == "$EXPECTED" ]] || { print -u2 'DXMT checksum mismatch'; exit 1; }
print 'DXMT archive verified'
