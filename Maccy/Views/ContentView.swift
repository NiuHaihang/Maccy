import Defaults
import SwiftData
import SwiftUI

struct ContentView: View {
  @State private var appState = AppState.shared
  @State private var modifierFlags = ModifierFlags()
  @State private var scenePhase: ScenePhase = .background

  @FocusState private var searchFocused: Bool

  var body: some View {
    ZStack {
      if #available(macOS 26.0, *) {
        GlassEffectView()
      } else {
        VisualEffectView()
          .overlay(
             Defaults[.popupPosition] == .bottom ? 
             Color(NSColor.windowBackgroundColor).opacity(0.4) : nil
          )
      }
      
      // Solid-ish background fill for the entire panel
      Color(NSColor.windowBackgroundColor)
        .opacity(Defaults[.popupPosition] == .bottom ? 0.7 : 0)
        .ignoresSafeArea()
      
      // Top accent line for the panel
      if Defaults[.popupPosition] == .bottom {
        VStack {
          LinearGradient(
            colors: [.accentColor.opacity(0.2), .clear],
            startPoint: .top,
            endPoint: .bottom
          )
          .frame(height: 80)
          Spacer()
        }
      }

      VStack(alignment: .leading, spacing: 0) {
        KeyHandlingView(searchQuery: $appState.history.searchQuery, searchFocused: $searchFocused) {
          if Defaults[.popupPosition] == .bottom {
            VStack(alignment: .leading, spacing: 0) {
              HeaderView(
                searchFocused: $searchFocused,
                searchQuery: $appState.history.searchQuery
              )
              .background(Color.primary.opacity(0.05))

              HistoryListView(
                searchQuery: $appState.history.searchQuery,
                searchFocused: $searchFocused
              )
            }
          } else {
            HeaderView(
              searchFocused: $searchFocused,
              searchQuery: $appState.history.searchQuery
            )

            HistoryListView(
              searchQuery: $appState.history.searchQuery,
              searchFocused: $searchFocused
            )

            FooterView(footer: appState.footer)
          }
        }
      }
      .animation(.default.speed(3), value: appState.history.items)
      .animation(.easeInOut(duration: 0.2), value: appState.searchVisible)
      .padding(.vertical, Defaults[.popupPosition] == .bottom ? 0 : Popup.verticalPadding)
      .padding(.horizontal, Defaults[.popupPosition] == .bottom ? 0 : Popup.horizontalPadding)
      .onAppear {
        searchFocused = true
        // Force the layout to update immediately on appear
        appState.popup.updateLayout()
      }
      .onMouseMove {
        appState.isKeyboardNavigating = false
      }
      .task {
        try? await appState.history.load()
      }
    }
    .environment(appState)
    .environment(modifierFlags)
    .environment(\.scenePhase, scenePhase)
    // FloatingPanel is not a scene, so let's implement custom scenePhase..
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) {
      if let window = $0.object as? NSWindow,
         let bundleIdentifier = Bundle.main.bundleIdentifier,
         window.identifier == NSUserInterfaceItemIdentifier(bundleIdentifier) {
        scenePhase = .active
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) {
      if let window = $0.object as? NSWindow,
         let bundleIdentifier = Bundle.main.bundleIdentifier,
         window.identifier == NSUserInterfaceItemIdentifier(bundleIdentifier) {
        scenePhase = .background
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSPopover.willShowNotification)) {
      if let popover = $0.object as? NSPopover {
        // Prevent NSPopover from showing close animation when
        // quickly toggling FloatingPanel while popover is visible.
        popover.animates = false
        // Prevent NSPopover from becoming first responder.
        popover.behavior = .semitransient
      }
    }
  }
}

#Preview {
  ContentView()
    .environment(\.locale, .init(identifier: "en"))
    .modelContainer(Storage.shared.container)
}
