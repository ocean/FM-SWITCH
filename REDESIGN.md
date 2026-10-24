# FM-SWITCH redesign: a friendly FM-1 app

Started 2026-10-22. Mockups: https://claude.ai/artifact/54z5aZU4dtdCc3BMPfRYsC

## Aim

An app for FM-1 owners who aren't technical: it feels like a proper iOS and macOS app, with a
little character. The current 8-bit Phosphor look stays as a hidden **Retro** look.

## Principles

- **Tasks, not tabs.** The home screen shows the FM-1 and up to three tasks:
  - **Change firmware** (iOS and Mac).
  - **Save my FM-1** (open firmware over MIDI on both; a full download-mode backup on the Mac).
  - **Add a safety net** (m-bootloader), or **Rescue my FM-1** on the Mac.

  Each task is a short step-by-step flow. The firmware list and saved copies are still
  reachable: through Browse on iOS, and through the sidebar's Library on the Mac and iPad.
- **The FM-1 is the character.** A drawn FM-1 based on the real panel, with knobs, screen, page
  buttons, PLAY/REC, OCT−/OCT+ and keys. Its screen shows what's happening, and it lights the
  keys to hold. Tapping its screen five times finds Retro: a "You found Retro!" note offers
  **Switch now** or **Later**, and tapping the note opens Settings, where Retro and its pixel app
  icon (iPhone and iPad) now sit. It doesn't switch the whole app without asking.
- **Plain words.** Say "your projects, samples and settings", "Getting ready / Installing /
  Checking / Restarting" and "Carry on installing". Never say VM, BTIF, hex, staging or loader in
  the main flow. Technical facts go behind a **Details** disclosure, which on the Mac also shows
  the flash map.
- **Safe by default.**
  - A two-item checklist before every write: a data cable, and staying plugged in.
  - Save before writing, where the firmware allows it.
  - One progress bar that never goes backwards.
  - Every problem screen says whether the FM-1 is fine as it is and offers one main button.
- **Standard Apple parts.**
  - System font with Dynamic Type, SF Symbols, light and dark mode, and VoiceOver labels.
  - `NavigationStack` on iPhone; `NavigationSplitView` with a sidebar on the Mac and iPad.
  - Firmware cards carry a badge of their own: initials on two colours, a light half and a
    dark one, split across or corner to corner (896 designs, from 16 hues evenly spaced in
    OKLCH). It comes from the name alone, so it never changes as other firmwares join the list.
    Later they could use each project's own artwork, where its licence allows.

## How it should feel

These rules adapt Emil Kowalski's apple-design skill
(github.com/emilkowalski/skills, `skills/apple-design`), which draws on Apple's WWDC talks, to
SwiftUI. The feeling to aim for is **calm and confident**: people are trusting the app with their
instrument.

Drew's direction (2026-10-22) is to put the effort into motion and interaction from the skill, not
into the iOS 26 glass look. The motion rules below are the part to build carefully. They're also
summarised in a note on the canvas.

**Motion building blocks (SwiftUI):**
- `PressableStyle`, a `ButtonStyle` used by every card and button. It shrinks to 0.97 while
  `configuration.isPressed`, with `.spring(response: 0.2, dampingFraction: 1)`, and drops the
  shrink under Reduce Motion.
- `Motion.standard = .spring(response: 0.35, dampingFraction: 1)`, used for every transition and
  state change.
- `Motion.flick = .spring(response: 0.35, dampingFraction: 0.8)`, used only after a gesture
  with momentum.
- `Motion.fade = .easeInOut(duration: 0.2)`, used for text changes and as the Reduce Motion
  replacement for slides.
- Interactive swipe-back keeps the system's navigation gesture, which already tracks 1:1 and
  decides by release speed. Our custom recogniser on iOS must keep that behaviour.
- Haptics with `.sensoryFeedback(_:trigger:)`, fired from the same state change that drives
  the visual, so both land on the same frame.

- **Respond on touch-down.**
  - Cards and buttons use one shared `ButtonStyle` that scales to 0.97 and dims slightly while
    pressed, with no delay.
  - Nothing on the input path waits on a timer.
- **Springs, not fixed timings.**
  - Every transition uses a critically damped spring (`.spring(response: 0.35,
    dampingFraction: 1)`). Bounce only follows a gesture that carried momentum, such as a
    swipe back released early. Nothing bounces just for appearing.
  - Transitions start from the current on-screen value, so pressing back during a push
    reverses smoothly.
