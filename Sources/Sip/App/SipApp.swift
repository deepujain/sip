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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.start()
        desk = DeskController(model: model)
        nudges = NudgeController(model: model)
        lock = LockController(model: model)
        if !UserDefaults.standard.bool(forKey: Prefs.hasOnboarded) {
            showWelcome()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSApp.presentationOptions = []
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
