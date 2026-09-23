import SwiftUI
import AppKit
import PersonalResearchAgentCore

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settingsWindowController: NSWindowController?
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Enforce accessory activation policy so app doesn't show an icon in the macOS Dock
        NSApp.setActivationPolicy(.accessory)
        
        // Start background scheduling, wake observation, and notifications
        Task { @MainActor in
            RunCoordinator.shared.start()
        }
    }
    
    @MainActor
    public func openSettingsWindow() {
        if let existing = settingsWindowController, let window = existing.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)
        
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Personal Research Agent Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.center()
        window.isReleasedWhenClosed = false
        
        let controller = NSWindowController(window: window)
        self.settingsWindowController = controller
        
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct PersonalResearchAgentApp: App {
    @StateObject private var appState = AppState.shared
    @StateObject private var settings = SettingsStore.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .onChange(of: appState.isShowingSettings) { _, newValue in
                    if newValue {
                        appDelegate.openSettingsWindow()
                        appState.isShowingSettings = false
                    }
                }
        } label: {
            Image(systemName: appState.status.iconName)
        }
        .menuBarExtraStyle(.window)
    }
}
