#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
# Integration tests validate the pinned graphics pack in temporary fixtures.
./scripts/fetch-vendor.sh
SWIFTC="$(xcrun --find swiftc)"
PLUGIN="${SWIFTC:h:h}/lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [[ -f "$PLUGIN" ]]; then
  swift test --disable-xctest -Xswiftc -load-plugin-library -Xswiftc "$PLUGIN" -Xlinker -rpath -Xlinker "${SWIFTC:h:h:h}/Library/Developer/Frameworks" -Xlinker -rpath -Xlinker "${SWIFTC:h:h:h}/Library/Developer/usr/lib"
else
  swift test --disable-xctest
fi
