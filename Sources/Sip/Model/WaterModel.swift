import AppKit
import Observation

enum Nudge: Equatable {
    case halfway(Slot)
    case due(Slot)
}

enum Phase: Equatable {
    case beforeDay, ahead, onPace, due, overdue, done, afterHours
}

/// Today's bottles, the reminders that follow them, and the Dry Spell lock.
@MainActor
@Observable
final class WaterModel {
    private(set) var plan: Plan
    private(set) var now = Date()
    private(set) var finishes: [Date] = []
    private(set) var lockedUntil: Date?
    private(set) var lockStarted: Date?
    private(set) var previewLock = false
    private(set) var nudge: Nudge?
    private(set) var streak = 0
    /// A short reward shown on the bottle right after you finish one.
    private(set) var celebration: String?
    var deskHover = false
    /// Bumped on every settings change so views reading the switches below refresh.
    private var settingsVersion = 0

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var day = ""
    @ObservationIgnored private var halfwayShown = Set<Int>()
    @ObservationIgnored private var dueShown = Set<Int>()
    @ObservationIgnored private(set) var graceUntil: Date?
    @ObservationIgnored private var nudgeExpires: Date?
    @ObservationIgnored private var celebrationExpires: Date?
    @ObservationIgnored let presence = Presence()

    init() {
        Prefs.register()
        plan = Plan.current()
    }

    // MARK: Switches

    var reminders: Bool {
        get { flag(Prefs.reminders) }
        set { setFlag(Prefs.reminders, newValue) }
    }

    var dryspell: Bool {
        get { flag(Prefs.dryspell) }
        set { setFlag(Prefs.dryspell, newValue) }
    }

    var respectCalls: Bool {
        get { flag(Prefs.respectCalls) }
        set { setFlag(Prefs.respectCalls, newValue) }
    }

    var onScreen: Bool {
        get { flag(Prefs.onScreen) }
        set { setFlag(Prefs.onScreen, newValue) }
    }

    var sounds: Bool {
        get { flag(Prefs.sounds) }
        set { setFlag(Prefs.sounds, newValue) }
    }

    var lockMinutes: Int {
        _ = settingsVersion
        return max(1, defaults.integer(forKey: Prefs.lockMinutes))
    }

    var graceMinutes: Int {
        _ = settingsVersion
        return max(1, defaults.integer(forKey: Prefs.graceMinutes))
    }

    private func flag(_ key: String) -> Bool {
        _ = settingsVersion
        return defaults.bool(forKey: key)
    }

    private func setFlag(_ key: String, _ value: Bool) {
        defaults.set(value, forKey: key)
        settingsVersion += 1
    }

    // MARK: Lifecycle

