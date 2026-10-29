import Foundation

enum Prefs {
    static let bottleML = "bottleML"
    static let profile = "profile"
    static let customGoalML = "customGoalML"
    static let active = "active"
    static let wakeMinutes = "wakeMinutes"
    static let sleepMinutes = "sleepMinutes"
    static let reminders = "reminders"
    static let dryspell = "dryspell"
    static let respectCalls = "respectCalls"
    static let onScreen = "onScreen"
    static let sounds = "sounds"
    static let lockMinutes = "lockMinutes"
    static let graceMinutes = "graceMinutes"
    static let hasOnboarded = "hasOnboarded"
    static let history = "history"
    static let corner = "corner"
    static let showInDock = "showInDock"
    /// Where you dragged the bottle: the panel's origin, as [x, y].
    static let deskOrigin = "deskOrigin"
    /// Set once Sip has added itself to login items, so turning it off in System Settings sticks.
    static let loginItemSet = "loginItemSet"

    static func register() {
        UserDefaults.standard.register(defaults: [
            bottleML: 750,
            profile: Profile.men.rawValue,
            customGoalML: 2500,
            active: false,
            wakeMinutes: 7 * 60,
            sleepMinutes: 22 * 60,
            reminders: true,
            dryspell: true,
            respectCalls: true,
            onScreen: true,
            sounds: true,
            lockMinutes: 15,
            graceMinutes: 10,
            corner: Corner.bottomRight.rawValue,
            showInDock: true,
        ])
    }
}

/// Which side of the screen the bottle starts on, until you drag it somewhere else.
enum Corner: String, CaseIterable, Identifiable {
    case bottomLeft, bottomRight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bottomLeft: "Left side"
        case .bottomRight: "Right side"
        }
    }
}

/// Where the daily goal comes from. Men and women start from different amounts; anyone can set their own.
enum Profile: String, CaseIterable, Identifiable {
    case men, women, custom

    var id: String { rawValue }

    /// Drinking water a day, before the extra for exercise or heat.
    var baseML: Int? {
        switch self {
        case .men: 3000
        case .women: 2200
        case .custom: nil
        }
    }

    var title: String {
        switch self {
        case .men: "Men"
        case .women: "Women"
        case .custom: "My own"
        }
    }
}

/// One bottle to finish between `start` and `end`.
struct Slot: Identifiable, Equatable {
    let index: Int
    let amount: Int
    let start: Date
    let end: Date

    var id: Int { index }
    var number: Int { index + 1 }
    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// A day of drinking: the goal split into bottles, each given time in proportion to how much it holds.
struct Plan: Equatable {
    static let activeExtraML = 500
    static let quietBeforeBed = 60

    var bottleML: Int
    var goalML: Int
    var wakeMinutes: Int
    var sleepMinutes: Int

    var bottleCount: Int { max(1, Int((Double(goalML) / Double(bottleML)).rounded(.up))) }
    /// The last bottle only needs filling as far as the goal requires.
    var lastAmount: Int { goalML - (bottleCount - 1) * bottleML }
    var finishMinutes: Int { max(wakeMinutes + 60, sleepMinutes - Self.quietBeforeBed) }
    var drinkingMinutes: Int { finishMinutes - wakeMinutes }
    /// Time to finish one full bottle.
    var minutesPerBottle: Double { Double(drinkingMinutes) * Double(bottleML) / Double(goalML) }

    func slots(on day: Date, calendar: Calendar = .current) -> [Slot] {
        let midnight = calendar.startOfDay(for: day)
        let minutesPerML = Double(drinkingMinutes) / Double(goalML)
        var cursor = Double(wakeMinutes)
        return (0..<bottleCount).map { index in
            let amount = index == bottleCount - 1 ? lastAmount : bottleML
            let start = cursor
            cursor += Double(amount) * minutesPerML
            return Slot(index: index, amount: amount,
                        start: midnight.addingTimeInterval(start * 60),
                        end: midnight.addingTimeInterval(cursor * 60))
        }
    }

    static func current(_ defaults: UserDefaults = .standard) -> Plan {
        let profile = Profile(rawValue: defaults.string(forKey: Prefs.profile) ?? "") ?? .men
        let base = profile.baseML ?? defaults.integer(forKey: Prefs.customGoalML)
        let goal = base + (defaults.bool(forKey: Prefs.active) ? activeExtraML : 0)
        let wake = defaults.integer(forKey: Prefs.wakeMinutes)
        return Plan(bottleML: max(200, defaults.integer(forKey: Prefs.bottleML)),
                    goalML: max(500, goal),
                    wakeMinutes: wake,
                    sleepMinutes: max(wake + 120, defaults.integer(forKey: Prefs.sleepMinutes)))
    }
}

enum Fmt {
    static func liters(_ ml: Int) -> String {
        ml % 100 == 0 ? String(format: "%.1f L", Double(ml) / 1000) : String(format: "%.2f L", Double(ml) / 1000)
    }

    static func ml(_ value: Int) -> String { "\(value) ml" }

    static func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

    static func clock(_ minutes: Int) -> String {
        time(Calendar.current.startOfDay(for: .now).addingTimeInterval(Double(minutes) * 60))
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    static func countdown(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
