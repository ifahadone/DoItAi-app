#if DEBUG
import SwiftUI
import DesignSystem

/// DEBUG-only gallery (`-sectographGallery`) previewing the user-selectable ``DialStyle`` options at
/// full size. Same code path the Today hero + Settings picker use. Not compiled into release builds.
struct SectographGallery: View {
    private let order: [DialStyle] = [.classic, .halo, .iconClock, .aurora, .donut]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ForEach(order) { style in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(style.title).font(.headline)
                            Text(style.blurb).font(.caption).foregroundStyle(.secondary)
                            SectographDial(items: DialSample.items, titles: DialSample.titles, style: style)
                                .frame(height: 240).frame(maxWidth: .infinity)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
                    }
                }
                .padding(16)
            }
            .navigationTitle("Dial styles")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private enum DialSample {
    /// Built relative to the current time so the gallery always shows a *current* block (faded past,
    /// glowing now, upcoming) regardless of when it's launched.
    static var items: [SectographItem] {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let n = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        func at(_ delta: Int) -> Int { max(0, min(1439, n + delta)) }
        return [
            SectographItem(id: "run",     startMinute: at(-300), endMinute: at(-235), colorHex: "#34C759",
                           symbolName: "figure.run", isDone: true),
            SectographItem(id: "standup", startMinute: at(-180), endMinute: at(-140), colorHex: "#5E5CE6",
                           symbolName: "person.2.fill"),
            SectographItem(id: "lunch",   startMinute: at(-110), endMinute: at(-55), colorHex: "#FF9F0A",
                           symbolName: "cup.and.saucer.fill"),
            SectographItem(id: "focus",   startMinute: at(-30),  endMinute: at(55),  colorHex: "#2E7DF6",
                           symbolName: "laptopcomputer", isEmphasized: true),
            SectographItem(id: "dentist", startMinute: at(70),   endMinute: at(71),  colorHex: "#FF375F",
                           kind: .instant, symbolName: "cross.case.fill"),
            SectographItem(id: "sync",    startMinute: at(95),   endMinute: at(150), colorHex: "#0FB5C9",
                           symbolName: "chart.bar.fill"),
        ]
    }
    static let titles = ["run": "Run", "standup": "Standup", "lunch": "Lunch",
                         "focus": "Deep work", "sync": "Team sync", "dentist": "Dentist"]
}
#endif