    func start() {
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsChanged() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func settingsChanged() {
        let latest = Plan.current(defaults)
        if latest != plan { plan = latest }
        settingsVersion += 1
    }

    // MARK: Today

    var slots: [Slot] { plan.slots(on: now) }
    var doneCount: Int { min(finishes.count, plan.bottleCount) }
    var current: Slot? { doneCount < slots.count ? slots[doneCount] : nil }
    var drankML: Int { slots.prefix(doneCount).reduce(0) { $0 + $1.amount } }
    var dayStart: Date { minutes(plan.wakeMinutes) }
    var bedtime: Date { minutes(plan.sleepMinutes) }
    var isLocked: Bool { lockedUntil != nil }

    private func minutes(_ value: Int) -> Date {
        Calendar.current.startOfDay(for: now).addingTimeInterval(Double(value) * 60)
    }

    var phase: Phase {
        guard let slot = current else { return .done }
        if now < dayStart { return .beforeDay }
        if now >= bedtime { return .afterHours }
        if now < slot.start { return .ahead }
        if now < slot.end { return .onPace }
        return now < lockAt(slot) ? .due : .overdue
    }

    /// When the Dry Spell starts if this bottle isn't finished.
    func lockAt(_ slot: Slot) -> Date {
        graceUntil ?? slot.end.addingTimeInterval(Double(graceMinutes) * 60)
    }

    /// How full a bottle should look right now: finished ones are empty, the current one drains on schedule.
    func level(of slot: Slot) -> Double {
        if slot.index < doneCount { return 0 }
        if slot.index > doneCount { return 1 }
        guard now > slot.start else { return 1 }
        // Past due, a little is left, so it never looks like a finished bottle.
        return max(0.12, 1 - now.timeIntervalSince(slot.start) / slot.duration)
    }

    var deskLevel: Double {
        guard let slot = current else { return 1 }
        return level(of: slot)
    }

    var headline: String {
        let total = plan.bottleCount
        switch phase {
        case .done: return "All \(total) bottles · \(Fmt.liters(drankML)) today"
        case .beforeDay: return "Your day starts at \(Fmt.time(dayStart))"
        case .afterHours: return "\(doneCount) of \(total) bottles today"
        default:
            guard let slot = current else { return "" }
            return "Bottle \(slot.number) of \(total) · due \(Fmt.time(slot.end))"
        }
    }

    var statusSymbol: String {
        switch phase {
        case .beforeDay: "sunrise"
        case .ahead: "hare"
        case .onPace: "drop"
        case .due: "exclamationmark.circle"
        case .overdue: "lock"
        case .done: "checkmark.seal"
        case .afterHours: "moon.zzz"
        }
    }

    var statusLine: String {
        switch phase {
        case .beforeDay:
            return "Reminders start at \(Fmt.time(dayStart))."
        case .ahead:
            guard let slot = current else { return "" }
            return "Ahead of schedule. Bottle \(slot.number) starts at \(Fmt.time(slot.start))."
        case .onPace:
            guard let slot = current else { return "" }
            let half = slot.start.addingTimeInterval(slot.duration / 2)
            return now < half
                ? "On pace. Aim for half the bottle by \(Fmt.time(half))."
                : "Keep sipping. Finish bottle \(slot.number) by \(Fmt.time(slot.end))."
        case .due:
            guard let slot = current else { return "" }
            return dryspell
                ? "Bottle \(slot.number) is due. Your Mac takes a water break at \(Fmt.time(lockAt(slot)))."
                : "Bottle \(slot.number) is due. Finish it when you can."
        case .overdue:
            guard let slot = current else { return "" }
            return "Bottle \(slot.number) is overdue."
        case .done:
            return "Goal reached. That’s plenty for today."
        case .afterHours:
            return "Quiet until morning, so you sleep through the night."
        }
    }

    /// The fact shown on the lock screen; it stays the same for the whole lock.
    var lockBenefit: Benefit {
        Benefit.pick(at: lockStarted ?? now, bottle: current?.index ?? 0)
    }

    var deskCaption: String {
        if let celebration { return celebration }
        switch phase {
        case .beforeDay: return "Starts at \(Fmt.time(dayStart))"
        case .ahead: return current.map { "Bottle \($0.number) at \(Fmt.time($0.start))" } ?? ""
        case .onPace: return current.map { "Bottle \($0.number) · \(Fmt.duration($0.end.timeIntervalSince(now))) left" } ?? ""
        case .due: return current.map { "Bottle \($0.number) is due" } ?? ""
        case .overdue: return current.map { "Bottle \($0.number) is overdue" } ?? ""
        case .done: return "Goal reached · \(Fmt.liters(drankML))"
        case .afterHours: return "Done for today"
        }
    }

    var menuSymbol: String {
        switch phase {
        case .due, .overdue: "drop.triangle.fill"
        case .beforeDay, .afterHours: "drop"
        default: "drop.fill"
        }
    }

    // MARK: The clock

    func tick() {
        now = Date()
        let key = Self.dayKey(now)
        if key != day {
            day = key
            finishes = history()[key]?.map { Date(timeIntervalSince1970: $0) } ?? []
            halfwayShown = []
            dueShown = []
            graceUntil = nil
            nudge = nil
            streak = computeStreak()
        }
        if let until = lockedUntil, now >= until { endLock(finished: false) }
        if let expires = nudgeExpires, now >= expires { dismissNudge() }
        if let expires = celebrationExpires, now >= expires {
            celebration = nil
            celebrationExpires = nil
        }

        guard reminders, !isLocked, let slot = current, now >= dayStart, now < bedtime else { return }
        if presence.isAway {
            // Time away from the Mac doesn't count against the grace period.
            if let grace = graceUntil { graceUntil = max(grace, now.addingTimeInterval(Double(graceMinutes) * 60)) }
            return
        }

        let half = slot.start.addingTimeInterval(slot.duration / 2)
        if now >= half, now < slot.end, !halfwayShown.contains(slot.index) {
            halfwayShown.insert(slot.index)
            show(.halfway(slot), for: 30)
        }
        if now >= slot.end, !dueShown.contains(slot.index) {
            dueShown.insert(slot.index)
            graceUntil = now.addingTimeInterval(Double(graceMinutes) * 60)
            show(.due(slot), for: nil)
            play("Glass")
        }
        if dryspell, let grace = graceUntil, now >= grace {
            if respectCalls, presence.inCall {
                graceUntil = now.addingTimeInterval(60)
            } else {
                startLock()
            }
        }
    }

    // MARK: Actions

    func finishBottle() {
        if previewLock { return endLock(finished: true) }
        guard let finished = current else { return }
        let at = Date()
        finishes.append(at)
        save()
        celebration = doneCount >= plan.bottleCount
            ? "Goal reached · \(Fmt.liters(drankML)) today"
            : "Bottle \(finished.number) done · \(Benefit.pick(at: at, bottle: finished.index).short)"
        celebrationExpires = at.addingTimeInterval(12)
        graceUntil = nil
        dismissNudge()
        if isLocked { endLock(finished: true) }
        play("Bottle")
        streak = computeStreak()
        now = at
    }

    func undoLast() {
        guard !finishes.isEmpty else { return }
        finishes.removeLast()
        save()
        streak = computeStreak()
    }

    func dismissNudge() {
        nudge = nil
        nudgeExpires = nil
    }

    func startLock(preview: Bool = false) {
        guard !isLocked else { return }
        previewLock = preview
        lockStarted = Date()
        lockedUntil = Date().addingTimeInterval(preview ? 20 : Double(lockMinutes) * 60)
        dismissNudge()
        play("Submarine")
    }

    /// Ends the Dry Spell. If the bottle still isn't finished, it comes back after twice the grace period.
    func endLock(finished: Bool) {
        let wasPreview = previewLock
        lockedUntil = nil
        lockStarted = nil
        previewLock = false
        if !finished, !wasPreview, current != nil {
            graceUntil = Date().addingTimeInterval(Double(graceMinutes) * 120)
        }
    }

    private func show(_ value: Nudge, for seconds: TimeInterval?) {
        nudge = value
        nudgeExpires = seconds.map { now.addingTimeInterval($0) }
    }

    private func play(_ name: String) {
        guard sounds else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    // MARK: History

    private func history() -> [String: [Double]] {
        defaults.dictionary(forKey: Prefs.history) as? [String: [Double]] ?? [:]
    }

    private func save() {
        var all = history()
        all[Self.dayKey(now)] = finishes.map(\.timeIntervalSince1970)
        let keep = Set((0..<60).map { Self.dayKey(Calendar.current.date(byAdding: .day, value: -$0, to: now) ?? now) })
        all = all.filter { keep.contains($0.key) }
        defaults.set(all, forKey: Prefs.history)
    }

    /// Days in a row the goal was met, counting today once it's done.
    private func computeStreak() -> Int {
        let all = history()
        let needed = plan.bottleCount
        var count = doneCount >= needed ? 1 : 0
        for back in 1..<60 {
            guard let date = Calendar.current.date(byAdding: .day, value: -back, to: now),
                  (all[Self.dayKey(date)]?.count ?? 0) >= needed else { break }
            count += 1
        }
        return count
    }

    static func dayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    #if DEBUG
    func stage(now: Date, done: Int, nudge: Nudge? = nil, locked: Bool = false, streak: Int = 6, celebration: String? = nil) {
        self.now = now
        self.celebration = celebration
        day = Self.dayKey(now)
        let slots = plan.slots(on: now)
        finishes = slots.prefix(done).map { $0.end.addingTimeInterval(-900) }
        self.nudge = nudge
        self.streak = streak
        lockStarted = locked ? now.addingTimeInterval(-160) : nil
        lockedUntil = locked ? now.addingTimeInterval(Double(lockMinutes) * 60 - 160) : nil
    }
    #endif
}
