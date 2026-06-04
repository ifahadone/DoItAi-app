import Foundation

/// Wire DTOs for the AI proxy (ApiSpec §9). Requests use explicit ISO strings for time fields (so the
/// client controls the exact format); responses decode the server's structured proposals. AI NEVER
/// writes the data layer — the client previews a proposal and then writes via the normal `sync/push`.

// MARK: - Shared

/// Priority as the server's string enum ('none'…'p1'), with a bridge to the app's `Priority`.
public enum AIPriority: String, Codable, Sendable {
    case none, p4, p3, p2, p1

    public var asPriority: Priority {
        switch self {
        case .none: return .none
        case .p4: return .p4
        case .p3: return .p3
        case .p2: return .p2
        case .p1: return .p1
        }
    }

    public init(_ priority: Priority) {
        switch priority {
        case .none: self = .none
        case .p4: self = .p4
        case .p3: self = .p3
        case .p2: self = .p2
        case .p1: self = .p1
        }
    }
}

// MARK: - /ai/parse

public struct AIParseRequest: Codable, Sendable, Equatable {
    public var text: String
    public var nowIso: String?
    public var timezone: String?
    public var lists: [String]?
    public var tags: [String]?

    public init(text: String, nowIso: String? = nil, timezone: String? = nil, lists: [String]? = nil, tags: [String]? = nil) {
        self.text = text
        self.nowIso = nowIso
        self.timezone = timezone
        self.lists = lists
        self.tags = tags
    }
}

public struct AIParsedTask: Codable, Sendable, Equatable {
    public var title: String
    public var start: Date?
    public var durationMinutes: Int?
    public var due: Date?
    public var priority: AIPriority
    public var tags: [String]
    public var listHint: String?

    public init(title: String, start: Date? = nil, durationMinutes: Int? = nil, due: Date? = nil,
                priority: AIPriority = .none, tags: [String] = [], listHint: String? = nil) {
        self.title = title
        self.start = start
        self.durationMinutes = durationMinutes
        self.due = due
        self.priority = priority
        self.tags = tags
        self.listHint = listHint
    }
}

public struct AIParseResponse: Codable, Sendable, Equatable {
    public var task: AIParsedTask
}

// MARK: - /ai/schedule

public struct AIScheduleTask: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var durationMinutes: Int
    public var priority: AIPriority
    public var dueIso: String?

    public init(id: String, title: String, durationMinutes: Int, priority: AIPriority, dueIso: String? = nil) {
        self.id = id
        self.title = title
        self.durationMinutes = durationMinutes
        self.priority = priority
        self.dueIso = dueIso
    }
}

public struct AITimeSlot: Codable, Sendable, Equatable {
    public var startIso: String
    public var endIso: String
    public init(startIso: String, endIso: String) {
        self.startIso = startIso
        self.endIso = endIso
    }
}

public struct AIScheduleRequest: Codable, Sendable, Equatable {
    public var tasks: [AIScheduleTask]
    public var freeSlots: [AITimeSlot]
    public var bufferMinutes: Int
    public var intent: String?

    public init(tasks: [AIScheduleTask], freeSlots: [AITimeSlot], bufferMinutes: Int = 5, intent: String? = nil) {
        self.tasks = tasks
        self.freeSlots = freeSlots
        self.bufferMinutes = bufferMinutes
        self.intent = intent
    }
}

public struct AIProposedBlock: Codable, Sendable, Equatable, Identifiable {
    public var taskId: String
    public var title: String
    public var startIso: String
    public var endIso: String
    public var reason: String
    public var id: String { taskId }
}

public struct AIUnscheduledTask: Codable, Sendable, Equatable, Identifiable {
    public var taskId: String
    public var title: String
    public var reason: String
    public var id: String { taskId }
}

public struct AIScheduleProposal: Codable, Sendable, Equatable {
    public var blocks: [AIProposedBlock]
    public var unscheduled: [AIUnscheduledTask]
    public var ranked: Bool
}

// MARK: - /ai/search

public struct AISearchRequest: Codable, Sendable, Equatable {
    public var query: String
    public var nowIso: String?
    public init(query: String, nowIso: String? = nil) {
        self.query = query
        self.nowIso = nowIso
    }
}

