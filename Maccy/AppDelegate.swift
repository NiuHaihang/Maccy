import Defaults
import KeyboardShortcuts
import Sparkle
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
  var panel: FloatingPanel<ContentView>!

  @objc
  private lazy var statusItem: NSStatusItem = {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.behavior = .removalAllowed
    statusItem.button?.action = #selector(performStatusItemClick)
    statusItem.button?.image = Defaults[.menuIcon].image
    statusItem.button?.imagePosition = .imageLeft
    statusItem.button?.target = self
    return statusItem
  }()

  private var isStatusItemDisabled: Bool {
    Defaults[.ignoreEvents] || Defaults[.enabledPasteboardTypes].isEmpty
  }

  private var statusItemVisibilityObserver: NSKeyValueObservation?

  func applicationWillFinishLaunching(_ notification: Notification) { // swiftlint:disable:this function_body_length
    #if DEBUG
    if CommandLine.arguments.contains("enable-testing") {
      SPUUpdater(hostBundle: Bundle.main,
                 applicationBundle: Bundle.main,
                 userDriver: SPUStandardUserDriver(hostBundle: Bundle.main, delegate: nil),
                 delegate: nil)
      .automaticallyChecksForUpdates = false
    }
    #endif

    // Bridge FloatingPanel via AppDelegate.
    AppState.shared.appDelegate = self

    Clipboard.shared.onNewCopy { History.shared.add($0) }
    Clipboard.shared.start()

    Task {
      for await _ in Defaults.updates(.clipboardCheckInterval, initial: false) {
        Clipboard.shared.restart()
      }
    }

    statusItemVisibilityObserver = observe(\.statusItem.isVisible, options: .new) { _, change in
      if let newValue = change.newValue, Defaults[.showInStatusBar] != newValue {
        Defaults[.showInStatusBar] = newValue
      }
    }

    Task {
      for await value in Defaults.updates(.showInStatusBar) {
        statusItem.isVisible = value
      }
    }

    Task {
      for await value in Defaults.updates(.menuIcon, initial: false) {
        statusItem.button?.image = value.image
      }
    }

    synchronizeMenuIconText()
    Task {
      for await value in Defaults.updates(.showRecentCopyInMenuBar) {
        if value {
          statusItem.button?.title = AppState.shared.menuIconText
        } else {
          statusItem.button?.title = ""
        }
      }
    }

    Task {
      for await _ in Defaults.updates(.ignoreEvents) {
        statusItem.button?.appearsDisabled = isStatusItemDisabled
      }
    }

    Task {
      for await _ in Defaults.updates(.enabledPasteboardTypes) {
        statusItem.button?.appearsDisabled = isStatusItemDisabled
      }
    }
  }

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    migrateUserDefaults()
    disableUnusedGlobalHotkeys()

    // Force bottom position for this specialized UI if not already set.
    Defaults[.popupPosition] = .bottom

    panel = FloatingPanel(
      contentRect: NSRect(origin: .zero, size: Defaults[.windowSize]),
      identifier: Bundle.main.bundleIdentifier ?? "org.p0deje.Maccy",
      statusBarButton: statusItem.button,
      onClose: { AppState.shared.popup.reset() }
    ) {
      ContentView()
    }

    ActivationHotKeyMonitor.shared.start()
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    panel.toggle(height: AppState.shared.popup.height)
    return true
  }

  func applicationWillTerminate(_ notification: Notification) {
    if Defaults[.clearOnQuit] {
      AppState.shared.history.clear()
    }
  }

  private func migrateUserDefaults() {
    if Defaults[.migrations]["2024-07-01-version-2"] != true {
      // Start 2.x from scratch.
      Defaults.reset(.migrations)

      // Inverse hide* configuration keys.
      Defaults[.showFooter] = !UserDefaults.standard.bool(forKey: "hideFooter")
      Defaults[.showSearch] = !UserDefaults.standard.bool(forKey: "hideSearch")
      Defaults[.showTitle] = !UserDefaults.standard.bool(forKey: "hideTitle")
      UserDefaults.standard.removeObject(forKey: "hideFooter")
      UserDefaults.standard.removeObject(forKey: "hideSearch")
      UserDefaults.standard.removeObject(forKey: "hideTitle")

      Defaults[.migrations]["2024-07-01-version-2"] = true
    }

    // The following defaults are not used in Maccy 2.x
    // and should be removed in 3.x.
    // - LaunchAtLogin__hasMigrated
    // - avoidTakingFocus
    // - saratovSeparator
    // - maxMenuItemLength
    // - maxMenuItems
  }

  @objc
  private func performStatusItemClick() {
    if let event = NSApp.currentEvent {
      let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

      if modifierFlags.contains(.option) {
        Defaults[.ignoreEvents].toggle()

        if modifierFlags.contains(.shift) {
          Defaults[.ignoreOnlyNextEvent] = Defaults[.ignoreEvents]
        }

        return
      }
    }

    panel.toggle(height: AppState.shared.popup.height, at: .bottom)
  }

  private func synchronizeMenuIconText() {
    _ = withObservationTracking {
      AppState.shared.menuIconText
    } onChange: {
      DispatchQueue.main.async {
        if Defaults[.showRecentCopyInMenuBar] {
          self.statusItem.button?.title = AppState.shared.menuIconText
        }
        self.synchronizeMenuIconText()
      }
    }
  }

  private func disableUnusedGlobalHotkeys() {
    let names: [KeyboardShortcuts.Name] = [.delete, .pin]
    KeyboardShortcuts.disable(names)

    NotificationCenter.default.addObserver(
      forName: Notification.Name("KeyboardShortcuts_shortcutByNameDidChange"),
      object: nil,
      queue: nil
    ) { notification in
      if let name = notification.userInfo?["name"] as? KeyboardShortcuts.Name, names.contains(name) {
        KeyboardShortcuts.disable(name)
      }
    }
  }
}

