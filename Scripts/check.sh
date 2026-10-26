#!/bin/bash
set -euo pipefail
AURALIS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for script in "$AURALIS_ROOT"/Scripts/*.sh; do bash -n "$script"; done
for script in "$AURALIS_ROOT"/Auralis/Resources/*.js "$AURALIS_ROOT"/Scripts/*.cjs; do node --check "$script"; done
bash "$AURALIS_ROOT/Scripts/test-core.sh"
bash "$AURALIS_ROOT/Scripts/test-artwork.sh"
node "$AURALIS_ROOT/Scripts/test-adapter.cjs"
node "$AURALIS_ROOT/Scripts/test-browse.cjs"
node "$AURALIS_ROOT/Scripts/test-lyrics.cjs"
bash "$AURALIS_ROOT/Scripts/build.sh"
plutil -lint "$AURALIS_ROOT/Auralis.xcodeproj/project.pbxproj" "$AURALIS_ROOT/Auralis/Resources/Info.plist"
printf 'All local checks passed.\n'