public struct AISearchFilter: Codable, Sendable, Equatable {
    public var text: String?
    public var priorities: [AIPriority]
    public var tags: [String]
    public var listHint: String?
    public var dueBefore: Date?
    public var dueAfter: Date?
    public var includeCompleted: Bool
}

public struct AISearchResponse: Codable, Sendable, Equatable {
    public var filter: AISearchFilter
}

// MARK: - /ai/routine-suggest

public struct AIRoutineSuggestTask: Codable, Sendable, Equatable {
    public var title: String
    public var completedAtIso: String?
    public init(title: String, completedAtIso: String? = nil) {
        self.title = title
        self.completedAtIso = completedAtIso
    }
}

public struct AIRoutineSuggestRequest: Codable, Sendable, Equatable {
    public var tasks: [AIRoutineSuggestTask]
    public init(tasks: [AIRoutineSuggestTask]) { self.tasks = tasks }
}

public struct AIRoutineStepSuggestion: Codable, Sendable, Equatable {
    public var title: String
    public var minutes: Int
}

public struct AIRecurrenceSuggestion: Codable, Sendable, Equatable {
    public var weekdays: [Int]?
    public var everyNDays: Int?
}

public struct AIRoutineSuggestion: Codable, Sendable, Equatable, Identifiable {
    public var name: String
    public var steps: [AIRoutineStepSuggestion]
    public var recurrence: AIRecurrenceSuggestion
    public var confidence: Double
    public var id: String { name }
}

public struct AIRoutineSuggestions: Codable, Sendable, Equatable {
    public var suggestions: [AIRoutineSuggestion]
}

// MARK: - /ai/brief + /ai/review (SSE)

public struct AIBriefTask: Codable, Sendable, Equatable {
    public var title: String
    public var priority: AIPriority
    public var dueIso: String?
    public var scheduledStartIso: String?
    public init(title: String, priority: AIPriority, dueIso: String? = nil, scheduledStartIso: String? = nil) {
        self.title = title
        self.priority = priority
        self.dueIso = dueIso
        self.scheduledStartIso = scheduledStartIso
    }
}

public struct AIBriefRequest: Codable, Sendable, Equatable {
    public var nowIso: String?
    public var tasks: [AIBriefTask]
    public var focusMinutesPlanned: Int?
    public init(nowIso: String? = nil, tasks: [AIBriefTask] = [], focusMinutesPlanned: Int? = nil) {
        self.nowIso = nowIso
        self.tasks = tasks
        self.focusMinutesPlanned = focusMinutesPlanned
    }
}

public struct AIReviewHabit: Codable, Sendable, Equatable {
    public var name: String
    public var streakCurrent: Int
    public init(name: String, streakCurrent: Int) {
        self.name = name
        self.streakCurrent = streakCurrent
    }
}

public struct AIReviewRequest: Codable, Sendable, Equatable {
    public var weekStartIso: String?
    public var completedCount: Int
    public var createdCount: Int
    public var focusMinutes: Int
    public var topTags: [String]?
    public var habits: [AIReviewHabit]?
    public init(weekStartIso: String? = nil, completedCount: Int, createdCount: Int, focusMinutes: Int,
                topTags: [String]? = nil, habits: [AIReviewHabit]? = nil) {
        self.weekStartIso = weekStartIso
        self.completedCount = completedCount
        self.createdCount = createdCount
        self.focusMinutes = focusMinutes
        self.topTags = topTags
        self.habits = habits
    }
}

/// One parsed SSE event from a streamed `/ai/brief` or `/ai/review` (ApiSpec §9.5).
public enum AINarrativeEvent: Sendable, Equatable {
    case text(String)
    case highlights([String: Int])
    case done

    /// Parse one SSE `data:` payload (the JSON after `data: `). Returns nil for keep-alives/unknowns.
    public static func parse(dataPayload: String) -> AINarrativeEvent? {
        let trimmed = dataPayload.trimmingCharacters(in: .whitespaces)
        if trimmed == "[DONE]" { return .done }
        guard let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return nil }
        switch type {
        case "text":
            return .text(obj["delta"] as? String ?? "")
        case "highlights":
            let raw = obj["highlights"] as? [String: Any] ?? [:]
            var ints: [String: Int] = [:]
            for (k, v) in raw { if let n = v as? Int { ints[k] = n } else if let d = v as? Double { ints[k] = Int(d) } }
            return .highlights(ints)
        default:
            return nil
        }
    }
}
