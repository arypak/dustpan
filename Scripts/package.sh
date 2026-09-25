#!/bin/bash
# Builds a universal Dustpan.app and dustpan CLI and packs them for a GitHub release:
#   dist/Dustpan-<version>.zip, dist/dustpan-<version>-macos.tar.gz, dist/SHA256SUMS
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/.*version = "\(.*\)".*/\1/p' Sources/DustpanCore/Dustpan.swift)
Scripts/build-app.sh --universal

rm -rf dist
mkdir -p dist
ditto -c -k --keepParent build/Dustpan.app "dist/Dustpan-$VERSION.zip"
tar -czf "dist/dustpan-$VERSION-macos.tar.gz" -C build dustpan
(cd dist && shasum -a 256 ./*.zip ./*.tar.gz > SHA256SUMS)
echo "Packed version $VERSION:"
ls -lh dist
