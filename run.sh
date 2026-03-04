#!/bin/bash
set -euo pipefail

if [ "${1:-}" = "--dev" ]; then
    # Unsigned dev run (useful for rapid local testing only).
    swiftc main.swift -o WispMark -framework Cocoa -framework Carbon
    ./WispMark
    exit 0
fi

# Default: build signed app, install to /Applications, launch stable bundle.
./build_app.sh
open "/Applications/WispMark.app"