- **Progress only goes forwards.** The bar animates to each new FM1Kit value with that spring
  and never moves backwards, matching FM1Kit's promise. Stage changes cross-fade the label.
- **Same way in, same way out.**
  - Flows push from the right and swipe back to the right.
  - Installing is a full-screen cover that slides up, can't be swiped away while writing, and
    goes back down to Home.
  - Sheets come from the control that opened them, using a popover on iPad and the Mac.
- **Solid surfaces, not glass.** Drew decided against Liquid Glass and translucent materials on
  2026-10-22: they don't fit the warm, physical feel the app is going for.
  - Use opaque warm-grey backgrounds, white cards and solid bars, with hierarchy from spacing,
    weight and the odd hairline.
  - Opt out of the OS's glass where SwiftUI applies it by default: solid toolbar backgrounds,
    and no glass button styles.
  - The Mac sidebar is still a standard sidebar, coloured to match.
- **Four kinds of feedback, each in its own place.**
  - *Status* is the connection pill and the FM-1's screen.
  - *Completion* is Done, with a `.success` haptic on the same frame as the tick.
  - *Warning* is the note before installing, with no haptic.
  - *Error* is the problem screen, with a `.error` haptic.
  - Ticking a checklist item gives a light `.selection` tap. That's the whole haptic
    vocabulary, so it stays meaningful.
- **Wayfinding.** Every screen answers four questions: where am I, where can I go, what's here,
  and how do I get out.
  - Installing is the one screen that can't be left. It says why ("keep it plugged in") and what
    happens if it stops anyway (you carry on later).
  - Labels name what's there: "My FM-1", "Saved copies", "Change firmware". Avoid vague ones
    like "Home" or "Tools".
- **Confirm sparingly.** The two-item checklist is the only confirmation before a write. Saving
  and browsing never ask. A dialog appears only for what can't be undone, such as erasing your
  projects on the Mac.
- **Type.**
  - System text styles throughout (`.largeTitle`, `.title2`, `.headline`, `.body`,
    `.footnote`), so Dynamic Type and size-specific tracking come for free.
  - Weight shows emphasis, never a custom fixed letter spacing.
  - Layouts use `ViewThatFits` and stacks that wrap at accessibility sizes.
- **Accessibility settings.**
  - *Reduce Motion:* cross-fades instead of slides, and the lit keys glow steadily instead of
    pulsing.
  - *Increase Contrast:* card borders and darker secondary text.
  - Nothing loops slowly. A lit key's pulse is about 1 Hz, never a 5-second breath.
- **The FM-1 drawing:**
  - Its screen changes with a short cross-fade.
  - A lit key fades in with the default spring.
  - It's one VoiceOver element, for example "FM-1, running SLOOP 2.7.1" or "FM-1, with its PLAY
    key lit".
- **Prototype before polishing.** The canvas is playable: Choose → Before you start →
  Installing (which runs to the end) → Done. Build the SwiftUI version of this one flow against
  the simulated FM-1 first, and judge it on a phone (and in slow motion) before drawing the
  rest.

## Design checks (automatic)

These rules from the apple-design skill and the plan are checked, so they don't drift:
- **Contrast:** `ContrastTests` checks every text and background pairing the screens use, in
  light and dark mode: 4.5:1 for text, 3:1 for icons and outlines (WCAG 2.2). It found two
  failures when added, both now fixed: white ticks on dark-mode green (2.5:1, now 3.4:1 with
  #2E9E57), and purple ticks and outlines on dark cards (2.3:1, now 5.8:1 with `firmwaresTint`).
- **SwiftLint custom rules** in `.swiftlint.yml`:
  - `no_glass`: no glass effects.
  - `standard_motion`: animations only from `Motion`, so they respect Reduce Motion.
  - `dynamic_type`: text styles, not fixed sizes, except in the FM-1 drawing and the badges.
  - `sensory_feedback`: haptics only through `.sensoryFeedback`.
- **`accessibility_trait_for_button`:** anything tappable tells VoiceOver it's a button or a link.
- **Accessibility audit:** `AppUITests/AccessibilityAuditTests` runs Apple's
  `performAccessibilityAudit` on My FM-1, Firmwares, Settings, Save my FM-1 (ready, and once
  saved, against the simulated FM-1 on open firmware) and the welcome notice, in light,
  dark and an accessibility text size, on iPhone (part of the `test` group; the Mac skips it, as
  Mac UI tests need the Accessibility permission granted by hand). It skips only:
  - text inside illustrations (the FM-1 drawing and badges, marked `decorative`), which VoiceOver
    reads as one image but XCUITest still lists;
  - contrast on text passing under the list's floating search field, or scrolled out of view
    (XCUITest calls it not hittable), or partly under a floating note and its shadow;
  - firmware summaries cut to two lines in the list (`summary`), shown in full on their page;
  - its Dynamic Type check, which flags text it enlarges itself; the large-text runs check
    text as actually drawn instead.
  `RetroNoteTests` also audits the "You found Retro!" note, without the clipped-text check, which
  reports one of its two buttons as cut short at random though neither is, and checks that
  Later, Switch now and tapping the note each do what they say.
  `TapTargetTests` checks what the audit can't: that a card that looks tappable answers a tap
  anywhere on it. It's there because the Details card on a firmware's page only answered its
  small arrow on the Mac, and a 28-point strip on iPhone; `WholeHeaderDisclosureStyle` fixes both.
  When added, it found Settings' section headers and footers in the system grey falling just short
  on the warm ground (now `secondaryInk`), and firmware names cut short beside their version
  instead of the row wrapping.

## Appearance: System, Light and Dark

Drew asked for this on 2026-10-22. The first round's light look (warm grey ground, white cards,
friendly task buttons) is the reference.

