import SwiftUI

/// The Plan tab: a segmented switch between the **Planner** (the day-grid, P2-3) and the **Lists**
/// (smart lists, P1-G). Owns the single `NavigationStack` both children push into.
struct PlanView: View {
    @State private var mode: Mode = .planner

    enum Mode: String, CaseIterable, Identifiable {
        case planner = "Planner"
        case lists = "Lists"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .planner: CalendarView()
                case .lists: SmartListsView()
                }
            }
            .navigationTitle("Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)
                }
            }
        }
    }
}
