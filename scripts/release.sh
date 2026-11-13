#!/bin/sh
# Builds a universal, ad-hoc signed GDocker.app zip and the matching Homebrew cask.
# Usage: scripts/release.sh <version>    e.g. scripts/release.sh 0.1.0
set -eu

version="${1:?usage: scripts/release.sh <version>}"
cd "$(dirname "$0")/.."

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" -c "Set :CFBundleVersion $version" scripts/Info.plist
make app SWIFT_FLAGS="--arch arm64 --arch x86_64"

zip="build/GDocker-$version.zip"
rm -f "$zip"
ditto -c -k --keepParent build/GDocker.app "$zip"
sha=$(shasum -a 256 "$zip" | cut -d' ' -f1)

cat > build/gdocker.rb <<EOF
cask "gdocker" do
  version "$version"
  sha256 "$sha"

  url "https://github.com/Diaszano/gdocker/releases/download/v#{version}/GDocker-#{version}.zip"
  name "GDocker"
  desc "Native Docker GUI with a built-in MCP server for AI clients"
  homepage "https://github.com/Diaszano/gdocker"

  depends_on macos: :sonoma

  app "GDocker.app"

  # The app is ad-hoc signed, not notarized, so Gatekeeper would refuse to open it with the quarantine flag set.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/GDocker.app"]
  end

  zap trash: [
    "~/Library/Application Support/GDocker",
    "~/Library/Preferences/com.diaszano.gdocker.plist",
  ]
end
EOF

cat <<EOF
Built $zip (sha256 $sha) and build/gdocker.rb.
Next:
  git commit -am "chore: release v$version" && git tag v$version && git push --follow-tags
  gh release create v$version $zip --title v$version --generate-notes
  cp build/gdocker.rb <homebrew-tap checkout>/Casks/gdocker.rb, then commit and push the tap
EOF