- A new setting, `AppSettings.appearance: Appearance` (`.system`, `.light`, `.dark`), defaults to
  `.system` and is saved in `UserDefaults`.
  - The root applies `.preferredColorScheme(appearance.colorScheme)`, where `.system` gives
    `nil`. On iOS and macOS this follows the device live, including automatic switching at
    sunset, with no code of our own.
  - On the Mac, the setting also sets `NSApp.appearance`, so menus and sheets match.
- Settings shows the three choices as preview tiles (System split light and dark), followed by
  a line saying what System is doing right now ("Matches your device, which is dark right now").
- Colours come from a small set of asset-catalogue colours, each with light and dark values:
  - ground: #EEE8DD / #141413 (warmed from #F4F3F0 on 2026-10-22, towards parchment)
  - card: #FFFFFF / #232321
  - ink: #1C1C1E / #F2F1EE
  - secondary ink: #5E5E63 / #A8A6A1
  - accent fill: #C2410C in both
  - accent text, for links and text buttons: #5B21B6 / #FF9259. In light mode it's a deep violet
    (from 2026-10-23), as orange text looked weak on the light ground, and darker than the
    firmwares' purple so links don't read as buttons; in dark mode it's a lighter orange.
  - control: #E2DBCD / #2C2B29, and hairlines #E8E2D7 / #33322F, warmed with the ground.

  Every pair passes 4.5:1. Firmware tints stay the same in both.
- Changing the setting cross-fades the colours (`withAnimation(.easeInOut(duration: 0.25))`)
  rather than flashing.
- **Retro** is its own dark look and ignores this setting. When the setting is Light, Retro's
  settings row says so.

## Mac sidebar icons

Use SF Symbols, as Mail, Music and Finder do, rather than coloured app-style tiles like System
Settings. Use outline symbols, tinted per row with `listItemTint(_:)`:

| Row | Symbol | Tint |
|---|---|---|
| My FM-1 | custom `fm1` symbol, one size up (`.imageScale(.large)`) | neutral (`.monochrome`) |
| **Firmwares** | `arrow.left.arrow.right` | **purple**, no badge |
| Save my FM-1 | `square.and.arrow.down` | blue |
| Rescue my FM-1 | `lifepreserver` | green |
| Backups | `archivebox` | neutral |

**The firmware list is the star.** "Change firmware" and the firmware list are one place. On the
Mac it's the sidebar row **Firmwares**; on iPhone it's Home's first card, which is a filled purple
card and the largest one. Firmware you've downloaded appears through the list's **Saved** filter
rather than a separate row. The sidebar shows no count, because a badge reads as "136 new"; the count goes on the list itself, and on the iPhone's Home card. Purple (#6D28D9) belongs to firmwares everywhere. The rest of the app
keeps the orange accent.

- The task colours match the iPhone Home screen's task tiles, so the same task looks the same on
  both platforms.
- The selected row uses the system selection, with the symbol turning white.
- `fm1` is a custom SF Symbol made in the SF Symbols app from the FM-1 drawing: body, screen
  and keys. It's exported as a symbol template in the asset catalogue, so it scales with the
  sidebar's icon size setting and matches the other symbols' weights.
- The same symbols label the iPhone task tiles, so there's one icon per task everywhere.

## Screens (mocked)

