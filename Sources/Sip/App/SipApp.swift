import AppKit
import SwiftUI

@main
struct SipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--render-icon"), arguments.indices.contains(flag + 1) {
            do {
                try AppIconRenderer.writeIconset(to: URL(fileURLWithPath: arguments[flag + 1], isDirectory: true))
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("Icon rendering failed: \(error)\n".utf8))
                exit(1)
            }
        }
        #if DEBUG
        if arguments.contains("--motion") {
            let sensors = MotionSensors()
            sensors.start()
            for _ in 0..<6 {
                RunLoop.main.run(until: Date().addingTimeInterval(0.5))
                print(String(format: "tilt %.3f rad  agitation %.2f", Slosh.shared.tilt, Slosh.shared.agitation))
            }
            sensors.stop()
            exit(0)
        }
        if let flag = arguments.firstIndex(of: "--snapshots"), arguments.indices.contains(flag + 1) {
            do {
                try Snapshots.render(to: URL(fileURLWithPath: arguments[flag + 1], isDirectory: true))
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("Snapshots failed: \(error)\n".utf8))
                exit(1)
            }
        }
        #endif
        // Without a saved position macOS adds the icon at the far left of the
        // status items, which is behind the notch on MacBooks with a full menu bar.
        let position = "NSStatusItem Preferred Position Item-0"
        if UserDefaults.standard.object(forKey: position) == nil {
            UserDefaults.standard.set(250, forKey: position)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: appDelegate.model, showWelcome: appDelegate.showWelcome, showBenefits: appDelegate.showBenefits)
        } label: {
            Image(systemName: appDelegate.model.menuSymbol)
                .accessibilityLabel(Text("Sip"))
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: appDelegate.model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = WaterModel()
    private var desk: DeskController?
    private var nudges: NudgeController?
    private var lock: LockController?
    private var welcomeWindow: NSWindow?
    private var benefitsWindow: NSWindow?

    private var todayWindow: NSWindow?
    private let motion = MotionSensors()

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyDockPolicy()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyDockPolicy() }
        }
        model.start()
        desk = DeskController(model: model)
        nudges = NudgeController(model: model)
        lock = LockController(model: model)
        motion.start()
        if !UserDefaults.standard.bool(forKey: Prefs.hasOnboarded) {
            showWelcome()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSApp.presentationOptions = []
        motion.stop()
    }

    /// Clicking the Dock icon opens today's bottles, for when the menu bar is too full to show Sip's drop.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showToday()
        return false
    }

    private func applyDockPolicy() {
        let policy: NSApplication.ActivationPolicy = UserDefaults.standard.bool(forKey: Prefs.showInDock) ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }

    func showToday() {
        if todayWindow == nil {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.title = "Sip"
            window.contentView = NSHostingView(rootView: MenuContent(model: model, showWelcome: { [weak self] in self?.showWelcome() },
                                                                     showBenefits: { [weak self] in self?.showBenefits() })
                .padding(.top, 14))
            window.center()
            todayWindow = window
        }
        NSApp.activate()
        todayWindow?.makeKeyAndOrderFront(nil)
    }

    func showWelcome() {
        if welcomeWindow == nil {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.title = "Welcome to Sip"
            window.contentView = NSHostingView(rootView: WelcomeView { [weak self] in
                UserDefaults.standard.set(true, forKey: Prefs.hasOnboarded)
                self?.model.tick()
                self?.welcomeWindow?.close()
            })
            window.center()
            welcomeWindow = window
        }
        NSApp.activate()
        welcomeWindow?.makeKeyAndOrderFront(nil)
    }

    func showBenefits() {
        if benefitsWindow == nil {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.title = "Why Water?"
            window.contentView = NSHostingView(rootView: BenefitsView())
            window.center()
            benefitsWindow = window
        }
        NSApp.activate()
        benefitsWindow?.makeKeyAndOrderFront(nil)
    }
}
