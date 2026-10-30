#!/usr/bin/env bash
# Checks a notarised Mac app and puts it in a signed, notarised DMG for a GitHub release.
#
# Give it the FM-SWITCH.app that Xcode's Organiser exported after Distribute App ▸ Direct
# Distribution:
#
#     scripts/package-mac.sh ~/Desktop/FM-SWITCH/FM-SWITCH.app
#
# It checks that the app and its flash tool are signed with the same Developer ID team, that
# Gatekeeper accepts it as notarised, and that the ticket is stapled. Then it makes a DMG of the
# app and a link to Applications, signs it with that team's Developer ID, has Apple notarise it,
# staples the ticket and checks the result. It writes .artifacts/release/FM-SWITCH-<version>.dmg,
# its SHA-256, and a copy named FM-SWITCH.dmg, which the site links to as the latest release's.
#
# It needs, once on each Mac:
# - A Developer ID Application certificate in the keychain: Xcode ▸ Settings ▸ Accounts ▸ Manage
#   Certificates ▸ + ▸ Developer ID Application.
# - notarytool's credentials, saved as the keychain profile "notary" (or the one NOTARY_PROFILE
#   names): `xcrun notarytool store-credentials notary --apple-id <email> --team-id <team>`, with
#   an app-specific password from appleid.apple.com.
#
# Archiving and notarising the app are done in Xcode for now. To automate them later, add
# `xcodebuild archive`, `xcodebuild -exportArchive` and `xcrun notarytool submit --wait` before
# these checks.
set -euo pipefail
cd "$(dirname "$0")/.."

app=${1:?Give the path to the exported FM-SWITCH.app.}
app=${app%/}
helper="$app/Contents/MacOS/FMSwitchHelper"
notary_profile=${NOTARY_PROFILE:-notary}

step() { printf '\n== %s\n' "$1"; }
fail() { printf 'error: %s\n' "$1" >&2; exit 1; }

# Prints the team that signed a file, or nothing when it isn't signed by one.
team_of() {
    codesign -dv "$1" 2>&1 | sed -n 's/^TeamIdentifier=//p' | grep -v '^not set$' || true
}

# Prints the signing authority a file's certificate chain starts with.
authority_of() {
    codesign -dv --verbose=2 "$1" 2>&1 | sed -n 's/^Authority=//p' | sed -n 1p
}

[[ -d $app ]] || fail "$app isn't there."
[[ -x $helper ]] || fail "The flash tool isn't in Contents/MacOS."

step "Signatures"
codesign --verify --deep --strict --verbose=2 "$app"
codesign --verify --strict --verbose=2 "$helper"
app_team=$(team_of "$app")
helper_team=$(team_of "$helper")
[[ -n $app_team ]] || fail "The app isn't signed by a team."
[[ $app_team == "$helper_team" ]] || fail "The app ($app_team) and flash tool ($helper_team) have different teams."
for file in "$app" "$helper"; do
    authority=$(authority_of "$file")
    [[ $authority == "Developer ID Application:"* ]] || fail "$file is signed by \"$authority\", not Developer ID."
done
# The output's kept before it's searched: `grep -q` stops reading at a match, and with pipefail the
# write it cuts short would fail the check.
[[ $(codesign -dv "$app" 2>&1) == *flags=*runtime* ]] || fail "The app doesn't have the hardened runtime."
[[ $(codesign -dv "$helper" 2>&1) == *flags=*runtime* ]] || fail "The flash tool doesn't have the hardened runtime."
echo "App and flash tool: Developer ID, team $app_team, hardened runtime."

step "Notarisation"
assessment=$(spctl --assess --type execute --verbose=2 "$app" 2>&1) || true
echo "$assessment"
[[ $assessment == *"source=Notarized Developer ID"* ]] || fail "Gatekeeper doesn't accept it as notarised."
xcrun stapler validate "$app"

step "Signing setup"
# Both are checked before the DMG is made, so a missing one fails in seconds, not after an upload.
identities=$(security find-identity -v -p codesigning)
identity=$(sed -n "s/.*\"\(Developer ID Application: .*($app_team)\)\"/\1/p" <<<"$identities" | sed -n 1p)
[[ -n $identity ]] ||
    fail "No Developer ID Application certificate for team $app_team in the keychain. Make one in Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates."
xcrun notarytool history --keychain-profile "$notary_profile" >/dev/null 2>&1 ||
    fail "No notarytool credentials saved as \"$notary_profile\". Run: xcrun notarytool store-credentials $notary_profile --apple-id <email> --team-id $app_team"
echo "Signing as $identity; notarising with the \"$notary_profile\" profile."

step "DMG"
info="$app/Contents/Info.plist"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info")
out=.artifacts/release
dmg="$out/FM-SWITCH-$version.dmg"
latest="$out/FM-SWITCH.dmg"
mkdir -p "$out"
rm -f "$dmg" "$dmg.sha256" "$latest"

# The DMG's window shows the app beside Applications, to drag it across.
work=$(mktemp -d)
mount="$work/mount"
trap 'hdiutil detach -quiet "$mount" 2>/dev/null || true; rm -rf "$work"' EXIT
mkdir "$work/contents"
ditto "$app" "$work/contents/$(basename "$app")"
ln -s /Applications "$work/contents/Applications"
hdiutil create -quiet -volname "FM-SWITCH" -srcfolder "$work/contents" -fs HFS+ -format UDZO "$dmg"
codesign --sign "$identity" --timestamp "$dmg"
codesign --verify --strict --verbose=2 "$dmg"

step "Notarising the DMG (a few minutes)"
submission=$(xcrun notarytool submit "$dmg" --keychain-profile "$notary_profile" --wait 2>&1) || true
echo "$submission"
if [[ $submission != *"status: Accepted"* ]]; then
    id=$(sed -n 's/^ *id: //p' <<<"$submission" | sed -n 1p)
    [[ -n $id ]] && xcrun notarytool log "$id" --keychain-profile "$notary_profile" || true
    fail "Apple didn't accept the DMG."
fi
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
assessment=$(spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg" 2>&1) || true
echo "$assessment"
[[ $assessment == *"source=Notarized Developer ID"* ]] || fail "Gatekeeper doesn't accept the DMG as notarised."

# Opens the DMG to check the app inside keeps its signature and stapled ticket.
mkdir "$mount"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mount" "$dmg"
codesign --verify --deep --strict "$mount/$(basename "$app")"
xcrun stapler validate -q "$mount/$(basename "$app")"
[[ -L "$mount/Applications" ]] || fail "The DMG has no link to Applications."
hdiutil detach -quiet "$mount"

(cd "$out" && shasum -a 256 "$(basename "$dmg")" >"$(basename "$dmg").sha256")
cp "$dmg" "$latest"

printf '\nFM-SWITCH %s (%s): %s, and a copy as %s\n' "$version" "$build" "$dmg" "$latest"
cat "$dmg.sha256"
