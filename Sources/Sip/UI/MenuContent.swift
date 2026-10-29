import SwiftUI

/// The menu bar panel: today's bottles, the plan, quick switches, and the way to everything else.
struct MenuContent: View {
    @Bindable var model: WaterModel
    let showWelcome: () -> Void
    let showBenefits: () -> Void
    var showAbout: () -> Void = {}
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 10) {
                today
                plan
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 12)

            Label(model.statusLine, systemImage: model.statusSymbol)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 10)

            switches
                .padding(.horizontal, 12)
                .padding(.top, 12)

            Divider().padding(.top, 12)
            footer
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .frame(width: 344)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            AppIconBadge()
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "Sip")
                    .font(.system(.headline, design: .rounded))
                Text(model.headline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
            Text(Fmt.liters(model.drankML) + " / " + Fmt.liters(model.plan.goalML))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
    }

    // MARK: Today

    private var today: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(title: "Today", trailing: "\(model.doneCount) of \(model.plan.bottleCount) done")
            let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: min(4, max(3, model.slots.count)))
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(model.slots) { slot in
                    BottleTile(model: model, slot: slot)
                }
            }
        }
    }

    // MARK: Plan

    private var plan: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(title: "Plan", trailing: nil)
            HStack(spacing: 6) {
                PlanTile(symbol: "waterbottle", title: "Bottle", value: Fmt.ml(model.plan.bottleML)) { settings() }
                PlanTile(symbol: "target", title: "Goal", value: Fmt.liters(model.plan.goalML)) { settings() }
                PlanTile(symbol: "sun.max", title: "Day", value: "\(short(model.plan.wakeMinutes))–\(short(model.plan.sleepMinutes))") { settings() }
                PlanTile(symbol: "flame", title: "Streak", value: model.streak == 1 ? "1 day" : "\(model.streak) days", action: nil)
            }
        }
    }

    private func short(_ minutes: Int) -> String {
        let hour = (minutes / 60) % 24, minute = minutes % 60
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        return minute == 0 ? "\(twelve)" : "\(twelve):\(String(format: "%02d", minute))"
    }

    // MARK: Switches

    private var switches: some View {
        HStack(spacing: 0) {
            QuickSwitch(symbol: "waterbottle.fill", title: "On Screen", isOn: $model.onScreen,
                        help: "Keep your bottle in the corner of the screen.")
            QuickSwitch(symbol: model.reminders ? "bell.fill" : "bell.slash.fill", title: "Reminders", isOn: $model.reminders,
                        help: "A nudge halfway through each bottle, and a check when it's due.")
            QuickSwitch(symbol: "lock.fill", title: "Dry Spell", isOn: $model.dryspell,
                        help: "Lock the screen for \(model.lockMinutes) minutes if a bottle is still not empty \(model.graceMinutes) minutes after it's due.")
            QuickSwitch(symbol: "video.fill", title: "Calls OK", isOn: $model.respectCalls,
                        help: "Never lock while the camera or microphone is in use.")
            QuickSwitch(symbol: model.sounds ? "speaker.wave.2.fill" : "speaker.slash.fill", title: "Sounds", isOn: $model.sounds,
                        help: "A pour when you finish a bottle, a chime when one is due.")
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 2) {
            FooterButton(symbol: "checkmark.circle", title: "Bottle’s Empty") {
                model.finishBottle()
            }
            .keyboardShortcut(.return)
            .disabled(model.current == nil)
            FooterButton(symbol: "arrow.uturn.backward", title: "Undo Last Bottle") {
                model.undoLast()
            }
            .keyboardShortcut("z")
            .disabled(model.finishes.isEmpty)

            Spacer()

            FooterButton(symbol: "heart.text.square", title: "Why Water?") {
                closeMenu()
                showBenefits()
            }
            FooterButton(symbol: "sparkles", title: "Set Up Your Bottle") {
                closeMenu()
                showWelcome()
            }
            FooterButton(symbol: "info.circle", title: "About Sip") {
                closeMenu()
                showAbout()
            }
            FooterButton(symbol: "gearshape", title: "Settings") { settings() }
                .keyboardShortcut(",")
            FooterButton(symbol: "power", title: "Quit Sip") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    private func settings() {
        closeMenu()
        NSApp.activate()
        openSettings()
    }

    private func closeMenu() {
        NSApp.keyWindow?.close()
    }
}

struct AppIconBadge: View {
    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: geo.size.width * 0.225, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.55, green: 0.85, blue: 1), Color(red: 0.12, green: 0.42, blue: 0.95)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay {
                    BottleView(level: 0.62, animated: false)
                        .frame(height: geo.size.height * 0.78)
                }
        }
    }
}

