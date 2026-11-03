import SwiftUI

/// Whether a scroll view has scrolled its content more than `offset` up out of sight.
///
/// It reads the scroll view's own position, as reading the filters' place while the list scrolls
/// stalls the Mac's layout. Before iOS 18 and macOS 15, it never has.
struct ScrolledPast: ViewModifier {
    var offset: CGFloat
    @Binding var isPast: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18, macOS 15, *) {
            content.onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > offset
            } action: { _, isPastNow in
                isPast = isPastNow
            }
        } else {
            content
        }
    }
}
