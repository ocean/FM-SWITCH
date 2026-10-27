#!/usr/bin/env bash
# Checks a notarised Mac app and zips it for a GitHub release.
#
# Give it the FM-SWITCH.app that Xcode's Organiser exported after Distribute App ▸ Direct
# Distribution:
#
#     scripts/package-mac.sh ~/Desktop/FM-SWITCH/FM-SWITCH.app
#
# It checks that the app and its helper are signed with the same Developer ID team, that
# Gatekeeper accepts it as notarised, and that the ticket is stapled. Then it writes
# .artifacts/release/FM-SWITCH-<version>.zip and the zip's SHA-256 next to it.
#
# Archiving and notarising are done in Xcode for now. To automate them later, add
# `xcodebuild archive`, `xcodebuild -exportArchive` and `xcrun notarytool submit --wait`
# before these checks.
set -euo pipefail
cd "$(dirname "$0")/.."

app=${1:?Give the path to the exported FM-SWITCH.app.}
app=${app%/}
helper="$app/Contents/MacOS/FMSwitchHelper"
daemon="$app/Contents/Library/LaunchDaemons/dev.drewr.fmswitch.helper.plist"

step() { printf '\n== %s\n' "$1"; }
fail() { printf 'error: %s\n' "$1" >&2; exit 1; }

# Prints the team that signed a file, or nothing when it isn't signed by one.
team_of() {
    codesign -dv "$1" 2>&1 | sed -n 's/^TeamIdentifier=//p' | grep -v '^not set$' || true
}

# Prints the signing authority a file's certificate chain starts with.
authority_of() {
    codesign -dv --verbose=2 "$1" 2>&1 | sed -n 's/^Authority=//p' | head -1
}

[[ -d $app ]] || fail "$app isn't there."
[[ -x $helper ]] || fail "The helper isn't in Contents/MacOS."
[[ -f $daemon ]] || fail "The helper's launchd property list isn't in Contents/Library/LaunchDaemons."

step "Signatures"
codesign --verify --deep --strict --verbose=2 "$app"
codesign --verify --strict --verbose=2 "$helper"
app_team=$(team_of "$app")
helper_team=$(team_of "$helper")
[[ -n $app_team ]] || fail "The app isn't signed by a team."
[[ $app_team == "$helper_team" ]] || fail "The app ($app_team) and helper ($helper_team) have different teams."
for file in "$app" "$helper"; do
    authority=$(authority_of "$file")
    [[ $authority == "Developer ID Application:"* ]] || fail "$file is signed by \"$authority\", not Developer ID."
done
codesign -dv "$app" 2>&1 | grep -q 'flags=.*runtime' || fail "The app doesn't have the hardened runtime."
codesign -dv "$helper" 2>&1 | grep -q 'flags=.*runtime' || fail "The helper doesn't have the hardened runtime."
echo "App and helper: Developer ID, team $app_team, hardened runtime."

step "Notarisation"
spctl --assess --type execute --verbose=2 "$app" 2>&1 | tee /dev/stderr | grep -q 'source=Notarized Developer ID' ||
    fail "Gatekeeper doesn't accept it as notarised."
xcrun stapler validate "$app"

step "Zip"
info="$app/Contents/Info.plist"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info")
out=.artifacts/release
zip="$out/FM-SWITCH-$version.zip"
mkdir -p "$out"
rm -f "$zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
(cd "$out" && shasum -a 256 "$(basename "$zip")" >"$(basename "$zip").sha256")

# Unzips a copy to check the zip keeps the signature and stapled ticket.
check=$(mktemp -d)
ditto -x -k "$zip" "$check"
codesign --verify --deep --strict "$check/$(basename "$app")"
xcrun stapler validate -q "$check/$(basename "$app")"
rm -rf "$check"

printf '\nFM-SWITCH %s (%s): %s\n' "$version" "$build" "$zip"
cat "$zip.sha256"