| Screen | Notes |
|---|---|
| Home | FM-1 drawing, a connection pill, three task cards and a settings button |
| Change firmware: choose | Search, filters (All, Official, Saved, Games), firmware cards with the current one marked |
| Before you start | Firmware header, links, a two-item checklist and a note about saving first; Install stays disabled until both items are ticked |
| Installing | FM-1 screen mirrors the stage; one bar; four friendly stages |
| Done | Confirms the identity the FM-1 reports, a link to the manual, and Done |
| Safety net | Explains m-bootloader honestly; asks "hold PLAY: do you see a menu?" and remembers the answer until the next V15 install |
| Problem | Example: cable pulled while writing. "Nothing is broken", two steps, **Carry on installing**, and Details to copy for Discord |
| Settings: appearance | System / Light / Dark tiles that re-theme the screen live; System follows the device. Also the firmware list options and About |
| Home in dark mode | The same Home in the dark palette |
| Settings: Retro | Shown once found: Standard/Retro look, phosphor colour, scanlines, flicker |
| Mac: Save my FM-1 | Sidebar (Home; Tasks; Library), a stepper, the FM-1 with REC lit, a password note, and Details holding the flash map |

## Platform split

- **iOS/iPadOS:** switching firmware over MIDI, as now.
  - Suggest m-bootloader without requiring it. It's new and its author has tested it on one FM-1.
  - Before a V15 install, warn that it puts the stock bootloader back, and offer m-bootloader
    again afterwards.
  - An iPhone can't repair an FM-1 from download mode, and the app must say so.
- **macOS:** Developer ID-signed and notarised, downloaded from fm-1.drewr.dev.
  - Later it gets download-mode backup and restore, m-bootloader installs and Rescue. That needs
    root, through FM1Kit's helper work.
  - Not before FM1Kit has proved the protocol.

## What the redesign needs from FM1Kit (after 0.3.0)

1. A next step for each `FM1UpdateError` (try again, resume, reconnect, hold keys, needs a
   computer), plus whether the FM-1 is fine as it is. This drives the Problem screen.
2. One overall progress value with stage names that never goes backwards. This drives Installing.
3. A plain device summary: what it runs, and whether it's waiting mid-update. This drives Home.
4. An m-bootloader `.fwsc` install over MIDI from V15. This drives Safety net.
5. `backUpOpenFirmware(progress:)` / `OpenFirmwareBackup.write(to:)` (0.3.0). This drives
   Save my FM-1 for open firmware.

## Built so far (2026-10-22, uncommitted)

- **Settings:** `AppSettings` has `look` (standard or Retro), `isRetroFound` and `appearance`.
  The app follows the Appearance setting; Retro stays dark. The Info.plist no longer forces dark.
- **Roots:** `RootView` picks `StandardRootView` or `RetroRootView` (the old root, unchanged).
  Both looks share the first list download and the MIDI retry. Retro's SETUP has SWITCH TO
  STANDARD.
- **Shared logic** (`App/Model`):
  - `InstallReadiness`: the install-check rules, which Retro's confirm screen now uses too.
  - `FirmwareFilter`: search, test versions and links-only, shared with Retro's list.
  - `InstallProgress`: one value that never goes backwards, with four stages.
  - `DeviceSummary`: the FM-1 described in plain words.
  - `EntryDescriptions`: where a firmware is listed and where its file comes from.
- **Standard look** (`App/Standard`):
  - `Palette` (light and dark colours) and `Motion` (springs, press feedback, button styles).
  - `FM1Drawing`, and Home, which includes the Retro easter egg (five taps on the screen).
  - The firmware list, firmware page, Before you start, the install cover with done and problem
    endings, Factory sounds, Settings and the welcome notice.
  - Save my FM-1 (2026-10-23, FM1Kit 0.3.0): on Home and in the sidebar. For open firmware it
    saves every project, the project being edited and the samples, with progress, then offers
    Share (a zip) and, on the Mac, Show in Finder. It lists earlier saves to share or delete.
    Other firmwares get a plain explanation. Saves go in a Backups folder (`BackupStore`), as the
    `.fm1` and `.fm1s` files M-VAVE's workbench reads. The simulated FM-1 can run open firmware with projects, from Settings.
  - iPhone uses a navigation stack; the Mac and iPad use a sidebar. The Mac also has a Settings
    scene (⌘,).
- **Tests:** `StandardLookTests`, `BackupTests`.
- **Debug only:** `-openPage firmwares|save|settings|<firmware id>` opens a page for screenshots.

