import SwiftUI

/// Shared motion language for DoIT. Motion is short, spatially consistent, and automatically removed
/// when the user enables Reduce Motion.
public extension View {
    /// A restrained fade-and-rise used for the primary hierarchy on a newly presented screen.
    func doitEntrance(order: Int = 0, trigger: AnyHashable = 0) -> some View {
        modifier(DoITEntranceModifier(order: order, trigger: trigger))
    }

    /// Animates state-driven layout changes with the app's standard spring.
    func doitStateAnimation<Value: Equatable>(value: Value) -> some View {
        animation(.spring(response: 0.38, dampingFraction: 0.86), value: value)
    }
}

private struct DoITEntranceModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let order: Int
    let trigger: AnyHashable
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 12)
            .onAppear { reveal() }
            .onChange(of: trigger) { _ in
                guard !reduceMotion else { visible = true; return }
                visible = false
                reveal()
            }
    }

    private func reveal() {
        guard !reduceMotion else { visible = true; return }
        withAnimation(
            .spring(response: 0.42, dampingFraction: 0.88)
                .delay(Double(max(0, order)) * 0.055)
        ) {
            visible = true
        }
    }
}

/// Consistent tactile feedback for prominent custom buttons without changing native button semantics.
public struct DoITPressStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A compact heading for progressive sections. The subtitle describes scope, not marketing value.
public struct DoITSectionHeading: View {
    private let title: String
    private let subtitle: String?
    private let actionTitle: String?
    private let action: (() -> Void)?

    public init(
        _ title: String,
        subtitle: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
            }
        }
    }
}
