#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h}"
app_dir="$project_dir/dist/Posteight.app"

cd "$project_dir"

# The Xcode target owns every build setting, including the ad-hoc signing this Mac uses
# during development. Keep this script a thin wrapper so the two never drift apart.
echo "Building Posteight..."
xcodebuild -project Posteight.xcodeproj \
    -scheme Posteight \
    -configuration Release \
    -derivedDataPath .build/xcode \
    CONFIGURATION_BUILD_DIR="$project_dir/dist" \
    build

echo "Done: $app_dir"
