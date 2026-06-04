import SwiftUI
import SyncCore
import DesignSystem

/// A visual picker for the Today day-dial style (P5-5 sectograph variants). Shows a live preview of
/// every ``DialStyle`` with sample data; tapping one selects it (persisted in `@AppStorage("dialStyle")`)
/// and the Today hero updates immediately. Reached from Settings → Day dial, and by tapping the dial.
struct DialStylePicker: View {
    @AppStorage("dialStyle") private var dialStyleRaw = DialStyle.arc.rawValue

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(DialStyle.allCases) { style in
                    let selected = style.rawValue == dialStyleRaw
                    Button {
                        withAnimation(.snappy) { dialStyleRaw = style.rawValue }
                    } label: {
                        VStack(spacing: 8) {
                            SectographDial(items: DialPreviewSample.items, titles: DialPreviewSample.titles, style: style)
                                .frame(height: 150)
                                .frame(maxWidth: .infinity)
                                .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18)
                                        .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 3)
                                )
                                .overlay(alignment: .topTrailing) {
                                    if selected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.title3)
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, Color.accentColor)
                                            .padding(8)
                                    }
                                }
                            Text(style.title)
                                .font(.subheadline.weight(selected ? .semibold : .regular))
                                .foregroundStyle(selected ? Color.accentColor : .primary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(style.title)
                    .accessibilityValue(selected ? "Selected" : "")
                    .accessibilityHint(style.blurb)
                }
            }
            .padding()
        }
        .navigationTitle("Day-dial style")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Sample blocks for the style previews, built relative to "now" so each preview shows a live current
/// block (and a faded past + an upcoming one) regardless of when the picker is opened.
enum DialPreviewSample {
    static var items: [SectographItem] {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let n = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        func at(_ delta: Int) -> Int { max(0, min(1439, n + delta)) }
        return [
            SectographItem(id: "run",   startMinute: at(-300), endMinute: at(-240), colorHex: "#34C759",
                           symbolName: "figure.run", isDone: true),
            SectographItem(id: "lunch", startMinute: at(-120), endMinute: at(-60),  colorHex: "#FF9F0A",
                           symbolName: "cup.and.saucer.fill"),
            SectographItem(id: "focus", startMinute: at(-25),  endMinute: at(55),   colorHex: "#2E7DF6",
                           symbolName: "laptopcomputer", isEmphasized: true),
            SectographItem(id: "sync",  startMinute: at(95),   endMinute: at(150),  colorHex: "#5E5CE6",
                           symbolName: "person.2.fill"),
        ]
    }
    static let titles = ["run": "Run", "lunch": "Lunch", "focus": "Deep work", "sync": "Team sync"]
}
