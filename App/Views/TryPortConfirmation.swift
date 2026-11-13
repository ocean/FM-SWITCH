import FM1Kit
import SwiftUI

extension View {
    /// Asks whether to try a port as an FM-1 before trying it, in both looks.
    ///
    /// - Parameter port: The port the person asked to try, until they say they're sure.
    /// - Returns: The view, asking while `port` is set.
    func confirmingTryPort(_ port: Binding<MIDIPortDescriptor?>) -> some View {
        modifier(TryPortConfirmation(port: port))
    }
}

private struct TryPortConfirmation: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var port: MIDIPortDescriptor?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Try \(port?.name ?? "this port") as an FM-1?",
                isPresented: Binding(get: { port != nil }, set: { if !$0 { port = nil } }),
                titleVisibility: .visible,
                presenting: port
            ) { port in
                Button("Try This Port") { Task { await model.device.tryPort(port) } }
            } message: { _ in
                Text(
                    """
                    FM-SWITCH sends it a short question that only an FM-1 answers, and keeps trying it \
                    from now on. Do this if it's your FM-1, running a firmware that names its USB port \
                    differently.
                    """)
            }
    }
}
