#!/bin/bash
set -euo pipefail
AURALIS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$AURALIS_ROOT/build/core-checks" "$AURALIS_ROOT/build/test-module-cache"
xcrun swiftc -swift-version 5 -O -module-cache-path "$AURALIS_ROOT/build/test-module-cache" \
 -framework AppKit -framework ImageIO "$AURALIS_ROOT/Auralis/Core/Playback.swift" \
 "$AURALIS_ROOT/Auralis/Services/ArtworkDiskCache.swift" "$AURALIS_ROOT/Auralis/Services/ArtworkService.swift" "$AURALIS_ROOT/Scripts/ArtworkChecks.swift" \
 -o "$AURALIS_ROOT/build/core-checks/artwork-checks"
"$AURALIS_ROOT/build/core-checks/artwork-checks"