class ActivationHotKeyMonitor {
  static let shared = ActivationHotKeyMonitor()
  
  private var globalMonitor: Any?
  private var lastModifier: NSEvent.ModifierFlags?
  private var lastTapTime: Date?
  private let threshold: TimeInterval = 0.3
  
  func start() {
    guard globalMonitor == nil else { return }
    
    // Global monitor catches events when other apps are focused.
    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
      self?.handleEvent(event)
    }
    
    // We also need a local monitor for when Maccy itself (like the Settings window) is focused.
    NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
      self?.handleEvent(event)
      return event
    }
    
    // Watch for preference changes to sync KeyboardShortcuts
    Task {
      for await shortcut in Defaults.updates(.activationShortcut) {
        if let shortcut = shortcut, case .standard(let s) = shortcut {
          KeyboardShortcuts.setShortcut(s, for: .popup)
        }
      }
    }
  }
  
  private func handleEvent(_ event: NSEvent) {
    if event.type == .flagsChanged {
      handleFlagsChanged(event)
    } else if event.type == .keyDown {
      handleKeyDown(event)
    }
  }

  private func handleKeyDown(_ event: NSEvent) {
    // KeyboardShortcuts handles standard shortcuts globally.
    // We only need to handle them here if they are stored in our custom ActivationShortcut
    // but weren't registered by KeyboardShortcuts.
  }
  
  private func handleFlagsChanged(_ event: NSEvent) {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    
    checkTrigger(Defaults[.activationShortcut], flags: flags) {
      AppState.shared.appDelegate?.panel.toggle(height: AppState.shared.popup.height, at: .bottom)
    }
    
    checkTrigger(Defaults[.pinShortcut], flags: flags) {
      DispatchQueue.main.async {
        if let item = AppState.shared.history.selectedItem {
          AppState.shared.history.togglePin(item)
        }
      }
    }
    
    checkTrigger(Defaults[.deleteShortcut], flags: flags) {
      DispatchQueue.main.async {
        if let item = AppState.shared.history.selectedItem {
          AppState.shared.history.delete(item)
          AppState.shared.highlightNext()
        }
      }
    }
  }

  private func checkTrigger(_ shortcut: ActivationShortcut?, flags: NSEvent.ModifierFlags, action: @escaping () -> Void) {
    guard let shortcut = shortcut else { return }
    
    switch shortcut {
    case .doubleTap(let raw):
      let targetFlag = NSEvent.ModifierFlags(rawValue: raw)
      if flags == targetFlag {
        let now = Date()
        if let last = lastModifier, last == flags, let lastTime = lastTapTime, now.timeIntervalSince(lastTime) < threshold {
          action()
          lastModifier = nil
          lastTapTime = nil
        } else {
          lastModifier = flags
          lastTapTime = now
        }
      } else if flags.isEmpty {
        // Ignored release
      } else {
        lastModifier = nil
      }
      
    case .chord(let raw):
      let targetFlag = NSEvent.ModifierFlags(rawValue: raw)
      if flags == targetFlag {
         action()
      }
      
    case .standard:
      break // Handled by KeyboardShortcuts or keyDown
    }
  }
}
