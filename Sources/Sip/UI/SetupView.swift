import SwiftUI

/// Bottle, goal, and day: everything the plan is made from, with the resulting schedule underneath.
struct SetupFields: View {
    @AppStorage(Prefs.bottleML) private var bottleML = 750
    @AppStorage(Prefs.profile) private var profile = Profile.men.rawValue
    @AppStorage(Prefs.customGoalML) private var customGoal = 2500
    @AppStorage(Prefs.active) private var active = false
    @AppStorage(Prefs.wakeMinutes) private var wake = 7 * 60
    @AppStorage(Prefs.sleepMinutes) private var sleep = 22 * 60

    static let bottleSizes = [500, 600, 750, 1000]

    private var plan: Plan { Plan.current() }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("Your bottle", note: "Pick the size printed on your bottle, or set your own.") {
                HStack(spacing: 8) {
                    ForEach(Self.bottleSizes, id: \.self) { size in
                        Chip(selected: bottleML == size) { bottleML = size } label: {
                            VStack(spacing: 6) {
                                BottleView(level: 0.7, animated: false)
                                    .frame(height: 22 + CGFloat(size) / 1000 * 26)
                                    .frame(height: 50, alignment: .bottom)
                                Text(Fmt.ml(size)).font(.system(size: 12, weight: .semibold, design: .rounded))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    Chip(selected: !Self.bottleSizes.contains(bottleML)) {
                        if Self.bottleSizes.contains(bottleML) { bottleML = 800 }
                    } label: {
                        VStack(spacing: 6) {
                            MiniStepper(value: $bottleML, range: 200...2000, step: 50, label: "\(bottleML)")
                                .frame(height: 50)
                            Text("Custom").font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }

            section("Daily water", note: "Drinks only. US guidance is about 3.7 L of total water a day for men and 2.7 L for women, and food gives about a fifth of it.") {
                HStack(spacing: 8) {
                    ForEach(Profile.allCases) { option in
                        Chip(selected: profile == option.rawValue) { profile = option.rawValue } label: {
                            VStack(spacing: 2) {
                                Text(option.title).font(.system(size: 13, weight: .semibold, design: .rounded))
                                if let base = option.baseML {
                                    Text(Fmt.liters(base)).font(.system(size: 11)).foregroundStyle(.secondary)
                                } else {
                                    MiniStepper(value: $customGoal, range: 1000...5000, step: 100, label: Fmt.liters(customGoal))
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                Chip(selected: active) { active.toggle() } label: {
                    HStack {
                        Image(systemName: active ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(active ? Color.accentColor : .secondary)
                        Text("I exercise most days or live somewhere hot")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text("+ \(Fmt.ml(Plan.activeExtraML))").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }

            section("Your day", note: "Sip stops an hour before bed, so you sleep through the night.") {
                HStack(spacing: 8) {
                    TimeField(title: "Wake up", symbol: "sunrise", minutes: $wake, range: 4 * 60...12 * 60)
                    TimeField(title: "Bedtime", symbol: "moon", minutes: $sleep, range: 19 * 60...24 * 60)
                }
            }

            PlanPreview(plan: plan)
        }
    }

    private func section<Content: View>(_ title: String, note: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.tertiary)
            content()
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// "4 bottles, one every 3 h 30 min", then each bottle with its finish time.
struct PlanPreview: View {
    let plan: Plan

    var body: some View {
        let slots = plan.slots(on: .now)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(plan.bottleCount) \(plan.bottleCount == 1 ? "bottle" : "bottles") a day")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Text("· one every \(Fmt.duration(plan.minutesPerBottle * 60))")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Fmt.liters(plan.goalML))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(slots) { slot in
                    VStack(spacing: 4) {
                        BottleView(level: Double(slot.amount) / Double(plan.bottleML) * 0.92, animated: false)
                            .frame(height: 40)
                        Text("By \(Fmt.time(slot.end))")
                            .font(.system(size: 10.5, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if slot.amount < plan.bottleML {
                            Text("fill to \(Fmt.ml(slot.amount))")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct Chip<Label: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(selected ? AnyShapeStyle(Color.accentColor.opacity(0.12)) : AnyShapeStyle(.quaternary.opacity(0.5)),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

/// Minus and plus buttons drawn in SwiftUI, so they render anywhere.
private struct MiniStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            round("minus") { value = max(range.lowerBound, value - step) }
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(minWidth: 34)
            round("plus") { value = min(range.upperBound, value + step) }
        }
    }

    private func round(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .frame(width: 16, height: 16)
                .background(.background, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct TimeField: View {
    let title: String
    let symbol: String
    @Binding var minutes: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
                Text(Fmt.clock(minutes)).font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
            }
            Spacer()
            MiniStepper(value: $minutes, range: range, step: 30, label: "")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

struct WelcomeView: View {
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                AppIconBadge().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to Sip")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("Tell Sip about your bottle and your day. It splits your water into bottles with a time to finish each one, and if a bottle is still full past its time, your Mac takes a short water break.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Label("Why it matters: even mild dehydration can dull your focus and bring on headaches.", systemImage: "brain.head.profile")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            SetupFields()
            HStack {
                Text("You can change all of this later in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                PillButton(title: "Start", prominent: true, action: done)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 560)
    }
}

struct SettingsView: View {
    let model: WaterModel
    @AppStorage(Prefs.lockMinutes) private var lockMinutes = 15
    @AppStorage(Prefs.graceMinutes) private var graceMinutes = 10
    @AppStorage(Prefs.corner) private var corner = Corner.bottomLeft.rawValue
    @AppStorage(Prefs.showInDock) private var showInDock = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SetupFields()
            VStack(alignment: .leading, spacing: 8) {
                Text("BOTTLE ON SCREEN")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.tertiary)
                HStack(spacing: 6) {
                    Text("Corner").font(.system(size: 12, weight: .medium)).frame(width: 110, alignment: .leading)
                    ForEach(Corner.allCases) { option in
                        Button {
                            corner = option.rawValue
                        } label: {
                            Text(option.title)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .foregroundStyle(corner == option.rawValue ? Color.white : Color.primary)
                                .background(corner == option.rawValue ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary.opacity(0.6)),
                                            in: Capsule())
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                HStack(spacing: 6) {
                    Text("Dock icon").font(.system(size: 12, weight: .medium)).frame(width: 110, alignment: .leading)
                    ForEach([true, false], id: \.self) { option in
                        Button {
                            showInDock = option
                        } label: {
                            Text(option ? "Show" : "Menu bar only")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .foregroundStyle(showInDock == option ? Color.white : Color.primary)
                                .background(showInDock == option ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary.opacity(0.6)),
                                            in: Capsule())
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("DRY SPELL")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.tertiary)
                choices(title: "Lock for", values: [5, 10, 15, 20], selection: $lockMinutes)
                choices(title: "Grace after due", values: [5, 10, 15, 30], selection: $graceMinutes)
                HStack {
                    Text("Never during calls, when you're away, or in the hour before bed. Hold the bottom of the lock screen for three seconds to get out in an emergency.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    PillButton(title: "Try it for 20 seconds", prominent: false) { model.startLock(preview: true) }
                }
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private func choices(title: String, values: [Int], selection: Binding<Int>) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 12, weight: .medium)).frame(width: 110, alignment: .leading)
            ForEach(values, id: \.self) { value in
                Button {
                    selection.wrappedValue = value
                } label: {
                    Text("\(value) min")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .foregroundStyle(selection.wrappedValue == value ? Color.white : Color.primary)
                        .background(selection.wrappedValue == value ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary.opacity(0.6)),
                                    in: Capsule())
                }
                .buttonStyle(PressableStyle())
            }
        }
    }
}