private struct SectionTitle: View {
    let title: String
    let trailing: String?

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.tertiary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(.tertiary)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 4)
    }
}

/// One bottle of the day: finished, in progress, or still to come.
private struct BottleTile: View {
    let model: WaterModel
    let slot: Slot

    private var isCurrent: Bool { slot.index == model.doneCount }
    private var isDone: Bool { slot.index < model.doneCount }
    private var late: Bool { isCurrent && (model.phase == .due || model.phase == .overdue) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top) {
                BottleView(level: model.level(of: slot), animated: isCurrent, warning: late)
                    .frame(height: 38)
                    .opacity(isDone || isCurrent ? 1 : 0.55)
                Spacer(minLength: 0)
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle.fill")
                    .font(.system(size: isDone ? 11 : 7))
                    .foregroundStyle(isDone ? AnyShapeStyle(Color.green) : late ? AnyShapeStyle(Color.orange)
                                     : isCurrent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Bottle \(slot.number)")
                    .font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(late ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(isCurrent ? 0.95 : 0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            if isCurrent {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(late ? Color.orange.opacity(0.6) : Color.accentColor.opacity(0.45), lineWidth: 1)
            }
        }
        .help(Text(help))
        .contextMenu {
            if isCurrent { Button("Bottle’s Empty") { model.finishBottle() } }
            if isDone, slot.index == model.doneCount - 1 { Button("Undo") { model.undoLast() } }
        }
    }

    private var detail: String {
        if isDone {
            let at = model.finishes.indices.contains(slot.index) ? model.finishes[slot.index] : slot.end
            return Fmt.time(at)
        }
        if isCurrent {
            switch model.phase {
            case .due, .overdue: return "Due \(Fmt.time(slot.end))"
            case .ahead, .beforeDay: return "From \(Fmt.time(slot.start))"
            default: return "By \(Fmt.time(slot.end))"
            }
        }
        return "By \(Fmt.time(slot.end))"
    }

    private var help: String {
        let fill = slot.amount < model.plan.bottleML ? "Fill to \(Fmt.ml(slot.amount)). " : ""
        return "\(fill)Drink between \(Fmt.time(slot.start)) and \(Fmt.time(slot.end))."
    }
}

private struct PlanTile: View {
    let symbol: String
    let title: String
    let value: String
    let action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                    if action != nil {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(value)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}

/// A round Control Center–style switch.
private struct QuickSwitch: View {
    let symbol: String
    let title: LocalizedStringKey
    @Binding var isOn: Bool
    let help: String

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.3, bounce: 0.4)) { isOn.toggle() }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isOn ? Color.white : Color.primary.opacity(0.75))
                    .frame(width: 34, height: 34)
                    .background(isOn ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.quaternary), in: Circle())
                    .contentTransition(.symbolEffect(.replace))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text(help))
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(isOn ? "On" : "Off"))
    }
}

private struct FooterButton: View {
    let symbol: String
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 30, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(FooterButtonStyle())
        .help(Text(title))
        .accessibilityLabel(Text(title))
    }
}

private struct FooterButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Hovering { hovering in
            configuration.label
                .foregroundStyle(.secondary)
                .opacity(isEnabled ? 1 : 0.4)
                .background(.primary.opacity(configuration.isPressed ? 0.14 : hovering && isEnabled ? 0.07 : 0),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}

struct Hovering<Content: View>: View {
    @ViewBuilder let content: (Bool) -> Content
    private let hoverState = State(initialValue: false)

    var body: some View {
        content(hoverState.wrappedValue)
            .onHover { hoverState.wrappedValue = $0 }
    }
}
