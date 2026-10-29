#!/bin/bash
# Builds the app and packages it for download: build/Sip.zip
set -euo pipefail
cd "$(dirname "$0")"

./build.sh release

ZIP="build/Sip.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "build/Sip.app" "$ZIP"
echo "Packaged $ZIP"
