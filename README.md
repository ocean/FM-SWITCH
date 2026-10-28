# FM-SWITCH

An app for iPhone, iPad and Mac for swapping M-VAVE FM-1 firmwares over USB. Firmwares come
from the firmware hub's catalogue merged with fm1-editor.com's list, and are saved on the device
for offline flashing. M-VAVE's official V15 comes with the app (from M-VAVE's open-source
[fm1_open](https://github.com/m-vave/fm1_open), Apache-2.0), so it's always there to go back to.
See `PLAN.md` for the research and the phased plan.

## Layout

```
project.yml              XcodeGen spec (the .xcodeproj is generated, not committed)
App/                     SwiftUI app (iOS 17+)
  Theme/                 8-bit look: accent colour, pixel fonts, pixel boxes, optional CRT effects
  Catalogue/             merged firmware list: thefirmwarehub.com feed, fm1-editor.com page and
                         aroum's FM1 Resource Hub README; package discovery (GitHub releases,
                         publisher manifests, project pages, M-VAVE's downloads); live checks
                         for newer releases and their builds
  Model/                 settings, catalogue, saved firmwares, flash history, device controller
  Views/                 Device, Firmware (catalogue), Saved, Setup, Flash; the wide layout
                         (sidebar and two panes) for iPad and Mac
  Platform/iOS, macOS/   the few things done differently on each: staying awake, links, navigation;
                         on the Mac, Backup & rescue (download mode), with m-bootloader 1.2 (MIT)
  Resources/Fonts/       Departure Mono, Silkscreen, VT323 (SIL OFL)
  Resources/Firmware/    M-VAVE's FM-1 V15, unmodified, and its Apache-2.0 notice
  Assets.xcassets/       the app icons, made by scripts/make-app-icon.swift and make-icon.py
Helper/                  the Mac's flash tool, which reads and writes the FM-1's flash in
                         download mode as root, for the app, over a pipe
Shared/                  the download-mode code the Mac app and its flash tool share
AppTests/                firmware list and flashing tests (Swift Testing)
Package.swift            fm1-catalogue, which builds the published firmware list from App/Catalogue
Tools/fm1-catalogue/     its command line
scripts/check.sh         every check CI runs
scripts/make-app-icon.swift  draws the app icon (light, dark, tinted, Mac) and the launch screen
scripts/make-icon.py     draws Retro's pixel icon from its 32 x 32 pixel map
```

Talking to the FM-1 (the update protocol, `.fwsc` packages, CoreMIDI and a simulated FM-1)
is [FM1Kit](https://github.com/ocean/FM1Kit), an open-source Swift package. `project.yml`
uses its tagged release from GitHub, taking 0.4.x fixes but not 0.5.0, which may change the API.

### The firmware list

The list merges three sources: the firmware hub's catalogue, fm1-editor.com and
[aroum's FM1 Resource Hub](https://github.com/aroum/fm1-custom-fw). Only facts are taken from
aroum's list (names, authors, links, licences and sections), as its repository has no licence.

fm-1.drewr.dev builds the list once a day with `fm1-catalogue` and publishes it as
[firmwares.json](https://fm-1.drewr.dev/firmwares.json). The app downloads that, and builds the
list itself from the same sources only if it can't. Building it on every phone would make about 90
GitHub API requests per refresh, more than GitHub allows an hour without a token.

`fm1-catalogue` is the app's own list code, `App/Catalogue`, built as a Swift package:

```bash
GITHUB_TOKEN=$(gh auth token) swift run -c release fm1-catalogue \
    --output firmwares.json --previous firmwares.json
```

Firmwares none of the lists describe get their GitHub repository's description, the author's own
words, marked with `whatSource: "gitHub"` so the app can say where it's from. A repository several
firmwares share describes none of them.

`--previous` is the last published list: packages that can't be found this time fall back on it,
and a list more than a fifth shorter is refused. Any exit code but 0 means "don't publish": 1 for
bad arguments or a failed write, 2 when a source can't be read, 3 for a list that shrank.

`MergedCatalogue.currentFormat` is the file's format, raised only for changes that would break
an app reading it. The app ignores a list in a newer format and builds its own instead.

### Working on FM1Kit and the app together

To build against a local FM1Kit checkout at `../FM1Kit` (that is, `~/code/FM1Kit`), generate
the project from `project.local.yml`. It's `project.yml` with FM1Kit's source swapped for that
path:

```bash
xcodegen generate --spec project.local.yml   # use ../FM1Kit
FM1KIT=local scripts/check.sh                # run the checks against ../FM1Kit
xcodegen generate                            # back to the tagged release
```

Before pushing app changes that need unreleased FM1Kit changes, tag a new FM1Kit release and
raise `minorVersion` in `project.yml` and the matching version in `Package.swift`. CI always uses the release.

## Running it

```bash
xcodegen generate
open FMSwitch.xcodeproj
```

Pick an iPhone or iPad simulator, or **My Mac**, and run. iPad (landscape, or a 13-inch in
either orientation) and the Mac get the wide layout: a sidebar, and lists with the picked item
beside them. The Mac app is native SwiftUI and talks to the FM-1 over USB MIDI like the iPhone.
It isn't sandboxed, as it's signed with Developer ID and downloaded from the website, and it
starts the root flash tool that download mode needs. In the Simulator the app uses the simulated FM-1 (set under
**SETUP ▸ CONNECTION**). It runs the whole protocol: install, the reboot into the loader, and
the identity check. It can also start in USB rescue mode or "pull the cable" at 45% to test
**RESUME**.

If Xcode says *"CoreSimulator is out of date"*, the Simulator components behind Xcode 27 need
updating. Open Xcode once and let it install them (or run `xcodebuild -runFirstLaunch`), then
reboot if it still complains.

On a real iPhone or iPad, or for **My Mac**, put your signing team in
`Signing.local.xcconfig` at the repo root (it's git-ignored). A free Apple ID works for personal
installs, and Xcode shows its team ID under Settings ▸ Accounts:

```
DEVELOPMENT_TEAM = <your team ID>
```

A team picked under Signing & Capabilities works too, but `xcodegen generate` forgets it.

## Backup & rescue on the Mac

The Mac's **Backup & rescue** page uses the FM-1's USB download mode, through FM1Kit's
`FM1Rescue`: whole-flash backups (saved in Backups › Whole flash as M-Flasher's `.bin` and
`.json`), restoring them, and installing a firmware or a bootloader straight to the flash. Every
job reads the whole flash and saves it first; a write is shown, then made only once confirmed,
and every change is checked against the chip's CRC-32.

Taking the FM-1 from macOS's disk driver needs root, so `Helper/` is a small flash tool, which
the app starts for each job with the person's administrator password, through
`AuthorizationExecuteWithPrivileges`, as M-Flasher does. The two talk over the pipe that call
returns, the tool's standard input and output, one JSON message a line, and the tool quits when
the app closes it. With the simulated FM-1, the page runs FM1Rescue's software chip in the app
instead, so it needs no tool.

It isn't a launchd daemon (`SMAppService`), because macOS asks the person before a program
opens a removable volume, which the FM-1 in download mode is, and it can't ask for a daemon:
the request is refused with no prompt, and Full Disk Access doesn't change that. A root tool
started from the app stays in the person's login, so macOS asks once to let FM-SWITCH use it.
AppleScript's `with administrator privileges` doesn't do this: macOS runs what it starts outside
the person's login, and refuses it without asking, as it does a daemon.

## Releasing the Mac app

1. In Xcode, pick **Any Mac** and run Product ▸ Archive.
2. In the Organiser: Distribute App ▸ **Direct Distribution**. Xcode signs the app and its
   flash tool with Developer ID (making the certificate the first time) and sends it to Apple to be
   notarised.
3. Once it's notarised, Export, then check and zip it for the GitHub release:
   `scripts/package-mac.sh path/to/FM-SWITCH.app`. It checks the app and flash tool are signed with
   Developer ID by the same team, notarised and stapled, then writes
   `.artifacts/release/FM-SWITCH-<version>.zip` and its SHA-256.

## Phase 0 with real hardware

1. **Mac, no risk:** plug the FM-1 into the Mac and run
   `swift run --package-path ../FM1Kit fm1probe ports`, then `... fm1probe identify`.
   It should print something like `FM-1_916`. `fm1probe inspect file.fwsc` shows a package's
   identity and hash.
2. **iPhone, no risk:** on the DEVICE tab, check that the FM-1 appears and reports its
   identity. The handshake is the only thing sent.
3. **iPhone, first flash:** flash a firmware you can easily recover from (e.g. Felucca), with a
   Mac and Chrome installer ready as a fallback. Note the duration. Then deliberately unplug
   mid-write and check that **RESUME** finishes it.
4. Tune FM1Kit's `UpdaterTiming` if the real device wants different pacing.

## Tests and checks

```bash
scripts/check.sh
```

This runs everything CI runs, and it must pass with no warnings. It needs
`brew install xcodegen swiftlint periphery`, and fetches FM1Kit's release (set
`FM1KIT=local` to use `../FM1Kit`). In order, it:

- regenerates the project;
- checks formatting (`swift format`, `.swift-format`);
- lints (`swiftlint --strict`, `.swiftlint.yml`);
- builds with warnings as errors, then runs the tests on the first available iPhone simulator
  (set `SIMULATOR` to choose one);
- does an unsigned iPhone and iPad device build;
- builds the Mac app with warnings as errors and runs the tests on macOS;
- builds the DocC documentation with warnings as errors;
- looks for unused code and imports (`swiftlint analyze` and Periphery);
- builds `fm1-catalogue` with warnings as errors.

To run only some of these, name their groups: `lint`, `build`, `test`, `device`, `mac`,
`docs`, `unused` and `tool`. For example, `scripts/check.sh lint` or `scripts/check.sh build test`.
`test` and `unused` use the results of `build`. CI runs three parallel jobs:
`lint device mac docs tool`, `build test` and `build unused`.

To fix formatting, run `swift format format --in-place --recursive App AppTests Tools`. Some lint
findings can be fixed with `swiftlint --fix`, but check what it changes: it can rewrite a
closure inside `#require` into a key path, which doesn't compile.

The app's tests cover the firmware list (reading the three lists, merging, finding packages,
version ordering and build names) and flashing against the simulated FM-1 (install, resume after
a pulled cable, confirming the same identity and refusing V15 over V15). FM1Kit has its own tests
and checks in its repository.

CI (`.github/workflows/ci.yml`) runs the same checks against FM1Kit's tagged release.

## Staying alive during a flash

Touching the screen doesn't keep an iOS app running. iOS suspends an app when you leave it or
lock the phone, not when you stop touching it. So the app:

- pauses auto-lock for the whole flash;
- asks iOS for the short background grace period if you do leave;
- shows a "keep this screen open" notice;
- relies on the loader's resume when a write is interrupted anyway.
