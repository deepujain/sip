import SwiftUI

/// Drawn by SwiftUI, not AppKit, so it answers the first click in a panel that never takes focus.
struct PillButton: View {
    let title: String
    let prominent: Bool
    var large = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: large ? 17 : 12, weight: .semibold, design: .rounded))
                .padding(.horizontal, large ? 28 : 12)
                .padding(.vertical, large ? 12 : 5)
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .background(prominent ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.quaternary), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}
