import SwiftUI

struct IslandRootView: View {
    @EnvironmentObject private var controller: IslandPanelController

    let onHoverChanged: (Bool) -> Void
    let onClick: () -> Void

    var body: some View {
        ZStack {
            IslandBackground(isExpanded: controller.state == .expanded)

            switch controller.state {
            case .collapsed, .hover:
                IslandIndicatorView(isHovering: controller.state == .hover)
            case .expanded:
                IslandExpandedView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onHover(perform: onHoverChanged)
        .onTapGesture(perform: onClick)
    }

    private var cornerRadius: CGFloat {
        controller.state == .expanded ? 28 : 999
    }
}

private struct IslandBackground: View {
    let isExpanded: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: isExpanded ? 28 : 999, style: .continuous)
            .fill(Color(red: 0.025, green: 0.025, blue: 0.028))
            .overlay(
                RoundedRectangle(cornerRadius: isExpanded ? 28 : 999, style: .continuous)
                    .stroke(Color.white.opacity(isExpanded ? 0.12 : 0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(isExpanded ? 0.28 : 0.18), radius: isExpanded ? 24 : 10, y: isExpanded ? 12 : 5)
    }
}
