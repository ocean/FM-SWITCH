import Foundation

/// The words on Backup & rescue, which both looks show.
enum DownloadModeWords {
    static let intro = """
        Download mode reads and writes the FM-1's whole flash: its bootloader, firmware, settings and \
        sounds. It works even when the firmware won't start.
        """
    static let simulated = "This is the simulated FM-1: nothing real is read or written."

    // MARK: - The helper.

    static let helperTitle = "Allow FM-SWITCH's helper"
    static let helperNeedsApproval = """
        Turn on FM-SWITCH in System Settings › General › Login Items & Extensions, under "Allow \
        in the Background". This page carries on once it's on.
        """
    static let openLoginItems = "Open System Settings"
    static let helperMissing = "The helper is missing from this copy of FM-SWITCH. Download the app again."
    static let helperExplained = """
        Reading and writing the flash needs administrator rights, so FM-SWITCH has a small helper \
        that macOS runs for it. You allow it once. It only runs while FM-SWITCH is using it, and \
        only answers FM-SWITCH.
        """
    static let allowHelper = "Allow the helper…"

    // MARK: - Download mode.

    static let inDownloadMode = "Your FM-1 is in download mode"
    static let inDownloadModeDetail = """
        Nothing is written until you confirm it. Switch the FM-1 off and on to leave download mode.
        """
    static let leaveSimulated = "Switch the simulated FM-1 off and on"
    static let enterTitle = "Put your FM-1 in download mode"
    static let enterWithMBootloader = "With m-bootloader on it: switch it off, then hold REC while you switch it on."
    static let enterWithMVave = """
        With M-VAVE's bootloader, download mode is reached through V15 or Felucca, so plug it in \
        running one of those and use the button above.
        """
    static let showsUpHere = "It shows up here once it's in download mode."
    static let askToEnter = "Restart it in download mode"
    static let askingToEnter = "Restarting…"
    static let askToEnterDetail = "Works with V15 and Felucca. Nothing is written."

    // MARK: - Jobs.

    static let jobsTitle = "What would you like to do?"
    static let backUpTitle = "Back up the whole FM-1"
    static let backUpDetail = "Saves everything on it, in a file M-Flasher can restore too. Nothing is written."
    static let backUp = "Back up"
    static let restoreTitle = "Restore a backup"
    static let restoreDetail = "Puts a whole-flash backup back, writing only what's changed."
    static let restore = "Restore"
    static let chooseBackup = "Choose a backup"
    static let chooseFile = "Choose a file…"
    static let installTitle = "Install a firmware"
    static let installDetail = """
        Writes a saved firmware straight to the flash, keeping the bootloader: for an FM-1 whose \
        firmware won't start. To swap firmware the usual way, use Firmwares.
        """
    static let install = "Install"
    static let chooseFirmware = "Choose a firmware"
    static let erasesSettings = "Erase the firmware's settings too"
    static let bootloaderTitle = "Bootloader"
    static let bootloaderDetail = """
        m-bootloader adds a recovery menu (hold PLAY) and download mode (hold REC), so a firmware \
        that won't start can always be fixed from a Mac. Installing V15 later puts M-VAVE's back.
        """
    static let installMBootloader = "Install m-bootloader 1.2"
    static let putBackMVave = "Put back M-VAVE's"

    // MARK: - Running.

    static let readingTitle = "Reading your FM-1"
    static let readingDetail = "It reads everything twice and checks both reads. Nothing is written."
    static let writingTitle = "Writing to your FM-1"
    static let writingDetail = "Keep it plugged in and switched on until this finishes."

    // MARK: - Confirming.

    static let writeTitle = "Write to your FM-1"
    static let mBootloaderChoiceTitle = "m-bootloader: easier rescue, but less switching from your iPhone"
    static let mBootloaderChoice = [
        """
        With m-bootloader, you can always rescue your FM-1 from this Mac by holding REC while \
        switching it on.
        """,
        """
        But if you install AMB-1, Felucca or a firmware like them from your iPhone, installing V15, \
        Open or most firmwares not built on Felucca will need this Mac.
        """,
    ]
    static let mBootloaderChoiceNote =
        "If you mostly switch firmware on your iPhone, keeping M-VAVE's start-up is simpler."
    static let keepsPluggedIn = "I'll keep my FM-1 plugged in and switched on until it's done"
    static let keepMVave = "Keep M-VAVE's"
    static let installMBootloaderNow = "Install m-bootloader"
    static let writeNow = "Write to my FM-1"

    static func saved(_ backup: SavedFlashBackup) -> String {
        "Your FM-1 as it is now is saved: \(backup.file.lastPathComponent)."
    }

    static func changes(_ plan: FlashPlanSummary) -> String {
        "It changes \(plan.sectorCount) of the flash's 256 parts of 4 KB."
    }

    /// What recovering would take if the write were cut off part-way.
    static func recovery(_ plan: FlashPlanSummary) -> String {
        if plan.writesBootArea {
            """
            This writes the boot area, where the bootloader is. If the FM-1 is switched off or unplugged \
            while it's writing, it may not start, and recovering it could need a USB_KEY dongle.
            """
        } else if plan.keepsMBootloader {
            """
            The bootloader isn't touched, so if anything goes wrong, holding REC while switching it on \
            still reaches download mode, to put back the backup just saved.
            """
        } else {
            """
            The bootloader isn't touched, but with M-VAVE's bootloader download mode is only reached \
            through the firmware, so a firmware left unable to start could need a USB_KEY dongle to \
            recover. Installing m-bootloader first avoids that.
            """
        }
    }

    // MARK: - Finished.

    static let backedUp = "Backed up"
    static let nothingToWrite = "Nothing to write"
    static let alreadyHoldsThis = "Your FM-1 already holds this, so nothing was written."
    static let written = "Written and checked"
    static let writtenDetail = "Every change matches the FM-1's own check. Switch it off and on to start it."
    static let mBootloaderKeys = """
        From now on, holding PLAY while switching it on opens m-bootloader's menu, and holding REC \
        starts download mode.
        """
    static let stillInDownloadMode = "Your FM-1 is still in download mode. Switch it off and on to start it."
    static let showInFinder = "Show in Finder"

    static func savedAs(_ backup: SavedFlashBackup) -> String {
        "It's saved as \(backup.file.lastPathComponent), which M-Flasher can restore too."
    }

    static func flashSavedAs(_ backup: SavedFlashBackup) -> String {
        "Its flash is saved as \(backup.file.lastPathComponent)."
    }

    static func flashFromBefore(_ backup: SavedFlashBackup) -> String {
        "Its flash from before is saved as \(backup.file.lastPathComponent)."
    }

    // MARK: - Stopped.

    static let writeFailed = "The write didn't finish"
    static let stopped = "It stopped"
    static let putBackBackup = """
        Keep your FM-1 plugged in and switched on: it's still in download mode. Put back the backup \
        saved before writing, then try again.
        """
    static let restoreBackup = "Restore the backup"

    // MARK: - Saved backups.

    static let backupsTitle = "Whole-flash backups"
    static let restoreToFM1 = "Restore to my FM-1"
    static let deleteTitle = "Delete this backup?"

    static func deleteDetail(_ backup: SavedFlashBackup) -> String {
        "The backup from \(backup.date.formatted(date: .abbreviated, time: .shortened)) goes for good."
    }
}
