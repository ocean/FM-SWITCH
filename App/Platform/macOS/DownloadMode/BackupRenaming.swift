import SwiftUI

/// Asks for a whole-flash backup's new name while `renaming` holds it, then renames its files.
struct BackupRenaming: ViewModifier {
    @Binding var renaming: SavedFlashBackup?
    var store: FlashBackupStore
    @State private var name = ""
    @State private var problem: String?

    func body(content: Content) -> some View {
        content
            .alert(DownloadModeWords.renameTitle, isPresented: isRenaming, presenting: renaming) { backup in
                TextField(DownloadModeWords.renameField, text: $name)
                Button(DownloadModeWords.rename) { rename(backup) }
                Button("Cancel", role: .cancel) { renaming = nil }
            } message: { _ in
                Text(DownloadModeWords.renameDetail)
            }
            .alert(DownloadModeWords.renameFailed, isPresented: isShowingProblem) {
                Button("OK") { problem = nil }
            } message: {
                Text(problem ?? "")
            }
            .onChange(of: renaming) {
                name = renaming?.file.deletingPathExtension().lastPathComponent ?? ""
            }
    }

    private func rename(_ backup: SavedFlashBackup) {
        renaming = nil
        Task {
            do {
                _ = try await store.rename(backup, to: name)
            } catch {
                problem = error.localizedDescription
            }
        }
    }

    private var isRenaming: Binding<Bool> {
        Binding {
            renaming != nil
        } set: { isPresented in
            if !isPresented { renaming = nil }
        }
    }

    private var isShowingProblem: Binding<Bool> {
        Binding {
            problem != nil
        } set: { isPresented in
            if !isPresented { problem = nil }
        }
    }
}

extension View {
    /// Asks for a backup's new name while `renaming` holds it.
    func renamingBackup(_ renaming: Binding<SavedFlashBackup?>, in store: FlashBackupStore) -> some View {
        modifier(BackupRenaming(renaming: renaming, store: store))
    }
}
