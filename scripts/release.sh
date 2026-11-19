#!/bin/sh
# Builds a universal, ad-hoc signed GDocker.app zip, SHA256SUMS, and matching Homebrew 7 Cask.
# Usage: scripts/release.sh <version>    e.g. scripts/release.sh 0.2.0
set -eu

raw_version="${1:?usage: scripts/release.sh <version>}"
version="${raw_version#v}"
cd "$(dirname "$0")/.."

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" -c "Set :CFBundleVersion $version" scripts/Info.plist
make app SWIFT_FLAGS="--arch arm64 --arch x86_64"

zip="build/GDocker-$version.zip"
rm -f "$zip"
ditto -c -k --keepParent build/GDocker.app "$zip"
sha=$(shasum -a 256 "$zip" | cut -d' ' -f1)
printf '%s  %s\n' "$sha" "GDocker-$version.zip" > build/SHA256SUMS

./scripts/generate-cask.sh "$version" "$sha" build/gdocker.rb

cat <<EOF
Built $zip (sha256 $sha), build/SHA256SUMS, and build/gdocker.rb.
Next (automated via GitHub Actions on tag push):
  git commit -am "chore: release v$version" && git tag v$version && git push --follow-tags

Or manually:
  gh release create v$version $zip build/SHA256SUMS --title v$version --generate-notes
  cp build/gdocker.rb <homebrew-tap checkout>/Casks/gdocker.rb, then commit and push the tap
EOF
