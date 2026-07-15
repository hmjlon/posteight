#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h}"
app_dir="$project_dir/dist/Posteight.app"
contents_dir="$app_dir/Contents"

cd "$project_dir"

echo "Building Posteight..."
swift build -c release --product Posteight

mkdir -p "$contents_dir/MacOS"
cp ".build/release/Posteight" "$contents_dir/MacOS/Posteight"
cp "Packaging/Info.plist" "$contents_dir/Info.plist"
chmod +x "$contents_dir/MacOS/Posteight"

# Ad-hoc signing is enough for this Mac during development.
codesign --force --deep --sign - "$app_dir" >/dev/null

echo "Done: $app_dir"
