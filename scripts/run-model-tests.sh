#!/bin/bash
# Compiles the model layer with the tests and runs them. No Xcode needed.
set -euo pipefail
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
cp scripts/model-tests.swift "$TMP/main.swift"   # top-level code requires main.swift
swiftc -o "$TMP/model-tests" FocusGate/Models.swift FocusGate/DomainMatcher.swift "$TMP/main.swift"
"$TMP/model-tests"
