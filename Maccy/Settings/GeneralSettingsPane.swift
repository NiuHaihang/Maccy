import SwiftUI
import Defaults
import KeyboardShortcuts
import LaunchAtLogin
import Settings

struct GeneralSettingsPane: View {
  private let notificationsURL = URL(
    string: "x-apple.systempreferences:com.apple.preference.notifications?id=\(Bundle.main.bundleIdentifier ?? "")"
  )

  @Default(.searchMode) private var searchMode
  @Default(.activationShortcut) private var activationShortcut
  @Default(.pinShortcut) private var pinShortcut
  @Default(.deleteShortcut) private var deleteShortcut

  @State private var copyModifier = HistoryItemAction.copy.modifierFlags.description
  @State private var pasteModifier = HistoryItemAction.paste.modifierFlags.description
  @State private var pasteWithoutFormatting = HistoryItemAction.pasteWithoutFormatting.modifierFlags.description

  @State private var updater = SoftwareUpdater()

  var body: some View {
    Settings.Container(contentWidth: 450) {
      Settings.Section(title: "", bottomDivider: true) {
        LaunchAtLogin.Toggle {
          Text("LaunchAtLogin", tableName: "GeneralSettings")
        }
        Toggle(isOn: $updater.automaticallyChecksForUpdates) {
          Text("CheckForUpdates", tableName: "GeneralSettings")
        }
        Button(
          action: { updater.checkForUpdates() },
          label: { Text("CheckNow", tableName: "GeneralSettings") }
        )
      }

      Settings.Section(label: { Text("Open", tableName: "GeneralSettings") }) {
        ActivationShortcutRecorder(shortcut: _activationShortcut.projectedValue)
          .help(Text("OpenTooltip", tableName: "GeneralSettings"))
      }

      Settings.Section(label: { Text("Pin", tableName: "GeneralSettings") }) {
        ActivationShortcutRecorder(shortcut: _pinShortcut.projectedValue)
          .help(Text("PinTooltip", tableName: "GeneralSettings"))
      }
      Settings.Section(
        bottomDivider: true,
        label: { Text("Delete", tableName: "GeneralSettings") }
      ) {
        ActivationShortcutRecorder(shortcut: _deleteShortcut.projectedValue)
          .help(Text("DeleteTooltip", tableName: "GeneralSettings"))
      }

      Settings.Section(
        bottomDivider: true,
        label: { Text("Search", tableName: "GeneralSettings") }
      ) {
        Picker("", selection: $searchMode) {
          ForEach(Search.Mode.allCases) { mode in
            Text(mode.description)
          }
        }
        .labelsHidden()
        .frame(width: 180, alignment: .leading)
      }

      Settings.Section(
        bottomDivider: true,
        label: { Text("Behavior", tableName: "GeneralSettings") }
      ) {
        Defaults.Toggle(key: .pasteByDefault) {
          Text("PasteAutomatically", tableName: "GeneralSettings")
        }
        .onChange(refreshModifiers)
        .fixedSize()

        Defaults.Toggle(key: .removeFormattingByDefault) {
          Text("PasteWithoutFormatting", tableName: "GeneralSettings")
        }
        .onChange(refreshModifiers)
        .fixedSize()

        Text(String(
          format: NSLocalizedString("Modifiers", tableName: "GeneralSettings", comment: ""),
          copyModifier, pasteModifier, pasteWithoutFormatting
        ))
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.gray)
        .controlSize(.small)
      }

      Settings.Section(title: "") {
        if let notificationsURL = notificationsURL {
          Link(destination: notificationsURL, label: {
            Text("NotificationsAndSounds", tableName: "GeneralSettings")
          })
        }
      }
    }
  }

  private func refreshModifiers(_ sender: Sendable) {
    copyModifier = HistoryItemAction.copy.modifierFlags.description
    pasteModifier = HistoryItemAction.paste.modifierFlags.description
    pasteWithoutFormatting = HistoryItemAction.pasteWithoutFormatting.modifierFlags.description
  }
}

struct ActivationShortcutRecorder: View {
  @Binding var shortcut: ActivationShortcut?
  @State private var isRecording = false
  
  var body: some View {
    HStack(spacing: 4) {
      ZStack(alignment: .leading) {
        if isRecording {
          Text("Press keys...")
            .foregroundStyle(.secondary)
            .italic()
        } else if let shortcut = shortcut {
          Text(shortcut.description)
        } else {
          Text("Click to record")
            .foregroundStyle(.tertiary)
        }
      }
      .font(.system(size: 11, design: .monospaced))
      .padding(.horizontal, 8)
      .frame(minWidth: 150, minHeight: 22, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 4)
          .fill(Color(NSColor.controlBackgroundColor))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 4)
          .stroke(isRecording ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: isRecording ? 1.5 : 1)
      )
      .onTapGesture {
        isRecording.toggle()
      }
      
      if shortcut != nil || isRecording {
        Button(action: {
          shortcut = nil
          isRecording = false
        }) {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
            .font(.system(size: 13))
        }
        .buttonStyle(.plain)
      }
    }
    .background(KeyEventHandlingView(isRecording: $isRecording, onShortcutRecorded: { newShortcut in
      self.shortcut = newShortcut
      self.isRecording = false
    }))
  }
}

struct KeyEventHandlingView: NSViewRepresentable {
  @Binding var isRecording: Bool
  var onShortcutRecorded: (ActivationShortcut) -> Void
  
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    return view
  }
  
  func updateNSView(_ nsView: NSView, context: Context) {
    if isRecording {
      context.coordinator.startMonitoring(onShortcutRecorded: onShortcutRecorded)
    } else {
      context.coordinator.stopMonitoring()
    }
  }
  
  func makeCoordinator() -> Coordinator {
    Coordinator(isRecording: $isRecording)
  }
  
  class Coordinator: NSObject {
    @Binding var isRecording: Bool
    private var localMonitor: Any?
    
    private var lastModifierPressed: NSEvent.ModifierFlags = []
    private var lastModifierReleaseTime: Date = .distantPast
    
    init(isRecording: Binding<Bool>) {
      self._isRecording = isRecording
    }
    
    func startMonitoring(onShortcutRecorded: @escaping (ActivationShortcut) -> Void) {
      stopMonitoring()
      
      localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
        guard let self = self else { return event }
        
        if event.type == .keyDown {
          if event.keyCode == 53 { // Escape
            self.isRecording = false
            return nil
          }
          
          let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
          let key = KeyboardShortcuts.Key(rawValue: Int(event.keyCode))
          let shortcut = KeyboardShortcuts.Shortcut(key, modifiers: modifiers)
          onShortcutRecorded(.standard(shortcut))
          return nil
        } else if event.type == .flagsChanged {
          let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
          
          if flags.isEmpty {
            let releasedModifier = self.lastModifierPressed
            let now = Date()
            
            if releasedModifier.rawValue.nonzeroBitCount == 1 {
              if now.timeIntervalSince(self.lastModifierReleaseTime) < 0.3 {
                onShortcutRecorded(.doubleTap(releasedModifier.rawValue))
              } else {
                self.lastModifierReleaseTime = now
              }
            } else if releasedModifier.rawValue.nonzeroBitCount > 1 {
              onShortcutRecorded(.chord(releasedModifier.rawValue))
            }
          } else {
            self.lastModifierPressed = flags
          }
          return nil
        }
        return nil
      }
    }
    
    func stopMonitoring() {
      if let monitor = localMonitor {
        NSEvent.removeMonitor(monitor)
        localMonitor = nil
      }
    }
  }
}

#Preview {
  GeneralSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
}
