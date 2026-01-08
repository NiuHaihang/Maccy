import Defaults
import SwiftUI

struct HeaderView: View {
  @FocusState.Binding var searchFocused: Bool
  @Binding var searchQuery: String

  @Environment(AppState.self) private var appState
  @Environment(\.scenePhase) private var scenePhase

  @Default(.showTitle) private var showTitle

  var body: some View {
    HStack(spacing: 15) {
      Spacer()

      // Search Field (Shortened and Centered)
      SearchFieldView(placeholder: "search_placeholder", query: $searchQuery)
        .focused($searchFocused)
        .frame(width: 200)
        .onChange(of: scenePhase) {
          if scenePhase == .background && !searchQuery.isEmpty {
            searchQuery = ""
          }
        }

      // Filter Chips
      HStack(spacing: 8) {
        ForEach(History.Filter.allCases, id: \.self) { filterOption in
          Button {
            appState.history.filter = filterOption
          } label: {
            let filterColor: Color = switch filterOption {
              case .all: Color(red: 0.96, green: 0.61, blue: 0.82) // Pink
              case .text: Color(red: 0.44, green: 0.86, blue: 0.58) // Green
              case .images: Color(red: 0.98, green: 0.84, blue: 0.53) // Yellow
              case .files: Color(red: 0.75, green: 0.85, blue: 0.98) // Blue
              case .pinned: Color(red: 0.81, green: 0.73, blue: 0.98) // Purple
            }
            
            Text(filterOption.description)
              .font(.system(size: 11, weight: .medium))
              .padding(.horizontal, 10)
              .padding(.vertical, 4)
              .background(appState.history.filter == filterOption ? filterColor : Color.primary.opacity(0.1))
              .foregroundStyle(appState.history.filter == filterOption ? .black.opacity(0.8) : .primary)
              .clipShape(.capsule)
          }
          .buttonStyle(.plain)
        }
      }

      Spacer()

      // Right-aligned Actions
      HStack(spacing: 12) {
        Button {
          appState.history.clear()
        } label: {
          Image(systemName: "trash")
            .font(.system(size: 14))
        }
        .buttonStyle(.plain)
        .help("clear_tooltip")

        Button {
          appState.openPreferences()
        } label: {
          Image(systemName: "gearshape")
            .font(.system(size: 14))
        }
        .buttonStyle(.plain)
        .help("preferences")

        Button {
          appState.openAbout()
        } label: {
          Image(systemName: "info.circle")
            .font(.system(size: 14))
        }
        .buttonStyle(.plain)
        .help("about_tooltip")
      }
      .foregroundStyle(.secondary)
    }
    .frame(height: 50)
    .padding(.horizontal, 20)
    .background {
      GeometryReader { geo in
        Color.clear
          .task(id: geo.size.height) {
            appState.popup.headerHeight = geo.size.height
          }
      }
    }
  }
}
