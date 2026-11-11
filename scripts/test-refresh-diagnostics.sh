#!/bin/sh
set -eu
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
cp scripts/refresh-diagnostics-main.swift "$out/main.swift"
swiftc -D DEBUG App/Infrastructure/RefreshDiagnostics.swift "$out/main.swift" -o "$out/test"
"$out/test" > "$out/output"
test "$(grep -c '^PUBO_REFRESH_DIAG ' "$out/output")" -eq 128
grep -q '^DIAGNOSTIC_TESTS_PASS$' "$out/output"
swiftc -emit-library App/Infrastructure/RefreshDiagnostics.swift -o "$out/release.dylib"
! nm "$out/release.dylib" | grep -q RefreshDiagnostics
echo 'Refresh diagnostics unit checks passed'
