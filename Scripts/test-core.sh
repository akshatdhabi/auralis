#!/bin/bash
# Run the same XCTest test methods with a tiny assertion harness when full Xcode is absent.
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$TASK_ROOT/build/core-checks" "$TASK_ROOT/build/test-module-cache"
/usr/bin/python3 - "$TASK_ROOT" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
tests = (root / 'Tests/AuralisCoreTests/PlaybackTests.swift').read_text()
tests = re.sub(r'#if SWIFT_PACKAGE.*?#endif', '', tests, flags=re.S)
tests = tests.replace('import XCTest', '').replace('@testable import Auralis', '')
methods = re.findall(r'    func (test\w+)\(\)( throws)?', tests)
harness = (root / 'Scripts/AssertionSupport.swift').read_text()
runner = '\n@main enum CoreChecks { static func main() throws { let tests = PlaybackTests()\n'
for method, throws in methods:
    runner += ('try ' if throws else '') + 'tests.' + method + '()\n'
runner += f'print("PASS · {len(methods)} core test methods (same source as XCTest)")\n}}}}\n'
(root / 'build/core-checks/Runner.swift').write_text(harness + tests + runner)
PY
xcrun swiftc -swift-version 5 -module-cache-path "$TASK_ROOT/build/test-module-cache" \
 "$TASK_ROOT"/Auralis/Core/*.swift "$TASK_ROOT/build/core-checks/Runner.swift" -o "$TASK_ROOT/build/core-checks/checks"
"$TASK_ROOT/build/core-checks/checks"