**Not yet:**
- The custom `fm1` sidebar symbol (`pianokeys` stands in for it).
- Safety net and Rescue, which wait for FM1Kit.
- Saving before a firmware change, offered on Before you start when the FM-1 runs open firmware.
- Save my FM-1 in the Retro look.
- Opting out of iOS 26's glass controls (`UIDesignRequiresCompatibility`), if wanted.

## Build order (steps 1, 2, 3 and 5 done, as above)

1. A theme layer: a `Look` setting (standard or Retro), with Phosphor moved behind it unchanged,
   plus the `Appearance` setting (System, Light, Dark), the light/dark colour set and the
   `Motion` and `PressableStyle` building blocks. Shared components check the look.
2. The FM-1 drawing as a SwiftUI view, with screen text, lit keys and progress, plus its
   accessibility label.
3. Home plus Change firmware (choose, check, install, done, problem) on today's FM1Kit API, then
   switch to FM1Kit's progress and next steps when they land.
4. Safety net, once FM1Kit's m-bootloader install exists.
5. Save my FM-1 for open firmware (0.3.0).
6. The Mac sidebar layout, then the download-mode tasks when FM1Kit's helper is proven.

## Tips (2026-10-24)

Every feature is free, and tips unlock nothing.

- **iPhone and iPad:** three in-app purchases, as consumables: Nibble ($2), Byte ($5) and
  Kilobyte ($10), as `dev.drewr.fmswitch.tip.nibble`, `.byte` and `.kilobyte`. `FMSwitch.storekit` stands in for App
  Store Connect when run from Xcode, and in `TipJarTests`.
- **Mac:** a link to ko-fi.com/oceanicity, as in-app purchases need the Mac App Store.
- **Where:** a Tip jar section in Settings (a panel in Retro), and a card that slides up from the
  bottom after the fifth install and again after the fifteenth, once each, with the tips on it.

## Files in iCloud Drive (2026-10-24)

Firmwares and backups live in the app's own iCloud Drive folder, `iCloud.dev.drewr.fmswitch`,
which the Files app and the Finder show as FM-SWITCH, with Firmwares and Backups inside. The
iPhone, iPad and Mac apps all see the same files.

- **iCloud Drive off:** the same two folders in the app's Documents, on this device only. Settings
  says which. Turning iCloud Drive on later moves them in at the next launch.
- **Firmwares:** named packages ("Felucca 1.2.fwsc"), each with its details in
  `Firmwares/.details/<sha256>.json`. Devices only add or remove whole files, so they never write
  over each other. The built-in V15 is read from the app and never saved.
- **Files from another device:** `ICloudWatcher` fetches everything as soon as it's listed, as
  it's all small. An install waits for its package if it hasn't arrived yet.
- **Before:** firmwares were in Application Support without names. That folder is deleted at
  launch, so anything downloaded before has to be downloaded again.

## App icon

The FM-1, simplified so it reads at small sizes: four knobs and the octave keys on the left, the
four knobs and six page keys on the right, and eight pill keys. Its screen shows the
firmware-swap arrows in white, and its keys are lit as on the stock firmware: HOME white, PLAY
green and REC red. It's on the app's purple, deep purple-black in dark mode, and greyscale for
tinted mode. The Mac gets it in its rounded square.

`scripts/make-app-icon.swift` draws it from code, not a pixel map. The screen is bigger than the
real one's so the arrows stay arrows at Home Screen sizes. A smaller screen with more even
arrows, also considered, is kept in the script: `scripts/make-app-icon.swift symmetrical`.

Retro's pixel cartridge stays as the alternate icon, offered once Retro's been found.

The launch screen is the icon on the standard look's ground, light or dark, even in Retro.

Later: a choice of the FM-1's colourways in Settings, so the drawing looks like your own. The
FM-1 doesn't say which colourway it is: over USB and MIDI it reports only its name, a per-unit
serial number and its firmware version, and it doesn't answer MIDI's identity request. So the
person picks it, and the app remembers it against the serial number, showing that colour
whenever that FM-1 is plugged in. Felucca and some other firmwares report no serial; then the
last colourway chosen is used. FM1Kit will add the serial to its device summary (API 3), so
this waits for that.

## Open questions for Drew

- Accent colour: the mockups use a burnt orange (#C2410C). Keep it, or take one from the FM-1
  itself?
- Should iPhone keep a tab bar (Home, Browse, Saved), or only the home tasks plus a Browse link?
- Name: keep "FM-SWITCH", or something friendlier now that it does more than switch?
