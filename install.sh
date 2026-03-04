#!/bin/bash
# Install WispMark to /usr/local/bin for daily use

set -e

echo "Compiling WispMark..."
swiftc main.swift -o WispMark -framework Cocoa -framework Carbon -O

echo "Installing to /usr/local/bin..."
sudo cp WispMark /usr/local/bin/WispMark
sudo chmod +x /usr/local/bin/WispMark

echo "Done! Run 'WispMark' from anywhere to launch."
echo "Development version: ./run.sh"
