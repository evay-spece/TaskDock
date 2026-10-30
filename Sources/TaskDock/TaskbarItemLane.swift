import SwiftUI

/// Measure the viewport before constructing the items. Measuring a scrolling
/// subtree through preferences can lose the width update when its contents change.
struct TaskbarItemLane<Content: View>: View {
    @ViewBuilder let content: (CGFloat) -> Content

    var body: some View {
        GeometryReader { viewport in
            ScrollView(.horizontal, showsIndicators: false) {
                content(max(0, viewport.size.width))
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(width: viewport.size.width, height: viewport.size.height,
                alignment: .leading)
        }
        .frame(minWidth: 0, maxWidth: .infinity)
    }
}
